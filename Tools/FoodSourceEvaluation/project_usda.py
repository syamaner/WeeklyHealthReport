#!/usr/bin/env python3
"""Build a pinned offline USDA projection from local official snapshots."""
import argparse, hashlib, json, math, zipfile
from pathlib import Path
SOURCES = {
 "foundation": ("2026-04-30", "186e988ec542e913f51ef62b86a47758e8cdd0d1dc3889e7b055581f3c09c77a"),
 "legacy": ("2018-04-01", "0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef"),
}
MAPPING = {
 "protein":1003, "fat_total":1004, "carbohydrates":1005, "fiber":1079, "sugar":2000,
 "fat_saturated":1258, "fat_monounsaturated":1292, "fat_polyunsaturated":1293, "cholesterol":1253,
 "calcium":1087, "iron":1089, "magnesium":1090, "phosphorus":1091, "potassium":1092,
 "sodium":1093, "zinc":1095, "copper":1098, "manganese":1101, "selenium":1103,
 "vitamin_c":1162, "thiamin_b1":1165, "riboflavin_b2":1166, "niacin_b3":1167,
 "pantothenic_acid_b5":1170, "vitamin_b6":1175, "folate_b9":1177, "vitamin_b12":1178,
 "vitamin_d":1114, "vitamin_e":1109, "vitamin_k":1185, "water":1051, "caffeine":1057,
}
# Vitamin A RAE/IU and folate DFE are intentionally not substituted for other conventions.
def build(paths):
 sources, records = [], []
 for kind, path in zip(SOURCES, paths):
  date, expected = SOURCES[kind];raw=path.read_bytes();digest=hashlib.sha256(raw).hexdigest()
  if digest != expected: raise ValueError("USDA archive hash mismatch: " + kind)
  with zipfile.ZipFile(path) as z:
   member=next(n for n in z.namelist() if n.endswith('.json'))
   entries=next(iter(json.loads(z.read(member)).values()))
  source_id='usda-'+kind;release_id=source_id+':'+date+':sha256:'+digest
  sources.append(dict(id=release_id,sourceID=source_id,date=date,archiveHash=digest,
    records=sum(isinstance(x,dict) for x in entries),nullSlots=sum(x is None for x in entries)))
  for food in entries:
   if food is None: continue
   if not isinstance(food,dict): raise ValueError('Invalid USDA record')
   values={}
   nutrients=food.get('foodNutrients',[])
   mapping=dict(MAPPING)
   ids={n['nutrient']['id'] for n in nutrients}
   # Energy convention is selected within this one record, never added together.
   mapping['energy_consumed']=next((n for n in [2048,2047,1008] if n in ids),1008)
   for key,nid in mapping.items():
    found=[n for n in nutrients if n['nutrient']['id']==nid]
    if len(found)!=1: continue
    n=found[0];amount=n.get('amount');unit=n['nutrient']['unitName']
    if not isinstance(amount,(int,float)) or isinstance(amount,bool) or not math.isfinite(amount) or amount<0: continue
    unit={'µg':'mcg','μg':'mcg','UG':'mcg','KCAL':'kcal','G':'g','MG':'mg'}.get(unit,unit)
    values[key]=dict(amount=amount,unit=unit,nutrientID=nid)
   name=food['description'];lower=name.lower()
   raw_state='raw' in lower.split(', ');cooked=any(x in lower for x in ['cooked','grilled','broiled','roasted','fried','boiled','braised'])
   preparation='raw' if raw_state and not cooked else 'cooked' if cooked and not raw_state else 'unknown'
   records.append(dict(id=release_id+':fdc:'+str(food['fdcId']),fdcID=food['fdcId'],releaseID=release_id,
    name=name,preparation=preparation,bone='boneless' if 'boneless' in lower else 'unknown',nutrients=values))
 return dict(version=1,sources=sources,records=records)
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('foundation',type=Path);parser.add_argument('legacy',type=Path);parser.add_argument('output',type=Path);args=parser.parse_args()
 data=(json.dumps(build([args.foundation,args.legacy]),sort_keys=True,separators=(',',':'),ensure_ascii=False)+'\n').encode()
 args.output.write_bytes(data);print(hashlib.sha256(data).hexdigest(),len(data))
