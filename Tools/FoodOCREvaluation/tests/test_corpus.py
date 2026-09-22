from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from corpus import split_for, validate_ground_truth, validate_manifest


class CorpusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = json.loads((ROOT / "frozen-contract-v1.json").read_text())

    def test_split_is_deterministic(self) -> None:
        digest = "a" * 64
        self.assertEqual(split_for("off:123:nutrition_en:1", digest), split_for("off:123:nutrition_en:1", digest))

    def test_manifest_rejects_hand_picked_split(self) -> None:
        digest = "b" * 64
        expected = split_for("off:123:nutrition_en:1", digest)
        wrong = "untouched_gate" if expected == "tuning" else "tuning"
        manifest = {
            "schema_version": 1,
            "panels": [{
                "panel_id": "off:123:nutrition_en:1",
                "image_sha256": digest,
                "split": wrong,
                "country_tag": "en:united-kingdom",
                "families": [],
                "source": {"image_url": "https://images.openfoodfacts.org/example.jpg"},
                "ground_truth": {"verification_status": "pending"},
            }],
        }
        with self.assertRaisesRegex(ValueError, "split mismatch"):
            validate_manifest(manifest, self.contract, require_complete=False)

    def test_ground_truth_verification_must_match_image_hash(self) -> None:
        panel = {
            "panel_id": "off:123:nutrition_en:1",
            "image_sha256": "a" * 64,
            "ground_truth": {
                "verification_status": "independently_verified",
                "full_transcript": "Energy 10 kJ",
                "cells": [],
                "review": {
                    "reviewer": "reviewer-1",
                    "verified_at": "2026-09-22T00:00:00Z",
                    "verified_against_image_sha256": "b" * 64,
                },
            },
        }
        with self.assertRaisesRegex(ValueError, "not tied to its image hash"):
            validate_ground_truth(panel)


if __name__ == "__main__":
    unittest.main()
