#!/usr/bin/env python3
"""Second Open Food Facts pass for families that still have no nutrients.

Queries per family, most specific first, stopping at the first that returns hits:
  b: title with pack size and marketing words removed (brand kept)
  c: the same without the leading brand words
  d: the mapped variety, else concept (generic)
All calls use http_client.Client (published-limit pacing, backoff, Retry-After,
circuit breaker). Only product names are sent.

Usage: python3 -I fetch_off_pass2.py <work_dir> <catalogue_json>
"""
import json
import re
import sys
import time
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check_output  # noqa: E402
from private_config import CONFIG, require  # noqa: E402
from http_client import CircuitOpen, Client, load_food_words, owner_approval, safe_query  # noqa: E402

FIELDS = "code,product_name,brands,quantity,countries_tags,nutriments,serving_size,categories_tags"
PACK = re.compile(r"\s*(\d+\s*[xX×]\s*)?\d+(\.\d+)?\s*(kg|g|ml|cl|l)\b.*$|\s*\d+\s+per pack.*$", re.I)
MARKETING = re.compile(r"\b(organic|fairtrade|british|collection|our best ever|perfectly ripe|washed & ready to eat|"
                       r"washed and ready to eat|ready to eat|multipack|sharing bag|family pack|rainforest alliance|"
                       r"&\s*fairtrade)\b", re.I)
# Shop and brand prefixes to strip for query c (private config), longest first.
BRAND_PREFIX = re.compile(r"^(" + "|".join(re.escape(p) for p in sorted(CONFIG["brand_prefixes"], key=len, reverse=True))
                          + r")\s+", re.I) if CONFIG["brand_prefixes"] else re.compile(r"(?!)")


def clean(s):
    return re.sub(r"\s+", " ", MARKETING.sub(" ", PACK.sub("", s))).strip(" -&,")


def queries(item, known_brands):
    t = clean(item["title"])
    qs = [("b", t)]
    nb = BRAND_PREFIX.sub("", t)
    if nb == t:
        low = t.casefold()
        for b in sorted(known_brands, key=len, reverse=True):
            if low.startswith(b + " "):
                nb = t[len(b):].strip()
                break
        else:
            nb = " ".join(t.split()[1:])  # assume a one-word brand
    if nb and nb != t:
        qs.append(("c", nb))
    g = item.get("variety") or item.get("concept")
    if g and g.casefold() not in {q.casefold() for _, q in qs}:
        qs.append(("d", g))
    return qs


def main(work: Path, catalogue: Path):
    cat = json.load(open(catalogue))
    n_of = {f["title"]: f["n"] for f in json.load(open(work / "families.json"))}
    known = set()
    for p in (work / "off-cache").glob("*.json"):
        for h in json.load(open(p)).get("hits", []):
            for b in (h.get("brands") or []):
                if b and len(b) > 2:
                    known.add(b.strip().casefold())
    todo = [i for i in cat["items"] if i["kind"] == "food" and i.get("category") != "other"
            and i.get("region") != "restaurant"
            # privacy-and-egress.md: receipt titles, and note-derived items only when they name a brand
            and ((i.get("origin") == "receipts" and not i["nutrient_sources"])
                 or (str(i.get("origin", "")).startswith("intake:") and i.get("brand")))]
    out = check_output(work / "off-cache2")  # a linked cache folder must not lead into a git tree
    out.mkdir(exist_ok=True)
    load_food_words(work)  # the outbound gate needs it
    planned = [q for item in todo for tag, q in queries(item, known)
               if not (out / f"{item.get('n') or n_of[item['title']]}-{tag}.json").exists()]
    approved = owner_approval(work, planned)  # stops here until the owner has decided
    client = Client(log=lambda m: print(m, flush=True))
    sent = errors = 0
    print(f"families to retry: {len(todo)}", flush=True)
    try:
        for item in todo:
            n = item.get("n") or n_of[item["title"]]
            for tag, q in queries(item, known):
                p = out / f"{n}-{tag}.json"
                if p.exists():
                    hits = json.load(open(p))["hits"]
                elif q not in approved:
                    continue  # declined or refused: never sent
                else:
                    url = "https://search.openfoodfacts.org/search?" + urllib.parse.urlencode(
                        {"q": safe_query(q), "page_size": 8, "fields": FIELDS})
                    try:
                        hits = client.get_json(url).get("hits", [])
                        sent += 1
                    except CircuitOpen:
                        raise
                    except Exception as e:  # recorded, not treated as "no match"
                        check_output(out / f"{n}-{tag}.error").write_text(f"{type(e).__name__}: {e}")
                        errors += 1
                        continue
                    check_output(p).write_text(json.dumps({"query": q, "pass": tag, "retrieved": time.strftime("%Y-%m-%d"),
                                             "hits": hits}, ensure_ascii=False))
                if any((h.get("nutriments") or {}).get("energy-kcal_100g") for h in hits):
                    break  # stop at the most specific query that found something usable
            if sent and sent % 25 == 0:
                print(f"progress requests={sent} errors={errors}", flush=True)
    except CircuitOpen as e:
        print(f"stopped: {e}", flush=True)
    print(f"finished requests={sent} errors={errors}", flush=True)


if __name__ == "__main__":
    require()
    main(check_output(sys.argv[1]), Path(sys.argv[2]))
