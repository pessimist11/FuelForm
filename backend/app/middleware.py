"""Bound and authenticate uploads before parsing; log only safe request metadata."""
import asyncio
import logging
import secrets
import time
from contextlib import nullcontext
from uuid import uuid4

from fastapi.responses import JSONResponse

from .providers import ProviderError

logger = logging.getLogger('uvicorn.error')
AI_PATHS = frozenset({'/v1/analyze', '/v1/plans/draft'})
LOG_PATHS = AI_PATHS | {'/health', '/v1/status', '/v1/foods', '/v1/exercises'}


class RequestGuard:
    def __init__(self, app, settings, runtime):
        self.app = app
        self.settings = settings
        self.runtime = runtime

    def authenticated(self, headers):
        values = [value for name, value in headers if name.lower() == b'authorization']
        if len(values) != 1:
            return False
        scheme, separator, token = values[0].partition(b' ')
        expected = self.settings.service_token.get_secret_value().encode()
        return bool(expected and separator and scheme.lower() == b'bearer'
                    and secrets.compare_digest(token, expected))

    async def bounded_body(self, scope, receive):
        maximum = self.settings.max_image_bytes + 256 * 1024 if scope['path'] == '/v1/analyze' else 64 * 1024
        lengths = [value for name, value in scope.get('headers', []) if name.lower() == b'content-length']
        if lengths:
            if len(lengths) != 1 or not lengths[0].isdigit() or len(lengths[0]) > 20:
                raise ProviderError('invalid_request', '请求长度格式无效', 400)
            if int(lengths[0]) > maximum:
                raise ProviderError('image_too_large' if scope['path'] == '/v1/analyze' else 'request_too_large',
                                    '请求超过大小限制', 413)
        body = bytearray()
        try:
            async with asyncio.timeout(self.settings.request_body_timeout_seconds):
                while True:
                    message = await receive()
                    if message['type'] == 'http.disconnect':
                        return None
                    chunk = message.get('body', b'')
                    if len(body) + len(chunk) > maximum:
                        raise ProviderError('image_too_large' if scope['path'] == '/v1/analyze' else 'request_too_large',
                                            '请求超过大小限制', 413)
                    body.extend(chunk)
                    if not message.get('more_body', False):
                        return bytes(body)
        except TimeoutError:
            raise ProviderError('upload_timeout', '上传超时，照片仍保留在手机，可稍后重试', 408) from None

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        request_id = uuid4().hex
        started = time.monotonic()
        status = 500
        response_started = False

        async def guarded_send(message):
            nonlocal status, response_started
            if message['type'] == 'http.response.start':
                response_started = True
                status = message['status']
                message = dict(message)
                headers = [(key, value) for key, value in message.get('headers', [])
                           if key.lower() not in {b'x-request-id', b'cache-control'}]
                message['headers'] = headers + [(b'x-request-id', request_id.encode()), (b'cache-control', b'no-store')]
            await send(message)

        async def failure(error):
            response = JSONResponse(status_code=error.status, headers=error.headers,
                                    content={'error': {'code': error.code, 'message': error.message}})
            await response(scope, receive, guarded_send)

        try:
            if scope['path'].startswith('/v1/') and not self.authenticated(scope.get('headers', [])):
                return await failure(ProviderError('unauthorized', '服务访问凭据无效', 401,
                                                   {'WWW-Authenticate': 'Bearer'}))
            admission = self.runtime.admit() if scope['path'] in AI_PATHS and scope['method'] == 'POST' else nullcontext()
            async with admission:
                body = None
                if scope['method'] in {'POST', 'PUT', 'PATCH'}:
                    body = await self.bounded_body(scope, receive)
                    if body is None:
                        status = 499
                        return
                delivered = False

                async def replay():
                    nonlocal delivered
                    if body is not None and not delivered:
                        delivered = True
                        return {'type': 'http.request', 'body': body, 'more_body': False}
                    return await receive()

                await self.app(scope, replay, guarded_send)
        except ProviderError as error:
            if response_started:
                raise
            await failure(error)
        except Exception:
            if response_started:
                raise
            # Never include exception repr, upstream response, or submitted data in logs.
            await failure(ProviderError('internal_error', '服务暂时无法处理请求，请稍后重试', 500))
        finally:
            path = scope['path'] if scope['path'] in LOG_PATHS else 'other'
            logger.info('request_completed request_id=%s route=%s status=%d duration_ms=%d',
                        request_id, path, status, round((time.monotonic() - started) * 1000))
