import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from build_gate_outcomes import build_outcomes, raw_filename
from evaluate import evaluate


ROOT = Path(__file__).resolve().parents[1]


class BuildGateOutcomesTests(unittest.TestCase):
    def test_raw_identity_and_frozen_policy_contract(self):
        fixture_bytes = (ROOT / "fixtures/ground-truth-v1.json").read_bytes()
        fixture = json.loads(fixture_bytes)
        contract = json.loads((ROOT / "frozen-contract-v1.json").read_text())
        gate = [panel for panel in fixture["panels"] if panel["split"] == "untouched_gate"]
        fixture_hash = hashlib.sha256(fixture_bytes).hexdigest()
        with tempfile.TemporaryDirectory() as directory:
            raw_dir = Path(directory)
            (raw_dir / "run-manifest.json").write_text(json.dumps({
                "scope": "untouched_gate", "fixture_sha256": fixture_hash,
                "vision_source_sha256": hashlib.sha256((ROOT / "vision.swift").read_bytes()).hexdigest(),
                "binary_sha256": "a" * 64,
                "panel_ids": [panel["panel_id"] for panel in gate],
            }))
            for panel in gate:
                (raw_dir / raw_filename(panel["panel_id"])).write_text(json.dumps({
                    "schemaVersion": 1, "imageSHA256": panel["image_sha256"],
                    "recognizer": "Apple Vision VNRecognizeTextRequest",
                    "recognitionLevel": "accurate", "recognitionLanguages": ["en-US"],
                    "usesLanguageCorrection": True, "observations": [],
                }))
            result = build_outcomes(fixture, fixture_hash, raw_dir, contract)
            self.assertEqual(len(result["panels"]), 40)
            self.assertTrue(all(item["declined"] for item in result["panels"]))
            self.assertEqual(sum(len(item["arithmetic_faults"]) for item in result["panels"]), 3)
            report = evaluate(contract, fixture, result)
            self.assertEqual(report["recommendation"]["decision"], "decline")
            self.assertEqual(report["failure_breakdown"]["arithmetic_mutations_undetected"], 1)
            self.assertEqual(len(report["per_panel"]), 40)
            first = gate[0]
            path = raw_dir / raw_filename(first["panel_id"])
            raw = json.loads(path.read_text())
            raw["imageSHA256"] = "0" * 64
            path.write_text(json.dumps(raw))
            with self.assertRaisesRegex(ValueError, "raw recognizer identity mismatch"):
                build_outcomes(fixture, fixture_hash, raw_dir, contract)


if __name__ == "__main__":
    unittest.main()
