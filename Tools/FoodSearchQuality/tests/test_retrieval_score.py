import importlib.util
import pathlib
import unittest
import math
spec = importlib.util.spec_from_file_location('score',pathlib.Path(__file__).parents[1]/'score_retrieval.py')
s = importlib.util.module_from_spec(spec); spec.loader.exec_module(s)

class ScoreTests(unittest.TestCase):
    def fixture(self):
        return {'cases':[{'id':'a','query':'q','family':'f','grades':{'usda-x':3,'usda-y':1},'incorrectVariantRecords':['usda-y']}]}
    def rows(self):
        return [dict(id='a',query='q',source=k,records=[] if k=='cofid' else ['usda-y','usda-x']) for k in ('cofid','usda','composite')]
    def test_ranking_and_coverage(self):
        v=s.score(self.fixture(),self.rows())['summaries']
        self.assertIsNone(v['cofid']['mrr']); self.assertEqual(v['cofid']['appropriateNoResult'],1)
        self.assertEqual(v['composite']['mrr'],.5); self.assertEqual(v['composite']['hitAt1'],0)
        self.assertEqual(v['composite']['hitAt5'],1); self.assertEqual(v['composite']['incorrectVariantAt1'],1)
        self.assertAlmostEqual(v['composite']['ndcgAt5'], (1+7/math.log2(3))/(7+1/math.log2(3)))
    def test_missing_duplicate_and_query_drift(self):
        for rows in [self.rows()[:2],self.rows()+self.rows()[:1], [dict(r,query='wrong') for r in self.rows()]]:
            with self.assertRaises(ValueError): s.score(self.fixture(),rows)
    def test_tentative_only_not_no_result(self):
        f=self.fixture(); f['cases'][0]['grades']={'usda-y':1}
        v=s.score(f,self.rows())['summaries']['composite']
        self.assertEqual(v['tentativeOnlyCases'],1); self.assertEqual(v['noResultCases'],0)
        self.assertIsNone(v['mrr']); self.assertEqual(v['confusionMatrix'],{'tentative':{'tentative':1}})
    def test_unrelated_results_remain_failure(self):
        f=self.fixture(); f['cases'][0]['grades']={}
        v=s.score(f,self.rows())['summaries']['composite']
        self.assertEqual(v['appropriateNoResult'],0)
        self.assertEqual(v['confusionMatrix'],{'empty':{'unrelated':1}})
