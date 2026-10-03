import copy
from dataclasses import replace
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from evidence_binding import Evidence,RequestEnvelope,resolve_record
import evaluate as ev
import candidate_v3 as v3
from resolve_discovery import evaluate_leads

class BindingTests(unittest.TestCase):
    def setUp(self):
        self.e=Evidence.selected('source','https://example.org/a','L1: panel')
        self.body=dict(input=json.dumps(dict(selected_source_id=self.e.source_id,evidence_sha256=self.e.content_sha256,selected_url=self.e.source_url,source_document=self.e.content)))
        self.request=RequestEnvelope.create(self.e,self.body)
    def test_metadata_is_bound_without_mutating_model(self):
        model=dict(status='extracted')
        result=self.request.bind(model)
        self.assertNotIn('source_url',model)
        self.assertEqual(result['extraction']['source_url'],self.e.source_url)
        self.assertEqual(result['provenance']['content_sha256'],self.e.content_sha256)
    def test_model_source_substitution_rejected(self):
        with self.assertRaises(ValueError):self.request.bind(dict(source_url='https://evil.example/'))
    def test_request_source_content_or_hash_tamper_rejected(self):
        for evidence in [replace(self.e,source_id='other-source'),replace(self.e,source_url='https://example.org/b'),replace(self.e,content='other'),replace(self.e,content_sha256='0'*64)]:
            with self.assertRaises(ValueError):RequestEnvelope.create(evidence,self.body)
        with self.assertRaises(ValueError):replace(self.request,request_json='{}').body()
    def test_resolution_fixture_results(self):
        results=evaluate_leads()
        self.assertTrue(all(r['passed'] for r in results))
        self.assertEqual(results[1]['result']['conflicts'],['protein'])
    def test_raw_preparation_and_duplicate_id_cannot_resolve(self):
        r=dict(family='f',id='1',name='Sirloin',preparation='raw',nutrients={})
        lead=dict(family='f',id='1',name='Sirloin',preparation='cooked',claims={})
        self.assertEqual(resolve_record(lead,[r])['status'],'rejected_identity')
        self.assertEqual(resolve_record(lead,[r,r])['status'],'unresolved')
    def test_changed_claim_unit_rejected(self):
        r=dict(family='f',id='1',name='Food',preparation='cooked',nutrients={'protein':dict(value=3,unit='g')})
        lead=dict(family='f',id='1',name='Food',preparation='cooked',claims={'protein':dict(value=3,unit='mg')})
        self.assertEqual(resolve_record(lead,[r])['status'],'conflicting_claims')
    def test_schema_excludes_source_and_request_excludes_gold(self):
        corpus,_=ev.verify();c=corpus['cases'][0]
        envelope=v3.request(c,corpus['sources'][c['source']],'panel')
        body=envelope.body()
        self.assertNotIn('source_url',body['response_format']['schema']['properties'])
        self.assertNotIn('gold',json.loads(body['input']))

if __name__=='__main__':unittest.main()
