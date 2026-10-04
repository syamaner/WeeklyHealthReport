import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from build_prospective_roster import build


class SourceRosterTests(unittest.TestCase):
    def fixture(self, root):
        captures = root / 'captures'; folder = captures / 'results' / 'tofu'
        folder.mkdir(parents=True)
        raw = b'<p>Tofu Per 100g Energy 80kcal Protein 6g</p>'
        digest = hashlib.sha256(raw).hexdigest()
        (folder / 'source-body-1.bin').write_bytes(raw)
        self.write(folder / 'capture-receipt.json', dict(responses=[dict(body_sha256=digest)]))
        self.write(folder / 'document.json', dict(id='d1', raw_sha256=digest))
        planned = [dict(id='tofu', query='Tofu', url='https://example.com/tofu'),
                   dict(id='oversized', query='Lentils', url='https://example.com/lentils')]
        self.write(captures / 'plan.json', dict(cases=planned))
        (captures / 'plan.sha256').write_text(hashlib.sha256((captures / 'plan.json').read_bytes()).hexdigest() + '\n')
        self.write(captures / 'report.json', dict(cases=[dict(**planned[0], status='captured'),
            dict(**planned[1], status='failed', closed_error='capture_responseTooLarge')]))
        cases = [dict(id='tofu', query='Tofu', source_url=planned[0]['url'], expected_action='select_partial',
            extraction_eligible=True, capture_review=dict(raw_sha256=digest), identity=dict(aliases=['Tofu'], country='TW'),
            source_basis=dict(amount='100', unit='g'), category='table', family_group_id='tofu',
            nutrients={key: dict(value=value) for key, value in dict(energy='80', protein='6', carbohydrate=None,
                fat=None, fibre=None, sodium=None).items()}),
            dict(id='oversized', query='Lentils', source_url=planned[1]['url'],
                 expected_action='acquisition_unavailable', extraction_eligible=False)]
        reference = root / 'references.json'
        self.write(reference, dict(predictions_seen=False, reference_status='Source reviewed before prediction', cases=cases))
        return reference, captures

    def write(self, path, value):
        path.write_text(json.dumps(value) + '\n')

    def testInvalidGoldFailsBeforeCreatingOutput(self):
        for mutation in ['negative_nutrient', 'infinite_basis', 'string_aliases', 'invalid_equivalent']:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); reference, captures = self.fixture(root)
                value = json.loads(reference.read_text()); case = value['cases'][0]
                if mutation == 'negative_nutrient': case['nutrients']['protein']['value'] = '-1'
                if mutation == 'infinite_basis': case['source_basis']['amount'] = 'Infinity'
                if mutation == 'string_aliases': case['identity']['aliases'] = 'Tofu'
                if mutation == 'invalid_equivalent': case['allowed_equivalent_bases'] = [dict(amount=True, unit='serving')]
                self.write(reference, value)
                with self.assertRaises(ValueError): build(reference, captures, root / 'prepared', ['luna'])
                self.assertFalse((root / 'prepared').exists())

    def testCaptureFailureRemainsFrozenWhileOnlyCapturedCasesReachExtraction(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); reference, captures = self.fixture(root)
            build(reference, captures, root / 'prepared', ['luna'])
            roster = json.loads((root / 'prepared/roster.json').read_text())
            self.assertEqual(len(roster['cases']), 1)
            self.assertEqual(roster['acquisition']['planned_case_ids'], ['tofu', 'oversized'])
            self.assertEqual(roster['acquisition']['excluded_cases'][0]['id'], 'oversized')
            self.assertIn('capture-report.json', roster['cases'][0]['evidence_files'])

    def testReviewCannotDropAFailureChangeQueryOrReplaceRetainedBytes(self):
        for mutation in ['drop_failure', 'change_query', 'wrong_bytes']:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); reference, captures = self.fixture(root)
                value = json.loads(reference.read_text())
                if mutation == 'drop_failure': value['cases'].pop()
                if mutation == 'change_query': value['cases'][0]['query'] = 'Different query'
                if mutation == 'wrong_bytes':
                    wrong = 'f' * 64
                    value['cases'][0]['capture_review']['raw_sha256'] = wrong
                    self.write(captures / 'results/tofu/document.json', dict(id='d1', raw_sha256=wrong))
                self.write(reference, value)
                with self.assertRaises(ValueError): build(reference, captures, root / 'prepared', ['luna'])

    def testInvalidDecoysAndIncompleteEligibilityFailBeforeWriting(self):
        for mutation in ['uncaptured_decoy', 'self_decoy', 'duplicate_decoy', 'missing_reason']:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); reference, captures = self.fixture(root)
                value = json.loads(reference.read_text())
                case = value['cases'][0]
                if mutation == 'uncaptured_decoy': case['decoy_source_urls'] = ['https://example.com/lentils']
                if mutation == 'self_decoy': case['decoy_source_urls'] = [case['source_url']]
                if mutation == 'duplicate_decoy': case['decoy_source_urls'] = ['https://example.com/other'] * 2
                if mutation == 'missing_reason': case['workflow_source_eligible'] = True
                self.write(reference, value)
                with self.assertRaises(ValueError): build(reference, captures, root / 'prepared', ['luna'])
                self.assertFalse((root / 'prepared').exists())


if __name__ == '__main__':
    unittest.main()
