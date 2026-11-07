#!/usr/bin/env python3
"""Synthetic test: no search query is sent before the owner approves it.

Uses a throwaway private workspace; makes no network calls.
Usage: python3 -I test_owner_approval.py <scripts_dir>
"""
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import http_client as H  # noqa: E402

H.FOOD_WORDS = {"oat", "yogurt", "apple"}
results = []
with tempfile.TemporaryDirectory() as tmp:
    os.chmod(tmp, 0o700)
    work = Path(tmp) / "work"
    work.mkdir()
    qs = ["Example Oats", "Example Greek Yogurt", "Alice Smith 5.00"]
    try:
        H.owner_approval(work, qs)
        results.append(("stops when undecided", False))
    except H.ApprovalNeeded:
        pending = (work / "outbound-pending.txt").read_text().splitlines()
        results.append(("stops when undecided", True))
        results.append(("pending lists only gate-passing queries", pending == qs[:2]))
        results.append(("gate-refused query listed as refused", (work / "outbound-refused.txt").read_text().split("\n")[0] == qs[2]))
    (work / "outbound-approved.txt").write_text("Example Oats\n")
    try:
        H.owner_approval(work, qs)
        results.append(("still stops with one undecided", False))
    except H.ApprovalNeeded:
        results.append(("still stops with one undecided", True))
    (work / "outbound-declined.txt").write_text("Example Greek Yogurt\n")
    approved = H.owner_approval(work, qs)
    results.append(("runs once every query is decided", approved == {"Example Oats"}))
    results.append(("pending file removed when nothing is pending", not (work / "outbound-pending.txt").exists()))
    results.append(("declined query not in the send set", "Example Greek Yogurt" not in approved))
failed = [n for n, ok in results if not ok]
print(f"owner approval: {len(results) - len(failed)} of {len(results)} checks pass")
if failed:
    print("FAILED:", failed)
    sys.exit(1)
