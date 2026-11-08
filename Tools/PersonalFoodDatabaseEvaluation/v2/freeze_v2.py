"""The v2 freeze record, `freeze-v2.json` beside `freeze-v1.json` (review v2 design, section 4).

    {"schema": "pfd-freeze-v2",
     "files": {"<repo-relative path>": "<sha256>", ...},   every v2 module and the inventory
     "freeze_v1_sha256": "...",                              the unchanged freeze-v1.json
     "part_a_bars": "v1_accepted" | "v2_proposed"}          optional; set by a docs commit

`freeze-v1.json` is never edited: its hash here carries the v1 record (and everything it pins)
forward, and the v2 commands also run the unchanged v1 check. Mirroring v1, every `.py` file of the
v2 folder must be listed (the tests are not), and so must the inventory. A missing or unknown key,
an unknown `part_a_bars` value, a changed file or a different freeze-v1.json stops a command
(fail closed).
"""
import hashlib
import json
import re
from pathlib import Path

from formats import dumps

SCHEMA = "pfd-freeze-v2"
KEYS = {"schema", "files", "freeze_v1_sha256", "part_a_bars"}
REQUIRED = {"schema", "files", "freeze_v1_sha256"}
BAR_SETS = {"v1_accepted", "v2_proposed"}
TOOL = "Tools/PersonalFoodDatabaseEvaluation"
INVENTORY = TOOL + "/nutrient-inventory-v1.json"
HEX64 = re.compile(r"[0-9a-f]{64}")


class FreezeError(ValueError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse(data: bytes) -> dict:
    try:
        doc = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise FreezeError("freeze-v2 record is not valid JSON") from None
    if not isinstance(doc, dict) or doc.get("schema") != SCHEMA or set(doc) - KEYS or REQUIRED - set(doc):
        raise FreezeError("freeze-v2 record is not pfd-freeze-v2")
    files = doc["files"]
    if not isinstance(files, dict) or not files or not all(
            isinstance(k, str) and k and isinstance(v, str) and HEX64.fullmatch(v) for k, v in files.items()):
        raise FreezeError("freeze-v2 record: files must map paths to SHA-256 hashes")
    if not isinstance(doc["freeze_v1_sha256"], str) or not HEX64.fullmatch(doc["freeze_v1_sha256"]):
        raise FreezeError("freeze-v2 record: freeze_v1_sha256 must be a SHA-256 hash")
    if "part_a_bars" in doc and doc["part_a_bars"] not in BAR_SETS:
        raise FreezeError("freeze-v2 record: part_a_bars must be v1_accepted or v2_proposed")
    return doc


def load(path: Path) -> dict:
    if path.is_symlink() or not path.is_file():
        raise FreezeError("freeze-v2 record not found")
    return parse(path.read_bytes())


def check(doc: dict, repo: Path, freeze_v1: Path) -> dict:
    if not freeze_v1.is_file() or sha256(freeze_v1.read_bytes()) != doc["freeze_v1_sha256"]:
        raise FreezeError("freeze-v1.json differs from the hash in the freeze-v2 record")
    here = Path(__file__).resolve().parent
    if repo.resolve() in here.parents:
        rel = here.relative_to(repo.resolve())
        for p in sorted(here.glob("*.py")):
            if str(rel / p.name) not in doc["files"]:
                raise FreezeError(f"freeze-v2 record does not list v2 file {p.name}")
    if INVENTORY not in doc["files"]:
        raise FreezeError("freeze-v2 record does not list the nutrient inventory")
    for rel_path, want in sorted(doc["files"].items()):
        p = repo / rel_path
        if not p.is_file() or sha256(p.read_bytes()) != want:
            raise FreezeError(f"frozen file changed or missing: {rel_path}")
    return doc


def dumps_record(doc: dict) -> bytes:
    return dumps(parse(dumps(doc)))
