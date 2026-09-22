import hashlib
import json
import unittest
from pathlib import Path

from build_gate_outcomes import build_outcomes
from evaluate import evaluate


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "fixtures"


def canonical_json(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


class FrozenGateResultTests(unittest.TestCase):
    def test_raw_run_replays_to_identical_decline_report(self):
        fixture_bytes = (FIXTURES / "ground-truth-v1.json").read_bytes()
        fixture = json.loads(fixture_bytes)
        contract = json.loads((ROOT / "frozen-contract-v1.json").read_text())
        outcomes = build_outcomes(
            fixture, hashlib.sha256(fixture_bytes).hexdigest(),
            FIXTURES / "untouched-vision-raw-v1", contract,
        )
        self.assertEqual(
            canonical_json(outcomes), (FIXTURES / "untouched-outcomes-v1.json").read_bytes()
        )
        report = evaluate(contract, fixture, outcomes)
        self.assertEqual(
            canonical_json(report), (FIXTURES / "untouched-report-v1.json").read_bytes()
        )
        self.assertEqual(report["recommendation"]["decision"], "decline")
        self.assertEqual(report["failure_breakdown"]["silent_false_saves"], 4)


if __name__ == "__main__":
    unittest.main()
