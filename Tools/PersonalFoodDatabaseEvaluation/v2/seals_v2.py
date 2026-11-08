"""Append-only v2 seals in the private evaluation folder (review v2 design, section 4).

v2 seals go to their own `seals-v2.txt`, never to the v1 `seals.txt`, so the v1 `seals.py` never
meets an unknown seal name. Lines use the v1 format, `<name> <sha256> <third field> <UTC time>`:

    seal-review-v2 <bundle sha256> <files> <time>   the review-v2/ bundle, recorded once
    score-a-v2 <freeze-v2 sha256> <part_a_bars> <time>   the bars lock, written by the first scoring run

A line is never replaced. The bundle hash uses the v1 listing rule (seals.bundle_sha256): the
SHA-256 of `<sha256>  review-v2/<name>\\n` lines sorted by name, over exactly the two named files;
a third file, a folder or a link is refused. `seal-review-v2` needs `seal-dev` and `seal-heldout`
in the v1 `seals.txt` (read through the unchanged `seals.recorded`) and is refused once a v1
`seal-review` exists. After the bars lock, a different `part_a_bars` is refused.
"""
import contextlib
import fcntl
import hashlib
import os
import re
from pathlib import Path

import seals

FILE = "seals-v2.txt"
FOLDER = "review-v2"
SHEET = "review-sheet-v2.csv"
EVIDENCE = "nutrient-evidence-v2.jsonl"
BUNDLE = tuple(sorted((SHEET, EVIDENCE)))
REVIEW = "seal-review-v2"
LOCK = "score-a-v2"
BAR_SETS = {"v1_accepted", "v2_proposed"}
HEX64 = re.compile(r"[0-9a-f]{64}")


class SealError(ValueError):
    pass


def bundle_sha256(root: Path):
    folder = root / FOLDER
    if folder.is_symlink() or not folder.is_dir():
        raise SealError(f"{FOLDER} must be a folder inside the evaluation folder, not a link")
    entries = list(folder.iterdir())
    if any(p.is_symlink() for p in entries):
        raise SealError(f"{FOLDER}: a sealed file must not be a link")
    if sorted(p.name for p in entries) != list(BUNDLE) or not all(p.is_file() for p in entries):
        raise SealError(f"{FOLDER} must hold exactly {SHEET} and {EVIDENCE}, and nothing else")
    listing = "".join(f"{hashlib.sha256((folder / n).read_bytes()).hexdigest()}  {FOLDER}/{n}\n" for n in BUNDLE)
    return hashlib.sha256(listing.encode("utf-8")).hexdigest(), len(BUNDLE)


def _file(root: Path) -> Path:
    p = root / FILE
    if p.is_symlink() or (p.exists() and not p.is_file()):
        raise SealError(f"{FILE} must be a plain file inside the evaluation folder")
    return p


@contextlib.contextmanager
def _locked(root: Path):
    fd = os.open(root / ".seals-v2.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def recorded(root: Path) -> dict:
    """{"seal-review-v2": sha256, "score-a-v2": (freeze-v2 sha256, part_a_bars)} for the lines present."""
    p = _file(root)
    out = {}
    for n, line in enumerate(p.read_text(encoding="utf-8").splitlines() if p.exists() else [], start=1):
        parts = line.split()
        ok = len(parts) == 4 and HEX64.fullmatch(parts[1]) is not None
        if ok and parts[0] == REVIEW and REVIEW not in out and not out and parts[2].isdigit():
            out[REVIEW] = parts[1]
        elif ok and parts[0] == LOCK and REVIEW in out and LOCK not in out and parts[2] in BAR_SETS:
            out[LOCK] = (parts[1], parts[2])
        else:
            raise SealError(f"{FILE} line {n} is damaged or repeats a seal; fix it by hand before going on")
    return out


def check_bars(root: Path, part_a_bars):
    """Refuse a part_a_bars that differs from the bars lock (absent counts as different)."""
    lock = recorded(root).get(LOCK)
    if lock is not None and part_a_bars != lock[1]:
        raise SealError("part_a_bars differs from the value locked by the first score-a-v2 run")


def seal_review(root: Path, now_utc: str) -> str:
    with _locked(root):
        have = recorded(root)
        if REVIEW in have:
            raise SealError(f"{REVIEW} is already recorded; seals are never replaced")
        v1 = seals.recorded(root)  # read only: the unchanged v1 module and seals.txt
        if "seal-review" in v1:
            raise SealError(f"a v1 seal-review is recorded, so {REVIEW} is refused for this rubric")
        for earlier in ("seal-dev", "seal-heldout"):
            if earlier not in v1:
                raise SealError(f"{earlier} must be recorded before {REVIEW}")
        h, files = bundle_sha256(root)
        with open(_file(root), "a", encoding="utf-8") as fh:
            fh.write(f"{REVIEW} {h} {files} {now_utc}\n")
        return h


def require_review(root: Path) -> str:
    have = recorded(root)
    if REVIEW not in have:
        raise SealError(f"{REVIEW} is not recorded")
    if bundle_sha256(root)[0] != have[REVIEW]:
        raise SealError(f"void: the files differ from {REVIEW}")
    return have[REVIEW]


def score_locked(root: Path, part_a_bars: str, freeze_v2_sha256: str, now_utc: str, write):
    """Run `write()` under the seal lock, after checking the review seal and the bars lock. The first
    run appends the bars lock line, flushed to disk, before any count is written, so an interruption
    can leave a lock without counts (a rerun with the same bars is allowed) but never counts without
    a lock."""
    if part_a_bars not in BAR_SETS or not HEX64.fullmatch(freeze_v2_sha256):
        raise SealError("score-a-v2 needs a known part_a_bars and the freeze-v2 hash")
    with _locked(root):
        require_review(root)
        check_bars(root, part_a_bars)
        first = LOCK not in recorded(root)
        if first:
            with open(_file(root), "a", encoding="utf-8") as fh:
                fh.write(f"{LOCK} {freeze_v2_sha256} {part_a_bars} {now_utc}\n")
                fh.flush()
                os.fsync(fh.fileno())
        write()
        return first
