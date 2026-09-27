import importlib.util,math,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('query_score',Path(__file__).parents[1]/'score.py');score=importlib.util.module_from_spec(spec);spec.loader.exec_module(score)
class MetricsTests(unittest.TestCase):
 def rows(self):
  cases=[];actual=[]
  for i,(expected,predicted) in enumerate([('search','search'),('search','clarify'),('clarify','search'),('reject','reject')]):
   quantity={'value':10,'unit':'g'} if expected=='search' else None
   c={'id':str(i),'family':'toy','query':'test '+str(i),'expected':{'food':'rice','attributes':{},'quantity':quantity,'route':expected}};cases.append(c)
   actual.append({'id':str(i),'parsed':{'original':c['query'],'food':'rice','attributes':{},'quantity':{'value':10,'unit':'g'} if predicted=='search' else None,'route':predicted}})
  return {'cases':cases},actual
 def test_confusion_precision_recall_and_unsafe_prefill(self):
  f,a=self.rows();r=score.evaluate(f,a)
  self.assertEqual(r['route_metrics']['confusion_matrix']['search'],{'search':1,'clarify':1,'reject':0})
  self.assertEqual(r['route_metrics']['per_class']['search']['precision'],.5)
  self.assertEqual(r['route_metrics']['per_class']['search']['recall'],.5)
  self.assertEqual(r['safety_metrics']['unexpected_prefill_ids'],['2'])
  self.assertEqual(r['safety_metrics']['false_search_eligible_rate'],.5)
  self.assertEqual(r['quantity_metrics']['presence_precision'],.5)
 def test_units_do_not_get_mixed_into_numeric_error(self):
  f,a=self.rows();a[0]['parsed']['quantity']={'value':999,'unit':'ml'}
  r=score.evaluate(f,a);self.assertEqual(r['quantity_metrics']['unit_errors'],1)
  self.assertEqual(r['quantity_metrics']['comparable_pairs'],0)
  self.assertIsNone(r['quantity_metrics']['mean_absolute_relative_error_comparable_pairs'])
 def test_numeric_percent_equivalence(self):
  self.assertEqual(score.normal_attributes({'fat_percent':10}),score.normal_attributes({'fat_percent':'10.0'}))
 def test_invalid_predictions_are_rejected(self):
  f,a=self.rows()
  for mutation in ['duplicate','missing','original','route','nan']:
   import copy
   b=copy.deepcopy(a)
   if mutation=='duplicate':b[1]['id']=b[0]['id']
   if mutation=='missing':b.pop()
   if mutation=='original':b[0]['parsed']['original']='changed'
   if mutation=='route':b[0]['parsed']['route']='other'
   if mutation=='nan':b[0]['parsed']['quantity']['value']=math.nan
   with self.assertRaises(ValueError):score.evaluate(f,b)
 def test_absent_classes_have_undefined_metrics(self):
  f,a=self.rows();f['cases']=f['cases'][:1];a=a[:1]
  r=score.evaluate(f,a)
  self.assertIsNone(r['route_metrics']['per_class']['reject']['precision'])
  self.assertIsNone(r['route_metrics']['per_class']['reject']['recall'])
  self.assertEqual(r['route_metrics']['macro_f1_supported_classes'],1)
  with self.assertRaises(ValueError):score.evaluate({'cases':[]},[])
 def test_attribute_pairs_and_relative_error(self):
  f,a=self.rows();f['cases']=f['cases'][:1];a=a[:1]
  f['cases'][0]['expected']['attributes']={'preparation':'raw','fat_percent':'10'}
  a[0]['parsed']['attributes']={'preparation':'cooked','fat_percent':'10.0'}
  a[0]['parsed']['quantity']['value']=12
  r=score.evaluate(f,a)
  self.assertEqual(r['attribute_metrics']['true_positive_pairs'],1)
  self.assertEqual(r['attribute_metrics']['false_positive_pairs'],1)
  self.assertEqual(r['attribute_metrics']['false_negative_pairs'],1)
  self.assertAlmostEqual(r['quantity_metrics']['mean_absolute_relative_error_comparable_pairs'],.2)
  self.assertEqual(r['quantity_metrics']['value_errors_comparable_units'],1)
if __name__=='__main__':unittest.main()
