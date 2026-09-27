"""Frozen record-level synthetic retrieval scoring; no provider access."""
import argparse
import gzip
import json
import math
from collections import defaultdict
from pathlib import Path


def load(path):
    return json.loads((gzip.open(path, 'rt') if str(path).endswith('.gz') else open(path)).read())


def score(fixture, rows):
    cases = {c['id']: c for c in fixture['cases']}
    expected = {(cid, source) for cid in cases for source in ('cofid', 'usda', 'composite')}
    actual = [(r['id'], r['source']) for r in rows]
    if len(set(actual)) != len(actual) or set(actual) != expected:
        raise ValueError('Missing, duplicate or unknown replay rows')
    groups = defaultdict(list)
    details = []
    for row in rows:
        case = cases[row['id']]
        if row['query'] != case['query'] or len(set(row['records'])) != len(row['records']):
            raise ValueError('Query drift or duplicate record')
        source = row['source']
        def eligible(rid):
            return source == 'composite' or rid.startswith(source + (':' if source == 'cofid' else '-'))
        if not all(eligible(rid) for rid in row['records']):
            raise ValueError('Source identity drift')
        labels = {rid: grade for rid, grade in case['grades'].items() if eligible(rid)}
        grades = [labels.get(rid, 0) for rid in row['records']]
        relevant = [i+1 for i, grade in enumerate(grades) if grade >= 2]
        covered = any(g >= 2 for g in labels.values())
        available = bool(labels)
        ideal = sorted(labels.values(), reverse=True)[:5]
        def dcg(values):
            return sum((2**g-1)/math.log2(i+2) for i,g in enumerate(values[:5]))
        wanted = 'relevant' if covered else 'tentative' if available else 'empty'
        observed = 'relevant' if relevant else 'tentative' if any(grades) else 'unrelated' if grades else 'empty'
        detail = dict(id=case['id'], family=case['family'], source=source, exactCoverage=covered,
            tentativeOnly=available and not covered, expected=wanted, observed=observed,
            hit1=bool(relevant and relevant[0] == 1), hit5=bool(relevant and relevant[0] <= 5),
            rr=1/relevant[0] if relevant else 0,
            ndcg5=dcg(grades)/dcg(ideal) if ideal else None,
            incorrectVariantAt1=bool(row['records'] and row['records'][0] in case['incorrectVariantRecords']),
            incorrectVariantsAt5=sum(rid in case['incorrectVariantRecords'] for rid in row['records'][:5]),
            grades=grades)
        details.append(detail)
        groups[source].append(detail); groups[source + '/' + case['family']].append(detail)
    summaries = {}
    for key, values in sorted(groups.items()):
        covered = [v for v in values if v['exactCoverage']]
        misses = [v for v in values if v['expected'] == 'empty']
        graded = [v for v in values if v['ndcg5'] is not None]
        matrix = defaultdict(lambda: defaultdict(int))
        for v in values: matrix[v['expected']][v['observed']] += 1
        def mean(field, items):
            return sum(v[field] for v in items)/len(items) if items else None
        summaries[key] = dict(cases=len(values), exactCoverageCases=len(covered),
            catalogueGapCases=len(values)-len(covered), tentativeOnlyCases=sum(v['tentativeOnly'] for v in values),
            hitAt1=mean('hit1',covered), hitAt5=mean('hit5',covered), mrr=mean('rr',covered),
            ndcgAt5=mean('ndcg5',graded), gradedCases=len(graded),
            noResultCases=len(misses), appropriateNoResult=sum(v['observed']=='empty' for v in misses),
            incorrectVariantAt1=sum(v['incorrectVariantAt1'] for v in values),
            incorrectVariantsAt5=sum(v['incorrectVariantsAt5'] for v in values), confusionMatrix=dict(matrix))
    return dict(version='retrieval-metrics-v1', independentAcceptance=False, summaries=summaries, details=details)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('fixture'); parser.add_argument('replay'); parser.add_argument('output')
    parser.add_argument('--verify-report')
    args = parser.parse_args()
    report = score(load(args.fixture),load(args.replay))
    Path(args.output).write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    if args.verify_report and report != load(args.verify_report):
        raise SystemExit('Retrieval development regression report differs; inspect before updating labels or results')
