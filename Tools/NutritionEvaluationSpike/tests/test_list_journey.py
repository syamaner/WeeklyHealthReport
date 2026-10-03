import copy,json,sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from list_journey import score
from current_report import compose,attach_lists
from test_current_profile import fixture


def examples():
    ref=json.loads((Path(__file__).resolve().parents[1]/'list-reference-v3.json').read_text())
    return ref,[dict(case_id=c['case_id'],**copy.deepcopy(c['expected'])) for c in ref['cases']]


class ListJourneys(unittest.TestCase):
    def test_success_stays_scoped_and_incomplete(self):
        ref,rows=examples();r=attach_lists(compose(*fixture()),score(ref,rows))
        self.assertEqual(r['decision'],'incomplete')
        self.assertEqual(r['scorecards']['linked_list_outcomes']['model_quality'],'not_run')

    def test_omitted_duplicate_wrong_and_merged_lines_fail_full_lists(self):
        for mode in ['omit','duplicate','wrong','merged']:
            ref,rows=examples()
            if mode=='omit':rows[0]['lines'].pop()
            if mode=='duplicate':rows[0]['lines'][2]=rows[0]['lines'][1]
            if mode=='wrong':rows[0]['lines'][1]['line']=8
            if mode=='merged':rows[0]['lines'][1]['query']='raw apples and boiled eggs'
            result=score(ref,rows)
            self.assertFalse(result['details'][0]['passed'])
            self.assertEqual(result['metrics']['line_outcomes']['total'],14)

    def test_context_admission_and_preaccept_write_fail_safeguard(self):
        for mode in ['context','acceptance']:
            ref,rows=examples()
            if mode=='context':rows[0]['lines'][0]['write_delta']=1
            else:rows[0]['lines'][1]['preaccept_blocked']=False
            self.assertEqual(attach_lists(compose(*fixture()),score(ref,rows))['decision'],'fail_exercised_safeguards')

    def test_unsupported_quantity_admitted_after_acceptance_fails_safeguard(self):
        ref,rows=examples();rows[2]['lines'][1].update(outcome='saved',error='',write_delta=1)
        self.assertEqual(attach_lists(compose(*fixture()),score(ref,rows))['decision'],'fail_exercised_safeguards')

    def test_supported_save_blocked_is_outcome_failure_not_safety_success(self):
        ref,rows=examples();line=rows[0]['lines'][1];line.update(outcome='blocked',error='unresolvedMandatoryIdentity',write_delta=0)
        r=score(ref,rows)
        self.assertEqual(r['metrics']['list_safeguards']['correct'],14)
        self.assertEqual(attach_lists(compose(*fixture()),r)['decision'],'fail_list_journeys')

    def test_unknown_zero_wrong_subtotal_and_duplicate_consumption_dedup_fail(self):
        for mode in ['unknown','total','dedup']:
            ref,rows=examples()
            if mode=='unknown':next(t for t in rows[0]['totals'] if t['key']=='water')['known']=0
            if mode=='total':next(t for t in rows[1]['totals'] if t['key']=='protein')['known']=0.6
            if mode=='dedup':rows[1]['saved_count']=1
            self.assertFalse(score(ref,rows)['passed_exercised_contract'])

    def test_partial_list_cannot_hide_outstanding_foods(self):
        ref,rows=examples();rows[2]['outstanding_food_lines']=0
        self.assertIn('outstanding_food_lines',score(ref,rows)['details'][2]['failures'])

    def test_missing_duplicate_case_and_invalid_report_fail_integrity(self):
        for mode in ['missing','duplicate']:
            ref,rows=examples()
            if mode=='missing':rows.pop()
            else:rows[1]=rows[0]
            with self.assertRaises(ValueError):score(ref,rows)
        self.assertEqual(attach_lists(compose(*fixture()),{})['integrity'],'invalid')

if __name__=='__main__':unittest.main()
