"""Audit staged discovery, first-lead capture and extraction without denominator loss.

No credentials or inference. Source review was frozen before extraction; this is
not a timed single app interaction or independent acceptance study.
"""
import json
from pathlib import Path
import sys

from compare_runs import load_run, request_statistics
from capture_discovery import verify_capture_outputs
from evaluate import fraction
from frozen_run import digest, verify, verify_output_hashes


def index(rows, key='id'):
    result = {row[key]: row for row in rows}
    if len(result) != len(rows):
        raise ValueError('duplicate workflow case')
    return result


def join_cases(discovery_cases, capture_cases, capture_report, extraction_cases, score_rows, acquisition, leads):
    planned = index(discovery_cases)
    captures, reports = index(capture_cases), index(capture_report)
    extracts, scores = index(extraction_cases, 'comparison_case'), index(score_rows, 'comparison_case')
    if not planned or set(captures) != set(planned) or set(reports) != set(planned) or set(leads) != set(planned):
        raise ValueError('workflow lost an original discovery case')
    captured = {key for key, row in reports.items() if row['status'] == 'captured'}
    if (set(extracts) != captured or set(scores) != captured
            or len(acquisition['planned_case_ids']) != len(planned)
            or set(acquisition['planned_case_ids']) != set(planned)
            or len(acquisition['captured_case_ids']) != len(captured)
            or set(acquisition['captured_case_ids']) != captured):
        raise ValueError('workflow lost a captured or planned case')
    excluded = index(acquisition['excluded_cases'])
    if set(excluded) != set(planned) - captured:
        raise ValueError('workflow lost an acquisition failure')
    eligibility = acquisition.get('source_eligibility', {})
    if set(eligibility) != captured or any(not isinstance(r.get('eligible'), bool) or not r.get('reason') for r in eligibility.values()):
        raise ValueError('workflow source review incomplete')
    rows = []
    for key, original in planned.items():
        capture, report = captures[key], reports[key]
        if original['query'] != capture['query'] or original['query'] != report['query']:
            raise ValueError('query changed between workflow stages')
        first = leads[key][0]['url'] if leads[key] else None
        if capture['url'] != first or report['url'] != first:
            raise ValueError('capture substituted the first native lead')
        if key in captured and (not first or extracts[key]['query'] != original['query']):
            raise ValueError('extraction changed the discovery query or captured no lead')
        if key in excluded and excluded[key]['status'] != report['status']:
            raise ValueError('capture failure changed')
        score = scores.get(key, {}).get('baseline', {})
        offered = scores.get(key, {}).get('eligible_offer_count', 0)
        eligible = eligibility.get(key, {}).get('eligible', False)
        answerable = scores.get(key, {}).get('expected_answerable', False)
        passed = score.get('passed', False)
        rows.append(dict(id=key, query=original['query'], first_url=first,
            search_available=bool(leads[key]), captured=key in captured,
            source_eligible=eligible, source_review_reason=eligibility.get(key, {}).get('reason'),
            extraction_available=score.get('available', False),
            correct_review_outcome=eligible and passed,
            useful_panel=eligible and passed and answerable,
            source_supported_abstention=eligible and passed and not answerable,
            wrong_source_selection=key in captured and not eligible and score.get('selected', False),
            wrong_source_reviewable_offer=key in captured and not eligible and offered > 0,
            abstention_with_reviewable_offers=passed and not answerable and offered > 0,
            eligible_offer_count=offered,
            wrong_source_safe_abstention=key in captured and not eligible and passed and not answerable,
            capture_status=report['status'], extraction_status=scores.get(key, {}).get('run_status', 'not_planned')))
    metrics = {field: fraction(sum(row[field] for row in rows), len(rows)) for field in [
        'search_available', 'captured', 'source_eligible', 'extraction_available', 'correct_review_outcome',
        'useful_panel', 'source_supported_abstention', 'wrong_source_selection', 'wrong_source_safe_abstention',
        'wrong_source_reviewable_offer', 'abstention_with_reviewable_offers']}
    return dict(original_query_count=len(rows), metrics=metrics, cases=rows)


def capture_plan(root):
    plan = json.loads((root / 'plan.json').read_text())
    if digest(root / 'plan.json') != (root / 'plan.sha256').read_text().strip():
        raise ValueError('capture plan changed')
    if plan['version'] not in ['keyless-source-capture-audit-v1', 'keyless-source-capture-audit-v2'] or not plan['policy'].startswith('First native lead only,'):
        raise ValueError('first-native-lead capture required')
    for name, expected in plan['snapshot_hashes'].items():
        target = (root / name).resolve()
        if not target.is_relative_to(root / 'snapshot') or digest(target) != expected:
            raise ValueError('capture snapshot changed')
    return plan


def verified_requests(root, plan):
    requests = []
    for case in plan['cases']:
        folder = root / 'results' / case['id']
        if not folder.exists():
            continue
        if not plan.get('output_hashes_required') or not (folder / 'run-status.json').exists():
            raise ValueError('completed output receipts required')
        verify_output_hashes(folder, json.loads((folder / 'run-status.json').read_text()))
        receipt = folder / 'receipt.json'
        if receipt.exists():
            requests.extend(json.loads(receipt.read_text())['requests'])
    return requests


def evaluate(discovery, capture, extraction, output):
    discovery, capture, extraction, output = [Path(p).resolve() for p in (discovery, capture, extraction, output)]
    if output.exists():
        raise ValueError('workflow report already exists')
    search, acquisition, inference = verify(discovery), capture_plan(capture), verify(extraction)
    if any(c['task'] != 'discovery' for c in search['cases']):
        raise ValueError('discovery roster required')
    if any(c['task'] != 'provided_document' or c.get('selection', True) for c in inference['cases']):
        raise ValueError('extractor-only workflow required')
    if len({c['extractor'] for c in inference['cases']}) != 1:
        raise ValueError('one extraction route per workflow required')
    metadata = inference['roster_metadata']
    if (metadata.get('discovery_plan_sha256') != digest(discovery / 'plan.json')
            or metadata.get('capture_plan_sha256') != digest(capture / 'plan.json')):
        raise ValueError('workflow stage plans do not match')
    search_requests = verified_requests(discovery, search)
    extraction_requests = verified_requests(extraction, inference)
    leads = {}
    for case in search['cases']:
        original = discovery / 'results' / case['id'] / 'discovery.json'
        copied = capture / 'snapshot/discovery' / (case['id'] + '.json')
        if original.exists():
            if not copied.exists() or digest(original) != digest(copied):
                raise ValueError('captured discovery result differs from original')
            result = json.loads(original.read_text())
            if result['query'] != case['query']:
                raise ValueError('discovery output query changed')
            leads[case['id']] = result['leads']
        else:
            if copied.exists():
                raise ValueError('capture introduced an unobserved search result')
            leads[case['id']] = []
    # Read the report committed to extraction's input snapshot, not a mutable
    # acquisition score. Every case must retain the same report.
    reports = []
    for case in inference['cases']:
        candidates = [extraction / name for name in case['evidence_files'] if name.endswith('-capture-report.json')]
        if len(candidates) != 1:
            raise ValueError('frozen acquisition report required')
        reports.append(candidates[0])
    if not reports or len({digest(p) for p in reports}) != 1:
        raise ValueError('inconsistent frozen acquisition reports')
    report = json.loads(reports[0].read_text())
    capture_integrity = verify_capture_outputs(capture, acquisition, report)
    score, _ = load_run(extraction, inference)
    for row in score['cases']:
        result_path = extraction / 'results' / row['id'] / 'result.json'
        result_value = json.loads(result_path.read_text()) if result_path.exists() else {}
        row['eligible_offer_count'] = len(result_value.get('eligible_candidate_ids', []))
    result = join_cases(search['cases'], acquisition['cases'], report['cases'], inference['cases'],
                        score['cases'], metadata['acquisition'], leads)
    useful = result['metrics']['useful_panel']['numerator']
    result.update(version='staged-food-discovery-workflow-v1',
        capture_output_integrity=capture_integrity,
        stages={label: dict(run=root.name, plan_sha256=digest(root / 'plan.json')) for label, root in
                [('discovery', discovery), ('capture', capture), ('extraction', extraction)]},
        operations=request_statistics(search_requests + extraction_requests, useful),
        extraction_baseline=score['baseline'],
        qualification='Development workflow through actual adapters, staged with source review before extraction. Not independent acceptance, calibrated confidence, or a timed single app tap. Preferred-choice abstention does not imply that no other reviewable candidates were offered; those are counted separately. Wrong-source abstention never counts as coverage success. Capture has no provider inference cost.')
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result['metrics']))


if __name__ == '__main__':
    evaluate(*sys.argv[1:])
