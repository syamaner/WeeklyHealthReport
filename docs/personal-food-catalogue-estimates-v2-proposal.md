# Personal food database: labelled estimates on catalogue v2 (proposal)

Status: **proposal, 15 November 2026, revised 16 November 2026 after a blind review (section 9).
Not accepted, nothing implemented.** Section 8 lists the decisions; P4 is decided, five are open. No app
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

The codec today rejects on the top-level key set before it reads `schema`. With a second key set
that order is fixed as: (1) the key set is v2's or v2's plus `estimate_evidence`, else `top-keys`;
(2) `schema` is a known value, else `schema`; (3) the key set is the one that schema requires, else
`top-keys`. So an estimates v1 file gives `schema`, a v1 or v2 file carrying `estimate_evidence`
gives `top-keys`, and no existing v1 or v2 fixture changes its code.

Each schema's rules apply only to files that declare it. Stored releases, manifests, records,
archives and exports decode and re-encode unchanged. The store keeps its fixed file name (import v2
decision 4) and its manifest accepts the new schema as a third known value. An R2 companion is not
importable by the app; if it should ever be, that is a rebuild as estimates v2, never a conversion
in the app.

## 3. The changed rule: an estimate may cite the entry's own same-food record

Estimates v1 section 2.3 rejects "a `national_composition` estimate whose `composition_source` and
`source_reference` name the same record as that entry's `generic_reference`, whatever its role".
Estimates v2 allows it for a `candidate` record matched `same_food_same_state`, under the
conditions below. **This is an identity exception and is proposed as one:** amendment A2 to
[identity contract](food-identity-nutrition-contract.md) section 8, recorded there when this
proposal is accepted. Section 8 makes a value with an unknown or contradictory decisive attribute
ineligible; A2 lets an owner-approved, labelled estimate cover an **unknown** attribute and never a
**contradictory** one. Amendment A1 (the merge rule) is not changed. Import v1 decision 8 keeps its
wording (a `candidate` record never merges) but is narrowed in effect: the entry itself can now
show values that came from its candidate record, as labelled estimates.

**First release: same food only (owner decision P4, 16 November 2026).** A `national_composition`
estimate with `method` `carried_from_similar_food` is rejected in this schema, own record or not.
The 213 close-match entries keep their separate "Generic" candidate and nothing else.

### 3.1 What the file must satisfy

Codec rules (pure, from the file alone), in this order for each estimate:

| Rule | Code |
|---|---|
| A `national_composition` estimate with `method` `carried_from_similar_food` | `estimate-similar` |
| Own record with `role` `merge` (the merged record already supplies its values) | `estimate-own-merge` |
| Own `candidate` record whose match is not `same_food_same_state`, or whose `method` is not `carried_from_same_food` | `estimate-own-method` |
| Own `candidate` record whose `state_basis` is `unknown` | `estimate-own-state` |
| Any `national_composition` estimate on an entry whose `basis` is not `per_100_g` (no density is ever inferred; such an entry takes page estimates stated per 100 ml, or stays unknown) | `estimate-basis` |

Importer rules (need the bundled record), run **only on a file the codec accepted**, so a rejection
holds codec codes or importer codes, never both. For each `national_composition` estimate, own
record or not, in this order: `corpus-mismatch`, `record-missing`, `value-unquantified`,
`value-mismatch` (the four checks of estimates v1 section 4.3, named here for the wire), then
`estimate-contradiction`.

**Traversal.** The codec keeps its rule of appending codes in the order found, repeats kept. The
inherited estimate checks run as in the R2 tool and keep its code strings (`evidence-keys`,
`not-approved`, `type-fields`, `corpus-undeclared`, `source-reference`, `open-food-facts-host`,
`free-text`, `derivation-missing`, `derivation-shape`, `derivation-unexpected`, `evidence-id`,
`evidence-duplicate`, `evidence-order`, `estimated-nutrients`, `estimate-keys`,
`label-and-estimate`, `evidence-dangling`, `evidence-mismatch`, `evidence-unused-or-shared`);
`own-reference` is retired in this schema and replaced by the table above. After them the codec
walks `estimate_evidence` in file order and applies the table to each record in table order. The
importer walks the same list in the same order. All new strings join `PersonalFoodDatabaseRuleCode`
in an estimates-only set, as `v2Only` does for import v2. The Python checker has parity for codec
codes only; importer codes are Swift tests with a stub lookup and the shared adapter suite.

**Value comparison** is the inherited one: at zero the file value and the record's value must be
exactly equal, otherwise they differ when more than 0.5 per cent of the record's value apart. A
record with no quantified value can never yield one. Unknown stays unknown.

**Contradiction (closed list, mechanical), for every `national_composition` estimate.** The file is
rejected with `estimate-contradiction` when any of these holds:

- the entry's `state` is `raw` or `cooked` and the record's preparation kind is `raw` or `cooked`
  and different;
- the record is fortified (an entry is never a fortified food, as for a merge);
- the record is not per 100 g with a known 100 g edible quantity.

**What the mechanical checks cannot see, stated plainly.** An entry `state` of `canned`, `frozen`,
`dried`, `smoked` or `unknown` maps to preparation unknown in the app, and those are the entries
this route exists for, so for them the list above checks fortification and basis only. A facet the
adapter holds as unknown on the record cannot veto either: USDA and TFDA records never state
fortification, so the fortified-record rule can fire for CoFID only. In both cases the safeguards
are the two free-text states, the `assumption`, the owner's approval of each value and the
"Estimated" label. That part is a builder and owner obligation; a fixture cannot prove an
assumption true. To keep it visible, the private change report counts estimates whose record
preparation is unknown and estimates from a source that never states fortification, and decision
P2 offers the stricter rule.

**Builder obligations added to estimates v1 section 3.1** (not checkable by the importer):

- An entry whose reference the E3 disposition demoted, removed or held at `candidate` takes no
  estimate from that record by any route (E3 disposition sections 4 and 4.1). A record or value E3
  withheld for a food stays refused for that food.
- Those lists are keyed to entry IDs of the pinned evaluation release. The builder carries them
  across by the private mapping of old entries to v2 entries; the **evaluator**, not the builder,
  reports the refused count, which must be zero in the file. An entry with no counterpart in the
  pinned release cannot be checked this way; such entries are counted separately as "no E3
  counterpart" so the limit of the rule stays visible.

### 3.2 What Confirm must do with it

An estimate does not give the entry the record's identity: a non-merged entry keeps its mostly
unknown facets, the identity questions of import v1 decision 12 are still asked, and the separate
"Generic" candidate is still offered with only its own record's values. Because the owner can then
answer those questions, every `national_composition` estimate is re-checked against the answers.

- **Where the record's identity comes from.** When the candidate is bound to Confirm, the
  application reads each cited record's `DecisiveIdentity` and edible quantity through
  `GenericRecordNutrientLookup` (section 7) and holds them in the Confirm state for that log. They
  are not added to the capture manifest, whose content stays as estimates v1 section 5.2 defines.
  **When a record cannot be read** (corpus pin moved, record missing), every estimate that cites it
  is withheld.
- **The comparison** is per facet and uses the equality the existing `IdentityCompatibility` rule
  uses, with one difference: a facet unknown on either side does not contradict. Preparation
  compares the whole state (kind, and method when both sides name one); `as_sold` and `unknown` on
  the confirmed side assert no cooking state and contradict nothing; packing medium is exact text
  equality. A facet (preparation, bone, skin, drained state, packing medium, fortification) that is
  known on both sides and different withholds every estimate citing that record.
- **Basis.** Changing the serving basis away from the entry's own withholds **every approved
  estimate** on the log, page estimates included: a value is never reinterpreted from per 100 g to
  per 100 ml or back.
- **Withheld** means the nutrient is unknown for that log, with the plain notice "Estimate left
  out: it does not match these details". Nothing is substituted.
- Otherwise the estimate stays, labelled "Estimated".

The check is one pure application policy over the estimate, the record's identity and the confirmed
identity. It runs when Confirm is bound, after each correction, and on re-resolution of a saved log
(against the saved identity). A reopened log that is not corrected shows its saved values as saved.

Why this route and not a wider merge (decision P2): an "as sold" merge would give the entry the
record's identity for every facet (amendment A1), silently settling drained, bone and packing, the
facets most likely to be wrong for tinned food, and it would show no per-value label. Here every
value shows "Estimated" with its assumption, a contradiction withholds the value, and the merge
rule stays closed. What the merge has in its favour: its values are read from the bundled corpus,
never copied into a file, and nothing rests on free text.

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
source type, the two states, the assumption and "Page not read directly" in details, record
identifiers behind details, and the existing "Nutrients from more than one source" notice. Added
here:

- **Correction before Log is new work, not an existing flow.** Today "Correct food details"
  changes identity and details only and carries the candidate's nutrients through unchanged
  (`FoodDetailsSheet.correction`, `FoodCorrection`). So:
  - *Identity-only corrections* keep every estimate and its "Estimated" label, subject to the
    re-check of section 3.2.
  - *Per-nutrient correction* is added for estimated nutrients only, with two actions (decision
    P6). **Leave out**: the nutrient is unknown for this log. **Enter the label value**: the owner
    types the value printed on the pack. The field starts empty and is never pre-filled with the
    estimate; only an exact value is accepted. It is saved as the owner's declaration, measured, as
    import v1 decision 11 treats values the owner typed from a pack. There is no "revised
    estimate": a typed number is the owner's declaration or it is not entered.
  - Nutrients the owner does not touch keep their provenance byte for byte. Undoing a correction
    before Log returns the nutrient to the captured estimate, subject to section 3.2.
- **The capture manifest (`pfd-estimate-capture-v1`) is never edited.** It is built once when the
  candidate is bound to Confirm and stays exactly as captured, so the record of what was offered
  survives a correction or a withheld value. A correction changes the log being confirmed, never
  the imported database or the manifest. A manifest that no saved provenance cites any more (every
  estimate withheld, left out or replaced) is still saved and still verified on reopen.
- **Correction evidence `pfd-estimate-correction-v1`.** One item per log, written only when at
  least one estimate was left out or replaced. Inline `CaptureEvidence`, kind `.labelText`,
  `originalPayload` `.text(<canonical JSON>)`, `byteHash` its SHA-256, `captureMethodVersion`
  `pfd-estimate-correction-v1`, committed in the log's `LedgerMutation`. Content: `schema`, the
  capture manifest's hash, the entry's `basis`, and for each corrected nutrient the key, the action
  (`left_out` or `label_value`), the estimate's value and unit it replaced, and for `label_value`
  the typed value and unit. Other `.labelText` readers select by `captureMethodVersion` and ignore
  it, and its reader ignores theirs (one test each way). Verified in the application on save and on
  reopen exactly as the manifest is; missing or altered evidence shows "Evidence not available" and
  never changes stored values.
- **Stored shapes** (no new `UnknownReason` and no new stored raw value beyond `approved_estimate`):

  | Case | Stored value | Provenance | How reopen tells it apart |
  |---|---|---|---|
  | Estimate kept | `.augmented` | `approved_estimate`, as estimates v1 section 5.1 | provenance |
  | Withheld by section 3.2 | `.unknown`, reason `no_compatible_source` | none | the key is in the manifest and not in the correction evidence; the notice is shown again |
  | Left out by the owner | `.unknown`, reason `no_compatible_source` | none | the key is in the correction evidence as `left_out`; shown as "Left out by you" |
  | Label value typed | `.measured` | `manual_declaration`; `sourceID` and `manifestReference` `pfd-estimate-correction-v1#<nutrient key>`; `sourceReleaseID` the database release; `evidenceID` and `responseHash` the correction evidence's; `capturedAt` from the injected clock | provenance |

  The application refuses to save a typed value without that evidence, since domain validation of
  a measured `manual_declaration` asks for none.
- **Re-resolution** of a saved log re-runs section 3.2 against the saved identity, never replaces a
  typed value and keeps a left-out nutrient unknown.
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
| Strict estimates v2 decoding: v2 rules, estimate rules, the codec rules of section 3.1 | `FoodLedgerDomain`, in the existing codec, sharing its validation functions so the schemas cannot drift | pure |
| `approved_estimate` provenance kind and its contract version | `FoodLedgerDomain` and `CanonicalFoodProjection` (the owner of `foodContractVersion` and the floor), **food contract 10**: see "Version allocation" | pure, closed versions |
| Estimate eligibility against the record and the confirmed identity (sections 3.1 and 3.2) | `FoodLedgerApplication`, one pure policy used by the importer, Confirm and re-resolution | pure |
| Per-nutrient correction (section 5): rule and evidence type in `FoodLedgerDomain`, orchestration in `FoodLedgerApplication` beside `FoodCorrection`, the two actions in `FoodLedgerPresentation` | new work | no new port |
| Binding estimates when a candidate is built and when a log is re-resolved | `FoodLedgerApplication` (the candidate builder and the search adapter's re-resolution) | existing ports |
| Import: validate, check values and contradictions against the bundled record, derive the ID, replace atomically | `FoodLedgerApplication` (`PersonalFoodDatabaseImporting`), through `Digesting`, `GenericRecordNutrientLookup` and `PersonalFoodDatabaseStoring` | ports only |
| Capture manifest and correction evidence, committed with the log, verified on save and reopen | `FoodLedgerApplication`; types in `FoodLedgerDomain` | existing ports |
| Stored bytes and manifest (third known schema) | `FoodLedgerPersonalDatabase` | complete file protection |
| "Estimated" labels, details, notices and Settings copy for each new rule code | `FoodLedgerPresentation`, from stored provenance and evidence, never a view-only flag | presentation only |
| Writing the file | the `personal-food-catalogue` skill, outside the app | private workspace |

**The lookup port.** `GenericRecordNutrientLookup` is planned by estimates v1 section 4.3 and not
yet built. Here its one method is `record(source, corpusSHA256, recordID) ->
Result<GenericRecordFacts, GenericRecordLookupFailure>`, where `GenericRecordFacts` is a domain
value holding the record's `NutrientSet`, `DecisiveIdentity` and edible quantity, and the failures
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
or `pfd-estimate-correction-v1` evidence, checked before the contract 9 rule, which is left exactly
as it is; a metadata-only migration `v10_approved_estimate` sets `food-ledger-v10`;
`FoodLedgerGRDBStore.schemaVersion` and the store's open check accept `food-ledger-v10`. As with
v9, the migration moves every store to `food-ledger-v10` on open, so contract 9 binaries decline
the store; an archive without estimates keeps its contract and its bytes. If 10 is taken by the
time the phase starts, the phase takes the next free number and says so in its gate.

**Daily export version 3 (supersedes estimates v1 section 7's daily export bullet, its decision C4
and its version 2 test line, on the number only).** Estimates v1 raised `food_daily_schema_version`
to 2 for a document holding an approved estimate, but
[daily export v2](food-daily-export-contract-v2.md) (decided, not implemented) takes 2 for every
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
label and the owner's approval are the safeguard, and the contract says so. A typed correction is
an owner declaration with its own verified evidence, never a silent edit of an estimate. v1 and v2
files, and every stored record, archive and export, decode and re-encode unchanged. No network
call.

**Extension axes.** The store remains the one variation point. A new source type, method, transform
or state is a new schema version, not configuration. Admitting `carried_from_similar_food` later is
a new schema version with its own gate.

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
- Codec table: one fixture per code (`estimate-similar` on an own and a non-own record,
  `estimate-own-merge`, `estimate-own-method` for a `close` match, `direct` and `derived`,
  `estimate-own-state`, `estimate-basis` on an own and a non-own record); the accepted case; a file
  with two faulty entries has a pinned code order with repeats; a codec rejection carries no
  importer code.
- Importer: unpinned corpus, missing record, unquantified value (missing, trace, bounded, "N") and
  a value outside the tolerance give the four codes; at zero only exact equality passes;
  `estimate-contradiction` for raw against cooked, a fortified record and a record without a known
  100 g edible quantity, each on an own record, a non-own record and an entry with no reference.
  The lookup port's shared suite runs against CoFID, USDA and TFDA and pins fortification unknown
  on USDA and TFDA.
- Confirm re-check: each decisive facet has a withheld case and a kept case, including preparation
  method, `as_sold` against `cooked` (kept), drained against undrained and packing text; a basis
  change withholds a page estimate too; a record that cannot be read withholds, on a new log and
  after a correction on a reopened one.
- Precedence: label, then estimate, then merged record; a label and an estimate on one key is
  rejected; an estimate does not promote a candidate; the separate candidate carries no estimates.
- Correction: an estimated value shows "Estimated" and its details; identity-only correction keeps
  label and provenance; the typed field starts empty; each row of the stored-shapes table has a
  case, with its reopen wording; untouched nutrients keep their provenance bytes; repeating,
  undoing and cancelling a correction, and correcting every estimate, each have a case; a typed
  value without its evidence cannot be saved; the manifest's bytes and hash are unchanged and still
  verify, also when no provenance cites it. Log is never pre-selected; an estimate-only entry is
  not a generic estimate.
- Evidence that is missing or altered (manifest or correction) is refused on save and on reopen,
  including after the database is removed and after an archive restore.
- Re-resolution: a log with one estimate withheld, one left out and one typed keeps all three.
- Versions: an archive without estimates keeps its contract and bytes; every store becomes
  `food-ledger-v10`; the floor returns 10 for a log holding an approved estimate, for one holding
  only the manifest and for one holding only correction evidence; a contract 9 binary declines it.
  Every closed `ProvenanceSourceKind` site listed in estimates v1 is re-run at contract 10.
- Saved logs hold `approved_estimate` as `.augmented`, survive replace, remove and archive restore,
  and export `state: "estimated"`; a typed value exports as `entered_by_you`; a withheld or
  left-out value exports as unknown with no page URL.
- Daily export: each bullet of the version 3 rules above, through serialisation, Drive validation,
  reconciliation and recovery.
- Search: an entry that gains its first known nutrient from an estimate becomes visible; an
  estimated fat value takes part in the requested-fat partition; escalation sufficiency counts it;
  a re-resolved log binds the same estimates and manifest.
- Simulator journey: import a synthetic estimates v2 file, search, open Confirm, read the estimate
  details, leave one value out, type one label value, log, remove the database, reopen the log.

Validation is the gates in `AGENTS.md` **plus the FoodSearchQuality and FoodQueryEvaluation steps
of the CI workflow**: the sort itself is untouched, but its inputs are not. Estimates count towards
visibility, the fat partition and escalation sufficiency, so an entry filled by estimates can stop
the online lookup being offered; the evaluations report how many results that changes. No
evaluation result of R1 or R2 is carried onto an estimates v2 release, and sealed sets stay with
their authorised evaluator. The implementing change also updates `privacy-and-egress.md` as
estimates v1 section 7 requires. Device acceptance is the owner's.

## 8. Decisions for the owner

In order; each open one has a recommendation.

- **P1. Which estimates schema does the app implement?** Recommended: only
  `personal-food-catalogue-estimates-v2`, with the support table of section 2. Cost: an R2
  companion is not importable by the app, and an estimates v2 release ships with no Part B result
  of its own until one is run on it. Accepting this adds dated amendment notes to estimates v1 and
  the E3 disposition.
- **P2. How do same-food entries with no cooking state get values?** Recommended: section 3 (a
  labelled, per-nutrient estimate from the entry's own same-food record, as identity amendment A2
  with its contradiction veto). Stricter variant, if wanted: also reject an own-record estimate
  whose record preparation the adapter holds as unknown; safer, fewer entries filled. Alternative:
  an "as sold" state that merges; mechanical and with no free text, but it amends the merge rule,
  shows no "Estimated" label and settles every facet from the record.
- **P3. Which E3 builder obligations bind the v2 catalogue?** Recommended: all of estimates v1
  section 3.1 plus the two obligations added in section 3.1 here; the evaluator reports the count.
  Limit, stated: the lists are keyed to the pinned release, so entries with no counterpart there
  are counted, not checked. Alternative: let the owner re-admit a refused source row by row on a
  fresh approval; more coverage, but it reopens a decided disposition.
- **P4. Close matches. Decided 16 November 2026: same food only for the first release.**
  `carried_from_similar_food` is rejected in this schema; the 213 close-match entries keep their
  separate candidate.
- **P5. Order of work.** Recommended: one implementation phase after acceptance, after daily
  export v2 has landed, with its own issue and a fresh architecture gate: codec and rule codes,
  provenance kind and contract 10, lookup port, eligibility policy, manifest, correction and its
  evidence, Confirm, export version 3 and Drive admission, privacy record. It is a large review
  surface; nothing ships until estimate provenance is bound end to end.
- **P6. What can the owner do to one estimated value on Confirm?** Recommended: leave it out, or
  enter the label value (section 5). Alternative: leave out only, with typed values going through
  the existing label routes; smaller, and no route from an estimate to a measured value on Confirm
  at all, but it does not meet "correct each value before Log".

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
- Still owed before acceptance: a repeat of both gates on this revision.
