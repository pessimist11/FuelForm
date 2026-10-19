import asyncio
import json
import logging
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app import runtime as runtime_module
from app.main import create_app
from app.providers import MockProvider, ProviderError
from app.runtime import BackendRuntime
from test_service import HEADERS, TOKEN, jpeg, request, settings


async def send_asgi(app, messages, *, path='/v1/analyze', headers=None, receive=None):
    pending = list(messages)
    reads = []
    sent = []
    async def incoming():
        reads.append(True)
        if receive is not None:
            return await receive()
        return pending.pop(0)
    async def outgoing(message):
        sent.append(message)
    scope = {'type': 'http', 'asgi': {'version': '3.0'}, 'http_version': '1.1',
             'method': 'POST', 'scheme': 'http', 'path': path, 'raw_path': path.encode(),
             'root_path': '', 'query_string': b'', 'headers': headers or [],
             'client': ('127.0.0.1', 12345), 'server': ('test', 80)}
    await app(scope, incoming, outgoing)
    return reads, sent


AUTH = [(b'authorization', ('Bearer ' + TOKEN).encode())]


def test_invalid_startup_config_error_does_not_print_sensitive_endpoint_input():
    with pytest.raises(ValidationError) as error:
        settings(deepseek_base_url='https://PRIVATE-SECRET@example.com')
    assert 'PRIVATE-SECRET' not in str(error.value)


def test_unauthorized_is_rejected_before_reading_body_or_spending_admission():
    app = create_app(settings())
    reads, messages = asyncio.run(send_asgi(app, [], headers=[(b'content-length', b'999999999')]))
    assert not reads
    assert messages[0]['status'] == 401
    assert app.state.runtime.active == 0 and not app.state.runtime.calls


@pytest.mark.parametrize('authorization', [TOKEN, 'Basic ' + TOKEN, 'Bearer wrong', 'Bearer'])
def test_authorization_requires_bearer_scheme_and_exact_token(authorization):
    response = TestClient(create_app(settings())).get('/v1/status', headers={'Authorization': authorization})
    assert response.status_code == 401
    assert response.headers['www-authenticate'] == 'Bearer'


def test_case_insensitive_bearer_and_duplicate_header_rejection():
    c = TestClient(create_app(settings()))
    assert c.get('/v1/status', headers={'Authorization': 'bearer ' + TOKEN}).status_code == 200
    assert c.get('/v1/status', headers=[('Authorization', 'Bearer ' + TOKEN)] * 2).status_code == 401
    assert c.get('/openapi.json').json()['components']['securitySchemes']['HTTPBearer']['scheme'] == 'bearer'


def test_chunked_upload_actual_limit_and_early_content_length_limit():
    app = create_app(settings(max_image_bytes=1024))
    chunks = [{'type': 'http.request', 'body': b'x' * 150000, 'more_body': True},
              {'type': 'http.request', 'body': b'x' * 150000, 'more_body': False}]
    reads, messages = asyncio.run(send_asgi(app, chunks, headers=AUTH))
    assert len(reads) == 2 and messages[0]['status'] == 413
    assert app.state.runtime.active == 0
    reads, messages = asyncio.run(send_asgi(app, [], headers=AUTH + [(b'content-length', b'300000')]))
    assert not reads and messages[0]['status'] == 413


@pytest.mark.parametrize('length', [b'-1', b'not-a-number', b'9' * 21])
def test_invalid_content_length_is_safe(length):
    _, messages = asyncio.run(send_asgi(create_app(settings()), [], headers=AUTH + [(b'content-length', length)]))
    assert messages[0]['status'] == 400


def test_small_json_body_limit_and_upload_disconnect_release_capacity():
    app = create_app(settings())
    _, messages = asyncio.run(send_asgi(app, [], path='/v1/plans/draft',
                                      headers=AUTH + [(b'content-length', b'65537')]))
    assert messages[0]['status'] == 413
    assert json.loads(messages[1]['body'])['error']['code'] == 'request_too_large'
    _, messages = asyncio.run(send_asgi(app, [{'type': 'http.disconnect'}], headers=AUTH))
    assert not messages
    assert app.state.runtime.active == 0


def test_upload_deadline_is_total_and_releases_capacity():
    async def run():
        app = create_app(settings(request_body_timeout_seconds=1))
        async def never_finishes():
            await asyncio.Event().wait()
        _, messages = await asyncio.wait_for(send_asgi(app, [], headers=AUTH, receive=never_finishes), 3)
        assert messages[0]['status'] == 408
        assert json.loads(messages[1]['body'])['error']['code'] == 'upload_timeout'
        assert app.state.runtime.active == 0
    asyncio.run(run())


def test_busy_request_is_rejected_without_queue_and_health_stays_available():
    async def run():
        entered, release = asyncio.Event(), asyncio.Event()
        class Slow(MockProvider):
            async def plan(self, value):
                entered.set()
                await release.wait()
                return await super().plan(value)
        app = create_app(settings(ai_max_concurrent_requests=1), Slow())
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test') as c:
                first = asyncio.create_task(c.post('/v1/plans/draft', headers=HEADERS, json=request()))
                try:
                    await asyncio.wait_for(entered.wait(), 2)
                    busy = await c.post('/v1/plans/draft', headers=HEADERS, json=request())
                    assert busy.status_code == 503 and busy.json()['error']['code'] == 'server_busy'
                    assert busy.headers['retry-after'] == '1'
                    assert len(app.state.runtime.calls) == 1
                    assert (await c.get('/health')).status_code == 200
                    assert (await c.get('/v1/status', headers=HEADERS)).json()['limits']['maxConcurrentAI'] == 1
                finally:
                    release.set()
                    response = await first
                assert response.status_code == 200 and app.state.runtime.active == 0
                assert (await c.post('/v1/plans/draft', headers=HEADERS, json=request())).status_code == 200
    asyncio.run(run())


def test_task_cancellation_and_internal_failure_release_capacity():
    async def run():
        entered, release = asyncio.Event(), asyncio.Event()
        class Slow(MockProvider):
            async def plan(self, value):
                entered.set()
                await release.wait()
                return await super().plan(value)
        app = create_app(settings(ai_max_concurrent_requests=1), Slow())
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test') as c:
            pending = asyncio.create_task(c.post('/v1/plans/draft', headers=HEADERS, json=request()))
            await asyncio.wait_for(entered.wait(), 2)
            pending.cancel()
            with pytest.raises(asyncio.CancelledError): await pending
            assert app.state.runtime.active == 0
            release.set()
            assert (await c.post('/v1/plans/draft', headers=HEADERS, json=request())).status_code == 200
        provider = MockProvider()
        provider.plan = AsyncMock(side_effect=RuntimeError('PRIVATE-INPUT-AND-KEY'))
        app = create_app(settings(), provider)
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test') as c:
            response = await c.post('/v1/plans/draft', headers=HEADERS, json=request())
            assert response.status_code == 500 and response.json()['error']['code'] == 'internal_error'
            assert 'PRIVATE' not in response.text
            assert app.state.runtime.active == 0
    asyncio.run(run())


def test_rate_limit_retry_after_expires_on_monotonic_boundary(monkeypatch):
    clock = [100.0]
    monkeypatch.setattr(runtime_module, 'time', SimpleNamespace(monotonic=lambda: clock[0]))
    async def run():
        runtime = BackendRuntime(settings(requests_per_minute=1))
        async with runtime.admit(): pass
        for now, retry in [(100, '60'), (159.1, '1')]:
            clock[0] = now
            with pytest.raises(ProviderError) as error:
                async with runtime.admit(): pass
            assert error.value.status == 429 and error.value.headers['Retry-After'] == retry
        clock[0] = 160
        async with runtime.admit(): assert runtime.active == 1
        assert runtime.active == 0
    asyncio.run(run())


def test_provider_pools_are_lazy_reused_and_closed_only_on_shutdown(monkeypatch):
    instances = []
    class Pool(MockProvider):
        def __init__(self, config, photo=False):
            self.closed = 0
            self.photo = photo
            instances.append(self)
        async def close(self): self.closed += 1
    monkeypatch.setattr(runtime_module, 'OpenAIProvider', Pool)
    app = create_app(settings(provider='openai', openai_api_key='synthetic', openai_model='synthetic'))
    with TestClient(app) as c:
        assert c.get('/v1/status', headers=HEADERS).status_code == 200 and not instances
        for _ in range(2):
            assert c.post('/v1/plans/draft', headers=HEADERS, json=request()).status_code == 200
        assert len(instances) == 1 and instances[0].closed == 0
        assert c.post('/v1/analyze', headers=HEADERS, files={'image': ('a.jpg', jpeg())}).status_code == 200
        assert len(instances) == 2 and all(p.closed == 0 for p in instances)
    assert all(p.closed == 1 for p in instances)
    assert not app.state.runtime.providers


def test_shutdown_still_closes_other_pool_if_one_close_fails():
    async def run():
        runtime = BackendRuntime(settings())
        first = SimpleNamespace(close=AsyncMock(side_effect=RuntimeError('PRIVATE')))
        second = SimpleNamespace(close=AsyncMock())
        runtime.providers = {False: first, True: second}
        with pytest.raises(RuntimeError, match='Failed to close backend model connections'):
            await runtime.close()
        assert first.close.await_count == second.close.await_count == 1
        assert not runtime.providers
    asyncio.run(run())


def test_request_ids_and_logs_never_echo_input_query_token_or_upstream_error(caplog):
    caplog.set_level(logging.INFO, logger='uvicorn.error')
    with TestClient(create_app(settings())) as c:
        value = request(weeks=0, goal='PRIVATE-GOAL')
        response = c.post('/v1/plans/draft?PRIVATE-QUERY', headers={**HEADERS, 'X-Request-ID': 'PRIVATE-ID'}, json=value)
        assert response.status_code == 422 and response.json()['error']['code'] == 'invalid_request'
        request_id = response.headers['x-request-id']
        assert len(request_id) == 32 and request_id != 'PRIVATE-ID'
        assert response.headers['cache-control'] == 'no-store'
        another = c.get('/PRIVATE-PATH?PRIVATE-QUERY')
        assert another.headers['x-request-id'] != request_id
        assert request_id in caplog.text
        assert TOKEN not in caplog.text and 'PRIVATE' not in caplog.text
        assert 'PRIVATE' not in response.text
