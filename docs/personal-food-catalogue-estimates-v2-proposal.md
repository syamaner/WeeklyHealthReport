# Personal food database: labelled estimates on catalogue v2 (contract)

Status: **accepted by the owner on 16 November 2026, after seven review rounds (section 9). Not
implemented.** Proposed on 15 November 2026; section 8 records the owner's seven decisions. The
file keeps its original name so that existing links hold. Implementation is one phase, after
daily export v2 has landed, with its own issue and architecture gate (decision P5). No app
code, skill code or fixture changes with this document. Programme #424, base contracts #419.

It is a delta on two accepted contracts and repeats neither:
[approved estimates v1](personal-food-catalogue-estimates-v1.md) (accepted 9 November 2026, not yet
implemented) and [import v2](personal-food-catalogue-import-v2.md) (approved 13 November 2026,
implemented). Everything in those documents that this one does not name stays as written.

**Amendment, 18 November 2026 ([label photo estimates](personal-food-catalogue-off-estimates-v1-proposal.md), accepted, not implemented).**
This schema is not widened. A new schema, `personal-food-catalogue-estimates-v3`, adds the source type
`product_dataset_photo` for Open Food Facts label photos. Section 3.1's "never re-admissible" list is
unchanged: nothing is re-admitted, and a photo estimate is refused for any entry and nutrient E3
withheld. The v3 schema caps that source type at `medium`; section 3.3's tiers and labels are
unchanged.

**Amendment, 16 November 2026 ([assistant-pasted estimates v1](assistant-pasted-estimates-v1-proposal.md), accepted, not implemented).**
That contract is a delta on this one and changes two points; everything else here stands.
- Sections 3.3 and 5, which tier is shown: the tier shown and exported for a log is the capture
  manifest's, unless the effective resolution version's verified choices evidence
  (`assistant-estimate-choices-v1`) names a lower tier for that nutrient, in which case it is that
  lower one. A tier is never raised, and the manifest is never edited.
- Section 3.3's closed label list gains "Estimated by your assistant, some doubt" and "Estimated
  by your assistant, rough", for the separate `assistant_estimate` kind only.

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
- `estimated_nutrients` and `estimate_evidence` are estimates v1 sections 2.1 and 2.2: the
  same keys, closed vocabularies, limits, `pfe:` evidence IDs and transform list (its section 6),
  plus one required key on each evidence record, `quality` (section 3.3).
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

The codec today rejects on the top-level key set before it reads `schema`. With a second key set
that order is fixed as: (1) the key set is v2's or v2's plus `estimate_evidence`, else `top-keys`;
(2) `schema` is a known value, else `schema`; (3) the key set is the one that schema requires, else
`top-keys`. When the key set includes `estimate_evidence` and the schema is not a known value, checking stops
at step 2 and `schema` is the only code; an unknown schema with v2's key set continues under v1 rules
as today. So an estimates v1 file gives exactly `schema`, a v1 or v2 file carrying
`estimate_evidence` gives `top-keys`, and no existing v1 or v2 fixture changes its code.

Each schema's rules apply only to files that declare it. Stored releases, manifests, records,
archives and exports decode and re-encode unchanged. The store keeps its fixed file name (import v2
decision 4) and its manifest accepts the new schema as a third known value. An R2 companion is not
importable by the app; if it should ever be, that is a rebuild as estimates v2, never a conversion
in the app.

## 3. The changed rule: an estimate may cite the entry's own record

Estimates v1 section 2.3 rejects "a `national_composition` estimate whose `composition_source` and
`source_reference` name the same record as that entry's `generic_reference`, whatever its role".
Estimates v2 allows it for a `candidate` record, matched `same_food_same_state` (as a same-food
estimate) or `close` (as a similar-food estimate), under the conditions below. **This is an identity exception and is proposed as one:** amendment A2 to
[identity contract](food-identity-nutrition-contract.md) section 8, recorded there when this
proposal is accepted. Section 8 makes a value with an unknown or contradictory decisive attribute
ineligible; A2 lets an owner-approved, labelled estimate cover an **unknown** attribute and never a
**contradictory** one, and lets a similar food's value be shown only under the visible label
"Estimated from a similar food", never as the food's own. Amendment A1 (the merge rule) is not changed. Import v1 decision 8 keeps its
wording (a `candidate` record never merges) but is narrowed in effect: the entry itself can now
show values that came from its candidate record, as labelled estimates.

**Close matches are admitted (owner decision P4, reopened 16 November 2026).** The owner's stated
aim is to fill as much as possible with reasonable, labelled estimates. A `national_composition`
estimate with `method` `carried_from_similar_food` is accepted, from the entry's own close-match
record or from another record, so the 213 close-match entries can carry values. It gives the entry
nothing of the similar food's identity; it is shown as "Estimated from a similar food" with the
record's name in details (estimates v1 section 7); every importer check and the contradiction veto
of this section apply to it as to any other composition estimate; and its quality tier can never
be the highest (section 3.3). The separate "Generic" candidate is still offered.

### 3.1 What the file must satisfy

Codec rules (pure, from the file alone), in this order for each estimate:

| Rule | Code |
|---|---|
| Own record with `role` `merge` (the merged record already supplies its values) | `estimate-own-merge` |
| Own `candidate` record whose `method` does not agree with its match: `same_food_same_state` takes `carried_from_same_food` only, a close match takes `carried_from_similar_food` only, and `direct` and `derived` are never an own record's method | `estimate-own-method` |
| Own `candidate` record whose `state_basis` is `unknown` | `estimate-own-state` |
| Own `candidate` record matched `same_food_same_state` on an entry whose `state` is `raw` or `cooked` (a same-food record that did not merge for such an entry was held or demoted on purpose, for example by the E3 disposition, and must not refill it) | `estimate-own-held` |
| An evidence record whose `quality` is above the ceiling of section 3.3 (a missing `quality` is the inherited `evidence-keys`, and one outside the closed list the inherited `token`) | `estimate-quality` |
| Any `national_composition` estimate on an entry whose `basis` is not `per_100_g` (no density is ever inferred; such an entry takes page estimates stated per 100 ml, or stays unknown) | `estimate-basis` |

The table is applied only to an evidence record that is bound to exactly one value of an existing
entry and whose tokens are valid; a record the inherited checks already failed gets no table code.
A record gets every row it matches, in table order. `estimate-own-held` costs no coverage: the 102
target entries are by definition those whose state is not `raw` or `cooked`, and an own `close`
record is a candidate by rule, not held on purpose, so the row does not apply to it.

Importer rules (need the bundled record), run **only on a file the codec accepted**, so a rejection
holds codec codes or importer codes, never both. For each `national_composition` estimate, own
record or not, in this order: `corpus-mismatch`, `record-missing`, `value-unquantified`,
`value-mismatch` (the four checks of estimates v1 section 4.3, named here for the wire), then
`estimate-contradiction`.

**Traversal.** The codec keeps its rule of appending codes in the order found, repeats kept. The
inherited estimate checks run as in the R2 tool and keep its code strings (`evidence-keys`,
`not-approved`, `token`, `date`, `digest`, `type-fields`, `corpus-undeclared`, `source-reference`,
`open-food-facts-host`, `free-text`, `derivation`, `derivation-missing`, `derivation-shape`, `derivation-unexpected`, `evidence-id`,
`evidence-duplicate`, `evidence-order`, `estimated-nutrients`, `estimate-keys`,
`label-and-estimate`, `evidence-dangling`, `evidence-mismatch`, `evidence-unused-or-shared`);
`own-reference` is retired in this schema and replaced by the table above; `items`, `item-keys`,
`unknown-nutrient`, `unit` and `value` on the estimate part reuse the existing enum cases. After them the codec
walks `estimate_evidence` in file order and applies the table to each record in table order. The
importer walks the same list in the same order. All new strings join `PersonalFoodDatabaseRuleCode`
in an estimates-only set, as `v2Only` does for import v2. The skill's checker gains the
estimate rules, ported from the R2 tool onto the v2 part, and has parity for codec codes only;
importer codes are Swift tests with a stub lookup and the shared adapter suite. Each fixture in the
manifest names its stage (codec or importer), and the Python checker asserts codec fixtures only.

**Value comparison** is the inherited one: at zero the file value and the record's value must be
exactly equal, otherwise they differ when more than 0.5 per cent of the record's value apart. A
record with no quantified value can never yield one. Unknown stays unknown.

**Contradiction (closed list, mechanical), for every `national_composition` estimate.** The file is
rejected with `estimate-contradiction` when any of these holds:

- the entry's `state` is `raw` or `cooked` and the record's preparation contradicts it under the
  comparison of section 3.2 (so the import list is that comparison applied to what the file
  already knows, and a value the importer accepts is not withheld at first bind with no answer
  changed);
- the record is fortified (an entry is never a fortified food, as for a merge);
- the record is not per 100 g with a known 100 g edible quantity.

**What the mechanical checks cannot see, stated plainly.** An entry `state` of `canned`, `frozen`,
`dried`, `smoked` or `unknown` maps to preparation unknown in the app, and those are the entries
this route exists for, so for them the list above checks fortification and basis only, and after
`estimate-own-held` the first bullet can fire only for a record that is not the entry's own. A facet the
adapter holds as unknown on the record cannot veto either: USDA and TFDA records never state
fortification, so the fortified-record rule can fire for CoFID only. In both cases the safeguards
are the two free-text states, the `assumption`, the owner's approval of each value and the
"Estimated" label. That part is a builder and owner obligation; a fixture cannot prove an
assumption true. To keep it visible, the private change report counts estimates whose record
preparation is unknown and estimates from a source that never states fortification. The stricter
rule (reject when the record's preparation is unknown) was offered in decision P2 and not taken.

**Builder obligations added to estimates v1 section 3.1** (not checkable by the importer):

- The own-record rows apply only when the estimate cites the entry's `generic_reference`. A close-match
  record is cited as `carried_from_similar_food` and never as `carried_from_same_food`: dropping
  or changing the entry's reference to pass one off as the same food is forbidden, and the
  evaluator counts same-food estimates whose record is the entry's close reference or a former
  close reference, and that count must be zero, re-admitted or not.
- An entry whose reference the E3 disposition demoted, removed or held at `candidate` takes no
  estimate from that record by any route (E3 disposition sections 4 and 4.1). A record or value E3
  withheld for a food stays refused for that food. This is the default; the one exception is the
  re-admission below.
- Those lists are keyed to entry IDs of the pinned evaluation release. The builder carries them
  across by the private mapping of old entries to v2 entries; the **evaluator**, not the builder,
  reports the count of refused estimates not re-admitted, which must be zero in the file. An entry with no counterpart in the
  pinned release cannot be checked this way; such entries are counted separately as "no E3
  counterpart" so the limit of the rule stays visible.
- **Re-admission, row by row (owner decision P3, 16 November 2026).** The owner may re-admit one
  refused source value for one entry on a fresh approval. It is recorded as a dated amendment,
  when this proposal is accepted, to each rule it touches: E3 disposition sections 4, 4.1 and 5
  point 3, and the must-be-zero count of estimates v1 section 3.1 (which becomes "refused and not
  re-admitted"). Its limits:
  - **What can be re-admitted (closed list).** Only a `national_composition` value or record that
    E3 withheld by a stratum consequence (its section 6) or by the removal-only mechanics of its
    section 3 (a reference removed or demoted because another value was withheld), and that no
    review found wrong in itself.
  - **Never re-admissible**, because the rule that refuses each is not amended here: a value whose
    stated underlying source is Open Food Facts, by whatever page or route (estimates v1 section
    3.1, E3 decision D3), so that count stays zero; the 2 unresolved A1 values; a record under a
    per-entry exclusion for wrong identity, incompatible state or variety mismatch (evaluation v1's
    per-entry exclusion; amendment A2 never covers a known contradiction); a value excluded for
    its own wrong basis, transcription or derivation; and a class with
    no truthful `source_type` (recipe estimate, prior release, a transform outside the closed
    list). A row of one of these classes on the list is counted as refused.
  - One row is one entry ID, one nutrient key, the `source_type`, the `source_reference` and the
    `method`, with the corpus hash and the date. A former close reference re-admits only as
    `carried_from_similar_food`. A row covers that value only, never a later value of the same
    record. The list is derived from a re-admission sheet of its own, in the private workspace, since the
    existing review sheets hold neither source references nor refusal reasons: one row per value,
    with those row fields, the E3 refusal class and its reason, and an accept column. The
    evaluator checks that each list row matches a sheet row carrying the owner's accept mark. There is no batch acceptance, and the builder or an agent never re-admits on the
    owner's behalf.
  - A re-admitted value is a labelled estimate and nothing more. Every codec, importer and Confirm
    rule applies unchanged, so re-admission overrides no mechanical rule: a `raw` or `cooked` entry
    still cannot take its own held record (`estimate-own-held`), a contradiction still rejects or
    withholds, and a similar-food estimate still cannot take the highest tier. Stated plainly: a record that is
    not the entry's own (for example one whose reference E3 removed) passes those rules on a `raw`
    or `cooked` entry, so there the row-level approval is the only safeguard.
  - Its `assumption` text says that the evaluation withheld the source and the owner re-admitted
    it, so the details on Confirm show it (E3 section 4: a weaker class is shown as such).
  - It never restores a `merge` role, changes a reference's role or the entry's identity, and it
    never makes a value measured.
  - The re-admission list is private and stays in the owner's workspace; it holds until the owner
    withdraws a row, after which the value counts as refused again. The file carries no marker
    beyond the `assumption` text.
  - **The evaluator's counts, six in all.** Four must be zero: a close reference passed off as
    the same food (first obligation above); refused estimates not re-admitted; re-admitted
    estimates above `medium`; and aggregator estimates above `medium` whose underlying source is
    not stated (section 3.3). Two are reported as numbers: re-admitted estimates, and estimates on
    entries with no E3 counterpart. The private change report lists the re-admitted rows.

### 3.2 What Confirm must do with it

An estimate does not give the entry the record's identity: a non-merged entry keeps its mostly
unknown facets, the identity questions of import v1 decision 12 are still asked, and the separate
"Generic" candidate is still offered with only its own record's values. Because the owner can then
answer those questions, every `national_composition` estimate is re-checked against the answers.

- **Where the record's identity comes from.** When the candidate is bound to Confirm, the
  application reads each cited record's `DecisiveIdentity` through
  `GenericRecordNutrientLookup` (section 7) and holds it in the Confirm state for that log. The
  lookup key must come from saved data, so the capture manifest carries one more field than
  estimates v1 section 5.2 lists: `corpus_sha256` beside each `national_composition` estimate (a
  stated amendment; the manifest is not implemented yet). When the details of a reopened log are corrected, the identity is
  read again with the manifest's source, hash and record ID, never with the active release's.
  **When a record cannot be read** (corpus pin moved, record missing), every estimate that cites it
  is withheld, with its own notice: "Estimate left out: its source record could not be read".
- **The comparison** is per facet and uses the equality the existing `IdentityCompatibility` rule
  uses, with one difference only: a facet that is `unknown` on either side does not contradict.
  Preparation compares the whole state (kind, and method when both sides name one), so `as_sold`
  against a `cooked`, `reheated` or `named` record is a contradiction like any other. **One pair is
  compatible by owner decision (16 November 2026): `as_sold` and `raw` do not contradict each
  other, in either direction,** so answering "as sold" keeps an estimate from a raw record. The
  stated cost: if a raw record was matched to a food sold tinned or smoked, this check will not
  catch it, and the review of the match and the "Estimated" label are the safeguard. The private
  change report counts estimates whose record is `raw` on an entry whose state is not `raw`. Packing
  medium is exact text equality. The function lives in `FoodLedgerDomain` beside
  `IdentityCompatibility`, with a test that both cover the same facets. A facet (preparation, bone, skin, drained state, packing medium, fortification) that is
  known on both sides and different withholds every estimate citing that record.
- **Basis.** Changing the serving basis away from the entry's own withholds **every approved
  estimate** on the log, page estimates included: a value is never reinterpreted from per 100 g to
  per 100 ml or back.
- **Withheld** means the nutrient is unknown for that log, with the plain notice "Estimate left
  out: it does not match these details". Nothing is substituted. Developer tools show which facet
  withheld it.
- Otherwise the estimate stays, with its label from the closed list of section 3.3.

The check is one pure application policy over the estimate, the record's identity and the confirmed
identity. It runs when a candidate is bound to Confirm, after each correction of details, and on
re-resolution of a saved log. **Reopening alone runs nothing:** a reopened log whose details are
not corrected reads no record and shows its saved values as saved, also after the corpus pin has
moved, and a change of quantity alone is not a correction of details. Undoing a
leave-out on a reopened log is the one other trigger: it runs the check for that nutrient with
the manifest's source, hash and record ID, and a record that cannot be read withholds it.
The manifest it reads must have the payload hash named in the leave-out evidence.
**Withholding wins over leaving out:** the saved leave-out evidence never lists a withheld key, so
an undo can never restore a value the check would withhold. The Confirm set itself keeps the
owner's choice until the owner undoes it: a key left out, then withheld, then no longer withheld
before Log is still left out. A value that was withheld
when the log was saved shows the one notice "Estimate left out when this was logged", since the
reason is not stored.

Why this route and not a wider merge (decision P2): an "as sold" merge would give the entry the
record's identity for every facet (amendment A1), silently settling drained, bone and packing, the
facets most likely to be wrong for tinned food, and it would show no per-value label. Here every
value shows "Estimated" with its assumption, a contradiction withholds the value, and the merge
rule stays closed. What the merge has in its favour: its values are read from the bundled corpus,
never copied into a file, and nothing rests on free text.

### 3.3 Quality tier (owner decision P7, 16 November 2026)

Every estimate carries a tier that says how strong its evidence is, so that weaker estimates can
be admitted and still be told apart. It describes the evidence, never the food: it has no health
meaning and sets no target.

- **Wire.** `quality` on each evidence record, closed list `high`, `medium`, `low`. No score,
  probability or free text is stored in the file.
- **Shown** as green, amber and red, always with text: "good match", "some doubt", "rough". The
  visible label joins the method and the tier, so a similar food is never shown as the food's
  own. The list is closed: "Estimated, good match", "Estimated, some doubt", "Estimated, rough",
  "Estimated from a similar food, some doubt", "Estimated from a similar food, rough". The colour marks that label, never the nutrient
  value; it never appears without its text on any surface; totals carry no tier. The reasons sit
  in details with the source type, states and assumption.
- **Ceilings the codec enforces** (`estimate-quality`), so no classifier or typing slip can
  overstate an estimate. `high` is accepted only when all of these hold: `method` is
  `carried_from_same_food` or `direct`; `state_basis` is `source_states_it`; `page_access` is not
  `indexed_copy`; and a `national_composition` estimate cites the entry's own record. Otherwise
  the ceiling is `medium`, except that an estimate whose `state_basis` is `unknown` is at most
  `low`. Below a ceiling the builder may always go lower. One more ceiling is a builder rule with
  an evaluator count, since the file cannot show it: an aggregator page whose underlying source
  is not stated is at most `medium`, and the count of those above it must be zero (section 3.1).
- **Who sets it.** The builder proposes a tier from the evidence, and may take advice from a
  classifier run at build time, outside the app, on generic food descriptions only (section 6). The tier is
  written only for a row the owner accepted on the review sheet with that tier shown. A model's
  answer never authorises a value or a tier by itself, and a low classifier confidence is shown to
  the owner, not resolved silently. The app runs no classifier and makes no network call for this.
- **A re-admitted value** (section 3.1) is at most `medium`. The file has no marker for it, so
  this is a builder rule with the evaluator's must-be-zero count of section 3.1.
- **What the tier never does.** It never changes a value, its provenance kind, the ranking of
  section 4, the contradiction veto or what Log saves; a `high` estimate is still augmented and
  never measured, and a `low` one is still offered and can be left out.
- **Stored.** The capture manifest already holds each estimate's whole evidence record (estimates
  v1 section 5.2), so the tier is there with no added field, and a saved log shows the tier it
  was logged with, also after the database is replaced. Daily export version 3 carries it as
  `estimate_quality`, required on every `approved_estimate` value, closed list `high`, `medium`,
  `low`; a missing or unknown token is rejected.

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

Estimates v1 section 7 applies, with its bare "Estimated" replaced by the closed label list of
section 3.3: the label in text beside each estimated nutrient, the
source type, the two states, the assumption and "Page not read directly" in details, record
identifiers behind details, and the existing "Nutrients from more than one source" notice. Added
here:

- **Correction before Log is new work, not an existing flow.** Today "Correct food details"
  changes identity and details only and carries the candidate's nutrients through unchanged
  (`correction(for:)` in `FoodDetailsSheet.swift`, `FoodCorrection`). So:
  - *Identity-only corrections* keep every estimate and its "Estimated" label, subject to the
    re-check of section 3.2.
  - *Leave out* is the one per-nutrient action, on estimated nutrients only (decision P6): the
    nutrient is unknown for this log. There is no field to type a value and no "revised
    estimate", so Confirm has no route from an estimate to a measured value. A value printed on
    the pack goes through the existing label routes, or into the catalogue as a label value on
    the next build.
  - Nutrients the owner does not touch keep their provenance byte for byte. Undoing a leave-out
    before Log returns the nutrient to the captured estimate, subject to section 3.2.
- **Log needs one known nutrient.** While withholding and leaving out leave no nutrient of the log
  known, Log is blocked and the reason is shown there ("Nothing to log: every value was left
  out"). Today the builder offers no candidate without a known nutrient; this keeps that rule
  after a leave-out, and keeps an all-unknown row out of the daily export, which cannot attribute
  one.
- **The capture manifest (`pfd-estimate-capture-v1`) is never edited.** It is built only for a
  candidate with at least one estimated nutrient, so a log without estimates keeps its contract.
  It is built once when the candidate is bound to Confirm and stays exactly as captured, so the record of what was offered
  survives a leave-out or a withheld value. A leave-out changes the log being confirmed, never
  the imported database or the manifest. A manifest that no saved provenance cites any more (every
  estimate withheld or left out) is still saved, found through the candidate's bound
  evidence IDs, and still verified on reopen.
- **Leave-out state and versions.** The set of left-out nutrient keys is Confirm state of its own,
  outside `FoodCorrection` (if that state is persisted, the set decodes as empty when absent). On
  a reopened log it is seeded from the effective resolution version's verified leave-out evidence.
  **One application predicate, "the log's food facts changed":** a correction is present, or the
  leave-out set differs from its seed (for a new log, is not empty). It replaces today's test of
  the correction alone **only where that test decides whether new records are written**: the
  save path's choice between new and reused records, the edit comparison, and the log policy's
  unchanged check; the phase gate lists the sites. It does not replace the correction test
  anywhere else, so a leave-out alone is not a correction: identity differences are still asked
  and recorded, label and layer admission are unchanged, and the candidate decision's outcome is
  computed as for an uncorrected save (`selected`, or what the contradiction rule gives), never
  forced to `rejected`. On a reopened log, where today no identity question is asked again, a
  leave-out-only save carries the saved identity, decision record and outcome unchanged into the
  new assertion and decision, so a log saved as an estimate keeps its estimate status and a
  previously corrected log keeps its outcome. When the predicate is true a new product version, resolution version and
  candidate decision are written, never the saved ones reused, with a user assertion and an edit
  reason whose texts are the leave-out's own, pinned in the phase gate beside the existing ones.
  The version's nutrients are the candidate's (or the correction's) with the left-out and
  withheld keys unknown; the phase gate names the save and reopen guards such a version passes.
  Undo is offered after Log too, under section 3.2. **On the same candidate, a key the owner left out stays unknown through a later change unless
  the owner undoes a verified leave-out**, so altered evidence or a correction rebuilt from the
  candidate can never bring a left-out value back. A key that was only withheld is different: a
  later correction of details re-runs section 3.2 from the manifest, so removing the
  contradiction brings the estimate back with its label, and no leave-out evidence is involved.
  A saved unknown estimate key with neither verified leave-out evidence nor a passing re-check
  stays unknown. Re-resolution is governed by its own bullet below.
- **Quick add and re-log always go through Confirm.** A pinned or re-logged entry that holds an
  approved estimate, a withheld value or a left-out value never uses the one-step sheet. It opens
  Confirm, section 3.2 runs at bind against the carried details, the labels and tiers are shown,
  and earlier leave-outs are not carried, with the re-resolution notice. Quick add gains its own
  ineligibility reason for this. It is detected from the restored candidate (an
  `approved_estimate` value or a capture manifest), never from the pinned version's saved
  provenance, so a favourite whose estimates were all withheld or left out is caught too; and
  the save service refuses a one-step save of a state holding a manifest. A new log built from a
  saved decision drops that decision's leave-out evidence IDs.
- **Leave-out evidence `pfd-estimate-left-out-v1`.** It exists for one purpose: so that a
  reopened log can say "Left out by you" and not the withheld notice. One item per saved
  resolution version whose set is not empty; evidence is immutable, so the earlier items stay.
  Its content is `schema`, the resolution version ID it belongs to, the capture manifest's hash
  and the sorted keys of the nutrients left out. It holds no nutrient value; the estimate that was
  offered is in the manifest. **It is reached the way all evidence is, by ID.** `CandidateDecision` has no
  evidence list of its own; the store loads evidence from its embedded candidate copy. So the new
  decision's embedded candidate carries the bound candidate's evidence IDs plus this item's, and
  differs from the bound candidate in that list only. No stored type gains a field, so existing
  records decode and re-encode unchanged. Inline `CaptureEvidence`, kind
  `.labelText`, `originalPayload` `.text(<canonical JSON>)`, `byteHash` its SHA-256,
  `captureMethodVersion` `pfd-estimate-left-out-v1`, committed in the log's `LedgerMutation`.
  Other `.labelText` readers select by `captureMethodVersion` and ignore it, and its reader
  ignores theirs (one test each way). Verified in the application on save and on reopen exactly as
  the manifest is; altered evidence shows "Evidence not available" and never changes
  stored values. A missing evidence row is a store integrity failure, as for any listed evidence
  today: the log does not load, which fails closed. Since decisions accumulate evidence IDs across
  versions, the reader accepts only the item whose resolution version ID is the effective
  version's; earlier items may stay listed and are ignored. Outside the log's own details a left-out value reads as any unknown does
  ("Unknown, no matching source", export reason `no_compatible_source`); that wording is accepted
  for this release, and no new reason is added.
- **Stored shapes** (no new `UnknownReason` and no new stored raw value beyond `approved_estimate`):

  | Case | Stored value | Provenance | How reopen tells it apart |
  |---|---|---|---|
  | Estimate kept | `.augmented` | `approved_estimate`, as estimates v1 section 5.1 | provenance |
  | Withheld by section 3.2 | `.unknown`, reason `no_compatible_source` | none | the key is in the manifest and not in the leave-out evidence; shown as "Estimate left out when this was logged" |
  | Left out by the owner | `.unknown`, reason `no_compatible_source` | none | the key is in the leave-out evidence; shown as "Left out by you" |
- **Re-resolution** of a saved log is not Confirm: today it has its own screen and its own service
  (`FoodReresolutionService`), which stores the fresh candidate's nutrients whole. It builds the
  candidate from the active release, as today, and so a fresh manifest (the same bytes and hash
  when the release and entry are unchanged, with a new evidence ID). **New work in that service
  and screen:** section 3.2 runs against the log's saved details and withheld keys are stored as
  unknown; the manifest is committed with the new version; an all-unknown result is blocked with
  its reason; and the screen shows each estimate's label and tier, the withheld notice, and
  "Values you left out before are not carried over". Earlier leave-outs are **not** carried: the
  saved version, with its left-out values, stays as it is in the append-only record. Leave-out is
  not offered on that screen; the owner reopens the log to leave a value out. With the database
  removed the entry cannot be re-resolved, as today.
- **Quality tier.** Each estimated nutrient shows its tier (section 3.3) as text with the colour,
  never colour alone, with a VoiceOver label that reads the text. The tier comes from the evidence
  record held in the capture manifest.
- **Nothing is selected or saved automatically.** One Log action, the quantity is always the user's,
  and import never logs. An entry whose values are all estimates is not a generic estimate under
  `FoodConfirmationPolicy`, so the identity questions of import v1 decision 12 still apply.
- No medical wording, target or classification appears with an estimate.

## 6. Privacy and egress

No new destination. Import reads a local file; search and Confirm run offline; the importer fetches
no URL. The two effects already recorded in estimates v1 section 7 apply unchanged: a public page
URL of an approved estimate (query string and fragment dropped) can appear in the daily export the
user sends, and archives carry the capture manifests. Additions: archives also carry the
leave-out evidence of section 5 (nutrient keys only, no values), and their capture manifests now
include `quality` and `corpus_sha256`; the daily export the user sends carries `estimate_quality`;
and the
implementing change records that in `privacy-and-egress.md` with the other two. The private catalogue, its review sheets and
its change reports stay in the owner's private workspace. **The build-time classifier of section
3.3 is not part of the app and adds nothing to the app's egress list.** It runs from the private
workspace and is sent generic food descriptions only: no brand, shop, receipt text, amount, date,
nutrient value or entry ID. `privacy-and-egress.md` must name its destination, payload and the
owner's approval date, as it does for other developer tooling. The first use, on 16 November
2026 with the owner's approval of each payload list, ran before that record existed; the record
was added the same day, with the owner's approval of its wording, in the change that carries
this sentence. A further destination or
payload needs a fresh approval and its record first; the repository receives this contract,
code and synthetic fixtures only.

## 7. Architecture gate

**Responsibilities**

| Responsibility | Home | Boundary |
|---|---|---|
| Strict estimates v2 decoding: v2 rules, estimate rules, the codec rules of section 3.1 | `FoodLedgerDomain`, in the existing codec, sharing its validation functions so the schemas cannot drift | pure |
| `approved_estimate` provenance kind and its contract version | `FoodLedgerDomain` and `CanonicalFoodProjection` (the owner of `foodContractVersion` and the floor), **food contract 10**: see "Version allocation" | pure, closed versions |
| Estimate eligibility against the record and the confirmed identity (sections 3.1 and 3.2) | the per-facet comparison in `FoodLedgerDomain` beside `IdentityCompatibility`; one pure policy in `FoodLedgerApplication` used by the importer, Confirm and re-resolution | pure |
| Leaving out an estimated nutrient (section 5): rule and evidence type in `FoodLedgerDomain`, orchestration in `FoodLedgerApplication` beside `FoodCorrection`, the one action in `FoodLedgerPresentation` | new work | no new port |
| Binding estimates when a candidate is built and when a log is re-resolved | `FoodLedgerApplication` (the candidate builder and the search adapter's re-resolution) | existing ports |
| Import: validate, check values and contradictions against the bundled record, derive the ID, replace atomically | `FoodLedgerApplication` (`PersonalFoodDatabaseImporting`), through `Digesting`, `GenericRecordNutrientLookup` and `PersonalFoodDatabaseStoring` | ports only |
| Capture manifest and leave-out evidence, committed with the log, verified on save and reopen | `FoodLedgerApplication`; types in `FoodLedgerDomain` | existing ports |
| Stored bytes and manifest (third known schema) | `FoodLedgerPersonalDatabase` | complete file protection |
| "Estimated" labels with the quality tier's text and colour, details, notices and Settings copy for each new rule code | `FoodLedgerPresentation`, from stored provenance and evidence, never a view-only flag | presentation only |
| Writing the file | the `personal-food-catalogue` skill, outside the app | private workspace |

**The lookup port.** `GenericRecordNutrientLookup` is planned by estimates v1 section 4.3 and not
yet built. Here its one method is `record(source, corpusSHA256, recordID) ->
Result<GenericRecordFacts, GenericRecordLookupFailure>`, where `GenericRecordFacts` is a domain
value holding the record's `NutrientSet`, `DecisiveIdentity` and edible quantity (the importer
uses all three, Confirm the identity only), and the failures
are `corpusMismatch` and `recordMissing`. It is owned by `FoodLedgerApplication`. The CoFID, USDA
and TFDA conformances live beside the existing `GenericRecordResolving` ones in
`PersonalFoodDatabaseResolvers.swift`, so the existing no-URL boundary rule covers them. One shared
contract suite runs against all three and also asserts that the lookup and `resolve` agree on
identity, edible quantity and nutrients for the same record.

**Version allocation (supersedes estimates v1 section 5.1 on the numbers only).** Estimates v1
planned contract 9, migration `v9_approved_estimate` and `food-ledger-v9`. Contract 9 has since
been taken by estimate layers on Open Food Facts products (`v9_off_label_estimate`). Approved
estimates therefore take **contract 10**. The sites that change: `foodContractVersion` rises to 10;
the floor returns 10 for a record holding `approved_estimate` provenance, `pfd-estimate-capture-v1`
or `pfd-estimate-left-out-v1` evidence, checked before the contract 9 rule, which is left exactly
as it is; a metadata-only migration `v10_approved_estimate` sets `food-ledger-v10`;
`FoodLedgerGRDBStore.schemaVersion` and the store's open check accept `food-ledger-v10`. As with
v9, the migration moves every store to `food-ledger-v10` on open, so contract 9 binaries decline
the store; an archive without estimates keeps its contract and its bytes. If 10, daily export
version 3 or the amendment name A2 is taken by the time the phase starts, the phase takes the next
free one and says so in its gate.

**Daily export version 3 (supersedes estimates v1 section 7's daily export bullet, its decision C4
and its version 2 test line, on the number only).** Estimates v1 raised `food_daily_schema_version`
to 2 for a document holding an approved estimate, but
[daily export v2](food-daily-export-contract-v2.md) (implemented 16 November 2026, #312) takes 2 for every
document. Version 3 is defined only as daily export v2's shape plus the estimate fields, so the
estimates phase depends on daily export v2 having landed. It is recorded as a dated amendment to
daily export v2, with goldens in `docs/fixtures/food-daily-v3/`:

- Written only for a document holding at least one `approved_estimate` value; any other document
  is written as version 2, byte-identically to a build without this change.
- Validator map row for 3: `summary_version` v6, `amount_method` on every entry and
  `notes.quantity_estimates` present, as for 2. A version 2 file carrying an estimate field, or a
  version 3 file with no `approved_estimate` value, is rejected.
- 2 and 3 replace each other for a date under the same Drive file ID, by the ordering token, in
  both directions (an estimated entry added to or removed from the day).
- Every later schema version includes the estimate fields; none reuses 3.
- A build with daily export v2 but without this change rejects a version 3 file in `validate` and
  so fails closed, as the v2 downgrade rule says.

**Dependency direction.** Unchanged: presentation and infrastructure depend on application, which
depends on domain. No new target. One port beyond today's, defined above. No framework or
persistence type crosses a port.

**Invariants (closed).** Unknown is not zero. An estimate is never measured and never overwrites a
label value. Approval is not logging. One source per nutrient. A carried value equals its bundled
record, within the inherited tolerance. An estimate never changes a reference's role or an entry's
identity. A `national_composition` estimate never survives a known contradiction with the confirmed
identity, and no approved estimate survives a basis change; where the record's facet is unknown the
label and the owner's approval are the safeguard, and the contract says so. Confirm has no
route from an estimate to a measured value: an estimate is kept, withheld or left out. v1 and v2
files, and every stored record, archive and export, decode and re-encode unchanged. No network
call.

**Extension axes.** The store remains the one variation point. A new source type, method, transform
or state is a new schema version, not configuration. A new quality tier or ceiling is likewise a new schema version.

**Contract tests** (synthetic fixtures only, in a new
`docs/fixtures/personal-food-database-estimates-v2/` with a manifest of expected rule codes; the
skill's checker and the Swift decoder both read it for codec codes):

- The v1 and v2 golden files and every existing fixture give the same rule code and hash as before.
  Key and schema order (section 2): an estimates v1 file gives `schema`; a v1 or v2 file carrying
  `estimate_evidence` and an estimates v2 file missing either estimate key give their pinned codes;
  a manifest whose schema disagrees with its file is rejected; a failed replacement keeps the
  active release.
- The rule-code enum equals the estimates v2 manifest's code list, and the v1 and v2 lists are its
  subsets. Settings copy exists for each new code.
- A v2 file re-labelled as estimates v2 with empty estimate fields is accepted; a scaled
  per-serving value and an estimate on different keys of one entry are accepted.
- Every inherited rejection fixture, re-based on v2, keeps its code string, except `own-reference`.
- Inherited codes: one fixture each for `token`, `date`, `digest` and `derivation`; an estimates v1
  file's full code list is exactly `schema`; an unknown schema with `estimate_evidence` likewise.
- Codec table: one fixture per code (`estimate-quality` for each ceiling, including a page estimate with `state_basis` `unknown` rejected at `medium` and accepted at `low`, with a missing tier giving `evidence-keys` and an unknown
  tier `token`; an accepted `high` for each of the two methods; a similar-food estimate accepted at `medium` and `low` on an own close-match record and
  on a non-own record; an own close-match record cited as the same food gives `estimate-own-method`;
  `estimate-own-merge`, `estimate-own-held` for a `raw` and a `cooked` entry with a same-food record, and a `raw` entry accepted with its own `close` record; `estimate-own-method` for an own same-food record cited as `carried_from_similar_food`, an own `close` record cited as `carried_from_same_food`, `direct` and `derived`,
  `estimate-own-state`, `estimate-basis` on an own and a non-own record); the accepted case; a record
  matching two rows gets both in table order; a record with a dangling `entry_id` or a bad
  `method` gets no table code; a file with two faulty entries has a pinned code order with
  repeats; a codec rejection carries no importer code.
- Importer: unpinned corpus, missing record, unquantified value (missing, trace, bounded, "N") and
  a value outside the tolerance give the four codes; at zero only exact equality passes;
  `estimate-contradiction` for a `raw` entry against a `cooked`, `reheated` or `named` record and
  for a `cooked` entry against a `raw`, `as_sold`, `reheated` or `named` record; a `raw` entry
  against an `as_sold` record is accepted; a fortified record and a record without a known 100 g edible
  quantity, on a non-own record and on an entry with no reference; fortification and edible
  quantity also on an own record. The importer with no lookup for a source rejects.
  The lookup port's shared suite runs against CoFID, USDA and TFDA and the dispatching set, pins
  fortification unknown on USDA and TFDA, pins what a fortified CoFID record returns, and the
  conformances pass the no-URL boundary rule (with a failing fixture for it).
- Confirm re-check: each decisive facet has a withheld case and a kept case, including preparation
  method, `as_sold` against `cooked` (withheld), `unknown` against `cooked` (kept), drained against
  undrained and packing text; a basis change withholds a page estimate too; a record that cannot
  be read withholds with its own notice; when a reopened log's details are corrected after the database was removed or
  replaced the lookup uses the manifest's corpus hash, with the corpus-moved and record-present
  cases. Both comparisons cover the same facets.
- Precedence: label, then estimate, then merged record; a label and an estimate on one key is
  rejected; an estimate does not promote a candidate; the separate candidate carries no estimates.
- Leave-out: an estimated value shows "Estimated" and its details; identity-only correction keeps
  label and provenance; each row of the stored-shapes table has a case, with its reopen wording;
  untouched nutrients keep their provenance bytes; repeating, undoing and cancelling a leave-out
  each have a case; leaving out or withholding every value blocks Log with its reason; all
  estimates left out but one label value kept, then reopened, shows "Left out by you"; a second
  change to a saved log writes a second evidence item and the newest version's governs; the
  evidence holds keys and no value and is loaded on reopen through the decision's evidence IDs,
  also after an archive restore; a leave-out or an undo alone on a reopened log writes a new
  resolution version; an identity-only correction of a reopened log keeps earlier leave-outs; a
  reopened log reads no record and shows saved values after the corpus pin moves; `as_sold`
  against `raw` is kept, in both directions; Confirm offers no field for an estimated nutrient's value;
  the domain still rejects `approved_estimate` as measured or bounded; the manifest's bytes and
  hash are unchanged and still verify, also when no provenance cites it. Log is never
  pre-selected; an estimate-only entry is not a generic estimate.
- Evidence (manifest or leave-out): altered evidence shows "Evidence not available" and changes no
  stored value; a missing evidence row is a store integrity failure and the log does not load;
  both are separate cases, on save and on reopen,
  including after the database is removed and after an archive restore.
- Re-resolution, in its own service: a contradicted estimate is stored as unknown, an all-unknown
  result is blocked, the manifest is saved, labels, tiers and both notices are shown, and no
  leave-out is offered. Same release gives the same manifest bytes and hash; a different release gives a
  new manifest; in both the earlier leave-outs are not carried, the notice is shown and the saved
  version is unchanged; with the database removed there is no re-resolution.
- A candidate with no estimate writes no manifest and its log keeps its contract.
- Versions: an archive without estimates keeps its contract and bytes; every store becomes
  `food-ledger-v10`; the floor returns 10 for a log holding an approved estimate, for one holding
  only the manifest, for one holding only leave-out evidence and for `approved_estimate` found
  only in a candidate decision or conflict candidate; a contract 9 binary declines it; the open
  check refuses v9 metadata on a v10 schema and the v10 migration is metadata only; the store
  round-trips an estimates v2 manifest.
  Every closed `ProvenanceSourceKind` site listed in estimates v1 is re-run at contract 10.
- Saved logs hold `approved_estimate` as `.augmented`, survive replace, remove and archive restore,
  and export `state: "estimated"`; a withheld or left-out value exports as unknown, never zero,
  and keeps the day's totals partial; a day whose only estimate was left out is written as
  version 2.
- Daily export: each bullet of the version 3 rules above, through serialisation, Drive validation,
  reconciliation and recovery.
- Search: an entry that gains its first known nutrient from an estimate becomes visible; an
  estimated fat value takes part in the requested-fat partition; escalation sufficiency counts it.
- Evaluator counts, with synthetic lists: each of the six, with a failing case for each of the
  four that must be zero (pass-off, refused not re-admitted, re-admitted above `medium`,
  aggregator above `medium` with no stated source); a withdrawn row counts as
  refused again; a never-re-admissible class is refused even when listed; a list row with no
  accepted sheet row is refused; a re-admitted own record on a `raw` entry still gives
  `estimate-own-held`.
- Quality tier: each of the five labels renders with its colour and its reasons in details, and
  no label exists for a similar-food estimate at `high`; a leave-out and an undo on a reopened
  log keep estimate status, decision record and outcome, for a decided-estimate log and for a
  previously corrected one; a one-step save of a state holding a manifest is refused; a favourite
  whose estimates were all withheld opens Confirm; the pasted-label reader ignores leave-out
  evidence; a
  similar-food estimate's visible label says so; the colour never appears without text and totals
  carry none; a version 3 export value without `estimate_quality` is rejected; a leave-out alone
  compares as edited and writes a product version and assertion; a key both withheld and left out
  is stored as withheld, and undo on a reopened log runs the check and withholds on an unreadable
  record; with leave-out evidence altered, a later correction keeps the saved unknowns; a withheld key
  returns with its label when a correction of details removes the contradiction, and stays
  unknown when the record cannot be read; a
  leave-out on a new log still asks and records identity decisions and stores the uncorrected
  outcome; the leave-out assertion and edit reason texts are pinned, new and reopened; after
  undoing every leave-out the stale item is ignored, and of three successive changes only the
  newest is read; a key left out, withheld and released before Log stays left out; quick add and
  re-log of an entry with an estimate, a withheld key or a left-out key open Confirm; the
  manifest carries the tier and a reopened log shows the tier it was logged with after the
  database is replaced; the tier changes no value, provenance kind, ranking or veto; a
  similar-food estimate is withheld on a known contradiction like any other; export version 3
  carries `estimate_quality` and a version 2 file carrying it is rejected.
- Simulator journey: import a synthetic estimates v2 file, search, open Confirm, read the estimate
  details, leave one value out, log, remove the database, reopen the log.

Validation is the gates in `AGENTS.md` **plus the FoodSearchQuality and FoodQueryEvaluation steps
of the CI workflow**: the sort itself is untouched, but its inputs are not. Estimates count towards
visibility, the fat partition and escalation sufficiency, so an entry filled by estimates can stop
the online lookup being offered; the evaluations report how many results that changes. No
evaluation result of R1 or R2 is carried onto an estimates v2 release, and sealed sets stay with
their authorised evaluator. The implementing change also updates `privacy-and-egress.md` as
estimates v1 section 7 requires. Device acceptance is the owner's.

## 8. Decisions for the owner

All seven were decided by the owner on 16 November 2026. The owner then accepted the contract as
a whole on the same day (section 9).

- **P1. Which estimates schema does the app implement? Decided 16 November 2026: only
  `personal-food-catalogue-estimates-v2`,** with the support table of section 2. Cost, accepted: an R2
  companion is not importable by the app, and an estimates v2 release ships with no Part B result
  of its own until one is run on it. Accepting this adds dated amendment notes to estimates v1 and
  the E3 disposition.
- **P2. How do same-food entries with no cooking state get values? Decided 16 November 2026:
  section 3** (a labelled, per-nutrient estimate from the entry's own same-food record, as identity
  amendment A2 with its contradiction veto). Not taken: the stricter variant, to also reject an own-record estimate
  whose record preparation the adapter holds as unknown; safer, fewer entries filled; and
  an "as sold" state that merges; mechanical and with no free text, but it amends the merge rule,
  shows no "Estimated" label and settles every facet from the record.
- **P3. Which E3 builder obligations bind the v2 catalogue? Decided 16 November 2026: all of
  estimates v1 section 3.1 and the obligations added in section 3.1 here bind by default, and the
  owner may re-admit a refused source row by row on a fresh approval** (section 3.1). This was the
  alternative, not the recommendation: it gives more coverage and reopens a decided disposition,
  which is why it is recorded as an amendment to E3 and overrides no mechanical rule. Limit,
  stated: the lists are keyed to the pinned release, so entries with no counterpart there are
  counted, not checked.
- **P4. Close matches. Decided 16 November 2026, then reopened the same day: close matches are
  admitted** as `carried_from_similar_food` estimates, labelled as from a similar food and never
  in the highest tier (sections 3 and 3.3). The first decision was same food only.
- **P5. Order of work. Decided 16 November 2026: one implementation phase** after acceptance, after daily
  export v2 has landed, with its own issue and a fresh architecture gate: codec and rule codes,
  provenance kind and contract 10, lookup port, eligibility policy, manifest, leave-out and its
  evidence, Confirm, export version 3 and Drive admission, privacy record. It is a large review
  surface; nothing ships until estimate provenance is bound end to end.
- **P6. One estimated value on Confirm. Decided 16 November 2026: leave out only.** There is no
  typed value on Confirm in this release; a pack value goes through the existing label routes
  (section 5).

- **P7. Quality tier. Decided 16 November 2026:** every estimate carries `high`, `medium` or `low`,
  shown as green, amber and red with text, with codec ceilings; a build-time classifier may
  advise, and the owner accepts each tier on the review sheet (section 3.3).

## 9. Review record

- 15 November 2026: three local Qodo passes; two findings fixed (manifest never edited; basis
  rule).
- 16 November 2026: blind architecture-gate and invariant review by a second agent, NEEDS WORK on
  both, seven findings, each checked against the code and accepted: contract 9 already taken (now
  contract 10); Confirm has no nutrient correction (section 5, decision P6); the own-record rule
  conflicted with identity section 8 (amendment A2 with a veto); decoder promises contradicted P1
  (support table); search evaluations wrongly exempted (now required); P3 too loose; new
  rejections had no codes and "must equal" contradicted the inherited tolerance.
- 16 November 2026: two local Qodo passes on that revision, four findings fixed (veto on every
  decisive facet, P3 keeps the no-laundering rule, daily export version 3 on the v2 shape).
- 16 November 2026: repeat gates by two blind subagents, NEEDS WORK on both. Accepted and folded
  in: the veto and re-check now cover every `national_composition` estimate; the record identity's
  source at Confirm and the unreadable case; rule code strings, traversal and stages; stored shapes
  and correction evidence; daily export version 3's rules; the E3 held-at-candidate obligation and
  the evaluator's count; full-preparation comparison; the empty typed field; basis guard on every
  estimate; re-resolution; the lookup port's signature. Limits stated instead of fixed: facets the
  record holds as unknown cannot veto. The owner then decided P4 (same food only).
- 16 November 2026: third gates on that revision, NEEDS WORK on both with fewer and smaller
  findings, all folded in: `as_sold` now contradicts a cooked record; `estimate-own-held` keeps a
  held or demoted same-food record from refilling a raw or cooked entry; Log is blocked while no
  nutrient is known; the manifest carries the corpus hash; correction evidence is per resolution
  version and found by its version ID; re-resolution carries no corrections; four missing
  inherited codes; the typed field's unit and basis; `sourceID`; smaller wording points.
- 16 November 2026: the owner decided P6 (leave out only). Section 5 lost the typed label value,
  its stored shape and its export case; the evidence item now holds left-out keys only.
- 16 November 2026: the owner decided P1 (estimates v2 only).
- 16 November 2026: the owner decided P2 (labelled estimates from the entry's own record).
- 16 November 2026: the owner decided P3 (refusals bind by default; row-by-row re-admission on a
  fresh approval). The re-admission text of section 3.1 is new and has had no review.
- 16 November 2026: the owner decided P5 (one implementation phase after daily export v2).
- 16 November 2026: fourth gates (two blind subagents, both NEEDS WORK) and one Qodo pass (two
  findings) on c98b2eb. No route from an estimate to a measured value, a label overwrite or a
  zero was found. Folded in: re-admission got a closed list of what can and cannot return, a
  per-value row tied to the review sheet, three evaluator counts and named amendments; the false
  claim that it reaches only non-`raw`, non-`cooked` entries was corrected; the leave-out set is
  Confirm state that forces a new version and its evidence is reached through the decision's
  evidence IDs; reopening alone reads no record; `as_sold` against `raw` is pinned as a
  contradiction; the evidence was renamed `pfd-estimate-left-out-v1`.
- 16 November 2026: the owner confirmed the never-re-admissible list of section 3.1 as what P3
  means.
- 16 November 2026: the owner decided that `as_sold` and `raw` do not contradict (the
  recommendation was to withhold). Section 3.2 and its tests say so. No owner question is open;
  the fixes since c98b2eb have had no review of their own.
- 16 November 2026: the owner stated the aim (fill as much as possible with reasonable, labelled
  estimates), reopened P4 to admit close matches and added the quality tier (P7).
  `estimate-similar` is gone and `estimate-quality` is new. None of this has been reviewed, and
  section 3.3 is new text.
- 16 November 2026: fifth gates (two blind subagents, both NEEDS WORK) and one Qodo pass on
  04f06c2. No route to a measured value or a zero and no app network call were found. Folded in:
  `estimate-quality` is the ceiling only; `estimate-own-held` is limited to same-food records so
  close matches on raw and cooked entries are not shut out; the ceilings are one decidable rule;
  the pass-off count is unconditional and a fourth count caps re-admitted tiers; the visible
  label names a similar food; one "food facts changed" predicate covers leave-outs; the evidence
  ID rides on the decision's embedded candidate; withholding wins over leaving out and undo is
  checked; export and privacy text name the new fields and the build-time classifier; the schema
  order sentence. These fixes have had no review of their own.
- 16 November 2026: sixth gates (two blind subagents, both NEEDS WORK with two blocking findings
  each, the rest left to the phase gate) and one Qodo pass (one new finding, the same as a gate's).
  No route to a measured value, a label overwrite, a zero or an app network call was found.
  Folded in: quick add and re-log always go through Confirm; the changed-facts predicate decides
  only whether new records are written, so a leave-out is not a correction; six evaluator counts,
  four of them must-be-zero; the closed label list; the reader takes only the effective version's
  leave-out item; a missing evidence row fails closed. The classifier's record was then added to
  `privacy-and-egress.md` with the owner's approval of its wording. These fixes have had no
  review of their own.
- 16 November 2026: seventh gates (two blind subagents, both NEEDS WORK, five blocking findings
  between them, all a sentence or two) and one Qodo pass (one finding). No route to a measured
  value or a zero and no app network call was found; the file rules, tier ceilings and six counts
  were reported consistent. Folded in: re-resolution has its own service and screen, where the
  check, the manifest, the labels and the notices are new work; a leave-out on a reopened log
  carries the saved identity, decision record and outcome; quick add is detected from the
  restored candidate and refused at save; the evidence tests are split; re-admission has a sheet
  of its own; the bare "Estimated" wording is gone. The egress paragraph's missing facts (key,
  provider routing, storage) were then added with the owner's approval of the wording.
- 16 November 2026: the egress paragraph was completed, and **the owner accepted the contract.**
  The seventh round's fixes had no review of their own at acceptance; the items the reviewers
  left to the phase gate are in section 5 and the contract tests. Recorded with the acceptance:
  dated amendment notes in estimates v1, the E3 disposition and the identity contract (A2).
- 16 November 2026, before the PR was marked ready: main was merged in (one conflict, the ledger
  file, both sections kept) and a last Qodo pass on the whole branch raised two findings, both
  fixed: the egress paragraph still called this contract a proposal, and a withheld value could
  not return after its contradiction was corrected.
