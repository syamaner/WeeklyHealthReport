import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import workflow_smoke as w

class SmokeTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        # Freeze hashes the loader code as runtime provenance, never credentials.
        # Offline contracts use synthetic code and must not depend on a host path.
        loader=self.root/'synthetic_private_loader.py'
        loader.write_text('def load_credentials(*args):\n    raise AssertionError("Offline fixture must never load credentials")\n')
        loader_patch=patch.object(w,'LOADER',loader);loader_patch.start();self.addCleanup(loader_patch.stop)
    def plan(self):
        return dict(cases=[dict(id=f'case-{i}',query=f'public food {i}')for i in range(6)],minimum_interval_seconds=0,
                    subset_denominator=6,subset_ids=[f'case-{i}'for i in range(6)],excluded_case_ids=[],maximum_requests=24,
                    executable='snapshot/runtime/FoodProposalProbe',harness_timeout_seconds=210,
                    reported_cost_stop_usd='1.50',per_case_reported_cost_stop_usd='0.05',
                    snapshot_hashes={'snapshot/source/Tools/GenericFoodProposalEvaluation/workflow_smoke.py':w.digest(w.__file__)})
    def receipt(self,folder,costs):
        folder.mkdir(exist_ok=True);rows=[]
        for i,c in enumerate(costs,1):
            w.write(folder/f'request-{i}.json',{'model':'synthetic','query':'public food'})
            row=dict(request=i,request_sha256=w.digest(folder/f'request-{i}.json'))
            if c is not None:
                w.write(folder/f'response-{i}.json',{'usage':{'cost':c}})
                row.update(reported_cost_usd=c,response_sha256=w.digest(folder/f'response-{i}.json'))
            rows.append(row)
        w.write(folder/'receipt.json',dict(requests=rows,maximum_requests=4,automatic_retries=0))
    def runner(self,costs=(.001,.001,.002),status='completed',error=None):
        def invoke(args,timeout,env):
            self.assertEqual(args[1],'review-smoke');self.assertEqual(timeout,210);self.assertNotIn('synthetic-secret',' '.join(args))
            folder=Path(args[-1]);self.receipt(folder,costs)
            w.write(folder/'result.json',dict(status=status,closed_error=error,review_elapsed_seconds=.02,allowed_confirmation_ids=['c1']if status=='completed'else[]))
            w.write(folder/'stages.json',dict(stages=[dict(stage='discovery',status='completed')]))
            return 0
        return invoke
    def run_mock(self,invoke):
        with patch.object(w,'verify',return_value=self.plan()):
            return w.run(self.root,invoke=invoke,environment=lambda:{'OPENROUTER_API_KEY':'synthetic-secret'},sleeper=lambda _:None)
    def test_six_real_entrypoint_invocations_preserve_denominator(self):
        result=self.run_mock(self.runner());self.assertEqual(result['request_count'],18);self.assertEqual(result['review_completed'],6)
        self.assertEqual(result['reviews_with_allowed_confirmation'],6);self.assertEqual(result['reported_cost_usd'],'0.024')
        self.assertFalse(result['numeric_accuracy_scored'])
    def test_source_abstentions_continue_and_are_not_confirmations(self):
        result=self.run_mock(self.runner(costs=(.001,.001),status='failed',error='source_not_suggested'))
        self.assertEqual(result['attempted_reviews'],6);self.assertEqual(result['request_count'],12);self.assertEqual(result['reviews_with_allowed_confirmation'],0)
    def test_unknown_cost_stops_remaining_five_without_retry(self):
        result=self.run_mock(self.runner(costs=(.001,None),status='failed'))
        self.assertEqual(result['attempted_reviews'],1);self.assertFalse(result['all_request_costs_known']);self.assertEqual(result['reported_cost_usd'],'0.001')
        self.assertEqual(sum(x['status']=='not_attempted'for x in result['cases']),5)
    def test_case_reported_stop_is_applied(self):
        result=self.run_mock(self.runner(costs=(.051,)));self.assertEqual(result['attempted_reviews'],1);self.assertEqual(result['status'],'stopped_reported_cost')
    def test_global_stop_is_applied(self):
        plan=self.plan();plan['reported_cost_stop_usd']='0.006'
        with patch.object(w,'verify',return_value=plan):
            result=w.run(self.root,invoke=self.runner(),environment=lambda:{},sleeper=lambda _:None)
        self.assertEqual(result['attempted_reviews'],2);self.assertEqual(result['status'],'stopped_reported_cost')
    def test_harness_timeout_keeps_unknown_and_all_six_rows(self):
        def invoke(*args):raise subprocess.TimeoutExpired('probe',210)
        result=self.run_mock(invoke);self.assertEqual(len(result['cases']),6);self.assertEqual(result['attempted_reviews'],1);self.assertFalse(result['all_request_costs_known'])
    def test_reviewer_timeout_stops_even_with_known_receipts(self):
        result=self.run_mock(self.runner(costs=(.001,),status='failed',error='provider_timedOut'));self.assertEqual(result['attempted_reviews'],1)
    def test_run_marker_prevents_repeat(self):
        self.run_mock(self.runner())
        with self.assertRaises(FileExistsError):self.run_mock(self.runner())
    def test_altered_response_cost_is_rejected(self):
        self.receipt(self.root,[.001]);w.write(self.root/'response-1.json',{'usage':{'cost':1}})
        with self.assertRaises(ValueError):w.cost_receipt(self.root)
    def test_boolean_negative_nan_costs_are_rejected(self):
        for cost in [True,-1,float('inf')]:
            with self.subTest(cost=cost):
                folder=self.root/str(cost);folder.mkdir();w.write(folder/'request-1.json',{})
                (folder/'receipt.json').write_text(json.dumps(dict(requests=[dict(request=1,request_sha256=w.digest(folder/'request-1.json'),reported_cost_usd=cost)],maximum_requests=4,automatic_retries=0)))
                with self.assertRaises(ValueError):w.cost_receipt(folder)
    def test_request_cap_rejected(self):
        self.receipt(self.root,[.001]*5)
        with self.assertRaises(ValueError):w.cost_receipt(self.root)
    def test_subset_rejects_empty_duplicate_unknown_and_reordered(self):
        original={'cases':self.plan()['cases']}
        for ids in [[],['case-1','case-1'],['unknown'],['case-4','case-1'],'case-1']:
            with self.subTest(ids=ids), self.assertRaises(ValueError):w.select_subset(original,ids)
    def test_subset_preserves_exact_strings_and_original_order(self):
        original={'cases':self.plan()['cases']};original['cases'][5]['query']='台灣 原始文字 100 g'
        cohort,cases=w.select_subset(original,['case-2','case-5'])
        self.assertEqual(len(cohort),6);self.assertEqual(cases,[original['cases'][2],original['cases'][5]])
    def test_single_subset_never_calls_excluded_five(self):
        plan=self.plan();plan['cases']=plan['cases'][-1:];plan.update(subset_denominator=1,subset_ids=['case-5'],excluded_case_ids=[f'case-{i}'for i in range(5)],maximum_requests=4)
        calls=[];invoke=self.runner()
        def invoke_once(args,*extra):calls.append(args[2]);return invoke(args,*extra)
        with patch.object(w,'verify',return_value=plan):
            result=w.run(self.root,invoke=invoke_once,environment=lambda:{},sleeper=lambda _:None)
        self.assertEqual(calls,['public food 5']);self.assertEqual(result['denominator'],1);self.assertEqual(result['original_cohort_denominator'],6)
        self.assertEqual(result['request_count'],3);self.assertEqual(len(result['excluded_case_ids']),5)
    def test_capture_timeout_now_stops_remaining_subset(self):
        result=self.run_mock(self.runner(costs=(.001,.001),status='failed',error='capture_timedOut'))
        self.assertEqual(result['attempted_reviews'],1);self.assertEqual(result['status'],'stopped_unknown_cost_or_timeout')
    def make_frozen_subset(self):
        discovery=self.root/'discovery';discovery.mkdir();w.write(discovery/'plan.json',{'cases':self.plan()['cases']})
        (discovery/'plan.sha256').write_text(w.digest(discovery/'plan.json')+'\n')
        runtime=self.root/'runtime';runtime.mkdir();exe=runtime/'FoodProposalProbe';exe.write_bytes(b'synthetic executable not invoked')
        (runtime/'FoodLedgerKit_FoodGenericSearch.bundle').mkdir()
        root=self.root/'frozen';plan=w.freeze(discovery,exe,root,['case-5'])
        return root,plan,discovery
    def test_freeze_keeps_original_plan_bytes_and_subset_denominators(self):
        root,plan,discovery=self.make_frozen_subset()
        self.assertEqual((root/'snapshot/original-query-plan.json').read_bytes(),(discovery/'plan.json').read_bytes())
        self.assertEqual(plan['subset_denominator'],1);self.assertEqual(plan['original_cohort_denominator'],6);self.assertEqual(plan['maximum_requests'],4)
        self.assertEqual(w.verify(root)['subset_ids'],['case-5'])
    def test_changed_subset_query_rejected_even_with_updated_plan_hash(self):
        root,plan,_=self.make_frozen_subset();plan['cases'][0]['query']='replacement query';w.write(root/'plan.json',plan)
        (root/'plan.sha256').write_text(w.digest(root/'plan.json')+'\n')
        with self.assertRaises(ValueError):w.verify(root)
    def test_runtime_snapshot_mutation_rejected(self):
        root,plan,_=self.make_frozen_subset();(root/plan['executable']).write_bytes(b'modified executable')
        with self.assertRaises(ValueError):w.verify(root)
    def test_closed_criteria_distinguish_tool_retention_and_numeric_accuracy(self):
        self.assertIn('Exa tool retention',w.CRITERIA['privacy']);self.assertIn('not independent nutrition accuracy',w.CRITERIA['scope'])

if __name__=='__main__':unittest.main()
