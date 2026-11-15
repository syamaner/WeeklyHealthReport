# Personal food database: labelled estimates on catalogue v2 (proposal)

Status: **proposal, 15 November 2026. Not accepted, nothing implemented.** It asks the owner for the
five decisions in section 8. No app code, skill code or fixture changes with this document.
Programme #424, base contracts #419.

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

A new schema string, decoded by its own decoder. **It is import v2 plus the two estimate fields of
estimates v1, with one rule changed (section 3).**

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

**Existing files are untouched.** `personal-food-catalogue-v1`, `personal-food-catalogue-v2` and
`personal-food-catalogue-estimates-v1` keep their decoders, rule codes, fixtures and golden hashes.
Each decoder refuses every other schema. Stored releases, manifests, records, archives and exports
decode and re-encode unchanged. The store keeps its fixed file name (import v2 decision 4) and its
manifest accepts the new schema as a third known value.

Estimates v1 stays the format of the evaluation's R2 builder
([R2 builder v1](personal-food-database-r2-builder-v1.md)); whether the app ever decodes it is
decision P1.

## 3. The one changed rule: an estimate may cite the entry's own candidate record

Estimates v1 section 2.3 rejects "a `national_composition` estimate whose `composition_source` and
`source_reference` name the same record as that entry's `generic_reference`, whatever its role".

In estimates v2 this becomes:

- **`role` `merge`: still rejected.** The merged record already supplies its values.
- **`role` `candidate`: allowed, with the method forced by the match.** `same_food_same_state`
  requires `method` `carried_from_same_food`; `close` requires `carried_from_similar_food`. `direct`
  and `derived` are rejected on an own-reference estimate, because the entry's state is not the
  record's by construction. `state_basis` is `stated_assumption` or `source_states_it`, never
  `unknown`, and `assumption` says in plain words why the record stands for the food (for example
  "sold ready to eat; no cooking state applies").
- Nothing else about the reference changes. An estimate never promotes a `candidate` to a `merge`,
  the separate "Generic" candidate is still offered and still carries only its own record's values,
  and import v1 decision 8 and identity contract section 8 are not amended.

Why this route and not a wider merge (the alternative, decision P2): an estimate is per nutrient, so
a close record can supply energy and macronutrients without its fatty acid split or its fortified
vitamins; every value shows "Estimated" with its assumption; and the merge rule, which is a closed
identity rule, stays closed. The original objection (an own-reference estimate "would act as a
forbidden merge") is answered by the label and the forced method, not waved away: the value is
never presented as the entry's own measured or merged value.

The bundled-corpus check of estimates v1 section 4.3 applies unchanged, so a carried value must
equal the bundled record's value for that key, and a record with no quantified value can never
yield one. Unknown stays unknown.

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

- **Every value can be corrected before Log**, through the existing correction flow of the shared
  Confirm screen. A corrected nutrient takes the provenance that flow already gives a typed value
  and loses its "Estimated" label, and its provenance no longer cites the estimate. The capture
  manifest (`pfd-estimate-capture-v1`) is not edited: it is built once when the candidate is bound
  to Confirm and stays exactly as captured, with every imported estimate and its evidence, so the
  record of what was offered survives the correction (capture evidence is append-only). A
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
| `approved_estimate` provenance kind, food contract 9 | `FoodLedgerDomain`, as estimates v1 section 5.1 | pure, closed versions |
| Import: validate, check carried values against the bundled record, derive the ID, replace atomically | `FoodLedgerApplication` (`PersonalFoodDatabaseImporting`), through `Digesting`, `GenericRecordNutrientLookup` and `PersonalFoodDatabaseStoring` | ports only |
| Capture manifest at Confirm binding, committed with the log, verified on save and reopen | `FoodLedgerApplication`; manifest type in `FoodLedgerDomain` | existing ports |
| Stored bytes and manifest (third known schema) | `FoodLedgerPersonalDatabase` | complete file protection |
| "Estimated" labels and details | `FoodLedgerPresentation`, from stored provenance, never a view-only flag | presentation only |
| Writing the file | the `personal-food-catalogue` skill, outside the app | private workspace |

**Dependency direction.** Unchanged: presentation and infrastructure depend on application, which
depends on domain. No new target and no new port beyond `GenericRecordNutrientLookup`, which
estimates v1 already defines. No framework or persistence type crosses a port.

**Invariants (closed).** Unknown is not zero. An estimate is never measured and never overwrites a
label value. Approval is not logging. One source per nutrient. A carried value equals its bundled
record. An estimate never changes a reference's role. v1, v2 and estimates v1 files, and every
stored record, archive and export, decode and re-encode unchanged. No network call.

**Extension axes.** The store remains the one variation point. A new source type, method, transform
or state is a new schema version, not configuration.

**Contract tests** (synthetic fixtures only, in a new
`docs/fixtures/personal-food-database-estimates-v2/` with a manifest of expected rule codes, read by
both the skill's checker and the Swift decoder):

- The v1 and v2 golden files and every existing fixture give the same rule code and hash as before;
  the four decoders refuse each other's schema.
- A v2 file re-labelled as estimates v2 with empty estimate fields is accepted; a scaled
  per-serving value and an estimate on different keys of one entry are accepted.
- Every estimates v1 section 2.3 rejection fixture, re-based on v2, keeps its rule code.
- Own reference: `merge` rejected; `candidate` with the matching carried method accepted;
  `candidate` with `direct`, `derived`, the other carried method or `state_basis` `unknown` rejected.
- A carried value that differs from its bundled record, cites an unpinned corpus, a missing record,
  or a record with no quantified value (missing, trace, bounded, "N") is rejected with four distinct
  rule codes, including a zero-value case.
- Precedence: label, then estimate, then merged record; a label and an estimate on one key is
  rejected; an estimate does not promote a candidate; the separate candidate carries no estimates.
- Confirm: an estimated value shows "Estimated" and its details; correcting it removes the label
  for that nutrient only, its saved provenance is the correction's, and the manifest's bytes and
  hash are unchanged and still verify; Log is never pre-selected; an estimate-only
  entry is not a generic estimate.
- Saved logs hold `approved_estimate` as `.augmented`, survive replace, remove and archive restore,
  and export `state: "estimated"`; a document with no estimate exports byte-identically.
- Simulator journey: import a synthetic estimates v2 file, search, open Confirm, read the estimate
  details, correct one value, log, remove the database, see the log unchanged.

Validation is the gates in `AGENTS.md`. Ranking is not touched, so the search evaluations are not
required. Device acceptance is the owner's.

## 8. Decisions for the owner

In order; each has a recommendation.

- **P1. Which estimates schema does the app implement?** Recommended: only
  `personal-food-catalogue-estimates-v2`. Estimates v1 remains the R2 evaluation format and its
  contract remains the definition this delta builds on; the app gains one estimates decoder, not two.
- **P2. How do same-food entries with no cooking state get values?** Recommended: section 3 (a
  labelled, per-nutrient estimate carried from the entry's own candidate record). Alternative: add
  an "as sold" state that merges when the match is `same_food_same_state`; simpler to read, but it
  amends a closed identity rule, shows no "Estimated" label and cannot carry a subset of nutrients.
- **P3. Do the E3 builder obligations bind the v2 catalogue?** Estimates v1 section 3.1 forbids an
  estimate whose source E3 withheld. Those lists are bound to the pinned evaluation release.
  Recommended: they stay with R2; for the v2 catalogue the builder rules are the ones restated in
  section 4 (never from Open Food Facts through a page, never onto a label key, composites stay
  empty, zero only where the source states zero).
- **P4. Close matches.** Recommended: allow `carried_from_similar_food` from the entry's own close
  record (section 3), one accepted row at a time in the private review sheet, with the nutrients
  that the difference affects left out. Alternative: same-food only, leaving 213 entries to their
  separate candidate.
- **P5. Order of work.** Recommended: one implementation phase for estimates v2 (decoder,
  provenance kind and contract 9, manifest, Confirm, export amendment), with its own architecture
  gate review and issue, after this proposal is accepted.

## 9. Review record

Written without a blind architecture-gate or invariant review; both are owed before acceptance,
because section 3 reverses a blocking finding of the estimates v1 invariant review of 9 November
2026.
