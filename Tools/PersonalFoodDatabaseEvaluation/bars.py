"""The accepted bars of plan section 6, as data, and the judge. Pure.

A bar is judged on the observed count; the interval is informational. "At most p per cent" allows
the largest whole count within it (round down), "at least p per cent" needs the smallest whole count
at or above it (round up), both on the actual denominator. A2 and A3 use fixed allowed counts
whatever their sample size (decision 7). A measure with a zero denominator is not assessed.
"""
from fractions import Fraction
import math

A1_SKIP_LIMIT = 6

BARS = {
    # name: (rule, value)  rule is "max_count", "max_share" or "min_share"
    "a1_wrong_product_or_variant": ("max_count", 2),
    "a1_nutrient_disagreements": ("max_share", Fraction(3, 100)),
    "a2_different_food_or_other_state": ("max_count", 2),
    "a3_misleading": ("max_count", 4),
    "a5_nutrient_disagreements": ("max_share", Fraction(3, 100)),
    "b_wrong_entry_first": ("max_share", Fraction(3, 100)),
    "b_negative_false_hits": ("max_share", Fraction(5, 100)),
    "b_top1_acceptable": ("min_share", Fraction(85, 100)),
}


def allowed(name: str, n: int):
    """The allowed count for a bar at denominator n (a maximum, or for min_share a minimum)."""
    rule, value = BARS[name]
    if rule == "max_count":
        return value
    if rule == "max_share":
        return math.floor(value * n)
    return math.ceil(value * n)


def judge(name: str, count: int, n: int, forced_fail: bool = False):
    """{allowed, passes}; a forced failure always fails, otherwise passes is None (not assessed) when n is 0."""
    if forced_fail:
        return {"allowed": allowed(name, n) if n else None, "passes": False}
    if n == 0:
        return {"allowed": None, "passes": None}
    a = allowed(name, n)
    rule = BARS[name][0]
    ok = count >= a if rule == "min_share" else count <= a
    return {"allowed": a, "passes": bool(ok)}
