import json
from pathlib import Path
from .schemas import Analysis, FoodSource, Recognition, SuggestedFood

DATA = Path(__file__).resolve().parents[1] / 'data'
CATALOG = json.loads((DATA / 'foods.v1.json').read_text())
FOODS = {food['id']: food for food in CATALOG['foods']}
EXERCISES = json.loads((DATA / 'exercises.v1.json').read_text())
EXERCISE_MAP = {e['id']: e for e in EXERCISES}

def match(recognition: Recognition, mode: str) -> Analysis:
    items = []
    for candidate in recognition.items:
        food = FOODS.get(candidate.food_id)
        # A model-selected ID alone is insufficient: preparation has to match too.
        matched = food is not None and food['preparation'] == candidate.preparation
        if matched:
            source = FoodSource.model_validate(food['source'])
            nutrients = food['nutrients']
            basis = 'per100'
        else:
            source = FoodSource(kind='demo' if mode == 'mock' else 'ai', label='演示估算' if mode == 'mock' else 'AI 估算 · 未匹配可靠营养数据', version='1', reference=None)
            nutrients = candidate.estimated_nutrients
            basis = 'total'
        items.append(SuggestedFood(name=food['name'] if matched else candidate.name, served_grams=candidate.served_grams,
            preparation=candidate.preparation, basis=basis, nutrients=nutrients, source=source,
            assumptions=candidate.assumptions,
            questions=candidate.questions + (['请核对数据库条目与实物及烹饪方式是否一致'] if matched else ['未匹配可靠数据，请核对估算热量'])))
    return Analysis(original_draft=recognition, mode=mode, is_food=recognition.is_food, items=items, message=recognition.message,
        warnings=['演示分析：固定示例，与图片内容无关'] if mode == 'mock' else ['图片无法准确确定份量、用油和剩余量；确认后才计入记录'],
        catalog_version=CATALOG['version'])
