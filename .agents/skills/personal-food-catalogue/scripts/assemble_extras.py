#!/usr/bin/env python3
"""Append the owner's note-derived foods to the assembled catalogue.

Tier order per nutrient (same rules as assemble.py): owner-typed label > own-brand
Open Food Facts label > generic (CoFID / USDA / TFDA, only same_food_same_state or
close) > other-brand label (single-ingredient only). Restaurant items are name-only.

Usage: python3 -I assemble_extras.py <work_dir> <catalogue_json> <resources_dir>
"""
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check_output  # noqa: E402
from private_config import require  # noqa: E402
import assemble as A  # noqa: E402
import intake as I  # noqa: E402

LABEL_SOURCE = {"owner_typed": "label:owner-typed", "photo_confirmed": "label:owner-photo",
                "photo_unconfirmed": "label:photo-unconfirmed", "page_confirmed": "label:owner-page",
                "page_unconfirmed": "label:page-unconfirmed"}


def attach_label(target, e) -> bool:
    """Add intake item e's label to an existing catalogue entry. Pure apart from mutating target.

    Returns False when nothing is attached. The intake note (for a page, its URL, date read and the
    state it describes) is kept with the label as its evidence, keyed by the label source.
    """
    lab = e.get("label") or {}
    if target is None or lab.get("basis") not in ("per_100_g", "per_100_ml"):
        return False
    lab_basis = "per_100_ml_as_labelled" if lab["basis"] == "per_100_ml" else "per_100_g"
    confirmed = not lab["origin"].endswith("unconfirmed")
    if lab_basis != target.get("basis", "per_100_g"):
        if not confirmed:
            return False  # an unconfirmed label never changes an entry's basis
        # the owner's confirmed label wins: its basis replaces the entry's, and values on the
        # old basis (product label, merged generic values) are dropped from the entry
        target["basis"] = lab_basis
        target["label_tiers"] = {"off": {}}
        target["nutrients"] = {}
        target["label_evidence"] = {}  # evidence for the dropped values goes with them
    src = f"{LABEL_SOURCE[lab['origin']]}:{e['source_id']}"
    owner = {}
    for k, v in lab["values"].items():
        owner[k] = {"value": v, "unit": I.CANON[k], "source": src}
        t = (lab.get("transforms") or {}).get(k)
        if t:
            owner[k]["transforms"] = [{"transform_id": t["transform_id"], "version": t["version"]}]
            owner[k]["source_value"] = t["source_value"]
    target.setdefault("label_tiers", {})["owner"] = owner
    target.setdefault("label_evidence", {})[src] = {"origin": lab["origin"], "note": e.get("note")}
    target["captured"] = e.get("captured")
    if confirmed:
        target.setdefault("nutrients", {}).update(owner)  # a printed label the owner confirmed comes first
    return True


def main(work: Path, cat_path: Path, res: Path):
    A.PRODUCT_DIR = work / "off-products-v3"
    cat = json.load(open(cat_path))
    cat["items"] = [i for i in cat["items"] if i.get("origin") == "receipts"]  # idempotent rerun
    cofid = {}
    import re
    for r in json.load(open(res / "cofid-2021-generic-search-v1.json"))["records"]:
        m = re.search(r":row:(\d+):", r["record_id"])
        if m:
            cofid[m[1]] = r
    usda = json.load(open(res / "usda-generic-v1.json"))["records"]
    tfda = json.load(open(res / "tfda-generic-v1.json"))["records"]
    maps = I.mapped(work)
    added = 0
    by_title = {I.norm(i["title"]): i for i in cat["items"]}
    attached = 0
    for e in I.all_intake_items(work):
        if e.get("kind", "food") != "food":
            continue  # supplements are per serving; not in catalogue v1
        if e.get("attach_to"):
            # an owner label for a receipt food: add it to that entry, never a second entry
            if attach_label(by_title.get(I.norm(e["attach_to"])), e):
                attached += 1
            continue
        m = maps.get(e["n"], {})
        g = m.get("generic") or {}
        rec, gn = None, {}
        key = str(g.get("key", ""))
        if g.get("source") == "cofid" and key in cofid:
            rec = cofid[key]
            gn = A.cofid_nutrients(rec)
        elif g.get("source") == "usda" and key.isdigit() and int(key) < len(usda):
            rec = usda[int(key)]
            gn = A.usda_nutrients(rec)
            ok, why = A.usda_state_ok(m, rec, e["title"])
            if ok:
                why = A.fat_level_conflict(e["title"], gn)
                ok = why is None
            if not ok:
                g = {**g, "match": "concept_only", "note": f"downgraded: {why}"}
        elif g.get("source") == "tfda" and key.isdigit() and int(key) < len(tfda):
            rec = tfda[int(key)]
            gn = A.usda_nutrients(rec, prefix="tfda")  # same canonical-unit rule
        if rec is not None and rec["name"] != g.get("name"):  # a missing name is a mismatch too
            # the model's key and name disagree: never trust either for nutrition
            g = {**g, "match": "concept_only", "note": "downgraded: record name differs from the proposed name"}
        if rec is not None and g.get("source") in ("cofid", "tfda"):
            # model-proposed mappings get the same mechanical checks as every other source
            ok, why = A.usda_state_ok(m, rec, e["title"])
            if ok:
                why = A.fat_level_conflict(e["title"], gn)
                ok = why is None
            if not ok and g.get("match") in ("same_food_same_state", "close"):
                g = {**g, "match": "concept_only", "note": f"downgraded: {why}"}
        if g.get("match") not in ("same_food_same_state", "close"):
            gn = {}
        owner = {}
        lab = e.get("label")
        basis = "per_100_g"
        if lab and lab.get("basis") in ("per_100_g", "per_100_ml"):
            src = f"{LABEL_SOURCE[lab['origin']]}:{e['source_id']}"
            owner = {}
            for k, v in lab["values"].items():
                owner[k] = {"value": v, "unit": I.CANON[k], "source": src}
                t = (lab.get("transforms") or {}).get(k)
                if t:  # e.g. sodium from printed salt: keep the transform ID and the printed value
                    owner[k]["transforms"] = [{"transform_id": t["transform_id"], "version": t["version"]}]
                    owner[k]["source_value"] = t["source_value"]
            confirmed = not lab["origin"].endswith("unconfirmed")
            if lab["basis"] == "per_100_ml" and confirmed:
                basis = "per_100_ml_as_labelled"
        label = other = None
        off_lab = off_other = {}
        off_basis = None
        hits = [h for hf in sorted((work / "off-cache2").glob(f"{e['n']}-*.json")) for h in json.load(open(hf))["hits"]]
        best = best_other = None
        brand = (e.get("brand") or "").split(" (")[0]
        title = f"{brand} {e['title']}" if brand and not e["title"].casefold().startswith(brand.casefold()) else e["title"]
        for hit in hits:
            if not isinstance((hit.get("nutriments") or {}).get("energy-kcal_100g"), (int, float)):
                continue
            sc, b = A.score_off(title, title.split()[0].casefold(), hit)
            b = b and bool(brand)  # an unbranded note item has no own-brand label
            if b and sc >= 0.6 and (best is None or sc > best[0]):
                best = (sc, hit)
            if not b and sc >= 0.8 and A.name_coverage(title, hit) >= 0.75 and (best_other is None or sc > best_other[0]):
                best_other = (sc, hit)
        if best:
            label = {"status": "probable", "code": best[1].get("code"), "product_name": best[1].get("product_name"),
                     "brands": best[1].get("brands"), "score": best[0]}
            off_basis, off_lab = A.off_label(label["code"])
        single = m.get("product_type") in ("packaged_single_ingredient", "fresh_whole")
        if not best and best_other and single:
            other = {"status": "other_brand_used", "code": best_other[1].get("code"),
                     "product_name": best_other[1].get("product_name"), "brands": best_other[1].get("brands"),
                     "score": best_other[0]}
            off_basis, ob = A.off_label(other["code"])
            off_other = {k: {**v, "source": v["source"].replace("label:off:", "label-other-brand:off:")}
                         for k, v in ob.items()}
        # basis from evidence only: the owner's label, else the product record; never the category
        owner_confirmed = bool(owner) and not lab["origin"].endswith("unconfirmed")
        if owner_confirmed:
            if off_basis and off_basis != basis:
                off_lab = off_other = {}  # a label on another basis never mixes with the owner's
        elif off_lab and off_basis:
            basis = off_basis  # only the item's own product record sets the basis
        if off_other and off_basis != basis:
            off_other = {}
        if basis == "per_100_ml_as_labelled":
            gn = {}  # one basis per entry: no per-100-g generic values
        fresh = m.get("product_type") == "fresh_whole"
        # same order as assemble.py; a printed label the owner typed or confirmed always comes first
        order = (owner, gn, off_lab, off_other) if fresh else (owner, off_lab, gn, off_other)
        nutrients = {}
        for tier in order:
            for k, v in tier.items():
                held = nutrients.get(k)
                if held is None or (held.get("value") is None and v.get("value") is not None):
                    nutrients[k] = v
        used = sorted({v["source"].split(":")[0] + ":" + v["source"].split(":")[1] for v in nutrients.values()})
        cat["items"].append({
            "id": "pfc:" + hashlib.sha256(("intake:" + I.norm(f"{e.get('brand') or ''} {e['title']}")).encode()).hexdigest()[:12],
            "n": e["n"],
            "origin": f"intake:{e['source_kind']}", "intake_source": e["source_id"], "title": e["title"], "titles": [e["title"]], "kind": "food",
            "brand": e.get("brand"), "region": e.get("region"),
            "concept": m.get("concept"), "variety": m.get("variety"),
            "aliases": sorted(set(e.get("aliases", [])) | set(m.get("aliases", []))),
            "fallback_chain": m.get("fallback_chain", []), "category": m.get("category"),
            "product_type": m.get("product_type"), "state": m.get("state") or e.get("state"),
            "packs": [], "retailers": [], "purchase_lines": 0, "basis": basis,
            "label_candidate": label, "other_brand_label": other,
            "generic_match": {"source": g.get("source"), "record_id": (rec or {}).get("record_id") or (rec or {}).get("id"),
                              "name": g.get("name"), "match": g.get("match"), "note": g.get("note")},
            "nutrient_sources": used, "nutrients": nutrients, "note": e.get("note"), "review": "unreviewed",
            "label_tiers": {"owner": owner, "off": off_lab}, "captured": e.get("captured"),
        })
        added += 1
    cat["sources"]["tfda"] = {"title": "Taiwan FDA Food Nutrition Database (reviewed slice bundled in the app)",
                              "licence": "Open Government Data License 1.0"}
    cat["sources"]["owner_labels"] = {"title": "Label values typed by the owner, or read from the owner's photo "
                                               "(photo-unconfirmed until the owner checks them)"}
    cat.setdefault("off_releases", {}).update(A.OFF_RELEASES)
    json.dump(cat, open(cat_path, "w"), indent=1, ensure_ascii=False)
    ex = [i for i in cat["items"] if str(i.get("origin", "")).startswith("intake:")]
    print(f"labels attached to receipt entries: {attached}")
    print(f"extras added: {added}; with nutrients: {sum(1 for i in ex if i['nutrient_sources'])}; "
          f"name-only: {[i['title'] for i in ex if not i['nutrient_sources']]}")


if __name__ == "__main__":
    require()
    main(check_output(sys.argv[1]), check_output(sys.argv[2]), Path(sys.argv[3]))
