#!/usr/bin/env python3
"""Synthetic tests for the label photo route (docs/personal-food-catalogue-off-estimates-v1-phase.md
section 6), and the writer of the shared v3 codec fixtures the Swift codec checks too.

Usage:
  python3 -I test_photo_estimates.py <scripts_dir>                          run the tests
  python3 -I test_photo_estimates.py <scripts_dir> --verify <fixtures_dir>  check the v3 fixtures
  python3 -I test_photo_estimates.py <scripts_dir> --write <fixtures_dir>   regenerate them
Every title, brand, barcode and value here is synthetic.
"""
import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import estimate_counts as C  # noqa: E402
import estimates_input as I  # noqa: E402
import estimates_v3 as V3  # noqa: E402
import export_v1  # noqa: E402
import test_export_check as X  # noqa: E402
from test_estimates_input import item, plain, read, row  # noqa: E402

BARCODE_OWN = "0000000000024"   # the serving bar's own label record, off:gtin:00000000000024
PHOTO_OWN = "https://images.openfoodfacts.org/images/products/000/000/000/0024/nutrition_en.1.400.jpg"
PHOTO_OTHER = "https://images.openfoodfacts.org/images/products/500/000/000/0017/nutrition_en.3.full.jpg"
PHOTO_SHORT = "https://images.openfoodfacts.org/images/products/29308750/nutrition_en.2.full.jpg"
DIGEST = "e" * 64


def photo(method="direct", url=PHOTO_OWN, quality="medium", state="as sold", basis="source_states_it", **changes):
    return {"approved_as_estimate": True, "source_type": V3.TOKEN, "composition_source": None,
            "source_reference": url, "page_access": "direct_read", "source_digest": DIGEST,
            "retrieved_on": "2026-11-18", "source_state": state, "target_state": "as sold", "state_basis": basis,
            "method": method, "assumption": "Synthetic assumption for a photo.", "derivation": None,
            "quality": quality, **changes}


# ---- shared codec fixtures (Python and Swift give the same codes in the same order) ------------

def golden_v3():
    d = X.golden_estimates()
    d["schema"] = V3.SCHEMA
    d["generated"] = "2026-11-18"
    # same food: a photo of the barcode the bar's own label cites
    X.put(d, X.BAR, "sugar", 12.0, photo())
    # similar food: another barcode, on an entry of unknown state, stated assumption at medium
    X.put(d, X.CHEESE, "fiber", 0.5, photo("carried_from_similar_food", PHOTO_OTHER, basis="stated_assumption"))
    return d


def _photo(d):
    return X.rec(d, X.BAR, "sugar")


def _v3(f):
    d = golden_v3()
    f(d)
    return d


CASES = {  # name -> (expected codes in order, mutation)
    "photo-in-v2-file": (["token", "token"], lambda d: d.update(schema=X.E.SCHEMA_ESTIMATES_V2)),
    "photo-missing": (["photo-missing"], lambda d: (d.update(estimate_evidence=[
        r for r in d["estimate_evidence"] if r["source_type"] != V3.TOKEN]),
        X.find(d, X.BAR)["estimated_nutrients"].pop("sugar"), X.find(d, X.CHEESE)["estimated_nutrients"].pop("fiber"))),
    "photo-other-host": (["photo-fields"], lambda d: _photo(d).update(
        source_reference="https://static.openfoodfacts.org/images/products/000/000/000/0024/n.jpg")),
    "photo-world-host": (["photo-fields"], lambda d: _photo(d).update(
        source_reference="https://world.openfoodfacts.org/product/0000000000024")),
    "photo-maker-host": (["photo-fields"], lambda d: _photo(d).update(source_reference=X.PAGE)),
    "photo-upper-case-host": (["photo-fields"], lambda d: _photo(d).update(
        source_reference=PHOTO_OWN.replace("images.openfoodfacts.org", "Images.OpenFoodFacts.org"))),
    "photo-port": (["photo-fields"], lambda d: _photo(d).update(
        source_reference=PHOTO_OWN.replace(".org/", ".org:443/", 1))),
    "photo-query": (["photo-fields"], lambda d: _photo(d).update(source_reference=PHOTO_OWN + "?x=1")),
    "photo-fragment": (["photo-fields"], lambda d: _photo(d).update(source_reference=PHOTO_OWN + "#a")),
    "photo-no-digit-segment": (["photo-fields"], lambda d: _photo(d).update(
        source_reference="https://images.openfoodfacts.org/images/products/nutrition_en.jpg")),
    "photo-letters-in-code": (["photo-fields"], lambda d: _photo(d).update(
        source_reference="https://images.openfoodfacts.org/images/products/000/abc/0024/n.jpg")),
    "photo-missing-digest": (["photo-fields"], lambda d: _photo(d).update(source_digest=None)),
    "photo-digest-not-hex": (["photo-fields", "digest"], lambda d: _photo(d).update(source_digest="x")),
    "photo-missing-date": (["photo-fields"], lambda d: _photo(d).update(retrieved_on=None)),
    "photo-indexed-copy": (["photo-fields"], lambda d: _photo(d).update(page_access="indexed_copy")),
    "photo-composition-source": (["photo-fields"], lambda d: _photo(d).update(composition_source="cofid")),
    "photo-state-unknown": (["photo-fields"], lambda d: _photo(d).update(state_basis="unknown", quality="low")),
    "photo-same-food-method": (["photo-fields"], lambda d: _photo(d).update(method="carried_from_same_food")),
    "photo-derived-without-derivation": (["photo-fields", "derivation-missing"],
                                         lambda d: _photo(d).update(method="derived")),
    "photo-derivation-present": (["photo-fields", "derivation-unexpected"], lambda d: _photo(d).update(
        derivation={"transform_id": "salt_to_sodium_v1", "version": "pasted-label-conversions-v1",
                    "source_value": {"value": 1.0, "unit": "g"}})),
    "photo-high": (["estimate-quality"], lambda d: _photo(d).update(quality="high")),
    "photo-relation-other-barcode": (["photo-relation"], lambda d: _photo(d).update(source_reference=PHOTO_OTHER)),
    "page-on-open-food-facts-host-in-v3": (["open-food-facts-host"], lambda d: X.rec(d, X.BAR, "fiber").update(
        source_reference="https://world.openfoodfacts.org/product/24")),
}
ACCEPT = {
    "photo-short-code": lambda: _v3(lambda d: X.rec(d, X.CHEESE, "fiber").update(source_reference=PHOTO_SHORT)),
    "photo-low": lambda: _v3(lambda d: _photo(d).update(quality="low")),
}


def code_list(data):
    return [e.split(":", 1)[0] for e in X.E.check_bytes(data)]


def write(fixtures: Path):
    fixtures.mkdir(parents=True, exist_ok=True)
    for old in [*fixtures.glob("reject-*.json"), *fixtures.glob("accept-*.json")]:
        old.unlink()
    (fixtures / "golden.json").write_text(json.dumps(golden_v3(), indent=1, ensure_ascii=False) + "\n")
    manifest = {"contract": "docs/personal-food-catalogue-off-estimates-v1-proposal.md",
                "phase_gate": "docs/personal-food-catalogue-off-estimates-v1-phase.md", "schema": V3.SCHEMA,
                "golden": "golden.json", "photo_rule_codes": list(V3.RULE_CODES),
                "note": "each reject fixture gives exactly the listed codes, in order, from both checkers",
                "reject": {}, "accept": []}
    for name, (expected, f) in CASES.items():
        (fixtures / f"reject-{name}.json").write_text(json.dumps(_v3(f), ensure_ascii=False) + "\n")
        manifest["reject"][f"reject-{name}.json"] = expected
    for name, make in ACCEPT.items():
        (fixtures / f"accept-{name}.json").write_text(json.dumps(make(), ensure_ascii=False) + "\n")
        manifest["accept"].append(f"accept-{name}.json")
    (fixtures / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"wrote golden.json, {len(CASES)} rejection and {len(ACCEPT)} accept fixtures to {fixtures}")


def verify(fixtures: Path):
    manifest = json.loads((fixtures / "manifest.json").read_text())
    golden_bytes = (fixtures / "golden.json").read_bytes()
    assert json.loads(golden_bytes) == golden_v3(), "golden.json differs from the generator; regenerate it"
    assert X.E.check_bytes(golden_bytes) == [], X.E.check_bytes(golden_bytes)
    assert manifest["photo_rule_codes"] == list(V3.RULE_CODES)
    for f in manifest["accept"]:
        assert X.E.check_bytes((fixtures / f).read_bytes()) == [], f
    wrong = [(f, want, got) for f, want in manifest["reject"].items()
             if (got := code_list((fixtures / f).read_bytes())) != want]
    for w in wrong:
        print("  WRONG:", w)
    print(f"estimates v3 golden accepted; {len(manifest['reject']) - len(wrong)} of {len(manifest['reject'])} "
          f"photo fixtures give exactly their codes")
    if wrong:
        sys.exit(1)


# ---- unit tests -------------------------------------------------------------------------------

FROZEN = item("Synthetic Frozen Berries", state="frozen")
COOKED = item("Synthetic Cooked Pouch", state="cooked")
UNKNOWN = item("Synthetic Granola", state="unknown")
CANNED = item("Synthetic Tinned Beans", state="canned")


def prow(entry, evidence, nutrient="fiber", value=3.5, ready=True, **changes):
    return {**row(entry, evidence, nutrient, value), "ready_to_eat": ready, **changes}


def build(*rows, doc=None):
    doc = doc or plain(FROZEN, COOKED, UNKNOWN, CANNED)
    rows = sorted(rows, key=lambda r: (r["entry_id"], r.get("nutrient", "")))
    return doc, I.parse(I.build(I.release_id(I.dumps(doc)), rows))


def admit(*rows, status=None, doc=None):
    doc, acc = build(*rows, doc=doc)
    estimates, _ = I.expand(doc, acc, read)
    return I.admit(doc, estimates, read, status)


class Input(unittest.TestCase):
    def refused(self, *rows, schema=None):
        doc = plain(FROZEN, COOKED, UNKNOWN, CANNED)
        rows = sorted(rows, key=lambda r: (r["entry_id"], r.get("nutrient", "")))
        body = {"schema": schema or I.SCHEMA_V2, "catalogue_release_id": I.release_id(I.dumps(doc)), "rows": rows}
        with self.assertRaises(I.EstimatesRefused) as cm:
            I.validate(body)
        self.assertNotIn("Synthetic", str(cm.exception))
        return str(cm.exception)

    def test_input_v2_is_chosen_for_a_photo_and_accepted(self):
        _, acc = build(prow(FROZEN, photo("carried_from_similar_food", PHOTO_OTHER)))
        self.assertEqual(acc["schema"], I.SCHEMA_V2)

    def test_input_v1_refuses_the_token(self):
        self.assertIn("token", self.refused(prow(FROZEN, photo("carried_from_similar_food", PHOTO_OTHER)),
                                            schema=I.SCHEMA))

    def test_ready_to_eat_only_and_always_on_a_photo_row(self):
        self.refused({k: v for k, v in prow(FROZEN, photo("carried_from_similar_food", PHOTO_OTHER)).items()
                      if k != "ready_to_eat"})
        self.refused({**row(FROZEN, X.page(), "fiber", 3.0), "ready_to_eat": True})
        self.refused(prow(FROZEN, photo("carried_from_similar_food", PHOTO_OTHER), ready="yes"))

    def test_underlying_source_must_be_not_applicable(self):
        self.refused(prow(FROZEN, photo("carried_from_similar_food", PHOTO_OTHER), underlying_source="open_food_facts"))

    def test_source_state_is_a_closed_exact_list(self):
        self.assertIn("closed list", self.refused(prow(FROZEN, photo("carried_from_similar_food", PHOTO_OTHER,
                                                                     state="As sold"))))
        self.refused(prow(FROZEN, photo("carried_from_similar_food", PHOTO_OTHER, state="as eaten")))

    def test_stated_assumption_needs_ready_to_eat_and_an_as_sold_panel(self):
        sa = dict(basis="stated_assumption")
        self.refused(prow(UNKNOWN, photo("carried_from_similar_food", PHOTO_OTHER, **sa), ready=False))
        self.refused(prow(COOKED, photo("carried_from_similar_food", PHOTO_OTHER, state="as prepared", **sa)))
        self.refused(prow(COOKED, photo("carried_from_similar_food", PHOTO_OTHER, state="cooked", **sa)))
        build(prow(UNKNOWN, photo("carried_from_similar_food", PHOTO_OTHER, **sa)))

    def test_the_photo_record_rules_refuse_the_row(self):
        for bad in (dict(source_digest=None), dict(retrieved_on=None), dict(page_access="indexed_copy"),
                    dict(method="carried_from_same_food"), dict(source_reference=X.PAGE),
                    dict(derivation={"transform_id": "x", "version": "y", "source_value": {"value": 1, "unit": "g"}})):
            ev = {**photo("carried_from_similar_food", PHOTO_OTHER), **bad}
            relation = {"relation": "same_food"} if bad.get("method") == "carried_from_same_food" else {}
            self.refused(prow(FROZEN, ev, **relation))

    def test_refusal_list_and_sheet_rows_keep_the_v2_token_set(self):
        for parse, body in (
            (C.parse_refusals, {"schema": C.SCHEMA_REFUSALS, "rows": [
                {"entry_id": FROZEN["id"], "source_type": V3.TOKEN, "source_reference": PHOTO_OTHER,
                 "refusal_class": "open_food_facts"}]}),
            (C.parse_readmissions, {"schema": C.SCHEMA_READMISSIONS, "rows": [
                {"entry_id": FROZEN["id"], "nutrient": "fiber", "source_type": V3.TOKEN, "source_reference": PHOTO_OTHER,
                 "method": "direct", "corpus_sha256": "a" * 64, "date": "2026-11-18"}]})):
            with self.assertRaises(I.EstimatesRefused):
                parse(I.canonical(body))


class Admission(unittest.TestCase):
    def test_a_photo_is_not_withheld_as_an_open_food_facts_source(self):
        admitted, counts = admit(prow(FROZEN, photo("carried_from_similar_food", PHOTO_OTHER, state="frozen")))
        self.assertEqual(len(admitted), 1)
        self.assertEqual(counts["withheld_open_food_facts_source"], 0)

    def test_the_state_table(self):
        cases = [(FROZEN, "frozen", "source_states_it", True), (FROZEN, "as sold", "source_states_it", True),
                 (FROZEN, "cooked", "source_states_it", False), (COOKED, "as sold", "source_states_it", False),
                 (COOKED, "as sold, cooked", "source_states_it", True), (COOKED, "as prepared", "source_states_it", True),
                 (UNKNOWN, "as prepared", "source_states_it", False), (UNKNOWN, "as sold", "source_states_it", True),
                 (UNKNOWN, "raw", "source_states_it", True), (CANNED, "drained", "source_states_it", True),
                 (CANNED, "as sold", "source_states_it", True), (CANNED, "as sold", "stated_assumption", False)]
        for entry, state, basis, ok in cases:
            admitted, counts = admit(prow(entry, photo("carried_from_similar_food", PHOTO_OTHER, state=state,
                                                       basis=basis)))
            self.assertEqual(bool(admitted), ok, (entry["title"], state, basis))
            self.assertEqual(counts["withheld_state_contradiction"], 0 if ok else 1)

    def lists(self, *rows):
        return C.Lists({"schema": C.SCHEMA_REFUSALS, "rows": list(rows)})

    def test_refusal_rows_of_another_source_type_match_by_entry_and_nutrient(self):
        ev = photo("carried_from_similar_food", PHOTO_OTHER, state="frozen")
        whole = self.lists({"entry_id": FROZEN["id"], "source_type": "aggregator",
                            "source_reference": "https://world.openfoodfacts.org/product/1", "refusal_class": "open_food_facts"})
        other = self.lists({"entry_id": FROZEN["id"], "source_type": "aggregator", "nutrient": "protein",
                            "source_reference": "https://world.openfoodfacts.org/product/1", "refusal_class": "value_fault"})
        same = self.lists({"entry_id": FROZEN["id"], "source_type": "national_composition", "nutrient": "fiber",
                           "source_reference": "cofid:synthetic:row:0009", "refusal_class": "per_entry_exclusion"})
        other_class = self.lists({"entry_id": FROZEN["id"], "source_type": "national_composition",
                                  "source_reference": "cofid:synthetic:row:0009", "refusal_class": "stratum_consequence"})
        self.assertEqual(whole.status(FROZEN["id"], "fiber", ev, None), I.REFUSED)
        self.assertEqual(whole.status(FROZEN["id"], "protein", ev, None), I.REFUSED)
        self.assertEqual(other.status(FROZEN["id"], "fiber", ev, None), I.CLEAR)
        self.assertEqual(same.status(FROZEN["id"], "fiber", ev, None), I.REFUSED)
        self.assertEqual(other_class.status(FROZEN["id"], "fiber", ev, None), I.CLEAR)

    def test_the_barcode_rule_refuses_the_photo_for_every_entry(self):
        lists = self.lists({"entry_id": COOKED["id"], "source_type": "aggregator",
                            "source_reference": "https://world.openfoodfacts.org/product/5000000000017",
                            "refusal_class": "open_food_facts", "nutrient": "sugar"})
        ev = photo("carried_from_similar_food", PHOTO_OTHER, state="frozen")
        self.assertEqual(lists.status(FROZEN["id"], "fiber", ev, None), I.REFUSED)
        gtin = self.lists({"entry_id": COOKED["id"], "source_type": "aggregator",
                           "source_reference": "off:gtin:00005000000000017", "refusal_class": "unresolved_a1"})
        self.assertEqual(gtin.status(UNKNOWN["id"], "fiber", ev, None), I.REFUSED)
        admitted, counts = admit(prow(FROZEN, ev), status=lists.status)
        self.assertEqual((admitted, counts["withheld_refused_source"]), ([], 1))

    def test_barcodes_from_addresses(self):
        self.assertEqual(V3.barcode(PHOTO_OWN), BARCODE_OWN)
        self.assertEqual(V3.barcode(PHOTO_SHORT), "29308750")
        self.assertIsNone(V3.barcode(PHOTO_OWN.replace("images.", "static.")))
        self.assertIsNone(V3.barcode("https://images.openfoodfacts.org/images/products/12/"))
        self.assertEqual(C.refusal_barcode("off:gtin:00000029308750"), "29308750")
        self.assertIsNone(C.refusal_barcode("cofid:synthetic:row:0001"))


class Writer(unittest.TestCase):
    def test_v3_only_with_a_photo_admitted(self):
        doc = plain(FROZEN, COOKED, UNKNOWN, CANNED)
        page_only, _ = admit(row(FROZEN, X.page(), "fiber", 3.0), doc=doc)
        self.assertEqual(I.assemble(doc, page_only)["schema"], export_v1.SCHEMA_ESTIMATES_V2)
        with_photo, _ = admit(row(COOKED, X.page(), "fiber", 3.0),
                              prow(FROZEN, photo("carried_from_similar_food", PHOTO_OTHER, state="frozen")), doc=doc)
        out = I.assemble(doc, with_photo)
        self.assertEqual(out["schema"], export_v1.SCHEMA_ESTIMATES_V3)
        data = I.dumps(out)
        self.assertEqual(export_v1.check_bytes(data), [])
        self.assertEqual(I.check_additive(doc, out), [])
        self.assertEqual(I.check_admitted(out, with_photo), [])
        report = I.change_report(doc, with_photo, read)
        self.assertEqual((report["photo_admitted_macro"], report["photo_admitted_similar_food"]), (1, 1))

    def test_the_state_mismatch_check_fails_a_tampered_document(self):
        doc = plain(FROZEN, COOKED, UNKNOWN, CANNED)
        admitted, _ = admit(prow(FROZEN, photo("carried_from_similar_food", PHOTO_OTHER, state="frozen")), doc=doc)
        out = I.assemble(doc, admitted)
        out["estimate_evidence"][0]["source_state"] = "cooked"
        result = C.six_counts(out, [], C.Lists({"schema": C.SCHEMA_REFUSALS, "rows": []}))
        self.assertIn("photo-state-mismatch: 1", C.failures(result))


class EndToEnd(unittest.TestCase):
    """apply_estimates.main on a temporary workspace: the output name follows the schema."""

    def test_names(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            os.chmod(tmp, 0o700)
            config = tmp / "private-config.json"
            config.write_text(json.dumps({"schema": "pfc-private-config-v1"}))
            os.chmod(config, 0o600)
            before = os.environ.get("PFC_CONFIG")
            os.environ["PFC_CONFIG"] = str(config)
            import apply_estimates as AP
            repo = Path(sys.argv[1]).resolve().parents[3]
            pins, errs = export_v1.corpus_pins(repo)
            self.assertEqual(errs, [])
            ws = tmp / "ws"
            for d in (ws, ws / "work", ws / "out"):
                d.mkdir()
                os.chmod(d, 0o700)
            doc = plain(FROZEN, COOKED, corpora=pins)
            data = I.dumps(doc)
            (ws / "out" / export_v1.OUTPUT_NAME).write_bytes(data)
            (ws / "work" / AP.REFUSALS_NAME).write_bytes(I.canonical({"schema": C.SCHEMA_REFUSALS, "rows": []}))

            def run(*rows):
                rows = sorted(rows, key=lambda r: (r["entry_id"], r.get("nutrient", "")))
                (ws / "work" / AP.INPUT_NAME).write_bytes(I.build(I.release_id(data), rows))
                with contextlib.redirect_stdout(io.StringIO()):
                    try:
                        AP.main(ws, repo)
                    except SystemExit as e:
                        self.assertIn(e.code, (0, None))

            run(row(COOKED, X.page(), "fiber", 3.0))
            v2_bytes = (ws / "out" / AP.OUTPUT_NAME).read_bytes()
            self.assertFalse((ws / "out" / AP.OUTPUT_NAME_V3).exists())
            run(row(COOKED, X.page(), "fiber", 3.0), prow(FROZEN, photo("carried_from_similar_food", PHOTO_OTHER,
                                                                        state="frozen")))
            self.assertTrue((ws / "out" / AP.OUTPUT_NAME_V3).exists())
            self.assertFalse((ws / "out" / AP.OUTPUT_NAME).exists())
            run(row(COOKED, X.page(), "fiber", 3.0))
            self.assertEqual((ws / "out" / AP.OUTPUT_NAME).read_bytes(), v2_bytes)  # v2 bytes unchanged
            self.assertFalse((ws / "out" / AP.OUTPUT_NAME_V3).exists())
            if before is None:
                os.environ.pop("PFC_CONFIG", None)
            else:
                os.environ["PFC_CONFIG"] = before
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    if len(sys.argv) > 3 and sys.argv[2] == "--write":
        write(Path(sys.argv[3]))
    elif len(sys.argv) > 3 and sys.argv[2] == "--verify":
        verify(Path(sys.argv[3]))
    else:
        unittest.main(argv=[sys.argv[0]])
