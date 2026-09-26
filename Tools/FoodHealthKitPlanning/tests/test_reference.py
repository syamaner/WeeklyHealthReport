from dataclasses import replace
from decimal import Decimal
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from reference import (Contribution, SyntheticSample, UNITS, prepare, readback_matches,
                       removable, selected_source_total)


def contribution(identifier="one", **changes):
    return replace(Contribution(identifier, "log-a", "log-version-1", "protein", "measured", "10", "g"), **changes)


class PlanningReferenceTests(unittest.TestCase):
    def test_all_39_plan_mappings_and_units_match_read_catalogue(self):
        repo = ROOT
        document = (repo / "docs/food-healthkit-write-plan.md").read_text()
        rows = re.findall(r"^\| ([a-z][a-z0-9_]*) \| (dietary[A-Za-z0-9]+) \| (kcal|g|mg|mcg|mL) \|$", document, re.M)
        identifiers = re.findall(r'"([a-z0-9_]+)": \.(dietary[A-Za-z0-9]+)', (repo / "WeeklyHealthReport/HealthKit/NutritionQueryCatalogue.swift").read_text())
        catalogue = re.findall(r'\.init\(key: "([a-z0-9_]+)".*unit: \.([A-Za-z]+)\)', (repo / "WeeklyHealthReport/Models/NutritionExport.swift").read_text())
        units = dict(kilocalories="kcal", grams="g", milligrams="mg", micrograms="mcg", millilitres="mL")
        self.assertEqual(len(rows), 39)
        self.assertEqual(sorted((key, kind) for key, kind, _ in rows), sorted(identifiers))
        self.assertEqual({key: unit for key, _, unit in rows}, UNITS)
        self.assertEqual({key: units[unit] for key, unit in catalogue}, UNITS)

    def test_exact_combination_preserves_unit_scaling_and_retry_identity(self):
        values = [contribution(), contribution("two", state="augmented", amount="2000", unit="mg")]
        intents, omitted = prepare(values, "writer-a", 1)
        self.assertFalse(omitted)
        self.assertEqual(intents[0].amount, Decimal(12))
        self.assertEqual(prepare(list(reversed(values)), "writer-a", 1), (intents, omitted))
        self.assertEqual(prepare(values, "writer-a", 2)[0][0].sync_key, intents[0].sync_key)

    def test_each_canonical_nutrient_is_checked_and_large_precision_is_not_rounded(self):
        for key, unit in UNITS.items():
            intents, omitted = prepare([contribution(nutrient=key, unit=unit, amount="1")], "writer-a", 1)
            self.assertFalse(omitted)
            self.assertEqual(intents[0].amount, 1)
        amount = "1.12345678901234567890123456789012345"
        intent = prepare([contribution(amount=amount)], "writer-a", 1)[0][0]
        self.assertEqual(intent.amount, Decimal(amount))

    def test_unknown_component_omits_whole_item_not_other_items(self):
        values = [contribution(), contribution("unknown", state="unknown", amount=None),
                  contribution("separate", log_id="log-b")]
        intents, omitted = prepare(values, "writer-a", 1)
        self.assertEqual([(item.log_id, item.amount) for item in intents], [("log-b", Decimal(10))])
        self.assertEqual(omitted["log-a", "protein"], ("non_scalar_state",))

    def test_unsafe_values_never_become_zero_or_scalar(self):
        for changes in [dict(state="bounded"), dict(state="unknown"), dict(amount="NaN"),
                        dict(amount="Infinity"), dict(amount="-1"), dict(amount=None),
                        dict(amount=1.5),
                        dict(unit="IU"), dict(unit="mL"), dict(compatible_form=False),
                        dict(conflict=True), dict(confirmed_quantity_and_identity=False),
                        dict(nutrient="unknown-key")]:
            with self.subTest(changes=changes):
                intents, omitted = prepare([contribution(**changes)], "writer-a", 1)
                self.assertFalse(intents)
                self.assertTrue(omitted)

    def test_evidenced_zero_and_volume_and_micrograms(self):
        for key, amount, unit, expected in [("water", "0", "mL", "0"), ("water", "0.5", "L", "500"),
                                            ("vitamin_b12", "0.002", "mg", "2")]:
            intents, _ = prepare([contribution(nutrient=key, amount=amount, unit=unit)], "writer-a", 1)
            self.assertEqual(intents[0].amount, Decimal(expected))

    def test_duplicate_contributions_and_mixed_versions_fail_closed(self):
        for values in [[contribution(), contribution()],
                       [contribution(), contribution("two", log_version="different")],
                       [contribution(), contribution("two", occurred_at=200)],
                       [contribution(log_version="")]]:
            with self.assertRaises(ValueError):
                prepare(values, "writer-a", 1)
        for writer, revision in [("writer:ambiguous", 1), ("writer-a", 0), ("writer-a", True)]:
            with self.assertRaises(ValueError):
                prepare([contribution()], writer, revision)

    def test_readback_rejects_duplicate_and_changed_output(self):
        intent = prepare([contribution()], "writer-a", 1)[0][0]
        sample = SyntheticSample("owned", "this-app", intent, 100)
        self.assertTrue(readback_matches(intent, [sample], "this-app"))
        self.assertFalse(readback_matches(intent, [sample, replace(sample, uuid="duplicate")], "this-app"))
        self.assertFalse(readback_matches(intent, [replace(sample, intent=replace(intent, amount=Decimal(11)))], "this-app"))
        self.assertFalse(readback_matches(intent, [replace(sample, source="other-app")], "this-app"))
        self.assertFalse(readback_matches(intent, [replace(sample, timestamp=200)], "this-app"))

    def test_removal_requires_exact_uuid_source_namespace_and_version(self):
        intent = prepare([contribution()], "writer-a", 1)[0][0]
        sample = SyntheticSample("owned", "this-app", intent, 100)
        foreign = [replace(sample, uuid="not-journalled"), replace(sample, source="other-app"),
                   replace(sample, intent=replace(intent, writer="other-writer")),
                   replace(sample, intent=replace(intent, revision=2)),
                   replace(sample, intent=replace(intent, nutrient="sugar")), replace(sample, timestamp=200)]
        self.assertEqual(removable([sample] + foreign, "this-app", {"owned": intent}), (sample,))
        self.assertEqual(removable([sample], "this-app", {}), ())

    def test_source_query_is_half_open_and_missing_is_not_zero(self):
        intent = prepare([contribution()], "writer-a", 1)[0][0]
        sample = SyntheticSample("owned", "this-app", intent, 100)
        samples = [sample, replace(sample, uuid="other", source="other-app"),
                   replace(sample, uuid="end", timestamp=200), replace(sample, uuid="before", timestamp=99)]
        self.assertEqual(selected_source_total(samples, "this-app", "protein", 100, 200), Decimal(10))
        self.assertIsNone(selected_source_total(samples, "missing", "protein", 100, 200))


if __name__ == "__main__":
    unittest.main()
