import asyncio
import json
from datetime import date, timedelta
from io import BytesIO
from types import SimpleNamespace
from unittest.mock import AsyncMock
import pytest
from fastapi.testclient import TestClient
from PIL import Image
from pydantic import SecretStr, ValidationError
from app.config import Settings
from app.main import create_app
from app.schemas import Recognition, PlanRequest
from app.providers import MockProvider, OpenAIProvider, ProviderError, validate_plan
from app.catalog import match, FOODS
from app.images import normalize_image

TOKEN = 'test-only-service-token-not-a-credential'
HEADERS = {'Authorization': 'Bearer ' + TOKEN}
def settings(**kw): return Settings(_env_file=None, service_token=SecretStr(TOKEN), **kw)
def client(**kw): return TestClient(create_app(settings(**kw)))
def jpeg(size=(80, 60)):
    out = BytesIO(); Image.new('RGB', size, 'green').save(out, 'JPEG'); return out.getvalue()
def request(**kw):
    data = dict(startDate='2026-10-12', weeks=2, trainingDays=3, durationMinutes=40,
        equipment=['bodyweight'], experience='beginner', goal='规律训练', avoidExerciseIds=[])
    data.update(kw); return data

def test_auth_and_mock_status():
    c = client()
    assert c.get('/health').json() == {'status':'ok'}
    assert c.get('/v1/foods').status_code == 401
    assert c.get('/v1/status', headers=HEADERS).json()['mode'] == 'mock'
    assert c.get('/v1/foods', headers=HEADERS).json()['version'] == 'fuelform-foods-1.0.0'

def test_startup_requires_auth_even_in_mock():
    with pytest.raises(RuntimeError, match='SERVICE_TOKEN'):
        with TestClient(create_app(Settings(_env_file=None))): pass

def test_mock_photo_is_explicit_and_uses_official_cooked_rice():
    response = client().post('/v1/analyze', headers=HEADERS, files={'image': ('meal.jpg', jpeg(), 'image/jpeg')})
    assert response.status_code == 200, response.text
    data = response.json(); assert data['originalDraft']['items'][0]['estimatedNutrients']['kcal'] == 195; assert data['mode'] == 'mock'; assert '固定示例' in data['warnings'][0]
    f = data['items'][0]; assert f['basis'] == 'per100'; assert f['servedGrams'] == 150
    assert f['nutrients']['kcal'] == 130; assert '熟重' in f['preparation']
    assert f['source']['kind'] == 'database'; assert '2018' in f['source']['version']

@pytest.mark.parametrize('content,filename', [(b'not-an-image','meal.jpg'), (b'','meal.png'), (jpeg((10,10)), 'meal.jpg')])
def test_invalid_image_is_rejected(content, filename):
    r = client().post('/v1/analyze', headers=HEADERS, files={'image': (filename,content,'image/jpeg')})
    assert r.status_code == 422; assert r.json()['error']['code'] == 'invalid_image'

def test_byte_limit():
    r = client(max_image_bytes=1024).post('/v1/analyze', headers=HEADERS, files={'image':('large.jpg',b'x'*2000,'image/jpeg')})
    assert r.status_code == 413

def test_stream_body_limit():
    r = client(max_image_bytes=1024).post('/v1/analyze', headers=HEADERS, files={'image':('large.jpg',b'x'*300000,'image/jpeg')})
    assert r.status_code == 413, r.text

def test_png_normalization_removes_metadata_and_rotates():
    out = BytesIO(); image = Image.new('RGB',(80,60),'red'); exif = Image.Exif(); exif[274] = 6; exif[270] = 'private note'
    image.save(out,'JPEG',exif=exif)
    decoded = Image.open(BytesIO(normalize_image(out.getvalue())))
    assert decoded.size == (60,80); assert len(decoded.getexif()) == 0
    out = BytesIO(); Image.new('RGBA',(80,60),(0,0,0,0)).save(out,'PNG')
    assert Image.open(BytesIO(normalize_image(out.getvalue()))).getpixel((0,0)) == (255,255,255)

def test_heic_is_decoded():
    import pillow_heif
    heif = pillow_heif.from_pillow(Image.new('RGB',(80,60),'green')); out = BytesIO(); heif.save(out)
    assert Image.open(BytesIO(normalize_image(out.getvalue()))).format == 'JPEG'

def test_preparation_mismatch_never_uses_raw_rice_for_cooked_rice():
    raw = asyncio.run(MockProvider().recognize(b'')); raw.items[0].food_id = 'rice-raw'
    result = match(raw, 'openai'); f = result.items[0]
    assert f.source.kind == 'ai'; assert f.basis == 'total'; assert f.nutrients.kcal == 195
    assert FOODS['rice-raw']['nutrients']['kcal'] != FOODS['rice-cooked']['nutrients']['kcal']

def test_non_food_response_keeps_no_items():
    class NonFood:
        async def recognize(self, image): return Recognition(is_food=False,items=[],message='不是食物')
    r = TestClient(create_app(settings(),NonFood())).post('/v1/analyze',headers=HEADERS,files={'image':('a.jpg',jpeg())})
    assert r.status_code == 200; assert not r.json()['isFood']; assert r.json()['items'] == []

def test_real_config_missing_is_error_not_mock():
    r = client(provider='openai').post('/v1/analyze',headers=HEADERS,files={'image':('a.jpg',jpeg())})
    assert r.status_code == 503; assert r.json()['error']['code'] == 'configuration_missing'

@pytest.mark.parametrize('training_days', [1,2,3,4,5,6])
def test_mock_plan_has_consecutive_dates_and_correct_rest(training_days):
    r = client().post('/v1/plans/draft',headers=HEADERS,json=request(trainingDays=training_days))
    assert r.status_code == 200, r.text
    data = r.json(); assert data['mode'] == 'mock'; days = data['draft']['days']; assert len(days) == 14
    assert days[0]['dayKey'] == '2026-10-12'; assert days[-1]['dayKey'] == '2026-10-25'
    for i in (0,7): assert sum(not d['rest'] for d in days[i:i+7]) == training_days
    for day in days: assert bool(day['exercises']) != day['rest']

def test_avoid_conditions_and_equipment():
    r = client().post('/v1/plans/draft',headers=HEADERS,json=request(equipment=['dumbbell'],avoidExerciseIds=['db-row']))
    assert r.status_code == 200
    assert all(e['exerciseId'] != 'db-row' for d in r.json()['draft']['days'] for e in d['exercises'])
    r = client().post('/v1/plans/draft',headers=HEADERS,json=request(avoidExerciseIds=['squat','pushup','bridge','deadbug']))
    assert r.status_code == 422

@pytest.mark.parametrize('change', [{'trainingDays':7},{'weeks':0},{'durationMinutes':1},{'startDate':'2026-02-29'},{'equipment':[]}])
def test_invalid_plan_request(change):
    assert client().post('/v1/plans/draft',headers=HEADERS,json=request(**change)).status_code == 422

def test_invalid_generated_dates_and_actions_and_duration():
    req = PlanRequest.model_validate(request())
    for mutate in ('date','action','duration','avoid'):
        draft = asyncio.run(MockProvider().plan(req))
        if mutate == 'date': draft.days[1].day_key = draft.days[0].day_key
        if mutate == 'action': draft.days[0].exercises[0].exercise_id = 'invented'
        if mutate == 'duration': draft.days[0].exercises[0].rest_seconds = 600; draft.days[0].exercises[0].sets = 10
        if mutate == 'avoid': req = PlanRequest.model_validate(request(avoidExerciseIds=['squat']))
        with pytest.raises(ProviderError): validate_plan(draft,req)

def test_rate_limit_no_infinite_retry():
    c = client(requests_per_minute=1)
    assert c.post('/v1/plans/draft',headers=HEADERS,json=request()).status_code == 200
    assert c.post('/v1/plans/draft',headers=HEADERS,json=request()).status_code == 429

def test_openai_adapter_uses_responses_schema_store_false_and_no_retries():
    engine = OpenAIProvider(settings(provider='openai',openai_api_key=SecretStr('test-only-key'),openai_model='configured-vision-model'))
    raw = asyncio.run(MockProvider().recognize(b''))
    parse = AsyncMock(return_value=SimpleNamespace(status='completed', output_parsed=raw))
    engine.client = SimpleNamespace(responses=SimpleNamespace(parse=parse))
    result = asyncio.run(engine.recognize(jpeg()))
    assert result.is_food
    kw = parse.call_args.kwargs; assert kw['model'] == 'configured-vision-model'; assert kw['store'] is False
    assert kw['text_format'] is Recognition
    assert kw['input'][0]['content'][1]['image_url'].startswith('data:image/jpeg;base64,')

@pytest.mark.parametrize('status,parsed', [('incomplete',None),('completed',None)])
def test_openai_refusal_and_incomplete_are_explicit_errors(status,parsed):
    engine = OpenAIProvider(settings(openai_api_key=SecretStr('test-only-key'),openai_model='configured-vision-model'))
    engine.client = SimpleNamespace(responses=SimpleNamespace(parse=AsyncMock(return_value=SimpleNamespace(status=status,output_parsed=parsed))))
    with pytest.raises(ProviderError) as error: asyncio.run(engine.recognize(jpeg()))
    assert error.value.code == 'invalid_ai_output'

def test_openai_timeout_is_explicit():
    engine = OpenAIProvider(settings(openai_api_key=SecretStr('test-only-key'),openai_model='configured-vision-model'))
    engine.client = SimpleNamespace(responses=SimpleNamespace(parse=AsyncMock(side_effect=asyncio.TimeoutError)))
    with pytest.raises(ProviderError) as e: asyncio.run(engine.recognize(jpeg()))
    assert e.value.code == 'ai_timeout'

def test_schema_rejects_negative_and_unknown_fields():
    raw = asyncio.run(MockProvider().recognize(b'')).model_dump()
    raw['items'][0]['estimated_nutrients']['kcal'] = -1
    with pytest.raises(ValidationError): Recognition.model_validate(raw)
    raw = {'isFood':False,'items':[],'message':'no','confidence':0.999}
    with pytest.raises(ValidationError): Recognition.model_validate(raw)

def test_catalog_bundle_matches_backend_and_has_sources():
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    catalog = json.loads((root/'backend/data/foods.v1.json').read_text())
    assert catalog == json.loads((root/'ios/FuelForm/Resources/foods.v1.json').read_text())
    assert len(catalog['archiveSHA256']) == 64
    for food in catalog['foods']: assert food['source']['reference'].startswith('https://fdc.nal.usda.gov/')
