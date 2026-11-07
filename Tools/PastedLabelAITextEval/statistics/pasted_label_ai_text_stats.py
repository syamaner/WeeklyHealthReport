#!/usr/bin/env python3
"""Statistics for the pasted label AI text evaluation (docs/pasted-label-ai-text-v1.md 5.2 item 4,
5.2.1 and 5.3; #416 A2).

Reads promptfoo's exported results (``promptfoo eval --output results.json``), whose per-label
counts come from the shipped Swift scorer through ``assert.js`` (``namedScores``) and whose
cost and latency come from ``PastedLabelAITextEval send`` (the provider's output). promptfoo's own
pass rates are never used as results. Run with ``python3 -I``; standard library only.

    python3 -I pasted_label_ai_text_stats.py summary RESULTS.json [--cases DIR] [--seed N] [--resamples N]
    python3 -I pasted_label_ai_text_stats.py compare RESULTS.json CELL_A CELL_B [--seed N] [--resamples N]

A cell is one provider label and one prompt label (``<provider>|<prompt>``).

Intervals (95%):
- label-level proportions (exact match, no edit, coverage, failed or declined reads, silent-error
  tables, risk): Wilson, or Clopper-Pearson (exact) when the count is 0 or equals the total;
- field-level metrics (precision, recall, F1, micro and macro), error-detection precision and
  recall, and attention items per table: a percentile bootstrap resampling labels (10,000 by
  default), with the seed recorded in the output.

Comparisons between two cells, on the labels both ran: an exact McNemar test for table-level
exact match, and a paired bootstrap (same resampling of labels) for micro field F1.

Bar 4 (5.3, D23): the median cost is the upper median (rank n // 2 + 1 of n sorted costs, the
13th of 24) and p90 latency is the nearest-rank 90th percentile (rank ceil(0.9 n), the 22nd of
24). An unknown cost is counted at the per-tap cap; a call that sent nothing costs nothing.

A tap served from the response cache is counted once, at its original tap's recorded cost
(``cached_cost_usd``), because the cost a tap has is what it cost when it ran; the money this
invocation spent (``charged_usd``, 0 for a cached tap) is reported apart as ``charged_this_run``,
so a rerun never counts a cost twice.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from dataclasses import dataclass, field
from pathlib import Path

SCHEMA = "pasted-label-ai-text-stats-v1"
Z95 = 1.959963984540054
ALPHA = 0.05
PER_TAP_CAP_USD = 0.05
DEFAULT_RESAMPLES = 10_000
DEFAULT_SEED = 416


# MARK: Intervals


def wilson(k: int, n: int, z: float = Z95) -> tuple[float, float]:
    """The Wilson score interval for k successes in n trials."""
    if n <= 0:
        raise ValueError("n must be positive")
    p = k / n
    denominator = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denominator
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denominator
    return max(0.0, centre - half), min(1.0, centre + half)


def _binomial_cdf(k: int, n: int, p: float) -> float:
    """P(X <= k) for X ~ Binomial(n, p)."""
    if k < 0:
        return 0.0
    if k >= n:
        return 1.0
    return sum(math.comb(n, i) * p**i * (1 - p) ** (n - i) for i in range(k + 1))


def _bisect(function, target: float, increasing: bool) -> float:
    low, high = 0.0, 1.0
    for _ in range(200):
        middle = (low + high) / 2
        value = function(middle)
        if (value < target) == increasing:
            low = middle
        else:
            high = middle
    return (low + high) / 2


def clopper_pearson(k: int, n: int, alpha: float = ALPHA) -> tuple[float, float]:
    """The exact (Clopper-Pearson) interval, by bisection on the binomial tails."""
    if n <= 0:
        raise ValueError("n must be positive")
    if k == 0:
        lower = 0.0
    else:
        # P(X >= k | p) = alpha / 2, increasing in p.
        lower = _bisect(lambda p: 1 - _binomial_cdf(k - 1, n, p), alpha / 2, increasing=True)
    if k == n:
        upper = 1.0
    else:
        # P(X <= k | p) = alpha / 2, decreasing in p.
        upper = _bisect(lambda p: _binomial_cdf(k, n, p), alpha / 2, increasing=False)
    return lower, upper


def proportion(k: int, n: int) -> dict:
    """A label-level proportion with its interval: Wilson, or Clopper-Pearson at 0 or n."""
    if n == 0:
        return {"count": k, "total": n, "value": None, "interval": None, "method": None}
    exact = k == 0 or k == n
    low, high = clopper_pearson(k, n) if exact else wilson(k, n)
    return {"count": k, "total": n, "value": k / n, "interval": [low, high], "method": "clopper_pearson" if exact else "wilson"}


# MARK: Order statistics (bar 4)


def upper_median(values: list[float]) -> float | None:
    """The upper median: rank n // 2 + 1 of the sorted values (the 13th of 24, D23)."""
    if not values:
        return None
    return sorted(values)[len(values) // 2]


def nearest_rank(values: list[float], percentile: float) -> float | None:
    """The nearest-rank percentile: rank ceil(p / 100 x n), at least 1 (the 22nd of 24 for p90)."""
    if not values:
        return None
    rank = max(1, math.ceil(percentile / 100 * len(values)))
    return sorted(values)[rank - 1]


# MARK: Labels


@dataclass
class Label:
    label_id: str
    cell: str
    scores: dict
    cost_usd: float | None = None
    cost_known: bool = False
    latency_seconds: float | None = None
    attempt: str = ""
    meta: dict = field(default_factory=dict)
    charged: float = 0.0

    def get(self, name: str) -> float:
        return float(self.scores.get(name, 0))

    @property
    def outcome(self) -> str:
        for name in OUTCOMES:
            if self.get(name) == 1:
                return name
        return "failed"


OUTCOMES = ("reached_confirm", "declined", "failed")
NOT_ASSIGNED = "not assigned"
LAYOUT_SHAPES = ("one_row_per_line", "one_value_per_line", "misaligned", "unitless", "other")


def tap_cost(send: dict, cap: float) -> tuple[float, bool]:
    """A tap's cost: the reported cost; for a cached tap, its original tap's cost; nothing when
    nothing was sent; otherwise (unknown) the per-tap cap."""
    attempt = str(send.get("attempt", ""))
    if send.get("cached"):
        if send.get("cached_cost_usd") is not None:
            return float(send["cached_cost_usd"]), True
        return cap, False
    if send.get("cost_usd") is not None:
        return float(send["cost_usd"]), True
    if attempt.startswith(("refused:", "not_sent:", "declined_before_send:")):
        return 0.0, True
    return cap, False


def load_results(path: Path, cases: Path | None = None, cap: float = PER_TAP_CAP_USD) -> dict[str, list[Label]]:
    """The labels of each cell, in the results' order. A result with no named scores (an error)
    counts as a failed label, never as a missing one."""
    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data["results"]["results"] if isinstance(data.get("results"), dict) else data["results"]
    cells: dict[str, list[Label]] = {}
    for row in rows:
        provider = row.get("provider") or {}
        provider_label = provider.get("label") or provider.get("id") or "provider"
        prompt_label = (row.get("prompt") or {}).get("label") or "prompt"
        cell = f"{provider_label}|{prompt_label}"
        label_id = (row.get("vars") or {}).get("label_id")
        if not label_id:
            raise ValueError("a result has no label_id")
        scores = (row.get("gradingResult") or {}).get("namedScores") or row.get("namedScores") or {}
        if not scores:
            scores = {"failed": 1}
        # Exactly one valid outcome per result (Qodo finding 8 on A2).
        marks = [scores.get(name, 0) for name in OUTCOMES]
        if any(mark not in (0, 1) for mark in marks) or sum(marks) != 1:
            raise ValueError(f"{label_id}: the result does not mark exactly one outcome of {OUTCOMES}")
        try:
            send = json.loads((row.get("response") or {}).get("output") or "{}")
        except (TypeError, json.JSONDecodeError):
            send = {}
        cost, known = tap_cost(send, cap)
        meta = {}
        if cases is not None:
            case_path = cases / f"{label_id}.json"
            if case_path.exists():
                case = json.loads(case_path.read_text(encoding="utf-8"))
                meta = {"tier": case.get("tier"), "copy_method": case.get("copy_method"), "set": case.get("set"), "format": case.get("format"),
                        "layout_shape": case.get("layout_shape") or NOT_ASSIGNED}
        if meta and meta["layout_shape"] not in LAYOUT_SHAPES + (NOT_ASSIGNED,):
            raise ValueError(f"{label_id}: unknown layout_shape {meta['layout_shape']}")
        cells.setdefault(cell, []).append(Label(label_id, cell, scores, cost, known, send.get("latency_seconds"), str(send.get("attempt", "")), meta,
                                                charged=float(send.get("charged_usd") or 0)))
    for cell, labels in cells.items():
        ids = [label.label_id for label in labels]
        if len(ids) != len(set(ids)):
            raise ValueError(f"{cell}: a label appears twice")
        # With the cases named, every cell must have run exactly the case set: a missing label
        # would silently shrink a denominator, and an extra one would score against nothing.
        if cases is not None:
            expected = {path.stem for path in cases.glob("*.json")}
            if set(ids) != expected:
                missing, extra = sorted(expected - set(ids)), sorted(set(ids) - expected)
                raise ValueError(f"{cell}: the results do not match the case set (missing {missing}, extra {extra})")
    return cells


# MARK: Metrics


def _ratio(numerator: float, denominator: float) -> float | None:
    return numerator / denominator if denominator else None


def _f1(precision: float | None, recall: float | None) -> float | None:
    if precision is None or recall is None:
        return None
    return 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)


def label_f1(label: Label) -> float:
    """A label's field F1: 0 for a failed or declined label, or one that read nothing correct."""
    shown, printed, correct = label.get("fields_shown"), label.get("fields_printed"), label.get("fields_correct")
    if label.outcome != "reached_confirm" or not shown or not printed or not correct:
        return 0.0
    return _f1(correct / shown, correct / printed) or 0.0


def field_metrics(labels: list[Label]) -> dict[str, float | None]:
    """The field-level and per-table metrics of 5.2.1 over a list of labels."""
    reached = [label for label in labels if label.outcome == "reached_confirm"]
    shown = sum(label.get("fields_shown") for label in labels)
    printed = sum(label.get("fields_printed") for label in labels)
    correct = sum(label.get("fields_correct") for label in labels)
    wrong = sum(label.get("fields_wrong") for label in labels)
    flagged = sum(label.get("wrong_flagged") for label in labels)
    attention = sum(label.get("attention_items") for label in reached)
    precision = _ratio(correct, shown)
    recall = _ratio(correct, printed)
    with_shown = [label for label in reached if label.get("fields_shown")]
    macro_precision = sum(label.get("fields_correct") / label.get("fields_shown") for label in with_shown) / len(with_shown) if with_shown else None
    macro_recall = (sum(label.get("fields_correct") / label.get("fields_printed") if label.outcome == "reached_confirm" and label.get("fields_printed") else 0.0
                        for label in labels) / len(labels)) if labels else None
    return {
        "field_precision_micro": precision,
        "field_recall_micro": recall,
        "field_f1_micro": _f1(precision, recall),
        "field_precision_macro": macro_precision,
        "field_recall_macro": macro_recall,
        "field_f1_macro": sum(label_f1(label) for label in labels) / len(labels) if labels else None,
        "error_detection_recall": _ratio(flagged, wrong),
        "error_detection_precision": _ratio(flagged, attention),
        "attention_items_per_table": _ratio(attention, len(reached)),
    }


def bootstrap(labels: list[Label], resamples: int, seed: int) -> dict[str, dict]:
    """Percentile bootstrap intervals (2.5th and 97.5th) for the field metrics, resampling labels."""
    point = field_metrics(labels)
    rng = random.Random(seed)
    draws: dict[str, list[float]] = {name: [] for name in point}
    for _ in range(resamples):
        sample = [labels[rng.randrange(len(labels))] for _ in labels]
        for name, value in field_metrics(sample).items():
            if value is not None:
                draws[name].append(value)
    out = {}
    for name, value in point.items():
        values = sorted(draws[name])
        interval = [percentile_of_sorted(values, 2.5), percentile_of_sorted(values, 97.5)] if values else None
        out[name] = {"value": value, "interval": interval, "method": "percentile_bootstrap", "resamples_defined": len(values)}
    return out


def percentile_of_sorted(values: list[float], percentile: float) -> float:
    """The percentile of sorted values by linear interpolation between closest ranks."""
    if len(values) == 1:
        return values[0]
    position = percentile / 100 * (len(values) - 1)
    low = math.floor(position)
    high = min(low + 1, len(values) - 1)
    return values[low] + (values[high] - values[low]) * (position - low)


def label_proportions(labels: list[Label]) -> dict[str, dict]:
    n = len(labels)
    reached = [label for label in labels if label.outcome == "reached_confirm"]
    count = lambda items, name: sum(1 for label in items if label.get(name) == 1)  # noqa: E731
    any_wrong = sum(1 for label in reached if label.get("fields_wrong") > 0)
    return {
        "exact_match": proportion(count(labels, "exact_match"), n),
        "no_edit": proportion(count(reached, "no_edit"), len(reached)),
        "coverage": proportion(len(reached), n),
        "failed_or_declined_reads": proportion(n - len(reached), n),
        "silent_error_tables": proportion(count(reached, "silent_error_table"), len(reached)),
        "risk": proportion(any_wrong, len(reached)),
    }


def operational(labels: list[Label]) -> dict:
    costs = [label.cost_usd for label in labels if label.cost_usd is not None]
    latencies = [float(label.latency_seconds) for label in labels if label.latency_seconds is not None]
    return {
        "outcomes": {name: sum(1 for label in labels if label.outcome == name) for name in ("reached_confirm", "declined", "failed")},
        "cost_usd": {"p50_upper_median": upper_median(costs), "p90_nearest_rank": nearest_rank(costs, 90), "count": len(costs),
                     "unknown_counted_at_cap": sum(1 for label in labels if not label.cost_known),
                     "charged_this_run": sum(label.charged for label in labels)},
        "latency_seconds": {"p50_upper_median": upper_median(latencies), "p90_nearest_rank": nearest_rank(latencies, 90), "count": len(latencies)},
    }


def by_nutrient(labels: list[Label]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for label in labels:
        for name, value in label.scores.items():
            if name.startswith("nutrient."):
                _, nutrient, count = name.split(".", 2)
                out.setdefault(nutrient, {"printed": 0, "shown": 0, "correct": 0, "wrong": 0})[count] += int(value)
    return dict(sorted(out.items()))


def breakdowns(labels: list[Label]) -> dict[str, dict]:
    out: dict[str, dict] = {"nutrient": by_nutrient(labels)}
    for key in ("tier", "copy_method", "set", "format", "layout_shape"):
        groups: dict[str, list[Label]] = {}
        for label in labels:
            groups.setdefault(str(label.meta.get(key)), []).append(label)
        if any(key in label.meta for label in labels):
            out[key] = {name: {"labels": len(group), **{k: v for k, v in label_proportions(group).items() if k in ("coverage", "exact_match")},
                               "field_f1_micro": field_metrics(group)["field_f1_micro"]} for name, group in sorted(groups.items())}
    return out


def bar(labels: list[Label], bar_path: Path) -> dict:
    """The 5.3 bar's figures over these labels, against `bar-v1.json`'s thresholds. Reported for
    any set; it gates release only on the one held-out run."""
    gates = {gate["id"]: gate for gate in json.loads(bar_path.read_text(encoding="utf-8"))["gates"]}
    reached = [label for label in labels if label.outcome == "reached_confirm"]
    silent = sum(1 for label in reached if label.get("silent_error_table") == 1)
    no_edit = sum(1 for label in reached if label.get("no_edit") == 1)
    failed = len(labels) - len(reached)
    op = operational(labels)
    median, p90 = op["cost_usd"]["p50_upper_median"], op["latency_seconds"]["p90_nearest_rank"]
    missing_latency = sum(1 for label in labels if label.latency_seconds is None)
    return {
        "bar_1": {"value": silent, "pass": silent == gates["bar_1"]["threshold"]},
        "bar_2": {"value": _ratio(no_edit, len(reached)), "pass": bool(reached) and no_edit / len(reached) >= gates["bar_2"]["threshold"]},
        "bar_3": {"value": failed, "pass": failed <= gates["bar_3"]["threshold"] if len(labels) == gates["bar_3"]["denominator_count"]
                  else failed / len(labels) <= gates["bar_3"]["fraction"] if labels else False},
        "bar_4_cost": {"value": median, "pass": median is not None and median <= gates["bar_4_cost"]["threshold"]},
        # Bar 4 is over all taps: a tap with no recorded latency fails it rather than leaving the count.
        "bar_4_latency": {"value": p90, "missing": missing_latency,
                          "pass": missing_latency == 0 and p90 is not None and p90 <= gates["bar_4_latency"]["threshold"]},
        "labels": len(labels),
    }


def macro_precision_exclusions(labels: list[Label]) -> dict[str, int]:
    """The labels left out of macro precision, reported beside it (Qodo finding 10 on A2)."""
    reached = [label for label in labels if label.outcome == "reached_confirm"]
    return {"averaged_over": sum(1 for label in reached if label.get("fields_shown")),
            "excluded_not_reaching_confirm": len(labels) - len(reached),
            "excluded_confirm_without_fields": sum(1 for label in reached if not label.get("fields_shown"))}


def summary(cells: dict[str, list[Label]], resamples: int, seed: int, bar_path: Path | None) -> dict:
    out = {"schema": SCHEMA, "seed": seed, "resamples": resamples, "cells": {}}
    for cell, labels in sorted(cells.items()):
        field_level = bootstrap(labels, resamples, seed)
        field_level["field_precision_macro"]["exclusions"] = macro_precision_exclusions(labels)
        entry = {"labels": len(labels), "label_level": label_proportions(labels), "field_level": field_level,
                 "operational": operational(labels), "breakdowns": breakdowns(labels)}
        if bar_path is not None:
            entry["bar"] = bar(labels, bar_path)
        out["cells"][cell] = entry
    return out


# MARK: Comparing two cells


def mcnemar_exact(b: int, c: int) -> float:
    """The exact two-sided McNemar p value for b and c discordant pairs."""
    n = b + c
    if n == 0:
        return 1.0
    tail = sum(math.comb(n, i) for i in range(min(b, c) + 1)) / 2**n
    return min(1.0, 2 * tail)


def compare(cells: dict[str, list[Label]], a: str, b: str, resamples: int, seed: int) -> dict:
    """McNemar on exact match and a paired bootstrap on micro field F1, over the shared labels."""
    left = {label.label_id: label for label in cells[a]}
    right = {label.label_id: label for label in cells[b]}
    shared = sorted(set(left) & set(right))
    if not shared:
        raise ValueError("the two cells share no labels")
    only_a = sum(1 for i in shared if left[i].get("exact_match") == 1 and right[i].get("exact_match") != 1)
    only_b = sum(1 for i in shared if left[i].get("exact_match") != 1 and right[i].get("exact_match") == 1)
    pairs = [(left[i], right[i]) for i in shared]

    def micro_f1(labels: list[Label]) -> float:
        return field_metrics(labels)["field_f1_micro"] or 0.0

    observed = micro_f1([p[0] for p in pairs]) - micro_f1([p[1] for p in pairs])
    rng = random.Random(seed)
    differences = []
    for _ in range(resamples):
        sample = [pairs[rng.randrange(len(pairs))] for _ in pairs]
        differences.append(micro_f1([p[0] for p in sample]) - micro_f1([p[1] for p in sample]))
    differences.sort()
    at_most_zero = sum(1 for d in differences if d <= 0) / len(differences)
    at_least_zero = sum(1 for d in differences if d >= 0) / len(differences)
    return {
        "schema": SCHEMA, "seed": seed, "resamples": resamples, "cell_a": a, "cell_b": b, "shared_labels": len(shared),
        "versions_compared": 2,
        "exact_match_mcnemar": {"a_only": only_a, "b_only": only_b, "p_value_exact": mcnemar_exact(only_a, only_b)},
        "field_f1_micro_paired_bootstrap": {"difference_a_minus_b": observed,
                                            "interval": [percentile_of_sorted(differences, 2.5), percentile_of_sorted(differences, 97.5)],
                                            "p_value_two_sided": min(1.0, 2 * min(at_most_zero, at_least_zero))},
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    s = sub.add_parser("summary")
    s.add_argument("results", type=Path)
    s.add_argument("--cases", type=Path)
    s.add_argument("--bar", type=Path, default=Path(__file__).resolve().parent.parent / "bar-v1.json")
    c = sub.add_parser("compare")
    c.add_argument("results", type=Path)
    c.add_argument("cell_a")
    c.add_argument("cell_b")
    for p in (s, c):
        p.add_argument("--seed", type=int, default=DEFAULT_SEED)
        p.add_argument("--resamples", type=int, default=DEFAULT_RESAMPLES)
        p.add_argument("--per-tap-cap-usd", type=float, default=PER_TAP_CAP_USD)
    args = parser.parse_args(argv)
    if args.resamples <= 0:
        parser.error("--resamples must be positive")
    cells = load_results(args.results, getattr(args, "cases", None), args.per_tap_cap_usd)
    if args.command == "summary":
        result = summary(cells, args.resamples, args.seed, args.bar)
    else:
        result = compare(cells, args.cell_a, args.cell_b, args.resamples, args.seed)
    json.dump(result, sys.stdout, indent=1, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
