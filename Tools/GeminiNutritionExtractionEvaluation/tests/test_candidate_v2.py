import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import evaluate as ev
import candidate_v2 as v2
from fetch_documents import VisibleText

class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.corpus,_=ev.verify();self.case=self.corpus['cases'][0]
        self.schema=ev.load(ev.ROOT/'response-schema-v2.json')
    def answer(self):
        x=copy.deepcopy(self.case['gold']);x['reason']='fixture'
        x['nutrients']=[dict(id=k,**v,evidence='value' if v['state']!='unknown' else '',evidence_line=None) for k,v in x['nutrients'].items()]
        return x
    def test_new_schema_does_not_repair_null_operator(self):
        x=self.answer();self.assertTrue(v2.score(self.case,'panel',x,None,self.schema)['passed'])
        x['nutrients'][0]['operator']=None
        self.assertFalse(v2.score(self.case,'panel',x,None,self.schema)['passed'])
    def test_html_keeps_columns_and_drops_executable_content(self):
        parser=VisibleText();parser.feed('<nav>Menu</nav><script>secret</script><table><tr><th>raw</th><th>cooked</th></tr><tr><td>100</td><td>200</td></tr></table>')
        text=parser.result();self.assertIn('raw | cooked',text);self.assertIn('100 | 200',text)
        self.assertIn('Menu',text);self.assertNotIn('secret',text)
    def test_request_excludes_gold_and_panel_from_document(self):
        source=self.corpus['sources'][self.case['source']]
        b=v2.request(self.case,source,'document',dict(selected_url=source['url'],text='L1: sample'))
        p=json.loads(b['input']);self.assertNotIn('evidence_panel',p);self.assertNotIn('gold',p);self.assertEqual(b['tools'],[])
        h=next(c for c in self.corpus['cases'] if c['split']=='holdout')
        with self.assertRaises(ValueError):v2.request(h,source,'panel')
    def test_wrong_line_cannot_pass(self):
        x=self.answer()
        for f in x['nutrients']:
            if f['state']!='unknown':f['evidence_line']=1
        r=v2.score(self.case,'document',x,dict(text='L1: Unrelated 999'),self.schema)
        self.assertFalse(r['passed']);self.assertIn('line_value_missing:protein',r['errors'])
    def test_timeout_journal_no_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'run';calls=[]
            def fetch(body,key):
                calls.append(body);self.assertEqual(ev.load(out/'attempts.json')['attempts'][-1]['outcome'],'started');raise TimeoutError()
            self.assertFalse(v2.capture(self.corpus,{}, {},out,'fake-secret-long-enough',20,fetch))
            self.assertEqual(len(calls),1);self.assertEqual(ev.load(out/'report.json')['planned'],20)

if __name__=='__main__':unittest.main()
