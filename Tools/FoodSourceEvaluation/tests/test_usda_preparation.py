import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from project_usda import preparation_from_description,PREPARATION_POLICY

class PreparationTests(unittest.TestCase):
 def test_uncooked_is_not_cooked_substring(self):
  for name in ('Quinoa, uncooked','Rice, white, uncooked','Tripe uncooked, raw'):
   self.assertEqual(preparation_from_description(name),'raw')
  self.assertEqual(preparation_from_description('Quinoa, cooked'),'cooked')
 def test_partial_words_do_not_assert_cooked(self):
  for name in ('Rice, parboiled, dry','Tahini, from unroasted kernels','Cookedness unknown'):
   self.assertEqual(preparation_from_description(name),'unknown')
 def test_existing_explicit_compounds_remain_supported(self):
  for name in ('Refried beans, canned','Chicken nuggets, precooked','Chicken, stir-fried'):
   self.assertEqual(preparation_from_description(name),'cooked')
 def test_contradictions_and_negations_remain_unknown(self):
  for name in ('Quinoa, raw, cooked','Rice, cooked or uncooked','Fish, not cooked','Fish, never fried','raw not cooked'):
   self.assertEqual(preparation_from_description(name),'unknown')
 def test_undocumented_state_does_not_become_raw(self):
  for name in ('Quinoa','Milk, whole','Salmonberries'):
   self.assertEqual(preparation_from_description(name),'unknown')
 def test_bundled_records_obey_versioned_policy(self):
  root=Path(__file__).resolve().parents[3]
  d=json.loads((root/'Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources/usda-generic-v1.json').read_text())
  self.assertEqual(d['preparationPolicy'],PREPARATION_POLICY)
  self.assertEqual(len(d['records']),8156)
  for row in d['records']:self.assertEqual(row['preparation'],preparation_from_description(row['name']),row['name'])
  uncooked=[r for r in d['records'] if 'uncooked' in r['name'].lower()]
  self.assertEqual(len(uncooked),23)
  self.assertTrue(all(r['preparation']=='raw' for r in uncooked))
if __name__=='__main__':unittest.main()
