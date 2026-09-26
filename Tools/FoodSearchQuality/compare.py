"""Compare actual Swift-adapter development output; never simulate the matcher."""
import argparse, json, re
from pathlib import Path

def summarise(report):
    rows = report["rows"]
    primary = {"apple": r"^apples?\b", "banana": r"^bananas?\b", "eggs": r"^eggs?\b", "milk": r"^milk\b", "salmon": r"^salmon\b", "tomatoes": r"^tomato(es)?\b", "brown rice": r"^rice, brown\b", "tuna": r"^tuna\b"}
    judged = [r for r in rows if r["query"] in primary]
    return {"queryCount": len(rows), "queriesWithCandidates": sum(bool(r["names"]) for r in rows), "queriesWithActionableRecovery": sum(bool(r["names"] or r["suggestions"]) for r in rows), "primaryFoodAtFirst": sum(bool(r["names"]) and bool(re.search(primary[r["query"]], r["names"][0], re.I)) for r in judged), "primaryFoodJudgedQueries": len(judged), "bothSourcesInFirstFive": sum(any(s.startswith("cofid") for s in r["sources"][:5]) and any(s.startswith("usda") for s in r["sources"][:5]) for r in rows)}

if __name__ == "__main__":
    parser=argparse.ArgumentParser(); parser.add_argument("before"); parser.add_argument("after"); parser.add_argument("output"); args=parser.parse_args()
    before=json.loads(Path(args.before).read_text()); after=json.loads(Path(args.after).read_text())
    assert [r["query"] for r in before["rows"]] == [r["query"] for r in after["rows"]]
    output={"version":"search-quality-paired-development-v1", "independentAcceptance":False, "interpretation":"Tuning diagnostics on 44 public/synthetic queries. Primary-name checks are eight narrow lexical development judgements, not nutritional identity verification, independent relevance labels or production accuracy.", "beforeSummary":summarise(before), "afterSummary":summarise(after), "pairs":[{"query":a["query"], "before":a, "after":b} for a,b in zip(before["rows"],after["rows"])]}
    Path(args.output).write_text(json.dumps(output,indent=2,sort_keys=True)+"\n")
    print(json.dumps({k:v for k,v in output.items() if k.endswith("Summary")},indent=2))
