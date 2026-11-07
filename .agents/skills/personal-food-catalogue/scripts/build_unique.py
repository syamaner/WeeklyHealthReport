#!/usr/bin/env python3
"""Group sanitised purchase lines into unique products.

Input is ONLY the sanitised purchase-lines.jsonl from extract_items.py.
Usage: python3 -I build_unique.py <work/purchase-lines.jsonl> <out_dir>
"""
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check_output  # noqa: E402

PACK = re.compile(
    r"(?P<multi>(?P<n>\d+)\s*[xX×]\s*)?(?P<amt>\d+(?:\.\d+)?)\s*(?P<unit>kg|g|ml|cl|l|litres?|L)\b\*?\s*$", re.I)
COUNT = re.compile(r"(?P<n>\d+)\s+(per pack|pack|sheets|tablets|capsules|caps|teabags|tea bags|pieces)\s*\*?\s*$", re.I)

NON_FOOD = re.compile(
    r"\b(fabric|softener|conditioner|shampoo|cleaner|wipes|tissues?|toilet|kitchen roll|bin bags?|washing|detergent|"
    r"dishwasher|laundry|soap|hand wash|toothpaste|toothbrush|floss|mouthwash|foil|cling film|baking paper|sponge|"
    r"bleach|deodorant|batter(y|ies)|candle|bouquet|flowers|plant pot|compost|nappies|razor|cotton buds|"
    r"bath|shower gel|body wash|moisturiser|sun cream|plasters|washing-up|washing up|limescale|descaler|"
    r"surface spray|antibacterial|freezer bags|sandwich bags|food bags|lightbulb|scoop|handbook|kitchen towel|soda crystals|shave|shaving|shower cream|hand cream|lip balm|"
    r"tampons?|sanitary|panty|wet wipes|air freshener|matches|lighter|charcoal|firelighters?)\b",
    re.I)
SUPPLEMENT = re.compile(r"\b(vitamin|multivitamin|tablets|capsules|caps|omega-3|zinc|magnesium|TUDCA|probiotic|"
                        r"collagen|whey|psyllium|creatine|electrolyte)\b", re.I)


def clean(name: str) -> str:
    name = re.sub(r"\s+", " ", name).strip().rstrip("*").strip()
    return re.sub(r"\b(\d+(?:\.\d+)?\s*(?:kg|g|ml|cl|l))\s+\1$", r"\1", name, flags=re.I)  # "1L 1L"


def pack_of(name: str):
    m = PACK.search(name)
    if m:
        unit = m["unit"].lower()
        unit = {"litre": "l", "litres": "l"}.get(unit, unit)
        amt = float(m["amt"])
        grams = {"kg": 1000, "g": 1}.get(unit)
        ml = {"l": 1000, "cl": 10, "ml": 1}.get(unit)
        total = amt * (int(m["n"]) if m["n"] else 1)
        return {"pack_text": m.group(0).rstrip("*").strip(),
                "pack_g": round(total * grams, 1) if grams else None,
                "pack_ml": round(total * ml, 1) if ml else None,
                "pack_count": None}, name[:m.start()].strip()
    m = COUNT.search(name)
    if m:
        return {"pack_text": m.group(0).rstrip("*").strip(), "pack_g": None, "pack_ml": None,
                "pack_count": int(m["n"])}, name[:m.start()].strip()
    return {"pack_text": None, "pack_g": None, "pack_ml": None, "pack_count": None}, name


def key_of(s: str) -> str:
    s = s.casefold().replace("’", "'")
    s = re.sub(r"[^\w&%+' ]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def main(src: Path, out: Path):
    lines = [json.loads(l) for l in open(src)]
    products = defaultdict(lambda: {"lines": 0, "units": 0, "months": set(), "retailers": set(),
                                    "layouts": set(), "vat_marker": False, "hints": set(), "titles": set()})
    for r in lines:
        title = clean(r["name"])
        pack, base = pack_of(title)
        k = key_of(title)
        p = products[k]
        p["titles"].add(title)
        p["base"] = base
        p.update({kk: vv for kk, vv in pack.items()})
        p["lines"] += 1
        p["units"] += r.get("qty") or r.get("delivered") or 0
        if r.get("month"):
            p["months"].add(r["month"])
        p["retailers"].add(r["retailer"])
        p["layouts"].add(r["layout"])
        p["vat_marker"] |= r["name"].rstrip().endswith("*")
        if r.get("pack_hint"):
            p["hints"].add(r["pack_hint"])
        if r.get("reference_only"):
            p["reference_only"] = True

    rows, families = [], defaultdict(list)
    for k, p in products.items():
        title = sorted(p["titles"], key=len)[-1]
        if NON_FOOD.search(title):
            kind = "non_food"
        elif SUPPLEMENT.search(title) or p["retailers"] & {"Healf", "Boots"}:
            kind = "supplement"
        else:
            kind = "food"
        months = sorted(p["months"])
        row = {"product_key": k, "title": title, "kind_proposal": kind,
               "base_name": p["base"], "pack_text": p["pack_text"], "pack_g": p["pack_g"],
               "pack_ml": p["pack_ml"], "pack_count": p["pack_count"],
               "typical_weight": "; ".join(sorted(p["hints"])) or None,
               "purchase_lines": p["lines"], "units": p["units"],
               "first_month": months[0] if months else None, "last_month": months[-1] if months else None,
               "retailers": "; ".join(sorted(p["retailers"])), "vat_marker": p["vat_marker"]}
        rows.append(row)
        families[key_of(p["base"])].append(k)
    rows.sort(key=lambda r: (r["kind_proposal"], -r["purchase_lines"], r["title"]))
    out.mkdir(parents=True, exist_ok=True)
    fields = ["product_key", "title", "kind_proposal", "base_name", "pack_text", "pack_g", "pack_ml", "pack_count",
              "typical_weight", "purchase_lines", "units", "first_month", "last_month", "retailers", "vat_marker"]
    if not rows:
        print("no products found in the purchase lines; nothing written")
        return
    for kind in ("food", "supplement", "non_food"):
        with open(out / f"unique-{kind}.csv", "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=fields)
            w.writeheader()
            w.writerows(r for r in rows if r["kind_proposal"] == kind)
    variants = {f: ks for f, ks in families.items() if len(ks) > 1}
    (out / "pack-variant-families.json").write_text(json.dumps(variants, indent=1, ensure_ascii=False))
    from collections import Counter
    print("unique products:", len(rows), dict(Counter(r["kind_proposal"] for r in rows)))
    print("families with several pack sizes:", len(variants))
    print("food with VAT marker (review: confectionery, drinks, or misfiled non-food):",
          sum(1 for r in rows if r["kind_proposal"] == "food" and r["vat_marker"]))


if __name__ == "__main__":
    main(Path(sys.argv[1]), check_output(sys.argv[2]))
