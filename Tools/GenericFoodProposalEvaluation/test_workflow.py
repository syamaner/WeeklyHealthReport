import copy
import unittest

from evaluate_workflow import join_cases


class WorkflowTests(unittest.TestCase):
    def fixture(self):
        search = [dict(id=str(i), query='Food ' + str(i)) for i in range(6)]
        leads = {r['id']: [dict(url='https://example.com/' + r['id'])] for r in search}
        captures = [dict(**r, url=leads[r['id']][0]['url']) for r in search]
        report = [dict(**r, status='captured' if r['id'] != '5' else 'failed') for r in captures]
        extracts = [dict(comparison_case=r['id'], query=r['query']) for r in search[:5]]
        scores = [dict(comparison_case=r['id'], expected_answerable=r['id'] not in ['3', '4'],
                       baseline=dict(passed=True, selected=r['id'] not in ['3', '4'], available=True)) for r in search[:5]]
        acquisition = dict(planned_case_ids=[r['id'] for r in search], captured_case_ids=[r['id'] for r in search[:5]],
            excluded_cases=[dict(id='5', status='failed')],
            source_eligibility={r['id']: dict(eligible=r['id'] != '4', reason='Predeclared review') for r in search[:5]})
        return [search, captures, report, extracts, scores, acquisition, leads]

    def testWrongSourceAbstentionIsSafeButDoesNotCountAsCoverage(self):
        result = join_cases(*self.fixture())
        self.assertEqual(result['original_query_count'], 6)
        expected = dict(search_available=6, captured=5, source_eligible=4, extraction_available=5,
                        correct_review_outcome=4, useful_panel=3, source_supported_abstention=1,
                        wrong_source_selection=0, wrong_source_safe_abstention=1)
        for key, value in expected.items():
            self.assertEqual(result['metrics'][key]['numerator'], value)
            self.assertEqual(result['metrics'][key]['denominator'], 6)

    def testWrongSourceSelectionRemainsAnError(self):
        args = self.fixture()
        args[4][4]['baseline'].update(passed=False, selected=True)
        result = join_cases(*args)
        self.assertEqual(result['metrics']['wrong_source_selection']['numerator'], 1)
        self.assertEqual(result['metrics']['wrong_source_safe_abstention']['numerator'], 0)
        self.assertEqual(result['metrics']['useful_panel']['numerator'], 3)

    def testStageSubstitutionAndDenominatorLossRejected(self):
        for change in ['omit_capture', 'omit_report', 'omit_extract', 'omit_score', 'changed_query',
                       'changed_extract_query', 'swapped_lead', 'changed_report_url', 'missing_review', 'drop_failure']:
            with self.subTest(change=change):
                args = copy.deepcopy(self.fixture())
                if change == 'omit_capture': args[1].pop()
                if change == 'omit_report': args[2].pop()
                if change == 'omit_extract': args[3].pop()
                if change == 'omit_score': args[4].pop()
                if change == 'changed_query': args[1][0]['query'] = 'Other food'
                if change == 'changed_extract_query': args[3][0]['query'] = 'Other food'
                if change == 'swapped_lead': args[1][0]['url'] = 'https://example.com/second'
                if change == 'changed_report_url': args[2][0]['url'] = 'https://example.com/second'
                if change == 'missing_review': args[5]['source_eligibility'].pop('0')
                if change == 'drop_failure': args[5]['excluded_cases'] = []
                with self.assertRaises(ValueError): join_cases(*args)

    def testUnavailablePredictionIsNotSuccessfulAbstention(self):
        args = self.fixture()
        args[4][3]['baseline'] = dict(passed=False, available=False, selected=False)
        result = join_cases(*args)
        self.assertEqual(result['metrics']['correct_review_outcome']['numerator'], 3)
        self.assertEqual(result['metrics']['source_supported_abstention']['numerator'], 0)

    def testPreferredAbstentionDoesNotHideOtherReviewableCandidates(self):
        args = self.fixture()
        args[4][4]['eligible_offer_count'] = 1
        result = join_cases(*args)
        self.assertEqual(result['metrics']['wrong_source_reviewable_offer']['numerator'], 1)
        self.assertEqual(result['metrics']['abstention_with_reviewable_offers']['numerator'], 1)
        self.assertEqual(result['metrics']['wrong_source_selection']['numerator'], 0)


if __name__ == '__main__':
    unittest.main()
