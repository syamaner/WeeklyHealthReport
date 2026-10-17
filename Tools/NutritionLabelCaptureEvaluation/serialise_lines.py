"""Route B serialiser: Vision lines with geometry to text for the shared parser. Pure.

Input is one image result from `vision_v3.swift` (lines with top-left normalised boxes
and per-token boxes). Output is plain text in the shape the shared Swift parser
(`NutritionLabelParsing`) reads: serving lines, one header line with the column headers
in left-to-right order, then one line per row label with its values in column order.

Binding follows plan section 2.1: by column header and order within a column, not by
nearest vertical position alone. Each value column is first bound at its printed
position (one value per row, within a tolerance of the row pitch). A column that leaves
values unbound may take one whole-column vertical offset, but only when that offset
binds every one of its values to exactly the rows a neighbouring column binds completely
at its printed position; so a column printed about one row lower than its neighbour (the
muesli stress case) binds row by row. A column with no complete neighbour may take the
smallest offset that binds all of its values one-to-one. A missed row label leaves more
values than rows, so it usually blocks the shift; when it does not, the parser and the
arithmetic checks are the remaining guards (see the false-ready results). Energy values
may share one energy row when their units differ (kJ and kcal stacked in one cell).

The serialiser never rewrites recognised characters, never fills a missing value and
never drops a value it cannot bind: an unbound value is written on its own line, which
the parser treats as a count mismatch and declines. That keeps failure loud.
"""

from __future__ import annotations

import re
import statistics
from dataclasses import dataclass, field
from typing import Any

SERIALISER_VERSION = "label-capture-serialiser-v1"

UNITS = r"kJ|kj|KJ|Kj|kcal|Kcal|KCAL|kCal|Cal|cal|mcg|mg|µg|μg|mL|ml|g|%|大卡|千卡|公克|毫克|微克|毫升|克"
VALUE = re.compile(rf"^(?:less than|<=|≤|＜|<|少於)?\s*\d+(?:[.,]\d+)?\s*(?:{UNITS})?$")
NUMBER = re.compile(r"^(?:less than|<=|≤|＜|<|少於)?\s*\d+(?:[.,]\d+)?$")
UNIT_ONLY = re.compile(rf"^(?:{UNITS})$")
COMPARATOR_ONLY = re.compile(r"^(?:<=|≤|＜|<|少於)$")
ENERGY_UNIT = re.compile(r"(kJ|kj|KJ|Kj|kcal|Kcal|KCAL|kCal|Cal|cal|大卡|千卡)$")
ENERGY_LABEL = re.compile(r"(?i)^(energy|calories|熱量)\b|^熱量")
HEADER = re.compile(r"(?i)\bper\b|每份|每\s*100|每日參考值|%\s*RI|\bRI\b|reference intake|%\s*DV|daily value|\bNRV\b")
HEADER_BOUNDARY = re.compile(r"(?i)(?=\bper\b|%\s*RI|%\s*DV|每份|每\s*100|每日參考值)")
SERVING = re.compile(r"(?i)^(serving\s+size|portion\s+size|每一?份量|servings?\s+per|本包裝含|this\s+pack\s+contains|pack\s+contains)")
TITLE = re.compile(r"(?i)^(營養標示|營養成分|nutrition(al)?( information| facts| declaration)?|typical values?)[:：]?$")
INDENT_THRESHOLD = 0.015


@dataclass
class Fragment:
    text: str
    x0: float
    x1: float
    y: float
    height: float

    @property
    def cx(self) -> float:
        return (self.x0 + self.x1) / 2


@dataclass
class Row:
    label: Fragment
    values: list[tuple[int, Fragment]] = field(default_factory=list)


def _box(item: dict[str, Any]) -> tuple[float, float, float, float]:
    box = item["box"]
    return float(box["x"]), float(box["x"]) + float(box["width"]), float(box["y"]) + float(box["height"]) / 2, float(box["height"])


def _fragment(tokens: list[dict[str, Any]], joiner: str = " ") -> Fragment:
    boxes = [_box(t) for t in tokens]
    text = ""
    for token in tokens:
        piece = token["text"]
        if text and (_is_han(text[-1]) or _is_han(piece[0]) or joiner == ""):
            text += piece
        else:
            text = f"{text}{joiner}{piece}" if text else piece
    return Fragment(
        text, min(b[0] for b in boxes), max(b[1] for b in boxes), statistics.median(b[2] for b in boxes), max(b[3] for b in boxes)
    )


def _is_han(char: str) -> bool:
    return "一" <= char <= "鿿" or "㐀" <= char <= "䶿"


def split_line(line: dict[str, Any]) -> tuple[list[Fragment], list[Fragment]]:
    """Split one recognised line into text fragments and value fragments."""
    tokens = [t for t in line.get("tokens") or [] if t.get("text")]
    if not tokens:
        tokens = [{"text": line["text"], "box": line["box"]}]
    tokens = [piece for token in tokens for piece in _split_slashed(token)]
    merged: list[list[dict[str, Any]]] = []
    kinds: list[str] = []
    for token in tokens:
        text = token["text"]
        if merged and kinds[-1] == "comparator" and NUMBER.match(text):
            merged[-1].append(token)
            kinds[-1] = "value"
        elif merged and kinds[-1] == "value" and NUMBER.match(_joined(merged[-1])) and UNIT_ONLY.match(text):
            merged[-1].append(token)
        elif VALUE.match(text):
            merged.append([token])
            kinds.append("value")
        elif COMPARATOR_ONLY.match(text):
            merged.append([token])
            kinds.append("comparator")
        else:
            if merged and kinds[-1] == "text":
                merged[-1].append(token)
            else:
                merged.append([token])
                kinds.append("text")
    texts, values = [], []
    for group, kind in zip(merged, kinds, strict=True):
        if kind == "value":
            values.append(_fragment(group, joiner=""))
        else:
            texts.append(_fragment(group))
    return texts, values


def _split_slashed(token: dict[str, Any]) -> list[dict[str, Any]]:
    """`1642kJ/388kcal` is two values; split it, sharing the box width by character count."""
    parts = token["text"].split("/")
    if len(parts) < 2 or not all(VALUE.match(part) for part in parts):
        return [token]
    box, total = token["box"], len(token["text"])
    pieces, offset = [], 0
    for part in parts:
        width = float(box["width"]) * len(part) / total
        x = float(box["x"]) + float(box["width"]) * offset / total
        pieces.append({"text": part, "box": {**box, "x": x, "width": width}})
        offset += len(part) + 1
    return pieces


def _joined(tokens: list[dict[str, Any]]) -> str:
    return "".join(t["text"] for t in tokens)


def header_segments(line: dict[str, Any]) -> list[Fragment]:
    """Column headers on one recognised line, each with the span of its tokens."""
    text = line["text"]
    tokens = [t for t in line.get("tokens") or [] if t.get("text")] or [{"text": text, "box": line["box"]}]
    starts = [m.start() for m in HEADER_BOUNDARY.finditer(text) if m.start() > 0]
    # Assign each token to a segment by its character offset in the line.
    offsets, cursor = [], 0
    for token in tokens:
        found = text.find(token["text"], cursor)
        offsets.append(found if found >= 0 else cursor)
        cursor = (found if found >= 0 else cursor) + len(token["text"])
    bounds = [0, *starts, len(text) + 1]
    segments = []
    for start, end in zip(bounds, bounds[1:], strict=False):
        group = [t for t, o in zip(tokens, offsets, strict=True) if start <= o < end]
        if not group:
            continue
        fragment = _fragment(group)
        fragment.text = text[start:end].strip() if end <= len(text) else text[start:].strip()
        if HEADER.search(fragment.text):
            segments.append(fragment)
    return segments


AMOUNT_HEADER = re.compile(r"(?i)per\s*100|每\s*100|每份|\bper\b")
REFERENCE_HEADER = re.compile(r"(?i)%\s*RI|\bRI\b|reference intake|%\s*DV|daily value|\bNRV\b|每日參考值")


def _header_band(headers: list[Fragment]) -> list[Fragment]:
    """Keep the column headers on the table's header row; drop footnotes such as
    `*Reference intake of an average adult` printed elsewhere on the panel."""
    kept = [h for h in headers if not h.text.startswith(("*", "＊", "†"))]
    anchors = [h for h in kept if AMOUNT_HEADER.search(h.text) and not REFERENCE_HEADER.search(h.text)]
    if not anchors:
        return kept
    anchor = min(anchors, key=lambda h: h.y)
    band = 1.5 * max(statistics.median(h.height for h in kept), 1e-6)
    return [h for h in kept if abs(h.y - anchor.y) <= band]


def _stack_headers(headers: list[Fragment], labels: list[Fragment], values: list[Fragment]) -> tuple[list[Fragment], list[Fragment]]:
    """Join a header printed over two lines (`Per` above `100g`, `Per` above `2 Sausages`).

    A fragment directly below a header, overlapping it horizontally and within about one
    and a half line heights, becomes part of that header's text and leaves the table body.
    """
    used: set[int] = set()
    for header in sorted(headers, key=lambda h: h.y):
        below = [
            f
            for f in (*labels, *values)
            if id(f) not in used
            and 0 < f.y - header.y <= 1.8 * header.height
            and min(f.x1, header.x1 + 0.03) - max(f.x0, header.x0 - 0.03) > 0
        ]
        if not below:
            continue
        nearest = min(below, key=lambda f: f.y)
        if _is_value_row_start(nearest, labels):
            continue
        # Grow along the same printed line while the gap stays within about one glyph.
        same_line = [nearest]
        level = [f for f in (*labels, *values) if id(f) not in used and f is not nearest and abs(f.y - nearest.y) < 0.3 * nearest.height]
        grown = True
        while grown:
            grown = False
            x0, x1 = min(f.x0 for f in same_line), max(f.x1 for f in same_line)
            for f in level:
                if f not in same_line and (0 <= f.x0 - x1 <= 0.6 * f.height or 0 <= x0 - f.x1 <= 0.6 * f.height):
                    same_line.append(f)
                    grown = True
        same_line.sort(key=lambda f: f.x0)
        header.text = " ".join([header.text, *(f.text for f in same_line)])
        header.x0, header.x1 = min(header.x0, *(f.x0 for f in same_line)), max(header.x1, *(f.x1 for f in same_line))
        used.update(id(f) for f in same_line)
    return [f for f in labels if id(f) not in used], [f for f in values if id(f) not in used]


def _is_value_row_start(fragment: Fragment, labels: list[Fragment]) -> bool:
    """A fragment level with a row label to its left is table body, not a header line."""
    return any(abs(label.y - fragment.y) < 0.5 * label.height and label.x1 < fragment.x0 for label in labels if label is not fragment)


def _skew(headers: list[Fragment]) -> float:
    """Vertical drift per unit of width (a tilted photo), from the header row only.

    The two amount headers furthest apart on the topmost header row give the slope;
    with fewer than two such headers it is 0. (Token boxes within one recognised line
    were tried on development data and were too noisy: descenders move box centres.)
    Only positions change; no character is rewritten.
    """
    amounts = sorted((h for h in headers if AMOUNT_HEADER.search(h.text) and not h.text.startswith(("*", "＊"))), key=lambda h: h.y)
    if len(amounts) < 2:
        return 0.0
    top = [h for h in amounts if h.y - amounts[0].y <= 2.5 * h.height]
    left, right = min(top, key=lambda h: h.cx), max(top, key=lambda h: h.cx)
    if right.cx - left.cx < 0.08:
        return 0.0
    slope = (right.y - left.y) / (right.cx - left.cx)
    return slope if abs(slope) <= 0.3 else 0.0


def _drift(column: list[Fragment], labels: list[Fragment], pitch: float) -> float:
    if not labels or not column:
        return 0.0
    residuals = [min((v.y - label.y for label in labels), key=abs) for v in column]
    median = statistics.median(residuals)
    return median if abs(median) < pitch / 3 else 0.0


def _pitch(labels: list[Fragment]) -> float:
    gaps = [b.y - a.y for a, b in zip(labels, labels[1:], strict=False) if b.y - a.y > 0]
    if gaps:
        return statistics.median(gaps)
    return statistics.median(f.height for f in labels) * 1.5 if labels else 0.05


def _assign(column: list[Fragment], labels: list[Fragment], shift: float, tolerance: float) -> tuple[dict[int, list[int]], float]:
    """Greedy one-to-one binding of column values to labels after a vertical shift."""
    pairs = []
    for vi, value in enumerate(column):
        for li, label in enumerate(labels):
            distance = abs(value.y - shift - label.y)
            if distance <= tolerance:
                pairs.append((distance, vi, li))
    pairs.sort()
    taken_values: set[int] = set()
    by_label: dict[int, list[int]] = {}
    total = 0.0
    for distance, vi, li in pairs:
        if vi in taken_values:
            continue
        existing = by_label.get(li, [])
        if existing:
            # A second value may share an energy row only with a different energy unit.
            units = {_energy_unit(column[i].text) for i in existing}
            unit = _energy_unit(column[vi].text)
            if not (ENERGY_LABEL.search(labels[li].text) and unit and None not in units and unit not in units):
                continue
        by_label.setdefault(li, []).append(vi)
        taken_values.add(vi)
        total += distance
    return by_label, total


def _energy_unit(text: str) -> str | None:
    match = ENERGY_UNIT.search(text)
    return match.group(1).lower() if match else None


def _column_clusters(values: list[Fragment], headers: list[Fragment]) -> list[list[Fragment]]:
    """Group values into columns: by nearest header centre when headers exist, else by x gaps."""
    if headers:
        columns: list[list[Fragment]] = [[] for _ in headers]
        for value in values:
            index = min(range(len(headers)), key=lambda i: abs(headers[i].cx - value.cx))
            columns[index].append(value)
        return columns
    ordered = sorted(values, key=lambda v: v.cx)
    clusters: list[list[Fragment]] = []
    for value in ordered:
        if clusters and value.cx - statistics.mean(v.cx for v in clusters[-1]) < 0.08:
            clusters[-1].append(value)
        else:
            clusters.append([value])
    return clusters


def serialise(result: dict[str, Any]) -> dict[str, Any]:
    """Text for the parser plus a small binding report (counts only, no image content)."""
    lines = sorted(result.get("lines") or [], key=lambda line: (_box(line)[2], _box(line)[0]))
    preamble: list[str] = []
    headers: list[Fragment] = []
    labels: list[Fragment] = []
    values: list[Fragment] = []
    for line in lines:
        text = line["text"].strip()
        if not text:
            continue
        if SERVING.match(text):
            preamble.append(text)
            continue
        if TITLE.match(text):
            preamble.append(text)
            continue
        if HEADER.search(text) and not VALUE.match(text):
            segments = header_segments(line)
            if segments:
                headers.extend(segments)
                continue
        texts, found = split_line(line)
        labels.extend(t for t in texts if not t.text.startswith(("*", "＊", "†")))
        values.extend(found)
    slope = _skew(headers)
    for fragment in (*headers, *labels, *values):
        fragment.y -= slope * (fragment.cx - 0.5)
    headers = _header_band(headers)
    labels, values = _stack_headers(headers, labels, values)
    headers.sort(key=lambda h: h.cx)
    header_y = min((h.y for h in headers), default=None)
    if header_y is not None:
        labels = [label for label in labels if label.y > header_y - 0.5 * label.height]
        values = [value for value in values if value.y > header_y]
    first_value_x = min((v.x0 for v in values), default=1.0)
    labels = sorted((label for label in labels if label.cx < first_value_x), key=lambda label: label.y)
    columns = [sorted(c, key=lambda v: v.y) for c in _column_clusters(values, headers)]
    columns = [c for c in columns if c]
    pitch = _pitch(labels)
    tolerance = 0.45 * pitch
    rows = [Row(label) for label in labels]
    unbound: list[Fragment] = []
    shifts = []
    # Shift 0 first: nearest position within tolerance, one value per row.
    # A small residual drift (perspective left after deskew) is removed per column: the
    # median distance from each value to its nearest row label, when under a third of a row.
    drift = [_drift(column, labels, pitch) for column in columns]
    at_zero = [_assign(column, labels, d, tolerance)[0] for column, d in zip(columns, drift, strict=True)]
    complete = [
        frozenset(by_label) for column, by_label in zip(columns, at_zero, strict=True) if sum(map(len, by_label.values())) == len(column)
    ]
    for ci, column in enumerate(columns):
        by_label, shift = at_zero[ci], drift[ci]
        if sum(map(len, by_label.values())) < len(column):
            # A whole-column offset must bind every value of this column one-to-one. It is
            # taken when it reproduces exactly the rows a neighbouring column binds
            # completely at its printed position (order within a column, anchored), or, for
            # a column with no complete neighbour, when it is the smallest such offset.
            # Otherwise the column stays put and any unbound value surfaces as a count
            # mismatch, so a missed row label (fewer labels than values) never shifts a column.
            candidates = {v.y - label.y for v in column for label in labels if 0 < abs(v.y - label.y) <= 1.5 * pitch}
            for candidate in sorted(candidates, key=abs):
                trial, _ = _assign(column, labels, candidate, tolerance)
                if sum(map(len, trial.values())) != len(column):
                    continue
                if (complete and frozenset(trial) in complete) or not complete:
                    by_label, shift = trial, candidate
                    break
        shifts.append(round(shift / pitch, 2) if pitch else 0.0)
        bound = set()
        for li, indices in by_label.items():
            for vi in indices:
                rows[li].values.append((ci, column[vi]))
                bound.add(vi)
        unbound.extend(v for vi, v in enumerate(column) if vi not in bound)
    left = statistics.median(label.x0 for label in labels) if labels else 0.0
    out = list(preamble)
    if headers:
        out.append("\t".join(h.text for h in headers))
    for row in rows:
        indent = "  " if row.label.x0 - left > INDENT_THRESHOLD else ""
        ordered = [v.text for _, v in sorted(row.values, key=lambda item: (item[0], item[1].y))]
        out.append("\t".join([indent + row.label.text, *ordered]))
    for value in sorted(unbound, key=lambda v: v.y):
        out.append(value.text)
    return {
        "serialiser_version": SERIALISER_VERSION,
        "text": "\n".join(out),
        "report": {
            "headers": len(headers),
            "labels": len(labels),
            "columns": len(columns),
            "values": sum(len(c) for c in columns),
            "unbound_values": len(unbound),
            "column_shift_in_rows": shifts,
            "skew": round(slope, 4),
        },
    }
