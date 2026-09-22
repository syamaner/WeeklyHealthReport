import json
import unittest
from pathlib import Path

from arithmetic_mutations import MUTATIONS, mutation_probes


ROOT = Path(__file__).resolve().parents[1]


class ArithmeticMutationTests(unittest.TestCase):
    def test_frozen_real_label_probes_are_deterministic_and_fail_closed(self):
        manifest = json.loads((ROOT / "fixtures/ground-truth-v1.json").read_text())
        contract = json.loads((ROOT / "frozen-contract-v1.json").read_text())
        probes = mutation_probes(manifest, contract["arithmetic_faults"]["seed"])
        all_cases = [case for cases in probes.values() for case in cases]
        self.assertEqual({case["mutation"] for case in all_cases}, set(MUTATIONS))
        self.assertEqual(len(all_cases), 3)
        by_type = {case["mutation"]: case["detected"] for case in all_cases}
        self.assertTrue(by_type[MUTATIONS[0]])
        self.assertTrue(by_type[MUTATIONS[1]])
        self.assertFalse(by_type[MUTATIONS[2]])


if __name__ == "__main__":
    unittest.main()
