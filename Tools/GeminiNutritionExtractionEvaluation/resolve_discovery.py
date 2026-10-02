"""Resolve v2 observed leads against pinned admitted resource identities."""
import json
from pathlib import Path
import hashlib
from evidence_binding import resolve_record
from evaluate import ROOT,load

REPO=ROOT.parents[1]
RESOURCE=REPO/'Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources'

def resources():
    cofid=load(RESOURCE/'cofid-2021-generic-search-v1.json')
    usda=load(RESOURCE/'usda-generic-v1.json')
    records=[]
    for r in cofid['records']:
        if r['published_code']!='18-070':continue
        mapping={'energy_kcal':'energy_consumed','protein':'protein','fat':'fat_total'}
        records.append(dict(family='cofid',id=r['published_code'],name=r['name'],preparation='cooked',
          reviewed_name_aliases=['Beef, sirloin steak, grilled medium-rare, lean only'],
          release_record_id=r['record_id'],basis_amount=100,basis_unit='g',
          nutrients={k:dict(value=float(r['nutrients'][v]['value']),unit=r['nutrients'][v]['source_unit']) for k,v in mapping.items()}))
    for r in usda['records']:
        if r['fdcID']!=169457:continue
        mapping={'energy_kcal':'energy_consumed','protein':'protein','fat':'fat_total'}
        records.append(dict(family='usda-sr',id=str(r['fdcID']),name=r['name'],preparation=r['preparation'],
          release_record_id=r['id'],basis_amount=100,basis_unit='g',
          nutrients={k:dict(value=r['nutrients'][v]['amount'],unit=r['nutrients'][v]['unit']) for k,v in mapping.items()}))
    return records

def evaluate_leads():
    fixtures=load(ROOT/'resolution-cases-v3.json');records=resources()
    return [dict(id=c['case_id'],result=resolve_record(c['lead'],records),
                 expected_status=c['expected_status'],passed=resolve_record(c['lead'],records)['status']==c['expected_status']) for c in fixtures]

if __name__=='__main__':print(json.dumps(evaluate_leads(),indent=2))
