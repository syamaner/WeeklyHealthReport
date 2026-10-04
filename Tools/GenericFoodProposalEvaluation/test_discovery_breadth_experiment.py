import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import discovery_breadth_experiment as e


def body(query='food'):
    return dict(model=e.base.MODEL, stream=False, max_completion_tokens=1800,
                reasoning={'effort':'none'}, provider=copy.deepcopy(e.EXPECTED_PROVIDER),
                plugins=[{'id':'web','engine':'exa','max_results':3}],
                messages=[{'role':'system','content':'Frozen instruction at most three sources'},
                          {'role':'user','content':query}])


def response(count=5, cost=.01, **changes):
    v=dict(model=e.base.MODEL, provider=e.base.PROVIDER, usage={'cost':cost}, choices=[dict(
        finish_reason='stop', message=dict(content='not used for eligibility',annotations=[dict(
            type='url_citation',url_citation=dict(url='https://example.com/'+str(i),title='food',content='excerpt',start_index=0,end_index=0)) for i in range(count)]))])
    v.update(changes)
    return json.dumps(v).encode()


class ContractTests(unittest.TestCase):
    def test_pair_differs_only_in_breadth(self):
        original=body();a,b=e.paired_requests(original,'food')
        self.assertEqual(a,original);self.assertEqual(b['plugins'][0]['max_results'],5)
        b['plugins'][0]['max_results']=3;self.assertEqual(a,b)
        self.assertEqual(original['plugins'][0]['max_results'],3)

    def test_filters_seeded_url_rewrites_and_routing_changes_rejected(self):
        variants=[]
        for field,value in [('tools',[]),('model','other/model'),('max_completion_tokens',4000),('stream',True),('provider',{})]:
            v=body();v[field]=value;variants.append(v)
        v=body();v['plugins'][0]['include_domains']=['example.com'];variants.append(v)
        v=body();v['messages'][1]['content']='rewritten';variants.append(v)
        for v in variants:
            with self.assertRaises(ValueError):e.paired_requests(v,'food')

    def test_all_annotations_preserved_without_truncation_or_dedup(self):
        raw=json.loads(response(6));raw['choices'][0]['message']['annotations'][5]['url_citation']['url']='https://example.com/0'
        result=e.decode(json.dumps(raw));self.assertEqual(result['native_lead_count'],6)
        self.assertEqual(result['unique_url_count'],5)
        self.assertEqual([x['annotation_index'] for x in result['native_leads']],list(range(6)))
        self.assertEqual(result['native_leads'][0]['start_index'],0)

    def test_unsafe_first_lead_is_retained_and_flagged(self):
        raw=json.loads(response(2));raw['choices'][0]['message']['annotations'][0]['url_citation']['url']='http://example.com/unsafe'
        result=e.decode(json.dumps(raw));self.assertFalse(result['native_leads'][0]['https_header_safe'])
        self.assertEqual(result['native_lead_count'],2);self.assertEqual(result['unique_safe_https_url_count'],1)

    def test_route_truncation_duplicate_keys_and_tools_rejected(self):
        for changes in [{'provider':'OpenAI'},{'model':'other/model'}, {'choices':[dict(finish_reason='length',message={})]}]:
            with self.assertRaises(ValueError):e.decode(response(**changes))
        raw=json.loads(response());raw['choices'][0]['message']['tool_calls']=[]
        with self.assertRaises(ValueError):e.decode(json.dumps(raw))
        with self.assertRaises(ValueError):e.decode('{"provider":"Azure","provider":"Azure"}')


class RunTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.loader=self.root/'approved_loader.py';self.loader.write_text('# synthetic loader')
        self.mock=patch.object(e.base,'LOADER',self.loader);self.mock.start()
        self.discovery=self.root/'discovery';self.discovery.mkdir();cases=[]
        for n in range(6):
            cid='case-'+str(n);query='food '+str(n);cases.append(dict(id=cid,query=query))
            folder=self.discovery/'results'/cid;folder.mkdir(parents=True)
            e.base.write(folder/'request-1.json',body(query))
        e.base.write(self.discovery/'plan.json',dict(cases=cases))
        (self.discovery/'plan.sha256').write_text(e.base.digest(self.discovery/'plan.json'))
        self.criteria=self.root/'criteria.json';e.base.write(self.criteria,dict(new_search_results_seen=False,cases=cases))
        self.runroot=self.root/'run';e.freeze(self.discovery,self.criteria,self.runroot)

    def tearDown(self):
        self.mock.stop();self.tmp.cleanup()

    def test_twelve_requests_fixed_order_and_rerun_forbidden(self):
        calls=[]
        def send(b,*args):calls.append(b);return 200,response(b['plugins'][0]['max_results'])
        result=e.run(self.runroot,send,lambda:'synthetic-private-token',lambda _:None)
        self.assertEqual(len(calls),12);self.assertEqual(result['not_attempted'],0)
        self.assertEqual(result['reported_cost_usd'],'0.12')
        self.assertEqual([b['plugins'][0]['max_results'] for b in calls],[3,5]*6)
        with self.assertRaises(FileExistsError):e.run(self.runroot,send,lambda:self.fail('loaded key for retry'))

    def test_tampering_prevents_key_load_or_transport(self):
        (self.runroot/'snapshot/case-0-exa3-request.json').write_text('{}')
        with self.assertRaises(ValueError):e.run(self.runroot,key_loader=lambda:self.fail('loaded key'))

    def test_unknown_cost_stops_and_preserves_raw(self):
        result=e.run(self.runroot,lambda *args:(200,response(cost=None)),lambda:'synthetic-private-token',lambda _:None)
        self.assertEqual(result['request_count'],1);self.assertEqual(result['status'],'stopped_unknown_cost')
        self.assertEqual(result['not_attempted'],11)
        self.assertTrue((self.runroot/'results/case-0-exa3/response.bin').exists())

    def test_transport_failure_no_retry_or_exception_leak(self):
        def send(*args):raise TimeoutError('sensitive arbitrary exception')
        result=e.run(self.runroot,send,lambda:'synthetic-private-token',lambda _:None)
        self.assertEqual(result['request_count'],1)
        self.assertNotIn('sensitive',(self.runroot/'summary.json').read_text())
        self.assertTrue((self.runroot/'results/case-0-exa3/attempt.json').exists())

    def test_known_cost_invalid_route_stops(self):
        result=e.run(self.runroot,lambda *args:(200,response(provider='OpenAI')),lambda:'synthetic-private-token',lambda _:None)
        self.assertEqual(result['request_count'],1);self.assertEqual(result['status'],'stopped_invalid_response')

    def test_reported_per_request_stop(self):
        result=e.run(self.runroot,lambda *args:(200,response(cost=.05)),lambda:'synthetic-private-token',lambda _:None)
        self.assertEqual(result['request_count'],1);self.assertEqual(result['status'],'stopped_reported_cost')

    def test_secret_echo_not_written_to_disk(self):
        raw=response();raw=raw.replace(b'not used for eligibility',b'synthetic-private-token')
        result=e.run(self.runroot,lambda *args:(200,raw),lambda:'synthetic-private-token',lambda _:None)
        self.assertEqual(result['status'],'stopped_unknown_cost')
        self.assertFalse((self.runroot/'results/case-0-exa3/response.bin').exists())
        self.assertNotIn('synthetic-private-token',(self.runroot/'summary.json').read_text())

    def test_query_drift_rejected_at_freeze(self):
        v=json.loads(self.criteria.read_text());v['cases'][0]['query']='rewritten';e.base.write(self.criteria,v)
        with self.assertRaises(ValueError):e.freeze(self.discovery,self.criteria,self.root/'second')


if __name__=='__main__':unittest.main()
