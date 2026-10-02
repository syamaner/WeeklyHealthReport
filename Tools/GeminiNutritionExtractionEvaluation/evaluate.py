"""Frozen reference checks and provider-independent nutrition extraction scoring."""
import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent

def load(path):
    return json.loads(Path(path).read_text())

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def verify(root=ROOT):
    contract = load(root / 'frozen-contract-v1.json')
    for name, expected in contract['sha256'].items():
        if digest(root / name) != expected:
            raise ValueError('frozen file changed: ' + name)
    corpus = load(root / 'corpus-v1.json')
    ids = [c['id'] for c in corpus['cases']]
    if len(ids) != len(set(ids)):
        raise ValueError('duplicate case')
    dev = {c['source'] for c in corpus['cases'] if c['split'] == 'development'}
    holdout = {c['source'] for c in corpus['cases'] if c['split'] == 'holdout'}
    if dev & holdout:
        raise ValueError('source split leakage')
    return corpus, contract

def plan(corpus):
    return [(c, arm) for arm in ('panel', 'url') for c in corpus['cases']
            if c['split'] == 'development' and (arm == 'panel' or corpus['sources'][c['source']]['url'])]

def validate(value, schema, path='root'):
    """Validate the deliberately small schema subset used by this experiment."""
    types = schema['type'] if isinstance(schema['type'], list) else [schema['type']]
    matches = {'null': value is None, 'object': type(value) is dict, 'array': type(value) is list,
               'string': type(value) is str,
               'number': type(value) in (int, float) and math.isfinite(value)}
    if not any(matches[t] for t in types):
        raise ValueError(path + ': type')
    if 'enum' in schema and value not in schema['enum']:
        raise ValueError(path + ': enum')
    if type(value) is dict:
        props = schema['properties']
        if set(schema['required']) - value.keys() or value.keys() - props.keys():
            raise ValueError(path + ': keys')
        for k, v in value.items():
            validate(v, props[k], path + '.' + k)
    if type(value) is list:
        for v in value:
            validate(v, schema['items'], path + '[]')

def score(case, result, schema):
    try:
        validate(result, schema)
    except (ValueError, KeyError, TypeError):
        return dict(schema_valid=False, passed=False, errors=['schema'], correct_fields=0,
                    expected_fields=len(case['gold']['nutrients']), invented_fields=[], values_on_abstention=False)
    gold = case['gold']
    errors = [key for key in ('status','source_url','basis_amount','basis_unit','preparation','applicability')
              if result[key] != gold[key]]
    entries = result['nutrients']
    actual = {f['id']: f for f in entries}
    if len(actual) != len(entries): errors.append('duplicate_nutrient')
    if actual.keys() != gold['nutrients'].keys(): errors.append('nutrient_set')
    correct = 0
    invented = []
    for name, expected in gold['nutrients'].items():
        observed = actual.get(name, {})
        if all(observed.get(k, 'MISSING') == v for k, v in expected.items()):
            correct += 1
        else:
            errors.append('field:' + name)
        if expected['state'] == 'unknown' and observed.get('value') is not None:
            invented.append(name)
        if observed.get('state') != 'unknown' and not observed.get('evidence', '').strip():
            errors.append('missing_evidence:' + name)
        if observed.get('state') == 'unknown' and observed.get('evidence'):
            errors.append('unknown_evidence:' + name)
    values_on_abstention = gold['status'] != 'extracted' and any(f['value'] is not None for f in entries)
    return dict(schema_valid=True,passed=not errors,errors=errors,correct_fields=correct,
                expected_fields=len(gold['nutrients']),invented_fields=invented,
                values_on_abstention=values_on_abstention)

def scale_portion(result, consumed):
    """Deterministic arithmetic, never model-estimated density or yield."""
    from decimal import Decimal
    if not consumed or result.get('status') != 'extracted': return None
    if consumed['unit'] != result.get('basis_unit') or consumed['unit'] not in ('g','ml'): return None
    basis = result.get('basis_amount')
    if type(basis) not in (int,float) or basis <= 0: return None
    factor = Decimal(str(consumed['amount'])) / Decimal(str(basis))
    return {f['id']:float(Decimal(str(f['value'])) * factor) for f in result['nutrients']
            if f['state']=='declared' and f['unit']!='%' and type(f['value']) in (int,float)}

def report(corpus, replay, schema):
    expected = {(c['id'], arm) for c, arm in plan(corpus)}
    rows = replay['results']
    keys = [(r['case_id'], r['arm']) for r in rows]
    if len(set(keys)) != len(keys) or set(keys) - expected:
        raise ValueError('duplicate or out-of-plan replay')
    by_key = dict(zip(keys, rows))
    details = []
    for case, arm in plan(corpus):
        row = by_key.get((case['id'], arm))
        details.append(dict(case_id=case['id'],arm=arm,completed=row is not None,
                            score=score(case,row['extraction'],schema) if row else None,
                            portion=scale_portion(row['extraction'],case.get('consumed')) if row else None,
                            expected_portion=case.get('expected_portion')))
    return dict(planned=len(expected),completed=len(rows),
                arms={arm:dict(planned=sum(d['arm']==arm for d in details),
                               completed=sum(d['arm']==arm and d['completed'] for d in details),
                               passed=sum(d['arm']==arm and d['score'] is not None and d['score']['passed'] for d in details))
                      for arm in ('panel','url')},details=details,
                evidence_review='separate manual review required; numeric match is not provenance proof')

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--validate',action='store_true')
    parser.add_argument('--replay',type=Path)
    args=parser.parse_args()
    corpus,contract=verify()
    if args.replay:
        replay=load(args.replay)
        if replay['contract'] != contract: raise ValueError('replay contract mismatch')
        print(json.dumps(report(corpus,replay,load(ROOT/'response-schema-v1.json')),indent=2))
    else:
        print(json.dumps(dict(cases=len(corpus['cases']),development_requests=len(plan(corpus)),frozen=True)))
