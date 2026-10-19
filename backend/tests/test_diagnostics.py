import importlib.util
import json
import runpy
import sys
from pathlib import Path

import httpx
import pytest

spec = importlib.util.spec_from_file_location('check_backend', Path(__file__).resolve().parents[2] / 'scripts/check_backend.py')
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)


def test_diagnostic_only_sends_two_gets_and_never_sends_model_key_or_prints_server_details():
    calls = []
    def handler(request):
        calls.append(request)
        assert request.method == 'GET' and not request.content
        if request.url.path == '/health':
            assert 'authorization' not in request.headers
            return httpx.Response(200, json={'status': 'ok'})
        assert request.url.path == '/v1/status'
        assert request.headers['authorization'] == 'Bearer synthetic-service-token'
        return httpx.Response(200, headers={'X-Request-ID': 'a' * 32}, json={
            'mode': 'deepseek', 'photoReady': True, 'planReady': True, 'configurationIssues': [],
            'unknownPrivateField': 'PRIVATE-INPUT', 'photoModel': 'PRIVATE-KEY'})
    result = diagnostics.inspect_backend('http://10.0.0.1:8000', 'synthetic-service-token', httpx.MockTransport(handler))
    assert len(calls) == 2 and result['configurationReady']
    assert not result['actualAIValidated'] and result['requestId'] == 'a' * 32
    assert 'PRIVATE' not in json.dumps(result)


@pytest.mark.parametrize('url', ['http://example.com', 'http://8.8.8.8', 'https://user:secret@example.com',
                                'https://example.com?token=private', 'https://example.com#private',
                                'https://example.com:99999', 'ftp://127.0.0.1'])
def test_diagnostic_rejects_unsafe_or_invalid_addresses_without_echoing_them(url):
    with pytest.raises(diagnostics.DiagnosticError) as error: diagnostics.checked_address(url)
    assert url not in str(error.value) and 'private' not in str(error.value)


def test_diagnostic_never_follows_redirects_with_credentials():
    calls = []
    def handler(request):
        calls.append(request)
        if request.url.path == '/health': return httpx.Response(200, json={'status': 'ok'})
        return httpx.Response(302, headers={'Location': 'https://other.example/collect'})
    with pytest.raises(diagnostics.DiagnosticError, match='重定向'):
        diagnostics.inspect_backend('https://example.com', 'synthetic', httpx.MockTransport(handler))
    assert len(calls) == 2 and all(request.url.host == 'example.com' for request in calls)


def test_diagnostic_auth_error_is_safe_and_missing_config_is_not_ready():
    def handler(request):
        if request.url.path == '/health': return httpx.Response(200, json={'status': 'ok'})
        return httpx.Response(401, json={'private': 'PRIVATE'})
    with pytest.raises(diagnostics.DiagnosticError, match='SERVICE_TOKEN') as error:
        diagnostics.inspect_backend('https://example.com', 'synthetic', httpx.MockTransport(handler))
    assert 'PRIVATE' not in str(error.value)
    def incomplete(request):
        if request.url.path == '/health': return httpx.Response(200, json={'status': 'ok'})
        return httpx.Response(200, json={'mode': 'deepseek', 'photoReady': False, 'planReady': False})
    result = diagnostics.inspect_backend('https://example.com', 'synthetic', httpx.MockTransport(incomplete))
    assert not result['configurationReady'] and result['authenticated']


def test_smoke_script_refuses_real_provider_before_any_post(monkeypatch):
    calls = []
    original_client = httpx.Client
    def handler(request):
        calls.append(request)
        assert request.method == 'GET' and request.url.path == '/v1/status'
        return httpx.Response(200, json={'mode': 'deepseek'})
    def client(**kwargs):
        return original_client(**kwargs, transport=httpx.MockTransport(handler))
    root = Path(__file__).resolve().parents[2]
    monkeypatch.syspath_prepend(str(root / 'scripts'))
    monkeypatch.setenv('SERVICE_TOKEN', 'synthetic-smoke-only')
    monkeypatch.setattr(httpx, 'Client', client)
    monkeypatch.setattr(sys, 'argv', ['smoke_backend.py', '--url', 'http://127.0.0.1:18000', '--no-write-fixtures'])
    with pytest.raises(AssertionError, match='Smoke script only runs'):
        runpy.run_path(str(root / 'scripts/smoke_backend.py'), run_name='__main__')
    assert len(calls) == 1
