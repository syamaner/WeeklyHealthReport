from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from validate_contract import validate


class ContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = json.loads((ROOT / "frozen-contract-v1.json").read_text())

    def test_frozen_contract_is_valid(self) -> None:
        validate(self.contract)

    def test_contract_rejects_automatic_save(self) -> None:
        self.contract["policy"]["automatic_save"] = True
        with self.assertRaisesRegex(ValueError, "unsafe promotion policy"):
            validate(self.contract)

    def test_contract_rejects_nonzero_false_save_tolerance(self) -> None:
        self.contract["metrics"]["false_save_maximum"] = 0.01
        with self.assertRaisesRegex(ValueError, "false-save tolerance"):
            validate(self.contract)


if __name__ == "__main__":
    unittest.main()
