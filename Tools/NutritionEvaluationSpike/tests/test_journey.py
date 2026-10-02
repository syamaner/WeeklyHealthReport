import copy
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from journey import score
from current_report import compose, attach_journeys
from test_current_profile import fixture


def examples():
    ref=json.loads((Path(__file__).resolve().parents[1]/'journey-reference-v3.json').read_text())
    # Contract input, not production evidence. Production observations are a separate run.
    rows=[dict(case_id=c['case_id'],**copy.deepcopy(c['expected'])) for c in ref['cases']]
    return ref,rows


class Journeys(unittest.TestCase):
    def test_success_stays_synthetic_and_incomplete(self):
        ref,rows=examples();r=score(ref,rows)
        master=attach_journeys(compose(*fixture()),r)
        self.assertEqual(master['decision'],'incomplete')
        self.assertEqual(master['scorecards']['user_outcomes']['real_user_outcomes'],'not_run')
        self.assertIn('full_save_and_daily_totals_coverage',master['missing_profiles'])

    def test_block_everything_cannot_pass_outcomes(self):
        ref,rows=examples()
        for row in rows:
            row.update(validation='blocked',saved_versions=0,protein_known=None)
        r=score(ref,rows)
        self.assertEqual(r['metrics']['saved_outcomes']['correct'],0)
        self.assertEqual(attach_journeys(compose(*fixture()),r)['decision'],'fail_production_journeys')

    def test_invented_zero_wrong_scaled_total_edit_double_count_and_missing_provenance_fail(self):
        for case,key,value in [('grams-100','fat_known',0),('grams-50','protein_known',10),('quantity-edit','protein_known',30),('two-entries','provenance_preserved',False)]:
            ref,rows=examples();row=next(r for r in rows if r['case_id']==case);row[key]=value
            self.assertFalse(score(ref,rows)['passed_exercised_contract'])

    def test_unsupported_save_is_safeguard_failure(self):
        ref,rows=examples();row=next(r for r in rows if r['case_id']=='unsupported-count');row.update(validation='saved',saved_versions=1)
        r=attach_journeys(compose(*fixture()),score(ref,rows))
        self.assertEqual(r['decision'],'fail_exercised_safeguards')

    def test_operational_error_cannot_count_as_safe_blocking(self):
        ref,rows=examples();row=next(r for r in rows if r['case_id']=='unsupported-count');row['error']='databaseUnavailable'
        r=score(ref,rows)
        self.assertEqual(r['metrics']['blocked_outcomes']['correct'],2)
        self.assertEqual(attach_journeys(compose(*fixture()),r)['decision'],'fail_exercised_safeguards')

    def test_missing_duplicate_wrong_roster_and_empty_cannot_pass(self):
        for mode in ['missing','duplicate','wrong','empty']:
            ref,rows=examples()
            if mode=='missing':rows.pop()
            if mode=='duplicate':rows[1]=rows[0]
            if mode=='wrong':rows[0]['case_id']='unknown'
            if mode=='empty':ref['cases']=[];rows=[]
            with self.assertRaises(ValueError):score(ref,rows)

    def test_bool_counts_and_missing_key_are_not_valid(self):
        ref,rows=examples();rows[0]['saved_versions']=True
        self.assertFalse(score(ref,rows)['passed_exercised_contract'])
        ref,rows=examples();del rows[0]['protein_incomplete']
        self.assertFalse(score(ref,rows)['passed_exercised_contract'])

if __name__=='__main__':unittest.main()
