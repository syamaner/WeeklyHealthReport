"""Pure preflight policy. No execution, label mutation or quality scoring."""
import math

SCHEMA = 'prospective-nutrition-collection-v1'
MINIMA = {'plain_generic': 12, 'preparation_form': 10, 'count_fraction': 10,
          'mass_volume': 8, 'exact_source_gap': 8, 'ambiguity_mixture': 6,
          'non_food_invalid': 6}


def assess(collection, freeze, integrity):
    blockers, invalid = [], []
    counts = {key: 0 for key in MINIMA}
    if not isinstance(collection, dict) or not isinstance(freeze, dict):
        return {'status': 'invalid', 'errors': ['invalid_document'], 'blockers': [],
                'acceptance': 'not_run', 'metrics': None}
    if collection.get('schema') != SCHEMA:
        invalid.append('collection_schema')
    rows = collection.get('cases')
    if not isinstance(rows, list) or any(not isinstance(r, dict) for r in rows):
        invalid.append('invalid_roster')
        rows = []
    ids = [r.get('case_id') for r in rows]
    if any(not isinstance(x, str) or not x.strip() for x in ids):
        invalid.append('invalid_case_ids')
    elif len(set(ids)) != len(ids):
        invalid.append('duplicate_case_ids')
    groups = set()
    collected = referenced = 0
    for r in rows:
        cid = r.get('case_id') if isinstance(r.get('case_id'), str) else 'invalid-id'
        text, group = r.get('original_input'), r.get('scenario_group')
        if not isinstance(text, str) or not text.strip():
            blockers.append({'case_id': cid, 'reason': 'input_missing'})
            continue
        collected += 1
        if not isinstance(group, str) or not group.strip():
            blockers.append({'case_id': cid, 'reason': 'scenario_group_missing'})
        elif group in groups:
            invalid.append('duplicate_scenario_group')
        else:
            groups.add(group)
            if r.get('primary_stratum') in counts:
                counts[r['primary_stratum']] += 1
            else:
                invalid.append('unknown_stratum')
        ref = r.get('reference')
        if not isinstance(ref, dict) or ref.get('answerability') not in {
                'answerable', 'needs_clarification', 'unsupported'}:
            blockers.append({'case_id': cid, 'reason': 'reference_unresolved'})
        elif not isinstance(ref.get('expected'), dict) or not ref['expected']:
            blockers.append({'case_id': cid, 'reason': 'expected_states_missing'})
        else:
            referenced += 1
        if not isinstance(r.get('intended_outcome'), str) or not r['intended_outcome'].strip():
            blockers.append({'case_id': cid, 'reason': 'intended_outcome_missing'})
        if not isinstance(r.get('reviewer'), str) or not r['reviewer'].strip():
            blockers.append({'case_id': cid, 'reason': 'reference_reviewer_missing'})
        if r.get('exposure') != 'prospective_unscored':
            blockers.append({'case_id': cid, 'reason': 'exposure_not_declared_prospective'})
        if r.get('overlap_reviewed') is not True:
            blockers.append({'case_id': cid, 'reason': 'overlap_audit_missing'})
    for key, minimum in MINIMA.items():
        if counts[key] < minimum:
            blockers.append({'reason': 'stratum_minimum_missing', 'stratum': key,
                             'observed': counts[key], 'required': minimum})
    if collection.get('status') != 'frozen_unscored':
        blockers.append({'reason': 'collection_not_declared_frozen_unscored'})
    if freeze.get('profile') != 'offline_nlp_retrieval':
        blockers.append({'reason': 'execution_profile_missing'})
    if not isinstance(freeze.get('scorer_versions'), dict) or not freeze['scorer_versions']:
        blockers.append({'reason': 'scorer_versions_missing'})
    if collection.get('references_reviewed_without_predictions') is not True:
        blockers.append({'reason': 'pre_prediction_reference_review_missing'})
    if collection.get('reference_review') != 'independent_human_reviewed':
        blockers.append({'reason': 'independent_review_missing'})
    if collection.get('inputs_authored_by') != 'human_after_implementation_freeze':
        blockers.append({'reason': 'prospective_human_input_provenance_missing'})
    if freeze.get('schema') != 'nutrition-acceptance-freeze-v1':
        invalid.append('freeze_schema')
    if freeze.get('collection_sha256') is None:
        blockers.append({'reason': 'collection_not_frozen'})
    if not integrity.get('collection_hash_matches', False) and freeze.get('collection_sha256') is not None:
        invalid.append('collection_hash_mismatch')
    for key in ('implementation', 'catalogue', 'metric_contract', 'readiness_policy'):
        if key not in integrity.get('verified_categories', []):
            blockers.append({'reason': 'pin_category_missing', 'category': key})
    invalid.extend(integrity.get('errors', []))
    thresholds = freeze.get('quality_thresholds')
    if not isinstance(thresholds, dict) or not thresholds:
        blockers.append({'reason': 'quality_thresholds_unratified'})
    else:
        # Preflight checks approval and bounded ratios, not their adequacy.
        for metric, rule in thresholds.items():
            if not isinstance(rule, dict):
                invalid.append('invalid_threshold'); continue
            value = rule.get('minimum')
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= 1:
                invalid.append('invalid_threshold')
            if not isinstance(rule.get('approved_by'), str) or not rule['approved_by'].strip():
                blockers.append({'reason': 'threshold_approval_missing', 'metric': metric})
        if not {'AI01_route_accuracy', 'AI01_quantity_accuracy', 'AI02_hit_at_5'} <= set(thresholds):
            blockers.append({'reason': 'required_quality_thresholds_missing'})
    return {'schema': 'nutrition-acceptance-readiness-report-v1',
            'status': 'invalid' if invalid else 'incomplete' if blockers else 'ready_for_execution',
            'acceptance': 'not_run', 'metrics': None, 'case_slots': len(rows),
            'collected_cases': collected, 'resolved_reference_cases': referenced,
            'distinct_groups': len(groups), 'strata': counts,
            'errors': sorted(set(invalid)), 'blockers': blockers,
            'limitations': ['Preflight does not prove semantic truth or reviewer independence.',
                           'No provider, runner, quality scorer, save or device stage executed.',
                           'Ready for execution never means acceptance passed.']}
