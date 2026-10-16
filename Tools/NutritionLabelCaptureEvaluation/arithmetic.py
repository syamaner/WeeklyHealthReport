"""Arithmetic cross-checks (plan section 7). Pure; no I/O.

These checks inform but never authorise. A pass never upgrades a candidate, fills a
value or removes a warning. A failure adds a warning and blocks the route from
marking the table ready; it never rewrites a value. A check runs only when every
input is an exact printed value on the same basis; bounds and unknowns make it
`not_checkable`, never zero.
"""

from __future__ import annotations

import copy
from decimal import Decimal, InvalidOperation
from typing import Any

PASS = "pass"
FAIL = "fail"
NOT_CHECKABLE = "not_checkable"

# Pre-registered tolerances (decision 10).
TOLERANCES = {
    "uk": {"absolute_kcal": Decimal("15"), "relative": Decimal("0.10")},
    "taiwan": {"absolute_kcal": Decimal("15"), "relative": Decimal("0.10")},
    "us": {"absolute_kcal": Decimal("20"), "relative": Decimal("0.20")},
}
KJ_PER_KCAL = Decimal("4.184")
KJ_RATIO_RELATIVE = Decimal("0.02")
AMOUNT_BASES = ("per_100g", "per_100ml", "per_serving")
MUTATIONS = ("tenfold_serving", "basis_transposition", "bound_replaced_by_exact")


def number(text: Any) -> Decimal | None:
    if not isinstance(text, str) or not text:
        return None
    try:
        return Decimal(text.replace(",", "."))
    except InvalidOperation:
        return None


def decimals(text: str) -> int:
    cleaned = text.replace(",", ".")
    return len(cleaned.split(".", 1)[1]) if "." in cleaned else 0


def jurisdiction_for(table: dict[str, Any]) -> str:
    if table.get("jurisdiction") in TOLERANCES:
        return table["jurisdiction"]
    return "taiwan" if table.get("language") in ("zh-Hant", "mixed") else "uk"


def exact_value(cells: list[dict[str, Any]], nutrient: str, unit: str, basis: str) -> Decimal | None:
    """The value of the single exact printed cell for a nutrient on a basis.

    None when the cell is absent, repeated, unparseable or a bound: such inputs make a
    check `not_checkable`, never zero.
    """
    matching = [c for c in cells if c.get("nutrient") == nutrient and c.get("basis") == basis and c.get("canonical_unit") == unit]
    if len(matching) != 1 or matching[0].get("comparator", "=") != "=":
        return None
    return number(matching[0].get("decimal_text"))


def energy_check(table: dict[str, Any], basis: str) -> dict[str, Any]:
    cells = table.get("cells") or []
    jurisdiction = jurisdiction_for(table)
    kcal = exact_value(cells, "energy_kcal", "kcal", basis)
    p = exact_value(cells, "protein", "g", basis)
    f = exact_value(cells, "fat", "g", basis)
    c = exact_value(cells, "carbohydrate", "g", basis)
    fibre = exact_value(cells, "fibre", "g", basis)
    if kcal is None or p is None or f is None or c is None:
        return {"name": "energy", "basis": basis, "status": NOT_CHECKABLE}
    forms: list[tuple[str, Decimal]] = []
    if jurisdiction == "taiwan" and fibre is not None:
        forms.append(("taiwan", 4 * p + 4 * (c - fibre) + 2 * fibre + 9 * f))
    forms.append(("general", 4 * p + 4 * c + 9 * f))
    if jurisdiction == "uk" and fibre is not None:
        forms.append(("uk_fibre", 4 * p + 4 * c + 9 * f + 2 * fibre))
    tolerance = TOLERANCES[jurisdiction]
    allowed = max(tolerance["absolute_kcal"], tolerance["relative"] * kcal)
    results = [{"form": name, "computed_kcal": str(value), "difference": str(abs(value - kcal))} for name, value in forms]
    passed = any(abs(value - kcal) <= allowed for _, value in forms)
    return {
        "name": "energy",
        "basis": basis,
        "status": PASS if passed else FAIL,
        "printed_kcal": str(kcal),
        "allowed_difference": str(allowed),
        "forms": results,
    }


def kj_kcal_check(table: dict[str, Any], basis: str) -> dict[str, Any]:
    cells = table.get("cells") or []
    kj_value = exact_value(cells, "energy_kj", "kJ", basis)
    kcal_value = exact_value(cells, "energy_kcal", "kcal", basis)
    if kj_value is None or kcal_value is None:
        return {"name": "kj_kcal_ratio", "basis": basis, "status": NOT_CHECKABLE}
    if kcal_value == 0:
        status = PASS if kj_value == 0 else FAIL
        return {"name": "kj_kcal_ratio", "basis": basis, "status": status}
    ratio = kj_value / kcal_value
    ok = abs(ratio - KJ_PER_KCAL) <= KJ_PER_KCAL * KJ_RATIO_RELATIVE
    return {"name": "kj_kcal_ratio", "basis": basis, "status": PASS if ok else FAIL, "ratio": str(ratio)}


def _serving_quantity(table: dict[str, Any]) -> tuple[Decimal, str] | None:
    size = table.get("serving_size")
    if not isinstance(size, dict):
        return None
    value = number(size.get("decimal_text"))
    unit = size.get("canonical_unit")
    if value is None or unit not in ("g", "ml") or value <= 0:
        return None
    return value, unit


def scaling_checks(table: dict[str, Any]) -> list[dict[str, Any]]:
    """Per-serving equals per-100 x serving / 100 within printed rounding."""
    quantity = _serving_quantity(table)
    cells = table.get("cells") or []
    if quantity is None:
        return [{"name": "serving_scaling", "status": NOT_CHECKABLE}]
    grams, unit = quantity
    hundred_basis = "per_100g" if unit == "g" else "per_100ml"
    results = []
    for serving in cells:
        if serving.get("basis") != "per_serving" or serving.get("canonical_unit") == "%":
            continue
        partner = [
            c
            for c in cells
            if c.get("basis") == hundred_basis
            and c.get("nutrient") == serving.get("nutrient")
            and c.get("canonical_unit") == serving.get("canonical_unit")
            and c.get("parent_row_id") == serving.get("parent_row_id")
        ]
        if len(partner) != 1:
            continue
        hundred = partner[0]
        if serving.get("comparator", "=") != "=" or hundred.get("comparator", "=") != "=":
            continue
        s, h = number(serving.get("decimal_text")), number(hundred.get("decimal_text"))
        if s is None or h is None:
            continue
        expected = h * grams / 100
        slack = (
            Decimal("0.5") * Decimal(10) ** -decimals(serving["decimal_text"])
            + Decimal("0.5") * Decimal(10) ** -decimals(hundred["decimal_text"]) * grams / 100
        )
        ok = abs(s - expected) <= slack + Decimal("1e-9")
        results.append(
            {
                "name": "serving_scaling",
                "nutrient": serving.get("nutrient"),
                "status": PASS if ok else FAIL,
                "per_serving": str(s),
                "expected": str(expected),
                "slack": str(slack),
            }
        )
    return results or [{"name": "serving_scaling", "status": NOT_CHECKABLE}]


def subrow_checks(table: dict[str, Any], basis: str) -> list[dict[str, Any]]:
    cells = table.get("cells") or []
    pairs = [("saturates", "fat"), ("trans_fat", "fat"), ("sugars", "carbohydrate")]
    if jurisdiction_for(table) == "taiwan":
        pairs.append(("fibre", "carbohydrate"))
    results = []
    for child, parent in pairs:
        a, b = exact_value(cells, child, "g", basis), exact_value(cells, parent, "g", basis)
        if a is not None and b is not None:
            ok = a <= b
            results.append({"name": "subrow_not_above_parent", "basis": basis, "child": child, "status": PASS if ok else FAIL})
    return results


def bound_consistency_checks(table: dict[str, Any]) -> list[dict[str, Any]]:
    """A nutrient printed as a bound in one amount column and exact in another is flagged."""
    cells = [c for c in table.get("cells") or [] if c.get("basis") in AMOUNT_BASES]
    results = []
    keys = {(c.get("nutrient"), c.get("parent_row_id"), c.get("canonical_unit")) for c in cells}
    for key in sorted(keys, key=str):
        comparators = {
            c.get("comparator", "=") for c in cells if (c.get("nutrient"), c.get("parent_row_id"), c.get("canonical_unit")) == key
        }
        if len(comparators) > 1:
            results.append({"name": "bound_consistency", "nutrient": key[0], "status": FAIL})
    return results


def net_weight_check(table: dict[str, Any], net_quantity: Decimal | None) -> dict[str, Any]:
    quantity = _serving_quantity(table)
    per_pack = table.get("servings_per_pack")
    if net_quantity is None or quantity is None or not isinstance(per_pack, dict) or per_pack.get("approximate"):
        return {"name": "net_weight", "status": NOT_CHECKABLE}
    count = number(per_pack.get("decimal_text"))
    if count is None:
        return {"name": "net_weight", "status": NOT_CHECKABLE}
    ok = abs(count * quantity[0] - net_quantity) <= quantity[0]
    return {"name": "net_weight", "status": PASS if ok else FAIL}


def check_table(table: dict[str, Any], net_quantity: Decimal | None = None) -> dict[str, Any]:
    """Run every informing check. Overall: fail if any check fails, pass if any passes."""
    if table.get("declined"):
        return {"status": NOT_CHECKABLE, "checks": [], "warnings": []}
    bases = sorted({c.get("basis") for c in table.get("cells") or [] if c.get("basis") in AMOUNT_BASES})
    checks: list[dict[str, Any]] = []
    for basis in bases:
        checks.append(energy_check(table, basis))
        checks.append(kj_kcal_check(table, basis))
        checks.extend(subrow_checks(table, basis))
    checks.extend(scaling_checks(table))
    checks.extend(bound_consistency_checks(table))
    checks.append(net_weight_check(table, net_quantity))
    statuses = {check["status"] for check in checks}
    status = FAIL if FAIL in statuses else PASS if PASS in statuses else NOT_CHECKABLE
    warnings = []
    if any(c["name"] == "energy" and c["status"] == FAIL for c in checks):
        warnings.append("energy does not match the macronutrients")
    if any(c["name"] != "energy" and c["status"] == FAIL for c in checks):
        warnings.append("printed values are not arithmetically consistent")
    return {"status": status, "checks": checks, "warnings": warnings}


def energy_status(table: dict[str, Any]) -> str:
    """The energy cross-check alone (reported, never gating)."""
    statuses = {c["status"] for c in check_table(table)["checks"] if c["name"] == "energy"}
    return FAIL if FAIL in statuses else PASS if PASS in statuses else NOT_CHECKABLE


# --- Frozen mutations -------------------------------------------------------


def mutate(table: dict[str, Any], mutation: str) -> dict[str, Any] | None:
    """Apply one frozen mutation to verified truth, or None when not applicable."""
    mutated = copy.deepcopy(table)
    cells = mutated.get("cells") or []
    if mutation == "tenfold_serving":
        for cell in cells:
            if cell.get("basis") == "per_serving" and cell.get("comparator", "=") == "=" and cell.get("canonical_unit") != "%":
                value = number(cell.get("decimal_text"))
                if value:
                    cell["decimal_text"] = str(value * 10)
                    cell["printed_text"] = cell["decimal_text"] + cell.get("unit", "")
                    return mutated
        return None
    if mutation == "basis_transposition":
        bases = {c.get("basis") for c in cells}
        quantity = _serving_quantity(mutated)
        if not {"per_serving", "per_100g"} <= bases or quantity is None or quantity[0] == 100:
            return None
        swap = {"per_serving": "per_100g", "per_100g": "per_serving"}
        for cell in cells:
            if cell.get("basis") in swap:
                cell["basis"] = swap[cell["basis"]]
        return mutated
    if mutation == "bound_replaced_by_exact":
        for cell in cells:
            if cell.get("comparator") in ("<", "<="):
                cell["comparator"] = "="
                cell["printed_text"] = cell.get("decimal_text", "") + cell.get("unit", "")
                return mutated
        return None
    raise ValueError(f"unknown mutation {mutation}")


def mutation_detection(tables: list[dict[str, Any]]) -> dict[str, Any]:
    """Detection rate of the three frozen mutations over truth tables whose originals pass."""
    outcome: dict[str, Any] = {}
    for mutation in MUTATIONS:
        applicable = detected = 0
        for table in tables:
            if check_table(table)["status"] == FAIL:
                continue
            mutated = mutate(table, mutation)
            if mutated is None:
                continue
            applicable += 1
            detected += check_table(mutated)["status"] == FAIL
        outcome[mutation] = {"applicable": applicable, "detected": detected}
    total = sum(v["applicable"] for v in outcome.values())
    outcome["overall"] = {"applicable": total, "detected": sum(v["detected"] for k, v in outcome.items() if k in MUTATIONS)}
    return outcome
