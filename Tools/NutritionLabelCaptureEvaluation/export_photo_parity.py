#!/usr/bin/env python3
"""Parity vectors for the Swift port of the route C wire mapping (#316, label photo L1b).

Contract: `docs/label-photo-ai-prefill-v1.md` 12.5 test 1 and 17.8 test 16. The Swift
`LabelPhotoWireMapping` must give, for every wire answer, exactly the candidate
`route_c_mapping.map_wire` gives. Three jobs, all deterministic (no clock, no randomness, no
network):

`vectors` writes the committed vectors from committed or synthetic data only:

- one wire answer rebuilt from each committed Taiwan truth record (development and untouched,
  `fixtures/ground-truth-off-taiwan-*-v1.json`), as the model would print it;
- hand-built synthetic answers for every branch of the mapping (decline, unknown and unreadable
  values, undeclared headers, duplicates, parents, the amendments M1 to M3, the serving and
  servings-per-pack patterns, Unicode digits and spaces, and the warning texts);
- a family of mutations of every fifth truth-derived answer (unit-less values, `unknown`, an
  undeclared header, absolute reference values, missing serving lines, a repeated row).

`check` re-derives the committed vectors and fails on any difference.

`private OUT` maps every saved route C answer of the untouched and development Taiwan runs
(kept outside the repository) and writes the vectors to `OUT`, which must also be outside the
repository; the Swift test reads it when `LABEL_PHOTO_PRIVATE_PARITY` names it, and only counts
are ever reported.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import route_c_mapping

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
OUT = REPO / "Packages/FoodLedgerKit/Tests/FoodLabelPhotoReadingTests/Fixtures/label-photo-wire-mapping-v1-vectors.json"
TRUTHS = [HERE / "fixtures/ground-truth-off-taiwan-development-v1.json", HERE / "fixtures/ground-truth-off-taiwan-untouched-v1.json"]
VERSION = "label-photo-wire-mapping-v1-vectors"


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def wire_from_truth(record: dict[str, Any]) -> dict[str, Any]:
    """The wire answer a model reading the label exactly as the truth records would print."""
    rows: list[dict[str, Any]] = []
    index: dict[str, dict[str, Any]] = {}
    nutrient_of = {cell["row_id"]: cell["nutrient"] for cell in record.get("cells") or []}
    for cell in record.get("cells") or []:
        row = index.get(cell["row_id"])
        if row is None:
            parent = cell.get("parent_row_id")
            row = {
                "printed_label": cell["printed_label"],
                "nutrient": cell["nutrient"],
                "parent_nutrient": nutrient_of.get(parent, "none") if parent else "none",
                "values": [],
            }
            index[cell["row_id"]] = row
            rows.append(row)
        row["values"].append({"header_id": cell["header_id"], "printed_text": cell["printed_text"]})
    serving = record.get("serving_size")
    pack = record.get("servings_per_pack")
    return {
        "declined": False,
        "decline_reasons": [],
        "language": record.get("language") if record.get("language") in ("en", "zh-Hant", "mixed") else "unknown",
        "serving_size_text": serving["printed_text"] if isinstance(serving, dict) else "unknown",
        "servings_per_pack_text": pack["printed_text"] if isinstance(pack, dict) else "unknown",
        "headers": [
            {"header_id": h["header_id"], "printed_text": h["printed_text"], "basis": h["basis"]} for h in record.get("headers") or []
        ],
        "rows": rows,
    }


def mutations(case: str, wire: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    out: list[tuple[str, dict[str, Any]]] = []
    if not wire["rows"]:
        return out
    bases = {h["header_id"]: h["basis"] for h in wire["headers"]}
    first = wire["rows"][0]
    if first["values"]:
        unknown = copy.deepcopy(wire)
        unknown["rows"][0]["values"][0]["printed_text"] = "unknown"
        out.append((f"{case}:unknown-value", unknown))
        star = copy.deepcopy(wire)
        star["rows"][0]["values"][0]["printed_text"] = "*"
        out.append((f"{case}:unreadable-value", star))
        bare = copy.deepcopy(wire)
        value = bare["rows"][0]["values"][0]
        value["printed_text"] = "".join(ch for ch in value["printed_text"] if ch.isdigit() or ch in ".,") or "0"
        out.append((f"{case}:bare-number", bare))
        undeclared = copy.deepcopy(wire)
        undeclared["rows"][0]["values"][0]["header_id"] = "header_undeclared"
        out.append((f"{case}:undeclared-header", undeclared))
    for header_id, basis in bases.items():
        if basis == "reference_intake":
            absolute = copy.deepcopy(wire)
            for row in absolute["rows"]:
                for value in row["values"]:
                    if value["header_id"] == header_id:
                        value["printed_text"] = "2000大卡"
                        break
            out.append((f"{case}:absolute-reference", absolute))
            break
    no_serving = copy.deepcopy(wire)
    no_serving["serving_size_text"] = "unknown"
    no_serving["servings_per_pack_text"] = ""
    out.append((f"{case}:no-serving-lines", no_serving))
    duplicate = copy.deepcopy(wire)
    duplicate["rows"].append(copy.deepcopy(duplicate["rows"][0]))
    out.append((f"{case}:repeated-row", duplicate))
    return out


def row(label: str, nutrient: str, values: list[tuple[str, str]], parent: str = "none") -> dict[str, Any]:
    return {
        "printed_label": label,
        "nutrient": nutrient,
        "parent_nutrient": parent,
        "values": [{"header_id": h, "printed_text": t} for h, t in values],
    }


def wire(
    headers: list[tuple[str, str, str]],
    rows: list[dict[str, Any]],
    serving: str = "每一份量30公克",
    pack: str = "本包裝含2份",
    language: str = "zh-Hant",
    declined: bool = False,
    reasons: list[str] | None = None,
) -> dict[str, Any]:
    return {
        "declined": declined,
        "decline_reasons": reasons or [],
        "language": language,
        "serving_size_text": serving,
        "servings_per_pack_text": pack,
        "headers": [{"header_id": i, "printed_text": t, "basis": b} for i, t, b in headers],
        "rows": rows,
    }


TW = [("h1", "每份", "per_serving"), ("h2", "每100公克", "per_100g")]
EN = [("h1", "Per serving", "per_serving"), ("h2", "Per 100g", "per_100g")]


def synthetic() -> list[tuple[str, dict[str, Any]]]:
    base = [
        row("熱量", "energy_kcal", [("h1", "120大卡"), ("h2", "400大卡")]),
        row("蛋白質", "protein", [("h1", "3.5公克"), ("h2", "11.7公克")]),
        row("脂肪", "fat", [("h1", "4公克"), ("h2", "13.3公克")]),
        row("飽和脂肪", "saturates", [("h1", "1.2公克"), ("h2", "4公克")], parent="fat"),
        row("碳水化合物", "carbohydrate", [("h1", "18公克"), ("h2", "60公克")]),
        row("糖", "sugars", [("h1", "<0.5公克"), ("h2", "1.5公克")], parent="carbohydrate"),
        row("鈉", "sodium", [("h1", "85毫克"), ("h2", "283毫克")]),
    ]
    out: list[tuple[str, dict[str, Any]]] = [("synthetic:taiwan-two-columns", wire(TW, base))]
    out.append(("synthetic:declined", wire([], [], declined=True, reasons=["not_a_nutrition_label"])))
    out.append(("synthetic:declined-without-reason", wire([], [], declined=True, language="mixed")))
    out.append(("synthetic:language-unknown", wire(TW, base, language="unknown")))
    out.append(
        (
            "synthetic:english",
            wire(
                EN,
                [
                    row("Energy", "energy_kcal", [("h1", "120kcal"), ("h2", "400kcal")]),
                    row("Fat", "fat", [("h1", "4g"), ("h2", "13.3 g")]),
                    row("Salt", "salt", [("h1", "0.2g"), ("h2", "0.7g")]),
                ],
                serving="Serving size 30g",
                pack="Servings per container: about 8",
                language="en",
            ),
        )
    )
    out.append(
        (
            "synthetic:comparators",
            wire(
                TW,
                [
                    row("糖", "sugars", [("h1", "≤0.5公克"), ("h2", "＜0.5公克")]),
                    row("鈉", "sodium", [("h1", "少於5毫克"), ("h2", "less than 5mg")]),
                    row("脂肪", "fat", [("h1", "<=1g"), ("h2", "< 1 g")]),
                ],
            ),
        )
    )
    out.append(
        (
            "synthetic:unit-echo-and-cases",
            wire(
                TW,
                [
                    row("熱量", "energy_kj", [("h1", "500KJ"), ("h2", "1675 kJ")]),
                    row("鈉", "sodium", [("h1", "0.5 公克(g)"), ("h2", "85mg（mg）")]),
                    row("維生素", "unrecognised", [("h1", "15mcg"), ("h2", "50μg")]),
                    row("飲料", "unrecognised", [("h1", "250mL"), ("h2", "100ml")]),
                ],
            ),
        )
    )
    out.append(
        (
            "synthetic:unicode-digits-and-spaces",
            wire(
                TW,
                [
                    row("熱量", "energy_kcal", [("h1", "１２０大卡"), ("h2", "　400 大卡 ")]),
                    row("脂肪", "fat", [("h1", "4,5公克"), ("h2", "13.3公克 ")]),
                ],
                serving="每一份量３０公克",
                pack="本包裝含 約 2 份",
            ),
        )
    )
    out.append(
        (
            "synthetic:unreadable-values",
            wire(
                TW,
                [
                    row("熱量", "energy_kcal", [("h1", "*"), ("h2", "unknown")]),
                    row("脂肪", "fat", [("h1", "UNKNOWN "), ("h2", "4 公克 5")]),
                    row("鈉", "sodium", [("h1", "85毫克/份"), ("h2", 'it\'s "85"\n\t\\')]),
                ],
            ),
        )
    )
    out.append(
        (
            "synthetic:undeclared-and-duplicate-headers",
            wire(
                TW + [("h1", "每份重複", "per_serving")],
                [row("熱量", "energy_kcal", [("h1", "120大卡"), ("h3", "400大卡")]), row("熱量", "energy_kcal", [("h1", "121大卡")])],
            ),
        )
    )
    out.append(("synthetic:duplicate-cells", wire(TW, [row("熱量", "energy_kcal", [("h1", "120大卡"), ("h1", "120大卡")])])))
    out.append(
        (
            "synthetic:parents",
            wire(
                TW,
                [
                    row("飽和脂肪", "saturates", [("h1", "1公克")], parent="fat"),
                    row("脂肪", "fat", [("h1", "4公克")], parent="fat"),
                    row("糖", "sugars", [("h1", "1公克")], parent=" carbohydrate "),
                    row("其他", "unrecognised", [("h1", "1公克")], parent="unrecognised"),
                    row("碳水化合物", "carbohydrate", [("h1", "18公克")], parent="unknown"),
                    row("糖2", "sugars", [("h1", "2公克")], parent="sugars"),
                ],
            ),
        )
    )
    ri = [("h1", "每份", "per_serving"), ("h3", "每日參考值百分比", "reference_intake")]
    out.append(
        (
            "synthetic:m1-absolute-reference",
            wire(
                ri,
                [
                    row("熱量", "energy_kcal", [("h1", "120大卡"), ("h3", "2000大卡")]),
                    row("脂肪", "fat", [("h1", "4公克"), ("h3", "7%")]),
                    row("鈉", "sodium", [("h1", "85毫克"), ("h3", "*")]),
                ],
            ),
        )
    )
    out.append(
        (
            "synthetic:m2-unit-from-label",
            wire(
                EN,
                [
                    row("Energy kJ", "energy_kj", [("h1", "704"), ("h2", " 2,100 ")]),
                    row("Energy (kcal)", "energy_kcal", [("h1", "168")]),
                    row("Energy kJ/kcal", "energy_kj", [("h1", "704")]),
                    row("Energy KCAL", "energy_kj", [("h1", "704")]),
                    row("Energykcal", "energy_kcal", [("h1", "168")]),
                    row("Fat g", "fat", [("h1", "4")]),
                ],
                language="en",
            ),
        )
    )
    out.append(
        (
            "synthetic:m3-quantity-from-header",
            wire(
                [("h1", "per 30g serving", "per_serving"), ("h2", "Per 100g", "per_100g"), ("h4", "每份", "per_serving")],
                [row("Fat", "fat", [("h1", "4g"), ("h2", "13g"), ("h4", "4g")])],
                serving="unknown",
                pack="unknown",
                language="mixed",
            ),
        )
    )
    out.append(("synthetic:serving-patterns-1", wire(TW, base[:1], serving="2 grilled sausages (90g)", pack="Servings per pack 3 (about)")))
    out.append(("synthetic:serving-patterns-2", wire(TW, base[:1], serving="每份 1.5 毫升", pack="approximately 3.5 servings")))
    out.append(("synthetic:serving-patterns-3", wire(TW, base[:1], serving="12gram 15 克", pack="approx. 4 Servings")))
    out.append(("synthetic:serving-patterns-4", wire(TW, base[:1], serving="per serving", pack="SERVINGS PER PACKAGE about  6")))
    out.append(("synthetic:serving-patterns-5", wire(TW, base[:1], serving="30mLs then 30 mL", pack="每盒2份")))
    out.append(("synthetic:serving-patterns-6", wire(TW, base[:1], serving=" unknown ", pack="2 per pack")))
    out.append(("synthetic:serving-patterns-7", wire(TW, base[:1], serving="", pack="servings per container 12.5")))
    out.append(("synthetic:no-amount-cells", wire(ri, [row("熱量", "energy_kcal", [("h3", "6%")])])))
    return out


def vectors() -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any]]] = []
    for path in TRUTHS:
        data = json.loads(path.read_text(encoding="utf-8"))
        for number, record in enumerate(data["records"]):
            if record.get("excluded"):
                continue
            case = f"truth:{record['case_id']}"
            w = wire_from_truth(record)
            cases.append((case, w))
            # Every fifth record also carries the mutation family (kept small: the vectors are committed).
            if number % 5 == 0:
                cases.extend(mutations(case, w))
    cases.extend(synthetic())
    out = []
    for case, w in cases:
        input_sha = sha(case)
        out.append({"id": case, "input_sha256": input_sha, "wire": w, "candidate": route_c_mapping.map_wire(w, input_sha)})
    return {"version": VERSION, "mapping": "label-photo-wire-mapping-v1", "reference": "route_c_mapping.map_wire", "vectors": out}


def private_vectors(runs: Path) -> dict[str, Any]:
    from inspect_ai.log import read_eval_log

    logs = sorted(runs.glob("untouched-v1/*/untouched/*.eval")) + sorted(runs.glob("route-c-dev/*/*.eval"))
    out = []
    for log_path in logs:
        log = read_eval_log(str(log_path))
        for sample in log.samples or []:
            metadata = sample.metadata or {}
            answer = metadata.get("route_c_answer")
            if not isinstance(answer, str):
                continue
            try:
                w = json.loads(answer)
            except json.JSONDecodeError:
                continue
            input_sha = str(metadata.get("sha256") or "")
            out.append(
                {
                    "id": f"{log_path.parent.name}:{sample.id}",
                    "input_sha256": input_sha,
                    "wire_text": answer,
                    "candidate": route_c_mapping.map_wire(w, input_sha),
                }
            )
    return {"version": VERSION, "mapping": "label-photo-wire-mapping-v1", "reference": "route_c_mapping.map_wire", "vectors": out}


def encode(data: dict[str, Any]) -> str:
    """One vector per line, keys sorted, so a change shows as a line diff."""
    head = {key: value for key, value in data.items() if key != "vectors"}
    lines = [json.dumps(vector, ensure_ascii=False, sort_keys=True, separators=(",", ":")) for vector in data["vectors"]]
    body = ",\n".join(lines)
    return json.dumps(head, ensure_ascii=False, sort_keys=True)[:-1] + ',"vectors":[\n' + body + "\n]}\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="job", required=True)
    sub.add_parser("vectors")
    sub.add_parser("check")
    private = sub.add_parser("private")
    private.add_argument("out", type=Path)
    private.add_argument("--runs", type=Path, default=Path.home() / "WHR-label-eval-private" / "runs")
    args = parser.parse_args()
    if args.job == "vectors":
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(encode(vectors()), encoding="utf-8")
        print(f"wrote {len(vectors()['vectors'])} vectors")
        return 0
    if args.job == "check":
        expected = encode(vectors())
        if OUT.read_text(encoding="utf-8") != expected:
            print("photo wire mapping vectors differ from route_c_mapping; run `export_photo_parity.py vectors`")
            return 1
        print("photo wire mapping vectors match")
        return 0
    if REPO in args.out.resolve().parents:
        print("private vectors must be written outside the repository")
        return 1
    data = private_vectors(args.runs)
    args.out.write_text(encode(data), encoding="utf-8")
    print(f"wrote {len(data['vectors'])} private vectors")
    return 0


if __name__ == "__main__":
    sys.exit(main())
