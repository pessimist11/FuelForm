#!/usr/bin/env python3
"""Exercise a running local Mock backend; write synthetic contract fixtures, never print tokens."""
from pathlib import Path
import argparse
import json
import os
import httpx
from io import BytesIO
from PIL import Image
from dotenv import dotenv_values
from check_backend import checked_address
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--url',default='http://127.0.0.1:8000')
parser.add_argument('--no-write-fixtures',action='store_true',help='Validate HTTP without replacing contract fixtures')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
config=dotenv_values(root/'backend/.env')
token=os.environ.get('SERVICE_TOKEN') or config.get('SERVICE_TOKEN')
if not token: raise SystemExit('SERVICE_TOKEN missing')
base=checked_address(args.url)
def call(path, body=None, content_type='application/json'):
 with httpx.Client(timeout=20,trust_env=False,follow_redirects=False) as connection:
  r=connection.request('GET' if body is None else 'POST',base+path,content=body,
   headers={'Authorization':'Bearer '+token,'Content-Type':content_type})
  r.raise_for_status()
  return r.json()
assert call('/v1/status')['mode']=='mock', 'Smoke script only runs in explicitly configured Mock mode'
output=BytesIO();Image.new('RGB',(96,96),'green').save(output,'JPEG')
boundary='FuelFormSmoke'
body=(f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="synthetic.jpg"\r\nContent-Type: image/jpeg\r\n\r\n').encode()+output.getvalue()+f'\r\n--{boundary}--\r\n'.encode()
analysis=call('/v1/analyze',body,'multipart/form-data; boundary='+boundary)
assert analysis['mode']=='mock' and analysis['items'][0]['nutrients']['kcal']==130
request={'startDate':'2026-10-12','weeks':2,'trainingDays':3,'durationMinutes':40,'equipment':['bodyweight'],'experience':'beginner','goal':'规律训练','avoidExerciseIds':['pushup']}
plan=call('/v1/plans/draft',json.dumps(request).encode());assert len(plan['draft']['days'])==14
if not args.no_write_fixtures:
 fixtures=root/'ios/Tests/Fixtures'; fixtures.mkdir(exist_ok=True)
 for name,value in [('analysis',analysis),('plan',plan),('plan-request',request)]:
  (fixtures/(name+'.json')).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
print('PASS: live HTTP auth/status + JPEG multipart Mock analysis + 2-week plan; '
 + ('fixtures unchanged' if args.no_write_fixtures else 'synthetic fixtures saved'))
