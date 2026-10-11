---
name: agent-phase-accounting
description: Measure a bounded Codex or Claude Code work phase from local session transcripts, calculate an explicitly assumed API-equivalent cost, and update an existing usage ledger. Use only when the user requests token or cost accounting; never use totals as productivity benchmarks or infer missing usage.
---

# Agent Phase Accounting

Produce reproducible token and comparison-cost figures for either agent without pretending that an unobserved boundary or execution channel was measured.

## Locate the session

- **Codex:** the active top-level rollout JSONL under the Codex sessions directory.
- **Claude Code:** `~/.claude/projects/<project-path-with-dashes>/<session-id>.jsonl`. Subagent transcripts sit in `<session-id>/subagents/`.

`scripts/phase_usage.py` detects the format; pass `--format codex|claude` if detection fails.

## Establish the boundary

At the start of a phase that will be measured:

- **Codex:** run `scripts/phase_usage.py <session>` and keep its input, cached-input and output counters as the baseline.
- **Claude Code:** record the UTC start time. Claude logs usage per message, so the boundary is a time window (`--since`, optionally `--until`), not a counter subtraction.

State whether subagents, reused threads, hosted review, discussion or other channels are inside the measured boundary. If no boundary was captured, use only a defensible earlier snapshot or label the result as whole-session usage. Never reconstruct or estimate a missing boundary.

## Measure and calculate

Read the target ledger before editing. Use its documented per-million rates and terminology; do not silently substitute current public pricing.

```bash
# Codex phase
python3 scripts/phase_usage.py SESSION \
  --baseline INPUT CACHED_INPUT OUTPUT \
  --uncached-input-rate RATE --cached-input-rate RATE --output-rate RATE

# Claude Code phase, including its subagents
python3 scripts/phase_usage.py SESSION --since 2026-10-11T09:00:00Z --include-subagents \
  --uncached-input-rate RATE --cached-input-rate RATE --cache-write-rate RATE --output-rate RATE
```

Compatibility with the former `codex-phase-accounting` script: Codex counting, baseline subtraction, pricing and exit statuses are unchanged. The output adds `format` and `cache_write_input_tokens` (always 0 for Codex) and some error messages differ, so update any tooling that parses the exact output.

Claude reports cache writes separately from cache reads; the script requires a cache-write rate whenever cache writes are present rather than pricing them as ordinary input. The script validates counters and performs decimal arithmetic. It does not edit any ledger.

## Update the ledger

- Preserve the ledger's columns, rounding, subtotals and rate explanation. Add an agent column or note when the ledger mixes agents.
- Identify the phase honestly; mention included design or review discussion when it was measured together.
- Recalculate subtotals from the recorded rows, not from a later session counter.
- Exclude the accounting edit itself unless the ledger defines another boundary.
- Label results API-equivalent or comparative when the work ran under a subscription. Keep actual billing, subscription limits and comparison pricing distinct.
- Do not claim that token totals measure quality, productivity, causation or provider efficiency, and do not compare agents on totals alone.
- State any unmeasured agents, reviews, threads or tools instead of estimating them.

Check the arithmetic and diff; commit or push only when requested.

## Failure conditions

Stop and report the limitation when the session cannot be identified, no usage exists in the window, counters decrease relative to a baseline, or the ledger has no defensible rate assumption. A bounded unknown is preferable to an invented number.
