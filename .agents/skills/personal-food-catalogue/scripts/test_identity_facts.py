#!/usr/bin/env python3
"""Synthetic tests for food details from the catalogue (docs/personal-food-catalogue-identity-facts-v1-amendment.md
sections I1.1 to I1.5), and the writer of the shared v4 codec fixtures the Swift codec checks too.

Usage:
  python3 -I test_identity_facts.py <scripts_dir>                          run the tests
  python3 -I test_identity_facts.py <scripts_dir> --verify <fixtures_dir>  check the v4 fixtures
  python3 -I test_identity_facts.py <scripts_dir> --write <fixtures_dir>   regenerate them
Every title, brand and value here is synthetic.
"""
import contextlib
import copy
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import export_v1  # noqa: E402
import identity_facts as F  # noqa: E402
import test_export_check as X  # noqa: E402
import test_photo_estimates as P  # noqa: E402

# Section I1.1: every fact stated, for a food sold as it is eaten.
AS_SOLD = {"preparation": "as_sold", "bone": "not_applicable", "skin": "not_applicable", "drained": "not_applicable",
           "packing_medium": "not applicable", "fortification": "unfortified"}
COOKED_PART = {**F.UNKNOWN, "preparation": "cooked", "packing_medium": "not applicable"}
RAW_FILL = {**F.UNKNOWN, "preparation": "raw", "bone": "not_applicable", "skin": "not_applicable",
            "fortification": "unfortified"}


# ---- shared codec fixtures ----------------------------------------------------------------------

def to_v4(d, facts=None):
    """The document as v4: the schema, and `identity_facts` on every entry (null unless named)."""
    d["schema"] = F.SCHEMA
    for it in d["items"]:
        it["identity_facts"] = copy.deepcopy((facts or {}).get(it["title"]))
    return d


def golden_v4():
    d = X.golden_estimates()
    d["generated"] = "2026-11-20"
    return to_v4(d, {X.CRISPS: AS_SOLD, X.RICE: COOKED_PART, X.OATS: RAW_FILL})


def _v4(f):
    d = golden_v4()
    f(d)
    return d


def _facts(d, title):
    return X.find(d, title)["identity_facts"]


def _only(d, title, schema):
    """An earlier schema with one entry's `identity_facts` key left in."""
    d["schema"] = schema
    for it in d["items"]:
        if it["title"] != title:
            it.pop("identity_facts")
    return d


def _v3_with_key():
    d = P.golden_v3()
    for it in d["items"]:
        if it["title"] == X.OATS:
            it["identity_facts"] = copy.deepcopy(RAW_FILL)
    return d


CASES = {  # name -> (expected codes in order, document maker)
    "facts-missing-key": (["facts-keys"], lambda: _v4(lambda d: _facts(d, X.CRISPS).pop("skin"))),
    "facts-unknown-key": (["facts-keys"], lambda: _v4(lambda d: _facts(d, X.CRISPS).update(salt="unknown"))),
    "facts-not-an-object": (["facts-keys"], lambda: _v4(lambda d: X.find(d, X.CRISPS).update(identity_facts="as_sold"))),
    "facts-fortified": (["facts-value"], lambda: _v4(lambda d: _facts(d, X.CRISPS).update(fortification="fortified"))),
    "facts-value-outside-list": (["facts-value"], lambda: _v4(lambda d: _facts(d, X.RICE).update(preparation="roasted"))),
    "facts-value-not-text": (["facts-value"], lambda: _v4(lambda d: _facts(d, X.CRISPS).update(bone=None))),
    "facts-packing-case": (["facts-value"], lambda: _v4(lambda d: _facts(d, X.CRISPS).update(packing_medium="As sold"))),
    "facts-raw-on-cooked": (["facts-state"], lambda: _v4(lambda d: _facts(d, X.RICE).update(preparation="raw"))),
    "facts-raw-on-unknown-state": (["facts-state"], lambda: _v4(lambda d: _facts(d, X.CRISPS).update(preparation="raw"))),
    "facts-as-sold-on-raw": (["facts-state"], lambda: _v4(lambda d: _facts(d, X.OATS).update(preparation="as_sold"))),
    "facts-key-missing-in-v4": (["item-keys"], lambda: _v4(lambda d: X.find(d, X.OATS).pop("identity_facts"))),
    "facts-in-v2-estimates-file": (["item-keys"], lambda: _only(golden_v4(), X.OATS, export_v1.SCHEMA_ESTIMATES_V2)),
    "facts-in-v3-file": (["item-keys"], _v3_with_key),
}
def _null_merge_other_record():
    """Review fix: a merged entry with null facts and a similar-food estimate from another record
    (which the Swift tests read as differing on skin) imports in v4 as in its v3 twin."""
    d = X.golden_estimates()
    X.put(d, X.OATS, "fiber", 9.0, X.national("cofid:other-skin", "carried_from_similar_food",
                                               "stated_assumption", "low", target_state="raw"))
    return to_v4(d)


def _duplicate_key():
    """A repeated key inside `identity_facts`: the strict reader refuses it before any facts rule."""
    text = json.dumps(golden_v4(), ensure_ascii=False)
    needle = '"identity_facts": {"preparation": "as_sold", '
    assert needle in text
    return text.replace(needle, needle + '"bone": "boneless", ', 1).encode()


RAW = {  # name -> (expected codes, bytes maker): fixtures json.dumps cannot express
    "facts-duplicate-key": (["duplicate-key"], _duplicate_key),
}
ACCEPT = {
    "null-facts-merge-other-record-estimate": _null_merge_other_record,
    "all-null": lambda: to_v4(X.golden_estimates()),
    "with-photo": lambda: to_v4(P.golden_v3(), {X.CRISPS: AS_SOLD}),
    "all-null-with-photo": lambda: to_v4(P.golden_v3()),
    "unknown-preparation-on-canned": lambda: to_v4(X.golden_estimates(), {X.FISH: {**F.UNKNOWN, "packing_medium": "brine"}}),
}
# Section I1.5 step 5: the checker and the Swift `mergeEligible` agree on these (the golden's oats entry,
# raw, merging `cofid:example`; each case gives the entry's facts and the record's identity).
RECORD = {"preparation": "raw", "bone": "unknown", "skin": "unknown", "drained": "unknown",
          "packing_medium": "unknown", "fortification": "unfortified"}
MERGE_CASES = [
    {"name": "eligible-without-facts", "facts": None, "record": RECORD, "eligible": True, "filled": []},
    {"name": "eligible-with-a-fill", "facts": RAW_FILL, "record": RECORD, "eligible": True,
     "filled": ["bone", "skin"]},
    {"name": "eligible-agreeing", "facts": {**F.UNKNOWN, "packing_medium": "not applicable"},
     "record": {**RECORD, "packing_medium": "not applicable"}, "eligible": True, "filled": []},
    {"name": "ineligible-by-a-fact", "facts": {**F.UNKNOWN, "bone": "boneless"},
     "record": {**RECORD, "bone": "with_bone"}, "eligible": False, "filled": []},
    {"name": "ineligible-by-packing", "facts": {**F.UNKNOWN, "packing_medium": "water"},
     "record": {**RECORD, "packing_medium": "brine"}, "eligible": False, "filled": []},
]


def stub_record(identity):
    return {"preparation": identity["preparation"], "fortification": identity["fortification"], "per_100_g": True,
            "identity": {k: identity[k] for k in ("bone", "skin", "drained", "packing_medium")}}


def merge_verdict(case):
    item = {**X.find(golden_v4(), X.OATS), "identity_facts": case["facts"]}
    record = stub_record(case["record"])
    eligible = F.merge_eligible(item, record)
    _, filled = F.entry_identity(item, record if eligible else None)
    return eligible, (filled if eligible else [])


def code_list(data):
    return [e.split(":", 1)[0] for e in export_v1.check_bytes(data)]


def write(fixtures: Path):
    fixtures.mkdir(parents=True, exist_ok=True)
    for old in [*fixtures.glob("reject-*.json"), *fixtures.glob("accept-*.json")]:
        old.unlink()
    (fixtures / "golden.json").write_text(json.dumps(golden_v4(), indent=1, ensure_ascii=False) + "\n")
    manifest = {"contract": "docs/personal-food-catalogue-identity-facts-v1-amendment.md", "schema": F.SCHEMA,
                "golden": "golden.json", "facts_rule_codes": list(F.RULE_CODES),
                "note": "each reject fixture gives exactly the listed codes, in order, from both checkers; "
                        "merge_cases give the same verdict from the skill's checker and the Swift mergeEligible",
                "reject": {}, "accept": [], "merge_cases": MERGE_CASES}
    for name, (expected, make) in CASES.items():
        (fixtures / f"reject-{name}.json").write_text(json.dumps(make(), ensure_ascii=False) + "\n")
        manifest["reject"][f"reject-{name}.json"] = expected
    for name, (expected, make) in RAW.items():
        (fixtures / f"reject-{name}.json").write_bytes(make() + b"\n")
        manifest["reject"][f"reject-{name}.json"] = expected
    for name, make in ACCEPT.items():
        (fixtures / f"accept-{name}.json").write_text(json.dumps(make(), ensure_ascii=False) + "\n")
        manifest["accept"].append(f"accept-{name}.json")
    (fixtures / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"wrote golden.json, {len(CASES) + len(RAW)} rejection and {len(ACCEPT)} accept fixtures to {fixtures}")


def verify(fixtures: Path):
    manifest = json.loads((fixtures / "manifest.json").read_text())
    golden = (fixtures / "golden.json").read_bytes()
    assert json.loads(golden) == golden_v4(), "golden.json differs from the generator; regenerate it"
    assert export_v1.check_bytes(golden) == [], export_v1.check_bytes(golden)
    assert manifest["facts_rule_codes"] == list(F.RULE_CODES)
    for f in manifest["accept"]:
        assert export_v1.check_bytes((fixtures / f).read_bytes()) == [], f
    wrong = [(f, want, got) for f, want in manifest["reject"].items()
             if (got := code_list((fixtures / f).read_bytes())) != want]
    merge_wrong = [c["name"] for c in manifest["merge_cases"]
                   if merge_verdict(c) != (c["eligible"], c["filled"])]
    for w in wrong + merge_wrong:
        print("  WRONG:", w)
    print(f"estimates v4 golden accepted; {len(manifest['reject']) - len(wrong)} of {len(manifest['reject'])} "
          f"facts fixtures give exactly their codes; {len(manifest['merge_cases']) - len(merge_wrong)} of "
          f"{len(manifest['merge_cases'])} merge cases agree")
    if wrong or merge_wrong:
        sys.exit(1)


# ---- unit tests ---------------------------------------------------------------------------------

def records(table):
    return lambda source, record_id: table.get(record_id)


def approved(*rows):
    return {"schema": F.INPUT_SCHEMA, "rows": list(rows)}


class Codec(unittest.TestCase):
    def test_every_case_gives_its_codes(self):
        for name, (expected, make) in CASES.items():
            self.assertEqual(code_list(json.dumps(make()).encode()), expected, name)
        for name, (expected, make) in RAW.items():
            self.assertEqual(code_list(make()), expected, name)

    def test_accepts(self):
        self.assertEqual(export_v1.check_bytes(json.dumps(golden_v4()).encode()), [])
        for name, make in ACCEPT.items():
            self.assertEqual(export_v1.check_bytes(json.dumps(make()).encode()), [], name)

    def test_v4_does_not_need_a_photo(self):
        self.assertFalse(any(r["source_type"] == "product_dataset_photo" for r in golden_v4()["estimate_evidence"]))

    def test_the_state_rule(self):
        for state, ok in (("raw", {"raw", "unknown"}), ("cooked", {"cooked", "unknown"}),
                          ("canned", {"as_sold", "unknown"}), ("unknown", {"as_sold", "unknown"})):
            for preparation in F.VALUES["preparation"]:
                self.assertEqual(F.preparation_agrees(preparation, state), preparation in ok, (state, preparation))


class Merge(unittest.TestCase):
    def test_shared_cases(self):
        for case in MERGE_CASES:
            self.assertEqual(merge_verdict(case), (case["eligible"], case["filled"]), case["name"])

    def test_comparison_is_the_a2_one(self):
        self.assertEqual(F.contradictions({"preparation": "as_sold"}, {"preparation": "raw"}), [])
        self.assertEqual(F.contradictions({"bone": "unknown"}, {"bone": "boneless"}), [])
        self.assertEqual(F.contradictions({"bone": "with_bone"}, {"bone": "boneless"}), ["bone"])


class Apply(unittest.TestCase):
    def base(self):
        d = X.golden_estimates()
        return d

    def test_writes_v4_with_only_approved_facts(self):
        out, report = F.apply(self.base(), approved({"entry_id": X.find(self.base(), X.CRISPS)["id"], "facts": AS_SOLD}),
                              records({}))
        self.assertEqual(out["schema"], F.SCHEMA)
        self.assertEqual(export_v1.check_bytes(json.dumps(out).encode()), [])
        self.assertEqual(X.find(out, X.CRISPS)["identity_facts"], AS_SOLD)
        self.assertIsNone(X.find(out, X.RICE)["identity_facts"])
        self.assertEqual(len(report["written"]), 1)

    def test_a_disagreeing_preparation_is_not_written(self):
        rid = X.find(self.base(), X.RICE)["id"]
        out, report = F.apply(self.base(), approved({"entry_id": rid, "facts": {**F.UNKNOWN, "preparation": "raw"}}),
                              records({}))
        self.assertEqual(report["state_disagrees"], [rid])
        self.assertEqual(report["written"], [])

    def test_merge_ineligible_and_entry_would_disappear(self):
        # a raw merge-only entry (no label or estimate of its own) whose fact contradicts its record
        d = self.base()
        oats = X.find(d, X.OATS)
        oats["label_nutrients"] = {}
        d["sources"] = [s for s in d["sources"] if any(
            v.get("source_release") == s["source_release_id"] for it in d["items"] for v in it["label_nutrients"].values())]
        table = {"cofid:example": stub_record({**RECORD, "bone": "with_bone"})}
        row = {"entry_id": oats["id"], "facts": {**F.UNKNOWN, "bone": "boneless"}}
        out, report = F.apply(d, approved(row), records(table))
        self.assertEqual(report["merge_ineligible"], [oats["id"]])
        self.assertEqual(report["entry_would_disappear"], [oats["id"]])
        self.assertIsNone(X.find(out, X.OATS)["identity_facts"])
        out, report = F.apply(d, approved({**row, "accept_disappear": True}), records(table))
        self.assertEqual(report["written"], [oats["id"]])

    def test_an_estimate_contradiction_is_never_written(self):
        d = self.base()
        fish = X.find(d, X.FISH)
        table = {"cofid:fish": stub_record({**RECORD, "preparation": "unknown", "packing_medium": "brine"})}
        out, report = F.apply(d, approved({"entry_id": fish["id"], "facts": {**F.UNKNOWN, "packing_medium": "oil"}}),
                              records(table))
        self.assertEqual(report["estimate_contradiction"], [fish["id"]])
        self.assertIsNone(X.find(out, X.FISH)["identity_facts"])

    def test_as_sold_raw_searched_is_listed(self):
        d = self.base()
        greens = X.find(d, X.CRISPS)
        greens["aliases"] = ["synthetic almonds"]
        _, report = F.apply(d, approved({"entry_id": greens["id"], "facts": AS_SOLD}), records({}))
        self.assertEqual(report["as_sold_raw_searched"], [greens["id"]])

    def test_input_is_strict(self):
        for bad in ({"schema": "x", "rows": []}, {"schema": F.INPUT_SCHEMA, "rows": [{"entry_id": "pfc:1"}]},
                    {"schema": F.INPUT_SCHEMA, "rows": [{"entry_id": "pfc:1", "facts": {**AS_SOLD, "fortification": "fortified"}}]},
                    {"schema": F.INPUT_SCHEMA, "rows": [{"entry_id": "pfc:1", "facts": AS_SOLD}] * 2}):
            with self.assertRaises(F.FactsRefused) as cm:
                F.parse(json.dumps(bad).encode())
            self.assertNotIn("Synthetic", str(cm.exception))


class EndToEnd(unittest.TestCase):
    """apply_identity_facts.main on a temporary workspace: v4 only with a fact written."""

    def test_names(self):
        tmp = Path(tempfile.mkdtemp())
        before = os.environ.get("PFC_CONFIG")
        try:
            os.chmod(tmp, 0o700)
            config = tmp / "private-config.json"
            config.write_text(json.dumps({"schema": "pfc-private-config-v1"}))
            os.chmod(config, 0o600)
            os.environ["PFC_CONFIG"] = str(config)
            import apply_identity_facts as AF
            import estimates_input as I
            repo = Path(sys.argv[1]).resolve().parents[3]
            pins, errs = export_v1.corpus_pins(repo)
            self.assertEqual(errs, [])
            ws = tmp / "ws"
            for d in (ws, ws / "work", ws / "out"):
                d.mkdir()
                os.chmod(d, 0o700)
            from test_estimates_input import item, plain
            entry = item("Synthetic Rolled Oats", state="dried")
            doc = plain(entry, corpora=pins)
            data = I.dumps(doc)
            (ws / "out" / export_v1.OUTPUT_NAME).write_bytes(data)

            def run(*rows):
                (ws / "work" / AF.INPUT_NAME).write_text(json.dumps(approved(*rows)))
                with contextlib.redirect_stdout(io.StringIO()):
                    try:
                        AF.main(ws, repo)
                    except SystemExit as e:
                        self.assertIn(e.code, (0, None))

            run({"entry_id": entry["id"], "facts": AS_SOLD})
            written = ws / "out" / AF.OUTPUT_NAME
            self.assertTrue(written.exists())
            self.assertEqual(export_v1.check_bytes(written.read_bytes()), [])
            self.assertEqual(json.loads(written.read_bytes())["schema"], F.SCHEMA)
            run({"entry_id": entry["id"], "facts": F.UNKNOWN})
            self.assertFalse(written.exists())
            self.assertEqual((ws / "out" / export_v1.OUTPUT_NAME).read_bytes(), data)  # the v2 file is untouched
        finally:
            if before is None:
                os.environ.pop("PFC_CONFIG", None)
            else:
                os.environ["PFC_CONFIG"] = before
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    if len(sys.argv) > 3 and sys.argv[2] == "--write":
        write(Path(sys.argv[3]))
    elif len(sys.argv) > 3 and sys.argv[2] == "--verify":
        verify(Path(sys.argv[3]))
    else:
        unittest.main(argv=[sys.argv[0]])
