import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import evaluate as ev
import collect

class EvaluationTests(unittest.TestCase):
    def setUp(self):
        self.corpus=ev.load(ev.ROOT/'corpus-v1.json')
        self.schema=ev.load(ev.ROOT/'response-schema-v1.json')
        self.case=self.corpus['cases'][0]
    def answer(self,case=None):
        case=case or self.case
        gold=copy.deepcopy(case['gold'])
        gold['nutrients']=[dict(id=n,**f,evidence='fixture value' if f['state']!='unknown' else '') for n,f in gold['nutrients'].items()]
        gold['reason']='fixture'
        return gold
    def test_frozen_contract(self):
        corpus,contract=ev.verify()
        self.assertEqual(len(ev.plan(corpus)),contract['planned_requests'])
    def test_reference_roundtrip(self):
        for case in self.corpus['cases']:
            self.assertTrue(ev.score(case,self.answer(case),self.schema)['passed'],case['id'])
    def test_unit_basis_preparation_and_unknown_cannot_silently_change(self):
        for key,value in [('basis_unit','ml'),('basis_amount',250),('preparation','frozen')]:
            answer=self.answer();answer[key]=value
            self.assertFalse(ev.score(self.case,answer,self.schema)['passed'])
        answer=self.answer();answer['nutrients'][6].update(state='declared',value=0,unit='g',operator='=',evidence='invented zero')
        self.assertEqual(ev.score(self.case,answer,self.schema)['invented_fields'],['fibre'])
    def test_bound_cannot_become_exact(self):
        case=self.corpus['cases'][6];answer=self.answer(case)
        answer['nutrients'][2]['operator']='='
        self.assertFalse(ev.score(case,answer,self.schema)['passed'])
    def test_missing_extra_duplicate_and_boolean_fail(self):
        for change in ('missing','extra','duplicate','boolean'):
            a=self.answer()
            if change=='missing': a['nutrients'].pop()
            if change=='extra': a['extra']='bad'
            if change=='duplicate': a['nutrients'].append(a['nutrients'][0])
            if change=='boolean': a['nutrients'][0]['value']=True
            self.assertFalse(ev.score(self.case,a,self.schema)['passed'],change)
    def test_abstention_values_fail(self):
        case=self.corpus['cases'][1]
        self.assertTrue(ev.score(case,self.answer(),self.schema)['values_on_abstention'])
    def test_request_omits_gold_and_url_arm_omits_panel(self):
        source=self.corpus['sources'][self.case['source']]
        body=collect.request(self.case,source,'url','instruction',self.schema)
        data=json.loads(body['input'])
        self.assertNotIn('gold',data);self.assertNotIn('evidence_panel',data)
        self.assertEqual(body['tools'],[{'type':'url_context'}])
        holdout=next(c for c in self.corpus['cases'] if c['split']=='holdout')
        with self.assertRaises(ValueError): collect.request(holdout,source,'panel','instruction',self.schema)
    def test_incomplete_report_keeps_denominator(self):
        report=ev.report(self.corpus,dict(results=[]),self.schema)
        self.assertEqual(report['planned'],len(ev.plan(self.corpus)))
        self.assertEqual(report['completed'],0)
    def test_private_journal_before_call_and_stop(self):
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'run'; calls=[]
            def transport(body,key):
                calls.append(body)
                journal=ev.load(out/'attempts.json')
                self.assertEqual(journal['attempts'][-1]['outcome'],'started')
                self.assertEqual((out/'replay.json').stat().st_mode & 0o777,0o600)
                raise TimeoutError()
            collect.capture(self.corpus,{},out,'synthetic-secret-not-real',20,transport)
            self.assertEqual(len(calls),1)
            self.assertEqual(ev.load(out/'attempts.json')['attempts'][0]['outcome'],'timeout')
    def test_cooked_weight_scales_and_cup_to_mass_refuses(self):
        for id in ('n15','n16'):
            c=next(c for c in self.corpus['cases'] if c['id']==id)
            self.assertEqual(ev.scale_portion(self.answer(c),c['consumed']),c['expected_portion'])
        c=next(c for c in self.corpus['cases'] if c['id']=='n14')
        self.assertIsNone(ev.scale_portion(self.answer(c),c['consumed']))
    def test_projection_discards_secrets_reasoning_and_ids(self):
        reply=dict(status='completed',id='DO_NOT_RETAIN',usage=dict(input_tokens=5,total_tokens=8),steps=[
            dict(type='thought',content='DO_NOT_RETAIN'),
            dict(type='url_context_result',result=[dict(url='https://example.org/',status='success',text='DO_NOT_RETAIN')]),
            dict(type='model_output',content=[dict(type='text',text=json.dumps(self.answer()))])])
        projected=collect.project(reply)
        self.assertNotIn('DO_NOT_RETAIN',json.dumps(projected))
        self.assertEqual(projected['retrieval'][0]['status'],'success')
        reply['status']='incomplete'
        with self.assertRaises(ValueError): collect.project(reply)

if __name__=='__main__': unittest.main()
