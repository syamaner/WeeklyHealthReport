import copy
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from current_report import compose, ratio, attach_fixed_source
from run_current import outside_git


def fixture():
    nlp = {'cases': 230, 'metrics': {k: {'correct': 230, 'total': 230} for k in ['query_route', 'query_quantity_eligible', 'list_quantity', 'list_explicit_preparation']}}
    summaries = [{'backend': b, 'path': p, 'all_reference_available_journey': {'hit1': 15, 'hit5': 15, 'denominator': 15}, 'execution_errors': 0} for b in ['cofid', 'usda', 'composite'] for p in ['query', 'list']]
    ids = ['synthetic-' + str(i) for i in range(30)]
    cases = [{'id': cid, 'backend': b, 'path': p} for cid in ids for b in ['cofid', 'usda', 'composite'] for p in ['query', 'list']]
    retrieval = {'summaries': summaries, 'cases': cases,
                 'confirmation_probe': {k: {'passed': 37, 'denominator': 37} for k in ['confirmationRemainsUnaccepted', 'originalEvidencePreserved', 'invalidSelectionRejected', 'amountClearingPreserved']},
                 'query_count_confirmation_probe': {'denominator': 11, 'undecided': 11, 'no_conversion': 11, 'mass_blocked': 11}}
    return nlp, retrieval, {'status': 'retained_bytes_verified'}, {'status': 'incomplete'}, {'all_required_commands_completed': True, 'expected_retrieval_ids': ids}


class CurrentProfile(unittest.TestCase):
    def test_component_success_cannot_pass_missing_whole_journey(self):
        r = compose(*fixture())
        self.assertEqual(r['decision'], 'incomplete')
        self.assertEqual(r['acceptance'], 'not_run')
        self.assertEqual(r['scorecards']['user_outcomes']['status'], 'not_run')
        self.assertIsNone(r['scorecards']['user_outcomes']['saved_entries'])

    def test_failed_count_safeguard_is_not_hidden_by_perfect_ai(self):
        args = fixture();args[1]['query_count_confirmation_probe']['mass_blocked'] = 10
        r = compose(*args)
        self.assertEqual(r['decision'], 'fail_exercised_safeguards')

    def test_known_safeguard_failure_survives_missing_or_malformed_ai(self):
        for mode in ['missing', 'malformed']:
            args = list(fixture())
            args[1]['query_count_confirmation_probe']['mass_blocked'] = 10
            if mode == 'missing': args[0] = None
            else: args[0]['metrics'] = {}
            r = compose(*args)
            self.assertEqual(r['decision'], 'fail_exercised_safeguards')
            self.assertEqual(r['integrity'], 'invalid')

    def test_missing_duplicate_or_wrong_case_invalidates(self):
        for mode in ['missing', 'duplicate', 'wrong']:
            args = fixture()
            if mode == 'missing': args[1]['cases'].pop()
            if mode == 'duplicate': args[1]['cases'][1] = args[1]['cases'][0]
            if mode == 'wrong': args[1]['cases'][0]['id'] = 'other'
            self.assertEqual(compose(*args)['integrity'], 'invalid')

    def test_missing_confirmation_check_or_probe_count_invalidates(self):
        args = fixture();args[1]['confirmation_probe'].pop('originalEvidencePreserved')
        self.assertEqual(compose(*args)['integrity'], 'invalid')
        args = fixture();args[1]['query_count_confirmation_probe']['denominator'] = 10
        self.assertEqual(compose(*args)['integrity'], 'invalid')

    def test_absent_suite_or_execution_is_incomplete(self):
        args = list(fixture());args[0] = None
        self.assertEqual(compose(*args)['integrity'], 'invalid')
        args = fixture();args[-1]['all_required_commands_completed'] = False
        self.assertEqual(compose(*args)['integrity'], 'invalid')

    def test_bad_source_hash_or_readiness_does_not_create_acceptance(self):
        args = fixture();args[2]['status'] = 'invalid'
        self.assertEqual(compose(*args)['integrity'], 'invalid')
        args = fixture();args[3]['status'] = 'ready_for_execution'
        self.assertEqual(compose(*args)['acceptance'], 'not_run')

    def test_zero_is_unavailable_invalid_counts_are_rejected(self):
        self.assertIsNone(ratio(0, 0)['value'])
        for values in [(2, 1), (-1, 1), (True, 1), (1, 0), (1.5, 2)]:
            with self.assertRaises(ValueError): ratio(*values)

    def test_fixed_source_success_retains_overall_gaps_and_failure_is_visible(self):
        from test_fixed_source import reference, RAW
        from fixed_source import evaluate
        fixed = evaluate(reference(), RAW)
        r = attach_fixed_source(compose(*fixture()), fixed)
        self.assertEqual(r['decision'], 'incomplete')
        self.assertIn('source_nutrient_fidelity', r['missing_profiles'])
        self.assertEqual(r['scorecards']['fixed_source_extraction']['app_admission'], 'not_run')
        fixed['metrics']['supported_fields']['correct'] -= 1
        self.assertEqual(attach_fixed_source(compose(*fixture()), fixed)['decision'], 'fail_fixed_source_contract')
        args = fixture(); args[1]['query_count_confirmation_probe']['mass_blocked'] = 10
        self.assertEqual(attach_fixed_source(compose(*args), fixed)['decision'], 'fail_exercised_safeguards')

    def test_malformed_fixed_source_is_invalid(self):
        self.assertEqual(attach_fixed_source(compose(*fixture()), {})['integrity'], 'invalid')

    def test_repo_paths_are_not_private_outputs(self):
        self.assertFalse(outside_git(Path(__file__).resolve()))


if __name__ == '__main__': unittest.main()
