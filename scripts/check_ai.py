#!/usr/bin/env python3
"""Check local AI settings; explicit --models/--live flags make upstream calls.

Never print credentials, full provider errors, image bytes, or personal responses.
--live uses a synthetic non-food image and generic training conditions.
"""
import argparse
import asyncio
import json
import re
import sys
from datetime import date
from io import BytesIO
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from PIL import Image
from pydantic import ValidationError
from app.config import Settings
from app.providers import DeepSeekProvider, OpenAIProvider, ProviderError, validate_plan
from app.schemas import PlanRequest


def label(value):
    return value if re.fullmatch(r'[a-zA-Z0-9._:-]{1,128}', value or '') else '(未填写或格式无效)'


async def check(args):
    settings = Settings()
    if settings.provider == 'mock':
        print('当前是 Mock，不能证明真实 AI 已接入。设置 PROVIDER=deepseek 或 openai。')
        return 1
    issues = list(dict.fromkeys(settings.configuration_issues() + settings.configuration_issues(photo=True)))
    print(json.dumps({'provider': settings.provider,
                      'planModel': label(settings.ai_configuration()[1]),
                      'photoModel': label(settings.ai_configuration(photo=True)[1]),
                      'configurationIssues': issues}, ensure_ascii=False))
    if issues: return 1
    if not args.models and not args.live:
        print('PASS: 本地配置齐全；尚未验证凭据、账户权限或实际模型调用。')
        return 0
    cls = DeepSeekProvider if settings.provider == 'deepseek' else OpenAIProvider
    engine = cls(settings)
    try:
        if args.models:
            result = await asyncio.wait_for(engine.client.models.list(), timeout=settings.ai_timeout_seconds)
            ids = {m.id for m in result.data}
            selected = {settings.ai_configuration()[1], settings.ai_configuration(photo=True)[1]}
            if not selected.issubset(ids):
                print('FAIL: 配置的模型未在当前账户模型列表中找到；请核对模型名称。')
                return 1
            print('PASS: 账户模型列表包含已配置模型；这不代表实际生成已验证。')
        if args.live:
            request = PlanRequest(start_date=date.today(), weeks=1, training_days=3, duration_minutes=40,
                equipment=['bodyweight'], experience='beginner', goal='建立规律训练习惯', avoid_exercise_ids=[])
            draft = validate_plan(await engine.plan(request), request)
            print(f'PASS: 真实训练草稿通过校验，{len(draft.days)}天；未写入手机、未启用。')
    finally:
        await engine.close()
    if args.live:
        photo = cls(settings, photo=True)
        try:
            image = BytesIO()
            Image.new('RGB', (96, 96), (40, 70, 110)).save(image, 'JPEG')
            result = await photo.recognize(image.getvalue())
            if result.is_food:
                print('FAIL: 合成纯色非食物图片被识别为食物；请检查模型效果。')
                return 1
            print('PASS: 真实图片请求及结构化返回通过；纯色测试不证明餐食识别准确性。')
        finally:
            await photo.close()
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models', action='store_true', help='读取账户模型列表，不生成内容')
    parser.add_argument('--live', action='store_true', help='最多两次实际生成请求，会消耗模型 API 额度')
    args = parser.parse_args()
    try:
        code = asyncio.run(check(args))
    except ProviderError as error:
        print(f'FAIL: {error.code}: {error.message}')
        code = 1
    except ValidationError:
        print('FAIL: 本地配置无效，请检查 .env；未显示配置值。')
        code = 1
    except Exception:
        print('FAIL: 模型服务连接或认证失败，请检查后端凭据、网络和账户；未显示上游错误内容。')
        code = 1
    raise SystemExit(code)
