# Personal food database evaluation tool

Phase E1a (#427) of [`docs/personal-food-database-evaluation-v1.md`](../../docs/personal-food-database-evaluation-v1.md)
(the plan). This folder holds the scoring tool and its synthetic tests. It holds no private data:
every input it reads and every per-entry or per-query file it writes lives in the owner's private
evaluation folder, and the only thing it writes into this repository is a counts-only results file.

Run it with `python3 -I Tools/PersonalFoodDatabaseEvaluation/pfd_eval.py <command> ...` from the
repository root. It uses the standard library only.

## Design (E1a architecture gate)

**Responsibilities.**

| Module | Responsibility |
|---|---|
| `formats.py` | Parse and validate the versioned files: `pfd-review-sheet-v1` (CSV), `pfd-query-set-v1`, `pfd-ranking-output-v1`, `pfd-purchase-counts-v1` (written by a skill script in E1c), `pfd-sample-v1` (the plan's sampled-ID file), `pfd-freeze-v1` (JSON). Closed tokens; an unknown schema, key, token or answer kind is refused. Pure. |
| `stats.py` | Wilson 95 per cent interval. Pure. |
| `bars.py` | The accepted bars of plan section 6 as data, the allowed-count rules (round down for "at most", round up for "at least", fixed A2 and A3 counts per decision 7) and the judge. Pure. |
| `sample.py` | Stratum assignment (A5 > A1 > A2 > A3 > A4) from a `personal-food-catalogue-v1` file, the seeded Part A sample (A1 and A5 census, top 30 always included and counted in their stratum, A2 40, A3 40, A4 20, a full seeded replacement order for A2 to A4) and the review sheet rows. Pure: takes bytes and a seed, returns data. |
| `split.py` | The seeded Part B split: negatives divided evenly, the rest about 60 per cent development and 40 per cent held-out. Pure. |
| `score_a.py` | Part A counts per stratum from a sample and a completed review sheet: skips, A1 product and nutrient counts over checked entries and checked values, `missing_in_entry` as its own count, A5 "not assessed" when empty, A3 close and other-state split. Pure. |
| `score_b.py` | Part B measures from a query set and a ranking output: top-1 and top-3 acceptable by answer kind, step correct, wrong generic first, wrong entry first, negative false hits, with the plan's denominators. Pure. |
| `results.py` | The `pfd-results-v1` allow-list writer: closed field names, whole-number counts, intervals, booleans for bar results and the release ID; any other key or string value is refused. |
| `seals.py` | Append-only `seals.txt` (`<name> <sha256> <file count> <UTC time>`), verify, never replace; the clock is injected. |
| `freeze.py` | Check file hashes against `freeze-v1.json` in this folder, the plan's one machine-checked Freeze list (plan section 11): scorer files and the skill's `workspace_guard.py` from E1a, then the release, seed, sample and purchase-count hashes, held-out seal hash and, before v12 code, the golden file. A test fails when a listed file stops matching. |
| `pfd_eval.py` | Command line and file input/output only: `draw-seed`, `sample`, `split`, `seal`, `score-a`, `score-b`. Every private path is checked by the skill's `workspace_guard.check_output` (imported by a path built from this file's location in the repository, never the working directory) before it is read or written. |

**Dependency direction.** `pfd_eval.py` (input/output, clock, randomness for `draw-seed` only) →
the pure modules. The pure modules import nothing outside the standard library and this folder, and
take seeds, clocks and bytes as arguments, so every result is reproducible from its inputs.

**Invariants.**
- No network access; no private data in this folder; agents never read the private files (the commands
  print counts only, never titles, query text or entry IDs).
- Unknown is never zero: `missing_in_entry`, `not_on_pack` and skips are excluded from denominators
  and reported as their own counts; an empty stratum or set is "not assessed", never a pass.
- A1 and A5 skips are never replaced; more than 6 skipped A1 entries fails both A1 bars.
- Bars are judged on the observed count; intervals are informational.
- The same inputs and seed always give byte-identical outputs.
- Scoring refuses an unsealed, changed or unpinned input and a scorer whose files differ from the
  freeze record.

**Extension axes.** A new file version is a new parser beside the old one; a new bar is a new row in
`bars.py` with its own plan revision. Nothing else varies.

**Contract tests** (synthetic, `tests/`): Wilson known values and edges; stratum order; sample
reproducibility and seed sensitivity; top-30 overflow keeps fixed A2 and A3 counts; split
reproducibility with negatives 10 and 10; planted review sheets and rankings giving exact counts,
including A1 skips at 6 and 7, `not_on_pack` and `missing_in_entry`, A5 empty, empty positive list
(not acceptable) and empty `none` list (acceptable); unknown token, kind and schema refused; seals
never replaced and changed files refused; freeze mismatch refused; results writer refuses an unknown
key and a free string; private-path refusal for a git tree and a shared folder; the command line
prints no title, query text or entry ID.

**Seals.** `seal-dev`, `seal-heldout` and `seal-review`, in that order, over the private
`development/`, `held-out/` and `review/` folders, with the Swift fresh-set bundle rule (SHA-256 of sorted
`<sha256>  <folder>/<file>` lines); `tests/fixtures/seal-bundle/` is the shared fixture and its
`EXPECTED` hash, for the Swift step test to check in the implementation phase. Held-out scoring runs are
recorded as `run-heldout` lines in `seals.txt`, and a third is refused. This guards against an
accidental rerun, not a deliberate one: anyone who can edit the private folder can remove those lines, so
each held-out result also states its run number.

**Private folder layout.** `<root>/sample/sample.json`, `<root>/review/review-sheet.csv`,
`<root>/sample/purchase-counts.json`, `<root>/development/query-set.json`, `<root>/held-out/query-set.json`,
`seals.txt` and `exposures.txt`. The
root must pass the skill's `workspace_guard.check` (not in a git tree, mode 700) and every path its
`check_output`; no evaluation file is ever overwritten.

**Reading rules settled in E1a.** For a `none` query, top-3 counts the first result only (as top-1).
A stratum that runs out of rows before its quota fails its bar. Each held-out result records
`owner_development_output_openings`, the number of lines in the private `exposures.txt`, where the owner
notes the date each time they open per-query development output (plan 4.3), and `held_out_run`, the
run number it was recorded as (1, or 2 for the one permitted rerun).

**Out of scope for E1a.** The Part B Swift step test, the `pfd-v11-ranking-golden-v1` file and the
importer belong to the implementation phase; E1b to E1d (release pin, seed, sample, query set) need
the owner.
