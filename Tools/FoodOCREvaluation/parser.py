"""Pure printed-panel token parsing. No result may authorize persistence."""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation

SPACE = re.compile(r"\s+")
VALUE = re.compile(r"^\s*(?P<comparator><=|<|≤)?\s*(?P<number>\d+(?:[.,]\d+)?)\s*(?P<unit>kcal|kj|mg|µg|ug|g|ml|%)?\s*$", re.IGNORECASE)


@dataclass(frozen=True)
class ParsedValue:
    comparator: str | None
    decimal_text: str
    unit: str | None
    numeric_value: Decimal
    persistence_authorized: bool = False


def normalize_label(value: str) -> str:
    return SPACE.sub(" ", unicodedata.normalize("NFC", value).strip()).casefold()


def parse_value(value: str) -> ParsedValue | None:
    match = VALUE.fullmatch(unicodedata.normalize("NFC", value))
    if not match:
        return None
    decimal_text = match.group("number").replace(",", ".")
    try:
        number = Decimal(decimal_text)
    except InvalidOperation:
        return None
    comparator = match.group("comparator")
    if comparator == "≤":
        comparator = "<="
    unit = match.group("unit")
    return ParsedValue(
        comparator=comparator,
        decimal_text=decimal_text,
        unit=unit.casefold().replace("ug", "µg") if unit else None,
        numeric_value=number,
    )


def classify_basis(value: str) -> str | None:
    text = normalize_label(value).replace(" ", "")
    if re.search(r"per100g\b", text):
        return "per_100g"
    if re.search(r"per100ml\b", text):
        return "per_100ml"
    if "%ri" in text or (text.startswith("%") and "ri" in text) or "referenceintake" in text:
        return "reference_intake"
    if (
        text.startswith("perserving")
        or text.startswith("perportion")
        or text.startswith("perpack")
        or (text.startswith("per") and any(word in text for word in ("serving", "portion", "pack")))
    ):
        return "per_serving"
    return None


def interval_for(parsed: ParsedValue) -> tuple[Decimal, Decimal | None]:
    if parsed.comparator in ("<", "<="):
        return Decimal(0), parsed.numeric_value
    places = max(0, -parsed.numeric_value.as_tuple().exponent)
    half_step = Decimal(5).scaleb(-(places + 1))
    return max(Decimal(0), parsed.numeric_value - half_step), parsed.numeric_value + half_step
