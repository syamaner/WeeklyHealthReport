#!/usr/bin/env python3
"""Write the private pfd-purchase-counts-v1 file for an import file (evaluation plan section 3.2).

The import file carries no purchase data, so the Part A sample's top 30 comes from this file: for
every entry in the import file, the number of receipt purchase lines of the working-catalogue foods
that export to that entry (the same brand and title rule as export_v1.entry_id). An entry with no
receipt lines (for example one added from notes) counts 0. The release ID is derived from the import
file's exact bytes, as the app does.

Prints counts only and never overwrites a file.

Usage: python3 -I purchase_counts.py <workspace> <import_file> <output_file>
"""
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_v1 import entry_id  # noqa: E402
from workspace_guard import check, check_output  # noqa: E402


class CountsError(ValueError):
    pass


def purchase_counts(catalogue: dict, export_bytes: bytes) -> dict:
    """The pfd-purchase-counts-v1 document. Pure."""
    export = json.loads(export_bytes.decode("utf-8"))
    if export.get("schema") != "personal-food-catalogue-v1":
        raise CountsError("the import file is not personal-food-catalogue-v1")
    ids = [it["id"] for it in export["items"]]
    if len(set(ids)) != len(ids):
        raise CountsError("the import file repeats an entry id")
    counts = dict.fromkeys(ids, 0)
    seen = set()
    for item in catalogue["items"]:
        if item.get("kind") != "food":
            continue
        lines = item.get("purchase_lines") or 0
        if isinstance(lines, bool) or not isinstance(lines, int) or lines < 0:
            raise CountsError("a catalogue food has an invalid purchase line count")
        eid = entry_id(item.get("brand"), item["title"])
        seen.add(eid)
        if eid in counts:
            counts[eid] += lines
    # The import file is built from this catalogue, so both must hold exactly the same foods; a catalogue
    # changed after the export (new foods, or foods dropped) is refused rather than counted.
    extra, missing = len(seen - set(counts)), len(set(counts) - seen)
    if extra or missing:
        raise CountsError(f"the catalogue and the import file differ ({extra} foods only in the catalogue, "
                          f"{missing} entries only in the import file); rebuild the import file from this catalogue first")
    return {"schema": "pfd-purchase-counts-v1",
            "release_id": "pfc:sha256:" + hashlib.sha256(export_bytes).hexdigest(),
            "counts": dict(sorted(counts.items()))}


def main(ws: Path, export_path: Path, out_path: Path):
    catalogue_bytes = (ws / "out" / "personal-food-catalogue.json").read_bytes()
    catalogue = json.loads(catalogue_bytes.decode("utf-8"))
    export_bytes = check_output(export_path).read_bytes()
    try:
        doc = purchase_counts(catalogue, export_bytes)
    except CountsError as e:
        sys.exit(f"refused: {e}")
    out = check_output(out_path)
    if out.exists() or out.is_symlink():
        sys.exit("refused: the purchase counts file already exists and is never overwritten")
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "x", encoding="utf-8") as fh:
        fh.write(json.dumps(doc, indent=1, sort_keys=True) + "\n")
    out.chmod(0o600)
    c = doc["counts"].values()
    print(f"purchase counts written: {len(doc['counts'])} entries, {sum(1 for v in c if v)} with purchases, "
          f"{sum(c)} purchase lines; from catalogue sha256 {hashlib.sha256(catalogue_bytes).hexdigest()} "
          f"and release {doc['release_id']}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(check(Path(sys.argv[1])), Path(sys.argv[2]).expanduser(), Path(sys.argv[3]).expanduser())
