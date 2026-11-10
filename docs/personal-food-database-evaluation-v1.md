# Personal food database evaluation v1

Status: **revision 7, 10 November 2026. Decisions 1 to 11 are settled. The owner accepted E3 as
final in decision 11, after the steps of the [E3 disposition](personal-food-database-e3-disposition.md),
section 1, were done; implementation may start (section 5). Revision 6 (decision 10) was approved
by the owner on 9 November 2026. Decision 8 authorised the drafting workflow, not any draft query,
answer or review verdict.**
Revision 2 added three clarifications to the bars after a Qodo review
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

1. **Is the database right?** For each kind of entry, how often the estimate rests on the wrong
   basis: a different product, food, preparation state or material variety, or a value whose source,
   basis or derivation is wrong (section 3; since the revision 5 amendment, agreement with a pack is
   no longer the test). This tests contract decision 9 ("Confirm is enough"): an automatic match is
   only safe to show unreviewed if it is rarely wrong.
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
4. **E1d, Part B query set.** Codex drafts queries and expected answers; the owner validates and
   approves every row before any split or seal (decision 8). Then the
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
6 rule: that needs no new Part A sample. Since revision 6, a release that adds approved estimates to
such a drops-only export is an **additive estimate release** with its own binding (decision 10,
point 4): it never reuses the pinned release's ID, seals or Part B answers. Part B answers are keyed by entry `id`, which is stable for a
brand and title (contract section 4), and every result names the release it ran on.

## 3. Part A: evidence-backed estimates

### 3.1 Review standard

The objective is the best supported estimate per 100 g or 100 ml for the food actually eaten.
Review identity, preparation state and materially different variety, then macro and micronutrient
coverage and the evidence for each value. Raw, cooked, drained, dry and prepared states are distinct;
no universal cooking or density conversion is assumed. Unknown is never zero. Pack verification,
pack tiers, serving sizes and portions are outside this review.

Use the pinned release and its pinned national composition corpora first. A matching national
composition record or manufacturer page may improve a missing value. Aggregator records are
secondary candidates. Each proposed value records source and record identifier, source state, basis,
method (direct, derived with its formula, or carried over from a similar food), and uncertainty.
Web-derived values also record URL and date read and remain `page_unconfirmed`. A page which does
not specify the nutrition table's preparation state is recorded as unspecified, not assumed cooked.
Every value remains an estimate; no proposal automatically changes the release.

### 3.2 Existing sample

Keep the pinned 158 initial census, top30 and draw rows and their existing A1 to A5 identifiers for
reproducibility. Those identifiers describe the historical source grouping, not evidence-quality
or pack tiers. Each entry sits in exactly one stratum, assigned in this order by `pfd_eval.py
sample` from the pinned release:

| Stratum | What the entry carries | Sampled | Checked under the section 3.1 standard |
|---|---|---:|---|
| A5 | values the owner typed or confirmed | 1 (census) | identity, state, variety and the evidence of each value |
| A1 | Open Food Facts label values | 57 (census) | the same, for each label value |
| A2 | a same-food generic record merged in | 40 | whether the merged record is the same food, state and material variety |
| A3 | a close or other-state generic record offered separately | 40 | whether the separate candidate is represented accurately (section 3.4) |
| A4 | no values and no reference | 20 | whether a suitable source record was missed |

These counts are read from the pinned release and match the E1c record (section 11.2). The earlier
plan estimated 58 A1 entries and "a few" A5 from the 7 November 2026 build; the pinned release
places 57 in A1 and 1 in A5 under the order above, 58 census entries in all, and the sample itself is
unchanged.

The draw (section 11.2) also includes the 30 most-bought entries in their own strata. Do not redraw, replace rows, modify the pinned release or regenerate the existing sheet.
A missing source or unresolved state is recorded as unresolved and is not a passing check.

### 3.3 Review format and minimal tool change

`pfd-review-sheet-v1` cannot express this rubric. Its eight fixed nutrient columns and stratum-specific
verdicts omit separate state and variety checks, micronutrients and per-value evidence. Preserve
`review/review-sheet.csv` byte-for-byte. Use a separate private `best-estimate-review.csv` keyed by
sheet row, with identity/state/variety proposals, present and missing macro/micro fields, evidence
gaps, state-conflict flags and a reason. Store individual values in `nutrient-evidence.jsonl` and
next-release work in `enrichment-candidates.csv`. These are proposals, not scorer input.

The smallest tool change (proposed in detail in
[personal-food-database-review-v2-design.md](personal-food-database-review-v2-design.md), approved
by the owner on 8 November 2026 and implemented in #443) is a versioned review-v2 row schema plus a nutrient-evidence sidecar, with
parsing, validation, sealing and Part A result/scorer support for the measures below. It needs
synthetic contracts for missing versus zero, state conflicts, derived values, incomplete evidence,
macro/micro coverage and rejection of v1 inputs by the v2 scorer. Existing v1 results remain readable
under their original semantics. The owner approved the design on 8 November 2026 and #443
implements it; Part A sealing and scoring wait for the owner's completed v2 sheet and sidecar.
The owner validates the proposals last. Never coerce the new rubric into old pack-verdict tokens.

### 3.4 Measures

Report checked and unresolved identity/state/variety counts by historical stratum; errors in the
source, basis, state or recorded derivation for assessed values; macro and micro coverage separately;
and counts of missing values a suitable source could supply. Freeze the assessed nutrient inventory
before scoring. Missing, trace and unquantified values are not zero and do not enter numerical-error
denominators. Source disagreement alone is not an error: an error requires evidence of an incorrect
identity, state, basis, transcription or derivation. Report candidate-only values separately from
proposed usable values. A complete micronutrient row means every nutrient in the declared inventory,
not merely every nutrient available from that source.

For the retained generic-match measures, the proposed v2 scorer uses these explicit row outcomes:

- **A2:** count one failed entry if a merged reference has a different food identity, an incompatible
  preparation state or a material variety difference. Multiple failures in one entry count once.
  A missing required judgement is unresolved, never counted as a passing entry. The values a merged
  reference supplies are also assessed for source, basis, state, transcription and derivation errors
  under the same rule as A1 and reported as A2 assessed value evidence errors (informational, no
  bar); a correct identity does not excuse a wrong value.
- **A3:** a separate candidate is sensible only when its food relationship and material differences
  are accurately represented, its source state is explicit and its values are never silently merged.
  Count `misleading_other_state` when a state-incompatible source is represented as equivalent;
  otherwise count `misleading_close` for a misleading identity or material variety relationship.
  Other-state takes precedence, so each entry counts at most once. A clearly labelled alternative
  state may be sensible as a separate option, but cannot supply values for the target state.
- **A4:** count `match_missed` only when the review names an available source record with a checked
  suitable identity, state, variety and basis. Count `nothing_suitable` only after the documented
  source search finds no suitable record. An unsearched or ambiguous case is unresolved.

These mappings are part of the proposed v2 design and do not authorise feeding new tokens into v1.

## 4. Part B: search quality (a query set from the owner's own words)

### 4.1 Building the query set (`pfd-query-set-v1`)

- **Draft sources:** Codex directs local offline scripts to draft from the pinned catalogue, including
  its titles, aliases, varieties and concepts. These are proposed searches, not evidence of the owner's actual wording or habits.
- **Owner validation:** the owner corrects every query and expected answer, confirms twenty frequent
  foods and twenty foods they eat that are absent from the database, and approves every row. For each
  query the owner also confirms it is worded as they would actually type it, or rewrites it in their own
  words; a catalogue title copied as a query tests indexing, not the owner's search. Before the owner
  edits anything, the drafted `queries/query-template.csv` is copied to a private archive file whose
  hash is recorded in the private draft status. Kept-versus-reworded counts come from comparing the
  approved CSV with that archive row by row, and the results narrative reports both counts beside
  Part B, so a reader can see how much of it rests on catalogue wording.
- **Target size:** about 160 queries, 20 negative, with entry, generic and none answers and all three
  entry steps represented. The existing split, bars and denominators do not change. Before `split`,
  the approved set's counts by answer kind and by entry step (counts only) are checked: if any answer
  kind or entry step is missing, or there are not 20 negatives, the set is corrected and reassembled
  first, because `assemble-queries` validates rows, not composition.
- **Who handles it:** Codex runs local scripts to write the private CSV draft and runs
  `assemble-queries` until it validates. Only counts and hashes return to the model.
  The draft remains unapproved. No split or seal runs until the owner approves all rows. `lookup`
  remains owner-only and interactive; the drafting agent never runs it. Any correction requires the
  unsplit JSON to be reassembled before approval and splitting.
- **Reporting:** every results report states "agent-drafted and owner-approved query set" only after
  approval. Until then it states "agent-drafted, awaiting owner approval". Record this provenance in
  the results narrative beside the counts, without adding fields to the closed `pfd-results-v1`
  format or changing its writer in this documentation revision.

### 4.2 Expected answers

For each query the owner validates and approves, before any ranking is run, exactly one answer kind:

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
refuses a third. The session or agent that implements ranking must never read the query set, its answers or the
held-out folder. A session or agent exposed while drafting is excluded from ranking implementation;
use a separate unexposed session without inherited private context. Implementers and harness operators
never read the held-out file or
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
Under decision 10, E3 produces two files in order: R1, the drops-only export of the pinned release,
and then R2, R1 plus approved estimates under the additive estimate binding.

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

Part B bars remain as accepted on 7 November 2026. These are software-quality thresholds, not
nutrition targets.

**Superseded Part A bars.** The Part A bars the owner accepted on 7 November 2026 (decision 2) were
the bars of record until decision 9 replaced them, before any Part A result was scored. They are
kept here as the record of what was accepted first:

| Measure | Bar | If it fails |
|---|---|---|
| A1 wrong product or wrong variant | at most 2 checked entries, whatever the number of skips | drop Open Food Facts label values from the import (entries keep their generic reference) |
| A1 nutrient disagreement | at most 3 per cent of checked values | as above |
| A2 different food or other state | at most 2 of 40 | no merges: every generic reference becomes a separate candidate |
| A3 misleading | at most 4 of 40 | drop all separate candidates (close and other-state); merges are unaffected |
| A4 match missed | informational | improve matching before the next release; no bar |
| A5 owner label value disagrees with the pack | at most 3 per cent of checked values; no A5 entries means "not assessed", not a pass | hold owner label values out of the import until the intake step is fixed and re-checked |

At the planned sizes these allowed A1 wrong product or variant at most 2, A1 nutrient disagreements at
most 13 of up to 464 checked values, A2 at most 2 of 40, A3 at most 4 of 40, and A5 at most the largest
whole count within 3 per cent of its checked values (0 below 34 values). The A1 nutrient and A5 bars
compare values with a pack, which the revision 5 amendment takes out of scope, so they cannot be scored
on the new rubric.

**Part A bars of record (accepted 8 November 2026, decision 9).** For the section 3 rubric, accepted
by the owner before any Part A result was scored; the tool records the choice as `part_a_bars`
`v2_proposed` in `freeze-v2.json` and locks it on the first scoring run (review v2 design, section
4). The tool exists (#443); Part A scoring waits for the owner's completed v2 sheet and sidecar. Earlier preliminary reviews of the
proposals have occurred; this is not a claim of preregistration before all evidence.

| Measure | Bar | If it fails |
|---|---|---|
| A1 wrong identity, state or material variety | at most 2 checked entries, with unresolved entries reported separately | drop Open Food Facts values; retain only independently checked suitable generic references |
| A1 assessed value evidence error | at most 3 per cent of checked values | as above |
| A2 different food or other state | at most 2 of 40 | no merges: every generic reference becomes a separate candidate |
| A3 misleading | at most 4 of 40 | drop all separate candidates (close and other-state); merges are unaffected |
| A4 match missed | informational | improve matching before the next release; no bar |
| A5 assessed value evidence error | at most 3 per cent of checked values; no A5 entries means "not assessed", not a pass | hold unsupported values out until their evidence is corrected and re-checked |

Part B bars, unchanged:

| Measure | Bar | If it fails |
|---|---|---|
| B wrong entry first (held-out) | at most 3 per cent | not released; fix ranking and re-run on a fresh held-out set (section 4.3) |
| B negative false hits (held-out) | at most 5 per cent | as above |
| B top-1 acceptable (held-out) | at least 85 per cent | as above |
| B regression | all three checks of section 4.5 | not released |

**How a bar is judged.** Each bar is judged on the **observed count**: the result passes when the count
is within the bar. The 95 per cent interval is reported beside it for information and does not decide
the result. A percentage bar allows the largest whole count within it (rounding down; for "at least",
the smallest whole count at or above it), computed on the actual denominator. For Part A, count assessed values under the new declared inventory, reporting macro and micro
denominators separately; do not reuse the old eight-column denominator. Proposed coverage bars are
informational, with all gaps and unresolved rows visible. A stratum containing unresolved required
identity/state/evidence checks cannot receive a final pass. For Part B the planned held-out counts
remain wrong entry first at most 1 of about 64, negative false hits 0 of 10 and top-1 acceptable at
least 55 of 64. The actual denominators are recorded before scoring.

**Per-entry exclusion, independent of bars.** Any identified wrong identity, incompatible merged
state or material variety mismatch withholds the affected source values and reference, regardless
of whether the entry was sampled as A1, A2, A3, A4 or A5. So does any individual value whose own
evidence shows a wrong basis, state, transcription or derivation: that value is withheld until its
evidence is corrected and re-checked, even when the stratum's error count is within its bar. A
threshold is not permission to retain a known error. A reference lacking the required review remains a candidate pending review, never a
new merge after label values are removed. This includes generic references attached to A1/A5 entries.
The owner-approved v2 tool phase must implement and test these exclusions alongside stratum-wide
failure consequences; this documentation revision performs no export changes.

**Export switches.** The A1 and A2 consequences need switches in `export_v1.py` (drop Open Food Facts
values; force every reference to `candidate`). Dropping Open Food Facts values can change an entry's
basis and make a merge newly eligible; such newly eligible merges stay `candidate` in that release,
because A2 never sampled them.

**A1 outcome determined (revision 6, decision 10).** The A1 result was scored with 2 unresolved
values, so the tool reports `passes: null`. Both A1 bars are exceeded under every resolution of
those values (E3 disposition, section 2), so the owner recorded A1 as failed and its consequence
applies to R1. This amends one rule by name: review v2 design section 3, "Unresolved and bars",
says no section 6 export consequence fires while a measure is not final. From revision 6 that rule
has one exception: a consequence fires when the measure **fails under every possible resolution**
of its unresolved items, and the owner records that in a dated revision of this file. It never
applies to a pass. The tool's verdict is unchanged: the results file keeps `passes: null` and the
unresolved count, and the unresolved values stay withheld.

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
- **Bounded drafting and semantic review (decision 8):** query drafting remains local-script work,
  returning aggregate counts and hashes only. On 8 November 2026 the owner explicitly authorised
  relevant product titles, matched record names and preparation states to enter Codex model context
  for identity and generic food/state review. Read only a filtered projection of those fields with
  row keys for alignment, not whole catalogue or sheet files. This sends the permitted fields to the
  model provider. Beyond the drafting session that writes them (see the next item), it does not
  authorise query text or expected query answers to enter model context, nor private configuration,
  unrelated notes or held-out contents; nutrient evidence is covered by the amendment below.
  Provisional semantic decisions are saved privately; user-facing replies, repository files,
  issues, PRs, commits and external code-review payloads contain counts and hashes only.
  See `privacy-and-egress.md` for this explicit, owner-requested exception. It does not approve
  Open Food Facts queries. The drafting/reviewing session cannot implement ranking. After splitting,
  no agent opens the held-out folder or per-query output. The best-estimate amendment (section 9)
  supersedes pack checks, permits nutrient evidence in model context and authorises
  food-description-only web research; uncertain identity/state cases remain explicit.
- **How the query boundary is kept:** query text and expected answers are written by local scripts
  under the drafting agent's direction, and only counts and hashes are printed back. Because the
  agent directs the drafting, query wording can still be in that drafting session's model context.
  The boundary is therefore that query text never leaves the drafting session (no repository file,
  issue, PR, commit, review payload or reply) and that the session never implements ranking, not that
  no model ever sees it. This is a procedural control, not one a script enforces: nothing prevents a session from opening the query
  files or a whole sheet. That is why any session that drafted or reviewed is treated as exposed and
  excluded from ranking implementation whether or not it read query text, and why every result states
  the exposure.
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

8. Decided 8 November 2026: Codex directs local offline scripts to draft E1d queries and pre-fill
   E3 identity and generic food/state proposals in a separate private file, returning counts and
   hashes only. This authorises the workflow, not the draft contents; the owner validates every row
   last. Pack value checks remain
   exclusively the owner's and are never pre-filled. Results disclose agent-drafted, owner-approved
   query provenance. The ranking implementer must be a separate unexposed session or agent and never
   read the query set or held-out folder. Decisions 1 to 7, acceptance bars, sample, release, seed and
   split rules remain unchanged. No split, seal or scoring is authorised before owner approval.
   Later on 8 November 2026, after being told that the selected fields reach the model provider,
   the owner explicitly authorised relevant titles, matched record names and preparation states
   for semantic identity review. This narrow exception replaces the counts-only model-input rule
   for those fields alone. It does not approve provisional decisions, nutrient comparisons or seals.

### Subsequent revision 5 amendment: best-estimate review

The owner replaced pack and serving checks with the section 3 rubric before any seal. Local evidence
comes first; food-description-only web research is authorised where it improves a source or fills a
nutrient gap, with national composition databases and manufacturers preferred over aggregators.
Requests contain no receipts or personal data; failures use backoff. Nutrient evidence read for this
work may enter model context and is stored privately, with web values marked `page_unconfirmed`.
The earlier offline-only and nutrient-context restrictions are superseded for this work alone.
Query texts and expected answers remain local-script-only. Private configuration and held-out
contents remain excluded. This supersedes earlier pack-check statements in revision 5, including
decision 8's owner-only pack checks, which no longer exist. Decision 9 below settles the Part A
bars; Part B bars and ranking blinding do not change. Approval of this workflow is not approval
of individual rows, the proposed Part A bars, the tool migration or seals. The alternate private
format is authorised; the existing sheet, pinned inputs and frozen tools remain untouched.

9. Decided 8 November 2026, before any Part A result was scored: the owner approved the review v2
   design ([personal-food-database-review-v2-design.md](personal-food-database-review-v2-design.md))
   and accepted the rubric Part A bars of section 6 (`v2_proposed`) in place of the 7 November bars,
   whose pack-comparison measures cannot be scored under the rubric. Part B bars are unchanged. The
   implementation of the v2 tool is its own phase.
10. Decided 9 November 2026, after the Part A v2 result was scored and before any Part B run (the
    owner's decisions D1 to D5 of the [E3 disposition](personal-food-database-e3-disposition.md)).
    No bar moves.
    1. **A1 disposition.** A1 is recorded as failed because both A1 bars are exceeded under every
       resolution of its 2 unresolved values; section 6 records the rule this amends. The A1
       consequence and the per-entry exclusions apply to R1.
    2. **Two releases.** R1 is the drops-only export of the pinned release (schema
       `personal-food-catalogue-v1`) and relies on the pinned release's E3. R2 is R1 plus approved
       estimates (schema `personal-food-catalogue-estimates-v1`,
       [contract](personal-food-catalogue-estimates-v1.md)). R1 is produced first and stands alone.
    3. **Evidence classes.** R2 admits the aggregator-sourced and indexed-copy estimates as labelled
       estimates, against the recommendation to withhold them: they are accepted as weaker evidence
       and never described as checked. The 2 unresolved A1 values stay withheld. Any value whose underlying source is Open Food Facts is refused while the A1
       consequence stands, and no estimate that restores a value withheld by E3 is admitted.
    4. **Additive estimate binding.** R2's ID is the SHA-256 of its bytes, recorded with R1's ID
       and the estimate companion's hash (counts and hashes only). Entries R2 leaves unchanged must
       be byte-identical to R1 in canonical form outside `estimated_nutrients`, with zero
       differences reported. Added estimates are a census reported by class, with no accuracy bar.
       That exemption from section 2 was proposed after the audit counts were known, so R2's
       estimates are never described as evaluated.
    5. **Part B binding.** Part B binds to R2 if the estimates contract is accepted and the
       evaluator has built and checked R2 before the first development run, and to R1 otherwise.
       The choice is recorded in a freeze record before that run and never changed. If the bound
       release does not ship, the other needs its own Part B run on a fresh held-out set (section
       4.3).
11. Decided 10 November 2026: the owner accepts E3 as final. The four steps of the
    [E3 disposition](personal-food-database-e3-disposition.md), section 1, are done: D1 to D5
    (decision 10); the counts-only results file `part-a-results-v2.json` (SHA-256
    `95715821858e41779432382ecb6aac51401ec3a18f6633279e1d208998e0e791`); R1 built with release ID
    `pfc:sha256:b883d5c6c9be35825609da9cc0fdbafd148fc93601b1c58b87fc744c6355ed4e`; and this
    acceptance. No bar moves, and no tool, seal, freeze record or frozen hash changes.
    1. **R1 ships first, as the floor.** It keeps 7 of 416 label values and leaves 167 entries with
       no nutrition data; that is the conservative result the bars require, accepted as it is.
    2. **R2 is the planned next step.** Its aim is a labelled best estimate for every entry, under
       decision 10 and the [estimates contract](personal-food-catalogue-estimates-v1.md): per-nutrient
       evidence, always shown as an estimate, never from an Open Food Facts record and never sourced
       from a value or record E3 withheld (contract section 3.1).
       Unknown stays unknown only where no admissible source exists. R2 is not a condition for
       implementation. Decision 10, point 5 is unchanged: Part B binds to R2 if it is built and checked before the first development
       run, and to R1 otherwise.
    3. **Implementation may start** (section 5), with the importer as its own phase and
       architecture gate ([import contract](personal-food-catalogue-import-v1.md)).

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

Revision 5 (8 November 2026) records decision 8 and updates sections 2, 3, 4 and 7 consistently.
Drafts are not approvals or measured results. The private review guide gives the owner the approval,
split, seal and scoring sequence; `heldout_sha256` is added in a later docs commit after approval and
sealing. It changes no tool or schema. Its best-estimate amendment proposed replacement Part A
bars, which decision 9 accepted on 8 November 2026 before any Part A result was scored; the
7 November bars stay in section 6 as the superseded record.

Revision 6 (9 November 2026) records decision 10, adds the additive estimate release to section 2,
the two-release order to section 5, and the "A1 outcome determined" rule to section 6, which
amends review v2 design section 3 by name for a failure determined under every resolution only. It
moves no bar, changes no tool, seal or frozen hash, and adds a freeze row (section 11) that a later
tool phase fills.

Revision 7 (10 November 2026) records decision 11, the owner's acceptance of E3 (E3 disposition,
section 1, point 4). It moves no bar and changes no tool, seal, freeze record or frozen hash.

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
| Before the first Part B development run | the Part B release binding (decision 10, point 5): R2's ID, or R1's. Recorded in a new versioned freeze record added by its own tool phase. That phase keeps the sealed query sets unchanged, validates their answer entry IDs against the bound file (counts only), and adds a new scorer version that links a pinned-ID query set to a bound-ID ranking output only through the binding record ([E3 disposition](personal-food-database-e3-disposition.md), section 5, point 4); `freeze-v1.json`, `freeze-v2.json` and every frozen tool hash stay as they are |

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
receipt purchases), from the working catalogue with SHA-256
`bbd411ef433b1274a98d904787fc2463b9e0bcb6271da37746ad6b9069b5a1c3`, which holds exactly the foods of the
pinned release (the script refuses otherwise). From the pinned release, `sample` drew A1 57 (census), A5 1 (census), A2 40, A3 40
and A4 20: 158 entries to check (58 census, 30 top-30, 70 drawn), followed on the sheet by the seeded
replacement order for A2 to A4. A second run from the same inputs gave byte-identical sample, sheet and
purchase-count files. The sample and the purchase-count copy beside it are pinned in the Freeze list;
both stay private.

### 11.3 E1d held-out record (9 November 2026)

The owner approved the 160 agent-drafted queries in the separate query-exposed drafting session,
before any split. That session then ran `split`, which divided them into 94 development and 66
held-out queries, each with 10 negatives, and `seal-dev` and `seal-heldout` sealed both sets at
`2026-11-09T08:25:06Z` and `2026-11-09T08:25:12Z`. This docs commit came later: the owner's
"Yes, open it" at `2026-11-09T10:29:18Z` (the WHR-424-E1d ledger window) authorised only recording
the hash, not the queries or the seals. The Freeze list records the `seal-heldout` bundle
hash as `heldout_sha256`: `cf74b225882b681e66fa05e2c892f751d19d0f0ae850daf2aa2018bd76543aab`. It was
copied from the private seal log, and the held-out contents were not read. A held-out Part B run
refuses a bundle whose seal differs from this hash.

The review v2 freeze record pins `freeze-v1.json` without `heldout_sha256` and `golden_sha256`
(`freeze_v2.v1_pin`), so this entry leaves `freeze-v2.json` and the recorded Part A v2 score
binding unchanged. No tool file, schema or bar changes.
