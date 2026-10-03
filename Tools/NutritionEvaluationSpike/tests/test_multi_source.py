import copy,json,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from multi_source import score
from current_report import compose,attach_multi_source
from test_current_profile import fixture

def examples():
    ref=json.loads((Path(__file__).resolve().parents[1]/'multi-reference-v3.json').read_text())
    return ref,[dict(case_id=c['case_id'],**copy.deepcopy(c['expected'])) for c in ref['cases']]

class MultiSource(unittest.TestCase):
    def test_success_is_scoped_and_incomplete(self):
        ref,rows=examples();r=attach_multi_source(compose(*fixture()),score(ref,rows))
        self.assertEqual(r['decision'],'incomplete')
        self.assertEqual(r['scorecards']['multi_source_outcomes']['metrics']['all_journeys'],{'correct':14,'total':14,'value':1.0})
    def test_missing_duplicate_extra_case_invalidates_integrity(self):
        for mode in ['missing','duplicate','extra']:
            ref,rows=examples()
            if mode=='missing':rows.pop()
            elif mode=='duplicate':rows[1]=rows[0]
            else:rows.append(dict(rows[0],case_id='extra'))
            with self.assertRaises(ValueError):score(ref,rows)
        self.assertEqual(attach_multi_source(compose(*fixture()),{})['integrity'],'invalid')
    def test_block_everything_cannot_pass_outcomes(self):
        ref,rows=examples()
        for r in rows:r['validation']='blocked'
        self.assertEqual(score(ref,rows)['metrics']['saved_outcomes']['correct'],0)
    def test_source_substitution_and_lost_evidence_fail(self):
        for key,value in [('selected_record','wrong'),('original_preserved',False),('provenance_preserved',False),('reopen_preserved',False)]:
            ref,rows=examples();rows[0][key]=value
            self.assertFalse(score(ref,rows)['passed_exercised_contract'])
    def test_automatic_wrong_record_and_stale_conversions_fail_safeguard(self):
        for cid in ['milk-no-conversion-tap','milk-edited-conversion','milk-uht-no-offer','milk-usda-no-offer']:
            ref,rows=examples();row=next(r for r in rows if r['case_id']==cid)
            row.update(conversion_applied=True,edible_unit='g',edible_value=206)
            self.assertEqual(attach_multi_source(compose(*fixture()),score(ref,rows))['decision'],'fail_exercised_safeguards')
    def test_unknown_volume_nutrition_cannot_be_zero_or_fabricated(self):
        for amount in [0,100]:
            ref,rows=examples();row=next(r for r in rows if r['case_id']=='milk-no-conversion-tap');row['totals'][0]['known']=amount
            self.assertEqual(score(ref,rows)['metrics']['safeguards']['correct'],13)
    def test_ambiguous_description_cannot_prefill_source_basis_as_intake(self):
        ref,rows=examples();row=next(r for r in rows if r['case_id']=='milk-usda-unreviewed-amount')
        row.update(handoff_value=100,validation='saved',error='',operations=1,rows=1,edible_value=100,edible_unit='g')
        self.assertEqual(attach_multi_source(compose(*fixture()),score(ref,rows))['decision'],'fail_exercised_safeguards')

    def test_preacceptance_and_count_admission_fail(self):
        for mode in ['preaccept','count']:
            ref,rows=examples()
            if mode=='preaccept':rows[0]['preaccept_blocked']=False
            else:rows[-1].update(validation='saved',operations=1,rows=1)
            self.assertEqual(attach_multi_source(compose(*fixture()),score(ref,rows))['decision'],'fail_exercised_safeguards')
if __name__=='__main__':unittest.main()
