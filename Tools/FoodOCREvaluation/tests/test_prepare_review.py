from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from prepare_review import bases_from_text, cells_from_text, select_panels, transcript_score


class PrepareReviewTests(unittest.TestCase):
    def test_selection_is_deterministic_and_balanced(self) -> None:
        manifest = {"panels": [
            {"panel_id": f"t-{index}", "split": "tuning"} for index in range(70)
        ] + [
            {"panel_id": f"g-{index}", "split": "untouched_gate"} for index in range(50)
        ]}
        first = select_panels(manifest)
        second = select_panels(manifest)
        self.assertEqual(first, second)
        self.assertEqual(len(first), 100)
        self.assertEqual(sum(item["split"] == "tuning" for item in first), 60)
        self.assertEqual(sum(item["split"] == "untouched_gate" for item in first), 40)

    def test_text_draft_preserves_bounds_and_nested_rows(self) -> None:
        text = "Typical values per 100g\nFat 10g\nof which saturates <0.1g\nSalt 0.5g"
        self.assertEqual(bases_from_text(text), ["per_100g"])
        cells = cells_from_text(text)
        saturates = next(cell for cell in cells if cell["row_id"] == "saturates")
        self.assertEqual(saturates["parent_row_id"], "fat")
        self.assertEqual(saturates["comparator"], "<")
        self.assertEqual(saturates["printed_text"], "<0.1g")

    def test_fragmented_public_ocr_rows_are_structured(self) -> None:
        text = "Typical values\nPer\n100g\n1/2 of a pack (190g)\nEnergy\n455kJ\n865kJ\n108kcal\n206kcal\nFat\n3.4g\n6.4g\nSalt\n0.55g\n1.04g"
        self.assertEqual(bases_from_text(text), ["per_100g", "per_serving"])
        cells = cells_from_text(text)
        self.assertEqual(len(cells), 8)
        self.assertEqual(
            {(cell["row_id"], cell["basis"], cell["printed_text"]) for cell in cells if cell["row_id"].startswith("energy")},
            {
                ("energy_kj", "per_100g", "455kJ"),
                ("energy_kj", "per_serving", "865kJ"),
                ("energy_kcal", "per_100g", "108kcal"),
                ("energy_kcal", "per_serving", "206kcal"),
            },
        )

    def test_transcript_score_prefers_nutrition_content(self) -> None:
        self.assertGreater(
            transcript_score("Energy 100kJ\nFat 2g\nProtein 3g"),
            transcript_score("random package words"),
        )


if __name__ == "__main__":
    unittest.main()
