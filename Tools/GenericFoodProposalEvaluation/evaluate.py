"""Score a frozen Swift run without hiding failed, skipped or unattempted cases.

Only source-reviewed declarations are gold. These development scores do not
establish independent acceptance, calibrated confidence or real meal accuracy.
"""
from collections import defaultdict
from decimal import Decimal, InvalidOperation
import json
from pathlib import Path
import sys

UNITS = dict(energy="kcal", protein="g", carbohydrate="g", fat="g", fibre="g", sodium="mg")


def fraction(numerator, denominator):
    return dict(numerator=numerator, denominator=denominator,
                rate=numerator / denominator if denominator else None)


def number_equal(left, right):
    try:
        if isinstance(left, bool) or isinstance(right, bool):
            return False
        a, b = Decimal(str(left)), Decimal(str(right))
        return a.is_finite() and b.is_finite() and a == b
    except (InvalidOperation, ValueError):
        return False


def assess_choice(case, extraction, result, choice, available):
    gold = case['gold']
    expected = gold['outcome']
    known = {k: v for k, v in gold.get('nutrients', {}).items() if v is not None}
    unknown = {k for k, v in gold.get('nutrients', {}).items() if v is None}
    candidates = {c['id']: c for c in (extraction or {}).get('candidates', [])}
    candidate = candidates.get(choice) if choice in (result or {}).get('eligible_candidate_ids', []) else None
    row = dict(available=available, choice=choice, selected=candidate is not None,
               identity_correct=False, basis_correct=False, passed=False,
               declared_claims=0, correct_declared_claims=0, required_declared_fields=len(known),
               recovered_declared_fields=0, required_unknown_fields=len(unknown),
               preserved_unknown_fields=0, invented_unknown_fields=0)
    if not available:
        return row
    if expected == 'abstain':
        row['passed'] = candidate is None and choice in gold['allowed_choices']
    if candidate is None:
        return row
    values = candidate.get('nutrients', [])
    row['declared_claims'] = sum(v.get('state') == 'declared' for v in values)
    if expected != 'selected':
        return row
    row['identity_correct'] = (candidate.get('name') in gold['allowed_names'] and
                               ('allowed_document_ids' not in gold or candidate.get('document_id') in gold['allowed_document_ids']))
    basis = candidate.get('basis', {})
    bases = [gold['basis']] + gold.get('allowed_equivalent_bases', [])
    row['basis_correct'] = any(basis.get('unit') == expected_basis['unit'] and
                              number_equal(basis.get('amount'), expected_basis['amount']) for expected_basis in bases)
    identity_and_basis = row['identity_correct'] and row['basis_correct']
    seen = set()
    for value in values:
        key = value.get('key')
        if key in seen:
            continue
        seen.add(key)
        if value.get('state') == 'declared':
            if key in unknown:
                row['invented_unknown_fields'] += 1
            if identity_and_basis and key in known and value.get('unit') == UNITS[key] and number_equal(value.get('value'), known[key]):
                row['correct_declared_claims'] += 1
                row['recovered_declared_fields'] += 1
        elif identity_and_basis and key in unknown and value.get('state') == 'unknown' and value.get('value') is None:
            row['preserved_unknown_fields'] += 1
    row['passed'] = (identity_and_basis and row['correct_declared_claims'] == len(known)
                     and row['declared_claims'] == len(known) and row['preserved_unknown_fields'] == len(unknown))
    return row


def assess(case, outcome):
    extraction = outcome.get('extraction')
    result = outcome.get('result')
    available = extraction is not None and result is not None
    preferred = extraction.get('preferred_id') if extraction else None
    eligible = (result or {}).get('eligible_candidate_ids', [])
    # This is the extractor's preference after the same closed binding policy.
    baseline_choice = preferred if preferred in eligible or preferred in ('none', 'clarify') else 'none'
    baseline = assess_choice(case, extraction, result, baseline_choice, available)
    status = (result or {}).get('selection_status')
    selector_available = available and status == 'completed'
    if status == 'skipped_no_eligible_candidates':
        selector_choice = baseline_choice
        policy_available = available
    else:
        selector_choice = (result or {}).get('choice')
        policy_available = selector_available
    selected = assess_choice(case, extraction, result, selector_choice, policy_available)
    return dict(id=case['id'], family=case['family'], layout=case['layout'], domain=case['domain'],
                comparison_case=case.get('comparison_case', case['id']),
                slice=case['slice'], reference_status=case['reference_status'],
                extractor=case.get('extractor', 'luna'), selection_enabled=case.get('selection', True),
                selector_route=case.get('selector', 'jev'),
                expected_answerable=case['gold']['outcome'] == 'selected',
                run_status=outcome.get('status', 'not_run'), extraction_completed=available,
                selector_completed=selector_available, selection_status=status,
                baseline=baseline, jev=selected)


def aggregate(rows, arm):
    scores = [r[arm] for r in rows]
    total = lambda name: sum(r[name] for r in scores)
    return dict(whole_case=fraction(total('passed'), len(scores)),
                answerable_case_success=fraction(sum(r[arm]['passed'] for r in rows if r['expected_answerable']),
                                                sum(r['expected_answerable'] for r in rows)),
                correct_abstention=fraction(sum(r[arm]['passed'] for r in rows if not r['expected_answerable']),
                                            sum(not r['expected_answerable'] for r in rows)),
                selected_case_count=total('selected'),
                availability=fraction(total('available'), len(scores)),
                declared_field_precision=fraction(total('correct_declared_claims'), total('declared_claims')),
                required_declared_field_recall=fraction(total('recovered_declared_fields'), total('required_declared_fields')),
                unknown_field_preservation=fraction(total('preserved_unknown_fields'), total('required_unknown_fields')),
                invented_unknown_fields=total('invented_unknown_fields'))


def provided_url_pipeline(acquisition, rows):
    planned = acquisition['planned_case_ids']
    captured = acquisition['captured_case_ids']
    excluded = [case['id'] for case in acquisition['excluded_cases']]
    eligibility = acquisition.get('source_eligibility', {})
    if (not planned or len(set(planned)) != len(planned) or len(set(captured)) != len(captured)
            or len(set(excluded)) != len(excluded) or set(captured) & set(excluded)
            or set(captured) | set(excluded) != set(planned)):
        raise ValueError('invalid acquisition denominator')
    if eligibility and (set(eligibility) != set(captured) or
                        any(not isinstance(value.get('eligible'), bool) for value in eligibility.values())):
        raise ValueError('incomplete source eligibility review')
    result = {}
    for route in sorted({row['extractor'] for row in rows}):
        group = [row for row in rows if row['extractor'] == route]
        if len(group) != len(captured) or {row['comparison_case'] for row in group} != set(captured):
            raise ValueError('extraction roster omitted a captured case')
        supports_query = lambda row: eligibility.get(row['comparison_case'], {}).get('eligible', True)
        result[route] = dict(acquisition=fraction(len(captured), len(planned)),
            successful_review_outcome=fraction(sum(row['baseline']['passed'] and supports_query(row) for row in group), len(planned)),
            usable_source_panel=fraction(sum(row['baseline']['passed'] and row['expected_answerable'] and supports_query(row) for row in group), len(planned)),
            source_eligibility=eligibility,
            acquisition_failures=acquisition['excluded_cases'],
            scope='Capture and extraction from preselected URLs, not discovery or independent acceptance.')
    return result


def report(cases, outcomes, requests, acquisition=None):
    ids = [c['id'] for c in cases]
    if len(ids) != len(set(ids)) or set(outcomes) - set(ids):
        raise ValueError('duplicate or unexpected case')
    rows = [assess(case, outcomes.get(case['id'], {})) for case in cases]
    grouped = {}
    for axis in ['slice', 'family', 'layout', 'domain', 'extractor']:
        groups = defaultdict(list)
        for row in rows:
            groups[row[axis]].append(row)
        grouped[axis] = {name: {arm: aggregate([r for r in group if arm == 'baseline' or r['selection_enabled']], arm)
                               for arm in ['baseline', 'jev']} for name, group in groups.items()}
    paired_rows = [r for r in rows if r['selection_enabled']]
    costs = [Decimal(str(r['reported_cost_usd'])) for r in requests if r.get('reported_cost_usd') is not None]
    if any(not c.is_finite() or c < 0 for c in costs):
        raise ValueError('invalid cost')
    result = dict(version='swift-food-proposal-evaluation-v1', cases=rows,
                baseline=aggregate(rows, 'baseline'), jev=aggregate(paired_rows, 'jev'), groups=grouped,
                paired=dict(denominator=len(paired_rows),
                            both_pass=sum(r['baseline']['passed'] and r['jev']['passed'] for r in paired_rows),
                            jev_only_pass=sum(not r['baseline']['passed'] and r['jev']['passed'] for r in paired_rows),
                            baseline_only_pass=sum(r['baseline']['passed'] and not r['jev']['passed'] for r in paired_rows),
                            neither_pass=sum(not r['baseline']['passed'] and not r['jev']['passed'] for r in paired_rows)),
                request_count=len(requests), reported_cost_usd=str(sum(costs, Decimal(0))),
                cost_coverage=fraction(len(costs), len(requests)),
                qualification='Agent-authored or previously exposed development cases; no independent acceptance or confidence calibration.',
                persistence_evidence='Separate Swift contract tests, not inferred from provider responses.',
                full_roster_denominator=True)
    result['selected'] = result['jev']
    result['selector_routes'] = sorted({r['selector_route'] for r in paired_rows})
    result['legacy_jev_key'] = 'Compatibility key for selected arm; actual route is selector_routes.'
    if acquisition is not None:
        result['provided_url_pipeline'] = provided_url_pipeline(acquisition, rows)
    return result


def main(run):
    root = Path(run)
    from frozen_run import verify, digest, verify_output_hashes
    plan = verify(root.resolve())
    if digest(Path(__file__)) != plan['snapshot_hashes']['snapshot/source/Tools/GenericFoodProposalEvaluation/evaluate.py']:
        raise ValueError('use the frozen evaluator')
    if any(c['task'] != 'provided_document' for c in plan['cases']):
        raise ValueError('discovery needs separately reviewed source coverage, not nutrient scoring')
    outcomes, requests = {}, []
    for case in plan['cases']:
        path = root / 'results' / case['id']
        outcome = {}
        for key in ['extraction', 'result']:
            file = path / (key + '.json')
            if file.exists():
                outcome[key] = json.loads(file.read_text())
        receipt = path / 'receipt.json'
        if receipt.exists():
            requests.extend(json.loads(receipt.read_text())['requests'])
        status = path / 'run-status.json'
        if status.exists():
            run_status = json.loads(status.read_text())
            if plan.get('output_hashes_required', False):
                verify_output_hashes(path, run_status)
            outcome['status'] = run_status['status']
        elif plan.get('output_hashes_required', False) and path.exists():
            raise ValueError('attempted case has no completed output receipt')
        outcomes[case['id']] = outcome
    result = report(plan['cases'], outcomes, requests, plan.get('roster_metadata', {}).get('acquisition'))
    result['output_integrity'] = 'verified_against_run_receipt' if plan.get('output_hashes_required') else 'not_recorded_legacy_run'
    (root / 'score.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: result[k] for k in ['baseline', 'jev', 'paired', 'request_count', 'reported_cost_usd', 'cost_coverage']}))


if __name__ == '__main__':
    main(sys.argv[1])
