"""Append-only seals for the private evaluation folder. Pure apart from the folder it is given.

The bundle hash matches the Swift fresh-set protocol (FreshSetProtocol.bundleSHA256): the SHA-256
of `<sha256>  <prefix>/<name>\\n` lines, one per file with the suffix, sorted by name. `seals.txt`
holds one line per seal, `<name> <sha256> <files> <UTC time>`, in the order seal-dev, seal-heldout,
seal-review; a seal is never replaced. Held-out scoring runs are logged in `runs.txt`; the held-out
set may be scored once plus one rerun for an infrastructure failure.
"""
import hashlib
from pathlib import Path

ORDER = ("seal-dev", "seal-heldout", "seal-review")
FOLDERS = {"seal-dev": ("development", ".json"), "seal-heldout": ("held-out", ".json"), "seal-review": ("review", ".csv")}
HELD_OUT_RUN_LIMIT = 2


class SealError(ValueError):
    pass


def bundle_sha256(folder: Path, prefix: str, suffix: str):
    names = sorted(p.name for p in folder.iterdir() if p.is_file() and p.name.endswith(suffix)) if folder.is_dir() else []
    listing = "".join(f"{hashlib.sha256((folder / n).read_bytes()).hexdigest()}  {prefix}/{n}\n" for n in names)
    return hashlib.sha256(listing.encode("utf-8")).hexdigest(), len(names)


def recorded(root: Path) -> dict:
    p = root / "seals.txt"
    out = {}
    if p.exists():
        for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), start=1):
            parts = line.split()
            if len(parts) != 4 or parts[0] not in ORDER or parts[0] in out or len(parts[1]) != 64 or not parts[2].isdigit():
                raise SealError(f"seals.txt line {n} is damaged or repeats a seal; fix it by hand before going on")
            out[parts[0]] = parts[1]
    return out


def current(name: str, root: Path):
    folder, suffix = FOLDERS[name]
    return bundle_sha256(root / folder, folder, suffix)


def seal(name: str, root: Path, now_utc: str) -> str:
    if name not in ORDER:
        raise SealError("unknown seal")
    have = recorded(root)
    if name in have:
        raise SealError(f"{name} is already recorded; seals are never replaced")
    for earlier in ORDER[:ORDER.index(name)]:
        if earlier not in have:
            raise SealError(f"{earlier} must be recorded before {name}")
    h, files = current(name, root)
    if files == 0:
        raise SealError(f"{name}: nothing to seal")
    with open(root / "seals.txt", "a", encoding="utf-8") as fh:
        fh.write(f"{name} {h} {files} {now_utc}\n")
    return h


def require(name: str, root: Path) -> str:
    have = recorded(root)
    if name not in have:
        raise SealError(f"{name} is not recorded")
    if current(name, root)[0] != have[name]:
        raise SealError(f"void: the files differ from {name}")
    return have[name]


def log_held_out_run(root: Path, ranking_sha256: str, now_utc: str):
    p = root / "runs.txt"
    runs = [l for l in p.read_text(encoding="utf-8").splitlines() if l.startswith("held-out ")] if p.exists() else []
    if len(runs) >= HELD_OUT_RUN_LIMIT:
        raise SealError("the held-out set has already been scored once and rerun once")
    with open(p, "a", encoding="utf-8") as fh:
        fh.write(f"held-out {ranking_sha256} {now_utc}\n")
    return len(runs) + 1
