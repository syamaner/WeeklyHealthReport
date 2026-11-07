#!/usr/bin/env python3
"""Shared synthetic fixtures for the import rejection rules, and their Python verdicts.

  python3 -I test_export_check.py <scripts_dir> --write <fixtures_dir>   regenerate the files
  python3 -I test_export_check.py <scripts_dir> <fixtures_dir>           check every file's verdict

The fixtures directory holds golden.json (must be accepted), one reject-*.json per rule, and
manifest.json with the expected verdict for each. The Swift importer tests read the same files
(contract section 9). Every value here is synthetic.
"""
import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import export_v1 as E  # noqa: E402

PIN = "a" * 64
H = "b" * 64
OFF_ID = f"pfc-off:sha256:{H}:projection:off-product-projection-v4:retrieved:2026-11-07"
OWNER_ID = "owner:sha256:" + "c" * 64
OFF_REL = {"source_release_id": OFF_ID, "source_id": "open-food-facts", "released_at": "2026-11-07T00:00:00Z",
           "artifact_sha256": H, "schema_version": "off-v3.6-product-record",
           "pipeline_version": "off-product-projection-v4", "licence": E.SOURCE_PINS["open-food-facts"]["licence"],
           "attribution": "Open Food Facts · https://world.openfoodfacts.org/product/00000017", "manifest_sha256": H}
OWNER_REL = {"source_release_id": OWNER_ID, "source_id": "owner", "released_at": "2026-11-07T00:00:00Z",
             "artifact_sha256": "c" * 64, "schema_version": "pfc-intake-label-v1",
             "pipeline_version": "personal-food-catalogue-skill-v1", "licence": "private",
             "attribution": "Label values typed or confirmed by the owner", "manifest_sha256": "c" * 64}


def entry(brand, title, **over):
    e = {"id": E.entry_id(brand, title), "brand": brand, "title": title, "titles": [title], "aliases": [],
         "concept": "oats", "variety": None, "fallback_chain": ["oats"], "category": "grain_cereal",
         "product_type": "packaged_single_ingredient", "state": "raw", "basis": "per_100_g",
         "label_nutrients": {}, "generic_reference": None}
    e.update(over)
    return e


def golden():
    oats = entry("Example Brand", "Synthetic Example Oats", label_nutrients={
        "sodium": {"value": 5.0, "unit": "mg", "source_kind": "exact_product_dataset", "source_release": OFF_ID,
                   "record_id": "off:gtin:00000000000017", "match": "probable",
                   "transforms": [{"transform_id": "mass-g-to-mg", "version": "v1"}],
                   "source_value": {"value": 0.005, "unit": "g"}},
        "energy_consumed": {"value": 370, "unit": "kcal", "source_kind": "manual_declaration",
                            "source_release": OWNER_ID, "record_id": None, "match": "owner"}},
        generic_reference={"source": "cofid", "corpus_sha256": PIN, "record_id": "cofid:example",
                           "match": "same_food_same_state", "role": "merge"})
    tofu = entry(None, "合成豆腐", concept="tofu", fallback_chain=["tofu"], category="legume", state="unknown",
                 generic_reference={"source": "tfda", "corpus_sha256": PIN, "record_id": "tfda:X0001",
                                    "match": "close", "role": "candidate"})
    salted = entry(None, "Synthetic Crème Spread", concept="spread", category="other", label_nutrients={
        "sodium": {"value": 200.0, "unit": "mg", "source_kind": "manual_declaration", "source_release": OWNER_ID,
                   "record_id": None, "match": "owner",
                   "transforms": [{"transform_id": "salt_to_sodium_v1", "version": "pasted-label-conversions-v1"}],
                   "source_value": {"value": 0.5, "unit": "g"}}})
    items = sorted([oats, tofu, salted], key=lambda x: x["id"])
    return {"schema": "personal-food-catalogue-v1", "generated": "2026-11-07", "sources": [OFF_REL, OWNER_REL],
            "generic_corpora": [{"source": "cofid", "corpus_sha256": PIN}, {"source": "tfda", "corpus_sha256": PIN}],
            "items": items}


def find(d, title):
    return next(i for i in d["items"] if i["title"] == title)


oats = lambda d: find(d, "Synthetic Example Oats")
sod = lambda d: oats(d)["label_nutrients"]["sodium"]
kcal = lambda d: oats(d)["label_nutrients"]["energy_consumed"]
ref = lambda d: oats(d)["generic_reference"]
CASES = {  # name: (expected rule code, mutation)
    "unknown-schema": ("schema", lambda d: d.update(schema="v0")),
    "unknown-top-level-key": ("top-keys", lambda d: d.update(extra=1)),
    "missing-top-level-key": ("top-keys", lambda d: d.pop("generic_corpora")),
    "generated-not-a-date": ("generated", lambda d: d.update(generated="2026-13-45")),
    "generated-week-date": ("generated", lambda d: d.update(generated="2026-W45-6")),
    "generated-basic-form": ("generated", lambda d: d.update(generated="20261107xx")),
    "source-missing-field": ("source-fields", lambda d: d["sources"][0].pop("licence")),
    "source-free-text-release-id": ("source-form", lambda d: d["sources"][1].update(source_release_id="owner:my receipts folder")),
    "source-unknown-projection": ("source-form", lambda d: d["sources"][0].update(
        source_release_id=OFF_ID.replace("off-product-projection-v4", "bogus"))),
    "source-hash-differs-from-id": ("source-hash", lambda d: d["sources"][0].update(artifact_sha256="f" * 64)),
    "source-licence-off-pin": ("source-pins", lambda d: d["sources"][0].update(licence="anything")),
    "source-released-at-not-utc-date": ("source-date", lambda d: d["sources"][0].update(released_at="yesterday")),
    "source-released-at-differs-from-id": ("source-date", lambda d: d["sources"][0].update(released_at="2026-11-06T00:00:00Z")),
    "source-declared-twice": ("source-duplicate", lambda d: d["sources"].append(copy.deepcopy(d["sources"][0]))),
    "duplicate-corpus": ("corpus", lambda d: d["generic_corpora"].append({"source": "cofid", "corpus_sha256": PIN})),
    "items-not-a-list": ("items", lambda d: d.update(items={})),
    "id-not-pfc-form": ("id-form", lambda d: oats(d).update(id="oats")),
    "id-out-of-order": ("id-order", lambda d: d["items"].reverse()),
    "empty-title": ("title", lambda d: oats(d).update(title=" ")),
    "brand-wrong-type": ("title", lambda d: oats(d).update(brand=7)),
    "titles-wrong-type": ("item-types", lambda d: oats(d).update(titles="oats")),
    "category-outside-vocabulary": ("vocabulary", lambda d: oats(d).update(category="ready meal")),
    "product-type-outside-vocabulary": ("vocabulary", lambda d: oats(d).update(product_type="ready_meal")),
    "state-outside-vocabulary": ("vocabulary", lambda d: oats(d).update(state="boiled")),
    "basis-outside-vocabulary": ("vocabulary", lambda d: oats(d).update(basis="per_serving")),
    "category-wrong-type": ("vocabulary", lambda d: oats(d).update(category=["x"])),
    "unknown-nutrient": ("unknown-nutrient", lambda d: oats(d)["label_nutrients"].update(salt=copy.deepcopy(sod(d)))),
    "non-canonical-unit": ("unit", lambda d: kcal(d).update(unit="kJ")),
    "negative-value": ("value", lambda d: kcal(d).update(value=-1)),
    "boolean-value": ("value", lambda d: kcal(d).update(value=True)),
    "unknown-value-field": ("value-keys", lambda d: kcal(d).update(note="x")),
    "missing-source-kind-and-match": ("value-keys", lambda d: [kcal(d).pop("source_kind"), kcal(d).pop("match")]),
    "kind-match-mismatch": ("kind-match", lambda d: kcal(d).update(match="probable")),
    "owner-value-with-record-id": ("record-id", lambda d: kcal(d).update(record_id="off:gtin:00000000000017")),
    "product-value-free-text-record-id": ("record-id", lambda d: sod(d).update(record_id="my oats")),
    "undeclared-source-release": ("undeclared-release", lambda d: kcal(d).update(source_release="owner:sha256:" + "d" * 64)),
    "release-of-wrong-kind": ("release-kind", lambda d: kcal(d).update(source_release=OFF_ID)),
    "unknown-transform": ("transform-unknown", lambda d: sod(d).update(transforms=[{"transform_id": "guess", "version": "v1"}])),
    "transform-not-a-dict": ("transform-shape", lambda d: sod(d).update(transforms=["mass-g-to-mg"])),
    "transform-on-wrong-nutrient": ("transform-scope", lambda d: oats(d)["label_nutrients"].update(
        fat_total={**copy.deepcopy(sod(d)), "unit": "g", "value": 5.0})),
    "transform-on-wrong-source-kind": ("transform-scope", lambda d: sod(d).update(
        transforms=[{"transform_id": "salt_to_sodium_v1", "version": "pasted-label-conversions-v1"}],
        source_value={"value": 0.0125, "unit": "g"})),
    "transform-arithmetic-wrong": ("transform-arithmetic", lambda d: sod(d).update(source_value={"value": 9, "unit": "g"})),
    "transform-small-value-off-by-40-percent": ("transform-arithmetic", lambda d: sod(d).update(
        value=0.014, source_value={"value": 0.00001, "unit": "g"})),
    "transform-without-source-value": ("value-keys", lambda d: sod(d).pop("source_value")),
    "source-value-without-transform": ("value-keys", lambda d: sod(d).pop("transforms")),
    "source-value-extra-key": ("source-value", lambda d: sod(d)["source_value"].update(note="x")),
    "close-match-merged": ("merge-condition", lambda d: ref(d).update(match="close")),
    "merge-with-unknown-state": ("merge-condition", lambda d: oats(d).update(state="frozen")),
    "merge-on-per-100-ml": ("merge-condition", lambda d: oats(d).update(basis="per_100_ml_as_labelled")),
    "concept-only-reference": ("reference", lambda d: ref(d).update(match="concept_only")),
    "unknown-generic-source": ("reference", lambda d: ref(d).update(source="ciqual")),
    "invalid-role": ("reference", lambda d: ref(d).update(role="maybe")),
    "undeclared-corpus": ("reference-corpus", lambda d: ref(d).update(corpus_sha256="e" * 64)),
    "tfda-without-prefix": ("tfda-record-id", lambda d: find(d, "合成豆腐")["generic_reference"].update(record_id="X0001")),
    "cofid-record-id-with-tfda-prefix": ("tfda-record-id", lambda d: ref(d).update(record_id="tfda:example")),
    "transform-wrong-source-unit": ("transform-scope", lambda d: sod(d).update(source_value={"value": 5000, "unit": "mg"})),
    "record-id-non-ascii-digits": ("record-id", lambda d: sod(d).update(record_id="off:gtin:" + "\u0660" * 14)),
    "reference-record-id-null": ("reference", lambda d: ref(d).update(record_id=None)),
    "duplicate-entry": ("id-duplicate", lambda d: d["items"].append(copy.deepcopy(oats(d)))),
}
RAW = {  # name: (expected rule code, bytes)
    "not-json": ("json", lambda: b"not json\n"),
    "utf16": ("encoding", lambda: json.dumps(golden(), ensure_ascii=False).encode("utf-16")),
    "bom": ("bom", lambda: b"\xef\xbb\xbf" + json.dumps(golden(), ensure_ascii=False).encode()),
    "deep-nesting": ("json", lambda: b"[" * 100000 + b"]" * 100000),
    "duplicate-key": ("duplicate-key", lambda: b'{"schema": "x", ' + json.dumps(golden(), ensure_ascii=False).encode()[1:]),
    "nan-token": ("json", lambda: json.dumps(golden(), ensure_ascii=False).replace('"value": 370', '"value": NaN').encode()),
    "huge-integer": ("value", lambda: json.dumps(golden(), ensure_ascii=False).replace('"value": 370', '"value": ' + "9" * 400).encode()),
    "over-size-limit": ("size", lambda: b" " * (E.LIMIT_BYTES + 1)),
    "too-many-items": ("count", lambda: json.dumps({**golden(), "items": [golden()["items"][0]] * (E.LIMIT_ITEMS + 1)},
                                                     ensure_ascii=False).encode()),
}
GENERATED = {"over-size-limit", "too-many-items"}  # large: built at test time, never committed


def write(fixtures: Path):
    fixtures.mkdir(parents=True, exist_ok=True)
    for old_file in fixtures.glob("reject-*.json"):
        old_file.unlink()
    manifest = {"contract": "docs/personal-food-catalogue-import-v1.md", "golden": "golden.json",
                "note": "each reject file must be rejected with the listed rule code among its errors",
                "reject": {}}
    (fixtures / "golden.json").write_text(json.dumps(golden(), indent=1, ensure_ascii=False) + "\n")
    for name, (code, f) in CASES.items():
        d = copy.deepcopy(golden())
        f(d)
        (fixtures / f"reject-{name}.json").write_text(json.dumps(d, ensure_ascii=False) + "\n")
        manifest["reject"][f"reject-{name}.json"] = code
    for name, (code, make) in RAW.items():
        if name in GENERATED:
            continue
        (fixtures / f"reject-{name}.json").write_bytes(make())
        manifest["reject"][f"reject-{name}.json"] = code
    manifest["generated_at_test_time"] = {n: RAW[n][0] for n in sorted(GENERATED)}
    (fixtures / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"wrote golden.json and {len(manifest['reject'])} rejection fixtures to {fixtures}")


def codes(data):
    return {e.split(":", 1)[0] for e in E.check_bytes(data)}


def verify(fixtures: Path):
    manifest = json.loads((fixtures / "manifest.json").read_text())
    golden_bytes = (fixtures / manifest["golden"]).read_bytes()
    errs = E.check_bytes(golden_bytes) + E.check_export_conventions(json.loads(golden_bytes))
    assert errs == [], f"golden rejected: {errs}"
    wrong = []
    for f, code in manifest["reject"].items():
        got = codes((fixtures / f).read_bytes())
        if code not in got:
            wrong.append((f, code, sorted(got)))
    for name, code in manifest.get("generated_at_test_time", {}).items():
        got = codes(RAW[name][1]())
        if code not in got:
            wrong.append((name, code, sorted(got)))
    total = len(manifest["reject"]) + len(manifest.get("generated_at_test_time", {}))
    print(f"golden accepted (release pfc:sha256:{hashlib.sha256(golden_bytes).hexdigest()[:16]}...); "
          f"{total - len(wrong)} of {total} rejection fixtures rejected with their expected rule code")
    if wrong:
        for w in wrong:
            print("  WRONG:", w)
        sys.exit(1)


if __name__ == "__main__":
    if sys.argv[2] == "--write":
        write(Path(sys.argv[3]))
    else:
        verify(Path(sys.argv[2]))
