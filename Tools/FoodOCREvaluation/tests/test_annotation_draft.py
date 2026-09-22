from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from build_annotation_draft import propose_semantic_families


class AnnotationDraftTests(unittest.TestCase):
    def test_only_objective_semantic_families_are_proposed(self) -> None:
        result = {
            "headers": [{"basis": "per_100g"}, {"basis": "per_serving"}],
        }
        families = propose_semantic_families("Fat\nof which saturates <0.1g\nSalt 1g", result)
        self.assertEqual(
            families,
            ["bound", "multi_column", "nested_rows", "per_100g", "per_serving", "salt"],
        )
        self.assertNotIn("glossy", families)


if __name__ == "__main__":
    unittest.main()
