---
name: codex-phase-accounting
description: Measure a bounded Codex work phase from local session token counters, calculate an explicitly assumed API-equivalent cost, and update an existing usage ledger. Use when the user requests token or cost accounting; do not use totals as productivity benchmarks or infer missing usage.
---

# Codex Phase Accounting

Produce reproducible token and comparison-cost figures without pretending that an unobserved boundary or execution channel was measured.

## Establish the boundary

At the start of a phase that is expected to be measured:

1. Locate the active top-level session JSONL.
2. Run `scripts/phase_usage.py <session>` and retain its input, cached-input and output counters as the baseline.
3. State whether subagents, reused threads, hosted review, discussion or other channels are inside the measured session.

If no baseline was captured, use only a defensible earlier snapshot or label the result as whole-session usage. Never reconstruct or estimate a missing phase boundary.

## Measure and calculate

Read the target ledger before editing. Use its documented per-million rates and terminology; do not silently substitute current public pricing.

Run:

```bash
python3 scripts/phase_usage.py SESSION \
  --baseline INPUT CACHED_INPUT OUTPUT \
  --uncached-input-rate RATE \
  --cached-input-rate RATE \
  --output-rate RATE
```

Omit `--baseline` only when whole-session accounting is intended. The script reads the latest complete token-count event, validates the counters, subtracts the baseline and performs decimal cost arithmetic. It does not edit any ledger.

## Update the ledger

- Preserve the ledger's existing columns, rounding, subtotals and rate explanation.
- Identify the phase honestly; mention included design or review discussion when it was measured together.
- Recalculate subtotals from the recorded row, not from a later session counter.
- Exclude the accounting edit itself unless the ledger explicitly defines another boundary.
- Label the result API-equivalent or comparative when the work ran under a subscription.
- Keep actual billing, subscription limits and comparison pricing distinct.
- Do not claim that token totals measure quality, productivity, causation or provider efficiency.
- State any unmeasured agents, reviews, threads or tools instead of estimating them.

Use `apply_patch` for the ledger edit, check its arithmetic and diff, and commit or push only when requested.

## Failure conditions

Stop and report the limitation when the session cannot be identified, no complete token-count event exists, counters decrease relative to the baseline, or the ledger has no defensible rate assumption. A bounded unknown is preferable to an invented number.
