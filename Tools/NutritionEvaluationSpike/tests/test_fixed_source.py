import copy
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fixed_source import extract, score, evaluate

# Independently authored synthetic panel. No personal/source fixture in Git.
RAW = b'<table><tr><th>Typical values</th><th>Per 100g</th><th>Per 30g serving</th></tr><tr><td>Protein</td><td>40g</td><td>12g</td></tr><tr><td>Salt</td><td>0.2g</td><td>0.06g</td></tr></table>'


def reference():
    import hashlib
    bases = []
    keys = ['energy_kj','energy_kcal','fat','saturates','carbohydrate','sugars','fibre','protein','salt','calcium','phosphorus','sodium']
    for col,amount,header,protein,salt in [(2,'100','Per 100g','40','0.2'),(3,'30','Per 30g serving','12','0.06')]:
        fields = {k:{'state':'unknown','value':None,'unit':None,'support':None} for k in keys}
        for key,label,value,row in [('protein','Protein',protein,2),('salt','Salt',salt,3)]:
            fields[key] = {'state':'declared','value':value,'unit':'g','support':{'table':1,'row':row,'column':col,'label':label,'cell':value+'g'}}
        bases.append({'amount':amount,'unit':'g','header':header,'table':1,'column':col,'nutrients':fields})
    return {'schema':'fixed-source-reference-v1','reference_quality':'synthetic','expected':{'schema':'fixed-source-nutrients-v1','source_sha256':hashlib.sha256(RAW).hexdigest(),'bases':bases,'scoop_mass_g':None}}


class FixedSource(unittest.TestCase):
    def test_adapter_matches_independent_reference(self):
        r = evaluate(reference(),RAW)
        self.assertEqual(r['metrics']['supported_fields'],{'correct':24,'total':24})
        self.assertEqual(r['metrics']['numeric_fields'],{'correct':4,'total':4})
        self.assertEqual(r['metrics']['scorer_faults_detected'],{'correct':6,'total':6})
        self.assertEqual(r['model_quality'],'not_run')

    def test_wrong_basis_has_numeric_credit_but_fails_supported_fields(self):
        p = extract(RAW);p['bases'][0]['amount']='30'
        r = score(reference(),p)
        self.assertEqual(r['numeric_fields']['correct'],4)
        self.assertEqual(r['supported_fields']['correct'],12)
        self.assertFalse(r['passed'])

    def test_duplicate_missing_extra_fields_and_source_mismatch_fail(self):
        for mode in ['duplicate_basis','missing','extra','source']:
            p=extract(RAW)
            if mode=='duplicate_basis':p['bases'][1]=copy.deepcopy(p['bases'][0])
            if mode=='missing':del p['bases'][0]['nutrients']['salt']
            if mode=='extra':p['bases'][0]['nutrients']['invented']={}
            if mode=='source':p['source_sha256']='other'
            self.assertFalse(score(reference(),p)['passed'])

    def test_unknown_zero_and_invented_scoop_are_rejected(self):
        p=extract(RAW);p['bases'][0]['nutrients']['sodium']['value']='0'
        self.assertFalse(score(reference(),p)['passed'])
        p=extract(RAW);p['scoop_mass_g']='30'
        self.assertIn('unsupported_scoop_conversion',score(reference(),p)['errors'])

    def test_ambiguous_ragged_merged_and_duplicate_rows_fail_closed(self):
        for raw in [RAW+RAW,RAW.replace(b'<td>40g</td>',b''),RAW.replace(b'<td>40g',b'<td colspan="2">40g'),RAW.replace(b'</table>',b'<tr><td>Protein</td><td>40g</td><td>12g</td></tr></table>')]:
            with self.assertRaises(ValueError):extract(raw)

    def test_script_table_not_source_and_direct_decimal_exact(self):
        self.assertEqual(extract(b'<script>'+RAW+b'</script>'+RAW)['bases'],extract(RAW)['bases'])
        p=extract(RAW);p['bases'][0]['nutrients']['protein']['value']='40.00001'
        self.assertFalse(score(reference(),p)['passed'])
        p['bases'][0]['nutrients']['protein']['value']='40.0'
        self.assertTrue(score(reference(),p)['passed'])

    def test_explicit_table_selection_is_required_for_duplicate_panels(self):
        self.assertEqual(extract(RAW + RAW, selected_table=1)['bases'], extract(RAW)['bases'])
        with self.assertRaises(ValueError): extract(RAW + RAW, selected_table=3)
        with self.assertRaises(ValueError): extract(RAW, selected_table=True)

    def test_changed_source_and_malformed_proposal_fail(self):
        with self.assertRaises(ValueError):evaluate(reference(),RAW+b'changed')
        self.assertFalse(score(reference(),{})['passed'])

if __name__=='__main__':unittest.main()
