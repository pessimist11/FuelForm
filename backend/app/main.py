import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, UploadFile, File, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.security import HTTPBearer
from pydantic import ValidationError
from .config import Settings
from .schemas import PlanRequest, PlanResponse, Analysis
from .providers import ProviderError, validate_plan
from .images import normalize_image
from .catalog import CATALOG, EXERCISES, match
from .middleware import RequestGuard
from .runtime import BackendRuntime

def create_app(settings: Settings | None = None, provider_override=None):
    settings = settings or Settings()
    runtime = BackendRuntime(settings, provider_override)
    @asynccontextmanager
    async def lifespan(app):
        if not settings.service_token.get_secret_value().strip():
            raise RuntimeError('SERVICE_TOKEN is required even in mock mode; run scripts/bootstrap_backend.py')
        try:
            yield
        finally:
            await runtime.close()
    app = FastAPI(title='FuelForm', version='1.0.0', lifespan=lifespan)
    app.state.runtime = runtime
    app.add_middleware(RequestGuard, settings=settings, runtime=runtime)

    @app.exception_handler(ProviderError)
    async def provider_error(request, exc):
        return JSONResponse(status_code=exc.status, headers=exc.headers,
                            content={'error': {'code': exc.code, 'message': exc.message}})

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request: Request, exc):
        # FastAPI's default details may echo the submitted goal or other private fields.
        return JSONResponse(status_code=422, content={'error': {
            'code': 'invalid_request', 'message': '请求格式或数值无效，请检查日期、训练条件或上传文件'}})

    @app.get('/health')
    async def health(): return {'status': 'ok'}

    # Keep the bearer scheme in OpenAPI; RequestGuard authenticates before body parsing.
    protected = [Depends(HTTPBearer(auto_error=False))]
    @app.get('/v1/status', dependencies=protected)
    async def status():
        photo_issues = settings.configuration_issues(photo=True)
        plan_issues = settings.configuration_issues()
        return {'mode': settings.provider, 'catalogVersion': CATALOG['version'],
                'photoReady': not photo_issues, 'planReady': not plan_issues,
                'photoModel': settings.ai_configuration(photo=True)[1] if settings.provider != 'mock' else None,
                'planModel': settings.ai_configuration()[1] if settings.provider != 'mock' else None,
                'configurationIssues': list(dict.fromkeys(photo_issues + plan_issues)),
                'limits': {'maxConcurrentAI': settings.ai_max_concurrent_requests,
                           'requestsPerMinute': settings.requests_per_minute,
                           'maxImageBytes': settings.max_image_bytes}}
    @app.get('/v1/foods', dependencies=protected)
    async def foods(): return CATALOG
    @app.get('/v1/exercises', dependencies=protected)
    async def exercises(): return EXERCISES

    @app.post('/v1/analyze', response_model=Analysis, dependencies=protected)
    async def analyze(image: UploadFile = File(...)):
        try:
            data = await image.read(settings.max_image_bytes + 1)
        finally:
            await image.close()
        if len(data) > settings.max_image_bytes:
            raise ProviderError('image_too_large', '照片超过大小限制', 413)
        jpeg = await asyncio.to_thread(normalize_image, data)
        raw = await runtime.provider(photo=True).recognize(jpeg)
        return match(raw, settings.provider)

    @app.post('/v1/plans/draft', response_model=PlanResponse, dependencies=protected)
    async def plan(request: PlanRequest):
        engine = runtime.provider()
        try:
            draft = validate_plan(await engine.plan(request), request)
            return PlanResponse(mode=settings.provider, draft=draft, warnings=['演示计划：固定规则，不是个性化 AI 结果'] if settings.provider == 'mock' else ['草稿需要用户核对动作与强度，确认后才启用'])
        except ValidationError:
            raise ProviderError('invalid_ai_output', '计划结构校验失败', 422) from None
    return app

app = create_app()
