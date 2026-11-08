# Personal food database evaluation v1

Status: **draft, revision 4, 8 November 2026; the owner has taken every section 9 decision, and the plan
is not yet marked accepted.** Revision 2 added three clarifications to the bars after a Qodo review
(section 9, decision 4). Revision 3 answers the architecture-gate review (PASS WITH CHANGES) and the
invariant review (NEEDS WORK) of revision 2 with the mechanics they asked for (sections 2, 4, 5 and 8)
and closes judging gaps; it moves no bar (section 10). It also records the A3 consequence, the private
configuration and the larger-sample rule (decisions 5 to 7). Revision 4 names the machine-checked Freeze
list and the files E1a introduces (section 10). Phase E0 of the personal food database work, after the
accepted [import contract](personal-food-catalogue-import-v1.md) (#419). It defines how the database and
its search are measured **before any importer code is written**. It adds no product code and changes no
shipped behaviour. Issue: #424.

In this file, "decision N" means section 9, decision N of this file; contract decisions are written
"contract decision N".

## 1. What this evaluation answers

1. **Is the database right?** For each kind of entry, how often the match is wrong: a label from a
   different product or variant, a generic record for a different food or state, or a value that
   does not agree with the pack. This tests contract decision 9 ("Confirm is enough"): an automatic
   match is only safe to show unreviewed if it is rarely wrong.
2. **Does search find the right thing?** For the way the owner actually names foods, how often the
   right entry, the right generic record or, for a food not in the database, no database entry comes
   first; and how often a wrong database entry comes first instead.
3. **Does it leave everything else alone?** With no database rows, ranking v12 must give exactly the
   v11 behaviour on the existing search evaluations (section 4.5).

The answers decide what is exported, not just whether to proceed: a kind of entry that fails its bar
is dropped from the import file (section 6), never shown with a looser bar.

## 2. What is frozen, and in what order

Nothing private is ever committed. The **Freeze list** is one machine-checked record,
`Tools/PersonalFoodDatabaseEvaluation/freeze-v1.json` (format `pfd-freeze-v1`, section 11), holding
only file hashes, the release ID, the plain-text seed and the seal hashes. Each step adds its entries in
a docs commit; a command that needs an entry stops when it is missing (fail closed).

1. **E1a, scorers.** The scoring tool and its synthetic tests are committed (section 7). The Freeze
   list records the SHA-256 of each scorer file and of the skill's `workspace_guard.py` that the scorer
   imports. The v11 golden file (section 4.5) is added to the Freeze list before any v12 code lands.
2. **E1b, release.** The database release under test is pinned: its `pfc:sha256:` ID (bytes stay
   private), the skill commit that built it, and the SHA-256 of the working mapping files it used.
3. **E1c, Part A sample.** The seed is drawn, recorded **in plain text** in the Freeze list (it is not
   secret without the private entry list), and the sample is generated from it. The sampled-ID file is
   `pfd-sample-v1`; its SHA-256, and that of the copy of the `pfd-purchase-counts-v1` file it was drawn
   from (kept beside it), are recorded too, so neither can change afterwards. Seeded orders use the
   SHA-256 of `<seed>|<entry id>`, so they never depend on the Python version.
4. **E1d, Part B query set.** The owner records every query and its expected answer first; then the
   seeded split runs into the private `development/` and `held-out/` folders; then `seal-dev` and
   `seal-heldout` append one line each to a private append-only `seals.txt` (`<name> <sha256> <file
   count> <UTC time>`, the format of the UK fresh-set protocol, with its bundle hash: the SHA-256 of
   sorted `<sha256>  <folder>/<file>` lines; a seal is never replaced, and seals are recorded in the
   order `seal-dev`, `seal-heldout`, `seal-review`); then the held-out hash goes into the Freeze list.
5. **E3, review sheet.** When the owner has finished the Part A review sheet, `seal-review` appends its
   hash to `seals.txt` before the E3 scoring run.

Scorers refuse an input that is unsealed, changed since its seal, or not the pinned release, and refuse
to run when the hash of a scorer file, `workspace_guard.py` or the golden file differs from the Freeze
list. A rebuilt database is a new release, except an E3 export that only **drops** values or candidates under a section
6 rule: that needs no new Part A sample. Part B answers are keyed by entry `id`, which is stable for a
brand and title (contract section 4), and every result names the release it ran on.

## 3. Part A: database quality (owner checks a sample)

### 3.1 Strata

Each entry is placed in exactly **one** stratum, in this order: A5 if it carries owner label values,
else A1 if it carries Open Food Facts label values, else A2 if its generic reference role is `merge`,
else A3 if it is `candidate`, else A4. Counts below are from the release built on 7 November 2026 and
will be re-read from the pinned release.

| Stratum | What the entry carries | Entries | What the owner checks |
|---|---|---:|---|
| A1 own label | Open Food Facts label values for the product | 58 | Is it this product (brand, variant, pack)? Do the values agree with the pack? |
| A2 merge | a same-food, raw or cooked generic record merged in | 297 | Is the generic record the same food in the same state? |
| A3 candidate | a close or other-state generic record offered separately | 382 | Is it a sensible "Generic" choice for this food, or misleading? |
| A4 name only | no values, no reference | 138 | Is there really nothing suitable, or did matching miss an obvious one? |
| A5 owner label | values the owner typed or confirmed | (few) | Do they agree with the pack? (checks the intake path, not the owner) |

### 3.2 Sample

- **A1 and A5 are checked in full** (a census, not a sample): all 58 A1 entries and every A5 entry.
- **Always included:** the 30 most-bought entries (by receipt purchase lines, from a private
  `pfd-purchase-counts-v1` file that a skill script writes in E1c, since the import file carries no
  purchase data; ties go to the lower entry `id`). They count towards
  their own stratum's quota; if a stratum's members among the top 30 exceed its quota, its quota grows
  to include them all, and the A2 and A3 bars keep their fixed allowed counts (decision 7).
- **A2 40, A3 40 and A4 20**, filled by a seeded random draw without replacement after the top 30.
- **Skips.** In A1 and A5 a skipped entry ("no pack to hand", or a pack that prints values only per
  serving) is **not replaced**; it is recorded and reported, and more than 6 skipped A1 entries fail the
  A1 bars (fail closed). In A2 to A4 a skipped entry is replaced by the next one in the seeded order and
  recorded.
- Expected effort: up to about 180 checks, including replacements.

### 3.3 What the owner records (`pfd-review-sheet-v1`)

The skill writes a private review sheet in the versioned format `pfd-review-sheet-v1` (columns:
`stratum`, `entry_id`, `title`, `matched`, `values`, then one verdict column per check). The sheet is
**written and scored by scripts; the agent never reads it, the verdicts or any per-entry output**, only
the counts (section 7). Each verdict uses exactly one token; the scorer rejects any other token or an
unknown schema version:

- **A1, A5 product:** `right_product`, `wrong_variant` (flavour, fat level, recipe), `wrong_product`,
  `skipped`.
- **A1, A5 each of the eight label nutrients:** `agrees`, `differs`, `not_on_pack`, `missing_in_entry`.
  "Agrees" means equal to the pack's printed **per 100 g (or per 100 ml)** value at the pack's own
  rounding; sodium is compared through the pack's printed salt. `missing_in_entry` means the pack prints
  the value but the entry has none: unknown is never counted as wrong or right. An entry value that the
  pack does not print is `differs`, because the entry claims a value the pack does not support.
- **A2:** `same_food_same_state`, `same_food_other_state`, `different_food`, `skipped`.
- **A3:** `sensible`, `misleading_close`, `misleading_other_state`, `skipped`.
- **A4:** `nothing_suitable`, `match_missed`, `skipped`.

The owner is the only judge. Verdicts are never inferred by a model.

### 3.4 Measures

Counts per stratum, over **checked** entries (skips excluded and reported): wrong product or wrong
variant (A1); nutrient disagreements over **checked values**, where checked values are `agrees` plus
`differs` (`not_on_pack` and `missing_in_entry` excluded, and `missing_in_entry` reported as its own
count) (A1, A5); different food or other state (A2); misleading, split into
close and other-state (A3); match missed (A4). Each count is reported with a 95 per cent Wilson
interval. For nutrient values the interval is approximate, because values cluster within an entry; it
is informational in every case.

## 4. Part B: search quality (a query set from the owner's own words)

### 4.1 Building the query set (`pfd-query-set-v1`)

- **Sources:** the food names in the owner's daily food logs and the foods in their notes (already
  extracted privately), with the owner's own spellings and variants exactly as written there.
- **Added by the owner:** the way they would actually type a search for twenty foods they eat often,
  and **twenty** foods they eat that are **not** in the database (negative queries).
- **Target size:** about 160 queries, 20 negative.
- **Who handles it.** The owner types the added queries and every expected answer into the private
  file directly. A script assembles the file and draws the split; the agent never reads the query
  text, the expected answers, the held-out file or any per-query output, only counts. The owner works
  in a spreadsheet template and finds entry and generic record IDs with an owner-only lookup that
  prints to their screen, alphabetically and without a score, so it is not the ranking under test
  (the tool's README gives the steps).

### 4.2 Expected answers

For each query the owner records, before any ranking is run, exactly one answer kind:

- `entry`: one or more acceptable database entry IDs, and the expected step: title or alias (1),
  variety (2) or concept (3);
- `generic`: one or more acceptable generic records (source and record ID) that the owner names;
- `none`: no database entry should come first (every negative query, and any others the owner marks).

### 4.3 Development and held-out sets

The query set is split by a seeded draw, stratified so the negative queries divide evenly (10 and 10):
about 60 per cent **development**, 40 per cent **held-out** (about 64 queries, 10 negative). The two sets
live in **separate private subfolders**. The held-out set is sealed (section 2) before any ranking code
exists and is opened once, at the release check, with at most one rerun for an infrastructure failure
(as in the UK fresh-set protocol); the scorer records each held-out run as a `run-heldout` line in the private `seals.txt` and
refuses a third. Implementers and harness operators never read the held-out file or
its per-query output, and every result states any exposure. Development iteration is counts-only for
agents too: only the owner may open per-query development output, and each time they do, the date is
recorded in the private folder and reported with the release-check result. If a held-out bar fails, the fresh held-out
set comes from **new queries the owner types after the failure**, never drawn from the development set,
of at least the same size and the same number of negatives.

### 4.4 Measures

For a query with answer kind `entry` or `generic`:

- **Top-1 acceptable:** an acceptable result is first. An empty list, or a non-acceptable result
  first, is not acceptable.
- **Top-3 acceptable.**
- **Step correct** (`entry` only): among top-1 hits, the step matches the expected one.
- **Wrong generic first** (`generic` only, informational): a generic record is first that the owner did
  not name.

For a query with answer kind `none`:

- **Acceptable** when no database entry is first: an empty list, or a generic record first, is
  acceptable.

For every query:

- **Wrong entry first:** a database entry comes first that is not an acceptable answer. This is the
  failure that matters most, because the owner may log it without noticing.

**Denominators.** Top-1 acceptable is computed over all queries, using the rule for each answer kind.
Wrong entry first is computed over all queries. Negative false hits are the `none` queries with a
database entry first, over the `none` queries. So one negative false hit counts once in each of those
three measures.

### 4.5 Regression with an empty database

Three checks, all required:

1. **FoodSearchQuality:** all six `--verify-report` checks pass with the committed
   `retrieval-metrics-*` reports byte-unchanged in the diff.
2. **Ordered results:** a new Swift test asserts that, with an empty database store, ranking v12 and
   the frozen v11 reference give the **same ordered candidate ID list** for every query in
   retrieval-scenarios v3 to v8. The frozen v11 reference is a committed golden file in the versioned
   format `pfd-v11-ranking-golden-v1` (scenario version, query ID and ordered candidate IDs, all
   synthetic), stored with the FoodLedgerKit test fixtures and generated from v11 before v12 code lands;
   its hash is in the Freeze list.
3. **FoodQueryEvaluation:** `--gate` passes with its fixture and runner unchanged. It checks the query
   parser, not ranking, so it is recorded as an unaffected parser gate.

## 5. When each part runs

| Phase | What runs | Uses |
|---|---|---|
| E0 | This plan | nothing private |
| E1a | Scoring tool and synthetic tests committed; CI step added | synthetic only |
| E1b to E1d | Freeze the release, draw the Part A sample, build and seal the query set | private workspace |
| E2 | Owner checks the Part A sample | private review sheet |
| E3 | Part A results, counts only, in a results file in this repository; section 6 consequences applied to the export | counts only |
| Implementation | Part B on the **development** set, locally (section 5.1) | development set (private) |
| Release check | Part B on the **held-out** set, once, after the implementation is frozen | held-out set (private) |

Implementation does not start until E3 is complete and its section 6 consequences are applied to the
exported file. A failed Part A bar changes the export, not the implementation plan (decision 3).

### 5.1 Running Part B against the real Swift code, privately

Part B runs as an **opt-in, local-only** FoodLedgerKit test, outside the CI scheme, following the UK
fresh-set step tests:

- It runs only when `WHR_PFD_EVAL_DIR` points at the private evaluation folder and `WHR_PFD_EVAL_STEP` is
  `run-dev` or `run-heldout`. With the variable unset it is skipped, and a skipped run is never
  evidence: development and held-out results come only from a local run, never from CI.
- With the variable set, a missing, unsealed or changed file **fails the run visibly**; it never passes.
- It refuses a folder inside a git working tree or readable by other users (the same refusal as the
  UK fresh-set `privateFolder`, with its own test).
- It imports the private file through the shipped importer into a temporary store and queries the
  production composite with ranking v12, built from **local sources only**: the bundled generic
  sources and that temporary store, with no network transport, so no query text can leave the Mac. A
  contract test asserts the runner's composition has no network-backed source. It writes the ordered
  candidate IDs per query **to the private folder only**, in the versioned format
  `pfd-ranking-output-v1` (release ID, query ID, ordered candidate IDs). It prints counts only; assertion messages never contain query text, titles
  or entry IDs.
- One pinned Python scorer (section 7) turns that output into counts.

## 6. Acceptance bars (owner sets these before any result is seen)

The bars below were **accepted by the owner as proposed on 7 November 2026**, before any result was
seen. They are measurement thresholds for this software, not nutrition targets. Each failing stratum
has a fixed consequence that removes the risk rather than relaxing the bar.

| Measure | Bar | If it fails |
|---|---|---|
| A1 wrong product or wrong variant | at most 2 checked entries, whatever the number of skips | drop Open Food Facts label values from the import (entries keep their generic reference) |
| A1 nutrient disagreement | at most 3 per cent of checked values | as above |
| A2 different food or other state | at most 2 of 40 | no merges: every generic reference becomes a separate candidate |
| A3 misleading | at most 4 of 40 | drop all separate candidates (close and other-state); merges are unaffected |
| A4 match missed | informational | improve matching before the next release; no bar |
| A5 owner label value disagrees with the pack | at most 3 per cent of checked values; no A5 entries means "not assessed", not a pass | hold owner label values out of the import until the intake step is fixed and re-checked |
| B wrong entry first (held-out) | at most 3 per cent | not released; fix ranking and re-run on a fresh held-out set (section 4.3) |
| B negative false hits (held-out) | at most 5 per cent | as above |
| B top-1 acceptable (held-out) | at least 85 per cent | as above |
| B regression | all three checks of section 4.5 | not released |

**How a bar is judged.** Each bar is judged on the **observed count**: the result passes when the count
is within the bar. The 95 per cent interval is reported beside it for information and does not decide
the result. A percentage bar allows the largest whole count within it (rounding down; for "at least",
the smallest whole count at or above it), computed on the actual denominator. At the planned sizes this
means: A1 wrong product or variant at most 2; A1 nutrient disagreements at most 13 of up to 464 checked
values; A2 at most 2 of 40; A3 at most 4 of 40; A5 at most the largest whole count within 3 per cent of
its checked values (0 below 34 values); held-out wrong entry first at most 1 of about 64; held-out
negative false hits at most 0 of 10; held-out top-1 acceptable at least 55 of 64. The counts for the
actual sizes are recorded in the results file before scoring.

**Export switches.** The A1 and A2 consequences need switches in `export_v1.py` (drop Open Food Facts
values; force every reference to `candidate`). Dropping Open Food Facts values can change an entry's
basis and make a merge newly eligible; such newly eligible merges stay `candidate` in that release,
because A2 never sampled them.

A bar is never moved after its results are seen. A changed bar needs a new revision of this file and a
fresh sample or a fresh held-out set.

## 7. Repository and privacy

- **Scoring tool:** `Tools/PersonalFoodDatabaseEvaluation/` (standard-library Python, run with
  `python3 -I`), with `tests/` on synthetic fixtures, run in CI by a new step in `ios-ci.yml`
  (`python3 -m unittest discover -s Tools/PersonalFoodDatabaseEvaluation/tests -v`), in the same way as
  the existing evaluation tools. Its private-file readers import `workspace_guard` from the skill's
  scripts folder by a path built from the repository root (never the working directory), so the
  git-tree and private-folder refusals are the same code; the CI step runs with that path, so a guard
  change that breaks the scorer fails its tests. The skill's own tests stay local (SKILL.md). When the tool cites
  this file, the file is added to `CODE_READ_DOCS` in `.github/scripts/ci_changes.py` in the same E1a
  commit, so later edits to it run the code jobs.
- **Private, never committed:** the database, the sample and review sheet, the verdicts, the query set
  and its expected answers, the held-out set, `seals.txt`, and any per-entry or per-query output.
- **Never read by the agent:** the review sheet and verdicts, the query text and expected answers, the
  held-out set and any per-query output. Scripts write and score them; the agent sees only counts.
  Earlier, already-recorded agent reading (notes, photos, food titles it maps) is unchanged
  (`privacy-and-egress.md`).
- **In the repository:** this plan; the scoring tool and its synthetic fixtures; the v11 golden file of
  section 4.5; and the E3 and release-check results files in the versioned format `pfd-results-v1`,
  **counts and intervals only**. That format is an allow-list: closed field names, whole-number counts,
  intervals and the release ID; the writer refuses any other key and any other string value, so no
  title, brand, query or entry ID can be written.
- Scoring runs offline with no network access. The query set never leaves the Mac.

## 8. Contract tests for the scoring tool (synthetic)

- Wilson intervals against known values; zero and full counts.
- A synthetic `pfd-review-sheet-v1` with planted verdicts gives exactly the expected counts per
  stratum, including A1 with skips (more than 6 fails both A1 bars; at most 6 keeps "at most 2"),
  `not_on_pack` excluded from checked values, and A5 with no entries reported as not assessed.
- A synthetic `pfd-query-set-v1` with planted rankings gives the expected top-1, top-3, step, wrong
  entry first, wrong generic first and negative counts, including a `none` query with an empty list
  (acceptable) and a positive query with an empty list (not acceptable).
- The scorer rejects an unknown verdict token, answer kind or schema version.
- The seeded sample and split are reproducible from the seed; a changed seed changes them.
- Seals: a seal is never replaced; run and score refuse a missing or changed seal; a second held-out
  run is refused after the one infrastructure rerun.
- Private folder: readers and the Swift step test refuse a folder inside a git working tree or readable
  by others (synthetic temporary folders).
- The opt-in Swift step test is skipped when `WHR_PFD_EVAL_DIR` is unset, and fails when it is set and a
  file is missing or changed.
- The `pfd-results-v1` writer refuses an unknown key or a free string value, and the Swift runner's
  counts pass through the same writer.
- `pfd-ranking-output-v1` and `pfd-v11-ranking-golden-v1` decode and re-encode unchanged; an unknown
  version is refused.
- The Part B runner's composition contains no network-backed source.
- A1 with `missing_in_entry` values: excluded from checked values and reported as its own count; an
  entry value the pack does not print counts as `differs`.
- Part A scoring refuses an unsealed or changed review sheet.
- A changed `workspace_guard.py` or golden file stops the scorer.
- The regression checks of section 4.5.

## 9. Decisions for the owner

1. Decided 7 November 2026: the sample sizes and the always-included top 30 (section 3.2), up to
   about 180 checks.
2. Decided 7 November 2026: the acceptance bars and their consequences, as proposed (section 6).
3. Decided 7 November 2026: a failed Part A bar only changes what is exported (section 6);
   implementation goes ahead, because the importer and search code do not depend on which kinds of
   entry the file contains.
4. Decided 7 November 2026, after a Qodo review and before any result was seen: an A5 bar for the
   owner's own labels; bars judged on the observed count with intervals for information and exact
   allowed counts stated; 20 negative queries split evenly; skips recorded, with more than 6 skipped
   A1 entries failing the A1 bars.
5. Decided 7 November 2026, before any result was seen: if the A3 bar fails, **all** separate
   candidates are dropped from the export, whatever their kind. Close and other-state errors are
   still counted apart for information (section 3.4), with no bar of their own, so the sample size
   is unchanged.
6. Decided 7 November 2026: names that identify the owner leave the merged skill. Shop layouts and
   markers, brand exceptions and aliases, shop prefixes and supplement names move to a private
   config in the workspace (`pfc-private-config-v1`, named by `PFC_CONFIG`), and the skill's tests
   use synthetic names. A rebuild with the old and new code gave byte-identical output, so the
   release under test is unchanged.
7. Decided 7 November 2026, before any result was seen: when the top 30 make the A2 or A3 sample larger
   than 40, the allowed counts stay fixed at 2 (A2) and 4 (A3) whatever the sample size.

## 10. Review record

Revision 3 applies the review findings that change mechanics or close a judging gap without moving a
bar: the scoring tool's home and CI step; the private, local-only Part B run; the freeze and seal
order; the regression's three checks; versioned file formats with closed tokens; the held-out exposure
rule and fresh-set source; owner-named generic answers; the `none`-query and denominator rules; A1 and
A5 skips not replaced (the A1 product bar stays "at most 2", now explicitly over checked entries); the
per 100 g comparison; the stratum order; A5 "not assessed"; the export switches; and the plain-text
seed. A second review of revision 3 added: local-only sources for the Part B run; versioned ranking
output, golden and results formats, with an allow-list results writer; `workspace_guard.py` and the
golden file in the Freeze list; a sealed review sheet; counts-only development iteration; and the
`missing_in_entry` verdict. Decisions 5 to 7 settled the remaining points; nothing is open for the
owner before E1.

Revision 4 (8 November 2026, with E1a) answers the E1a architecture gate: one machine-checked Freeze
list (`freeze-v1.json`, section 11) instead of a list in this file; the golden file's hash recorded
before v12 code rather than at E1a; the sample and purchase-count files named (`pfd-sample-v1`,
`pfd-purchase-counts-v1`) with a version-independent seeded order and a top-30 tie-break; the seal
bundle rule and order shared with the Swift fresh-set protocol; and the held-out run log. It moves no
bar and changes no decision.

## 11. Freeze list

The Freeze list is `Tools/PersonalFoodDatabaseEvaluation/freeze-v1.json` (format `pfd-freeze-v1`). It is
filled in this order, each by a docs commit:

| Step | Entries |
|---|---|
| E1a | `files`: SHA-256 of each scorer file and of `.agents/skills/personal-food-catalogue/scripts/workspace_guard.py` |
| E1b | `release_id` |
| E1c | `seed`, `sample_sha256`, `purchase_counts_sha256` |
| E1d | `heldout_sha256` (the `seal-heldout` bundle hash) |
| Before v12 code | `golden_sha256` and the golden file's path in `files` |

A test fails when a listed file no longer matches its hash, so a scorer change after E1a is visible in
CI and needs a new freeze record.

### 11.1 E1b release record (8 November 2026)

The release under test is `pfc:sha256:55caa60d11a9af23a0a7aff23f6a52b6390ef9d8da05c069b4b3f66295d5088d`
(844 entries; the bytes stay private). It was exported on 7 November 2026 at 19:07 UTC, shortly before
the skill's first commit. On 8 November 2026 the skill at commit
`80889c4940d642538f8b656fa4ee63d7b8c724ea` (the latest commit touching
`.agents/skills/personal-food-catalogue/`) rebuilt it offline with `build.py`, from a copy of the same
working files, into an empty output folder: every entry was identical, and only the `generated` date
differed. Because the release ID is the SHA-256 of the file's bytes, the rebuilt file has a different
ID; the pinned release is the original file, and that commit is the skill that reproduces its entries.
Every command that reads the release compares its ID with `release_id` and refuses a mismatch.

The working mapping files it used (SHA-256):

| File | SHA-256 |
|---|---|
| `work/families.json` | `e4214142742dceb6e78d809c75f34fd1fbd71f9a95b6c3c5d6cbcbbeecf91fb5` |
| `work/mapping-1.json` | `60f5db12d88238d10e86a23adf9a66979a66ace21c2f062fe488c268bc8cdd71` |
| `work/mapping-2.json` | `3739bd52040fbf77ac5676d5806a7ae00e9e9079597112804be1c4b457899657` |
| `work/mapping-3.json` | `e1dd93747a3da322405ec82f2aec24df3e2403ab1d61fc7a206e6e86cb6618cf` |
| `work/mapping-4.json` | `6629a33fc0652d82b33e915930e14cc74e8d0b0ebe6bb2b5856ddcf6d8ace5ba` |
| `work/mapping-validated.json` | `5cd021c4782888fee72511b4102fc4b647b09e0bf6775bf0ae314a09b3e7a02b` |
| `work/usda-mapping-1.json` | `80630227cae6807d1367593ad3e56d443261381c27cb46553cbb2c230df3fc7a` |
| `work/usda-mapping-2.json` | `750d2847574e50cd3856069f5551cc830b215b7d6480b5b394880a162186bed2` |
| `work/intake-registry.json` | `fc97b80adbfb7e0a02b136ee15e9a4498169bf09aa53d58769199da5ee362f6b` |
| `work/intake-mapping-notes-2026-11-07.json` | `c074c6bb0a167e6869f1320f2c532aabbccf93aa3a6d517933c039a416b9b7a8` |
| `work/intake/notes-2026-11-07.json` | `2f5469c969e125aaa9ecbf6ff646305c051bd52dfe6772f62d67e6237791bba7` |

### 11.2 E1c sample record (8 November 2026)

The seed `1072955911` was drawn with `pfd_eval.py draw-seed` and pushed in commit `2bc2941` before the
sample was generated. The purchase counts came from the skill's `purchase_counts.py` (844 entries, 798 with
receipt purchases). From the pinned release, `sample` drew A1 57 (census), A5 1 (census), A2 40, A3 40
and A4 20: 158 entries to check (58 census, 30 top-30, 70 drawn), followed on the sheet by the seeded
replacement order for A2 to A4. A second run from the same inputs gave byte-identical sample, sheet and
purchase-count files. The sample and the purchase-count copy beside it are pinned in the Freeze list;
both stay private.
