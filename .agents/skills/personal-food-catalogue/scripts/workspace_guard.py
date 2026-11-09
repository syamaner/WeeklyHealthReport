"""Refuse to run against a workspace that could leak private data.

Use check() for the workspace root and check_output() for any path a script writes.
The workspace must exist, must not be inside a git working tree, and must not be
readable by other users. Every script that writes catalogue data calls check().
"""
import os
import stat
import subprocess
import sys
from pathlib import Path


def check(ws: Path) -> Path:
    os.umask(0o077)  # every file this process writes is private (0600 / 0700)
    ws = ws.expanduser().resolve()
    if not ws.is_dir():
        sys.exit(f"workspace {ws} does not exist; create it with mode 700 first")
    r = subprocess.run(["git", "-C", str(ws), "rev-parse", "--is-inside-work-tree"], capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip() == "true":
        sys.exit(f"workspace {ws} is inside a git working tree; private catalogue data must never be there")
    if ws.stat().st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        sys.exit(f"workspace {ws} is readable by other users; run: chmod 700 '{ws}'")
    return ws


def check_output(path) -> Path:
    """Any path a script writes to must not be inside a git working tree, and must sit under a
    private (mode 700) folder. Also makes every file this process writes private."""
    os.umask(0o077)
    p = Path(path).expanduser().resolve()
    probe = p
    while not probe.exists():
        probe = probe.parent
    if probe.is_file():
        probe = probe.parent
    r = subprocess.run(["git", "-C", str(probe), "rev-parse", "--is-inside-work-tree"], capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip() == "true":
        sys.exit(f"refusing to write {p}: it is inside a git working tree; private catalogue data must never be there")
    if not any(not (d.stat().st_mode & (stat.S_IRWXG | stat.S_IRWXO)) for d in [probe, *probe.parents] if d.exists()):
        sys.exit(f"refusing to write {p}: no private (mode 700) folder above it; run chmod 700 on the workspace")
    return p
