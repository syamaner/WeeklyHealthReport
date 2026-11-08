"""Part A counts from a sample and a completed review sheet. Pure.

Rules (plan sections 3.2 to 3.4 and 6):
- A1 and A5 are a census; a skipped entry is never replaced, and more than 6 skipped A1 entries
  fails both A1 bars.
- A2 to A4 take rows in sheet order until the quota is checked; a skipped row is replaced by the
  next row; a verdict after the quota is reached, or a gap before it, is refused; a stratum that runs
  out of rows before its quota fails its bar (fail closed).
- Checked values are `agrees` plus `differs`; `not_on_pack` and `missing_in_entry` are excluded and
  reported as their own counts. An empty stratum is not assessed.
"""
from bars import A1_SKIP_LIMIT, judge
from formats import NUTRIENTS, FormatError
from stats import wilson


def _measure(count, n, bar=None, forced_fail=False):
    m = {"count": count, "of": n, "interval": list(wilson(count, n)) if n else None}
    if bar:
        m.update(judge(bar, count, n, forced_fail))
    return m


def _label_stratum(rows, s):
    rs = [r for r in rows if r["stratum"] == s]
    if any(not r["product"] for r in rs):
        raise FormatError(f"review sheet: {s} has rows without a product verdict")
    checked = [r for r in rs if r["product"] != "skipped"]
    skipped = len(rs) - len(checked)
    wrong = sum(1 for r in checked if r["product"] in ("wrong_product", "wrong_variant"))
    tokens = [r[k] for r in checked for k in NUTRIENTS]
    agree, differ = tokens.count("agrees"), tokens.count("differs")
    return {"entries": len(rs), "checked": len(checked), "skipped": skipped, "wrong": wrong,
            "wrong_product": sum(1 for r in checked if r["product"] == "wrong_product"),
            "wrong_variant": sum(1 for r in checked if r["product"] == "wrong_variant"),
            "values_checked": agree + differ, "differs": differ,
            "not_on_pack": tokens.count("not_on_pack"), "missing_in_entry": tokens.count("missing_in_entry")}


def _quota_stratum(rows, s, quota):
    rs = [r for r in rows if r["stratum"] == s]
    checked, skipped, done = [], 0, False
    for r in rs:
        if done:
            if r["verdict"]:
                raise FormatError(f"review sheet: {s} has a verdict after its quota was reached")
            continue
        if not r["verdict"]:
            raise FormatError(f"review sheet: {s} has an empty row before its quota was reached")
        if r["verdict"] == "skipped":
            skipped += 1
        else:
            checked.append(r["verdict"])
        done = len(checked) >= quota
    return checked, skipped, len(checked) < quota


def score(sample: dict, sheet_rows):
    expected = [(e["entry_id"], e["stratum"]) for e in sample["entries"]]
    for s in ("A2", "A3", "A4"):
        expected += [(i, s) for i in sample["replacements"].get(s, [])]
    got = [(r["entry_id"], r["stratum"]) for r in sheet_rows]
    if got != expected:
        raise FormatError("review sheet: rows differ from the sealed sample (each entry once, in sample order)")

    a1, a5 = _label_stratum(sheet_rows, "A1"), _label_stratum(sheet_rows, "A5")
    too_many_skips = a1["skipped"] > A1_SKIP_LIMIT
    out = {
        "a1_entries": a1["entries"], "a1_skipped": a1["skipped"], "a1_skip_limit_exceeded": too_many_skips,
        "a1_wrong_product_or_variant": _measure(a1["wrong"], a1["checked"], "a1_wrong_product_or_variant", too_many_skips),
        "a1_wrong_product": a1["wrong_product"], "a1_wrong_variant": a1["wrong_variant"],
        "a1_nutrient_disagreements": _measure(a1["differs"], a1["values_checked"], "a1_nutrient_disagreements", too_many_skips),
        "a1_not_on_pack": a1["not_on_pack"], "a1_missing_in_entry": a1["missing_in_entry"],
        "a5_entries": a5["entries"], "a5_skipped": a5["skipped"],
        "a5_nutrient_disagreements": _measure(a5["differs"], a5["values_checked"], "a5_nutrient_disagreements"),
        "a5_not_on_pack": a5["not_on_pack"], "a5_missing_in_entry": a5["missing_in_entry"],
    }
    for s, bar, bad in (("A2", "a2_different_food_or_other_state", {"same_food_other_state", "different_food"}),
                        ("A3", "a3_misleading", {"misleading_close", "misleading_other_state"}),
                        ("A4", None, {"match_missed"})):
        checked, skipped, short = _quota_stratum(sheet_rows, s, sample["quotas"].get(s, 0))
        k = s.lower()
        name = {"A2": "a2_different_food_or_other_state", "A3": "a3_misleading", "A4": "a4_match_missed"}[s]
        out[name] = _measure(sum(1 for v in checked if v in bad), len(checked), bar, forced_fail=bool(bar) and short)
        out[f"{k}_skipped"] = skipped
        out[f"{k}_short_of_quota"] = short
        if s == "A2":
            out["a2_other_state"] = checked.count("same_food_other_state")
            out["a2_different_food"] = checked.count("different_food")
        if s == "A3":
            out["a3_misleading_close"] = checked.count("misleading_close")
            out["a3_misleading_other_state"] = checked.count("misleading_other_state")
    return out
