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
| `queries.py` | The owner's query template (`query-template.csv`), its assembly into the unsplit `pfd-query-set-v1` (query IDs in row order; every entry ID checked against the pinned import file and every generic record against the pinned corpora; errors name the row and column, never a cell's value) and the owner-only lookup (entries or generic records holding every typed word, alphabetical, no score, with the fields that matched). Pure. |
| `score_a.py` | Part A counts per stratum from a sample and a completed review sheet: skips, A1 product and nutrient counts over checked entries and checked values, `missing_in_entry` as its own count, A5 "not assessed" when empty, A3 close and other-state split. Pure. |
| `score_b.py` | Part B measures from a query set and a ranking output: top-1 and top-3 acceptable by answer kind, step correct, wrong generic first, wrong entry first, negative false hits, with the plan's denominators. Pure. |
| `results.py` | The `pfd-results-v1` allow-list writer: closed field names, whole-number counts, intervals, booleans for bar results and the release ID; any other key or string value is refused. |
| `seals.py` | Append-only `seals.txt` (`<name> <sha256> <file count> <UTC time>`), verify, never replace; the clock is injected. |
| `freeze.py` | Check file hashes against `freeze-v1.json` in this folder, the plan's one machine-checked Freeze list (plan section 11): scorer files and the skill's `workspace_guard.py` from E1a, then the release, seed, sample and purchase-count hashes, held-out seal hash and, before v12 code, the golden file. A test fails when a listed file stops matching. |
| `pfd_eval.py` | Command line and file input/output only: `draw-seed`, `query-template`, `assemble-queries`, `lookup`, `sample`, `split`, `seal`, `score-a`, `score-b`. Every private path is checked by the skill's `workspace_guard.check_output` (imported by a path built from this file's location in the repository, never the working directory) before it is read or written. |

**Dependency direction.** `pfd_eval.py` (input/output, clock, randomness for `draw-seed` only) →
the pure modules. The pure modules import nothing outside the standard library and this folder, and
take seeds, clocks and bytes as arguments, so every result is reproducible from its inputs.

**Invariants.**
- No network access; no private data in this folder. Plan revision 5 permits a dedicated drafting
  agent to direct local offline scripts that prepare private unsplit queries and separate review
  proposals for owner validation. Query drafting returns counts and hashes only to anything outside
  the drafting session; query wording may sit in that session's context, which is why the session is
  excluded from ranking (plan section 7). A subsequent explicit
  owner authorisation permits selected titles, matched record names and preparation states in model
  context for semantic identity review (plan section 7); other private fields remain excluded.
  User-facing and external code-review output remains counts-only. The drafting agent cannot implement ranking.
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
each held-out result also states its run number. A held-out run must name `--out`; its result is
written before the run is recorded, so a failed write uses up no run. Seal and run writes take an
exclusive lock on the private `.seals.lock`, and a sealed folder or file that is a link is refused.

**Private folder layout.** `<root>/sample/sample.json`, `<root>/review/review-sheet.csv`,
`<root>/sample/purchase-counts.json`, `<root>/queries/query-template.csv`, `<root>/queries/query-set.json`,
`<root>/development/query-set.json`, `<root>/held-out/query-set.json`,
`seals.txt`, `.seals.lock` and `exposures.txt` (a plain file, never a link). The
root must pass the skill's `workspace_guard.check` (not in a git tree, mode 700) and every path its
`check_output`; no evaluation file is ever overwritten.

**Reading rules settled in E1a.** For a `none` query, top-3 counts the first result only (as top-1).
A stratum that runs out of rows before its quota fails its bar. Each held-out result records
`owner_development_output_openings`, the number of lines in the private `exposures.txt`, where the owner
notes the date each time they open per-query development output (plan 4.3), and `held_out_run`, the
run number it was recorded as (1, or 2 for the one permitted rerun).

## Building the query set (E1d, owner)

Under plan revision 5, Codex may direct local offline scripts to prepare and assemble an unapproved
draft, returning only aggregate counts and hashes. Workflow authorisation does not approve its rows.
The owner validates every row before splitting or sealing; `lookup` remains owner-only. `ROOT` is the private evaluation
folder and `EXPORT` the pinned import file. The release must already be pinned in `freeze-v1.json` (E1b).

1. `python3 -I pfd_eval.py query-template --root ROOT` writes an empty `queries/query-template.csv`.
2. Open it in a spreadsheet and add one row per query:

   | Column | What to write |
   |---|---|
   | `query` | the search exactly as you would type it |
   | `negative` | `yes` for a food you eat that is not in the database, otherwise `no` |
   | `answer` | `entry`, `generic` or `none` |
   | `entry_ids` | for `entry`: one or more `pfc:` IDs, separated by spaces |
   | `step` | for `entry`: `title` (1), `variety` (2) or `concept` (3), the field that should find it |
   | `generic` | for `generic`: `source=record_id` items separated by `;`, as `lookup --generic` prints them |

   A negative query must have answer `none`; you may also mark other queries `none` (plan 4.2). Blank
   rows are ignored. Save as UTF-8 CSV.
3. To find IDs, `python3 -I pfd_eval.py lookup --root ROOT --export EXPORT oat milk` lists the entries
   holding every word, alphabetically and without a score, with the fields that matched; add
   `--generic` to search the generic records. It prints to your screen only, writes nothing, and runs only
   in an interactive terminal (a guard against an accidental run by an agent, not authentication). The
   choice of answer and step stays yours: the lookup is not the ranking under test.
4. `python3 -I pfd_eval.py assemble-queries --root ROOT --export EXPORT` checks every row and writes
   `queries/query-set.json`, printing counts only. A refusal names the row and column to fix.
5. Only after every query and expected answer is owner-approved: `python3 -I pfd_eval.py split --root ROOT --query-set ROOT/queries/query-set.json`, then
   `seal --root ROOT seal-dev` and `seal --root ROOT seal-heldout`; the held-out hash then goes into
   the Freeze list.

**Out of scope for E1a.** The Part B Swift step test, the `pfd-v11-ranking-golden-v1` file and the
importer belong to the implementation phase; E1b to E1d (release pin, seed, sample, query set) need
the owner.

## Owner validation of drafts (plan revision 5)

Review `review/best-estimate-review.csv` alongside the unchanged `review/review-sheet.csv`;
`review/prefill-proposals.csv` is a byte-identical copy kept under its earlier name, so validating
one validates both. Proposals are keyed by sheet row, with reasons, for the initial census, top-30 and drawn rows only. Validate
or correct every proposal. Pack checks are out of scope since the best-estimate amendment below,
so no pack verdict exists for anyone to fill. Do not run `seal-review` or `score-a` (see the scoring
hold below). The private `review/HOW-TO-REVIEW.txt` gives the sequence.

If queries change after draft assembly, preserve the old unsplit JSON under a private archive name
and reassemble; the tool never overwrites it. Approve the final CSV and assembled JSON together.
No split or seal occurs during drafting. The results narrative must disclose agent-drafted and
owner-approved query provenance without changing the closed results JSON schema. A separate
unexposed session implements ranking and must never read queries or the held-out folder.

The owner-authorised semantic review saves provisional identity/state judgements to the separate
private proposal file and leaves uncertain cases unresolved. Model access is limited to the fields
listed in plan section 7 and the privacy register (including nutrient evidence under the amendment
below), not the whole review sheet. The original sheet is completed only through the owner-validation workflow.

## Revision 5 best-estimate amendment: scoring hold

The current v1 review sheet and Part A scorer implement the earlier pack-verification rubric. They
cannot score the revised identity/state/variety, macro/micro coverage and per-nutrient evidence
review. Keep the original sheet unchanged. Private `best-estimate-review.csv`,
`nutrient-evidence.jsonl` and `enrichment-candidates.csv` hold proposals only. Do not translate these
into v1 verdicts or run `seal-review`/`score-a` until the owner approves a versioned schema/scorer
migration described in plan section 3.3. No new tool implementation is authorised by this document.
The plan's subsequent amendment supersedes earlier pack-check instructions here. Part B query
validation, blinding and bars remain unchanged. All web values remain `page_unconfirmed` and carry
URL, date read, source state, basis and method; use local evidence before external research.

## Part A review v2 (#443)

The owner approved the v2 design ([`docs/personal-food-database-review-v2-design.md`](../../docs/personal-food-database-review-v2-design.md))
and the Part A bars `v2_proposed` (plan decision 9). The v2 modules live in `v2/`, because the v1
freeze check refuses any unlisted `*.py` file in this folder; every v1 file and `freeze-v1.json`
stay byte for byte. `freeze-v2.json` pins the v2 modules, `nutrient-inventory-v1.json` and the
hash of `freeze-v1.json`, and holds `part_a_bars`.

Private layout under the evaluation root: `review-v2/review-sheet-v2.csv` and
`review-v2/nutrient-evidence-v2.jsonl` (the only two files sealed by `seal-review-v2`),
`exclusions-v2/exclusions.json`, and the append-only `seals-v2.txt`.

```
python3 -I v2/pfd_eval_v2.py review-sheet-v2 --root DIR     (writes the empty v2 sheet)
python3 -I v2/pfd_eval_v2.py seal --root DIR seal-review-v2 (after the owner fills both files)
python3 -I v2/pfd_eval_v2.py score-a-v2 --root DIR --out OUT (refuses without part_a_bars; locks it)
```

Run `python3 -I v2/pfd_eval_v2.py <command> --help` for exact options. The A1 and A5 value bar is
judged on macro and micro values together, as the plan's single "assessed value evidence error"
bar; macro and micro counts are reported separately for information. After any change to a `v2/`
module or the inventory, regenerate `freeze-v2.json` in the same commit.

## R1, the drops-only export (#424, plan decision 10)

`r1/` builds R1, the export of the pinned release with the E3 consequences applied (E3 disposition,
[`docs/personal-food-database-e3-disposition.md`](../../docs/personal-food-database-e3-disposition.md),
D1 and D2). It changes no frozen file: it imports the frozen review v2 modules and the skill's
`export_v1.py` read-only, and it is not in either freeze record.

| Module | Responsibility |
|---|---|
| `r1/r1_export.py` | Pure. Derives R1 from the parsed pinned release, the frozen `pfd-exclusions-v1` list and a `pfd-unresolved-v1` list, under two explicit switches (`a1`: drop every Open Food Facts label value; `a2`: every merge becomes a candidate). `check_drops_only` proves the result only removes: same entries in the same order, every kept field, value, source and reference byte-equal, and a reference changed only from `merge` to `candidate`. `check_applied` proves every required removal happened. |
| `r1/pfd_r1.py` | Command line and files only: `build-r1 --root DIR --release PINNED.json --results RESULTS.json --a1 on|off --a2 on|off`. |

**How it decides.** R1 is never rebuilt from working files, so no merge can be created and a
merge made newly eligible by dropped values stays a candidate by construction. A withheld entry
keeps no value and no reference and stays listed ("No nutrition data yet"). A withheld or
unresolved value is removed. Its key must be in the frozen nutrient inventory; when it is not a
label value of the entry, the reviewed value came from the entry's generic reference, so that
reference is removed instead, whether `merge` or `candidate`, and a listed key on an entry with
neither is refused. Unresolved values are taken from every stratum (unresolved is never a pass),
and the console reports them by stratum. When any label value is removed
(withheld, unresolved or by `a1`), the entry's `merge` reference becomes a `candidate`, so the
merged record never silently supplies those nutrients in their place (plan section 6: never a new
merge after label values are removed, including references attached to A1 entries). Entries keep
their pinned `basis`. Sources no longer cited are removed; `generated`
and `generic_corpora` stay as pinned.

**Formats.** `pfd-unresolved-v1`, private: `{"schema": "pfd-unresolved-v1", "release_id":
"pfc:sha256:...", "withhold_values": [{"entry_id", "nutrient"}]}`, values unique and in ascending
`(entry_id, nutrient)` order, written with sorted keys, no spaces and one trailing newline; any
other byte form is refused. It holds entry IDs and inventory keys only. `pfd-r1-build-v1`, private,
the same canonical form: the pinned and R1 release IDs, the switches and the SHA-256 of the
exclusion list, the unresolved list and the Part A results file, so the stored R1 always says how it was built. A new field is a
new schema version.

**Fail closed.** `build-r1` runs only when both freeze records, the bars lock and the review seal
hold, the Part A results file (`--results`, the `score-a-v2 --out` file, inside this repository and
not a link) holds exactly the result the sealed review gives (the bars lock is written before the
scorer's files, so the lock alone does not prove scoring finished), the release file has the pinned ID and passes the importer's rules, and the exclusion list
names the same release. The unresolved list is derived from the sealed review with the frozen
parsers (values assessed `unresolved`). The output must pass `check_drops_only`, `check_applied`, the skill's
export conventions and the importer's rules, or nothing is written. All three files go to
`<root>/r1/` (refused when it is a link or not a folder), all or nothing, and a different existing file is never overwritten. The console
prints counts and the R1 release ID only. The three files are the R1 file, the unresolved list and the build record.

For the A1 consequence the evaluator runs it with `--a1 on --a2 off` (A2 passed), passing the committed Part A results file as `--results`.
