import copy
import json
import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch

from evaluate import number_equal, report
from frozen_run import validate_cases, output_hashes, verify_output_hashes, cost_state, freeze


def fixture():
    case = dict(id='one', task='provided_document', query='Tofu', family='tofu', layout='text', domain='synthetic.example',
                slice='taiwan', reference_status='authored_synthetic',
                gold=dict(outcome='selected', allowed_names=['Tofu'], basis=dict(amount='100', unit='g'),
                          nutrients=dict(energy='80', protein='6', carbohydrate=None, fat=None, fibre=None, sodium=None)))
    candidate = dict(id='c1', name='Tofu', basis=dict(amount='100', unit='g'), nutrients=[
        dict(key=k, state='declared' if v else 'unknown', value=v, unit='kcal' if k == 'energy' else 'g')
        for k, v in case['gold']['nutrients'].items()])
    outcome = dict(status='completed', extraction=dict(preferred_id='c1', candidates=[candidate]),
                   result=dict(eligible_candidate_ids=['c1'], selection_status='completed', choice='c1'))
    return case, outcome


class EvaluationTests(unittest.TestCase):
    def testMalformedGoldStopsFreezeBeforeRuntimeOrCredentialLoaderAccess(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); case, _ = fixture()
            case['gold']['nutrients']['protein'] = True
            roster = root / 'roster.json'; roster.write_text(json.dumps(dict(cases=[case])))
            with patch('frozen_run.digest', side_effect=AssertionError('No file hashing before gold validation')):
                with self.assertRaisesRegex(ValueError, 'invalid reference number'):
                    freeze(roster, root / 'missing-runtime', root / 'run')
            self.assertFalse((root / 'run').exists())

    def testReferenceNumbersMustBeFiniteNonnegativeAndNotBoolean(self):
        for field in ['nutrient', 'basis', 'equivalent_basis']:
            for value in [True, False, '-1', 'NaN', 'Infinity', '-Infinity', 'not a number', {}, []]:
                with self.subTest(field=field, value=value):
                    case, _ = fixture()
                    if field == 'nutrient':
                        case['gold']['nutrients']['protein'] = value
                    elif field == 'basis':
                        case['gold']['basis']['amount'] = value
                    else:
                        case['gold']['allowed_equivalent_bases'] = [dict(amount=value, unit='serving')]
                    with self.assertRaises(ValueError): validate_cases([case])
        case, _ = fixture(); case['gold']['nutrients']['protein'] = '0'
        validate_cases([case])
        case['gold']['basis']['amount'] = '0'
        with self.assertRaises(ValueError): validate_cases([case])

    def testReferenceIdentitiesAndChoicesMustBeExplicitDistinctLists(self):
        for field in ['allowed_names', 'allowed_document_ids', 'allowed_choices']:
            for value in ['Tofu', [], [''], [' '], ['same', 'same'], [None], [True], {}]:
                with self.subTest(field=field, value=value):
                    case, _ = fixture()
                    if field == 'allowed_choices': case['gold'] = dict(outcome='abstain')
                    case['gold'][field] = value
                    with self.assertRaises(ValueError): validate_cases([case])
        case, _ = fixture()
        # Repeating the primary basis is redundant but does not change scoring.
        case['gold']['allowed_equivalent_bases'] = [dict(amount='100.0', unit='g')]
        validate_cases([case])
        case['gold']['allowed_equivalent_bases'] = [dict(amount='1', unit='serving')]
        validate_cases([case])

    def testResumeStopsForUnjournalledInterruptedAndChangedCostEvidence(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); (root / 'results').mkdir()
            self.assertTrue(cost_state(root)['all_request_costs_known'])
            folder = root / 'results/attempt'; folder.mkdir()
            self.assertFalse(cost_state(root)['all_request_costs_known'])
            self.assertEqual(cost_state(root)['unverified_cost_attempts'], ['attempt'])
            receipt = folder / 'receipt.json'
            receipt.write_text(json.dumps(dict(requests=[dict(reported_cost_usd='0.01')])))
            self.assertFalse(cost_state(root)['all_request_costs_known'], 'An interrupted case lacks its output completion receipt')
            (folder / 'run-status.json').write_text(json.dumps(dict(status='completed', output_hashes=output_hashes(folder))))
            self.assertTrue(cost_state(root)['all_request_costs_known'])
            self.assertEqual(cost_state(root)['known_reported_cost_usd'], '0.01')
            receipt.write_text(json.dumps(dict(requests=[dict(reported_cost_usd='0.001')])))
            with self.assertRaises(ValueError): cost_state(root)

    def testUnknownCostsAreDistinctFromUnverifiedAttemptCounts(self):
        for value in [None, True, -1, 'NaN', 'Infinity']:
            with tempfile.TemporaryDirectory() as temp:
                root = Path(temp); folder = root / 'results/attempt'; folder.mkdir(parents=True)
                (folder / 'receipt.json').write_text(json.dumps(dict(requests=[dict(reported_cost_usd=value)])))
                (folder / 'run-status.json').write_text(json.dumps(dict(status='failed', output_hashes=output_hashes(folder))))
                if value is None:
                    state = cost_state(root)
                    self.assertEqual(state['unknown_cost_requests'], 1)
                    self.assertEqual(state['unverified_cost_attempts'], [])
                    self.assertFalse(state['all_request_costs_known'])
                else:
                    with self.assertRaises(ValueError): cost_state(root)

    def testAbstainingFromWrongSourceCannotBecomeWorkflowSuccess(self):
        case, outcome = fixture()
        case['gold'] = dict(outcome='abstain', allowed_choices=['none', 'clarify'])
        outcome['extraction'] = dict(preferred_id='none', candidates=[])
        outcome['result'] = dict(eligible_candidate_ids=[], selection_status='skipped_no_eligible_candidates')
        acquisition = dict(planned_case_ids=['one'], captured_case_ids=['one'], excluded_cases=[],
                           source_eligibility={'one': dict(eligible=False, reason='Wrong market')})
        result = report([case], {'one': outcome}, [], acquisition)
        self.assertEqual(result['baseline']['whole_case']['numerator'], 1)
        self.assertEqual(result['provided_url_pipeline']['luna']['successful_review_outcome']['numerator'], 0)
        acquisition['source_eligibility']['one']['eligible'] = True
        result = report([case], {'one': outcome}, [], acquisition)
        self.assertEqual(result['provided_url_pipeline']['luna']['successful_review_outcome']['numerator'], 1)
        self.assertEqual(result['provided_url_pipeline']['luna']['usable_source_panel']['numerator'], 0)

    def testAcquisitionFailureRemainsInPreselectedURLDenominator(self):
        case, outcome = fixture()
        acquisition = dict(planned_case_ids=['one', 'oversized'], captured_case_ids=['one'],
                           excluded_cases=[dict(id='oversized', status='failed', closed_error='capture_responseTooLarge')])
        result = report([case], {'one': outcome}, [], acquisition)['provided_url_pipeline']['luna']
        self.assertEqual(result['acquisition']['rate'], 0.5)
        self.assertEqual(result['successful_review_outcome']['denominator'], 2)
        self.assertEqual(result['usable_source_panel']['numerator'], 1)
        self.assertEqual(result['acquisition_failures'][0]['id'], 'oversized')
        missing = copy.deepcopy(acquisition); missing['captured_case_ids'].append('unscored')
        missing['planned_case_ids'].append('unscored')
        with self.assertRaises(ValueError): report([case], {'one': outcome}, [], missing)
        duplicate = copy.deepcopy(acquisition); duplicate['excluded_cases'].append(duplicate['excluded_cases'][0])
        with self.assertRaises(ValueError): report([case], {'one': outcome}, [], duplicate)

    def testChangedDeletedAndAddedPredictionFilesInvalidateOutputReceipt(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            result = folder / 'result.json'; result.write_text('{}')
            status = dict(output_hashes=output_hashes(folder))
            verify_output_hashes(folder, status)
            result.write_text('{"changed":true}')
            with self.assertRaises(ValueError): verify_output_hashes(folder, status)
            result.unlink()
            with self.assertRaises(ValueError): verify_output_hashes(folder, status)
            result.write_text('{}'); (folder / 'extraction.json').write_text('{}')
            with self.assertRaises(ValueError): verify_output_hashes(folder, status)

    def testMatchingNameFromWrongDocumentStillFailsIdentity(self):
        case, outcome = fixture(); case['gold']['allowed_document_ids'] = ['target']
        outcome['extraction']['candidates'][0]['document_id'] = 'decoy'
        result = report([case], {'one': outcome}, [])
        self.assertFalse(result['cases'][0]['baseline']['identity_correct'])
        self.assertEqual(result['baseline']['declared_field_precision']['numerator'], 0)

    def testOnlyPredeclaredEquivalentBasisCanPass(self):
        case, outcome = fixture()
        case['gold']['allowed_equivalent_bases'] = [dict(amount='1', unit='serving')]
        outcome['extraction']['candidates'][0]['basis'] = dict(amount='1', unit='serving')
        self.assertTrue(report([case], {'one': outcome}, [])['cases'][0]['baseline']['passed'])
        outcome['extraction']['candidates'][0]['basis']['amount'] = '2'
        self.assertFalse(report([case], {'one': outcome}, [])['cases'][0]['baseline']['basis_correct'])

    def testDisabledSelectorIsNotScoredAsFailedComparison(self):
        case, outcome = fixture()
        case.update(extractor='qwen', selection=False)
        outcome['result']['selection_status'] = 'disabled_for_extractor_comparison'
        validate_cases([case])
        result = report([case], {'one': outcome}, [])
        self.assertEqual(result['baseline']['whole_case']['numerator'], 1)
        self.assertEqual(result['jev']['whole_case']['denominator'], 0)
        self.assertEqual(result['paired']['denominator'], 0)
        self.assertEqual(result['paired']['baseline_only_pass'], 0)
        self.assertEqual(result['groups']['extractor']['qwen']['baseline']['whole_case']['denominator'], 1)

    def testUnknownRouteAndNonbooleanSelectorSettingsFailBeforeSpend(self):
        for settings in [dict(extractor='unreviewed'), dict(selection='false'), dict(extractor='sol', selection=True)]:
            case, _ = fixture(); case.update(settings)
            with self.assertRaises(ValueError):
                validate_cases([case])

    def testMissingCaseRemainsInDenominators(self):
        case, outcome = fixture()
        second = copy.deepcopy(case); second['id'] = 'two'
        result = report([case, second], {'one': outcome}, [])
        self.assertEqual(result['baseline']['whole_case']['denominator'], 2)
        self.assertEqual(result['baseline']['whole_case']['numerator'], 1)
        self.assertEqual(result['baseline']['required_declared_field_recall']['denominator'], 4)
        self.assertIsNone(result['cost_coverage']['rate'])

    def testWrongFoodNumbersAreNotCorrectClaims(self):
        case, outcome = fixture()
        outcome['extraction']['candidates'][0]['name'] = 'Different food'
        result = report([case], {'one': outcome}, [])
        self.assertEqual(result['jev']['declared_field_precision']['rate'], 0)
        self.assertEqual(result['jev']['whole_case']['numerator'], 0)

    def testWrongBasisDoesNotCountAsCorrectNutrients(self):
        case, outcome = fixture()
        outcome['extraction']['candidates'][0]['basis']['unit'] = 'ml'
        result = report([case], {'one': outcome}, [])
        self.assertEqual(result['baseline']['required_declared_field_recall']['rate'], 0)

    def testInventedZeroForUnknownIsAnError(self):
        case, outcome = fixture()
        value = outcome['extraction']['candidates'][0]['nutrients'][-1]
        value.update(state='declared', value='0', unit='mg')
        result = report([case], {'one': outcome}, [])
        self.assertEqual(result['jev']['invented_unknown_fields'], 1)
        self.assertEqual(result['jev']['whole_case']['numerator'], 0)

    def testSelectorFailureDoesNotHideSuccessfulExtraction(self):
        case, outcome = fixture()
        outcome['result']['selection_status'] = 'failed'
        result = report([case], {'one': outcome}, [])
        self.assertEqual(result['paired']['baseline_only_pass'], 1)
        self.assertFalse(result['cases'][0]['selector_completed'])

    def testNoEligibleCandidateUsesAbstentionWithoutChargingSelectorCoverage(self):
        case, outcome = fixture()
        case['gold'] = dict(outcome='abstain', allowed_choices=['none', 'clarify'])
        outcome['extraction'] = dict(preferred_id='none', candidates=[])
        outcome['result'] = dict(eligible_candidate_ids=[], selection_status='skipped_no_eligible_candidates')
        result = report([case], {'one': outcome}, [])
        self.assertEqual(result['paired']['both_pass'], 1)
        self.assertFalse(result['cases'][0]['selector_completed'])
        missing = report([case], {}, [])
        self.assertEqual(missing['jev']['whole_case']['numerator'], 0)

    def testUnknownCostIsNotZeroCost(self):
        case, outcome = fixture()
        result = report([case], {'one': outcome}, [dict(reported_cost_usd=0.003), dict(status='transport_failed_cost_unknown')])
        self.assertEqual(result['cost_coverage']['rate'], 0.5)
        self.assertEqual(result['reported_cost_usd'], '0.003')

    def testGroupsRetainSharedFamily(self):
        case, outcome = fixture()
        second = copy.deepcopy(case); second['id'] = 'two'
        result = report([case, second], {'one': outcome, 'two': outcome}, [])
        self.assertEqual(len(result['groups']['family']), 1)
        self.assertEqual(result['groups']['family']['tofu']['baseline']['whole_case']['denominator'], 2)

    def testDuplicateAndUnexpectedCasesFail(self):
        case, outcome = fixture()
        with self.assertRaises(ValueError):
            report([case, case], {}, [])
        with self.assertRaises(ValueError):
            report([case], {'unexpected': outcome}, [])

    def testDecimalEqualityIsExactAndRejectsBooleanOrNonfinite(self):
        self.assertTrue(number_equal('6.00', '6'))
        for value in [True, False, 'NaN', 'Infinity', None]:
            self.assertFalse(number_equal(value, 1))
        self.assertFalse(number_equal('6.1', '6'))

    def testFreezeRequiresCompleteGoldAndSafeIdentifiers(self):
        case, _ = fixture()
        validate_cases([case])
        case['gold']['nutrients'].pop('sodium')
        with self.assertRaises(ValueError):
            validate_cases([case])
        case, _ = fixture(); case['id'] = '../other'
        with self.assertRaises(ValueError):
            validate_cases([case])


if __name__ == '__main__':
    unittest.main()
