#!/usr/bin/env python3
"""Check reachability/auth/configuration only. Never submits a photo or AI request."""
import argparse
import ipaddress
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from app.config import Settings


class DiagnosticError(Exception):
    pass


def checked_address(address):
    value = address.strip().rstrip('/')
    try:
        url = urlsplit(value)
        port = url.port
        if not url.hostname or url.username or url.password or url.query or url.fragment:
            raise ValueError
        if port is not None and not 1 <= port <= 65535:
            raise ValueError
        if url.scheme == 'https':
            return value
        local = url.hostname == 'localhost' or url.hostname.endswith('.local')
        try:
            ip = ipaddress.ip_address(url.hostname)
            local = ip == ipaddress.ip_address('127.0.0.1') or any(ip in network for network in (
                ipaddress.ip_network('10.0.0.0/8'), ipaddress.ip_network('172.16.0.0/12'),
                ipaddress.ip_network('192.168.0.0/16')))
        except ValueError:
            pass
        if url.scheme != 'http' or not local:
            raise ValueError
    except ValueError:
        raise DiagnosticError('地址无效：使用本地开发HTTP地址或不含凭据、查询参数的HTTPS地址。') from None
    return value


def read_json(client, url, headers=None):
    with client.stream('GET', url, headers=headers) as response:
        if response.status_code == 401:
            raise DiagnosticError('后端可达，但SERVICE_TOKEN认证失败；模型Key不能代替服务令牌。')
        if response.is_redirect:
            raise DiagnosticError('服务返回重定向；请直接填写最终服务地址，诊断不会转发凭据。')
        if response.status_code != 200:
            raise DiagnosticError(f'后端返回HTTP {response.status_code}，请检查服务状态。')
        body = bytearray()
        for chunk in response.iter_bytes():
            if len(body) + len(chunk) > 64 * 1024:
                raise DiagnosticError('后端状态响应过大。')
            body.extend(chunk)
        try:
            result = json.loads(body)
            if not isinstance(result, dict): raise ValueError
        except (ValueError, UnicodeError):
            raise DiagnosticError('后端状态响应格式不正确。') from None
        request_id = response.headers.get('x-request-id', '')
        return result, request_id if re.fullmatch(r'[a-f0-9]{32}', request_id) else None


def inspect_backend(address, token, transport=None):
    address = checked_address(address)
    if not token.strip():
        raise DiagnosticError('本机未配置SERVICE_TOKEN；请先运行bootstrap_backend.py。')
    # Local checks must not accidentally route through the model provider's proxy.
    with httpx.Client(timeout=10, follow_redirects=False, trust_env=False, transport=transport) as client:
        health, _ = read_json(client, address + '/health')
        if health.get('status') != 'ok':
            raise DiagnosticError('健康检查未返回ok，请核对服务地址。')
        status, request_id = read_json(client, address + '/v1/status', {'Authorization': 'Bearer ' + token})
    mode = status.get('mode')
    if mode not in {'mock', 'openai', 'deepseek'}:
        raise DiagnosticError('后端供应商模式未知，请检查服务版本。')
    photo, plan = status.get('photoReady'), status.get('planReady')
    issues = status.get('configurationIssues')
    configured = photo is True and plan is True and isinstance(issues, list) and not issues
    return {'reachable': True, 'authenticated': True, 'mode': mode,
            'configurationReady': configured, 'requestId': request_id,
            'actualAIValidated': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:8000', help='Running backend URL; no keys in the URL')
    args = parser.parse_args()
    try:
        settings = Settings()
        result = inspect_backend(args.url, settings.service_token.get_secret_value())
        print(json.dumps(result, ensure_ascii=False))
        if not result['configurationReady']:
            print('连接与认证通过，但配置尚未就绪或后端版本较旧；请在App检查配置项。')
            return 1
        print('PASS: 后端连接、认证和配置状态正常；未调用模型，不代表实际分析已验证。')
        return 0
    except DiagnosticError as error:
        print('FAIL: ' + str(error))
    except httpx.TimeoutException:
        print('FAIL: 后端连接超时；请检查地址、网络和后端进程。')
    except httpx.HTTPError:
        print('FAIL: 无法连接后端；请检查地址、网络、TLS证书和本地网络权限。')
    except Exception:
        print('FAIL: 本机配置或服务响应无效；未显示配置值或原始响应。')
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
