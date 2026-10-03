import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('project_tfda', Path(__file__).parents[1] / 'project_tfda.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class TFDAProjectionTests(unittest.TestCase):
    def setUp(self):
        self.review = {'schema': 'tfda-reviewed-foods-v1', 'records': [dict(id='X1', sourceName='測試', name='Example', aliases=['example'])]}
        self.rows = [dict(整合編號='X1', 樣品名稱='測試', 樣品英文名稱='Example', 內容物描述='樣品狀態:生; 前處理描述:混合均勻打碎',
            食品分類='蔬菜類', 俗名=None, 分析項=field, 含量單位=unit, 每100克含量=' 0.0 ')
            for field, unit in m.MAPPING.values()]

    def testLiteralZeroIsRetainedAndNullDoesNotBecomeZero(self):
        self.rows[-1]['每100克含量'] = None
        record = m.project(self.rows, self.review)[0]
        self.assertEqual(record['nutrients']['energy_consumed']['amount'], 0)
        self.assertNotIn('vitamin_b6', record['nutrients'])
        self.assertEqual(record['nutrients']['energy_consumed']['sourceRow'], 0)
        self.assertEqual(record['preparation'], 'raw')

    def testUnitsInvalidNumbersMissingMacrosAndDuplicateFieldsAreRejected(self):
        for changes in [dict(含量單位='kJ'), dict(每100克含量='NaN'), dict(每100克含量='<1'), dict(每100克含量='-1'), dict(每100克含量=None)]:
            rows = copy.deepcopy(self.rows); rows[0].update(changes)
            with self.assertRaises(ValueError): m.project(rows, self.review)
        with self.assertRaises(ValueError): m.project(self.rows + [self.rows[0]], self.review)

    def testRecordIdentityCannotDriftOrBeSpliced(self):
        rows = copy.deepcopy(self.rows); rows[0]['樣品名稱'] = '其他'
        with self.assertRaises(ValueError): m.project(rows, self.review)
        rows = copy.deepcopy(self.rows); rows[-1]['內容物描述'] = '其他'
        with self.assertRaises(ValueError): m.project(rows, self.review)
        with self.assertRaises(ValueError): m.project([], self.review)

    def testLabPreparationAndFrozenOrDriedStateDoNotInventCooking(self):
        for text in ['前處理描述:混合均勻打碎', '樣品狀態:冷凍包裝; 前處理描述:混合均勻', '樣品狀態:乾貨; 前處理描述:混合均勻']:
            self.assertEqual(m.preparation(text), 'unknown')
        self.assertEqual(m.preparation('樣品狀態:熟,真空包裝; 前處理描述:混合均勻'), 'cooked')

if __name__ == '__main__': unittest.main()
