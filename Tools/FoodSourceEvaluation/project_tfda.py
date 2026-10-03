#!/usr/bin/env python3
"""Project reviewed TFDA records from a pinned local public ZIP. No network or private inputs."""
import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import re
from zipfile import ZipFile

ARCHIVE_SHA256 = 'c1ef5502ceceead6d5ce3b7ee21fe544702b1e508be73b196fce2cf0e61985cb'
VERSION = 'tfda-projection-v1'
MAPPING = {
    'energy_consumed': ('熱量', 'kcal'), 'protein': ('粗蛋白', 'g'),
    'fat_total': ('粗脂肪', 'g'), 'carbohydrates': ('總碳水化合物', 'g'),
    'fiber': ('膳食纖維', 'g'), 'sugar': ('糖質總量', 'g'),
    'fat_saturated': ('飽和脂肪', 'g'), 'cholesterol': ('膽固醇', 'mg'),
    'sodium': ('鈉', 'mg'), 'potassium': ('鉀', 'mg'), 'calcium': ('鈣', 'mg'),
    'iron': ('鐵', 'mg'), 'magnesium': ('鎂', 'mg'), 'phosphorus': ('磷', 'mg'),
    'zinc': ('鋅', 'mg'), 'copper': ('銅', 'mg'), 'manganese': ('錳', 'mg'),
    'vitamin_c': ('維生素C', 'mg'), 'thiamin_b1': ('維生素B1', 'mg'),
    'riboflavin_b2': ('維生素B2', 'mg'), 'vitamin_b6': ('維生素B6', 'mg'),
}
METADATA = ['樣品名稱', '樣品英文名稱', '內容物描述', '食品分類', '俗名']

def preparation(description):
    # Only the explicit source sample state, not laboratory grinding or recipe words.
    state = description.split(';', 1)[0]
    if re.match(r'^樣品狀態:生(?:[,，]|$)', state): return 'raw'
    if re.match(r'^樣品狀態:熟(?:[,，]|$)', state): return 'cooked'
    return 'unknown'

def project(rows, review):
    if review['schema'] != 'tfda-reviewed-foods-v1': raise ValueError('review schema')
    wanted = review['records']
    if len({x['id'] for x in wanted}) != len(wanted): raise ValueError('duplicate reviewed ID')
    groups = defaultdict(list)
    for index, row in enumerate(rows): groups[row['整合編號']].append((index, row))
    records = []
    for selected in wanted:
        entries = groups[selected['id']]
        if not entries: raise ValueError('missing source record')
        first = entries[0][1]
        if first['樣品名稱'] != selected['sourceName']: raise ValueError('source identity drift')
        if any(any(r.get(k) != first.get(k) for k in METADATA) for _, r in entries): raise ValueError('inconsistent source identity')
        fields = {}
        for index, row in entries:
            field = row['分析項']
            if field in fields: raise ValueError('duplicate nutrient declaration')
            fields[field] = (index, row)
        nutrients = {}
        for key, (field, unit) in MAPPING.items():
            if field not in fields: continue
            index, row = fields[field]
            literal = row['每100克含量']
            if literal is None or not literal.strip(): continue
            if row['含量單位'] != unit: raise ValueError('unexpected nutrient unit')
            if not re.fullmatch(r'\d+(?:\.\d+)?', literal.strip()): raise ValueError('non-exact nutrient value')
            value = float(literal)
            if not math.isfinite(value) or value < 0: raise ValueError('invalid nutrient value')
            nutrients[key] = dict(amount=value, unit=unit, sourceField=field,
                sourceRow=index, literal=literal.strip())
        if not all(k in nutrients for k in ['energy_consumed', 'protein', 'fat_total', 'carbohydrates']):
            raise ValueError('reviewed record lacks four macros')
        aliases = list(dict.fromkeys(selected['aliases'] + [selected['name'], selected['sourceName']]))
        records.append(dict(id=selected['id'], name=selected['name'], sourceName=selected['sourceName'],
            sourceEnglish=first['樣品英文名稱'], description=first['內容物描述'], category=first['食品分類'],
            preparation=preparation(first['內容物描述']), aliases=aliases, nutrients=nutrients))
    return records

def build(archive, review_path):
    raw = archive.read_bytes()
    if hashlib.sha256(raw).hexdigest() != ARCHIVE_SHA256: raise ValueError('TFDA archive hash mismatch')
    review_bytes = review_path.read_bytes()
    review = json.loads(review_bytes)
    with ZipFile(archive) as source:
        if source.namelist() != ['20_5.json']: raise ValueError('unexpected archive members')
        member = source.read('20_5.json')
    rows = json.loads(member)
    return dict(schema='tfda-generic-v1', projectionVersion=VERSION, aliasPolicy=review['aliasPolicy'],
        sourceURL='https://data.fda.gov.tw/data/opendata/export/20/json', snapshotDate='2026-10-03',
        archiveSHA256=ARCHIVE_SHA256, sourceJSONSHA256=hashlib.sha256(member).hexdigest(),
        reviewSHA256=hashlib.sha256(review_bytes).hexdigest(), sourceRows=len(rows),
        sourceRecords=len({r['整合編號'] for r in rows}), records=project(rows, review))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path); parser.add_argument('review', type=Path); parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = build(args.archive, args.review)
    data = (json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode()
    args.output.write_bytes(data)
    print(json.dumps(dict(records=len(result['records']), sourceRecords=result['sourceRecords'], bytes=len(data), sha256=hashlib.sha256(data).hexdigest())))
