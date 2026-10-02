import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from readiness import assess, MINIMA
from run import outside_git, verify_pins


def fixture():
    # Artificial infrastructure fixture; never a human-reference or acceptance dataset.
    rows = []
    for stratum, count in MINIMA.items():
        for i in range(count):
            cid = f'{stratum}-{i}'
            rows.append(dict(case_id=cid, scenario_group=cid, primary_stratum=stratum,
                             original_input='synthetic fixture', intended_outcome='clarify',
                             reviewer='synthetic reviewer placeholder',
                             reference={'answerability': 'needs_clarification', 'expected': {'route': 'clarify'}},
                             exposure='prospective_unscored', overlap_reviewed=True))
    collection = dict(status='frozen_unscored', schema='prospective-nutrition-collection-v1', cases=rows,
                      references_reviewed_without_predictions=True,
                      reference_review='independent_human_reviewed',
                      inputs_authored_by='human_after_implementation_freeze')
    freeze = dict(profile='offline_nlp_retrieval', scorer_versions={'fixture': 'synthetic-test'}, schema='nutrition-acceptance-freeze-v1', collection_sha256='test',
                  quality_thresholds={key: {'minimum': 0.9, 'approved_by': 'synthetic fixture'}
                                      for key in ['AI01_route_accuracy', 'AI01_quantity_accuracy', 'AI02_hit_at_5']})
    integrity = dict(collection_hash_matches=True, errors=[],
                     verified_categories=['implementation', 'catalogue', 'metric_contract', 'readiness_policy'])
    return collection, freeze, integrity


class Readiness(unittest.TestCase):
    def test_preflight_never_produces_acceptance_or_scores(self):
        r = assess(*fixture())
        self.assertEqual(r['status'], 'ready_for_execution')
        self.assertEqual(r['acceptance'], 'not_run')
        self.assertIsNone(r['metrics'])

    def test_empty_inputs_cannot_count_as_coverage(self):
        c, f, i = fixture()
        for row in c['cases']: row['original_input'] = None
        r = assess(c, f, i)
        self.assertEqual(r['status'], 'incomplete')
        self.assertEqual(r['distinct_groups'], 0)
        self.assertEqual(r['collected_cases'], 0)

    def test_duplicate_ids_or_groups_invalidate(self):
        for field in ['case_id', 'scenario_group']:
            c, f, i = fixture();c['cases'][1][field] = c['cases'][0][field]
            self.assertEqual(assess(c, f, i)['status'], 'invalid')

    def test_exposed_reference_and_missing_independence_cannot_pass(self):
        for edit in ['exposed', 'review', 'unresolved']:
            c, f, i = fixture()
            if edit == 'exposed': c['cases'][0]['exposure'] = 'development'
            if edit == 'review': c['reference_review'] = 'single_reviewer'
            if edit == 'unresolved': c['cases'][0]['reference']['answerability'] = 'unresolved_reference'
            self.assertEqual(assess(c, f, i)['status'], 'incomplete')

    def test_unratified_nonfinite_or_bool_thresholds(self):
        c, f, i = fixture();f['quality_thresholds'] = None
        self.assertEqual(assess(c, f, i)['status'], 'incomplete')
        for value in [True, float('nan'), -0.1, 1.1]:
            c, f, i = fixture();f['quality_thresholds']['AI01_route_accuracy']['minimum'] = value
            self.assertEqual(assess(c, f, i)['status'], 'invalid')

    def test_missing_pin_or_hash_drift_cannot_pass(self):
        c, f, i = fixture();i['verified_categories'] = []
        self.assertEqual(assess(c, f, i)['status'], 'incomplete')
        i['errors'] = ['pin_hash_mismatch']
        self.assertEqual(assess(c, f, i)['status'], 'invalid')
        c, f, i = fixture();i['collection_hash_matches'] = False
        self.assertEqual(assess(c, f, i)['status'], 'invalid')

    def test_malformed_documents_fail_closed(self):
        c, f, i = fixture();c['cases'] = [None]
        self.assertEqual(assess(c, f, i)['status'], 'invalid')
        self.assertEqual(assess([], f, i)['status'], 'invalid')

    def test_git_boundary_and_changed_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp);(p / '.git').mkdir();(p / 'child').mkdir()
            self.assertFalse(outside_git(p / 'child'))
            file = p / 'source';file.write_text('changed')
            result = verify_pins({'pins': [{'path': str(file), 'sha256': 'wrong'}]}, file)
            self.assertIn('pin_hash_mismatch', result['errors'])

    def test_cli_rejects_symlink_into_git(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp); repo = p / 'repo';repo.mkdir();(repo / '.git').mkdir()
            source = repo / 'personal.json';source.write_text('{}')
            link = p / 'link.json';link.symlink_to(source)
            freeze = p / 'freeze.json';freeze.write_text('{}')
            r = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / 'run.py'),
                                '--collection', str(link), '--freeze', str(freeze),
                                '--output', str(p / 'report')], capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertFalse((p / 'report').exists())

    def test_cli_preserves_existing_snapshot(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp); collection = p / 'collection.json';collection.write_text('{}')
            freeze = p / 'freeze.json';freeze.write_text('{}')
            out = p / 'report';out.mkdir();marker = out / 'marker';marker.write_text('preserved')
            r = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / 'run.py'),
                                '--collection', str(collection), '--freeze', str(freeze),
                                '--output', str(out)], capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertEqual(marker.read_text(), 'preserved')

    def test_cli_missing_input_reports_invalid_without_raw_content(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp);freeze = p / 'freeze.json';freeze.write_text('{}')
            r = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / 'run.py'),
                                '--collection', str(p / 'missing'), '--freeze', str(freeze),
                                '--output', str(p / 'report')], capture_output=True, text=True)
            self.assertEqual(r.returncode, 1, r.stderr)
            self.assertEqual(json.loads((p / 'report/readiness.json').read_text())['status'], 'invalid')


if __name__ == '__main__': unittest.main()
