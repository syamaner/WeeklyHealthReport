"""Pure projection for the current offline development profile; no policy changes."""


def ratio(correct, total):
    if isinstance(correct, bool) or isinstance(total, bool) or not isinstance(correct, int) or not isinstance(total, int) or not 0 <= correct <= total:
        raise ValueError('invalid_metric_counts')
    return {'correct': correct, 'total': total, 'value': correct / total if total else None}


def known_safeguard_failure(retrieval):
    """Retain a valid observed failure even if another component is absent."""
    if not isinstance(retrieval, dict):
        return False
    checks = retrieval.get('confirmation_probe', {})
    tuples = []
    if isinstance(checks, dict):
        tuples += [(m.get('passed'), m.get('denominator')) for m in checks.values() if isinstance(m, dict)]
    counts = retrieval.get('query_count_confirmation_probe', {})
    if isinstance(counts, dict):
        tuples += [(counts.get(k), counts.get('denominator')) for k in ['undecided', 'no_conversion', 'mass_blocked']]
    for passed, total in tuples:
        try:
            m = ratio(passed, total)
            if m['total'] > 0 and m['correct'] < m['total']:
                return True
        except ValueError:
            pass
    return False


def compose(nlp, retrieval, sources, readiness, execution):
    errors = []
    observed_failure = known_safeguard_failure(retrieval)
    if not isinstance(nlp, dict) or not isinstance(retrieval, dict):
        return {'schema': 'current-nutrition-report-v8', 'decision': 'fail_exercised_safeguards' if observed_failure else 'incomplete',
                'integrity': 'invalid', 'errors': ['mandatory_suite_missing'],
                'acceptance': 'not_run', 'scorecards': {'application_safeguards': {'status': 'fail' if observed_failure else 'incomplete', 'metrics': {}}}, 'provider_calls': 0}
    ai = {'status': 'descriptive_development', 'implementation': 'deterministic_nlp_and_bundled_retrieval',
          'reference_quality': 'exposed_mixed_review_partial_annotations', 'metrics': {}}
    try:
        if nlp['cases'] != 230:
            errors.append('nlp_roster_count')
        for key in ['query_route', 'query_quantity_eligible', 'list_quantity', 'list_explicit_preparation']:
            m = nlp['metrics'][key]
            ai['metrics'][key] = ratio(m['correct'], m['total'])
        summaries = retrieval['summaries']
        if len(summaries) != 6 or {(s['backend'], s['path']) for s in summaries} != {(b, p) for b in ['cofid', 'usda', 'composite'] for p in ['query', 'list']}:
            errors.append('retrieval_summary_roster')
        cases = retrieval['cases']
        expected_ids = execution.get('expected_retrieval_ids', [])
        expected = {(cid, b, p) for cid in expected_ids for b in ['cofid', 'usda', 'composite'] for p in ['query', 'list']}
        if len(expected_ids) != 30 or len(cases) != 180 or {(r['id'], r['backend'], r['path']) for r in cases} != expected:
            errors.append('retrieval_case_roster')
        for s in summaries:
            m = s['all_reference_available_journey']
            key = s['backend'] + '_' + s['path']
            ai['metrics'][key + '_hit1'] = ratio(m['hit1'], m['denominator'])
            ai['metrics'][key + '_hit5'] = ratio(m['hit5'], m['denominator'])
            if m['denominator'] != 15:
                errors.append('retrieval_reference_denominator')
            if s['execution_errors']:
                errors.append('retrieval_execution_error')
        list_checks = retrieval['confirmation_probe']
        required = {'confirmationRemainsUnaccepted', 'originalEvidencePreserved', 'invalidSelectionRejected', 'amountClearingPreserved'}
        if set(list_checks) != required:
            errors.append('confirmation_checks_missing')
        safeguards = {'status': 'pass_exercised_probes', 'metrics': {}}
        for key, m in list_checks.items():
            safeguards['metrics'][key] = ratio(m['passed'], m['denominator'])
            if m['denominator'] != 37:
                errors.append('confirmation_probe_roster')
            if m['passed'] != m['denominator'] or not m['denominator']:
                safeguards['status'] = 'fail'
        counts = retrieval['query_count_confirmation_probe']
        for key in ['undecided', 'no_conversion', 'mass_blocked']:
            safeguards['metrics']['count_' + key] = ratio(counts[key], counts['denominator'])
            if counts[key] != counts['denominator'] or not counts['denominator']:
                safeguards['status'] = 'fail'
        if counts['denominator'] != 11:
            errors.append('count_probe_roster')
    except (KeyError, TypeError, ValueError) as error:
        errors.append('invalid_component_report')
        safeguards = {'status': 'fail' if observed_failure else 'incomplete', 'metrics': {}}
    if sources.get('status') != 'retained_bytes_verified':
        errors.append('retained_source_integrity')
    if not execution.get('all_required_commands_completed'):
        errors.append('mandatory_execution_incomplete')
    if errors:
        safeguards['status'] = 'incomplete' if safeguards['status'] != 'fail' else 'fail'
    decision = 'fail_exercised_safeguards' if safeguards['status'] == 'fail' else 'incomplete'
    return {'schema': 'current-nutrition-report-v8', 'decision': decision,
            'integrity': 'invalid' if errors else 'verified_current_profile',
            'errors': sorted(set(errors)), 'acceptance': 'not_run',
            'scorecards': {'AI_components': ai, 'application_safeguards': safeguards,
                          'user_outcomes': {'status': 'not_run', 'saved_entries': None, 'daily_totals': None}},
            'source_capture': sources, 'acceptance_readiness': readiness,
            'missing_profiles': ['provider_ai_and_judge_calibration', 'source_nutrient_fidelity',
                                 'receipt_ocr', 'voice_recognition', 'save_and_daily_totals',
                                 'independent_acceptance', 'physical_device_capture'],
            'provider_calls': 0, 'inference_cost': None,
            'cost_status': 'No inference requests; execution/subscription cost unmeasured.',
            'limitations': ['Descriptive development ratios are not acceptance thresholds.',
                            'Private query-route labels score the legacy parser diagnostic; current FoodQueryInterpretation discovery policy is exercised by linked journeys and application tests, not that private accuracy denominator.',
                            'Retained source hash integrity is not semantic nutrient verification.',
                            'Mechanical confirmation checks do not prove successful saved intake.',
                            'Missing profiles keep the overall decision incomplete.']}


def attach_fixed_source(report, fixed):
    """Separate single-source extraction and scorer checks from real app safeguards."""
    try:
        if fixed['schema'] != 'fixed-source-nutrients-v1' or fixed['source_cases'] != 1 or fixed['model_quality'] != 'not_run' or fixed['app_admission'] != 'not_run':
            raise ValueError('fixed_source_profile')
        metrics = {k: ratio(v['correct'], v['total']) for k, v in fixed['metrics'].items()}
        if set(metrics) != {'supported_fields','numeric_fields','whole_source_cases','scorer_faults_detected'} or metrics['whole_source_cases']['total'] != 1 or metrics['scorer_faults_detected']['total'] != 6 or metrics['supported_fields']['total'] == 0:
            raise ValueError('fixed_source_metrics')
        passed = all(m['total'] > 0 and m['correct'] == m['total'] for m in metrics.values())
        report['scorecards']['fixed_source_extraction'] = {'status': 'descriptive_fixed_evidence' if passed else 'fail_exercised_contract',
            'adapter': fixed['adapter'], 'reference_quality': fixed['reference_quality'], 'metrics': metrics,
            'model_quality': 'not_run', 'app_admission': 'not_run', 'scorer_faults_are_synthetic': True}
        if not passed and not report['decision'].startswith('fail'):
            report['decision'] = 'fail_fixed_source_contract'
        report['fixed_source_pins'] = fixed.get('pins', {})
        report['limitations'].append('One fixed-source evaluation adapter and synthetic scorer faults do not establish provider extraction quality or app admission.')
    except (KeyError, TypeError, ValueError):
        report['integrity'] = 'invalid'
        report.setdefault('errors', []).append('invalid_fixed_source_profile')
    return report


def attach_journeys(report, journeys):
    try:
        if journeys['schema'] != 'synthetic-save-daily-journeys-v1' or journeys['persistence'] != 'in_memory' or journeys['entry_boundary'] != 'populated_confirmation':
            raise ValueError('journey_profile')
        metrics = {k: ratio(v['correct'], v['total']) for k, v in journeys['metrics'].items()}
        required = {'all_journeys':13, 'saved_outcomes':10, 'blocked_outcomes':3}
        if set(metrics) != set(required) or any(metrics[k]['total'] != total for k, total in required.items()):
            raise ValueError('journey_metric_roster')
        passed = all(m['correct'] == m['total'] for m in metrics.values())
        report['scorecards']['user_outcomes'] = {'status': 'descriptive_synthetic_production_journeys' if passed else 'fail_exercised_journeys',
            'metrics': metrics, 'persistence': 'in_memory', 'entry_boundary': 'populated_confirmation',
            'independent_acceptance': 'not_run', 'real_user_outcomes': 'not_run'}
        safeguards = report['scorecards']['application_safeguards']
        safeguards['metrics']['synthetic_journey_blocking'] = metrics['blocked_outcomes']
        if metrics['blocked_outcomes']['correct'] != 3:
            safeguards['status'] = 'fail'
            report['decision'] = 'fail_exercised_safeguards'
        elif not passed and not report['decision'].startswith('fail'):
            report['decision'] = 'fail_production_journeys'
        report['missing_profiles'] = ['full_save_and_daily_totals_coverage' if k == 'save_and_daily_totals' else k for k in report['missing_profiles']]
        report['limitations'].append('Synthetic confirmed-input journeys exercise production save/projection with in-memory persistence; raw input, persistent storage, UI and complete family coverage remain unrun.')
    except (KeyError, TypeError, ValueError):
        report['integrity'] = 'invalid'
        report.setdefault('errors', []).append('invalid_journey_profile')
    return report


def attach_linked(report, linked):
    try:
        if linked['schema'] != 'synthetic-linked-report-v1' or linked['persistence'] != 'in_memory' or linked['entry_boundary'] != 'typed_query' or linked['backend'] != 'cofid':
            raise ValueError('linked_profile')
        metrics = {k: ratio(v['correct'], v['total']) for k,v in linked['metrics'].items()}
        required = {'all_linked_journeys':9,'linked_saves':4,'linked_blocks':3,'expected_stops':2,'linked_safeguards':7}
        if set(metrics) != set(required) or any(metrics[k]['total'] != total for k,total in required.items()):
            raise ValueError('linked_metric_roster')
        stages = {k:ratio(v['correct'],v['total']) for k,v in linked['stage_metrics'].items()}
        if {k:v['total'] for k,v in stages.items()} != {'parser':9,'retrieval':8,'handoff':7,'save':7,'daily_projection':7}:
            raise ValueError('linked_stage_roster')
        passed = all(m['correct'] == m['total'] for m in metrics.values())
        report['scorecards']['linked_query_outcomes'] = {'status':'descriptive_synthetic_linked_journeys' if passed else 'fail_exercised_linked_journeys',
            'metrics':{**metrics, **{'stage_'+k:v for k,v in stages.items()}}, 'backend':'cofid','persistence':'in_memory',
            'selection':'frozen_explicit_user_action','model_quality':'not_run','real_user_outcomes':'not_run'}
        report['scorecards']['application_safeguards']['metrics']['linked_query_safeguards'] = metrics['linked_safeguards']
        if metrics['linked_safeguards']['correct'] != 7:
            report['scorecards']['application_safeguards']['status']='fail'
            report['decision']='fail_exercised_safeguards'
        elif not passed and not report['decision'].startswith('fail'):
            report['decision']='fail_linked_journeys'
        report['limitations'].append('Linked typed-query scenarios use explicit frozen generic selection with CoFID only; composite/personal-library, pasted-list, UI, provider and persistent-storage continuity remain unrun.')
    except (KeyError,TypeError,ValueError):
        report['integrity']='invalid'
        report.setdefault('errors',[]).append('invalid_linked_profile')
    return report


def attach_lists(report,lists):
    try:
        if lists['schema']!='synthetic-list-report-v1' or lists['backend']!='cofid' or lists['persistence']!='in_memory':raise ValueError('list_profile')
        metrics={k:ratio(v['correct'],v['total']) for k,v in lists['metrics'].items()}
        required={'whole_lists':7,'line_outcomes':14,'line_parsing':14,'list_safeguards':14,'daily_totals':7}
        if set(metrics)!=set(required) or any(metrics[k]['total']!=n for k,n in required.items()):raise ValueError('list_metric_roster')
        passed=metrics['whole_lists']['correct']==7
        report['scorecards']['linked_list_outcomes']={'status':'descriptive_synthetic_list_journeys' if passed else 'fail_exercised_list_journeys',
            'metrics':metrics,'backend':'cofid','persistence':'in_memory','selection':'explicit_per_line_user_action',
            'model_quality':'not_run','real_user_outcomes':'not_run','safeguard_scope':'No save before acceptance; context/no-result lines write nothing. Earlier gates can mask quantity-specific checks.'}
        report['scorecards']['application_safeguards']['metrics']['list_preaccept_and_stop_safeguards']=metrics['list_safeguards']
        if metrics['list_safeguards']['correct']!=14:
            report['scorecards']['application_safeguards']['status']='fail';report['decision']='fail_exercised_safeguards'
        elif not passed and not report['decision'].startswith('fail'):report['decision']='fail_list_journeys'
        report['limitations'].append('Pasted-list evaluation uses production list service and in-memory CoFID route. Failed supported saves remain outcome failures; earlier identity blocking does not prove quantity-specific rejection.')
    except (KeyError,TypeError,ValueError):
        report['integrity']='invalid';report.setdefault('errors',[]).append('invalid_list_profile')
    return report


def attach_multi_source(report, multi):
    try:
        if multi['schema']!='synthetic-multi-source-report-v1' or multi['backend']!='cofid_usda_composite' or multi['persistence']!='in_memory':
            raise ValueError('multi_profile')
        metrics={k:ratio(v['correct'],v['total']) for k,v in multi['metrics'].items()}
        if {k:v['total'] for k,v in metrics.items()}!={'all_journeys':14,'saved_outcomes':12,'blocked_outcomes':2,'volume_outcomes':7,'safeguards':14}:
            raise ValueError('multi_roster')
        passed=all(m['correct']==m['total'] for m in metrics.values())
        report['scorecards']['multi_source_outcomes']={'status':'descriptive_synthetic_multi_source_journeys' if passed else 'fail_exercised_multi_source_journeys',
            'metrics':metrics,'backend':'cofid_usda_composite','persistence':'in_memory','model_quality':'not_run','independent_acceptance':'not_run'}
        report['scorecards']['application_safeguards']['metrics']['multi_source_safeguards']=metrics['safeguards']
        if metrics['safeguards']['correct']!=14:
            report['scorecards']['application_safeguards']['status']='fail';report['decision']='fail_exercised_safeguards'
        elif not passed and not report['decision'].startswith('fail'):report['decision']='fail_multi_source_journeys'
        report['limitations'].append('Multi-source journeys cover frozen explicit selections and milk conversion with synthetic in-memory saves. Unsupported volume remains saved as volume with unknown nutrient totals; it is never silently converted. UI, persistent-store continuity, live models and independent acceptance remain separate.')
    except (KeyError,TypeError,ValueError):
        report['integrity']='invalid';report.setdefault('errors',[]).append('invalid_multi_source_profile')
    return report
