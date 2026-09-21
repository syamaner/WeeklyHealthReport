from __future__ import annotations

import gzip
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from evaluate import canonical_json, load_and_verify


class FixtureIntegrityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = json.loads((ROOT / "frozen-contract-v1.json").read_text())
        cls.corpus = json.loads(gzip.decompress((ROOT / "fixtures/cofid-2021-evaluation-v1.json.gz").read_bytes()))
        cls.gold = json.loads((ROOT / "fixtures/gold-set-v1.json").read_text())
        cls.report = json.loads((ROOT / "result-v1.json").read_text())

    def test_fixture_hash_mismatch_fails_closed(self) -> None:
        corpus = canonical_json({"records": [], "source": {}})
        gold = canonical_json({"cases": [], "synthetic_records": []})
        with tempfile.TemporaryDirectory() as directory:
            corpus_path = Path(directory) / "corpus.json.gz"
            gold_path = Path(directory) / "gold.json"
            corpus_path.write_bytes(gzip.compress(corpus, mtime=0))
            gold_path.write_bytes(gold)
            contract = {
                "fixtures": {
                    "corpus_gzip_sha256": "0" * 64,
                    "corpus_canonical_sha256": hashlib.sha256(corpus).hexdigest(),
                    "gold_sha256": hashlib.sha256(gold).hexdigest(),
                }
            }
            with self.assertRaisesRegex(ValueError, "corpus_gzip_sha256 mismatch"):
                load_and_verify(contract, corpus_path, gold_path)

    def test_noncanonical_gold_fails_closed_even_with_matching_hash(self) -> None:
        corpus = canonical_json({"records": [], "source": {}})
        gold = b'{ "cases": [], "synthetic_records": [] }\n'
        with tempfile.TemporaryDirectory() as directory:
            corpus_path = Path(directory) / "corpus.json.gz"
            gold_path = Path(directory) / "gold.json"
            corpus_gzip = gzip.compress(corpus, mtime=0)
            corpus_path.write_bytes(corpus_gzip)
            gold_path.write_bytes(gold)
            contract = {
                "fixtures": {
                    "corpus_gzip_sha256": hashlib.sha256(corpus_gzip).hexdigest(),
                    "corpus_canonical_sha256": hashlib.sha256(corpus).hexdigest(),
                    "gold_sha256": hashlib.sha256(gold).hexdigest(),
                }
            }
            with self.assertRaisesRegex(ValueError, "gold set is not canonical JSON"):
                load_and_verify(contract, corpus_path, gold_path)

    def test_committed_fixtures_match_the_frozen_hashes(self) -> None:
        loaded_corpus, loaded_gold = load_and_verify(
            self.contract,
            ROOT / "fixtures/cofid-2021-evaluation-v1.json.gz",
            ROOT / "fixtures/gold-set-v1.json",
        )
        self.assertEqual(loaded_corpus, self.corpus)
        self.assertEqual(loaded_gold, self.gold)

    def test_corpus_preserves_source_and_canonical_water_units(self) -> None:
        water = self.corpus["records"][0]["nutrients"]["water"]
        self.assertEqual(water["source_unit"], "g")
        self.assertEqual(water["canonical_unit"], "mL")
        self.assertNotIn("unit", water)

    def test_corpus_preserves_published_mass_and_volume_serving_bases(self) -> None:
        alcoholic = [record for record in self.corpus["records"] if record["published_group"].startswith("Q")]
        non_alcoholic = [record for record in self.corpus["records"] if not record["published_group"].startswith("Q")]
        self.assertTrue(alcoholic)
        self.assertTrue(non_alcoholic)
        self.assertEqual({record["identity"]["serving_basis"] for record in alcoholic}, {"per_100_ml"})
        self.assertEqual({record["identity"]["serving_basis"] for record in non_alcoholic}, {"per_100_g"})

    def test_gold_set_meets_size_split_and_hard_family_contract(self) -> None:
        self.assertEqual(len(self.gold["cases"]), 1280)
        self.assertEqual(self.gold["personal_gate"]["status"], "deferred")
        self.assertEqual({case["split"] for case in self.gold["cases"]}, {"tuning", "calibration", "gate"})
        families = {case["family"] for case in self.gold["cases"]}
        for field in ("preparation", "bone", "skin", "drained", "packing_medium", "fortification", "salt_state", "serving_basis"):
            self.assertIn(f"hard_negative_{field}", families)

    def test_policy_and_report_never_promote_automatic_acceptance(self) -> None:
        self.assertFalse(self.contract["policy"]["automatic_acceptance"])
        self.assertEqual(self.report["recommendation"]["decision"], "keep_user_selection_only")
        self.assertEqual(self.report["recommendation"]["automatic_acceptance"], "disabled")
        self.assertFalse(self.report["gate"]["automatic_acceptance_eligible"])

    def test_report_retains_complete_failure_taxonomy(self) -> None:
        self.assertEqual(
            set(self.report["metrics"]["failures"]),
            {"retrieval_miss", "hard_rule_failure", "ranking_failure", "explanation_failure", "calibration_failure", "action_failure"},
        )
        self.assertEqual(self.report["metrics"]["catastrophic_hard_negative_acceptances"], 0)


if __name__ == "__main__":
    unittest.main()
