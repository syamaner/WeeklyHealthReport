#!/usr/bin/env python3
"""Offline source-to-projection audit. This does not measure independent food-match quality."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile


def audit(archive, projection):
    archive_bytes, projected_bytes = archive.read_bytes(), projection.read_bytes()
    corpus = json.loads(projected_bytes)
    if hashlib.sha256(archive_bytes).hexdigest() != corpus['archiveSHA256']: raise ValueError('archive binding')
    with ZipFile(archive) as z: original = z.read('20_5.json')
    if hashlib.sha256(original).hexdigest() != corpus['sourceJSONSHA256']: raise ValueError('source binding')
    rows = json.loads(original)
    checks = []
    for record in corpus['records']:
        for field, value in record['nutrients'].items():
            raw = rows[value['sourceRow']]
            checks.append(raw['整合編號'] == record['id'] and raw['樣品名稱'] == record['sourceName']
                and raw['分析項'] == value['sourceField'] and raw['含量單位'] == value['unit']
                and raw['每100克含量'].strip() == value['literal'] and float(raw['每100克含量']) == value['amount'])
    return dict(schema='tfda-source-audit-v1', sourceURL=corpus['sourceURL'], snapshotDate=corpus['snapshotDate'],
        archiveSHA256=corpus['archiveSHA256'], sourceJSONSHA256=corpus['sourceJSONSHA256'],
        projectionSHA256=hashlib.sha256(projected_bytes).hexdigest(), reviewSHA256=corpus['reviewSHA256'],
        sourceRecords=corpus['sourceRecords'], admittedRecords=len(corpus['records']),
        categoryCounts=dict(sorted(Counter(r['category'] for r in corpus['records']).items())),
        preparationCounts=dict(sorted(Counter(r['preparation'] for r in corpus['records']).items())),
        fieldCorrespondence=dict(passed=sum(checks), denominator=len(checks)),
        completeFourMacros=sum(all(k in r['nutrients'] for k in ['energy_consumed','protein','fat_total','carbohydrates']) for r in corpus['records']),
        retainedZeroValues=sum(v['amount']==0 for r in corpus['records'] for v in r['nutrients'].values()),
        providerCalls=0, independentAcceptance='not_run',
        limitations=['Reviewed development selection, not a representative coverage rate.',
                    'Literal source fidelity does not establish the identity of a user meal or portion.',
                    'Unknown cooking state, serving weight, density and unmapped nutrients remain unknown.'])

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('archive',type=Path);p.add_argument('projection',type=Path);p.add_argument('output',type=Path)
    a=p.parse_args();result=audit(a.archive,a.projection)
    a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False))
    if result['fieldCorrespondence']['passed'] != result['fieldCorrespondence']['denominator']: raise SystemExit(1)
