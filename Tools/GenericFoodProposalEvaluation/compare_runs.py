"""Compare matched frozen runs without treating repeated foods as new samples.

Inputs, gold, runtime and evaluator must match. Scores are recomputed from retained
outputs; mutable score.json files are never trusted. No inference or credentials.
"""
from collections import defaultdict
from decimal import Decimal
import importlib.util
import json
import math
from pathlib import Path
import statistics
import sys

from frozen_run import digest, verify, verify_output_hashes


def case_key(case):
    return case.get('comparison_case', case['id'])


def matched_cases(left, right):
    def index(cases):
        result = {case_key(case): case for case in cases}
        if len(result) != len(cases) or not result:
            raise ValueError('empty or duplicate comparison cases')
        if any(case.get('selection', True) for case in cases):
            raise ValueError('extractor-only comparison required')
        if len({case.get('extractor', 'luna') for case in cases}) != 1:
            raise ValueError('one extractor per run required')
        return result
    a, b = index(left), index(right)
    if set(a) != set(b):
        raise ValueError('different planned case denominators')
    for key in a:
        for field in ['task', 'query', 'gold', 'family', 'domain', 'layout', 'slice']:
            if a[key][field] != b[key][field]:
                raise ValueError('comparison changed ' + field)
    return a, b


def pair_outcomes(left, right):
    a = {row['comparison_case']: row for row in left}
    b = {row['comparison_case']: row for row in right}
    if len(a) != len(left) or len(b) != len(right) or not a or set(a) != set(b):
        raise ValueError('incomplete or duplicate outcome pairing')
    pairs = []
    for key in a:
        x, y = a[key], b[key]
        pairs.append(dict(case=key, family=x['family'], domain=x['domain'],
                          left_pass=x['baseline']['passed'], right_pass=y['baseline']['passed'],
                          left_available=x['baseline']['available'], right_available=y['baseline']['available']))
    def totals(rows):
        return dict(planned_pairs=len(rows),
                    both_pass=sum(r['left_pass'] and r['right_pass'] for r in rows),
                    left_only_pass=sum(r['left_pass'] and not r['right_pass'] for r in rows),
                    right_only_pass=sum(not r['left_pass'] and r['right_pass'] for r in rows),
                    neither_pass=sum(not r['left_pass'] and not r['right_pass'] for r in rows))
    groups = {}
    for axis in ['family', 'domain']:
        buckets = defaultdict(list)
        for row in pairs:
            buckets[row[axis]].append(row)
        groups[axis] = {key: dict(**totals(rows), left_all_pass=all(r['left_pass'] for r in rows),
                                  right_all_pass=all(r['right_pass'] for r in rows)) for key, rows in buckets.items()}
    return dict(**totals(pairs), groups=groups, cases=pairs)


def request_statistics(requests, usable_panels):
    costs = [Decimal(str(r['reported_cost_usd'])) for r in requests if r.get('reported_cost_usd') is not None]
    if any(not value.is_finite() or value < 0 for value in costs):
        raise ValueError('invalid request cost')
    latencies = [r['latency_seconds'] for r in requests if r.get('latency_seconds') is not None]
    if any(isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value)
           or value < 0 for value in latencies):
        raise ValueError('invalid request latency')
    total = sum(costs, Decimal(0))
    complete_cost = bool(requests) and len(costs) == len(requests)
    ordered = sorted(latencies)
    return dict(request_count=len(requests), known_cost_requests=len(costs), unknown_cost_requests=len(requests)-len(costs),
                known_reported_cost_usd=str(total), cost_complete=complete_cost,
                cost_per_usable_panel_usd=str(total / usable_panels) if complete_cost and usable_panels else None,
                usable_correct_panels=usable_panels, latency_observed_requests=len(latencies),
                median_request_seconds=statistics.median(latencies) if latencies else None,
                p90_request_seconds=ordered[math.ceil(0.9*len(ordered))-1] if ordered else None,
                latency_scope='Observed request latency, including reported failures; not end-to-end UI latency. Missing timings are not zero.')


def load_run(root, plan):
    evaluator_path = root / 'snapshot/source/Tools/GenericFoodProposalEvaluation/evaluate.py'
    spec = importlib.util.spec_from_file_location('frozen_food_evaluator', evaluator_path)
    evaluator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(evaluator)
    outcomes, requests = {}, []
    for case in plan['cases']:
        folder = root / 'results' / case['id']
        if not folder.exists():
            continue
        if not plan.get('output_hashes_required') or not (folder / 'run-status.json').exists():
            raise ValueError('completed output receipts required for comparison')
        status = json.loads((folder / 'run-status.json').read_text())
        verify_output_hashes(folder, status)
        outcome = dict(status=status['status'])
        for field in ['extraction', 'result']:
            path = folder / (field + '.json')
            if path.exists():
                outcome[field] = json.loads(path.read_text())
        outcomes[case['id']] = outcome
        receipt = folder / 'receipt.json'
        if receipt.exists():
            requests.extend(json.loads(receipt.read_text())['requests'])
    result = evaluator.report(plan['cases'], outcomes, requests)
    usable = sum(row['baseline']['passed'] and row['expected_answerable'] for row in result['cases'])
    return result, request_statistics(requests, usable)


def compare(left, right, output):
    left, right, output = [Path(p).resolve() for p in (left, right, output)]
    if output.exists():
        raise ValueError('comparison output already exists')
    plans = [verify(root) for root in [left, right]]
    indexes = matched_cases(*(plan['cases'] for plan in plans))
    for key in indexes[0]:
        documents = [json.loads((root / index[key]['document']).read_text()) for root, index in zip([left, right], indexes)]
        if documents[0] != documents[1]:
            raise ValueError('comparison changed source documents')
    # Route is the sole intended experimental difference. This also pins the
    # extraction schema, prompt, domain rules and scoring implementation.
    runtime_maps = [{name: value for name, value in plan['snapshot_hashes'].items()
                     if name.startswith(('snapshot/source/', 'snapshot/runtime/'))} for plan in plans]
    if runtime_maps[0] != runtime_maps[1]:
        raise ValueError('comparison changed runtime, source or evaluator')
    if plans[0]['minimum_interval_seconds'] != plans[1]['minimum_interval_seconds']:
        raise ValueError('comparison changed request pacing')
    scores, operations = zip(*(load_run(root, plan) for root, plan in zip([left, right], plans)))
    result = dict(version='matched-food-route-comparison-v1',
                  left=dict(run=left.name, plan_sha256=digest(left/'plan.json'), extractor=plans[0]['cases'][0]['extractor'],
                            baseline=scores[0]['baseline'], operations=operations[0]),
                  right=dict(run=right.name, plan_sha256=digest(right/'plan.json'), extractor=plans[1]['cases'][0]['extractor'],
                             baseline=scores[1]['baseline'], operations=operations[1]),
                  paired=pair_outcomes(scores[0]['cases'], scores[1]['cases']),
                  qualification='Descriptive matched development comparison. Repeated foods and shared families are not independent samples; no statistical superiority or calibrated-confidence claim.',
                  scope='Extraction and binding on identical captured documents. Does not measure discovery, acquisition, source truth, saved entries or physical-device behaviour.')
    output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({key: result['paired'][key] for key in ['planned_pairs','both_pass','left_only_pass','right_only_pass','neither_pass']}))


if __name__ == '__main__':
    compare(*sys.argv[1:])
