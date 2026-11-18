#!/usr/bin/env python3
"""Synthetic tests for estimates_input.py and apply_estimates.py. Every title, brand and typed value
here is synthetic. The end-to-end run uses a temporary workspace and two record IDs read from the
public bundled corpus files, so the hash pins hold; it never touches a real workspace.

Usage: python3 -I test_estimates_input.py <scripts_dir>
"""
import contextlib
import io
import json
import os
import shutil
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import estimates_input as I  # noqa: E402
import export_v1  # noqa: E402

BRAND = "Example Brand"
CORPORA = {"cofid": "a" * 64, "usda": "b" * 64, "tfda": "c" * 64}
COFID, COFID_OTHER, USDA = "cofid:synthetic:row:0001", "cofid:synthetic:row:0002", "usda-synthetic:fdc:1"
RECORDS = {
    ("cofid", COFID): {"nutrients": {"protein": 20.0, "fat_total": 5.5, "fiber": 0, "sodium": 310.0},
                       "preparation": "unknown", "fortification": "unknown", "per_100_g": True},
    ("cofid", COFID_OTHER): {"nutrients": {"protein": 3.0}, "preparation": "cooked", "fortification": "fortified",
                             "per_100_g": False},
    ("usda", USDA): {"nutrients": {"protein": 9.0, "iron": 1.5}, "preparation": "raw", "fortification": None,
                     "per_100_g": True},
}
FORTIFIED, COOKED = "cofid:synthetic:row:0003", "cofid:synthetic:row:0004"
RECORDS[("cofid", FORTIFIED)] = {"nutrients": {"protein": 8.0}, "preparation": "unknown", "fortification": "fortified",
                                 "per_100_g": True}
RECORDS[("cofid", COOKED)] = {"nutrients": {"protein": 4.0}, "preparation": "cooked", "fortification": "unfortified",
                              "per_100_g": True}
SALT = {"transform_id": "salt_to_sodium_v1", "version": "pasted-label-conversions-v1",
        "source_value": {"value": 1.0, "unit": "g"}}


def read(source, record_id):
    return RECORDS.get((source, record_id))


def reference(source=None, record_id=None, match="same_food_same_state", role="candidate", corpora=CORPORA):
    source = source or "cofid"
    return {"source": source, "corpus_sha256": corpora[source], "record_id": record_id or COFID, "match": match,
            "role": role}


def item(title, **changes):
    base = {"id": export_v1.entry_id(BRAND, title), "brand": BRAND, "title": title, "titles": [title], "aliases": [],
            "concept": None, "variety": None, "fallback_chain": [], "category": "other",
            "product_type": "packaged_single_ingredient", "state": "canned", "basis": "per_100_g",
            "label_nutrients": {}, "generic_reference": None}
    return {**base, **changes}


def labelled(title, key, value, **changes):
    """An entry with one owner-typed label value, and the source release the file must declare."""
    release = export_v1.owner_release(title, {key: value}, "2026-11-17")
    label = export_v1.value_out({"value": value, "unit": export_v1.CANON_UNITS[key]}, "manual_declaration",
                                release["source_release_id"], None, "owner")
    return item(title, label_nutrients={key: label}, **changes), release


def plain(*items, sources=(), corpora=CORPORA):
    return {"schema": export_v1.SCHEMA_V2, "generated": "2026-11-17",
            "sources": sorted(sources, key=lambda s: s["source_release_id"]),
            "generic_corpora": [{"source": k, "corpus_sha256": h} for k, h in sorted(corpora.items())],
            "items": sorted(items, key=lambda it: it["id"])}


def national(method="carried_from_same_food", source="cofid", ref=COFID, quality="medium", **changes):
    return {"approved_as_estimate": True, "source_type": "national_composition", "composition_source": source,
            "source_reference": ref, "page_access": None, "source_digest": None, "retrieved_on": None,
            "source_state": "as sold", "target_state": "as sold", "state_basis": "source_states_it",
            "method": method, "assumption": "Synthetic assumption.", "derivation": None, "quality": quality,
            **changes}


def page(source_type="manufacturer_page", url="https://example.invalid/synthetic-food", method="direct",
         quality="medium", **changes):
    return {"approved_as_estimate": True, "source_type": source_type, "composition_source": None,
            "source_reference": url, "page_access": "direct_read", "source_digest": None,
            "retrieved_on": "2026-11-16", "source_state": "as sold", "target_state": "as sold",
            "state_basis": "source_states_it", "method": method, "assumption": "Synthetic assumption.",
            "derivation": None, "quality": quality, **changes}


def row(entry, evidence, nutrient=None, value=None, underlying=None, **changes):
    out = {"entry_id": entry["id"], "scope": "nutrient" if nutrient else "entry", "evidence": evidence,
           "underlying_source": underlying or ("stated_independent" if evidence["source_type"] == "aggregator"
                                               else "not_applicable"),
           "relation": "similar_food" if evidence["method"] == "carried_from_similar_food" else "same_food",
           "accepted": {"sheet": "Synthetic sheet A", "row": 2}}
    if nutrient:
        out["nutrient"] = nutrient
    if value is not None:
        out.update(value=value, unit=export_v1.CANON_UNITS[nutrient])
    return {**out, **changes}


def accepted(doc, *rows):
    rows = sorted(rows, key=lambda r: (r["entry_id"], r.get("nutrient", "")))
    return I.parse(I.build(I.release_id(I.dumps(doc)), rows))


def run(doc, *rows, status=None):
    """(admitted estimates, counts) for rows over a document, through expansion and admission."""
    estimates, counts = I.expand(doc, accepted(doc, *rows), read)
    admitted, admission = I.admit(doc, estimates, read, status)
    return admitted, {**counts, **admission}


FISH = item("Synthetic Tinned Fish", generic_reference=reference())
PULSE = item("Synthetic Dried Pulse", state="dried")


class Format(unittest.TestCase):
    def good(self):
        return [row(FISH, national(quality="high")), row(PULSE, page(), "fiber", 7.5)]

    def refused(self, rows, release="pfc:sha256:" + "0" * 64):
        with self.assertRaises(I.EstimatesRefused) as cm:
            I.build(release, rows)
        self.assertNotIn("Synthetic", str(cm.exception))
        self.assertNotIn("7.5", str(cm.exception))
        return str(cm.exception)

    def test_a_valid_document_parses_only_from_its_canonical_bytes(self):
        doc = plain(FISH, PULSE)
        data = I.build(I.release_id(I.dumps(doc)), sorted(self.good(), key=lambda r: r["entry_id"]))
        self.assertEqual(I.parse(data)["schema"], "pfc-accepted-estimates-v1")
        for other in (json.dumps(json.loads(data), indent=1).encode(), b"\xef\xbb\xbf" + data, data + b"\n",
                      data.replace(b'"rows"', b'"rows":[],"rows"', 1), b"{", b"\xff", "text"):
            with self.assertRaises(I.EstimatesRefused):
                I.parse(other)

    def test_a_national_row_never_carries_a_typed_value(self):
        typed = row(FISH, national(), "protein", 21.0)
        self.assertIn("never carries a typed value", self.refused([typed]))
        self.assertIn("never carries a typed value", self.refused([{**row(FISH, national()), "value": 21.0}]))
        self.refused([row(FISH, national(method="derived", derivation=SALT), "sodium")])

    def test_exact_keys_and_closed_vocabularies(self):
        fish, pulse = self.good()
        for bad in ({**fish, "note": "x"}, {k: v for k, v in fish.items() if k != "accepted"},
                    {**fish, "scope": "everything"}, {**fish, "relation": "similar_food"},
                    {**fish, "underlying_source": "not_stated"}, {**fish, "entry_id": "pfc:XYZ"},
                    {**fish, "accepted": {"sheet": "Synthetic sheet A", "row": 0}},
                    {**fish, "accepted": {"sheet": "", "row": 1}}, {**fish, "accepted": {"sheet": "A", "row": True}},
                    {**fish, "evidence": {**fish["evidence"], "quality": "certain"}},
                    {**fish, "evidence": {k: v for k, v in fish["evidence"].items() if k != "quality"}},
                    {**pulse, "scope": "entry"}, {**pulse, "unit": "mg"}, {**pulse, "value": -1},
                    {**pulse, "nutrient": "sparkle"}, {k: v for k, v in pulse.items() if k != "value"},
                    {**pulse, "underlying_source": "stated_independent"},
                    row(PULSE, page("aggregator"), "fiber", 7.5, underlying="not_applicable"),
                    row(PULSE, page(url="http://example.invalid/x"), "fiber", 7.5)):
            self.refused([bad])
        self.refused([fish, fish])  # each pair once
        self.refused(sorted([fish, pulse], key=lambda r: r["entry_id"], reverse=True))  # ascending order
        self.refused([fish], release="pfc:sha256:XYZ")

    def test_values_of_an_odd_type_are_refusals_never_crashes(self):
        fish = self.good()[0]
        for doc in (None, [], 3, "x", {"schema": []}, {"schema": I.SCHEMA, "catalogue_release_id": [], "rows": []},
                    {"schema": I.SCHEMA, "catalogue_release_id": "pfc:sha256:" + "0" * 64, "rows": {}}):
            with self.assertRaises(I.EstimatesRefused):
                I.validate(doc)
        for odd in (None, 3, [], {}, "x", [[]], {"a": []}):
            for field in ("entry_id", "scope", "evidence", "underlying_source", "relation", "accepted"):
                self.refused([{**fish, field: odd}])
            for field in ("source_type", "method", "quality", "source_reference", "composition_source", "assumption"):
                if odd != "x" or field not in ("source_reference", "assumption"):  # plain text is valid there
                    self.refused([{**fish, "evidence": {**fish["evidence"], field: odd}}])
            self.refused([odd])


class Expansion(unittest.TestCase):
    def test_a_whole_entry_row_gives_one_estimate_for_each_quantified_key(self):
        estimates, counts = I.expand(plain(FISH), accepted(plain(FISH), row(FISH, national())), read)
        self.assertEqual({e["nutrient"]: e["value"] for e in estimates},
                         {"protein": 20.0, "fat_total": 5.5, "fiber": 0, "sodium": 310.0})
        self.assertEqual([e["nutrient"] for e in estimates], sorted(e["nutrient"] for e in estimates))
        self.assertEqual((counts["rows_entry_scope"], counts["estimates"]), (1, 4))

    def test_never_for_a_key_the_entry_has_or_a_nutrient_row_names(self):
        fish, release = labelled("Synthetic Tinned Fish", "protein", 19.0, generic_reference=reference())
        doc = plain(fish, sources=[release])
        rows = [row(fish, national()), row(fish, page(), "fiber", 1.2)]
        estimates, counts = I.expand(doc, accepted(doc, *rows), read)
        self.assertEqual({e["nutrient"]: e["value"] for e in estimates}, {"fat_total": 5.5, "fiber": 1.2, "sodium": 310.0})
        self.assertEqual((counts["expansion_skipped_label"], counts["expansion_skipped_nutrient_row"]), (1, 1))

    def test_a_record_that_cannot_be_read_gives_nothing_and_a_missing_entry_refuses(self):
        doc = plain(FISH)
        estimates, counts = I.expand(doc, accepted(doc, row(FISH, national(ref="cofid:synthetic:row:9999"))), read)
        self.assertEqual((estimates, counts["entry_rows_record_unreadable"]), ([], 1))
        with self.assertRaises(I.EstimatesRefused):
            I.expand(doc, accepted(doc, row(PULSE, page(), "fiber", 7.5)), read)

    def test_the_value_comes_from_the_record_reader(self):
        estimates, _ = I.expand(plain(FISH), accepted(plain(FISH), row(FISH, national(), "protein")), read)
        self.assertEqual((estimates[0]["value"], estimates[0]["unit"]), (20.0, "g"))


class Admission(unittest.TestCase):
    def check(self, doc, rows, admitted, status=None, **withheld):
        got, counts = run(doc, *rows, status=status)
        self.assertEqual(len(got), admitted)
        self.assertEqual(counts["admitted"], admitted)
        expected = {f"withheld_{r}": 0 for r in I.REASONS}
        expected.update({f"withheld_{k}": v for k, v in withheld.items()})
        self.assertEqual({k: v for k, v in counts.items() if k.startswith("withheld_")}, expected)
        return counts

    def test_the_reasons_are_the_gate_list_in_order(self):
        self.assertEqual(I.REASONS, ("label_kept", "merged_kept", "composite", "open_food_facts_source",
                                     "refused_source", "readmission_class", "unquantified", "basis",
                                     "fortified_record", "state_contradiction", "transform", "codec"))

    def test_label_kept(self):
        fish, release = labelled("Synthetic Tinned Fish", "protein", 19.0, generic_reference=reference())
        doc = plain(fish, sources=[release])
        self.check(doc, [row(fish, national(), "protein")], 0, label_kept=1)
        self.check(doc, [row(fish, national(), "sodium")], 1)

    def test_merged_kept(self):
        # A merge the app makes: raw entry, raw per 100 g record that is not fortified.
        fish = item("Synthetic Tinned Fish", state="raw", generic_reference=reference(source="usda", record_id=USDA, role="merge"))
        doc = plain(fish)
        self.check(doc, [row(fish, page(), "protein", 21.0)], 0, merged_kept=1)
        self.check(doc, [row(fish, page(), "fiber", 2.0)], 1)  # the merged record has no fibre

    def test_merged_kept_only_where_the_app_merges(self):
        # Qodo on PR 514: a `merge` reference the app does not merge leaves the key unknown in the
        # app, so the accepted estimate is not withheld. Mirrors `mergeEligible`.
        raw_record = reference(source="usda", record_id=USDA, role="merge")  # raw, per 100 g, protein 9
        def entry(state="raw", ref=raw_record, basis="per_100_g"):
            return item("Synthetic Raw Fillet", state=state, basis=basis, generic_reference=ref)
        def accepted(it):
            return [row(it, page(), "protein", 21.0)]
        merged = entry()
        self.check(plain(merged), accepted(merged), 0, merged_kept=1)
        for it in [entry(state="cooked"),                                                   # preparation differs
                   entry(ref=reference(record_id=COFID_OTHER, role="merge")),              # not per 100 g, fortified
                   entry(ref=reference(record_id=FORTIFIED, role="merge")),                # fortified
                   entry(ref=reference(record_id=COFID, role="merge"))]:                   # preparation unknown
            self.check(plain(it), accepted(it), 1)
        self.assertTrue(I.merges(merged, RECORDS[("usda", USDA)]))
        self.assertFalse(I.merges(entry(state="canned"), RECORDS[("usda", USDA)]), "only raw or cooked entries merge")
        self.assertFalse(I.merges(merged, None))

    def test_composite(self):
        dish = item("Synthetic Ready Dish", product_type="packaged_composite")
        doc = plain(dish)
        self.check(doc, [row(dish, national(source="usda", ref=USDA), "protein")], 0, composite=1)
        self.check(doc, [row(dish, page(), "protein", 6.0)], 1)

    def test_open_food_facts_source(self):
        doc = plain(PULSE)
        self.check(doc, [row(PULSE, page("aggregator"), "fiber", 7.5, underlying="open_food_facts")], 0,
                   open_food_facts_source=1)
        self.check(doc, [row(PULSE, page("aggregator", url="https://world.openfoodfacts.org/product/1"), "fiber", 7.5)],
                   0, open_food_facts_source=1)
        self.check(doc, [row(PULSE, page("aggregator"), "fiber", 7.5)], 1)

    def test_refused_source_and_readmission_class(self):
        doc, rows = plain(FISH), [row(FISH, national(), "protein")]
        seen = []

        def status(answer):
            return lambda entry_id, key, ev, corpus: seen.append((entry_id, key, corpus)) or answer

        self.check(doc, rows, 0, status=status(I.REFUSED), refused_source=1)
        self.check(doc, rows, 0, status=status(I.CLASS), readmission_class=1)
        self.check(doc, rows, 0, status=status("anything else"), refused_source=1)
        self.assertEqual(self.check(doc, rows, 1, status=status(I.READMITTED))["admitted_readmitted"], 1)
        self.assertEqual(self.check(doc, rows, 1, status=status(I.CLEAR))["admitted_readmitted"], 0)
        self.assertEqual(seen[0], (FISH["id"], "protein", CORPORA["cofid"]))

    def test_unquantified(self):
        doc = plain(FISH)
        self.check(doc, [row(FISH, national(), "iron")], 0, unquantified=1)  # the record has no iron value
        self.check(doc, [row(FISH, national(ref="cofid:synthetic:row:9999", method="carried_from_similar_food"),
                             "protein")], 0, unquantified=1)  # no such record
        self.check(doc, [row(FISH, national(), "fiber")], 1)  # a quantified zero is a value

    def test_basis(self):
        drink = item("Synthetic Drink", basis="per_100_ml_as_labelled")
        doc = plain(drink, PULSE)
        self.check(doc, [row(drink, national(source="usda", ref=USDA), "protein")], 0, basis=1)
        self.check(doc, [row(PULSE, national(ref=COFID_OTHER), "protein")], 0, basis=1)  # record not per 100 g
        self.check(doc, [row(drink, page(), "protein", 0.4)], 1)

    def test_rows_the_importer_would_reject_are_withheld_and_counted(self):
        # Independent review, 17 November 2026: the app rejects a whole file for a fortified record,
        # or for a raw or cooked entry against a record whose stated preparation differs
        # (`estimate-contradiction`). Where the bundled data shows it, the row is withheld here.
        similar = dict(method="carried_from_similar_food", state_basis="stated_assumption", quality="low")
        raw, cooked = item("Synthetic Raw Leaf", state="raw"), item("Synthetic Cooked Grain", state="cooked")
        doc = plain(FISH, raw, cooked)
        self.check(doc, [row(FISH, national(ref=FORTIFIED, **similar), "protein")], 0, fortified_record=1)
        self.check(doc, [row(raw, national(ref=COOKED, **similar), "protein")], 0, state_contradiction=1)
        self.check(doc, [row(cooked, national(source="usda", ref=USDA, **similar), "protein")], 0, state_contradiction=1)
        # Unknown never contradicts, an equal preparation agrees, and an entry that is neither raw nor
        # cooked is not checked on preparation (the label and the owner's approval carry that).
        self.check(doc, [row(raw, national(ref=COFID, **similar), "protein")], 1)
        self.check(doc, [row(cooked, national(ref=COOKED, **similar), "protein")], 1)
        self.check(doc, [row(FISH, national(ref=COOKED, **similar), "protein")], 1)

    def test_transform(self):
        doc = plain(PULSE)
        derived = page(method="derived", derivation=SALT)
        self.check(doc, [row(PULSE, derived, "sodium", 500.0)], 0, transform=1)
        self.check(doc, [row(PULSE, derived, "sodium", 400.0)], 1)

    def test_codec_names_the_code(self):
        held = item("Synthetic Tinned Fish", state="raw", generic_reference=reference())
        cases = (
            (plain(held), row(held, national(), "protein"), "estimate-own-held"),
            (plain(FISH), row(FISH, national(method="carried_from_similar_food"), "protein"), "estimate-own-method"),
            (plain(FISH), row(FISH, national(state_basis="unknown", quality="low"), "protein"), "estimate-own-state"),
            (plain(PULSE), row(PULSE, national(source="usda", ref=USDA, quality="high"), "protein"), "estimate-quality"),
            (plain(PULSE, corpora={"cofid": CORPORA["cofid"]}), row(PULSE, national(source="usda", ref=USDA), "protein"),
             "corpus-undeclared"),
        )
        for doc, one, code in cases:
            self.assertEqual(self.check(doc, [one], 0, codec=1)[f"codec_{code}"], 1, code)
        self.check(plain(FISH), [row(FISH, national(quality="high"), "protein")], 1)

    def test_the_first_reason_wins(self):
        fish, release = labelled("Synthetic Tinned Fish", "protein", 19.0, product_type="packaged_composite")
        doc = plain(fish, sources=[release])
        self.check(doc, [row(fish, national(source="usda", ref=USDA), "protein")], 0,
                   status=lambda *_: I.REFUSED, label_kept=1)
        self.check(doc, [row(fish, national(source="usda", ref=USDA), "iron")], 0,
                   status=lambda *_: I.REFUSED, composite=1)


class Assembly(unittest.TestCase):
    def setUp(self):
        self.doc = plain(FISH, PULSE)
        self.admitted, _ = run(self.doc, row(FISH, national(quality="high")), row(PULSE, page(), "fiber", 7.5))
        self.out = I.assemble(self.doc, self.admitted)

    def test_shape_order_and_evidence_ids(self):
        out = self.out
        self.assertEqual(len(self.admitted), 5)
        self.assertEqual(out["schema"], export_v1.SCHEMA_ESTIMATES_V2)
        self.assertEqual(list(out), list(self.doc) + ["estimate_evidence"])
        for before, after in zip(self.doc["items"], out["items"]):
            self.assertEqual(list(after), list(before) + ["estimated_nutrients"])
            self.assertEqual(list(after["estimated_nutrients"]), sorted(after["estimated_nutrients"]))
        ids = [r["id"] for r in out["estimate_evidence"]]
        self.assertEqual(ids, sorted(ids))
        fish = next(it for it in out["items"] if it["id"] == FISH["id"])
        self.assertEqual(fish["estimated_nutrients"]["protein"],
                         {"value": 20.0, "unit": "g", "evidence_id": I.evidence_id(FISH["id"], "protein")})

    def test_evidence_id_derivation(self):
        import hashlib
        expected = "pfe:" + hashlib.sha256(f"pfe-v1|{FISH['id']}|protein".encode()).hexdigest()[:16]
        self.assertEqual(I.evidence_id(FISH["id"], "protein"), expected)
        self.assertRegex(expected, r"^pfe:[0-9a-f]{16}$")
        self.assertNotEqual(I.evidence_id(FISH["id"], "fiber"), expected)

    def test_the_output_passes_the_importer_rules_and_the_proofs(self):
        self.assertEqual(export_v1.check_bytes(I.dumps(self.doc)), [])
        self.assertEqual(export_v1.check_bytes(I.dumps(self.out)), [])
        self.assertEqual(export_v1.check_export_conventions(self.out), [])
        self.assertEqual(I.check_additive(self.doc, self.out), [])
        self.assertEqual(I.check_admitted(self.out, self.admitted), [])

    def test_the_additive_proof_fails_on_a_tampered_document(self):
        def tampered(change):
            out = json.loads(I.dumps(self.out))
            change(out)
            return I.check_additive(self.doc, out)

        self.assertTrue(tampered(lambda o: o["items"][0].update(title="Synthetic Other Food")))
        self.assertTrue(tampered(lambda o: o["items"][0]["label_nutrients"].update(protein={})))
        self.assertTrue(tampered(lambda o: o.update(generated="2026-11-18")))
        self.assertTrue(tampered(lambda o: o["items"].pop()))
        self.assertTrue(tampered(lambda o: o.update(schema=export_v1.SCHEMA_V2)))
        self.assertTrue(tampered(lambda o: o.update(extra=[])))
        self.assertTrue(tampered(lambda o: [it["estimated_nutrients"].clear() for it in o["items"]]))
        self.assertTrue(I.check_additive(self.doc, None))  # never raises

    def test_the_admitted_proof_fails_on_a_changed_value_or_record(self):
        out = json.loads(I.dumps(self.out))
        out["items"][0]["estimated_nutrients"] and next(iter(out["items"][0]["estimated_nutrients"].values())).update(value=1)
        out["items"][1]["estimated_nutrients"] and next(iter(out["items"][1]["estimated_nutrients"].values())).update(value=1)
        self.assertIn("estimate-changed", I.check_admitted(out, self.admitted))
        out = json.loads(I.dumps(self.out))
        out["estimate_evidence"][0]["quality"] = "low"
        self.assertEqual(I.check_admitted(out, self.admitted), ["evidence-changed"])
        self.assertTrue(I.check_admitted(self.out, self.admitted[1:]))

    def test_plain_bytes_stand_when_nothing_is_admitted(self):
        data = I.dumps(self.doc)
        admitted, counts = run(self.doc, row(PULSE, page("aggregator"), "fiber", 7.5, underlying="open_food_facts"))
        self.assertEqual((admitted, counts["withheld_open_food_facts_source"]), ([], 1))
        self.assertIs(I.output_bytes(data, self.doc, admitted), data)
        self.assertEqual(I.dumps(json.loads(data)), data)  # the plain file round-trips byte for byte
        self.assertNotEqual(I.output_bytes(data, self.doc, self.admitted), data)

    def test_change_report_is_counts_only(self):
        doc = plain(FISH, PULSE)
        admitted, _ = run(doc, row(FISH, national()), row(PULSE, page("aggregator", quality="medium"), "fiber", 7.5,
                                                          underlying="not_stated"),
                          row(PULSE, national(source="usda", ref=USDA, method="carried_from_similar_food"), "iron"))
        report = I.change_report(doc, admitted, read)
        self.assertEqual(report["checked_against_bundled_record"], 5)
        self.assertEqual(report["national_by_composition_source_cofid"], 4)
        self.assertEqual(report["record_preparation_unknown"], 4)
        self.assertEqual(report["source_never_states_fortification"], 1)  # the USDA record
        self.assertEqual(report["raw_record_on_non_raw_entry"], 1)
        self.assertEqual(report["aggregator_underlying_not_stated"], 1)
        self.assertEqual(report["zeros_national_composition"], 1)
        self.assertEqual(report["entries_with_estimates"], 2)
        self.assertTrue(all(isinstance(v, int) for v in report.values()))
        self.assertNotIn("Synthetic", json.dumps(report))


class EndToEnd(unittest.TestCase):
    """apply_estimates.main on a temporary workspace, with real record IDs from the public corpus."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        os.chmod(cls.tmp, 0o700)
        config = cls.tmp / "private-config.json"
        config.write_text(json.dumps({"schema": "pfc-private-config-v1"}))
        os.chmod(config, 0o600)
        cls.before = os.environ.get("PFC_CONFIG")
        os.environ["PFC_CONFIG"] = str(config)  # synthetic only: never the owner's private config
        import apply_estimates
        cls.AP = apply_estimates
        cls.repo = Path(sys.argv[1]).resolve().parents[3]
        cls.ws = cls.tmp / "ws"
        for d in (cls.ws, cls.ws / "work", cls.ws / "out"):
            d.mkdir()
            os.chmod(d, 0o700)
        cls.pins, errs = export_v1.corpus_pins(cls.repo)
        assert not errs, errs
        res = cls.repo / "Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources"
        cofid = json.loads((res / export_v1.SWIFT_PINS["cofid"][0]).read_bytes())["records"]
        usda = json.loads((res / export_v1.SWIFT_PINS["usda"][0]).read_bytes())["records"]
        cls.cofid = next(r for r in cofid if r["identity"]["serving_basis"] == "per_100_g"
                         and r["identity"]["fortification"] != "fortified"
                         and len(apply_estimates.cofid_facts(r)["nutrients"]) >= 3)["record_id"]
        cls.usda = next(r for r in usda if len(apply_estimates.usda_facts(r)["nutrients"]) >= 3)["id"]
        cls.reader = staticmethod(apply_estimates.record_reader(cls.repo))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)
        if cls.before is None:
            os.environ.pop("PFC_CONFIG", None)
        else:
            os.environ["PFC_CONFIG"] = cls.before

    def main(self):
        buffer, code = io.StringIO(), 0
        with contextlib.redirect_stdout(buffer):
            try:
                self.AP.main(self.ws, self.repo)
            except SystemExit as e:
                code = e.code
        text = buffer.getvalue()
        for private in ("Synthetic", "Example", "7.5"):
            self.assertNotIn(private, text)
        return code, text

    def write_input(self, release, *rows):
        rows = sorted(rows, key=lambda r: (r["entry_id"], r.get("nutrient", "")))
        (self.ws / "work" / self.AP.INPUT_NAME).write_bytes(I.build(release, rows))

    def test_runs(self):
        out = self.ws / "out"
        fish = item("Synthetic Tinned Fish", generic_reference=reference(record_id=self.cofid, corpora=self.pins))
        pulse = item("Synthetic Dried Pulse", state="dried")
        doc = plain(fish, pulse, corpora=self.pins)
        data = I.dumps(doc)
        self.assertEqual(export_v1.check_bytes(data), [])
        plain_path, estimates_path = out / export_v1.OUTPUT_NAME, out / self.AP.OUTPUT_NAME
        release = I.release_id(data)

        code, text = self.main()  # no plain file yet
        self.assertEqual(code, 2)
        plain_path.write_bytes(data)

        code, text = self.main()  # no input: nothing to do
        self.assertEqual(code, 0)
        self.assertIn("the plain v2 file stands", text)
        self.assertFalse(estimates_path.exists())

        usda_key = sorted(self.reader("usda", self.usda)["nutrients"])[0]
        good = [row(fish, national(ref=self.cofid, quality="high")), row(pulse, page(), "fiber", 7.5),
                row(pulse, national(source="usda", ref=self.usda, method="carried_from_similar_food"), usda_key)]
        if usda_key == "fiber":
            good.pop(1)
        self.write_input(release, *good)
        code, text = self.main()
        self.assertEqual(code, 0, text)
        written = estimates_path.read_bytes()
        self.assertEqual(export_v1.check_bytes(written), [])
        self.assertEqual(stat.S_IMODE(estimates_path.stat().st_mode), 0o600)
        self.assertEqual(plain_path.read_bytes(), data)  # the plain v2 file is never modified
        result = json.loads(written)
        self.assertEqual(result["schema"], export_v1.SCHEMA_ESTIMATES_V2)
        by_id = {it["id"]: it for it in result["items"]}
        self.assertEqual(set(by_id[fish["id"]]["estimated_nutrients"]), set(self.reader("cofid", self.cofid)["nutrients"]))
        self.assertIn(usda_key, by_id[pulse["id"]]["estimated_nutrients"])
        self.assertIn(I.release_id(written), text)
        report = json.loads((out / self.AP.REPORT_NAME).read_bytes())
        # No refusals list was present: the report says so, so a zero count is not read as a check.
        self.assertEqual(report["lists_read"], {self.AP.REFUSALS_NAME: False, self.AP.READMISSIONS_NAME: False,
                                                self.AP.SHEET_NAME: False})
        self.assertTrue(report["written"])
        self.assertEqual(report["counts"]["checked_against_bundled_record"], len(result["estimate_evidence"]) - (len(good) - 2))
        self.assertEqual(report["evaluator_counts"], {k: 0 for k in report["evaluator_counts"]})

        # A must-be-zero count that is not zero refuses the file and retires the earlier one.
        doubtful = page("aggregator", quality="high")
        self.write_input(release, row(pulse, doubtful, "fiber", 7.5, underlying="not_stated"))
        code, text = self.main()
        self.assertEqual(code, 2)
        self.assertIn("aggregator_not_stated_above_medium: 1", text)
        self.assertFalse(estimates_path.exists())
        self.assertTrue((out / self.AP.SUPERSEDED_NAME).exists())
        self.assertFalse(json.loads((out / self.AP.REPORT_NAME).read_bytes())["written"])

        # Nothing admitted: no estimates file, the plain v2 file stands.
        self.write_input(release, row(pulse, page("aggregator"), "fiber", 7.5, underlying="open_food_facts"))
        code, text = self.main()
        self.assertEqual(code, 0)
        self.assertIn("no estimate admitted: the plain v2 file stands", text)
        self.assertFalse(estimates_path.exists())

        # Rows accepted against another release, and an input that is not canonical, refuse the run.
        self.write_input("pfc:sha256:" + "0" * 64, *good)
        self.assertEqual(self.main()[0], 2)
        (self.ws / "work" / self.AP.INPUT_NAME).write_bytes(b'{"schema": "pfc-accepted-estimates-v1"}')
        self.assertEqual(self.main()[0], 2)
        (self.ws / "work" / self.AP.REFUSALS_NAME).write_bytes(b"[]")
        self.write_input(release, *good)
        self.assertEqual(self.main()[0], 2)  # a malformed refusal list
        self.assertEqual(plain_path.read_bytes(), data)
        self.assertFalse(estimates_path.exists())


if __name__ == "__main__":
    unittest.main(argv=sys.argv[:1])
