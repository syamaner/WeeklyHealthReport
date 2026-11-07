"""The owner's private configuration: shop layouts, brand exceptions and other names that
would identify the owner if they were written into this repository.

The file lives in the private workspace and is named by the PFC_CONFIG environment variable.
With PFC_CONFIG unset every list is empty, which is always the stricter choice: the privacy
gates allow no brand exceptions, the extractor recognises no layout, and brand matching uses
only the brands in the data itself. A synthetic example is in references/private-config-example.json.

Format pfc-private-config-v1; unknown keys or wrong types are refused, never ignored. It is loaded
once at import (a refused file stops the script), so every gate in a run uses the same values.
"""
import json
import os
import re
import stat
import sys
from pathlib import Path

SCHEMA = "pfc-private-config-v1"
PARSERS = {"itemised_receipt", "order_page", "invoice_table", "order_summary", "product_page_title"}
LIST_KEYS = ("brand_honorifics", "site_chrome_prefixes", "receipt_noise_prefixes", "brand_prefixes",
             "title_stopwords", "supplement_words", "supplement_retailers")
MATCH_KEYS = {"text_contains_all", "text_contains_any_casefold", "file_name_contains", "file_name_suffix"}

# An exception must be exactly one title and one capitalised name word, so it can never exempt a
# bare title ("Mr") or anything longer than the brand itself; a chrome prefix must be a whole word
# of at least four letters, so it can never exempt every header fragment that starts with a letter.
HONORIFIC = re.compile(r"(Mr|Mrs|Miss|Ms|Mx|Dr)\.? [A-Z][a-z]+")
CHROME_PREFIX = re.compile(r"[A-Z][A-Za-z]{3,}")

EMPTY = {"layouts": [], "brand_aliases": {}, **{k: [] for k in LIST_KEYS}}


def _strings(value, where):
    if not isinstance(value, list) or not all(isinstance(s, str) and s.strip() for s in value):
        raise ValueError(f"{where} must be a list of non-empty strings")
    return value


def parse(doc) -> dict:
    """Validate a decoded config document and return it with every key present."""
    if not isinstance(doc, dict) or doc.get("schema") != SCHEMA:
        raise ValueError(f"private config must have schema {SCHEMA!r}")
    unknown = set(doc) - {"schema", "layouts", "brand_aliases", *LIST_KEYS}
    if unknown:
        raise ValueError(f"unknown private config keys: {sorted(unknown)}")
    cfg = {"layouts": [], "brand_aliases": {}}
    for k in LIST_KEYS:
        cfg[k] = _strings(doc.get(k, []), k)
    for b in cfg["brand_honorifics"]:
        if not HONORIFIC.fullmatch(b):
            raise ValueError(f"brand_honorifics entry {b!r} must be one title and one capitalised word")
    for p in cfg["site_chrome_prefixes"]:
        if not CHROME_PREFIX.fullmatch(p):
            raise ValueError(f"site_chrome_prefixes entry {p!r} must be one capitalised word of four or more letters")
    aliases = doc.get("brand_aliases", {})
    if not isinstance(aliases, dict):
        raise ValueError("brand_aliases must map a canonical brand to a list of spellings")
    for canon, spellings in aliases.items():
        if not isinstance(canon, str) or not canon.strip():
            raise ValueError("brand_aliases keys must be non-empty strings")
        cfg["brand_aliases"][canon] = _strings(spellings, f"brand_aliases[{canon!r}]")
    layouts = doc.get("layouts", [])
    if not isinstance(layouts, list):
        raise ValueError("layouts must be a list")
    ids = set()
    for i, lay in enumerate(layouts):
        if not isinstance(lay, dict) or set(lay) - {"id", "retailer", "parser", "match"}:
            raise ValueError(f"layouts[{i}] must have only id, retailer, parser and match")
        if not all(isinstance(lay.get(k), str) and lay[k].strip() for k in ("id", "retailer", "parser")):
            raise ValueError(f"layouts[{i}] needs non-empty id, retailer and parser")
        if lay["parser"] not in PARSERS:
            raise ValueError(f"layouts[{i}].parser must be one of {sorted(PARSERS)}")
        if lay["id"] in ids or lay["id"] == "unknown":
            raise ValueError(f"layouts[{i}].id must be unique and not 'unknown'")
        ids.add(lay["id"])
        match = lay.get("match")
        if not isinstance(match, dict) or not match or set(match) - MATCH_KEYS:
            raise ValueError(f"layouts[{i}].match needs one or more of {sorted(MATCH_KEYS)}")
        for k in ("text_contains_all", "text_contains_any_casefold"):
            if k in match:
                _strings(match[k], f"layouts[{i}].match.{k}")
        for k in ("file_name_contains", "file_name_suffix"):
            if k in match and not (isinstance(match[k], str) and match[k]):
                raise ValueError(f"layouts[{i}].match.{k} must be a non-empty string")
        if lay["parser"] == "product_page_title" and "file_name_suffix" not in match:
            raise ValueError(f"layouts[{i}]: product_page_title takes its title from file_name_suffix")
        cfg["layouts"].append(lay)
    return cfg


def load() -> dict:
    """Read the file PFC_CONFIG names, refusing one inside a git tree or a non-private folder."""
    name = os.environ.get("PFC_CONFIG", "").strip()
    if not name:
        return {k: (list(v) if isinstance(v, list) else dict(v)) for k, v in EMPTY.items()}
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from workspace_guard import check_output  # same refusals as every private write
    path = check_output(name)
    if not path.is_file():
        sys.exit(f"PFC_CONFIG names {path}, which is not a file")
    if path.stat().st_mode & (stat.S_IRWXG | stat.S_IRWXO) or path.parent.stat().st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        sys.exit(f"private config {path} refused: it or its folder is readable by other users; chmod 600 the file and 700 the folder")
    try:
        return parse(json.loads(path.read_text(encoding="utf-8")))
    except (ValueError, json.JSONDecodeError) as e:
        sys.exit(f"private config {path} refused: {e}")


def require():
    """For whole-pipeline entry points: an unset PFC_CONFIG would silently rebuild without the
    owner's layouts and brand aliases, so refuse instead."""
    if not os.environ.get("PFC_CONFIG", "").strip():
        sys.exit("set PFC_CONFIG to the private config (<workspace>/private-config.json) first")


CONFIG = load()
