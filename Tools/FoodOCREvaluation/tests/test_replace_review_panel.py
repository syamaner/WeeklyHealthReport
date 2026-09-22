import unittest

from prepare_review import selection_key
from replace_review_panel import replacement_for


class ReplaceReviewPanelTests(unittest.TestCase):
    def test_next_unused_same_split_english_candidate(self):
        manifest = {"panels": [
            {"panel_id": "used", "split": "untouched_gate", "source": {"image_language": "en"}},
            {"panel_id": "tuning", "split": "tuning", "source": {"image_language": "en"}},
            {"panel_id": "foreign", "split": "untouched_gate", "source": {"image_language": "fr"}},
            {"panel_id": "spare-b", "split": "untouched_gate", "source": {"image_language": "en"}},
            {"panel_id": "spare-a", "split": "untouched_gate", "source": {"image_language": "en"}},
        ]}
        selection = {"panels": [{"review_index": 3, "panel_id": "used", "split": "untouched_gate"}]}
        expected = min(("spare-a", "spare-b"), key=selection_key)
        self.assertEqual(replacement_for(manifest, selection, 3)["panel_id"], expected)


if __name__ == "__main__":
    unittest.main()
