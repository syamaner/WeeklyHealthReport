"""The two Part A bar sets for the v2 review, as data, and their own judge. Pure.

Design: docs/personal-food-database-review-v2-design.md, sections 3 and 4. `v1_accepted` is the
superseded table of plan section 6 (accepted 7 November 2026); `v2_proposed` is the table of
record (decision 9, 8 November 2026). The choice is `part_a_bars` in freeze-v2.json, not code.

Rounding is the rule of bars.py: "at most p per cent" allows the largest whole count within it
(round down) on the actual denominator; fixed counts hold whatever the sample size. A measure with
a zero denominator is not assessed. A measure whose stratum has an unresolved entry or value is not
final: it never passes and never fails (`passes` is None).
"""
from fractions import Fraction
import math

BAR_SETS = ("v1_accepted", "v2_proposed")

BARS = {
    "v1_accepted": {
        # name: (rule, value); rule "max_count", "max_share" or "not_assessable"
        "a1_wrong_product_or_variant": ("max_count", 2),
        "a1_nutrient_disagreements": ("not_assessable", None),  # compares with a pack, out of scope
        "a2_different_food_or_other_state": ("max_count", 2),
        "a3_misleading": ("max_count", 4),
        "a5_nutrient_disagreements": ("not_assessable", None),
    },
    "v2_proposed": {
        "a1_wrong_identity_state_or_variety": ("max_count", 2),
        "a1_value_evidence_errors": ("max_share", Fraction(3, 100)),
        "a2_different_food_or_other_state": ("max_count", 2),
        "a3_misleading": ("max_count", 4),
        "a5_value_evidence_errors": ("max_share", Fraction(3, 100)),
    },
}


class BarsError(ValueError):
    pass


def _bar(bar_set: str, name: str):
    if bar_set not in BARS or name not in BARS[bar_set]:
        raise BarsError("unknown bar set or bar")
    rule, value = BARS[bar_set][name]
    if rule == "not_assessable":
        raise BarsError(f"{name} is not assessable under {bar_set}")
    return rule, value


def not_assessable(bar_set: str):
    """The bars of a set that this rubric cannot score, sorted."""
    return sorted(n for n, (rule, _) in BARS[bar_set].items() if rule == "not_assessable")


def allowed(bar_set: str, name: str, n: int) -> int:
    rule, value = _bar(bar_set, name)
    return value if rule == "max_count" else math.floor(value * n)


def judge(bar_set: str, name: str, count: int, n: int, unresolved: bool = False) -> dict:
    """{allowed, passes}: passes is None when n is 0 (not assessed) or when unresolved (not final)."""
    _bar(bar_set, name)
    if n == 0:
        return {"allowed": None, "passes": None}
    a = allowed(bar_set, name, n)
    if unresolved:
        return {"allowed": a, "passes": None}
    return {"allowed": a, "passes": bool(count <= a)}
