# Personal food database: labelled estimates on catalogue v2 (proposal)

Status: **proposal, 15 November 2026, revised 16 November 2026 after a blind review (section 9).
Not accepted, nothing implemented.** It asks the owner for the six decisions in section 8. No app
code, skill code or fixture changes with this document. Programme #424, base contracts #419.

It is a delta on two accepted contracts and repeats neither:
[approved estimates v1](personal-food-catalogue-estimates-v1.md) (accepted 9 November 2026, not yet
implemented) and [import v2](personal-food-catalogue-import-v2.md) (approved 13 November 2026,
implemented). Everything in those documents that this one does not name stays as written.

## 1. Why a delta is needed

Two things happened after the estimates contract was accepted.

1. **The catalogue moved to schema v2.** Estimates v1 is defined as "v1's keys plus
   `estimated_nutrients` and `estimate_evidence`". The skill has written only
   `personal-food-catalogue-v2` since 13 November, so today no file can carry both a per-serving
   Open Food Facts value and an estimate.
2. **The measured gap is mostly a state gap, not a missing-source gap.** Counts from the owner's
   private catalogue on 15 November 2026 (844 entries; counts only, no names or values):

   | Entries | Count |
   |---|---:|
   | With a value of their own (a label value or a `merge` reference) | 408 |
   | No value of their own | 436 |
   | of which matched to the same food in the same state, not merged because the entry's state is not `raw` or `cooked` | 102 |
   | of which matched only to a close record | 213 |
   | of which no reference | 121 |
   | Labelled entries with no `merge` reference, so no micronutrient on the entry | 111 |
   | Labelled entries missing fibre / missing sodium | 40 / 25 |

   Fibre on an entry's own row: 92 from a label and 240 from a merged record (227 CoFID, 13 USDA),
   332 in all. Of 278 CoFID `merge` references, 40 name a record with no fibre value.

   The 102 same-food entries are foods sold as they are eaten or used (cheese, butter, oil, salt,
   tinned and dried foods). Import v1 section 4.1 merges only `raw` and `cooked`, and estimates v1
   section 2.3 rejects an estimate that names the entry's own reference record. Together they leave
   no route for these entries to carry a value, although the right record is already known. Their
   record is still offered as a separate "Generic" candidate, so nothing is lost on Confirm today;
   the entry itself is empty.

## 2. Schema `personal-food-catalogue-estimates-v2`

A new schema string, a third value for the existing codec. **It is import v2 plus the two estimate
fields of estimates v1, with the own-reference rule changed (section 3).**

- Top level: exactly v2's keys plus `estimate_evidence`. Entry: exactly v2's keys plus
  `estimated_nutrients`. Both required, both may be empty.
- `estimated_nutrients` and `estimate_evidence` are exactly estimates v1 sections 2.1 and 2.2: the
  same keys, closed vocabularies, limits, `pfe:` evidence IDs and transform list (its section 6).
- Every import v2 rule applies to the v2 part (projection v6, the serving transform, its rule codes),
  and every estimates v1 rule of section 2.3 applies to the estimate part, except the own-reference
  rule as changed below.
- Release identity is unchanged: `pfc:sha256:` of the exact bytes, `schemaVersion` the file's own
  schema. A file with no estimate is still written as plain v2, so a catalogue without estimates is
  byte-identical to today's.

**Existing files are untouched.** The app's codec today is one codec that dispatches on the schema
string and knows `personal-food-catalogue-v1` and `-v2` (`PersonalFoodDatabaseSchema`). Estimates v2
becomes its third value. Support, with decision P1 as recommended:

| Schema | App importer | Skill and evaluation tools |
|---|---|---|
| `personal-food-catalogue-v1` | accepted, rules, codes and golden hashes unchanged | unchanged |
| `personal-food-catalogue-v2` | accepted, unchanged | written when a catalogue has no estimate |
| `personal-food-catalogue-estimates-v2` | accepted (new) | written when a catalogue has an estimate |
| `personal-food-catalogue-estimates-v1` | **rejected** with the existing `schema` code, active release unchanged | stays the R2 builder's format, validated by its own tool |

Each schema's rules apply only to files that declare it. Stored releases, manifests, records,
archives and exports decode and re-encode unchanged. The store keeps its fixed file name (import v2
decision 4) and its manifest accepts the new schema as a third known value. An R2 companion is not
importable by the app; if it should ever be, that is a rebuild as estimates v2, never a conversion
in the app.

## 3. The changed rule: an estimate may cite the entry's own candidate record

Estimates v1 section 2.3 rejects "a `national_composition` estimate whose `composition_source` and
`source_reference` name the same record as that entry's `generic_reference`, whatever its role".
Estimates v2 allows it for a `candidate` record under the conditions below. **This is an identity
exception and is proposed as one:** amendment A2 to
[identity contract](food-identity-nutrition-contract.md) section 8, recorded there when this
proposal is accepted. Section 8 makes a value with an unknown or contradictory decisive attribute
ineligible; A2 lets an owner-approved, labelled estimate cover an **unknown** attribute and never a
**contradictory** one. Import v1 decision 8 and amendment A1 (the merge rule) are not changed.

### 3.1 What the file must satisfy

| Rule | Code | Checked by |
|---|---|---|
| Own record with `role` `merge`: rejected (the merged record already supplies its values) | `estimate-own-merge` | codec |
| Own `candidate` record: `same_food_same_state` requires `method` `carried_from_same_food`, `close` requires `carried_from_similar_food`; `direct`, `derived` or the other carried method rejected | `estimate-own-method` | codec |
| Own `candidate` record: `state_basis` is `stated_assumption` or `source_states_it`, never `unknown` | `estimate-own-state` | codec |
| Any `national_composition` estimate on an entry whose `basis` is not `per_100_g` (no density is ever inferred; such an entry takes page estimates stated per 100 ml, or stays unknown) | `estimate-basis` | codec |
| Own `candidate` record that contradicts the entry (below) | `estimate-contradiction` | importer |

The codec reports its codes in the order of this table, after the inherited estimates v1 codes; the
importer's codes follow the codec's, after the four bundled-corpus codes of estimates v1 section
4.3. That check applies unchanged, **with its own comparison**: at zero the file value and the
record's value must be exactly equal, otherwise they differ when more than 0.5 per cent of the
record's value apart. A record with no quantified value can never yield one. Unknown stays unknown.

**Contradiction (closed list, mechanical).** The importer reads the record's identity through the
lookup port (section 7) and rejects the file when any of these holds:

- the entry's `state` is `raw` or `cooked` and the record's preparation kind is known and different;
- the record is fortified (an entry is never a fortified food, as for a merge);
- the record is not per 100 g with a known 100 g edible quantity.

**What an assumption may cover.** Only attributes that are unknown on the entry: a `state` of
`canned`, `frozen`, `dried`, `smoked` or `unknown` (the app maps all five to preparation unknown),
and the bone, skin, drained and packing facets an entry never declares. For those, the two
free-text states and the `assumption` carry the judgement, the owner approves each value, and the
value is shown as an estimate. That part is a builder and owner obligation; a JSON fixture cannot
prove an assumption true, and this contract does not pretend it can.

### 3.2 What Confirm must do with it

An own-record estimate does not give the entry the record's identity: a non-merged entry keeps its
mostly unknown facets, the identity questions of import v1 decision 12 are still asked, and the
separate "Generic" candidate is still offered with only its own record's values. Because the owner
can then answer those questions, the estimate is re-checked against the answers:

- If the confirmed identity sets a preparation kind or drained state that is known on the record
  and different, or changes the serving basis away from per 100 g, every own-record estimate on
  that log is **withheld**: the nutrient is unknown for that log, with the plain notice "Estimate
  left out: it is for a different preparation". Nothing is substituted.
- The same basis guard applies to every `national_composition` estimate, own record or not: a
  correction to per 100 ml never reinterprets a per 100 g value.
- Otherwise the estimate stays, labelled "Estimated".

The check is one pure application policy over the estimate, the record's identity and the confirmed
identity, run when Confirm is bound and again after each correction.

Why this route and not a wider merge (decision P2): an estimate is per nutrient, so a close record
can supply energy and macronutrients without its fatty acid split or its fortified vitamins; every
value shows "Estimated" with its assumption; a contradiction withholds the value instead of merging
it; and the merge rule stays closed. The original objection (an own-reference estimate "would act
as a forbidden merge") is met by a named, versioned exception with a contradiction veto, not by the
label alone.

## 4. Ranking of sources, per nutrient

Unchanged from estimates v1 section 4.1, restated because it is the question most often asked:

1. a label value: `manual_declaration` (typed or confirmed by the owner, **measured**) or
   `exact_product_dataset` (the product's own Open Food Facts record, augmented), with amendment
   A1's fresh-whole order;
2. an approved estimate (**augmented**, never measured);
3. the merged generic record, for keys still unknown.

A file with the same nutrient in `label_nutrients` and `estimated_nutrients` of one entry is
rejected, so an estimate can never overwrite or shadow a label value. Composite entries get no
national-composition estimate from another recipe (import v1 decision 4); that stays a builder rule
with an evaluator count, as in estimates v1 section 3.1. A web page value is written only after the
owner has confirmed it; `page_unconfirmed` values never reach a file.

## 5. Confirm, correction and saving

Estimates v1 section 7 applies as written: "Estimated" in text beside each estimated nutrient, the
source type, the two states, the assumption, "Estimated from a similar food" and "Page not read
directly" in details, record identifiers behind details, and the existing "Nutrients from more than
one source" notice. Added here, to state the owner's requirements explicitly:

- **Correction before Log is new work, not an existing flow.** Today "Correct food details"
  changes identity and details only and carries the candidate's nutrients through unchanged
  (`FoodDetailsSheet.correction`, `FoodCorrection`). So:
  - *Identity-only corrections* keep every estimate and its "Estimated" label, subject to the
    re-check of section 3.2.
  - *Per-nutrient correction* is added for estimated nutrients only, with two actions (decision
    P6). **Leave out**: the nutrient is unknown for this log. **Enter the label value**: the owner
    types the value printed on the pack; it is saved as `manual_declaration`, measured, shown as
    entered by the owner, following the typed-correction precedent of the pasted-label route, and
    bound to a new append-only evidence item `pfd-estimate-correction-v1` (nutrient key, value,
    unit, and the hash of the capture manifest it replaces a value of). There is no "revised
    estimate": a typed number is the owner's declaration or it is not entered.
  - Nutrients the owner does not touch keep their provenance byte for byte. Repeating or undoing a
    correction before Log returns the nutrient to the captured estimate.
- **The capture manifest (`pfd-estimate-capture-v1`) is never edited.** It is built once when the
  candidate is bound to Confirm and stays exactly as captured, with every imported estimate and its
  evidence, so the record of what was offered survives a correction or a withheld value. A
  correction changes the log being confirmed, never the imported database or the manifest.
- **Nothing is selected or saved automatically.** One Log action, the quantity is always the user's,
  and import never logs. An entry whose values are all estimates is not a generic estimate under
  `FoodConfirmationPolicy`, so the identity questions of import v1 decision 12 still apply.
- No medical wording, target or classification appears with an estimate.

## 6. Privacy and egress

No new destination. Import reads a local file; search and Confirm run offline; the importer fetches
no URL. The two effects already recorded in estimates v1 section 7 apply unchanged: a public page
URL of an approved estimate (query string and fragment dropped) can appear in the daily export the
user sends, and archives carry the capture manifests. The private catalogue, its review sheets and
its change reports stay in the owner's private workspace; the repository receives this contract,
code and synthetic fixtures only.

## 7. Architecture gate

**Responsibilities**

| Responsibility | Home | Boundary |
|---|---|---|
| Strict estimates v2 decoding: v2 rules, estimate rules, the own-reference rule of section 3 | `FoodLedgerDomain`, beside the v1 and v2 codecs, sharing their validation functions so the schemas cannot drift | pure |
| `approved_estimate` provenance kind and its contract version | `FoodLedgerDomain` and `CanonicalFoodProjection` (the owner of `foodContractVersion` and the floor), **food contract 10**: see "Version allocation" below | pure, closed versions |
| Estimate eligibility against the record and the confirmed identity (section 3) | `FoodLedgerApplication`, one pure policy used by the importer and by Confirm | pure |
| Per-nutrient correction (section 5): rule and evidence type in `FoodLedgerDomain`, orchestration in `FoodLedgerApplication` beside `FoodCorrection`, the two actions in `FoodLedgerPresentation` | new work | no new port |
| Binding estimates when a candidate is built and when a log is re-resolved | `FoodLedgerApplication` (the candidate builder and the search adapter's re-resolution) | existing ports |
| Import: validate, check carried values against the bundled record, derive the ID, replace atomically | `FoodLedgerApplication` (`PersonalFoodDatabaseImporting`), through `Digesting`, `GenericRecordNutrientLookup` and `PersonalFoodDatabaseStoring` | ports only |
| Capture manifest at Confirm binding, committed with the log, verified on save and reopen | `FoodLedgerApplication`; manifest type in `FoodLedgerDomain` | existing ports |
| Stored bytes and manifest (third known schema) | `FoodLedgerPersonalDatabase` | complete file protection |
| "Estimated" labels and details | `FoodLedgerPresentation`, from stored provenance, never a view-only flag | presentation only |
| Writing the file | the `personal-food-catalogue` skill, outside the app | private workspace |

**Version allocation (supersedes estimates v1 section 5.1 on this point only).** Estimates v1
planned contract 9, migration `v9_approved_estimate` and `food-ledger-v9`. Contract 9 has since
been taken by estimate layers on Open Food Facts products (`v9_off_label_estimate`). Approved
estimates therefore take **contract 10**: `foodContractVersion` rises to 10, the floor returns 10
for a record holding `approved_estimate` provenance, `pfd-estimate-capture-v1` or
`pfd-estimate-correction-v1` evidence, checked before the contract 9 rule, which is left exactly as
it is; a metadata-only migration `v10_approved_estimate` sets `food-ledger-v10`, so contract 9
binaries decline the store instead of failing on an unknown kind. If 10 is taken by the time the
phase starts, the phase takes the next free number and says so in its gate.

**Dependency direction.** Unchanged: presentation and infrastructure depend on application, which
depends on domain. No new target. One port beyond today's: `GenericRecordNutrientLookup`, planned
by estimates v1 and not yet built; here its result also carries the record's `DecisiveIdentity` and
edible quantity, which the contradiction check needs. No framework or persistence type crosses a
port.

**Invariants (closed).** Unknown is not zero. An estimate is never measured and never overwrites a
label value. Approval is not logging. One source per nutrient. A carried value equals its bundled
record, within the inherited tolerance. An estimate never changes a reference's role or an entry's
identity, and never survives a contradiction with the confirmed identity. A typed correction is an
owner declaration with its own evidence, never a silent edit of an estimate. v1 and v2 files, and
every stored record, archive and export, decode and re-encode unchanged. No network call.

**Extension axes.** The store remains the one variation point. A new source type, method, transform
or state is a new schema version, not configuration.

**Contract tests** (synthetic fixtures only, in a new
`docs/fixtures/personal-food-database-estimates-v2/` with a manifest of expected rule codes, read by
both the skill's checker and the Swift decoder):

- The v1 and v2 golden files and every existing fixture give the same rule code and hash as before.
  Schema dispatch: each schema's rules apply only to its own files; an estimates v1 file is
  rejected with `schema` and the active release is unchanged; a manifest whose schema disagrees
  with its file is rejected; a failed replacement keeps the active release.
- A v2 file re-labelled as estimates v2 with empty estimate fields is accepted; a scaled
  per-serving value and an estimate on different keys of one entry are accepted.
- Every estimates v1 section 2.3 rejection fixture, re-based on v2, keeps its rule code, except the
  own-reference fixture, which the next line replaces.
- Own reference: one fixture per code of section 3.1 (`estimate-own-merge`, `estimate-own-method`
  for `direct`, `derived` and the other carried method, `estimate-own-state`, `estimate-basis`,
  `estimate-contradiction` for raw against cooked, a fortified record and a record without a known
  100 g edible quantity); the matching carried method on a compatible record is accepted. Python
  checker and Swift importer give the same codes in the same order for a file with several faults.
- Confirm re-check: answering a preparation or drained state the record contradicts, or changing
  the basis, withholds the estimate as unknown with its notice; an answer the record does not
  contradict keeps it; dry against prepared and drained against undrained each have a case.
- A carried value that differs from its bundled record by more than the inherited tolerance, cites
  an unpinned corpus, a missing record, or a record with no quantified value (missing, trace,
  bounded, "N") is rejected with four distinct rule codes; at zero only exact equality passes. The
  lookup port's shared suite runs against CoFID, USDA and TFDA.
- Precedence: label, then estimate, then merged record; a label and an estimate on one key is
  rejected; an estimate does not promote a candidate; the separate candidate carries no estimates.
- Confirm: an estimated value shows "Estimated" and its details. Identity-only correction keeps
  the label and provenance. Leave out makes that nutrient unknown, not zero. Enter the label value
  saves `manual_declaration` for that nutrient only with its correction evidence; untouched
  nutrients keep their provenance bytes; repeating, undoing and cancelling a correction, and
  correcting every estimate, each have a case; the manifest's bytes and hash are unchanged and
  still verify. Log is never pre-selected; an estimate-only entry is not a generic estimate.
- Capture evidence that is missing or altered is refused on save and on reopen, including after
  the database is removed and after an archive restore.
- Versions: an existing contract 9 archive and store decode and re-encode unchanged and keep
  contract 9; a record with an approved estimate gives contract 10 and `food-ledger-v10`; a
  contract 9 binary declines it.
- Saved logs hold `approved_estimate` as `.augmented`, survive replace, remove and archive restore,
  and export `state: "estimated"`. Daily export: a document with no estimate exports
  byte-identically at version 1, one with an estimate at version 2, and **both** pass
  serialisation, Drive validation (which accepts a single version today), reconciliation and
  recovery.
- Search: an entry that gains its first known nutrient from an estimate becomes visible; an
  estimated fat value takes part in the requested-fat partition; escalation sufficiency counts it;
  a re-resolved log binds the same estimates and manifest.
- Simulator journey: import a synthetic estimates v2 file, search, open Confirm, read the estimate
  details, correct one value, log, remove the database, see the log unchanged.

Validation is the gates in `AGENTS.md` **plus the FoodSearchQuality and FoodQueryEvaluation steps
of the CI workflow**: the sort itself is untouched, but its inputs are not (visibility, the fat
partition and coverage all read augmented values). No evaluation result of R1 or R2 is carried onto
an estimates v2 release, and sealed sets stay with their authorised evaluator. Device acceptance is
the owner's.

## 8. Decisions for the owner

In order; each has a recommendation.

- **P1. Which estimates schema does the app implement?** Recommended: only
  `personal-food-catalogue-estimates-v2`, with the support table of section 2. Cost: an R2
  companion is not importable by the app; evaluation and shipping formats differ until R2 is
  rebuilt as estimates v2.
- **P2. How do same-food entries with no cooking state get values?** Recommended: section 3 (a
  labelled, per-nutrient estimate from the entry's own candidate record, as identity amendment A2
  with its contradiction veto). Alternative: add an "as sold" state that merges when the match is
  `same_food_same_state`; simpler to read, but it amends the merge rule, shows no "Estimated"
  label, cannot carry a subset of nutrients, and "as sold" alone says nothing about drained state
  or edible basis.
- **P3. Which E3 builder obligations bind the v2 catalogue?** Recommended: all of estimates v1
  section 3.1 stays (approval per value, never an Open Food Facts value by any route, the
  aggregator's underlying source recorded and counted, zero only where the source states zero, one
  source per nutrient). Only one clause is replaced: "withheld by an E3 consequence, a per-entry
  exclusion or as unresolved" is keyed to entry IDs of the pinned evaluation release, which the v2
  catalogue does not share. For the v2 catalogue a source that E3 rejected for that food is offered
  again only as its own row in the private review sheet with the earlier rejection shown, and
  enters only on a fresh owner approval; a schema change alone never re-admits it.
- **P4. Close matches.** Recommended: allow `carried_from_similar_food` from the entry's own close
  record under section 3 (contradictions rejected at import and withheld on Confirm), one accepted
  row at a time in the private review sheet, with the nutrients that the difference affects left
  out. Alternative, and the safer one if the veto seems too thin: same-food only, leaving 213
  entries to their separate candidate.
- **P5. Order of work.** Recommended: one implementation phase after acceptance, with its own
  issue and a fresh architecture gate: codec and rule codes, provenance kind and contract 10,
  lookup port, eligibility policy, manifest, per-nutrient correction, Confirm, export amendment and
  Drive admission, privacy record. It is a large review surface; nothing ships until estimate
  provenance is bound end to end.
- **P6. What can the owner do to one estimated value on Confirm?** Recommended: leave it out, or
  enter the label value (section 5). Alternative: leave out only, with typed values going through
  the existing label routes; smaller, but it does not meet "correct each value before Log".

## 9. Review record

- 15 November 2026: three local Qodo passes; two findings fixed (manifest never edited; basis
  rule).
- 16 November 2026: blind architecture-gate and invariant review by a second agent, verdict NEEDS
  WORK on both, seven findings, each checked against the code and accepted: contract 9 already
  taken (now contract 10); Confirm has no nutrient correction (section 5 now specifies it as new
  work, decision P6); the own-record rule conflicted with identity section 8 (now amendment A2 with
  a contradiction veto, sections 3.1 and 3.2); decoder promises contradicted P1 (support table,
  section 2); search evaluations wrongly exempted (now required); P3 too loose (clauses named);
  new rejections had no codes and "must equal" contradicted the inherited tolerance (table in 3.1).
- Still owed before acceptance: a repeat of both gates on this revision.
