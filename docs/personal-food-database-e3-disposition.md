# Personal food database: E3 gate status and evidence audit disposition

Status: **9 November 2026. D1 to D5 are decided (section 7). Plan revision 6 records them and was
approved by the owner the same day; E3 is not final until the steps in section 1 are done.** Written by the
unexposed implementation session from the counts-only handover; it read no private query, expected
answer, held-out file, review note, estimate companion or transcript. Every input count is copied
from that handover; the only derived numbers are the bar arithmetic in section 2. Programme #424,
contract #419.

Implementation stays blocked until E3 is final (plan section 5; owner ruling of 9 November 2026,
no pre-E3 exception). This file says what "final" needs, records how the one non-final measure is
resolved without moving a bar or turning uncertainty into a pass, and records what happens to the
approved estimates. This file itself changes no tool, freeze record, seal, bar or private file;
plan revision 6 adds a freeze row (section 5) and amends one review v2 rule (section 2).

## 1. Where E3 stands

| Measure (bars `v2_proposed`) | Handover count | Bar | State |
|---|---|---|---|
| A1 wrong identity, state or material variety | 5 of 57 entries | at most 2 | not final (stratum has unresolved values) |
| A1 assessed value evidence error | 22 of 407 assessed values, 2 unresolved | at most 3 per cent (12 of 407) | not final |
| A2 different food or other state | passed | at most 2 of 40 | final |
| A3 misleading | passed | at most 4 of 40 | final |
| A4 match missed | informational | none | reported |
| A5 assessed value evidence error | passed | at most 3 per cent | final |

Also recorded: per-entry exclusions withhold 24 values and 2 references (6 entries lose values or
references); the private candidate built with them passes the Python v1 checker. Approving
replacement estimates did not change any historical assessment, and must not.

E3 is final when all of these hold (plan sections 2, 5 and 6):

1. Every Part A measure has a recorded disposition, with no bar moved after its result was seen.
2. A counts-only Part A results file (`pfd-results-v2`) is committed, naming the pinned release.
3. The section 6 consequences and per-entry exclusions are applied to an exported file, checked,
   and its release ID recorded (counts and hashes only).
4. The owner has accepted points 1 to 3 in a dated plan revision.

None of the four is done. The owner approved plan revision 6 and the estimates contract on
9 November 2026; that approval records the decisions, not point 4, which needs the results of
points 2 and 3 first.

## 2. A1: the outcome is already determined

Both A1 bars are exceeded by the observed counts, whatever the two unresolved values turn out to be:

- **Identity bar.** The 5 failed entries are decided entries. Resolving a value assessment cannot
  change an entry's identity, state or variety judgement, so the count stays at 5, above 2.
- **Value bar.** If both unresolved values become `correct`: 22 of 409, allowed 12 (3 per cent of
  409 is 12.27, rounded down). If both become errors: 24 of 409. If either becomes `missing` or
  `present_unquantified`, it leaves the denominator: 22 or 23 of 407 or 408, allowed 12. In every case
  the count is above 12. (407 already excludes the unresolved pair: review v2 counts assessed values
  as `correct` plus `error_*`.)

So no resolution can make A1 pass. The tool still reports `passes: null` and `unresolved: 2`, and
that report must stay as it is: the design rule is that an unresolved stratum "never passes and
never fails until resolved", and the rule is about the tool's verdict, which this file does not
change.

The tool judges the value bar on macro and micro values together and reports the two counts
apart for information (tool README, Part A review v2). The outcome would be the same if the bar
were applied to each separately. Each part's allowed count is rounded down, so the two allowances
together never exceed the combined allowance of 12; 22 or more errors cannot then fit within both,
and at least one part fails under every resolution.

**Options for the disposition**

| Option | What happens | Cost |
|---|---|---|
| **A (recommended).** Record "A1 failed, outcome determined" in a plan revision | The owner records that the A1 consequence applies because the bars are exceeded under every resolution. The results file keeps `passes: null` and `a1_..._unresolved: 2`, with the arithmetic above in the results narrative. The two unresolved values stay counted as unresolved and are withheld (unresolved is never a pass). | One docs revision. No tool change. |
| B. Versioned addendum review | A new private addendum format resolves the two values, is sealed under its own name and scored by a new scorer version. | New tool, seal and freeze entries for an outcome that cannot change. |
| C. Leave A1 non-final | E3 never becomes final, so implementation stays blocked indefinitely. | Blocks the programme. |

Option A resolves by a failure, the conservative direction, moves no bar, reuses no row and keeps
the uncertainty visible. It does not claim the two values were assessed. It does change one closed
rule: review v2 design section 3 says that while a measure is not final "no section 6 export
consequence fires". Plan revision 6 must amend that rule by name, for a failure determined under
every resolution only, and never for a pass.

**Consequence if A1 is recorded as failed** (plan section 6, bars of record): drop every Open Food
Facts label value from the export, keeping only independently checked suitable generic references.
Under the export switch note, a merge that becomes eligible only because Open Food Facts values were
dropped stays `candidate` in that release, because A2 never sampled it. Per-entry exclusions apply
as well. A1 entries that keep no value and no reference are shown as "No nutrition data yet".

## 3. Two releases, not one

The plan allows one kind of rebuild without a new Part A sample: an E3 export that only **drops**
values or candidates under a section 6 rule. Adding approved estimates is not that. So the proposal
splits them:

| Release | Contents | Evaluation it relies on |
|---|---|---|
| **R1**, drops-only | The pinned release with the A1 consequence, the per-entry exclusions, the 2 unresolved A1 values withheld and the "newly eligible merge stays candidate" rule applied. Schema `personal-food-catalogue-v1`, unchanged. | E3 of the pinned release, which the plan carries over to a drops-only export. |
| **R2**, additive | R1 plus approved estimates, in the separate schema `personal-food-catalogue-estimates-v1` ([contract](personal-food-catalogue-estimates-v1.md)). | A new, versioned binding (section 5 below). It never reuses the pinned release ID, its seals or Part B answers as though they described R2. |

The evaluator produces R1 first. R1 is a complete, shippable result even if R2 is never approved.
It is built by `Tools/PersonalFoodDatabaseEvaluation/r1/pfd_r1.py build-r1 --a1 on --a2 off`, which
derives R1 from the pinned file by removal only and proves that it did. One rule there is a
consequence of removal-only: a withheld or unresolved value that is not a label value of its entry
came through the entry's generic reference, so that reference is removed. When a withheld or
unresolved label value is removed, the entry's merge reference becomes a candidate, so the merged
record never fills that nutrient in its place. The unresolved list
covers every stratum, not only A1, because unresolved is never a pass; the evaluator reports it by
stratum.

## 4. Evidence audit disposition for the approved estimates

The handover's audit of the 727 approved estimates (77 reviewed rows) established structural
completeness and copying fidelity only. It did not certify that each source's recipe, state or
fortification describes the food eaten. The owner's approval of each estimate is the semantic
judgement of record, shown as an estimate with its assumption. Under D3 the owner also admitted the
two classes whose evidence is weaker than the rest (aggregator and indexed-copy values), against
the recommendation to withhold them; they are shown as such and never described as checked:

| Class (handover count) | What the audit showed | Disposition for R2 (decided) |
|---|---|---|
| All 727 | finite non-negative value, assumption, locator, source state, basis matching the entry | Precondition for admission, re-checked by the importer (contract section 4). |
| 250 national composition values | match the pinned corpus digest, record, value and unit | Admit as estimates. The app also re-checks each against its bundled corpus at import (contract section 4.3, decision C3). |
| 392 overlaps with existing label nutrients | numerically identical | Count once. Each nutrient has exactly one source in the file (contract section 4.1). Where the label value survives into R1, the label value stays and the estimate is not added. Where the label value is an Open Food Facts value dropped by the A1 consequence, the estimate is admitted only if its own source is independent of that Open Food Facts record (section 4.1 below). |
| 37 aggregator-sourced values | copied faithfully | **Admit as estimates** (D3), labelled "Food database website". The D1 consequence still governs any whose underlying source is Open Food Facts: the builder refuses them while the A1 consequence stands (section 4.1), and the importer refuses Open Food Facts page URLs outright. The evaluator reports how many of the 37 that refuses. |
| 24 page values read from indexed content, not a successful direct page read | copied faithfully | **Admit as estimates** (D3), with `page_access: indexed_copy` and "Page not read directly" shown. The page content itself was never confirmed, and nothing may say it was. |
| Values whose method is `derived` with a transform outside the closed list | not reported in the handover | **Withhold** (contract section 6). The evaluator reports the count. |
| Values whose source is a recipe estimate or a "prior release" | not reported in the handover | Resolve a prior-release value to its underlying source and apply the rules above; withhold recipe estimates (contract section 3.2). The evaluator reports the counts. |
| The remaining values | structurally complete | Admit as estimates. Accuracy is not certified; the label, source, state and assumption are shown. |

The 37 and 24 may overlap; the evaluator reports the size of their union and how many of them R2
admits. Admitting them (D3) is the owner's acceptance of weaker evidence for these values, shown
as such: it is not a check of their source content, and no text may describe them as checked. A
value still withheld under the other rows stays unknown in the app, never zero, and stays
available privately for a later release.

### 4.1 No laundering through the estimate route

An estimate must never bring back a value that E3 withheld. The builder refuses, and the evaluator
counts, any estimate whose source is a record or value withheld by a section 6 consequence, a
per-entry exclusion or as unresolved (the 2 A1 values), including an Open Food Facts value dropped
by the A1 consequence.

For aggregator values, the builder records the aggregator's stated underlying source. A value whose
stated source is Open Food Facts is refused. A value with no stated underlying source is admitted
under D3 and counted separately as "underlying source not stated", so the evaluator's must-be-zero
count covers the stated cases and the unstated ones stay visible. An estimate
with an independent source that happens to agree numerically with a dropped value is admissible:
the evidence, not the number, decides. The importer cannot check this (it never sees the
exclusions), so it is a builder rule with an evaluator count, recorded as such.

## 5. Evaluation binding for R2 (decided, D4; plan revision 6, decision 10)

The "additive estimate release" rule:

1. R2's release ID is the SHA-256 of its own bytes. The evaluator records R1's ID, the hash of the
   estimate companion used and R2's ID together, counts only.
2. **Unchanged entries inherit R1's evaluation.** For every entry, the evaluator checks that R2's
   v1 fields (everything except `estimated_nutrients`) are byte-identical in canonical form to R1's,
   and that `estimate_evidence` touches only the reviewed rows. It reports the count of entries that
   differ outside estimates, which must be zero.
3. **Added estimates are a census, not a sample.** Every admitted estimate is owner-approved, passed
   the structural audit and falls outside the withheld classes of section 4. The evaluator reports
   admitted and withheld counts by class and by macro/micro. There is no accuracy bar on estimates,
   because Part A measures evidence errors in the release under test and the estimates are labelled as
   estimates; adding one would need a new sample and a bar set before results, under plan section 6.
   **This exemption from plan section 2 is proposed after the audit counts (727, 392, 37, 24) were
   known.** Because of that, no results narrative, Settings text or release note may describe R2's
   estimates as evaluated; they are owner-approved estimates, shown as such.
4. **Part B binds to the release that ships.** Ranking reads titles, aliases, varieties and
   concepts, but escalation sufficiency and the fat partition can read nutrients, so the development
   runs and the single held-out run name R2's ID if R2 is to ship, and R1's otherwise. The choice is
   made **before the first development run** and recorded in a new versioned freeze record (added by its own tool phase; `freeze-v1.json`, `freeze-v2.json` and frozen tool hashes stay as they are); it is never changed after.
   Part B binds to R2 only once the estimates contract is accepted and R2 is built and checked. If
   the bound release then does not ship, its Part B result does not carry over to the other
   release: that release needs its own Part B run on a fresh held-out set (plan section 4.3).
   Today the query set, the Part B runner and `score_b.py` all check the pinned release ID, so
   Part B cannot run on R1 or R2 yet. The tool phase that adds the binding record must also make
   the runner and the scorer take the bound release ID from it (answers are keyed by entry `id`,
   which removal-only R1 and additive R2 keep), with synthetic tests, before the first development
   run.

## 6. Who does what

| Step | Who | Reads private data |
|---|---|---|
| Decide D1 to D5 below | owner | no |
| Plan revision 6 recording the decisions | this session (docs only) | no |
| Build R1 with `pfd_r1.py build-r1` (A1 on, A2 off), report counts and ID | separate private-data evaluator | yes |
| Write and commit the counts-only Part A results file and narrative | evaluator writes the counts; this session commits the reviewed bytes | evaluator only |
| Build R2 under the estimates contract, apply section 4, report counts and ID | evaluator | yes |
| Importer, store, Settings, Confirm and estimate provenance on synthetic data | this session, after E3 is final and the contract is approved | no |
| Ranking v12, after the v11 golden file is frozen | this session | no |
| Part B development and held-out runs | evaluator, under the attempt limit | yes |

The evaluator must not implement or tune ranking. This session never reads its per-entry or
per-query output.

## 7. Decisions for the owner

Asked one at a time, each with a recommendation:

- **D1. Decided 9 November 2026 (12:52 UTC): yes.** The owner chose option A: A1 is recorded as
  failed because the observed counts exceed both A1 bars under every resolution of the two
  unresolved values. The tool output keeps `passes: null` and the unresolved count of 2; the two
  values stay unresolved and are withheld; the A1 consequence (drop Open Food Facts values) applies
  to R1. Plan revision 6 records this and amends the review v2 section 3 rule by name. No bar moves.
- **D2. Decided 9 November 2026: yes.** The work splits into R1 (drops-only, schema
  `personal-food-catalogue-v1`, relying on the pinned release's E3) and R2 (R1 plus approved
  estimates, schema `personal-food-catalogue-estimates-v1`, under its own binding). The evaluator
  produces R1 first; R1 stands on its own if R2 is never approved.
- **D3. Decided 9 November 2026: admit them** (the recommendation was to withhold). R2 admits the
  37 aggregator values and the 24 indexed-content values as estimates, with their source type and
  "Page not read directly" shown. Two limits still apply because D1 and the contract require them:
  any value whose underlying source is Open Food Facts is refused while the A1 consequence stands,
  and no text may describe these values as checked. The evaluator reports admitted and refused
  counts for both classes.
- **D4. Decided 9 November 2026: yes.** Plan revision 6 adopts the "additive estimate release"
  binding of section 5 as written: unchanged entries must be byte-identical to R1 (zero differing
  entries), added estimates are a census with no accuracy bar and are never described as evaluated,
  and Part B binds to the shipped release through a freeze record made before the first
  development run.
- **D5. Decided 9 November 2026: R2.** Part B binds to R2, provided the estimates contract is
  accepted and the evaluator has built and checked R2 before the first development run; otherwise
  it binds to R1. Whichever applies is recorded in a freeze record before that run and never
  changed. If the bound release does not ship, the other needs its own Part B run on a fresh
  held-out set (section 5, point 4).
