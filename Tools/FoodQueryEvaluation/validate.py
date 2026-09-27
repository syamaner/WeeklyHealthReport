import hashlib, json
from pathlib import Path
root = Path(__file__).parent
import sys
version = sys.argv[1] if len(sys.argv) > 1 else "v2"
assert version in {"v1", "v2", "v3", "v4", "v5"}
raw = (root / f"synthetic-{version}.json").read_bytes()
data = json.loads(raw)
manifest = json.loads((root / f"manifest-{version}.json").read_text())
assert hashlib.sha256(raw).hexdigest() == manifest["sha256"]
cases = data["cases"]
assert len(cases) == manifest["case_count"]
assert len({c["id"] for c in cases}) == len(cases)
for c in cases:
    e = c["expected"]
    assert e["route"] in {"search", "clarify", "reject"}
    if e["route"] == "search": assert e["food"]
    else: assert e["reason"] and e["quantity"] is None
    if e["quantity"]:
        assert e["quantity"]["value"] > 0
        assert e["quantity"]["unit"] in {"g", "ml", "count"}
    assert "explicit_selection_and_confirmation" in c["invariants"]
print(f"Validated {len(cases)} synthetic fixtures; parser performance not evaluated.")
