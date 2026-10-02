"""Replay consumed development evidence through the original v3 pure scorer.

Collector modules are imported for historical request construction only; capture,
frozen(), keychain, resolver and holdout functions are never invoked. The enclosing
OS sandbox blocks network and execution of the Keychain security command.
"""
import hashlib
import importlib
import json
import sys
from pathlib import Path


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def replay(root, documents):
    sys.path.insert(0, str(root))
    candidate = importlib.import_module("candidate_v3")
    corpus = json.loads((root / "corpus-v1.json").read_text())
    corpus["cases"] = [c for c in corpus["cases"] if c["split"] == "development"]
    used_sources = {c["source"] for c in corpus["cases"]}
    corpus["sources"] = {k: v for k, v in corpus["sources"].items() if k in used_sources}
    contract = json.loads((root / "frozen-contract-v3.json").read_text())
    prior = json.loads((root / "frozen-contract-v2.json").read_text())
    # Hash all historical dependencies but allow unrelated current resource drift
    # only as a visible historical-comparability limitation. Those sources are not
    # used by the extraction replay; resolver evaluation is excluded.
    drift = []
    for name, sha in contract["sha256"].items():
        if digest(root / name) != sha:
            if name.startswith("../../Packages/"):
                drift.append(name)
            else:
                raise ValueError("Changed extraction dependency: " + name)
    for name, sha in prior["sha256"].items():
        if digest(root / name) != sha:
            raise ValueError("Changed prior extraction dependency: " + name)
    if digest(documents / "manifest.json") != prior["document_manifest_sha256"]:
        raise ValueError("Changed document manifest")
    manifest = json.loads((documents / "manifest.json").read_text())
    docs = {}
    for name, meta in manifest["sources"].items():
        if name not in used_sources or meta["outcome"] != "fetched":
            continue
        doc = json.loads((documents / (name + ".json")).read_text())
        if hashlib.sha256(doc["text"].encode()).hexdigest() != meta["text_sha256"]:
            raise ValueError("Changed source text")
        if doc["selected_url"] != corpus["sources"][name]["url"] or doc["retrieved_url"] != meta["retrieved_url"]:
            raise ValueError("Changed document identity")
        docs[name] = doc
    saved = json.loads((root / "development-replay-v3.json").read_text())
    if saved["split"] != "development":
        raise ValueError("Development replay only")
    report = candidate.report(corpus, contract, docs, saved)
    historical = json.loads((root / "development-report-v3.json").read_text())
    if report != historical:
        raise ValueError("Development replay differs from preserved report")
    rows = [dict(id="extraction-" + r["case_id"] + "-" + r["arm"], suite="extraction",
                 family=r["arm"], evidence="historical_agent_reviewed_development",
                 observed=r["score"], expectation_met=bool(r["score"] and r["score"]["passed"]),
                 reason="historical v3 scorer reproduced" if r["score"] and r["score"]["passed"] else "extraction failure",
                 ai_status="legacy_case_pass" if r["score"] and r["score"]["passed"] else "fail",
                 safeguard_status="not_run", outcome_status="not_run") for r in report["details"]]
    return report, rows, drift
