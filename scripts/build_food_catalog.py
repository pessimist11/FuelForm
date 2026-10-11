#!/usr/bin/env python3
"""Extract a tiny offline catalog from the official USDA SR Legacy CSV archive.
Usage: python3 scripts/build_food_catalog.py /path/to/FoodData_Central_sr_legacy_food_csv_2018-04.zip
No values are estimated by this script. See docs/nutrition.md.
"""
import csv
import hashlib
import io
import json
import sys
import zipfile
from pathlib import Path
selections = [
 ('rice-cooked','熟白米饭','Rice, white, long-grain, regular, enriched, cooked','熟重，水煮，无额外油',['白米饭','米饭']),
 ('rice-raw','生白米','Rice, white, long-grain, regular, raw, enriched','生重，未烹饪',['生米']),
 ('banana','香蕉','Bananas, raw','生重，可食部分',['香蕉']),
 ('apple','苹果（带皮）',"Apples, raw, with skin (Includes foods for USDA's Food Distribution Program)",'生重，可食部分，带皮',['苹果']),
 ('chicken-roasted','烤鸡胸肉（去皮）','Chicken, broilers or fryers, breast, meat only, cooked, roasted','熟重，烤制，去皮，不另加油',['鸡胸肉']),
 ('egg-boiled','水煮鸡蛋','Egg, whole, cooked, hard-boiled','熟重，可食部分，水煮',['鸡蛋']),
 ('olive-oil','橄榄油','Oil, olive, salad or cooking','食用油，按实际用量',['油']),
 ('broccoli-boiled','水煮西兰花','Broccoli, cooked, boiled, drained, without salt','熟重，水煮沥干，无油无盐',['西兰花'])
]
archive = Path(sys.argv[1]); z = zipfile.ZipFile(archive)
def rows(file):
 name = next(n for n in z.namelist() if n.endswith('/' + file))
 return csv.DictReader(io.TextIOWrapper(z.open(name), encoding='utf-8-sig'))
by_description = {r['description']: r for r in rows('food.csv')}
wanted = {by_description[s[2]]['fdc_id'] for s in selections}
values = {}
for r in rows('food_nutrient.csv'):
 if r['fdc_id'] in wanted and r['nutrient_id'] in ('1008','1003','1004','1005'):
  values.setdefault(r['fdc_id'], {})[r['nutrient_id']] = float(r['amount'])
foods = []
for key, name, desc, prep, aliases in selections:
 record = by_description[desc]; fdc = record['fdc_id']; n = values[fdc]
 foods.append(dict(id=key,name=name,preparation=prep,aliases=aliases,
  nutrients=dict(kcal=n['1008'],protein=n.get('1003'),carbs=n.get('1005'),fat=n.get('1004')),
  source=dict(kind='database',label='USDA SR Legacy · ' + desc,version='2018-04',reference=f'https://fdc.nal.usda.gov/food-details/{fdc}/nutrients')))
output = dict(version='fuelform-foods-1.0.0', sourceArchive='https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip', archiveSHA256=hashlib.sha256(archive.read_bytes()).hexdigest(), foods=foods)
root = Path(__file__).resolve().parents[1]
for path in (root/'backend/data/foods.v1.json', root/'ios/FuelForm/Resources/foods.v1.json'):
 path.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
print('Extracted', len(foods), 'official per-100g records; identical iOS/backend catalog')
