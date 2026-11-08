"""Append-only seals for the private evaluation folder. Pure apart from the folder it is given.

The bundle hash matches the Swift fresh-set protocol (FreshSetProtocol.bundleSHA256): the SHA-256
of `<sha256>  <prefix>/<name>\\n` lines, one per file with the suffix, sorted by name. `seals.txt`
holds one line per seal, `<name> <sha256> <files> <UTC time>`, in the order seal-dev, seal-heldout,
seal-review; a seal is never replaced. Held-out scoring runs are recorded in the same file as
`run-heldout <sha256> <n> <UTC time>` lines; the held-out set may be scored once plus one rerun for
an infrastructure failure. The limit guards against an accidental rerun, not a deliberate edit of the
private file. A seal file
that is a link is refused.
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


def _file(root: Path) -> Path:
    p = root / "seals.txt"
    if p.is_symlink() or (p.exists() and not p.is_file()):
        raise SealError("seals.txt must be a plain file inside the evaluation folder")
    return p


def _lines(root: Path):
    p = _file(root)
    return p.read_text(encoding="utf-8").splitlines() if p.exists() else []


def recorded(root: Path) -> dict:
    out, runs = {}, 0
    for n, line in enumerate(_lines(root), start=1):
        parts = line.split()
        ok = len(parts) == 4 and len(parts[1]) == 64 and parts[2].isdigit()
        if ok and parts[0] == "run-heldout" and "seal-heldout" in out and int(parts[2]) == runs + 1:
            runs += 1
            continue
        if not ok or parts[0] not in ORDER or parts[0] in out:
            raise SealError(f"seals.txt line {n} is damaged or repeats a seal; fix it by hand before going on")
        out[parts[0]] = parts[1]
    return out


def held_out_runs(root: Path) -> int:
    recorded(root)
    return sum(1 for l in _lines(root) if l.startswith("run-heldout "))


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
    with open(_file(root), "a", encoding="utf-8") as fh:
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
    require("seal-heldout", root)
    runs = held_out_runs(root)
    if runs >= HELD_OUT_RUN_LIMIT:
        raise SealError("the held-out set has already been scored once and rerun once")
    with open(_file(root), "a", encoding="utf-8") as fh:
        fh.write(f"run-heldout {ranking_sha256} {runs + 1} {now_utc}\n")
    return runs + 1
