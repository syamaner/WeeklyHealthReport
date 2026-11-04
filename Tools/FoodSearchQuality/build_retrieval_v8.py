"""Build retrieval-scenarios-v8: the frozen v7 cases plus chocolate type cases, with Ciqual labels.

The Ciqual 2025 admission (#384, docs/ciqual-2025-admission-v1.md) adds a reference-only
source to the production composite (composite-generic-ranking-v11). v8 keeps every v7 case
and every v7 label unchanged, labels each Ciqual record a v7 case retrieves with the name rule
below, and adds three chocolate type cases ("milk chocolate", "white chocolate", "chocolate
spread") labelled across every source. The rules are written from the names, independently of
the policy code. Pass the ungraded v8 replay (WHR_RETRIEVAL_REPORT_V8); without a replay, the new
cases and the Ciqual records are ungraded. The build stops if a Ciqual record appears in a v7
case that is not a chocolate case or a named mention case, so no earlier non-chocolate label
can move silently. The milk and nut cases retrieve Ciqual chocolate products by full word
coverage (the USDA eligibility rules, for example "Milk chocolate, bar" for "milk" and
"Chocolate-coated peanut" for "peanuts"); they are chocolate products that mention the food,
graded 1, and the replay places every one after the UK, US and Taiwan rows.

Fixed labels (FIXED below) are written from the spec, independently of any replay, for the six
Ciqual rows the spec names (31074, 31005, 31085, 31004, 31010, 31032) on their spec queries and
for the CoFID and USDA plain type rows the three new cases need; they are applied whether or not
a replay retrieves the record, and win over the replay-derived name rule. The plain CoFID and
USDA rows of the dark chocolate cases are already fixed by the v7 labels, which v8 keeps. Every
other v8 label is replay-derived: the name rules below applied to the records a replay retrieved.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))
import build_retrieval_v7 as v7  # noqa: E402  (the v7 name rules, reused unchanged)

CIQUAL = "ciqual:"
# (id, family, query, chocolate type)
NEW_CASES = [
    ("r122", "chocolate-type", "milk chocolate", "milk"),
    ("r123", "chocolate-type", "white chocolate", "white"),
    ("r124", "chocolate-spread", "chocolate spread", None),
]
# v7 cases whose query names chocolate; only these may retrieve Ciqual records.
CHOCOLATE_CASES = {case_id for case_id, _, _, _ in v7.NEW_CASES} | {"r037"}
SPREAD_EXTRA = {"with", "hazelnut", "hazelnuts", "nut", "nuts"}
CIQUAL_RELEASE = "ciqual:2025-11-19:sha256:3134f8dc9feb3e17e4d297fdc42f7711eff41af3210facb5d24c35194fa0d847:alim:"
COFID = "cofid:2021:sha256:436e9445ef2adb2a75f3d7edd51302de3adad25385f9795fc94ba58bd030e97d:row:"
USDA = "usda-legacy:2018-04-01:sha256:0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef:fdc:"
DARK_70, DARK_50 = (CIQUAL_RELEASE + "31074", "Dark chocolate, 70% cocoa, bar"), (CIQUAL_RELEASE + "31005", "Dark chocolate, 50% cocoa, bar")
COOKING = (CIQUAL_RELEASE + "31085", "Dark chocolate, more than 40% cocoa, for cooking, bar")
# Spec section 4: 31074 is [70, 70], 31005 is [50, 50], 31085 has no single band (grade 1, as
# every unbanded dark chocolate row in v7). New cases: the plain named chocolate is grade 3.
FIXED = {
    "r106": [(*DARK_70, 3), (*DARK_50, 2), (*COOKING, 1)],
    "r109": [(*DARK_70, 2), (*DARK_50, 2), (*COOKING, 1)],
    "r110": [(*DARK_70, 2), (*DARK_50, 3), (*COOKING, 1)],
    "r119": [(*DARK_70, 3), (*DARK_50, 3), (*COOKING, 1)],
    "r122": [(CIQUAL_RELEASE + "31004", "Milk chocolate, bar", 3), (COFID + "0759:5675bdbab1c892a7", "Chocolate, milk", 3),
             (USDA + "167587", "Candies, milk chocolate", 3)],
    "r123": [(CIQUAL_RELEASE + "31010", "White chocolate, bar", 3), (COFID + "0761:edbf9c1ec6b9bba2", "Chocolate, white", 3),
             (USDA + "167571", "Candies, white chocolate", 3)],
    "r124": [(CIQUAL_RELEASE + "31032", "Chocolate spread with hazelnuts", 3), (COFID + "0756:29004af4b167d639", "Chocolate spread", 3)],
}
# v7 cases outside chocolate where a Ciqual chocolate product mentions the food: grade 1.
MENTION_CASES = {"r049", "r050", "r051", "r052", "r088", "r091", "r093", "r100"}


def ciqual_words(name):
    """Name words with Ciqual's trailing ", bar" form word removed (a plain bar is not a product)."""
    lowered = name.lower()
    words = re.findall(r"[a-z]+", lowered)
    if lowered.rstrip().endswith(", bar") and words and words[-1] == "bar":
        words = words[:-1]
    return set(words)


def ciqual_band(name):
    """A single stated point band ("70% cocoa"); an open-ended or absent statement has none."""
    lowered = name.lower()
    if re.search(r"\b(?:more than|over|at least|minimum)\s+\d+(?:\.\d+)?\s*%|%\s*(?:cocoa|cacao)\s+(?:or more|and more|minimum)", lowered):
        return None
    points = set(re.findall(r"(\d+(?:\.\d+)?)\s*%\s*(?:cocoa|cacao)", lowered))
    return (float(next(iter(points))),) * 2 if len(points) == 1 else None


def grade_ciqual_v7_case(case_id, requested, name):
    """The v7 grade with Ciqual's form word and point bands: 3 plain dark chocolate in the
    asked band, 2 another band, 1 a product, a mention or no single band, 0 unrelated."""
    words = ciqual_words(name)
    if not words & {"chocolate", "cocoa", "cacao"}:
        return 0
    if case_id in v7.MINT:
        return 3 if {"mint", "dark", "chocolate"} <= words else 1
    band = ciqual_band(name)
    if words & set(v7.PRODUCT) or band is None or "dark" not in words:
        return 1
    if requested is None:
        return 3
    return 3 if band[0] <= requested <= band[1] else 2


def grade_type(kind, name):
    """New cases, every source: 3 the plain named chocolate (a leading "Candies," category and a
    trailing ", bar" form word allowed), 1 another chocolate food, 0 unrelated."""
    words = ciqual_words(name.split(" · ")[0]) - {"candies"}
    if "chocolate" not in words:
        return 0
    if kind is None:
        return 3 if {"chocolate", "spread"} <= words and words - {"chocolate", "spread"} <= SPREAD_EXTRA else 1
    return 3 if words == {kind, "chocolate"} else 1


def main():
    """Argument: the ungraded v8 replay (optional)."""
    data = json.loads((ROOT / "retrieval-scenarios-v7.json").read_text())
    replay = json.loads(Path(sys.argv[1]).read_text()) if len(sys.argv) > 1 else []
    names = {}
    for row in replay:
        for record, name in zip(row["records"], row["names"]):
            names.setdefault(row["id"], {})[record] = name
    requested = {case_id: percent for case_id, _, _, percent in v7.NEW_CASES}
    added = 0
    for case in data["cases"]:
        ciqual = {rid: name for rid, name in names.get(case["id"], {}).items() if rid.startswith(CIQUAL)}
        if ciqual and case["id"] not in CHOCOLATE_CASES | MENTION_CASES:
            raise SystemExit(f"{case['id']} retrieves Ciqual records outside the chocolate cases: {sorted(ciqual.values())}")
        for rid, name in sorted(ciqual.items()):
            case["grades"][rid] = 1 if case["id"] in MENTION_CASES else grade_ciqual_v7_case(case["id"], requested.get(case["id"]), name)
            case.setdefault("labelNames", {})[rid] = name
            added += 1
        if ciqual:
            case["grades"] = dict(sorted(case["grades"].items()))
            case["labelNames"] = dict(sorted(case["labelNames"].items()))
            # Ciqual records that state another band are incorrect variants only where a row
            # states the asked band (the v7 rule); v7's own incorrect records are kept as they are.
            has_band = requested.get(case["id"]) is not None and any(value == 3 for value in case["grades"].values())
            case["incorrectVariantRecords"] = sorted(set(case["incorrectVariantRecords"])
                | {rid for rid in ciqual if has_band and case["grades"][rid] == 2})
    for case_id, family, query, kind in NEW_CASES:
        found = names.get(case_id, {})
        data["cases"].append({
            "family": family,
            "grades": {rid: grade_type(kind, name) for rid, name in sorted(found.items())},
            "id": case_id,
            "incorrectVariantRecords": [],
            "labelNames": dict(sorted(found.items())),
            "market": None,
            "preparation": None,
            "query": query,
        })
    disagreements = []
    for case in data["cases"]:
        for rid, name, grade in FIXED.get(case["id"], []):
            if case["grades"].get(rid, grade) != grade:
                disagreements.append(f"{case['id']} {name}: rule {case['grades'][rid]}, fixed {grade}")
            case["grades"][rid] = grade
            case.setdefault("labelNames", {})[rid] = name
        if case["id"] in FIXED:
            case["grades"] = dict(sorted(case["grades"].items()))
            case["labelNames"] = dict(sorted(case["labelNames"].items()))
            has_band = requested.get(case["id"]) is not None and any(value == 3 for value in case["grades"].values())
            case["incorrectVariantRecords"] = sorted(set(case["incorrectVariantRecords"])
                | {rid for rid, _, grade in FIXED[case["id"]] if has_band and grade == 2})
    for line in disagreements:
        print("fixed label overrides the name rule:", line)
    data.update(version="retrieval-scenarios-v8",
                focus="v7 cases plus Ciqual 2025 chocolate rows and chocolate type cases (composite-generic-ranking-v11)",
                labelRules=("build_retrieval_v4.py to build_retrieval_v8.py name rules; same-author development labels. v8: fixed "
                            "spec labels (build_retrieval_v8.py FIXED) for Ciqual 31074, 31005, 31085, 31004, 31010 and 31032 on their "
                            "spec queries and the CoFID and USDA plain type rows of r122 to r124; all other v8 labels are derived from "
                            "the v8 replay by the name rules"))
    data["corpusSHA256"] = dict(data.get("corpusSHA256", {}), ciqual="2a298bd5e9c43d2e32ed3164c2a53de0dc21f80c9812285faf137dde196f333f")
    out = ROOT / "retrieval-scenarios-v8.json"
    out.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    print(f"Wrote {len(data['cases'])} cases to {out.name}; labelled {added} Ciqual records in v7 cases")


if __name__ == "__main__":
    main()
