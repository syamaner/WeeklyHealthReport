from __future__ import annotations

import sys
import unittest
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from parser import classify_basis, interval_for, normalize_label, parse_value


class ParserTests(unittest.TestCase):
    def test_parses_and_preserves_bound(self) -> None:
        parsed = parse_value("<0.1 g")
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual((parsed.comparator, parsed.decimal_text, parsed.unit), ("<", "0.1", "g"))
        self.assertEqual(interval_for(parsed), (Decimal(0), Decimal("0.1")))
        self.assertFalse(parsed.persistence_authorized)

    def test_parses_decimal_comma_without_authorizing_save(self) -> None:
        parsed = parse_value("2,5 mg")
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed.numeric_value, Decimal("2.5"))
        self.assertFalse(parsed.persistence_authorized)

    def test_classifies_only_explicit_bases(self) -> None:
        self.assertEqual(classify_basis("Per 100 g"), "per_100g")
        self.assertEqual(classify_basis("Per serving"), "per_serving")
        self.assertEqual(classify_basis("per 1/2 pack"), "per_serving")
        self.assertEqual(classify_basis("% adult RI"), "reference_intake")
        self.assertEqual(classify_basis("% RI"), "reference_intake")
        self.assertIsNone(classify_basis("Typical values"))

    def test_label_normalization_does_not_change_meaning(self) -> None:
        self.assertEqual(normalize_label("  of which   sugars "), "of which sugars")


if __name__ == "__main__":
    unittest.main()
