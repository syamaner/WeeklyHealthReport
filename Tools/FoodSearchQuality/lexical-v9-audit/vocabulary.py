"""Audit input for food-lexical-terms-v9: every lowercase ASCII word in the
bundled CoFID, USDA and TFDA names (TFDA aliases included) and in the given
evaluation query sets, with the sources it occurs in.

Usage: python3 vocabulary.py <repository root> <output.tsv> <query set.json>...
Diacritics are removed and words split on anything that is not a letter or
digit, close to GenericFoodRankingPolicy.literalTerms. Offline only.
"""
import json
import re
import sys
import unicodedata
from collections import defaultdict

root, output = sys.argv[1], sys.argv[2]
resources = root + "/Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources/"


def words(text):
    text = "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c)).lower()
    return [w for w in re.split(r"[^\w]|_", text) if w]


sources = defaultdict(set)
for record in json.load(open(resources + "cofid-2021-generic-search-v1.json"))["records"]:
    for word in words(record["name"]):
        sources[word].add("cofid")
for record in json.load(open(resources + "usda-generic-v1.json"))["records"]:
    for word in words(record["name"]):
        sources[word].add("usda")
for record in json.load(open(resources + "tfda-generic-v1.json"))["records"]:
    for alias in record["aliases"] + [record["name"]]:
        for word in words(alias):
            sources[word].add("tfda")
for path in sys.argv[3:]:
    label = path.split("/")[-1].replace(".json", "")
    for case in json.load(open(path))["cases"]:
        for word in words(case["query"]):
            sources[word].add(label)
with open(output, "w") as handle:
    for word in sorted(sources):
        if re.fullmatch("[a-z]+", word):
            handle.write(word + "\t" + ",".join(sorted(sources[word])) + "\n")
print(len(sources))
