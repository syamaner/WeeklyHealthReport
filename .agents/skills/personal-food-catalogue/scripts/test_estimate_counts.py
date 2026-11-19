#!/usr/bin/env python3
"""Synthetic tests for estimate_counts.py: the three private list formats, the re-admission rules
and the evaluator's six counts. Every title, brand, record ID and value here is synthetic.

Usage: python3 -I test_estimate_counts.py <scripts_dir>
"""
import sys
import unittest

sys.path.insert(0, sys.argv[1])
import estimate_counts as C  # noqa: E402
import estimates_input as I  # noqa: E402
import test_estimates_input as T  # noqa: E402  (the shared synthetic builders; its tests do not run here)

READMITTED_TEXT = C.SENTENCE + " Synthetic assumption."
FISH, PULSE = T.FISH, T.PULSE
# A record that is not the entry's own, so a `raw` or `cooked` entry may take it once re-admitted.
OTHER = dict(source="usda", ref=T.USDA)


def refusals(*rows, former=None, none=None):
    doc = {"schema": C.SCHEMA_REFUSALS, "rows": list(rows) if len(rows) < 2 else sorted(rows, key=lambda r: (
        r["entry_id"], r["source_type"], r["source_reference"], r.get("nutrient", ""), r["refusal_class"]))}
    if former is not None:
        doc["former_close_references"] = former
    if none is not None:
        doc["no_e3_counterpart"] = sorted(none)
    return C.parse_refusals(I.canonical(doc))


def refusal(entry, evidence, nutrient=None, refusal_class="stratum_consequence"):
    row = {"entry_id": entry["id"], "source_type": evidence["source_type"],
           "source_reference": evidence["source_reference"], "refusal_class": refusal_class}
    return {**row, "nutrient": nutrient} if nutrient else row


def listed(entry, nutrient, evidence, corpus=None, date="2026-11-16"):
    return {"entry_id": entry["id"], "nutrient": nutrient, "source_type": evidence["source_type"],
            "source_reference": evidence["source_reference"], "method": evidence["method"],
            "corpus_sha256": corpus or T.CORPORA.get(evidence["composition_source"], "d" * 64), "date": date}


def on_sheet(row, refusal_class="stratum_consequence", accept="accepted", **changes):
    return {**row, "refusal_class": refusal_class, "reason": "Synthetic reason.", "accept": accept, **changes}


def readmissions(*rows):
    return C.parse_readmissions(I.canonical({"schema": C.SCHEMA_READMISSIONS, "rows": list(rows)}))


def sheet(*rows):
    return C.parse_sheet(I.canonical({"schema": C.SCHEMA_SHEET, "rows": list(rows)}))


def document(doc, *rows):
    """(estimates v2 document, accepted rows) for rows written as they stand, with no admission, so
    a test can hold a file the builder would never write."""
    accepted = T.accepted(doc, *rows)
    estimates, _ = I.expand(doc, accepted, T.read)
    return I.assemble(doc, estimates), accepted["rows"]


class Formats(unittest.TestCase):
    def test_the_three_lists_parse_from_canonical_bytes_only(self):
        ev = T.national()
        one = listed(FISH, "protein", ev)
        self.assertEqual(len(refusals(refusal(FISH, ev), refusal(FISH, ev, "protein"))["rows"]), 2)
        self.assertEqual(len(readmissions(one)["rows"]), 1)
        self.assertEqual(len(sheet(on_sheet(one))["rows"]), 1)
        loose = b'{"schema": "pfc-estimate-readmissions-v1", "rows": []}'
        for parse in (C.parse_refusals, C.parse_readmissions, C.parse_sheet):
            for data in (loose, b"[]\n", b"{", None, b"\xef\xbb\xbf{}"):
                with self.assertRaises(I.EstimatesRefused):
                    parse(data)

    def test_exact_keys_closed_vocabularies_and_odd_types(self):
        ev = T.national()
        one = listed(FISH, "protein", ev)
        for bad in ({**one, "note": "x"}, {**one, "nutrient": "sparkle"}, {**one, "method": "guessed"},
                    {**one, "corpus_sha256": "abc"}, {**one, "date": "16 November"}, {**one, "source_type": "recipe"},
                    {**one, "entry_id": []}, {**one, "source_reference": ""}, None, [], 3):
            with self.assertRaises(I.EstimatesRefused):
                readmissions(bad)
        for bad in (on_sheet(one, accept="yes"), on_sheet(one, refusal_class="other"), on_sheet(one, reason=""),
                    on_sheet(one, accept=None), {k: v for k, v in on_sheet(one).items() if k != "reason"}):
            with self.assertRaises(I.EstimatesRefused):
                sheet(bad)
        with self.assertRaises(I.EstimatesRefused):
            sheet(on_sheet(one), on_sheet(one, accept="withdrawn"))  # one row per value
        for bad in ({**refusal(FISH, ev), "refusal_class": "other"}, {**refusal(FISH, ev), "nutrient": None},
                    {**refusal(FISH, ev), "why": "x"}, {"entry_id": FISH["id"]}, None, "x"):
            with self.assertRaises(I.EstimatesRefused):
                refusals(bad)
        for extra in ({"former_close_references": [{"entry_id": FISH["id"], "composition_source": "other",
                                                    "record_id": T.COFID}]},
                      {"former_close_references": {}}, {"no_e3_counterpart": ["not-an-id"]},
                      {"no_e3_counterpart": [FISH["id"], FISH["id"]]}, {"no_e3_counterpart": [[]]}):
            with self.assertRaises(I.EstimatesRefused):
                C.parse_refusals(I.canonical({"schema": C.SCHEMA_REFUSALS, "rows": [], **extra}))
        with self.assertRaises(I.EstimatesRefused) as cm:
            C.parse_refusals(I.canonical({"schema": C.SCHEMA_REFUSALS, "rows": [], "titles": ["Synthetic Tinned Fish"]}))
        self.assertNotIn("Synthetic", str(cm.exception))


class Status(unittest.TestCase):
    ev = T.national(assumption=READMITTED_TEXT, **OTHER)
    corpus = T.CORPORA["usda"]

    def status(self, lists, evidence=None, corpus=None, nutrient="protein"):
        return lists.status(FISH["id"], nutrient, evidence or self.ev, corpus or self.corpus)

    def test_clear_refused_and_readmitted(self):
        one = listed(FISH, "protein", self.ev)
        refused = refusals(refusal(FISH, self.ev))
        self.assertEqual(self.status(C.Lists()), I.CLEAR)
        self.assertEqual(self.status(C.Lists(refusals(refusal(PULSE, self.ev)))), I.CLEAR)
        self.assertEqual(self.status(C.Lists(refusals(refusal(FISH, self.ev, "iron")))), I.CLEAR)
        self.assertEqual(self.status(C.Lists(refused)), I.REFUSED)
        self.assertEqual(self.status(C.Lists(refused, readmissions(one), sheet(on_sheet(one)))), I.READMITTED)
        self.assertEqual(self.status(C.Lists(refusals(refusal(FISH, self.ev, "protein")), readmissions(one),
                                             sheet(on_sheet(one)))), I.READMITTED)

    def test_a_refused_page_is_refused_under_another_spelling_of_its_host(self):
        # Invariant review, 17 November 2026: a refused page must not be written again because its
        # host is spelt in another case or with a trailing dot. A bundled record ID is compared as written.
        key = C.reference_key
        page = "https://www.example.com/products/synthetic"
        self.assertEqual(key("aggregator", page), key("aggregator", "https://WWW.Example.com/products/synthetic"))
        self.assertEqual(key("aggregator", page), key("aggregator", "https://www.example.com./products/synthetic"))
        self.assertNotEqual(key("aggregator", page), key("aggregator", "https://www.example.com/products/other"))
        self.assertNotEqual(key("aggregator", page), key("aggregator", "https://www.example.com:8443/products/synthetic"))
        self.assertNotEqual(key("aggregator", page), key("aggregator", "https://www.example.com/Products/synthetic"))
        self.assertEqual(key("national_composition", "cofid:Example"), "cofid:Example")
        self.assertEqual(key("aggregator", "not a url"), "not a url")

    def test_a_list_row_without_an_accepted_sheet_row_is_refused(self):
        one = listed(FISH, "protein", self.ev)
        refused = refusals(refusal(FISH, self.ev))
        for pages in (None, sheet(), sheet(on_sheet(one, accept="not_accepted")),
                      sheet(on_sheet(one, date="2026-11-15")), sheet(on_sheet(one, corpus_sha256="e" * 64)),
                      sheet(on_sheet(listed(FISH, "iron", self.ev)))):
            lists = C.Lists(refused, readmissions(one), pages)
            self.assertEqual(self.status(lists), I.REFUSED)
            self.assertEqual(lists.list_checks()["list_rows_without_accepted_sheet_row"], 1)

    def test_a_withdrawn_row_is_refused(self):
        one = listed(FISH, "protein", self.ev)
        lists = C.Lists(refusals(refusal(FISH, self.ev)), readmissions(one), sheet(on_sheet(one, accept="withdrawn")))
        self.assertEqual(self.status(lists), I.REFUSED)
        self.assertEqual(lists.list_checks()["list_rows_withdrawn"], 1)

    def test_a_row_covers_that_value_only(self):
        one = listed(FISH, "protein", self.ev)
        lists = C.Lists(refusals(refusal(FISH, self.ev)), readmissions(one), sheet(on_sheet(one)))
        self.assertEqual(self.status(lists, corpus="f" * 64), I.REFUSED)  # a later value of the same record
        self.assertEqual(self.status(lists, nutrient="iron"), I.REFUSED)
        other_method = {**self.ev, "method": "carried_from_similar_food"}
        self.assertEqual(self.status(lists, evidence=other_method), I.REFUSED)

    def test_a_never_re_admissible_class_is_refused_even_when_listed_and_accepted(self):
        one = listed(FISH, "protein", self.ev)
        for never in C.NEVER:
            lists = C.Lists(refusals(refusal(FISH, self.ev, refusal_class=never)), readmissions(one),
                            sheet(on_sheet(one, refusal_class=never)))
            self.assertEqual(self.status(lists), I.CLASS, never)
        # The sheet cannot relabel the class, and a second refusal of a never class still holds.
        lists = C.Lists(refusals(refusal(FISH, self.ev, refusal_class="value_fault")), readmissions(one),
                        sheet(on_sheet(one)))
        self.assertEqual(self.status(lists), I.CLASS)
        lists = C.Lists(refusals(refusal(FISH, self.ev), refusal(FISH, self.ev, "protein", "per_entry_exclusion")),
                        readmissions(one), sheet(on_sheet(one)))
        self.assertEqual(self.status(lists), I.CLASS)
        web = T.page()
        row = listed(FISH, "protein", web)
        lists = C.Lists(refusals(refusal(FISH, web)), readmissions(row), sheet(on_sheet(row)))
        self.assertEqual(lists.status(FISH["id"], "protein", web, "d" * 64), I.CLASS)  # only composition re-admits
        self.assertEqual(lists.status(FISH["id"], "protein", web, None), I.REFUSED)


class SixCounts(unittest.TestCase):
    def counts(self, doc, rows, lists=None):
        out, accepted_rows = document(doc, *rows)
        return C.six_counts(out, accepted_rows, lists or C.Lists())

    def zero(self, result, **nonzero):
        self.assertEqual(result["counts"], {**{k: 0 for k in C.MUST_BE_ZERO + C.REPORTED}, **nonzero})
        self.assertEqual(C.failures(result) == [], not (set(nonzero) & set(C.MUST_BE_ZERO)) and not result["checks"])

    def test_six_names_and_a_clean_catalogue(self):
        # estimates v2, plus two must-be-zero (G1) and one reported (G3) from the gap estimates amendments, and one
        # must-be-zero from the composite web amendment G5
        self.assertEqual(len(C.MUST_BE_ZERO), 7)
        self.assertEqual(len(C.REPORTED), 3)
        doc = T.plain(FISH, PULSE)
        self.zero(C.six_counts(doc, [], C.Lists()))  # a plain v2 document has no estimate
        result = self.counts(doc, [T.row(FISH, T.national(quality="high")), T.row(PULSE, T.page(), "fiber", 7.5)])
        self.zero(result)
        self.assertEqual(C.failures(result), [])

    def test_a_close_reference_passed_off_as_the_same_food(self):
        close = T.item("Synthetic Tinned Fish", generic_reference=T.reference(match="close"))
        doc = T.plain(close)
        self.zero(self.counts(doc, [T.row(close, T.national(), "protein")]), close_reference_as_same_food=1)
        self.zero(self.counts(doc, [T.row(close, T.national(method="carried_from_similar_food"), "protein")]))
        # A former close reference, dropped or changed to pass the record off as the same food.
        former = C.Lists(refusals(former=[{"entry_id": PULSE["id"], "composition_source": "usda", "record_id": T.USDA}]))
        rows = [T.row(PULSE, T.national(**OTHER), "protein")]
        result = self.counts(T.plain(PULSE), rows, former)
        self.zero(result, close_reference_as_same_food=1)
        self.assertEqual(C.failures(result), ["close_reference_as_same_food: 1"])
        self.zero(self.counts(T.plain(PULSE), rows))
        self.zero(self.counts(T.plain(PULSE), [T.row(PULSE, T.national(method="carried_from_similar_food", **OTHER),
                                                     "protein")], former))

    def test_refused_estimates_not_re_admitted_and_the_re_admitted_number(self):
        ev = T.national(assumption=READMITTED_TEXT, **OTHER)
        doc, rows = T.plain(PULSE), [T.row(PULSE, ev, "protein"), T.row(PULSE, ev, "iron")]
        one = listed(PULSE, "protein", ev)
        refused = refusals(refusal(PULSE, ev))
        self.zero(self.counts(doc, rows, C.Lists(refused)), refused_not_readmitted=2)
        result = self.counts(doc, rows, C.Lists(refused, readmissions(one), sheet(on_sheet(one))))
        self.zero(result, refused_not_readmitted=1, readmitted=1)
        self.assertEqual(result["readmitted_rows"], [{"entry_id": PULSE["id"], "nutrient": "protein",
                                                      "source_reference": T.USDA}])
        both = [one, listed(PULSE, "iron", ev)]
        both.sort(key=lambda r: r["nutrient"])
        clean = self.counts(doc, rows, C.Lists(refused, readmissions(*both), sheet(*map(on_sheet, both))))
        self.zero(clean, readmitted=2)
        self.assertEqual(C.failures(clean), [])
        withdrawn = sheet(*(on_sheet(r, accept="withdrawn" if r["nutrient"] == "iron" else "accepted") for r in both))
        self.zero(self.counts(doc, rows, C.Lists(refused, readmissions(*both), withdrawn)),
                  refused_not_readmitted=1, readmitted=1)
        never = C.Lists(refusals(refusal(PULSE, ev, refusal_class="unresolved_a1")), readmissions(*both),
                        sheet(*(on_sheet(r, refusal_class="unresolved_a1") for r in both)))
        self.zero(self.counts(doc, rows, never), refused_not_readmitted=2)
        self.zero(self.counts(doc, rows, C.Lists(refused, readmissions(*both))), refused_not_readmitted=2)

    def test_a_re_admitted_estimate_above_medium(self):
        # The entry's own same-food record may be `high` for the codec; re-admitted, it may not.
        ev = T.national(assumption=READMITTED_TEXT, quality="high")
        one = listed(FISH, "protein", ev)
        lists = C.Lists(refusals(refusal(FISH, ev)), readmissions(one), sheet(on_sheet(one)))
        doc = T.plain(FISH)
        result = self.counts(doc, [T.row(FISH, ev, "protein")], lists)
        self.zero(result, readmitted=1, readmitted_above_medium=1)
        self.assertEqual(C.failures(result), ["readmitted_above_medium: 1"])
        medium = {**ev, "quality": "medium"}
        self.zero(self.counts(doc, [T.row(FISH, medium, "protein")], lists), readmitted=1)

    def test_an_aggregator_above_medium_with_no_stated_underlying_source(self):
        doc = T.plain(PULSE)
        high = T.page("aggregator", quality="high")
        result = self.counts(doc, [T.row(PULSE, high, "fiber", 7.5, underlying="not_stated")])
        self.zero(result, aggregator_not_stated_above_medium=1)
        self.assertEqual(C.failures(result), ["aggregator_not_stated_above_medium: 1"])
        self.zero(self.counts(doc, [T.row(PULSE, high, "fiber", 7.5)]))  # stated_independent
        self.zero(self.counts(doc, [T.row(PULSE, T.page("aggregator"), "fiber", 7.5, underlying="not_stated")]))
        out, _ = document(doc, T.row(PULSE, high, "fiber", 7.5))
        self.zero(C.six_counts(out, [], C.Lists()), aggregator_not_stated_above_medium=1)  # no row states it

    def test_entries_with_no_e3_counterpart_are_reported(self):
        doc = T.plain(FISH, PULSE)
        rows = [T.row(FISH, T.national()), T.row(PULSE, T.page(), "fiber", 7.5)]
        result = self.counts(doc, rows, C.Lists(refusals(none=[FISH["id"]])))
        self.zero(result, no_e3_counterpart=4)
        self.assertEqual(C.failures(result), [])

    def test_the_fixed_sentence_and_the_former_close_method(self):
        ev = T.national(**OTHER)  # its assumption does not say the source was re-admitted
        one = listed(PULSE, "protein", ev)
        lists = C.Lists(refusals(refusal(PULSE, ev)), readmissions(one), sheet(on_sheet(one)))
        result = self.counts(T.plain(PULSE), [T.row(PULSE, ev, "protein")], lists)
        self.assertEqual(result["checks"], ["readmission-sentence: 1"])
        self.assertEqual(C.failures(result), ["readmission-sentence: 1"])
        # A former close reference re-admits only as carried_from_similar_food.
        former = [{"entry_id": PULSE["id"], "composition_source": "usda", "record_id": T.USDA}]
        result = self.counts(T.plain(PULSE), [], C.Lists(refusals(refusal(PULSE, ev), former=former),
                                                         readmissions(one), sheet(on_sheet(one))))
        self.assertEqual(result["checks"], ["readmission-former-close-method: 1"])
        similar = listed(PULSE, "protein", {**ev, "method": "carried_from_similar_food"})
        result = self.counts(T.plain(PULSE), [], C.Lists(refusals(refusal(PULSE, ev), former=former),
                                                         readmissions(similar), sheet(on_sheet(similar))))
        self.assertEqual(result["checks"], [])


class ReadmissionOverridesNoMechanicalRule(unittest.TestCase):
    def test_a_re_admitted_own_record_on_a_raw_entry_is_still_estimate_own_held(self):
        held = T.item("Synthetic Tinned Fish", state="raw", generic_reference=T.reference())
        ev = T.national(assumption=READMITTED_TEXT)
        one = listed(held, "protein", ev)
        lists = C.Lists(refusals(refusal(held, ev)), readmissions(one), sheet(on_sheet(one)))
        self.assertEqual(lists.status(held["id"], "protein", ev, T.CORPORA["cofid"]), I.READMITTED)
        admitted, counts = T.run(T.plain(held), T.row(held, ev, "protein"), status=lists.status)
        self.assertEqual(admitted, [])
        self.assertEqual((counts["withheld_codec"], counts["codec_estimate-own-held"]), (1, 1))
        # Without the re-admission the refusal list answers first.
        admitted, counts = T.run(T.plain(held), T.row(held, ev, "protein"),
                                 status=C.Lists(refusals(refusal(held, ev))).status)
        self.assertEqual((admitted, counts["withheld_refused_source"]), ([], 1))
        # A record that is not the entry's own passes on a raw entry, once re-admitted.
        other = T.national(assumption=READMITTED_TEXT, **OTHER)
        row = listed(held, "iron", other)
        lists = C.Lists(refusals(refusal(held, other)), readmissions(row), sheet(on_sheet(row)))
        admitted, counts = T.run(T.plain(held), T.row(held, other, "iron"), status=lists.status)
        self.assertEqual((len(admitted), counts["admitted_readmitted"]), (1, 1))


if __name__ == "__main__":
    unittest.main(argv=sys.argv[:1])
