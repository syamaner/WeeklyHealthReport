import copy,json,sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from linked import score
from current_report import compose, attach_linked
from test_current_profile import fixture


def examples():
    ref=json.loads((Path(__file__).resolve().parents[1]/'linked-reference-v3.json').read_text())
    return ref,[dict(case_id=c['case_id'],**copy.deepcopy(c['expected'])) for c in ref['cases']]


class Linked(unittest.TestCase):
    def test_success_is_scoped_and_keeps_overall_incomplete(self):
        ref,rows=examples();r=attach_linked(compose(*fixture()),score(ref,rows))
        self.assertEqual(r['decision'],'incomplete')
        self.assertEqual(r['scorecards']['linked_query_outcomes']['backend'],'cofid')
        self.assertEqual(r['scorecards']['linked_query_outcomes']['model_quality'],'not_run')

    def test_wrong_parsed_amount_keeps_stage_and_outcome_failure_separate_from_block(self):
        ref,rows=examples();next(r for r in rows if r['case_id']=='egg-count')['parsed_quantity']=1
        r=score(ref,rows)
        self.assertEqual(r['metrics']['linked_safeguards']['correct'],7)
        self.assertEqual(r['stage_metrics']['parser']['correct'],8)
        self.assertEqual(attach_linked(compose(*fixture()),r)['decision'],'fail_linked_journeys')

    def test_missing_selection_cannot_be_replaced_by_first_match(self):
        ref,rows=examples();rows[0]['selected_record']='other'
        r=score(ref,rows)
        self.assertIn('retrieval',r['details'][0]['stage_failures'])
        self.assertFalse(r['passed_exercised_contract'])

    def test_nutrient_unknown_as_zero_and_wrong_subtotal_are_detected(self):
        for mode in ['zero','wrong','bool']:
            ref,rows=examples()
            if mode=='zero':next(t for t in rows[0]['totals'] if t['key']=='caffeine')['known']=0
            if mode=='wrong':next(t for t in rows[1]['totals'] if t['key']=='protein')['known']=0.6
            if mode=='bool':rows[0]['totals'][0]['incomplete']=False
            self.assertIn('daily_projection',score(ref,rows)['details'][0 if mode!='wrong' else 1]['stage_failures'])

    def test_mass_water_cannot_become_volume_and_generic_flags_cannot_disappear(self):
        for mode in ['water','estimate']:
            ref,rows=examples()
            if mode=='water': next(t for t in rows[0]['totals'] if t['key']=='water').update(known=85.5,incomplete=0)
            else: rows[0]['totals'][0]['estimate']=False
            self.assertIn('daily_projection',score(ref,rows)['details'][0]['stage_failures'])

    def test_admission_without_acceptance_or_unexpected_error_fails_safeguard(self):
        for mode in ['accepted','operational']:
            ref,rows=examples()
            if mode=='accepted':rows[0]['preaccept_blocked']=False
            else:next(r for r in rows if r['case_id']=='egg-count')['error']='databaseFailure'
            self.assertEqual(attach_linked(compose(*fixture()),score(ref,rows))['decision'],'fail_exercised_safeguards')

    def test_block_all_missing_duplicate_extra_and_malformed_profiles_cannot_pass(self):
        ref,rows=examples()
        for row in rows:row['validation']='blocked'
        self.assertEqual(score(ref,rows)['metrics']['linked_saves']['correct'],0)
        for mode in ['missing','duplicate','extra']:
            ref,rows=examples()
            if mode=='missing':rows.pop()
            if mode=='duplicate':rows[1]=rows[0]
            if mode=='extra':rows.append(dict(rows[0],case_id='unexpected'))
            with self.assertRaises(ValueError):score(ref,rows)
        self.assertEqual(attach_linked(compose(*fixture()),{})['integrity'],'invalid')

if __name__=='__main__':unittest.main()
