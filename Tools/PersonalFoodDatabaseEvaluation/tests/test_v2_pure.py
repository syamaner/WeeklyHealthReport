"""Contract tests for the pure v2 review modules (synthetic data only).

Design: docs/personal-food-database-review-v2-design.md, section 7.
"""
import json
import re
import sys
import unittest

import helpers as H

sys.path.insert(0, str(H.HERE / "v2"))

import bars  # noqa: E402
import bars_v2  # noqa: E402
import exclusions  # noqa: E402
import formats  # noqa: E402
import formats_v2 as F2  # noqa: E402
import results  # noqa: E402
import results_v2  # noqa: E402
import score_a_v2  # noqa: E402

INVENTORY_BYTES = (H.HERE / "nutrient-inventory-v1.json").read_bytes()
INV = F2.parse_inventory(INVENTORY_BYTES)
SECRET = "Synthetic Secret Title"

GOOD = {
    "A1": ("same_food", "same_state", "same_or_immaterial", "not_applicable"),
    "A5": ("same_food", "same_state", "same_or_immaterial", "not_applicable"),
    "A2": ("same_food", "same_state", "same_or_immaterial", "merge_ok"),
    "A3": ("same_food", "same_state", "same_or_immaterial", "sensible"),
    "A4": ("unresolved", "unresolved", "unresolved", "nothing_suitable"),
}


def make_sample(a1=3, a5=1, a2=4, a3=4, a4=3):
    entries, n = [], 1
    for s, count in (("A1", a1), ("A5", a5), ("A2", a2), ("A3", a3), ("A4", a4)):
        for i in range(count):
            reason = ("top30" if i == 0 else "census") if s in ("A1", "A5") else "draw"
            entries.append({"entry_id": H.eid(n), "stratum": s, "reason": reason})
            n += 1
    quotas = {"A1": a1, "A5": a5, "A2": a2, "A3": a3, "A4": a4}
    return {"schema": "pfd-sample-v1", "release_id": H.RELEASE, "seed": 1, "quotas": quotas, "entries": entries,
            "replacements": {"A2": [H.eid(900)], "A3": [], "A4": []}}


def make_rows(sample, overrides=None):
    """Filled sheet rows (dicts of strings); overrides maps a row number to (identity, state, variety, outcome)."""
    rows = []
    for r in F2.sheet_template(sample):
        tokens = (overrides or {}).get(int(r["row"]), GOOD[r["stratum"]])
        rows.append({**r, **dict(zip(("identity", "state", "variety", "outcome"), tokens))})
    return rows


def rec(row, nutrient, assessment="correct", state_basis="source_states_it"):
    filled = assessment not in F2.NOT_ASSESSED
    return {"schema": F2.EVIDENCE_SCHEMA, "row": str(row), "nutrient": nutrient, "assessment": assessment,
            "source_kind": "pinned_release" if filled else "", "state_basis": state_basis if filled else "",
            "method": "direct" if filled else ""}


def make_records(rows, values=None, state_basis="source_states_it"):
    """Full coverage for A1, A2 and A5 rows and one match record per match_missed A4 row; values maps
    (row number, nutrient) to an assessment token."""
    out = []
    for r in rows:
        n = int(r["row"])
        if r["stratum"] in F2.FULL_COVERAGE:
            out += [rec(n, k, (values or {}).get((n, k), "correct"), state_basis) for k in INV["keys"]]
        elif r["stratum"] == "A4" and r["outcome"] == "match_missed":
            out.append(rec(n, "energy_consumed", "match_available", state_basis))
    return out


def sheet(rows):
    return F2.parse_sheet(F2.write_sheet(rows))


def evidence(records):
    return F2.parse_evidence(F2.write_evidence(records), INV)


def row_of(sample, stratum, i=0):
    return [n for n, e in enumerate(sample["entries"], start=1) if e["stratum"] == stratum][i]


class Inventory(unittest.TestCase):
    def test_equals_the_nutrition_export_keys_under_the_explicit_grouping(self):
        swift = (H.REPO / "WeeklyHealthReport" / "Models" / "NutritionExport.swift").read_text(encoding="utf-8")
        keys = re.findall(r'\.init\(key: "([^"]+)"', swift)
        self.assertEqual(len(keys), 39)
        self.assertEqual(len(set(keys)), 39)
        self.assertEqual(set(INV["keys"]), set(keys))
        self.assertEqual({g: len(INV["groups"][g]) for g in F2.GROUPS}, {"macro": 8, "micro": 26, "other": 5})
        self.assertEqual(set(INV["groups"]["macro"]), set(formats.NUTRIENTS))  # the v1 eight
        self.assertEqual(set(INV["groups"]["other"]),
                         {"water", "cholesterol", "fat_monounsaturated", "fat_polyunsaturated", "caffeine"})
        self.assertNotIn("salt", INV["keys"])

    def test_round_trips_and_refuses_a_changed_shape(self):
        self.assertEqual(F2.write_inventory(F2.parse_inventory(INVENTORY_BYTES)), INVENTORY_BYTES)
        doc = json.loads(INVENTORY_BYTES)
        moved = json.loads(INVENTORY_BYTES)
        moved["groups"]["other"].append(moved["groups"]["micro"].pop())
        twice = json.loads(INVENTORY_BYTES)
        twice["groups"]["micro"][0] = "sodium"
        for bad in (moved, twice, {**doc, "schema": "pfd-nutrient-inventory-v2"}, {**doc, "note": "x"},
                    {**doc, "groups": {**doc["groups"], "extra": []}}):
            with self.assertRaises(formats.FormatError):
                F2.parse_inventory(formats.dumps(bad))


class Sheet(unittest.TestCase):
    def setUp(self):
        self.sample = make_sample()

    def test_round_trip_and_template_refused_until_filled(self):
        data = F2.write_sheet(make_rows(self.sample))
        self.assertEqual(F2.write_sheet(F2.parse_sheet(data)), data)
        self.assertEqual(len(F2.parse_sheet(data)), len(self.sample["entries"]))
        with self.assertRaises(formats.FormatError) as e:
            F2.parse_sheet(F2.write_sheet(F2.sheet_template(self.sample)))
        self.assertIn("blank cell", str(e.exception))

    def test_blank_unknown_order_replacement_and_no_echo(self):
        for change in ({"variety": ""}, {"identity": SECRET}, {"row": "7"}, {"row": SECRET}, {"reason": "replacement"},
                       {"schema": "pfd-review-sheet-v1"}, {"entry_id": SECRET}, {"stratum": "A6"}, {"outcome": ""}):
            rows = make_rows(self.sample)
            rows[0].update(change)
            with self.assertRaises(formats.FormatError) as e:
                F2.parse_sheet(F2.write_sheet(rows))
            self.assertNotIn(SECRET, str(e.exception))
            self.assertIn("line 2", str(e.exception))

    def test_v1_and_v2_sheets_are_refused_by_the_other_parser(self):
        with self.assertRaises(formats.FormatError):
            formats.parse_sheet(F2.write_sheet(make_rows(self.sample)))
        v1 = formats.write_sheet([{"schema": formats.SHEET_SCHEMA, "row": 1, "stratum": "A4", "reason": "draw",
                                   "entry_id": H.eid(1), "verdict": "nothing_suitable"}])
        with self.assertRaises(formats.FormatError):
            F2.parse_sheet(v1)

    def test_every_refused_combination_is_refused(self):
        refused = [
            ("A1", ("same_food", "same_state", "same_or_immaterial", "merge_ok")),
            ("A5", ("same_food", "same_state", "same_or_immaterial", "sensible")),
            ("A2", ("different_food", "same_state", "same_or_immaterial", "merge_ok")),
            ("A2", ("same_food", "unresolved", "same_or_immaterial", "merge_ok")),
            ("A2", ("same_food", "same_state", "same_or_immaterial", "merge_failed")),
            ("A2", ("unresolved", "same_state", "same_or_immaterial", "merge_failed")),
            ("A2", ("same_food", "same_state", "material_difference", "unresolved")),
            ("A2", ("same_food", "same_state", "same_or_immaterial", "unresolved")),
            ("A2", ("same_food", "same_state", "same_or_immaterial", "not_applicable")),
            ("A3", ("different_food", "same_state", "same_or_immaterial", "sensible")),
            ("A3", ("same_food", "same_state", "material_difference", "misleading_other_state")),
            ("A3", ("same_food", "unresolved", "same_or_immaterial", "sensible")),
            ("A3", ("same_food", "same_state", "same_or_immaterial", "unresolved")),
            ("A3", ("different_food", "unresolved", "same_or_immaterial", "unresolved")),  # misleading whatever is open
            ("A4", ("same_food", "unresolved", "same_or_immaterial", "match_missed")),
            ("A4", ("same_food", "unresolved", "unresolved", "nothing_suitable")),
            ("A4", ("unresolved", "unresolved", "unresolved", "sensible")),
        ]
        for stratum, tokens in refused:
            with self.subTest(stratum=stratum, tokens=tokens), self.assertRaises(formats.FormatError):
                sheet(make_rows(self.sample, {row_of(self.sample, stratum): tokens}))

    def test_allowed_combinations_are_accepted(self):
        allowed = [
            ("A1", ("different_food", "unresolved", "material_difference", "not_applicable")),
            ("A1", ("unresolved", "same_state", "same_or_immaterial", "not_applicable")),
            ("A2", ("unresolved", "same_state", "material_difference", "merge_failed")),
            ("A2", ("same_food", "unresolved", "same_or_immaterial", "unresolved")),
            ("A3", ("same_food", "different_state", "same_or_immaterial", "sensible")),  # a labelled alternative state
            ("A3", ("same_food", "same_state", "material_difference", "sensible")),
            ("A3", ("same_food", "different_state", "unresolved", "misleading_other_state")),
            ("A3", ("unresolved", "same_state", "same_or_immaterial", "misleading_close")),
            ("A3", ("unresolved", "same_state", "same_or_immaterial", "unresolved")),
            ("A4", ("same_food", "same_state", "same_or_immaterial", "unresolved")),
        ]
        for stratum, tokens in allowed:
            with self.subTest(stratum=stratum, tokens=tokens):
                sheet(make_rows(self.sample, {row_of(self.sample, stratum): tokens}))

    def test_stated_assumption_needs_its_sidecar_basis(self):
        n = row_of(self.sample, "A2")
        rows = sheet(make_rows(self.sample, {n: ("same_food", "compatible_with_stated_assumption", "same_or_immaterial",
                                                 "merge_ok")}))
        with self.assertRaises(formats.FormatError):
            F2.check_bundle(rows, evidence(make_records(rows)), INV)
        recs = [r if r["row"] != str(n) else rec(n, r["nutrient"], "correct", "stated_assumption") for r in make_records(rows)]
        F2.check_bundle(rows, evidence(recs), INV)
        self.assertEqual(F2.check_status(rows[n - 1], "state"), "pass")
        a3 = row_of(self.sample, "A3")  # A3 rows supply no values, so the token can never be supported there
        rows3 = sheet(make_rows(self.sample, {a3: ("same_food", "compatible_with_stated_assumption", "same_or_immaterial",
                                                   "sensible")}))
        with self.assertRaises(formats.FormatError):
            F2.check_bundle(rows3, evidence(make_records(rows3)), INV)

    def test_match_missed_needs_its_sidecar_record(self):
        n = row_of(self.sample, "A4")
        rows = sheet(make_rows(self.sample, {n: ("same_food", "same_state", "same_or_immaterial", "match_missed")}))
        recs = make_records(rows)
        F2.check_bundle(rows, evidence(recs), INV)
        with self.assertRaises(formats.FormatError):
            F2.check_bundle(rows, evidence([r for r in recs if r["row"] != str(n)]), INV)
        with self.assertRaises(formats.FormatError):
            F2.check_bundle(rows, evidence([r if r["row"] != str(n) else rec(n, "protein", "match_available") for r in recs]),
                            INV)


class Sidecar(unittest.TestCase):
    def setUp(self):
        self.sample = make_sample()
        self.rows = sheet(make_rows(self.sample))
        self.recs = make_records(self.rows)

    def bundle(self, recs):
        return F2.check_bundle(self.rows, evidence(recs), INV)

    def test_round_trip(self):
        data = F2.write_evidence(self.recs)
        self.assertEqual(F2.write_evidence(F2.parse_evidence(data, INV)), data)
        self.bundle(self.recs)

    def test_missing_or_duplicate_key_refused(self):
        with self.assertRaises(formats.FormatError):
            self.bundle(self.recs[1:])
        with self.assertRaises(formats.FormatError):
            evidence(self.recs + [self.recs[0]])

    def test_records_outside_the_coverage_rule_refused(self):
        a3, a4, a1 = row_of(self.sample, "A3"), row_of(self.sample, "A4"), row_of(self.sample, "A1")
        for extra in (rec(a3, "protein"), rec(a4, "energy_consumed", "match_available"), rec(999, "protein")):
            with self.subTest(extra=extra["row"]), self.assertRaises(formats.FormatError):
                self.bundle(self.recs + [extra])
        swapped = [r if (r["row"], r["nutrient"]) != (str(a1), "protein") else rec(a1, "protein", "match_available")
                   for r in self.recs]
        with self.assertRaises(formats.FormatError):
            self.bundle(swapped)

    def test_extra_fields_non_strings_and_unknown_keys_refused_without_echo(self):
        base = self.recs[0]
        for bad in ({**base, "value": SECRET}, {**base, "url": SECRET}, {**base, "title": SECRET},
                    {**base, "row": 1}, {**base, "assessment": None}, {**base, "source_kind": 0},
                    {**base, "nutrient": "salt"}, {**base, "assessment": SECRET}, {**base, "row": "01"},
                    {k: v for k, v in base.items() if k != "method"}):
            data = (json.dumps(bad) + "\n").encode()
            with self.assertRaises(formats.FormatError) as e:
                F2.parse_evidence(data, INV)
            self.assertNotIn(SECRET, str(e.exception))
        with self.assertRaises(formats.FormatError):
            F2.parse_evidence(F2.write_evidence(self.recs[:1]) + b"\n" + F2.write_evidence(self.recs[1:2]), INV)  # blank line

    def test_empty_source_fields_enforced(self):
        for token in F2.NOT_ASSESSED:
            with self.assertRaises(formats.FormatError):
                F2.parse_evidence((json.dumps({**rec(1, "protein", token), "source_kind": "aggregator"}) + "\n").encode(), INV)
            F2.parse_evidence((json.dumps(rec(1, "protein", token)) + "\n").encode(), INV)
        for token in ("correct", "error_basis", "match_available"):
            with self.assertRaises(formats.FormatError):
                F2.parse_evidence((json.dumps({**rec(1, "protein", token), "method": ""}) + "\n").encode(), INV)


def score(sample, rows, recs, bar_set="v2_proposed"):
    return score_a_v2.score(sample, sheet(rows), evidence(recs), INV, bar_set)


class Scoring(unittest.TestCase):
    def setUp(self):
        self.sample = make_sample(a1=4, a5=1, a2=4, a3=4, a4=3)
        self.a1 = [row_of(self.sample, "A1", i) for i in range(4)]

    def test_all_good_passes_under_v2_proposed(self):
        rows = make_rows(self.sample)
        m = score(self.sample, rows, make_records(rows))
        for name in ("a1_wrong_identity_state_or_variety", "a1_value_evidence_errors",
                     "a2_different_food_or_other_state", "a3_misleading", "a5_value_evidence_errors"):
            self.assertTrue(m[name]["passes"], name)
        for name in ("a1_macro_value_evidence_errors", "a1_micro_value_evidence_errors"):
            self.assertNotIn("passes", m[name])  # informational: the one value bar covers both together
        self.assertEqual(m["a1_value_evidence_errors"]["of"], 4 * 34)
        self.assertEqual(m["a1_macro_value_evidence_errors"]["of"], 4 * 8)
        self.assertEqual(m["a1_micro_value_evidence_errors"]["of"], 4 * 26)
        self.assertEqual(m["a4_match_missed"], {"count": 0, "of": 3, "interval": m["a4_match_missed"]["interval"]})
        self.assertNotIn("a1_nutrient_disagreements_not_assessable", m)

    def test_precedence_one_count_per_entry_and_decided_denominator(self):
        rows = make_rows(self.sample, {
            self.a1[0]: ("different_food", "different_state", "material_difference", "not_applicable"),  # one failure
            self.a1[1]: ("different_food", "unresolved", "same_or_immaterial", "not_applicable"),  # fail beats unresolved
            self.a1[2]: ("same_food", "unresolved", "same_or_immaterial", "not_applicable"),  # unresolved beats pass
        })
        m = score(self.sample, rows, make_records(rows))
        self.assertEqual((m["a1_wrong_identity_state_or_variety"]["count"], m["a1_wrong_identity_state_or_variety"]["of"]), (2, 3))
        self.assertEqual(m["a1_wrong_identity_state_or_variety_unresolved"], 1)
        self.assertIsNone(m["a1_wrong_identity_state_or_variety"]["passes"])  # not final, although within the bar
        self.assertEqual((m["a1_identity_failed"], m["a1_state_failed"], m["a1_state_unresolved"], m["a1_variety_failed"]),
                         (2, 1, 2, 1))

    def test_unresolved_is_never_a_fail(self):
        fails = {n: ("different_food", "same_state", "same_or_immaterial", "not_applicable") for n in self.a1[:3]}
        rows = make_rows(self.sample, fails)
        decided = score(self.sample, rows, make_records(rows))
        self.assertFalse(decided["a1_wrong_identity_state_or_variety"]["passes"])  # 3 > 2
        recs = make_records(rows, {(self.a1[3], "iodine"): "unresolved"})  # one unresolved value in the stratum
        m = score(self.sample, rows, recs)
        self.assertIsNone(m["a1_wrong_identity_state_or_variety"]["passes"])
        self.assertIsNone(m["a1_value_evidence_errors"]["passes"])
        self.assertEqual(m["a1_micro_value_evidence_errors_unresolved"], 1)
        self.assertEqual(m["a1_value_evidence_errors_unresolved"], 1)
        self.assertEqual(m["a1_values_unresolved"], 1)
        self.assertTrue(m["a2_different_food_or_other_state"]["passes"])  # other strata stay final

    def test_a2_a3_a4_counts(self):
        a2 = [row_of(self.sample, "A2", i) for i in range(4)]
        a3 = [row_of(self.sample, "A3", i) for i in range(4)]
        a4 = [row_of(self.sample, "A4", i) for i in range(3)]
        rows = make_rows(self.sample, {
            a2[0]: ("same_food", "same_state", "material_difference", "merge_failed"),
            a2[1]: ("same_food", "unresolved", "same_or_immaterial", "unresolved"),
            a3[0]: ("same_food", "different_state", "material_difference", "misleading_other_state"),
            a3[1]: ("different_food", "same_state", "unresolved", "misleading_close"),
            a3[2]: ("unresolved", "same_state", "same_or_immaterial", "unresolved"),
            a4[0]: ("same_food", "same_state", "same_or_immaterial", "match_missed"),
            a4[1]: ("same_food", "unresolved", "same_or_immaterial", "unresolved"),
        })
        m = score(self.sample, rows, make_records(rows))
        self.assertEqual((m["a2_different_food_or_other_state"]["count"], m["a2_different_food_or_other_state"]["of"]), (1, 3))
        self.assertEqual(m["a2_different_food_or_other_state_unresolved"], 1)
        self.assertIsNone(m["a2_different_food_or_other_state"]["passes"])
        self.assertEqual((m["a3_misleading"]["count"], m["a3_misleading"]["of"]), (2, 3))
        self.assertEqual((m["a3_misleading_other_state"], m["a3_misleading_close"], m["a3_sensible"]), (1, 1, 1))
        self.assertIsNone(m["a3_misleading"]["passes"])
        self.assertEqual((m["a4_match_missed"]["count"], m["a4_match_missed"]["of"], m["a4_nothing_suitable"],
                          m["a4_match_missed_unresolved"]), (1, 2, 1, 1))
        self.assertNotIn("passes", m["a4_match_missed"])  # informational

    def test_denominators(self):
        rows = make_rows(self.sample)
        n = self.a1[0]
        values = {(n, "energy_consumed"): "error_basis", (n, "protein"): "missing",
                  (n, "fat_total"): "missing_source_available", (n, "sugar"): "present_unquantified",
                  (n, "fiber"): "candidate_only", (n, "sodium"): "unresolved", (n, "water"): "error_state",
                  (n, "caffeine"): "missing", (n, "zinc"): "error_derivation"}
        m = score(self.sample, rows, make_records(rows, values))
        macro, micro = m["a1_macro_value_evidence_errors"], m["a1_micro_value_evidence_errors"]
        self.assertEqual((macro["count"], macro["of"]), (1, 4 * 8 - 5))  # the five non-assessed tokens never enter it
        self.assertEqual((micro["count"], micro["of"]), (1, 4 * 26))  # a declared zero assessed correct still counts
        self.assertEqual(m["a1_other_value_errors"], 1)  # other keys never enter an error denominator
        self.assertEqual((m["a1_values_missing"], m["a1_values_missing_source_available"], m["a1_values_present_unquantified"],
                          m["a1_values_candidate_only"], m["a1_values_unresolved"]), (2, 1, 1, 1, 1))
        self.assertEqual(m["a1_macro_value_evidence_errors_unresolved"], 1)
        both = m["a1_value_evidence_errors"]
        self.assertEqual((both["count"], both["of"]), (2, 4 * 8 - 5 + 4 * 26))  # one bar over macro and micro together

    def test_coverage_counts_correct_only(self):
        rows = make_rows(self.sample)
        n, k = self.a1[0], self.a1[1]
        micro = INV["groups"]["micro"]
        m = score(self.sample, rows, make_records(rows, {(n, micro[-1]): "missing", (k, micro[0]): "present_unquantified",
                                                         (k, "water"): "missing"}))
        self.assertEqual(m["a1_rows_complete_micro"], 2)  # 25 of 26 is not complete
        self.assertEqual(m["a1_micro_correct"], 4 * 26 - 2)
        self.assertEqual(m["a1_rows_complete_macro"], 4)
        self.assertEqual(m["a1_other_correct"], 4 * 5 - 1)

    def test_exposure(self):
        n = row_of(self.sample, "A5")
        rows = make_rows(self.sample, {n: ("same_food", "compatible_with_stated_assumption", "same_or_immaterial",
                                           "not_applicable")})
        recs = [r if r["row"] != str(n) else rec(n, r["nutrient"], "correct", "stated_assumption") for r in make_records(rows)]
        recs = [r if (r["row"], r["nutrient"]) != (str(self.a1[0]), "iron") else rec(self.a1[0], "iron", "correct", "unknown")
                for r in recs]
        m = score(self.sample, rows, recs)
        self.assertEqual((m["a5_values_stated_assumption"], m["a5_values_unknown_state"]), (39, 0))
        self.assertEqual((m["a1_values_stated_assumption"], m["a1_values_unknown_state"]), (0, 1))

    def test_v1_accepted_mapping(self):
        rows = make_rows(self.sample, {self.a1[0]: ("same_food", "different_state", "same_or_immaterial", "not_applicable")})
        m = score(self.sample, rows, make_records(rows), "v1_accepted")
        self.assertIs(m["a1_nutrient_disagreements_not_assessable"], True)
        self.assertIs(m["a5_nutrient_disagreements_not_assessable"], True)
        self.assertEqual(m["a1_wrong_identity_state_or_variety"]["count"], 1)  # a state failure counts under it
        self.assertEqual(m["a1_wrong_identity_state_or_variety"]["allowed"], bars.allowed("a1_wrong_product_or_variant", 4))
        self.assertTrue(m["a1_wrong_identity_state_or_variety"]["passes"])
        for name in ("a1_value_evidence_errors", "a1_macro_value_evidence_errors", "a1_micro_value_evidence_errors",
                     "a5_value_evidence_errors", "a5_macro_value_evidence_errors"):
            self.assertNotIn("passes", m[name])  # never reported as a pass
        self.assertNotIn("a1_skip_limit_exceeded", m)
        with self.assertRaises(bars_v2.BarsError):
            score(self.sample, rows, make_records(rows), "v3")

    def test_rows_must_be_the_initial_sample_never_replaced(self):
        rows = make_rows(self.sample)
        extra = {**rows[-1], "row": str(len(rows) + 1), "entry_id": self.sample["replacements"]["A2"][0], "stratum": "A2",
                 "outcome": "merge_ok"}
        with self.assertRaises(formats.FormatError):
            score(self.sample, rows + [extra], make_records(rows))
        swapped = [dict(r) for r in rows]
        swapped[0]["entry_id"], swapped[1]["entry_id"] = swapped[1]["entry_id"], swapped[0]["entry_id"]
        with self.assertRaises(formats.FormatError):
            score(self.sample, swapped, make_records(rows))


class BarsV2(unittest.TestCase):
    def test_matches_bars_judge_on_shared_names(self):
        for bar_set in bars_v2.BAR_SETS:
            shared = [n for n, (rule, _) in bars_v2.BARS[bar_set].items() if n in bars.BARS and rule != "not_assessable"]
            self.assertTrue(shared)
            for name in shared:
                for n in range(0, 70):
                    for count in range(0, n + 1):
                        self.assertEqual(bars_v2.judge(bar_set, name, count, n), bars.judge(name, count, n), (name, count, n))

    def test_same_rounding_for_the_new_share_bars(self):
        for n in (0, 33, 34, 104, 464):
            self.assertEqual(bars_v2.allowed("v2_proposed", "a1_value_evidence_errors", n),
                             bars.allowed("a1_nutrient_disagreements", n))
            self.assertEqual(bars_v2.allowed("v2_proposed", "a5_value_evidence_errors", n),
                             bars.allowed("a5_nutrient_disagreements", n))
        self.assertEqual(bars_v2.allowed("v2_proposed", "a2_different_food_or_other_state", 45), 2)

    def test_not_assessable_and_unresolved(self):
        self.assertEqual(bars_v2.not_assessable("v1_accepted"), ["a1_nutrient_disagreements", "a5_nutrient_disagreements"])
        self.assertEqual(bars_v2.not_assessable("v2_proposed"), [])
        with self.assertRaises(bars_v2.BarsError):
            bars_v2.judge("v1_accepted", "a1_nutrient_disagreements", 0, 10)
        self.assertEqual(bars_v2.judge("v2_proposed", "a3_misleading", 9, 40, unresolved=True), {"allowed": 4, "passes": None})
        self.assertEqual(bars_v2.judge("v2_proposed", "a3_misleading", 0, 0), {"allowed": None, "passes": None})


class ResultsV2(unittest.TestCase):
    def setUp(self):
        self.sample = make_sample()
        self.rows = make_rows(self.sample)

    def test_accepts_scorer_output_under_both_sets_and_round_trips(self):
        for bar_set in ("v1_accepted", "v2_proposed"):
            m = score(self.sample, self.rows, make_records(self.rows), bar_set)
            data = results_v2.build(H.RELEASE, bar_set, m)
            self.assertEqual(results_v2.parse(data)["part_a_bars"], bar_set)
            self.assertNotIn(H.eid(1).encode(), data)
            self.assertIn(b"pfd-results-v2", data)

    def test_refuses_unknown_keys_strings_and_bars(self):
        m = score(self.sample, self.rows, make_records(self.rows))
        good = m["a3_misleading"]
        for bad in ({"title": 1}, {"a1_entries": SECRET}, {"a3_misleading": {**good, "note": SECRET}},
                    {"a1_nutrient_disagreements_not_assessable": 1}, {"a3_misleading_unresolved": -1},
                    {"a3_misleading": {**good, "passes": "yes"}}, {"a1_skip_limit_exceeded": False}):
            with self.assertRaises(results_v2.ResultsError):
                results_v2.build(H.RELEASE, "v2_proposed", bad)
        for bars_token in (None, "", "v3_proposed", SECRET):
            with self.assertRaises(results_v2.ResultsError):
                results_v2.build(H.RELEASE, bars_token, m)
        with self.assertRaises(results_v2.ResultsError):
            results_v2.build("pfc:not-a-release", "v2_proposed", m)
        results_v2.build(H.RELEASE, "v1_accepted", {"a1_nutrient_disagreements_not_assessable": True,
                                                    "a5_nutrient_disagreements_not_assessable": True})

    def test_existing_v1_results_still_parse_and_are_not_v2(self):
        v1 = results.build("A", H.RELEASE, {"a3_misleading": {"count": 1, "of": 40, "interval": [0.004, 0.128],
                                                              "allowed": 4, "passes": True}})
        self.assertEqual(json.loads(v1)["schema"], "pfd-results-v1")
        self.assertEqual(formats.dumps(json.loads(v1)), v1)
        with self.assertRaises(results_v2.ResultsError):
            results_v2.parse(v1)


class Exclusions(unittest.TestCase):
    def test_per_entry_and_per_value_exclusions_in_every_stratum(self):
        sample = make_sample(a1=40, a5=2, a2=4, a3=4, a4=2)
        a1, a5 = row_of(sample, "A1", 0), row_of(sample, "A5", 0)
        a2, a2u = row_of(sample, "A2", 0), row_of(sample, "A2", 1)
        a3, a3d, a3u = row_of(sample, "A3", 0), row_of(sample, "A3", 1), row_of(sample, "A3", 2)
        a4 = row_of(sample, "A4", 0)
        rows = make_rows(sample, {
            a1: ("same_food", "same_state", "material_difference", "not_applicable"),
            a5: ("different_food", "same_state", "same_or_immaterial", "not_applicable"),
            a2: ("same_food", "different_state", "same_or_immaterial", "merge_failed"),
            a2u: ("unresolved", "same_state", "same_or_immaterial", "unresolved"),
            a3: ("same_food", "different_state", "same_or_immaterial", "misleading_other_state"),
            a3d: ("different_food", "unresolved", "same_or_immaterial", "unresolved"),
            a3u: ("unresolved", "same_state", "same_or_immaterial", "unresolved"),
            a4: ("same_food", "same_state", "same_or_immaterial", "match_missed"),
        })
        clean_a1 = row_of(sample, "A1", 5)
        recs = make_records(rows, {(clean_a1, "protein"): "error_transcription", (row_of(sample, "A2", 2), "iron"): "error_source",
                                   (row_of(sample, "A5", 1), "water"): "error_state"})
        m = score(sample, rows, recs)
        self.assertTrue(m["a1_value_evidence_errors"]["passes"])  # one error is within the bar ...
        data = score_a_v2.exclusion_list(sample, sheet(rows), evidence(recs), INV)
        ids = [e["entry_id"] for e in sample["entries"]]
        self.assertEqual(data["withhold_entries"], [ids[n - 1] for n in sorted((a1, a5, a2, a3, a3d))])
        self.assertEqual(data["reference_candidates"], [ids[n - 1] for n in sorted((a2u, a3u))])
        self.assertIn({"entry_id": ids[clean_a1 - 1], "nutrient": "protein", "assessment": "error_transcription"},
                      data["withhold_values"])  # ... and the value is still withheld
        self.assertEqual(len(data["withhold_values"]), 3)
        self.assertNotIn(ids[a4 - 1], data["withhold_entries"] + data["reference_candidates"])

    def test_versioned_and_round_trips(self):
        data = {"withhold_entries": [H.eid(1)], "reference_candidates": [H.eid(2)],
                "withhold_values": [{"entry_id": H.eid(3), "nutrient": "iron", "assessment": "error_basis"}]}
        raw = exclusions.build(H.RELEASE, data)
        self.assertEqual(exclusions.build(H.RELEASE, {k: v for k, v in exclusions.parse(raw).items()
                                                     if k not in ("schema", "release_id")}), raw)
        self.assertEqual(formats.dumps(exclusions.parse(raw)), raw)
        doc = json.loads(raw)
        for bad in ({**doc, "schema": "pfd-exclusions-v2"}, {**doc, "note": SECRET},
                    {**doc, "withhold_entries": [SECRET]}, {**doc, "reference_candidates": [H.eid(1)]},
                    {**doc, "withhold_values": [{**data["withhold_values"][0], "value": "1"}]},
                    {**doc, "withhold_values": [{**data["withhold_values"][0], "assessment": "missing"}]}):
            with self.assertRaises(formats.FormatError) as e:
                exclusions.parse(formats.dumps(bad))
            self.assertNotIn(SECRET, str(e.exception))


if __name__ == "__main__":
    unittest.main()
