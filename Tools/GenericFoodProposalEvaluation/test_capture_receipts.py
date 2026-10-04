import copy
import json
from pathlib import Path
import tempfile
import unittest

from capture_discovery import capture_output_hashes, verify_capture_outputs, validate_capture_cases, freeze


class CaptureReceiptTests(unittest.TestCase):
    def testUnsafeIdentifiersURLsAndDuplicateCasesFailBeforeCapture(self):
        valid = dict(id='food-1', query='Plain tofu', url='https://example.com/food')
        validate_capture_cases([valid, dict(id='missing', query='Rice', url=None)])
        for edit in [dict(id='../food'), dict(id=''), dict(id='/tmp/food'),
                     dict(query=''), dict(query='x' * 301), dict(url='http://example.com/food'),
                     dict(url='https://user:secret@example.com/food'), dict(url='https://example.com:444/food')]:
            with self.subTest(edit=edit), self.assertRaises(ValueError):
                validate_capture_cases([dict(valid, **edit)])
        for cases in [[], [valid, valid], [dict(valid, id='food-' + str(i)) for i in range(41)]]:
            with self.assertRaises(ValueError): validate_capture_cases(cases)

    def testMissingRuntimeAndInvalidReferencesLeaveNoPartialRun(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); reference = root / 'references.json'; destination = root / 'run'
            reference.write_text(json.dumps(dict(reference_status='development', cases=[
                dict(id='../unsafe', query='Tofu', identity=dict(country='UK'), source_url='https://example.com/food')
            ])))
            executable = root / 'FoodProposalProbe'
            with self.assertRaises(ValueError): freeze(reference, executable, destination, references=True)
            self.assertFalse(destination.exists())
            executable.write_text('unused')
            with self.assertRaises(ValueError): freeze(reference, executable, destination, references=True)
            self.assertFalse(destination.exists())
            (root / 'FoodLedgerKit_FoodGenericSearch.bundle').mkdir()
            with self.assertRaises(ValueError): freeze(reference, executable, destination, references=True)
            self.assertFalse(destination.exists())

    def fixture(self, root):
        folder = root / 'results/food'; folder.mkdir(parents=True)
        (folder / 'source-body-1.bin').write_bytes(b'<p>Food</p>')
        (folder / 'document.json').write_text('{"id":"d1"}')
        responses = [dict(url='https://example.com/food', status=200)]
        (folder / 'capture-receipt.json').write_text(json.dumps(dict(responses=responses)))
        status = dict(status='captured', closed_error=None, completed_at='2026-10-04T00:00:00Z',
                      output_hashes=capture_output_hashes(folder))
        (folder / 'status.json').write_text(json.dumps(status))
        plan = dict(output_hashes_required=True, cases=[dict(id='food'), dict(id='missing')])
        audit = dict(cases=[dict(id='food', **status, responses=responses), dict(id='missing', status='not_run')])
        return plan, audit, folder

    def testCaptureOutputsAndUnattemptedDenominatorRemainVisible(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); plan, audit, _ = self.fixture(root)
            self.assertEqual(verify_capture_outputs(root, plan, audit), 'verified_against_capture_completion_receipt')
            self.assertEqual(verify_capture_outputs(root, {}, {}), 'not_recorded_legacy_capture')

    def testChangedAddedAndDeletedSourceEvidenceFails(self):
        for change in ['document', 'body', 'receipt', 'added_body', 'deleted_body']:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); plan, audit, folder = self.fixture(root)
                if change == 'document': (folder / 'document.json').write_text('{"id":"changed"}')
                if change == 'body': (folder / 'source-body-1.bin').write_bytes(b'Changed food')
                if change == 'receipt': (folder / 'capture-receipt.json').write_text('{"responses":[]}')
                if change == 'added_body': (folder / 'source-body-2.bin').write_bytes(b'Extra response')
                if change == 'deleted_body': (folder / 'source-body-1.bin').unlink()
                with self.assertRaises(ValueError): verify_capture_outputs(root, plan, audit)

    def testReportCannotChangeStatusResponsesOrDropACase(self):
        for change in ['drop_case', 'change_status', 'change_responses', 'missing_receipt']:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); plan, audit, folder = self.fixture(root)
                audit = copy.deepcopy(audit)
                if change == 'drop_case': audit['cases'].pop()
                if change == 'change_status': audit['cases'][0]['status'] = 'failed'
                if change == 'change_responses': audit['cases'][0]['responses'] = []
                if change == 'missing_receipt': (folder / 'status.json').unlink()
                with self.assertRaises(ValueError): verify_capture_outputs(root, plan, audit)


if __name__ == '__main__':
    unittest.main()
