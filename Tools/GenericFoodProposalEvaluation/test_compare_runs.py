import copy
import unittest

from compare_runs import matched_cases, pair_outcomes, request_statistics
from evaluate import report
from test_evaluate import fixture


class MatchedComparisonTests(unittest.TestCase):
    def cases(self):
        left, outcome = fixture()
        left.update(selection=False, extractor='luna', comparison_case='same-food')
        right = copy.deepcopy(left)
        right.update(id='other-id', extractor='grok')
        return left, right, outcome

    def testOnlyRouteAndLocalIDCanDifferInMatchedCases(self):
        left, right, _ = self.cases()
        matched_cases([left], [right])
        for field, replacement in [('query', 'another query'), ('family', 'another family'),
                                   ('gold', dict(outcome='abstain'))]:
            changed = copy.deepcopy(right); changed[field] = replacement
            with self.assertRaises(ValueError): matched_cases([left], [changed])
        with self.assertRaises(ValueError): matched_cases([left], [])
        with self.assertRaises(ValueError): matched_cases([left], [right, right])

    def testMissingPredictionIsPairedFailureNotDropped(self):
        left, right, outcome = self.cases()
        a = report([left], {left['id']: outcome}, [])['cases']
        b = report([right], {}, [])['cases']
        result = pair_outcomes(a, b)
        self.assertEqual(result['planned_pairs'], 1)
        self.assertEqual(result['left_only_pass'], 1)
        self.assertFalse(result['groups']['family']['tofu']['right_all_pass'])
        with self.assertRaises(ValueError): pair_outcomes(a, [])

    def testUnknownCostAndTimingRemainUnknown(self):
        stats = request_statistics([dict(reported_cost_usd='0.1', latency_seconds=2), dict(status='failed')], 1)
        self.assertEqual(stats['known_reported_cost_usd'], '0.1')
        self.assertFalse(stats['cost_complete'])
        self.assertIsNone(stats['cost_per_usable_panel_usd'])
        self.assertEqual(stats['unknown_cost_requests'], 1)
        self.assertEqual(stats['latency_observed_requests'], 1)
        self.assertEqual(stats['median_request_seconds'], 2)
        self.assertIsNone(request_statistics([], 0)['p90_request_seconds'])

    def testCompleteCostUsesCorrectUsablePanelDenominator(self):
        stats = request_statistics([dict(reported_cost_usd='0.1', latency_seconds=2),
                                    dict(reported_cost_usd='0.2', latency_seconds=8)], 2)
        self.assertEqual(stats['cost_per_usable_panel_usd'], '0.15')
        self.assertEqual(stats['median_request_seconds'], 5)
        self.assertEqual(stats['p90_request_seconds'], 8)
        self.assertIsNone(request_statistics([dict(reported_cost_usd='0.1')], 0)['cost_per_usable_panel_usd'])
        for bad in [-1, float('nan'), True, '2']:
            with self.assertRaises(ValueError): request_statistics([dict(latency_seconds=bad)], 1)


if __name__ == '__main__':
    unittest.main()
