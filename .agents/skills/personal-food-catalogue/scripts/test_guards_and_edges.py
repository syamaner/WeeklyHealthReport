#!/usr/bin/env python3
"""Synthetic tests for guard and edge cases found in the PR review (no network, no private data).

Usage: python3 -I test_guards_and_edges.py <scripts_dir>
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

os.environ.pop("PFC_CONFIG", None)  # synthetic only: never the owner's private config
S = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(S))
import export_v1 as E  # noqa: E402
import match_inputs as M  # noqa: E402

results = []
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    os.chmod(tmp, 0o700)
    repo = tmp / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    ws = tmp / "ws"
    (ws / "work").mkdir(parents=True)
    os.chmod(ws, 0o700)
    (ws / "work" / "off-cache").symlink_to(repo)  # a cache folder that leads into a git tree
    r = subprocess.run([sys.executable, "-I", "-c",
                        f"import sys; sys.path.insert(0, {str(S)!r}); import workspace_guard as g; "
                        f"g.check_output({str(ws / 'work' / 'off-cache' / 'x.json')!r})"], capture_output=True, text=True)
    results.append(("linked cache folder into a git tree is refused", r.returncode != 0 and "git working tree" in (r.stderr + r.stdout)))
    results.append(("nothing was written into the git tree", not (repo / "x.json").exists()))

    empty = ws / "work" / "empty.jsonl"
    empty.write_text("")
    cfg = ws / "private-config.json"  # synthetic example, copied into the private folder
    cfg.write_text((S.parent / "references" / "private-config-example.json").read_text(encoding="utf-8"), encoding="utf-8")
    os.chmod(cfg, 0o600)
    r = subprocess.run([sys.executable, "-I", str(S / "build_unique.py"), str(empty), str(ws / "work" / "out")],
                       capture_output=True, text=True, env={**os.environ, "PFC_CONFIG": str(cfg)})
    results.append(("empty purchase lines give a controlled result", r.returncode == 0 and "no products" in r.stdout))

results.append(("an ampersand brand survives tokenising", "a&b" in M.toks("A&B Greek Yogurt")))
results.append(("another brand is not a product match", not (M.toks("A&B") <= M.toks("Other Greek Yogurt"))))

cat = {"items": [{"kind": "food", "title": "Synthetic Oats", "brand": None, "category": ["x"], "product_type": {"a": 1},
                  "state": None, "nutrients": {}, "label_tiers": {}}], "off_releases": {}}
try:
    doc, _ = E.build(cat, {"cofid": "a" * 64, "usda": "b" * 64, "tfda": "c" * 64}, "2026-11-07")
    it = doc["items"][0]
    results.append(("list or dict vocabulary values fall back, no crash",
                    it["category"] == "other" and it["product_type"] == "unknown" and it["state"] == "unknown"))
except Exception as e:
    results.append((f"list or dict vocabulary values fall back, no crash ({type(e).__name__})", False))

# PR #487 review: the previous-file report and the retired v1 export, in a private temporary folder.
with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp)
    os.chmod(out, 0o700)
    doc = {"items": [{"id": "pfc:000000000001", "basis": "per_100_g", "label_nutrients": {}, "generic_reference": None}]}
    name, report = E.previous_report(out, doc)
    results.append(("no previous file: every entry is new", name is None and report.get("new entries") == 1))
    for bad in (b"[]", b"7", b'{"items": 3}', b"not json"):
        (out / E.V1_OUTPUT_NAME).write_bytes(bad)
        name, report = E.previous_report(out, doc)
        results.append((f"previous file {bad!r} is not compared, never all new",
                        name == E.V1_OUTPUT_NAME and isinstance(report, str) and report.startswith("not compared")))
    (out / E.V1_OUTPUT_NAME).write_text(json.dumps({"items": doc["items"]}))
    name, report = E.previous_report(out, doc)
    results.append(("a v1 previous file is compared", name == E.V1_OUTPUT_NAME and report.get("new entries") is None))
    (out / E.OUTPUT_NAME).write_text(json.dumps({"items": []}))
    name, _ = E.previous_report(out, doc)
    results.append(("the v2 file is preferred as the previous file", name == E.OUTPUT_NAME))
    retired = E.retire_v1_output(out)
    results.append(("the old v1 export is renamed beside the v2 file",
                    retired == (out / E.V1_SUPERSEDED_NAME).resolve() and not (out / E.V1_OUTPUT_NAME).exists()
                    and retired.exists() and (out / E.OUTPUT_NAME).exists()))
    results.append(("nothing to retire the second time", E.retire_v1_output(out) is None))

failed = [n for n, ok in results if not ok]
print(f"guards and edge cases: {len(results) - len(failed)} of {len(results)} checks pass")
if failed:
    print("FAILED:", failed)
    sys.exit(1)
