"""Pasted label PR 1 (#93): the frozen tables and parity vectors still match the frozen Python.

Offline and without the Swift binary: the parser output in the vectors is taken as given, and
everything the Python reference derives from it (gate v2, the arithmetic checks, the mutation
families, the declared formats) is recomputed and compared.
"""

from __future__ import annotations

import re
import unittest

import helpers  # noqa: F401  (puts the harness folder on sys.path)

import decline_gate
import export_swift_parity as export


class FrozenTables(unittest.TestCase):
    def test_simplified_only_table_is_gate_v2s_codec_rule(self) -> None:
        text = export.SIMPLIFIED_TABLE.read_text(encoding="utf-8")
        self.assertEqual(text, export.simplified_only_table())
        codes = [int(line, 16) for line in text.splitlines()]
        self.assertEqual(codes, sorted(codes))
        self.assertTrue(all(any(low <= c <= high for low, high in decline_gate.HAN_RANGES) for c in codes))
        self.assertFalse({chr(c) for c in codes} & decline_gate.SHARED_VARIANTS)

    def test_swift_version_block_records_the_table_hashes(self) -> None:
        source = (export.PACKAGE / "Sources" / "NutritionLabelParsing" / "LabelDeclineGate.swift").read_text(encoding="utf-8")
        for name, path in (("simplifiedOnlyTableSHA256", export.SIMPLIFIED_TABLE), ("markerClassesTableSHA256", export.MARKER_TABLE)):
            match = re.search(rf'{name} = "([0-9a-f]{{64}})"', source)
            self.assertIsNotNone(match)
            assert match is not None
            self.assertEqual(match.group(1), export.case_loading.sha256_file(path))

    def test_marker_structure_rebuilds_gate_v2s_pattern(self) -> None:
        self.assertEqual(export.marker_pattern(), decline_gate.SUPPLEMENT_MARKERS.pattern)
        swift = (export.PACKAGE / "Sources" / "NutritionLabelParsing" / "LabelGateTables.swift").read_text(encoding="utf-8")
        self.assertIn('static let pattern = #"' + decline_gate.SUPPLEMENT_MARKERS.pattern + '"#', swift)


class ParityVectors(unittest.TestCase):
    def test_vectors_match_the_frozen_python(self) -> None:
        self.assertEqual(export.check(), [])

    def test_untouched_fda_vectors_carry_attribution_and_the_six_misses(self) -> None:
        meta = export.json.loads(export.jsonl_lines(export.CASES)[0])
        self.assertIn(export.FDA_SET, meta["sets"])
        self.assertEqual(meta["untouched_dataset_sha256"], export.untouched_dataset_sha256())
        self.assertIn("Open Government Data License", meta["fda188_attribution"])
        truths = [
            json_line["truth"]
            for json_line in map(export.json.loads, export.jsonl_lines(export.MUTATIONS))
            if json_line["split"] == "untouched"
        ]
        outcome = export.arithmetic.mutation_detection(truths)
        self.assertEqual(outcome["overall"], {"applicable": 116, "detected": 110})

    def test_vectors_cover_every_gate_rule_and_skip(self) -> None:
        reasons: set[str] = set()
        skips: set[str] = set()
        for line in export.jsonl_lines(export.CASES)[1:]:
            report = export.json.loads(line)["expected"]["gate"]["report"]
            reasons |= {*report["declines"], *report["blocks"]}
            if report["skipped"]:
                skips.add(report["skipped"])
        self.assertEqual(
            reasons,
            {
                "unsupported_script",
                "not_a_food_nutrition_panel",
                "required_row_missing",
                "column_count_mismatch",
                "required_basis_missing",
                "required_serving_declaration_missing",
            },
        )
        self.assertEqual(skips, {"failed_candidate", "already_declined"})


if __name__ == "__main__":
    unittest.main()
