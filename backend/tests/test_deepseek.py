import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest
from fastapi.testclient import TestClient
from openai import AsyncOpenAI, AuthenticationError, BadRequestError, NotFoundError, PermissionDeniedError, RateLimitError
from pydantic import SecretStr, ValidationError

from app.config import Settings
from app.main import create_app
from app.providers import DeepSeekProvider, MockProvider, ProviderError
from app.schemas import PlanRequest
from test_service import HEADERS, TOKEN, jpeg, request


def settings(**kw):
    values = dict(_env_file=None, provider='deepseek', service_token=SecretStr(TOKEN),
                  deepseek_api_key=SecretStr('test-only-deepseek-key'), deepseek_model='deepseek-flash')
    values.update(kw)
    return Settings(**values)


def test_status_reports_missing_configuration_without_claiming_live_success():
    c = TestClient(create_app(settings(deepseek_api_key=SecretStr(''))))
    status = c.get('/v1/status', headers=HEADERS).json()
    assert status['mode'] == 'deepseek'
    assert not status['photoReady'] and not status['planReady']
    assert 'DEEPSEEK_API_KEY' in status['configurationIssues'][0]
    assert 'test-only-deepseek-key' not in json.dumps(status)
    for path, kwargs in [('/v1/analyze', {'files': {'image': ('a.jpg', jpeg())}}),
                         ('/v1/plans/draft', {'json': request()})]:
        response = c.post(path, headers=HEADERS, **kwargs)
        assert response.status_code == 503
        assert response.json()['error']['code'] == 'configuration_missing'
        assert 'mode' not in response.json()


def test_photo_and_plan_models_are_separate_and_text_only_photos_fail_before_network():
    config = settings(deepseek_model='deepseek-v4-pro')
    c = TestClient(create_app(config))
    status = c.get('/v1/status', headers=HEADERS).json()
    assert status['planReady'] and not status['photoReady']
    r = c.post('/v1/analyze', headers=HEADERS, files={'image': ('a.jpg', jpeg())})
    assert r.status_code == 503
    assert 'DEEPSEEK_VISION_MODEL' in r.json()['error']['message']
    config = settings(deepseek_model='deepseek-v4-pro', deepseek_vision_model='deepseek-flash')
    assert config.ai_configuration()[1] == 'deepseek-v4-pro'
    assert config.ai_configuration(photo=True)[1] == 'deepseek-flash'
    assert not config.configuration_issues(photo=True)


@pytest.mark.parametrize('endpoint', ['http://api.deepseek.com', 'https://secret@api.deepseek.com',
                                      'https://api.deepseek.com?token=secret', 'https://api.deepseek.com/#secret'])
def test_provider_credentials_cannot_be_embedded_in_endpoint(endpoint):
    with pytest.raises(ValidationError): settings(deepseek_base_url=endpoint)


def test_deepseek_sdk_serializes_real_responses_schema_and_inline_photo_without_retry():
    async def run():
        raw = await MockProvider().recognize(b'')
        calls = []
        async def handler(req):
            payload = json.loads(req.content)
            calls.append(payload)
            assert str(req.url) == 'https://api.deepseek.com/responses'
            assert req.headers['authorization'] == 'Bearer test-only-deepseek-key'
            assert payload['model'] == 'deepseek-flash'
            assert payload['reasoning']['effort'] == 'none'
            assert 'store' not in payload
            assert payload['text']['format']['type'] == 'json_schema'
            assert payload['text']['format']['strict'] is True
            assert payload['input'][0]['content'][1]['image_url'].startswith('data:image/jpeg;base64,')
            return httpx.Response(200, json={
                'id': 'resp_test', 'object': 'response', 'created_at': 0, 'status': 'completed',
                'model': 'deepseek-flash', 'parallel_tool_calls': True,
                'output': [{'id': 'msg_test', 'type': 'message', 'role': 'assistant', 'status': 'completed',
                            'content': [{'type': 'output_text', 'text': raw.model_dump_json(by_alias=True), 'annotations': []}]}]
            })
        engine = DeepSeekProvider(settings(), photo=True)
        await engine.close()
        engine.client = AsyncOpenAI(api_key='test-only-deepseek-key', base_url='https://api.deepseek.com',
            max_retries=0, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
        try:
            assert (await engine.recognize(jpeg())).is_food
            assert len(calls) == 1
            assert engine.client.max_retries == 0
        finally: await engine.close()
    asyncio.run(run())


def test_deepseek_http_routes_keep_real_mode_and_validate_plan():
    # An injected test provider checks routing only, never real AI quality.
    with TestClient(create_app(settings(), MockProvider())) as c:
        analysis = c.post('/v1/analyze', headers=HEADERS, files={'image': ('a.jpg', jpeg())})
        assert analysis.status_code == 200
        assert analysis.json()['mode'] == 'deepseek'
        plan = c.post('/v1/plans/draft', headers=HEADERS, json=request())
        assert plan.status_code == 200
        assert plan.json()['mode'] == 'deepseek'
        assert len(plan.json()['draft']['days']) == 14
        assert '演示' not in plan.json()['warnings'][0]


@pytest.mark.parametrize('status,parsed', [('incomplete', None), ('completed', None)])
def test_deepseek_refusal_or_truncation_never_returns_success(status, parsed):
    async def run():
        engine = DeepSeekProvider(settings())
        await engine.close()
        engine.client = SimpleNamespace(responses=SimpleNamespace(parse=AsyncMock(
            return_value=SimpleNamespace(status=status, output_parsed=parsed))))
        with pytest.raises(ProviderError) as e: await engine.recognize(jpeg())
        assert e.value.code == 'invalid_ai_output'
    asyncio.run(run())


@pytest.mark.parametrize('cls,status,code', [
    (AuthenticationError, 401, 'provider_auth_failed'), (PermissionDeniedError, 403, 'provider_access_denied'),
    (RateLimitError, 429, 'provider_rate_limited'), (NotFoundError, 404, 'provider_model_unavailable'),
    (BadRequestError, 400, 'provider_request_rejected')])
def test_provider_errors_are_actionable_without_exposing_upstream_body(cls, status, code):
    async def run():
        engine = DeepSeekProvider(settings())
        await engine.close()
        upstream = httpx.Response(status, request=httpx.Request('POST', 'https://api.deepseek.com/responses'))
        error = cls('PRIVATE-KEY-AND-PHOTO', response=upstream, body={'private': 'PRIVATE-KEY-AND-PHOTO'})
        parse = AsyncMock(side_effect=error)
        engine.client = SimpleNamespace(responses=SimpleNamespace(parse=parse))
        with pytest.raises(ProviderError) as e: await engine.plan(PlanRequest.model_validate(request()))
        assert e.value.code == code
        assert 'PRIVATE' not in e.value.message
        assert parse.await_count == 1
    asyncio.run(run())


def test_deepseek_timeout_is_bounded_and_not_retried():
    async def run():
        engine = DeepSeekProvider(settings())
        await engine.close()
        parse = AsyncMock(side_effect=asyncio.TimeoutError)
        engine.client = SimpleNamespace(responses=SimpleNamespace(parse=parse))
        with pytest.raises(ProviderError) as e: await engine.recognize(jpeg())
        assert e.value.code == 'ai_timeout'
        assert parse.await_count == 1
    asyncio.run(run())
