"""Synthetic builders shared by the tests. No private data."""
import os
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

RELEASE = "pfc:sha256:" + "1" * 64


def eid(n: int) -> str:
    return f"pfc:{n:012x}"


def label(kind):
    release = ("owner:sha256:" + "c" * 64) if kind == "manual_declaration" else \
        ("pfc-off:sha256:" + "b" * 64 + ":projection:off-product-projection-v4:retrieved:2026-11-07")
    return {"value": 1.0, "unit": "g", "source_kind": kind, "source_release": release,
            "record_id": None if kind == "manual_declaration" else "off:gtin:00000000000017",
            "match": "owner" if kind == "manual_declaration" else "probable"}


def entry(n, kind=None, role=None, title=None):
    e = {"id": eid(n), "brand": None, "title": title or f"Synthetic food {n}", "label_nutrients": {},
         "generic_reference": None}
    if kind:
        e["label_nutrients"] = {"protein": label(kind)}
    if role:
        e["generic_reference"] = {"source": "cofid", "corpus_sha256": "a" * 64, "record_id": f"cofid:synthetic:{n}",
                                  "match": "same_food_same_state" if role == "merge" else "close", "role": role}
    return e


def population(a1=5, a2=60, a3=60, a4=30, a5=2):
    out, n = [], 1
    for count, kw in ((a1, {"kind": "exact_product_dataset"}), (a2, {"role": "merge"}), (a3, {"role": "candidate"}),
                      (a4, {}), (a5, {"kind": "manual_declaration"})):
        for _ in range(count):
            out.append(entry(n, **kw))
            n += 1
    return out


def private_dir():
    """A temporary private folder (mode 700) outside any git tree."""
    t = tempfile.TemporaryDirectory()
    os.chmod(t.name, 0o700)
    return t
