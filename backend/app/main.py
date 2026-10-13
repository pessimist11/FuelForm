import asyncio
import secrets
import time
from collections import deque
from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, Header, UploadFile, File, Request
from fastapi.responses import JSONResponse
from pydantic import ValidationError
from .config import Settings
from .schemas import PlanRequest, PlanResponse, Analysis
from .providers import ProviderError, MockProvider, OpenAIProvider, DeepSeekProvider, ResponsesProvider, validate_plan
from .images import normalize_image
from .catalog import CATALOG, EXERCISES, match

class BodyLimit:
    def __init__(self, app, max_bytes): self.app = app; self.max_bytes = max_bytes
    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http' or scope['method'] not in ('POST', 'PUT', 'PATCH'):
            return await self.app(scope, receive, send)
        total = 0; chunks = []
        while True:
            message = await receive()
            if message['type'] == 'http.disconnect': return
            total += len(message.get('body', b''))
            if total > self.max_bytes:
                response = JSONResponse(status_code=413, content={'error': {'code': 'image_too_large', 'message': '请求超过大小限制'}})
                return await response(scope, receive, send)
            chunks.append(message.get('body', b''))
            if not message.get('more_body', False): break
        body = b''.join(chunks); delivered = False
        async def replay():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {'type': 'http.request', 'body': body, 'more_body': False}
            return await receive()
        await self.app(scope, replay, send)

def create_app(settings: Settings | None = None, provider_override=None):
    settings = settings or Settings()
    calls = deque()
    @asynccontextmanager
    async def lifespan(app):
        if not settings.service_token.get_secret_value():
            raise RuntimeError('SERVICE_TOKEN is required even in mock mode; run scripts/bootstrap_backend.py')
        yield
    app = FastAPI(title='FuelForm', version='1.0.0', lifespan=lifespan)
    app.add_middleware(BodyLimit, max_bytes=settings.max_image_bytes + 256 * 1024)

    @app.exception_handler(ProviderError)
    async def provider_error(request, exc):
        return JSONResponse(status_code=exc.status, content={'error': {'code': exc.code, 'message': exc.message}})

    async def auth(authorization: str | None = Header(default=None)):
        expected = settings.service_token.get_secret_value()
        actual = (authorization or '').removeprefix('Bearer ')
        if not expected or not secrets.compare_digest(actual.encode(), expected.encode()):
            raise ProviderError('unauthorized', '服务访问凭据无效', 401)

    async def rate_limit():
        now = time.monotonic()
        while calls and calls[0] < now - 60: calls.popleft()
        if len(calls) >= settings.requests_per_minute:
            raise ProviderError('rate_limited', '分析请求过于频繁，请稍后重试', 429)
        calls.append(now)

    def provider(photo=False):
        if provider_override is not None: return provider_override
        if settings.provider == 'mock': return MockProvider()
        cls = DeepSeekProvider if settings.provider == 'deepseek' else OpenAIProvider
        return cls(settings, photo=photo)

    @app.get('/health')
    async def health(): return {'status': 'ok'}

    protected = [Depends(auth)]
    ai_deps = [Depends(auth), Depends(rate_limit)]
    @app.get('/v1/status', dependencies=protected)
    async def status():
        photo_issues = settings.configuration_issues(photo=True)
        plan_issues = settings.configuration_issues()
        return {'mode': settings.provider, 'catalogVersion': CATALOG['version'],
                'photoReady': not photo_issues, 'planReady': not plan_issues,
                'photoModel': settings.ai_configuration(photo=True)[1] if settings.provider != 'mock' else None,
                'planModel': settings.ai_configuration()[1] if settings.provider != 'mock' else None,
                'configurationIssues': list(dict.fromkeys(photo_issues + plan_issues))}
    @app.get('/v1/foods', dependencies=protected)
    async def foods(): return CATALOG
    @app.get('/v1/exercises', dependencies=protected)
    async def exercises(): return EXERCISES

    @app.post('/v1/analyze', response_model=Analysis, dependencies=ai_deps)
    async def analyze(image: UploadFile = File(...)):
        try:
            data = await image.read(settings.max_image_bytes + 1)
        finally:
            await image.close()
        if len(data) > settings.max_image_bytes:
            raise ProviderError('image_too_large', '照片超过大小限制', 413)
        jpeg = await asyncio.to_thread(normalize_image, data)
        engine = provider(photo=True)
        try:
            raw = await engine.recognize(jpeg)
            return match(raw, settings.provider)
        finally:
            if isinstance(engine, ResponsesProvider): await engine.close()

    @app.post('/v1/plans/draft', response_model=PlanResponse, dependencies=ai_deps)
    async def plan(request: PlanRequest):
        engine = provider()
        try:
            draft = validate_plan(await engine.plan(request), request)
            return PlanResponse(mode=settings.provider, draft=draft, warnings=['演示计划：固定规则，不是个性化 AI 结果'] if settings.provider == 'mock' else ['草稿需要用户核对动作与强度，确认后才启用'])
        except ValidationError:
            raise ProviderError('invalid_ai_output', '计划结构校验失败', 422) from None
        finally:
            if isinstance(engine, ResponsesProvider): await engine.close()
    return app

app = create_app()
