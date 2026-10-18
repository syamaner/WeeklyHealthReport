"""Phase 5 (#255): the untouched pasted-text renderer reproduces the frozen generator.

Local only: it needs the FDA 188 CSV in the private folder and skips without it.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

import helpers  # noqa: F401  (puts the harness folder on sys.path)

import build_cases
import run_untouched_text

HERE = Path(__file__).resolve().parents[1]
CSV = Path.home() / "WHR-label-eval-private" / "fda-188" / "extracted" / "188_2.csv"


@unittest.skipUnless(CSV.exists(), "the FDA 188 CSV is local only (private folder)")
class FrozenGeneratorPath(unittest.TestCase):
    def test_development_split_is_reproduced_byte_for_byte(self) -> None:
        committed = [
            line
            for line in (HERE / "synthetic" / "development-cases-v1.jsonl").read_text(encoding="utf-8").splitlines()
            if line and json.loads(line)["metadata"]["corpus"] in ("fda188", "zh_template")
        ]
        rendered = [json.dumps(case, ensure_ascii=False, sort_keys=True) for case in run_untouched_text.render_rows(CSV, "development")]
        self.assertEqual(rendered, committed)

    def test_untouched_split_is_disjoint_and_labelled(self) -> None:
        self.assertEqual(
            build_cases.sha256_file(CSV), json.loads((HERE / "fixtures" / "fda-188-source-v1.json").read_text())["extracted"]["sha256"]
        )
        untouched = run_untouched_text.render_rows(CSV, "untouched")
        development = {case["id"] for case in run_untouched_text.render_rows(CSV, "development")}
        self.assertTrue(untouched)
        self.assertFalse({case["id"] for case in untouched} & development)
        self.assertTrue(all(case["metadata"]["split"] == "untouched" and case["metadata"]["synthetic"] for case in untouched))


if __name__ == "__main__":
    unittest.main()
