import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from frozen_run import freeze
from holdout_audit import audit, read_bytes
from test_evaluate import fixture


class HoldoutAuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.development = self.root / 'development'
        self.document = self.development / 'snapshot/documents/one.json'
        self.document.parent.mkdir(parents=True)
        self.write(self.document, [dict(raw_sha256='a' * 64, url='https://source.test/tofu')])
        old, _ = fixture()
        old.update(document='snapshot/documents/one.json', domain='source.test')
        self.plan = dict(version='swift-frozen-evaluation-v1', cases=[old],
                         snapshot_hashes={'snapshot/documents/one.json': self.hash(self.document)})
        self.save_plan()
        self.roster = self.root / 'roster.json'
        self.candidate = copy.deepcopy(old)
        self.candidate.update(id='fresh-beans', query='Plain cooked beans', family='beans',
                              domain='fresh.test', document='beans.json')
        self.write(self.root / 'beans.json', [dict(raw_sha256='b' * 64, url='https://fresh.test/beans')])
        self.save_roster()

    def write(self, path, value):
        path.write_text(json.dumps(value) + '\n')

    def hash(self, path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def save_roster(self):
        self.write(self.roster, dict(cases=[self.candidate]))

    def save_plan(self):
        self.write(self.development / 'plan.json', self.plan)
        (self.development / 'plan.sha256').write_text(self.hash(self.development / 'plan.json') + '\n')

    def result(self):
        return audit(self.roster, [self.development])

    def testDisjointMetadataDoesNotBecomeIndependentAcceptance(self):
        result = self.result()
        self.assertTrue(result['eligible_for_prospective_run'])
        self.assertFalse(result['independent_acceptance'])
        self.assertFalse(result['confidence_calibrated'])
        self.assertEqual(result['candidate_roster_sha256'], self.hash(self.roster))
        self.assertEqual(result['development_plans'][0]['planned_cases'], 1)

    def testEveryOverlapAxisRejectsRelabelledCasesBeforePredictions(self):
        mutations = [
            ('comparison_case', lambda: self.candidate.update(comparison_case='one')),
            ('declared_food_family', lambda: self.candidate.update(family=' TOFU ')),
            ('declared_source_domain', lambda: self.candidate.update(domain='www.source.test')),
            ('declared_source_domain', lambda: self.candidate.update(domain_group='source.test')),
            ('normalised_query', lambda: self.candidate.update(query=' Ｔｏｆｕ ')),
            ('raw_source_bytes', lambda: self.write(self.root / 'beans.json', [dict(raw_sha256='a' * 64, url='https://fresh.test/beans')])),
            ('source_url', lambda: self.write(self.root / 'beans.json', [dict(raw_sha256='b' * 64, url='https://source.test/tofu#nutrition')]))]
        original = copy.deepcopy(self.candidate)
        for reason, mutation in mutations:
            with self.subTest(reason=reason):
                self.candidate = copy.deepcopy(original)
                self.write(self.root / 'beans.json', [dict(raw_sha256='b' * 64, url='https://fresh.test/beans')])
                mutation(); self.save_roster()
                result = self.result()
                self.assertFalse(result['eligible_for_prospective_run'])
                self.assertIn(reason, result['overlaps'][0]['matches'][0]['reasons'])

    def testHistoricalDiscoveryUnknownDomainRetainsQueryAndFamilyExposure(self):
        for sentinel in ['unobserved', 'not_known_before_discovery']:
            with self.subTest(sentinel=sentinel):
                self.plan['cases'][0].update(task='discovery', domain=sentinel)
                self.save_plan()
                self.candidate['family'] = 'tofu'; self.save_roster()
                result = self.result()
                self.assertEqual(result['development_cases_without_source_domain'], 1)
                self.assertFalse(result['eligible_for_prospective_run'])
                self.assertIn('declared_food_family', result['overlaps'][0]['matches'][0]['reasons'])
                self.assertFalse(result['independent_acceptance'])

    def testUnknownDomainSentinelCannotHideProvidedDocumentSource(self):
        for task, host in [('provided_document', 'unobserved'), ('discovery', 'anything_unknown')]:
            with self.subTest(task=task, host=host):
                self.plan['cases'][0].update(task=task, domain=host); self.save_plan()
                with self.assertRaisesRegex(ValueError, 'domain must'):
                    self.result()

    def testCapturedRedirectHostCannotBeHiddenByDeclaredDomain(self):
        self.write(self.root / 'beans.json', [dict(raw_sha256='b' * 64, url='https://source.test/another-food')])
        result = self.result()
        self.assertFalse(result['eligible_for_prospective_run'])
        self.assertIn('declared_source_domain', result['overlaps'][0]['matches'][0]['reasons'])

    def testUnattemptedDevelopmentCasesStillCountAsExposed(self):
        self.assertFalse((self.development / 'results').exists())
        self.candidate['family'] = 'tofu'; self.save_roster()
        self.assertEqual(self.result()['overlapping_candidate_count'], 1)

    def testChangedPlanAndChangedSourceCannotBeUsedAsSplitEvidence(self):
        (self.development / 'plan.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'plan changed'): self.result()
        self.save_plan()
        self.document.write_text('[]')
        with self.assertRaisesRegex(ValueError, 'document changed'): self.result()

    def testDevelopmentSourceCannotEscapeItsHashedSnapshot(self):
        self.plan['cases'][0]['document'] = '../../beans.json'; self.save_plan()
        with self.assertRaisesRegex(ValueError, 'escapes snapshot'): self.result()
        self.plan['cases'][0]['document'] = 'snapshot/documents/one.json'
        self.plan['snapshot_hashes'] = {}; self.save_plan()
        with self.assertRaisesRegex(ValueError, 'not frozen'): self.result()

    def testCredentialFileIsRejectedBeforeFileAccess(self):
        with patch.object(Path, 'read_bytes', side_effect=AssertionError('Must not read')):
            with self.assertRaisesRegex(ValueError, 'credential files'):
                read_bytes(self.root / '.env')
        self.candidate['document'] = '.env.private'; self.save_roster()
        with self.assertRaisesRegex(ValueError, 'credential files'): self.result()

    def testMissingDuplicateOrInvalidDevelopmentEvidenceFailsClosed(self):
        for roots in [[], [self.development, self.development]]:
            with self.assertRaises(ValueError): audit(self.roster, roots)
        self.candidate['domain'] = 'https://fresh.test'; self.save_roster()
        with self.assertRaises(ValueError): self.result()

    def testOverlapStopsFreezeBeforeRuntimeAndLoaderAccess(self):
        self.candidate['family'] = 'tofu'; self.save_roster()
        with patch('frozen_run.digest', side_effect=AssertionError('No runtime or loader hashing')):
            with self.assertRaisesRegex(ValueError, 'overlaps'):
                freeze(self.roster, self.root / 'missing-runtime', self.root / 'run', [self.development])
        self.assertFalse((self.root / 'run').exists())

    def testSuccessfulFreezeRetainsAuditUnderSnapshotHashes(self):
        runtime = self.root / 'runtime'; runtime.mkdir()
        executable = runtime / 'FoodProposalProbe'; executable.write_bytes(b'synthetic non-executable fixture')
        (runtime / 'FoodLedgerKit_FoodGenericSearch.bundle').mkdir()
        repo = self.root / 'repo'; package = repo / 'Packages/FoodLedgerKit'; package.mkdir(parents=True)
        scripts = repo / 'Tools/GenericFoodProposalEvaluation'; scripts.mkdir(parents=True)
        loader = self.root / 'synthetic-loader.py'; loader.write_text('# synthetic, never executed\n')
        with patch('frozen_run.REPO', repo), patch('frozen_run.HERE', scripts), patch('frozen_run.LOADER', loader):
            freeze(self.roster, executable, self.root / 'run', [self.development])
        plan = json.loads((self.root / 'run/plan.json').read_text())
        audit_path = self.root / 'run' / plan['holdout_audit']
        self.assertEqual(plan['snapshot_hashes'][plan['holdout_audit']], self.hash(audit_path))
        self.assertFalse(json.loads(audit_path.read_text())['independent_acceptance'])


if __name__ == '__main__':
    unittest.main()
