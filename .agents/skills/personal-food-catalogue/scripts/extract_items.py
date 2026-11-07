#!/usr/bin/env python3
"""Sanitising item extractor for private receipts.

Allow-list: only item-line fields are ever written. Raw receipt text is held in
memory only. A deny-list gate scans every output field and aborts without
writing anything if a personal-data pattern or a header fragment appears.

Shop layouts (marker strings, parser and shop name) come from the owner's private config
(PFC_CONFIG, see private_config.py); with none set every document is reported as unknown.

Usage: python3 -I extract_items.py <receipts_dir> <out_dir>
"""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check_output  # noqa: E402
from private_config import CONFIG, require  # noqa: E402

ITEM_RECEIPT = re.compile(r"^\s{3,}(?P<name>\S.*?)\s{2,}(?P<d>\d+)/(?P<o>\d+)\s+£?\s*(?P<price>-?[\d.]+)\s*$")
ITEM_ORDERPAGE = re.compile(r"^\s+(?P<q>\d+)\s*[хxX×]\s+(?P<rest>\S.*)$")  # Cyrillic х is real
PER_UNIT = re.compile(r"^\s*\((?:£|)[\d.]+p?\s+per\s+(?P<unit>[a-z0-9 ]+)\)", re.I)
RECEIPT_NOISE = re.compile(
    r"^\s*(Fridge|Cupboard|Freezer|Use by end of|Products with|Now |Buy |"
    r"Save |£\d+ .*Meal Deal|Delivered /|Ordered|"
    r"Price to pay|You've saved|Page \d|Offers|Total|Cost of goods|Delivery charge|Carrier bag|"
    r"Payment details|\*You have paid|Multi-buy|Was |Half price"
    + "".join("|" + re.escape(p) for p in CONFIG["receipt_noise_prefixes"]) + ")", re.I)  # shop-specific words are private

# Deny-list gate (applies to every string written).
DENY = [
    ("email", re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")),
    ("uk_postcode", re.compile(r"\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b")),
    ("long_digits", re.compile(r"\d{7,}")),
    ("card", re.compile(r"\b(AMEX|VISA|MASTERCARD|MAESTRO|card ending)\b", re.I)),
    ("honorific", re.compile(r"\b(Mr|Mrs|Miss|Ms|Mx|Dr)\.?\s+[A-Z][a-z]+", )),
    ("address_word", re.compile(r"\b\d+\s+(\w+\s+){1,3}(Road|Street|Lane|Avenue|Close|Gardens|Drive|Way)\b", re.I)),
    ("reference", re.compile(r"\b(order (number|reference)|invoice|payment reference|INV-)\b", re.I)),
]


def pdf_text(path: Path) -> str:
    return subprocess.run(["pdftotext", "-layout", str(path), "-"], capture_output=True, text=True, check=True).stdout


def h(s: str, n: int = 12) -> str:
    return hashlib.sha256(s.encode()).hexdigest()[:n]


def header_chunks(lines, upto):
    chunks = set()
    for ln in lines[:upto]:
        for c in re.split(r"\s{2,}", ln.strip()):
            if len(c) >= 6:
                chunks.add(c)
    return chunks


def parse_receipt(lines):
    order = re.search(r"Order number:\s*(\d+)", "\n".join(lines[:15]))
    date = re.search(r"Delivery date:\s*\w+\s+(\d{2})/(\d{2})/(\d{4})", "\n".join(lines[:15]))
    items, unclaimed, first = [], [], None
    in_offers = False
    head = None          # name start awaiting a quantity-only line
    tail_target = None   # item built from a wrap, which may take one suffix line
    qty_only = re.compile(r"^\s+(?P<d>\d+)/(?P<o>\d+)\s+£?\s*-?[\d.]+\s*$")
    page_footer = re.compile(r"^\s*\d+/\d+\s*$")
    for i, ln in enumerate(lines):
        if re.search(r"Price to pay \(£\)\s+Qty", ln):
            in_offers = True  # savings table repeats products; never counted
        if in_offers or not ln.strip() or page_footer.match(ln):
            continue
        q = qty_only.match(ln)
        if q and head:
            # Three-line wrap: name start, then quantity/price only, then optional suffix.
            items.append({"line_no": head[0], "name": head[1], "delivered": int(q["d"]), "ordered": int(q["o"])})
            tail_target, head = items[-1], None
            continue
        m = ITEM_RECEIPT.match(ln)
        if m:
            first = i if first is None else first
            if head:
                unclaimed.append(head[0])  # orphan name start: reported, never guessed
            items.append({"line_no": i + 1, "name": m["name"].strip(), "delivered": int(m["d"]), "ordered": int(m["o"])})
            head = tail_target = None
            continue
        textual = first is not None and re.match(r"^\s{3,}\S", ln) and "£" not in ln and not RECEIPT_NOISE.match(ln)
        if textual and tail_target is not None:
            tail_target["name"] = f"{tail_target['name']} {ln.strip()}"
            tail_target["wrapped"] = True
            tail_target = None
        elif textual:
            if head:
                unclaimed.append(head[0])
            head = (i + 1, ln.strip())
        else:
            if head:
                unclaimed.append(head[0])
            head = tail_target = None
    meta = {"month": f"{date[3]}-{date[2]}" if date else None}  # no order key: short numbers can be reversed
    return meta, items, unclaimed, first or 0


def parse_orderpage(lines):
    order = re.search(r"Order reference:\s*(\d+)", "\n".join(lines))
    items, unclaimed, first = [], [], None
    for i, ln in enumerate(lines):
        m = ITEM_ORDERPAGE.match(ln)
        if m:
            first = i if first is None else first
            name = re.split(r"\s{2,}", m["rest"].strip())[0]
            unit = None
            nxt = next((l for l in lines[i + 1:i + 12] if l.strip()), "")
            typ = re.match(r"^\s*([\d.]+)\s*(G|KG)\s+typically", nxt, re.I)
            if typ:
                nxt = nxt[typ.end():]
            u = PER_UNIT.match(nxt)
            unit = u["unit"].strip().lower() if u else None
            if not u and nxt.strip() and not ITEM_ORDERPAGE.match(nxt) \
                    and not re.match(r"^\s*(£|Summary|Live Chat|Feedback)", re.split(r"\s{2,}", nxt.strip())[0]):
                unclaimed.append(i + 2)  # unexpected line after a name: report it
            items.append({"line_no": i + 1, "name": name, "qty": int(m["q"]),
                          "unit_price_basis": unit,
                          "pack_hint": f"{typ[1]} {typ[2].lower()} typical weight" if typ else None})
    meta = {"month": None}
    return meta, items, unclaimed, first or 0


def parse_invoice_table(lines):
    items, start = [], None
    for i, ln in enumerate(lines):
        if ln.strip().startswith("Description"):
            start = i
        elif start is not None and ln.strip().startswith("Shipping charges"):
            break
        elif start is not None:
            m = re.match(r"^(?P<name>\S.*?)\s{2,}(?P<q>\d+)\s{2,}£[\d.]+\s*$", ln)
            if m:
                pack = lines[i + 1].strip() if i + 1 < len(lines) and "£" not in lines[i + 1] else None
                items.append({"line_no": i + 1, "name": m["name"].strip(), "qty": int(m["q"]), "pack_hint": pack or None})
    date = re.search(r"Order date\s+\d+\s+(\w+)\s+(\d{4})", "\n".join(lines))
    months = {m: f"{n:02d}" for n, m in enumerate(["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sept", "Oct", "Nov", "Dec"], 1)}
    month = f"{date[2]}-{months.get(date[1], months.get(date[1][:3]))}" if date else None
    return {"month": month}, items, [], start or 0


def parse_shopify_order(lines):
    items, first = [], None
    for i, ln in enumerate(lines):
        m = re.match(r"^\s*(?P<name>[A-Z][^£]*?)\s{2,}£[\d.]+\s*$", ln)
        if m and not re.match(r"\s*(Subtotal|Shipping|Total|Including)", m["name"]):
            pack = lines[i + 1].strip() if i + 1 < len(lines) and re.match(r"^\s*\d+\s*(g|kg|ml)\s*$", lines[i + 1]) else None
            first = i if first is None else first
            items.append({"line_no": i + 1, "name": m["name"].strip(), "pack_hint": pack})
    return {"month": None}, items, [], first or 0


PARSERS = {"itemised_receipt": parse_receipt, "order_page": parse_orderpage,
           "invoice_table": parse_invoice_table, "order_summary": parse_shopify_order,
           "product_page_title": None}


def matches(match, path: Path, text: str) -> bool:
    """Every condition a layout names must hold."""
    low = text.casefold()
    return all([
        all(m in text for m in match.get("text_contains_all", [])),
        any(m.casefold() in low for m in match["text_contains_any_casefold"]) if "text_contains_any_casefold" in match else True,
        match["file_name_contains"] in path.name if "file_name_contains" in match else True,
        path.name.endswith(match["file_name_suffix"]) if "file_name_suffix" in match else True,
    ])


def classify(path: Path, text: str, layouts=None):
    """First private layout whose markers all match: (layout id, shop, parser kind)."""
    for lay in CONFIG["layouts"] if layouts is None else layouts:
        if matches(lay["match"], path, text):
            return lay["id"], lay["retailer"], lay["parser"]
    return "unknown", None, None


# Exact, reviewed exceptions, kept in the private config: brand names that look like
# honorifics, and site-navigation words that also occur in product titles.
BRAND_HONORIFICS = set(CONFIG["brand_honorifics"])
SITE_CHROME_WORDS = set(CONFIG["site_chrome_prefixes"])  # a header fragment exempt only when it is exactly one of these


def gate(records, chunks_by_doc):
    failures = []
    for r in records:
        for field, v in r.items():
            if not isinstance(v, str) or not v or field in ("doc_id", "layout", "retailer", "month"):
                continue
            for label, rx in DENY:
                hit = rx.search(v)
                if hit and not (label == "honorific" and hit.group(0) in BRAND_HONORIFICS):
                    failures.append((r["doc_id"], r["line_no"], field, label))
            for c in chunks_by_doc.get(r["doc_id"], ()):
                if c in v and c not in SITE_CHROME_WORDS:
                    failures.append((r["doc_id"], r["line_no"], field, "header_fragment"))
    return failures


def main(src: Path, out: Path):
    records, coverage, chunks_by_doc = [], [], {}
    for path in sorted(src.glob("*.pdf")):
        raw = path.read_bytes()
        doc_id = hashlib.sha256(raw).hexdigest()[:16]
        text = pdf_text(path)
        layout, retailer, kind = classify(path, text)
        lines = text.splitlines()
        parser = PARSERS.get(kind)
        if parser is None:
            items, meta, unclaimed, first = [], {"month": None}, [], 0
            if kind == "product_page_title":
                suffix = next(l["match"]["file_name_suffix"] for l in CONFIG["layouts"] if l["id"] == layout)
                title = path.name[:-len(suffix)].rstrip(" -")
                items = [{"line_no": 0, "name": title, "reference_only": True}]
        else:
            meta, items, unclaimed, first = parser(lines)
        chunks_by_doc[doc_id] = header_chunks(lines, first) if kind != "product_page_title" else set()
        for it in items:
            records.append({"doc_id": doc_id, "layout": layout, "retailer": retailer, **meta, **it})
        coverage.append({"doc_id": doc_id, "layout": layout, "items": len(items),
                         "wrapped_or_unclaimed_lines": unclaimed,
                         "missing_lines": sum(1 for it in items if it.get("delivered", 1) < it.get("ordered", 0))})
    failures = gate(records, chunks_by_doc)
    if failures:
        print(f"GATE FAILED: {len(failures)} hits; nothing written.")
        for f in failures[:50]:
            print("  ", f)  # doc hash, line number, field, rule: no content
        sys.exit(2)
    out.mkdir(parents=True, exist_ok=True)
    with open(out / "purchase-lines.jsonl", "w") as fh:
        for r in records:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    (out / "coverage.json").write_text(json.dumps(coverage, indent=1))
    by = {}
    for c in coverage:
        b = by.setdefault(c["layout"], [0, 0, 0])
        b[0] += 1; b[1] += c["items"]; b[2] += len(c["wrapped_or_unclaimed_lines"])
    print("GATE PASSED")
    for k, (d, n, u) in sorted(by.items()):
        print(f"  {k:20s} docs={d:3d} lines={n:5d} wrapped/unclaimed={u}")


if __name__ == "__main__":
    require()
    main(Path(sys.argv[1]), check_output(sys.argv[2]))
