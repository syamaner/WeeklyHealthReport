#!/usr/bin/env python3
"""Fetch Open Food Facts candidates for each family title.

Only the product title (pack size removed) is sent. Responses are cached per
family; reruns skip cached families. Network calls go through http_client.Client: proactive
per-host rate limit under the published limit, backoff with jitter, Retry-After,
adaptive slow-down on 429 and a circuit breaker.

Usage: python3 -I fetch_off.py <work_dir>
"""
import json
import re
import sys
import time
import urllib.error
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check_output  # noqa: E402
from http_client import CircuitOpen, Client, load_food_words, owner_approval, safe_query  # noqa: E402

FIELDS = "code,product_name,brands,quantity,countries_tags,nutriments,serving_size,categories_tags"
PACK = re.compile(r"\s*(\d+\s*[xX×]\s*)?\d+(\.\d+)?\s*(kg|g|ml|cl|l)\b.*$|\s*\d+\s+per pack.*$", re.I)


def query_of(title: str) -> str:
    q = PACK.sub("", title)
    return re.sub(r"\s+", " ", q).strip()


def main(work: Path):
    cache = check_output(work / "off-cache")  # a linked cache folder must not lead into a git tree
    cache.mkdir(exist_ok=True)
    fams = json.load(open(work / "families.json"))
    done = failed = 0
    load_food_words(work)  # the outbound gate needs it
    todo = [(f, query_of(f["title"])) for f in fams if not (cache / f"{f['n']}.json").exists()]
    approved = owner_approval(work, [q for _, q in todo])  # stops here until the owner has decided
    client = Client(log=lambda m: print(m, flush=True))
    for f, q in todo:
        p = cache / f"{f['n']}.json"
        if q not in approved:
            continue  # declined or refused: never sent
        url = "https://search.openfoodfacts.org/search?" + urllib.parse.urlencode(
            {"q": safe_query(q), "page_size": 8, "fields": FIELDS})
        try:
            d = client.get_json(url)
            hits = d.get("hits", [])
            check_output(p).write_text(json.dumps({"query": q, "retrieved": time.strftime("%Y-%m-%d"),
                                     "hits": hits}, ensure_ascii=False))
            done += 1
        except CircuitOpen as e:
            print(f"stopped: {e}", flush=True)
            break
        except Exception as e:  # recorded, never silently treated as no match
            check_output(cache / f"{f['n']}.error").write_text(f"{type(e).__name__}: {e}")
            failed += 1
        if (done + failed) % 50 == 0:
            print(f"progress done={done} failed={failed}", flush=True)
    print(f"finished done={done} failed={failed}", flush=True)


if __name__ == "__main__":
    main(check_output(sys.argv[1]))
