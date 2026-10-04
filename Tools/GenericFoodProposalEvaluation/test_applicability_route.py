import unittest
from frozen_run import validate_cases

class ApplicabilityRouteTests(unittest.TestCase):
    def case(self, selector='applicability'):
        return dict(id='partial',task='provided_document',query='public food',family='fixture',layout='text',domain='example.com',slice='synthetic',reference_status='authored',extractor='grok',selection=True,selector=selector,
                    gold=dict(outcome='abstain',allowed_choices=['none','clarify']))
    def test_applicability_supports_grok_without_relabelling_jev(self):
        validate_cases([self.case()])
        with self.assertRaises(ValueError):validate_cases([self.case('jev')])
    def test_unknown_route_fails_before_credential_access(self):
        with self.assertRaises(ValueError):validate_cases([self.case('invented')])
