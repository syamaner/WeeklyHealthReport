import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import lead_selection_experiment as e


def response(choice=None, cost=0.001, **changes):
    value={'model':e.MODEL,'provider':e.PROVIDER,'usage':{'cost':cost},'choices':[
        {'finish_reason':'stop','message':{'content':json.dumps(choice or {
            'version':e.VERSION,'decision':'select','selected_index':0,
            'reason':'exact_product_primary_lead'})}}]}
    value.update(changes)
    return json.dumps(value).encode()


class ContractTests(unittest.TestCase):
    def test_metadata_excludes_synthesized_answer_and_gold(self):
        supplied=e.metadata('food',[{'url':'https://example.com/food','title':'food',
                                    'cited_text':None,'response_text':'secret answer','gold':'hidden'}])
        body=e.request_body(supplied)
        self.assertNotIn('plugins',body);self.assertNotIn('tools',body)
        self.assertEqual(set(supplied['leads'][0]),{'index','url','title','excerpt'})
        self.assertEqual(body['provider'],{'only':['azure'],'order':['azure'],
            'allow_fallbacks':False,'require_parameters':True,'data_collection':'deny','zdr':True})
        self.assertEqual(body['reasoning'],{'effort':'none'})

    def test_index_and_abstention_constraints(self):
        for index in [-2,3,True,0.0,'0']:
            with self.assertRaises(ValueError):e.decode(response({'version':e.VERSION,
                'decision':'select','selected_index':index,'reason':'exact_product_primary_lead'}),3)
        with self.assertRaises(ValueError):e.decode(response({'version':e.VERSION,
            'decision':'abstain','selected_index':0,'reason':'no_eligible_primary_lead'}),3)
        abstain={'version':e.VERSION,'decision':'abstain','selected_index':-1,
                 'reason':'insufficient_metadata'}
        self.assertEqual(e.decode(response(abstain),3),abstain)

    def test_route_finish_and_unexpected_tools(self):
        for changes in [{'provider':'OpenAI'},{'model':e.MODEL+'-other'},
                        {'choices':[{'finish_reason':'length','message':{}}]}]:
            with self.assertRaises(ValueError):e.decode(response(**changes),3)
        obj=json.loads(response());obj['choices'][0]['message']['tool_calls']=[]
        with self.assertRaises(ValueError):e.decode(json.dumps(obj),3)

    def test_duplicate_keys_extra_keys_and_nonfinite(self):
        with self.assertRaises(ValueError):e.strict_load('{"x":1,"x":2}')
        with self.assertRaises(ValueError):e.strict_load('{"x":NaN}')
        c={'version':e.VERSION,'decision':'select','selected_index':0,
           'reason':'exact_product_primary_lead','url':'https://invented.test'}
        with self.assertRaises(ValueError):e.decode(response(c),3)

    def test_cost_unknown_not_zero(self):
        for v in [None,True,-1,'NaN','Infinity',{},'bad']:
            self.assertIsNone(e.reported_cost(response(cost=v)))
        self.assertEqual(e.reported_cost(response(cost=0)),'0')
        self.assertIsNone(e.reported_cost(b'{broken'))


class RunTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.loader=self.root/'private_loader.py';self.loader.write_text('# synthetic loader, never executed')
        self.mock=patch.object(e,'LOADER',self.loader);self.mock.start()
        self.discovery=self.root/'discovery';self.discovery.mkdir();cases=[];expected=[]
        for n in range(6):
            cid='case-'+str(n);q='food '+str(n);cases.append({'id':cid,'query':q})
            folder=self.discovery/'results'/cid;folder.mkdir(parents=True)
            leads=[{'url':'https://example.com/'+str(i),'title':'food','cited_text':'public'} for i in range(3)]
            e.write(folder/'discovery.json',{'query':q,'leads':leads,'response_text':'not supplied'})
            expected.append({'id':cid,'query':q,'eligible_indices':[0],
                'native_leads_sha256':hashlib.sha256(json.dumps(leads,ensure_ascii=False,sort_keys=True).encode()).hexdigest()})
        e.write(self.discovery/'plan.json',{'cases':cases})
        (self.discovery/'plan.sha256').write_text(e.digest(self.discovery/'plan.json'))
        self.expectations=self.root/'expectations.json';e.write(self.expectations,
            {'selection_predictions_seen':False,'cases':expected})
        self.runroot=self.root/'run';e.freeze(self.discovery,self.expectations,self.runroot)

    def tearDown(self):
        self.mock.stop();self.temp.cleanup()

    def test_snapshot_tamper_stops_before_key_or_transport(self):
        (self.runroot/'snapshot/case-0-request.json').write_text('{}')
        with self.assertRaises(ValueError):e.run(self.runroot,key_loader=lambda:self.fail('loaded credential'))

    def test_six_requests_only_and_rerun_forbidden(self):
        calls=[]
        def send(body,key,timeout):calls.append(body);return 200,response()
        summary=e.run(self.runroot,send,lambda:'synthetic',lambda _:None)
        self.assertEqual(len(calls),6);self.assertEqual(summary['correct_choices'],6)
        self.assertEqual(summary['reported_cost_usd'],'0.006')
        with self.assertRaises(FileExistsError):e.run(self.runroot,send,lambda:self.fail('retry loaded key'))
        self.assertEqual(len(calls),6)

    def test_unknown_cost_stops_after_first_and_retains_raw(self):
        calls=[]
        def send(*args):calls.append(1);return 200,response(cost=None)
        result=e.run(self.runroot,send,lambda:'synthetic',lambda _:None)
        self.assertEqual(len(calls),1);self.assertEqual(result['status'],'stopped_unknown_cost')
        self.assertEqual(result['not_attempted'],5)
        self.assertTrue((self.runroot/'results/case-0/response.bin').exists())

    def test_transport_failure_consumes_attempt_and_stops(self):
        def send(*args):raise TimeoutError('no exception details should be persisted')
        result=e.run(self.runroot,send,lambda:'synthetic',lambda _:None)
        self.assertEqual(result['request_count'],1);self.assertFalse(result['all_request_costs_known'])
        self.assertTrue((self.runroot/'results/case-0/attempt.json').exists())
        self.assertNotIn('exception details',(self.runroot/'summary.json').read_text())

    def test_known_cost_wrong_route_stops_without_relaxing_validation(self):
        result=e.run(self.runroot,lambda *args:(200,response(provider='OpenAI')),lambda:'synthetic',lambda _:None)
        self.assertEqual(result['status'],'stopped_invalid_response');self.assertEqual(result['request_count'],1)

    def test_reported_cost_threshold_stops_later_cases(self):
        result=e.run(self.runroot,lambda *args:(200,response(cost=.06)),lambda:'synthetic',lambda _:None)
        self.assertEqual(result['status'],'stopped_reported_cost');self.assertEqual(result['request_count'],1)

    def test_prospective_expected_hash_prevents_changed_leads(self):
        f=self.discovery/'results/case-0/discovery.json';x=json.loads(f.read_text());x['leads'][0]['title']='changed';e.write(f,x)
        with self.assertRaises(ValueError):e.freeze(self.discovery,self.expectations,self.root/'second')


if __name__=='__main__':unittest.main()
