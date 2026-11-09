#!/usr/bin/env python3
"""Every skill script must at least parse: no test imports the network fetchers.

Usage: python3 -I test_compile_all.py <scripts_dir>
"""
import ast
import sys
from pathlib import Path

bad = []
files = sorted(Path(sys.argv[1]).glob("*.py"))
for f in files:
    try:
        ast.parse(f.read_text(encoding="utf-8"), filename=str(f))
    except SyntaxError as e:
        bad.append(f"{f.name}:{e.lineno}: {e.msg}")
print(f"{len(files) - len(bad)} of {len(files)} scripts parse")
if bad:
    print("\n".join(bad))
    sys.exit(1)
