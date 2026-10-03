import ast,hashlib,json,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from run_current import bind_runner_workspace

class WorkspaceBinding(unittest.TestCase):
    def test_rebinds_only_verified_copies_and_adds_required_policy(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);work=root/'work';work.mkdir();repo=root/"candidate's workspace"
            policy=repo/'Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryDiscoveryPolicy.swift'
            policy.parent.mkdir(parents=True);policy.write_text('// synthetic dependency')
            original="REPO=Path('/Users/sertanyamaner/git/WeeklyHealthReport')\nsource_files=[]+[parser,ROOT/'nlp-runner.swift']\n"
            (work/'run_private.py').write_text(original)
            (work/'run_retrieval.py').write_text("repo=Path('/Users/sertanyamaner/git/WeeklyHealthReport')\n")
            labels=work/'labels.json';labels.write_text('{"private_example":"synthetic"}')
            report=bind_runner_workspace(work,repo)
            self.assertEqual(labels.read_text(),'{"private_example":"synthetic"}')
            for name,digest in report['effective_runner_sha256'].items():
                ast.parse((work/name).read_text())
                self.assertEqual(hashlib.sha256((work/name).read_bytes()).hexdigest(),digest)
                self.assertIn(repr(str(repo)),(work/name).read_text())
            self.assertIn("parser.with_name('FoodQueryDiscoveryPolicy.swift')",(work/'run_private.py').read_text())
    def test_ambiguous_binding_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            work=Path(folder)
            (work/'run_private.py').write_text("a=Path('/Users/sertanyamaner/git/WeeklyHealthReport')\nb=Path('/Users/sertanyamaner/git/WeeklyHealthReport')")
            with self.assertRaisesRegex(ValueError,'runner_workspace_binding_contract'):bind_runner_workspace(work,work)
if __name__=='__main__':unittest.main()
