#!/usr/bin/env python3
"""Intake for new catalogue items from any input type.

Every input (PDF, CSV, free text, image, export, URL, typed) is first turned into
an intake file, work/intake/<source_id>.json:

{"source": {"id": "notes-2026-11-07", "kind": "free_text|pdf|csv|image|export|url|typed",
            "captured": "YYYY-MM-DD", "description": "what it was, no personal data"},
 "items": [{"title": "...", "brand": null, "aliases": [], "kind": "food|supplement",
            "state": null, "region": null, "note": null,
            "label": null | {"origin": "owner_typed|photo_confirmed|photo_unconfirmed|page_confirmed|page_unconfirmed",
                             "basis": "per_100_g|per_100_ml|per_serving", "serving": null,
                             "values": {"energy_consumed": 120, "protein": 21.7, "sodium": 481, ...}}}]}

Label values use canonical keys and units (kcal, g, mg, mcg). Amounts eaten,
prices, names, addresses and anything personal are never written to an intake file.

Commands:
  add <file>     validate, copy into work/intake/, register items, report new / known
  pending        write work/intake-batch.txt with registered food items lacking a mapping
  status         counts per source and mapping state
Usage: python3 -I intake.py <workspace> <command> [file]
"""
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check, check_output  # noqa: E402

TRANSFORMS = {("salt_to_sodium_v1", "pasted-label-conversions-v1"): ("sodium", "g"),
              ("kj_to_kcal_v1", "pasted-label-conversions-v1"): ("energy_consumed", "kJ")}
# owner labels may carry only the app's two calculated pairs (PastedLabelDomain.calculatedTransforms);
# mass-g-to-mg belongs to Open Food Facts values and is refused here
KINDS = {"free_text", "pdf", "csv", "image", "export", "url", "typed"}
LABEL_ORIGINS = {"owner_typed", "photo_confirmed", "photo_unconfirmed", "page_unconfirmed", "page_confirmed"}
CANON = {"energy_consumed": "kcal", "protein": "g", "fat_total": "g", "fat_saturated": "g",
         "fat_monounsaturated": "g", "fat_polyunsaturated": "g", "carbohydrates": "g", "sugar": "g",
         "fiber": "g", "sodium": "mg", "cholesterol": "mg", "calcium": "mg", "iron": "mg",
         "magnesium": "mg", "potassium": "mg", "zinc": "mg", "phosphorus": "mg", "vitamin_c": "mg",
         "vitamin_d": "mcg", "vitamin_a": "mcg", "vitamin_b12": "mcg", "folate_b9": "mcg",
         "vitamin_e": "mg", "vitamin_k": "mcg", "thiamin_b1": "mg", "riboflavin_b2": "mg",
         "niacin_b3": "mg", "vitamin_b6": "mg", "iodine": "mcg", "selenium": "mcg", "copper": "mg",
         "manganese": "mg", "caffeine": "mg"}
# A cheap last line of defence: intake files must never carry personal data.
DENY = [re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+"), re.compile(r"\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b"),
        re.compile(r"\d{7,}"), re.compile(r"\b(AMEX|VISA|MASTERCARD|card ending|order number|invoice)\b", re.I),
        re.compile(r"\b(Mr|Mrs|Miss|Ms|Mx|Dr)\.?\s+[A-Z][a-z]+"),
        re.compile(r"\b\d+\s+(\w+\s+){1,3}(Road|Street|Lane|Avenue|Close|Gardens|Drive|Way)\b", re.I),
        re.compile(r"£\s?\d"), re.compile(r"(\+44|\b0)\s?\d{3,4}\s?\d{3}\s?\d{3,4}\b")]
BRAND_HONORIFICS = {"Mr Organic", "Mr Filberts", "Mr Kipling"}  # same exact exceptions as extract_items


def norm(s):
    return re.sub(r"\s+", " ", re.sub(r"[^\w&% ]", " ", s.casefold())).strip()


def validate(doc):
    errs = []
    src = doc.get("source") or {}
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{2,60}", src.get("id", "")):
        errs.append("source.id must be lower-case letters, digits and hyphens")
    try:
        import datetime
        ok_date = isinstance(src.get("captured"), str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", src["captured"]) \
            is not None and bool(datetime.date.fromisoformat(src["captured"]))
    except ValueError:
        ok_date = False
    if not ok_date:
        errs.append("source.captured must be a real YYYY-MM-DD date")
    if src.get("kind") not in KINDS:
        errs.append(f"source.kind must be one of {sorted(KINDS)}")
    for i, it in enumerate(doc.get("items") or []):
        if not (it.get("title") or "").strip():
            errs.append(f"item {i}: title missing")
        if it.get("kind", "food") not in ("food", "supplement"):
            errs.append(f"item {i}: kind must be food or supplement")
        lab = it.get("label")
        if lab:
            if it.get("kind", "food") == "food" and lab.get("basis") not in ("per_100_g", "per_100_ml"):
                errs.append(f"item {i}: food label basis must be per_100_g or per_100_ml")
            if lab.get("origin") not in LABEL_ORIGINS:
                errs.append(f"item {i}: label.origin must be one of {sorted(LABEL_ORIGINS)}")
            for k, t in (lab.get("transforms") or {}).items():
                rule = TRANSFORMS.get((t.get("transform_id"), t.get("version"))) if isinstance(t, dict) else None
                sv = t.get("source_value") if isinstance(t, dict) else None
                ok = rule is not None and rule[0] == k and isinstance(sv, dict) and sv.get("unit") == rule[1] \
                    and k in (lab.get("values") or {})
                if not ok:
                    errs.append(f"item {i}: transform for {k} needs a known transform_id/version and source_value")
            for k, v in (lab.get("values") or {}).items():
                if k not in CANON:
                    errs.append(f"item {i}: unknown nutrient key {k}")
                elif isinstance(v, bool) or not isinstance(v, (int, float)) or v < 0 or v != v or v in (float("inf"),):
                    errs.append(f"item {i}: {k} must be a non-negative number")
    text = json.dumps(doc, ensure_ascii=False)
    for b in BRAND_HONORIFICS:
        text = text.replace(b, "")
    for rx in DENY:
        if rx.search(text):
            errs.append(f"personal-data pattern found ({rx.pattern[:30]}...): remove it before intake")
    if not doc.get("items"):
        errs.append("no items")
    return errs


def load_registry(work):
    p = work / "intake-registry.json"
    return json.load(open(p)) if p.exists() else {"next_n": 9000, "items": {}}


def save_registry(work, reg):
    check_output(work / "intake-registry.json").write_text(json.dumps(reg, indent=1, ensure_ascii=False))


def catalogue_index(ws):
    p = ws / "out" / "personal-food-catalogue.json"
    if not p.exists():
        return [], set()
    items = [i for i in json.load(open(p))["items"] if i.get("origin") == "receipts"]
    names = set()
    for i in items:
        names |= {norm(t) for t in i.get("titles", [])} | {norm(a) for a in i.get("aliases", [])}
        for k in ("concept", "variety"):
            if i.get(k):
                names.add(norm(i[k]))
    return items, names


def add(ws, path):
    work = ws / "work"
    doc = json.load(open(path))
    errs = validate(doc)
    if errs:
        print("REJECTED, nothing changed:")
        for e in errs:
            print("  -", e)
        sys.exit(2)
    check_output(work / "intake")  # work/ or intake/ may be a link: check where it really resolves
    (work / "intake").mkdir(exist_ok=True)
    dest = check_output(work / "intake" / f"{doc['source']['id']}.json")
    shutil.copyfile(path, dest)
    dest.chmod(0o600)
    reg = load_registry(work)
    items, names = catalogue_index(ws)
    titles = {norm(i["title"]): i["title"] for i in items}  # receipt titles carry their brand
    new = known_product = alias_only = 0
    for it in doc["items"]:
        key = norm(f"{it.get('brand') or ''} {it['title']}")
        if key in reg["items"]:
            reg["items"][key]["sources"] = sorted(set(reg["items"][key]["sources"]) | {doc["source"]["id"]})
            continue
        # match on brand and title together, so another brand's label never lands on this entry
        t = norm(f"{it.get('brand') or ''} {it['title']}") if it.get("brand") and \
            not norm(it["title"]).startswith(norm(it.get("brand") or "")) else norm(it["title"])
        if t in titles and not it.get("label"):
            known_product += 1
            print(f"  already in catalogue: {it['title']}")
            continue
        if t in titles:  # a label for a receipt food: attach it to that entry, never a second entry
            reg["items"][key] = {"n": reg["next_n"], "title": it["title"], "sources": [doc["source"]["id"]],
                                 "attach_to": titles[t]}
            reg["next_n"] += 1
            print(f"  LABEL for existing entry: {it['title']}")
            continue
        if not it.get("brand") and not it.get("label") and (t in names or any(norm(a) in names for a in it.get("aliases", []))):
            alias_only += 1
            print(f"  covered by an existing concept or alias: {it['title']}")
            continue
        reg["items"][key] = {"n": reg["next_n"], "title": it["title"], "sources": [doc["source"]["id"]]}
        reg["next_n"] += 1
        new += 1
        print(f"  NEW #{reg['items'][key]['n']}: {it['title']}")
    save_registry(work, reg)
    print(f"added source {doc['source']['id']}: {new} new, {known_product} already products, {alias_only} covered by concept")


def mapped(work):
    out = {}
    for p in sorted(work.glob("intake-mapping-*.json")):
        for m in json.load(open(p)):
            out[m["n"]] = m
    return out


def all_intake_items(work):
    reg = load_registry(work)
    by_key = {}
    rank = lambda x: (not str((x.get("label") or {}).get("origin", "")).endswith("unconfirmed"),
                      bool(x.get("label")), x.get("captured") or "")
    for p in sorted((work / "intake").glob("*.json")):
        doc = json.load(open(p))
        for it in doc["items"]:
            key = norm(f"{it.get('brand') or ''} {it['title']}")
            if key in reg["items"]:
                cand = {**it, "n": reg["items"][key]["n"], "source_id": doc["source"]["id"],
                        "source_kind": doc["source"]["kind"], "captured": doc["source"].get("captured"),
                        "attach_to": reg["items"][key].get("attach_to")}
                if key not in by_key or rank(cand) >= rank(by_key[key]):
                    by_key[key] = cand  # a confirmed label beats an unconfirmed one; then the newest
    return list(by_key.values())


def pending(ws):
    work = ws / "work"
    m = mapped(work)
    todo = [i for i in all_intake_items(work) if i.get("kind", "food") == "food"
            and i["n"] not in m and i.get("region") != "restaurant"]
    with open(check_output(work / "intake-batch.txt"), "w") as fh:
        for i in todo:
            shown = i["title"] if not i.get("brand") or i["title"].casefold().startswith(i["brand"].casefold()) \
                else f"{i['brand']} {i['title']}"
            fh.write(f"{i['n']}\t{shown}\t{i.get('state') or ''}\t{i.get('region') or 'UK'}\t{i.get('note') or ''}\n")
    print(f"{len(todo)} items need a mapping; wrote work/intake-batch.txt")


def status(ws):
    work = ws / "work"
    items, m = all_intake_items(work), mapped(work)
    from collections import Counter
    print("by source:", dict(Counter(i["source_id"] for i in items)))
    print("mapped:", sum(1 for i in items if i["n"] in m), "of", len(items))


if __name__ == "__main__":
    ws, cmd = check(Path(sys.argv[1])), sys.argv[2]
    {"add": lambda: add(ws, Path(sys.argv[3])), "pending": lambda: pending(ws), "status": lambda: status(ws)}[cmd]()
