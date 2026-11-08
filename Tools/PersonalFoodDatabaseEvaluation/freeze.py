"""The machine-checked freeze record, `freeze-v1.json` in this folder (plan section 11 cites it).

    {"schema": "pfd-freeze-v1",
     "files": {"<repo-relative path>": "<sha256>", ...},   scorer files and workspace_guard.py
     "release_id": "pfc:sha256:...",                          E1b
     "seed": 123,                                             E1c
     "sample_sha256": "...", "purchase_counts_sha256": "...",  E1c
     "heldout_sha256": "...",                                 E1d (the seal-heldout bundle hash)
     "golden_sha256": "..."}                                  before v12 code

A command names the entries it needs; a declared entry that is missing, or a file whose hash
differs, stops it (fail closed).
"""
import hashlib
import json
from pathlib import Path

KEYS = {"schema", "files", "release_id", "seed", "sample_sha256", "purchase_counts_sha256", "heldout_sha256",
        "golden_sha256"}


class FreezeError(ValueError):
    pass


def load(path: Path) -> dict:
    if not path.is_file():
        raise FreezeError("freeze record not found")
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        raise FreezeError("freeze record is not valid JSON") from None
    if not isinstance(doc, dict) or doc.get("schema") != "pfd-freeze-v1" or set(doc) - KEYS \
            or not isinstance(doc.get("files"), dict) or not doc["files"]:
        raise FreezeError("freeze record is not pfd-freeze-v1")
    return doc


def check(doc: dict, repo: Path, needs=()):
    tool = Path(__file__).resolve().parent
    rel_tool = tool.relative_to(repo.resolve()) if repo.resolve() in tool.parents else None
    if rel_tool is not None:
        for p in sorted(tool.glob("*.py")):
            if str(rel_tool / p.name) not in doc["files"]:
                raise FreezeError(f"freeze record does not list scorer file {p.name}")
    for rel, want in sorted(doc["files"].items()):
        p = repo / rel
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != want:
            raise FreezeError(f"frozen file changed or missing: {rel}")
    for key in needs:
        if doc.get(key) in (None, ""):
            raise FreezeError(f"freeze record has no {key}")
    return doc
