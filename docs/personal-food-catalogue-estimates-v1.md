# Personal food database: approved estimates, contract v1

Status: **revision 2, accepted by the owner on 9 November 2026 after the re-review in section 8. C1 to C6 are decided (section 9). Not implemented: production code waits until E3 is final.**
It closes the open design items of the earlier untracked proposal ("approved estimates, v2
proposal", Codex, 9 November 2026), which it supersedes: provenance mapping, capture manifest,
transform vocabulary, and archive and export versioning. Importer implementation stays blocked
until E3 is final ([E3 disposition](personal-food-database-e3-disposition.md)) and this contract is
approved. Programme #424, base contract #419.

It extends [import v1](personal-food-catalogue-import-v1.md) and changes nothing in it except one
dated amendment: import v1 section 7 allows "only existing `ProvenanceSourceKind` cases" on save,
and that sentence gains the `approved_estimate` exception of section 5.1 for this schema alone. Ranking,
acceptance bars, seals, the pinned release and the `personal-food-catalogue-v1` format all stay as
they are. Supplements and count-based quantities stay out of scope; the name reserved for a future
supplement schema is not used here.

## 1. Required behaviour

- **An estimate stays an estimate** through import, Confirm, Log, reopen, archive restore and the
  daily export. Approval never makes it a measured or owner-declared label value.
- **Evidence belongs to each nutrient.** Different nutrients of one food may have different sources.
- **Unknown is never zero.** Missing, trace, bounded and unquantified observations are omitted from
  the file and appear as unknown. Only a supported zero is admitted.
- **No silent conversion.** A value is on its evidenced basis (per 100 g or per 100 ml as labelled).
  No density, cooking yield or portion conversion is inferred; a value on another basis is refused.
- **Approval is not logging.** A database entry still reaches the shared Confirm screen with one Log
  action, and the quantity is always the user's.
- **No new egress.** Import never fetches a URL. The file, the assumptions and the free-text states
  stay on the device. The one exception is section 7: the public page URL of an approved estimate
  (query string and fragment dropped) appears in the daily export the user sends to an existing
  destination, and food archives the user exports or backs up carry the capture manifests.

## 2. File format `personal-food-catalogue-estimates-v1`

A separate schema, decoded by its own decoder. The v1 decoder is unchanged and refuses this schema
(and the reverse). Every v1 rule still applies: UTF-8 without a byte-order mark, size and count
limits, strict keys at every level, no repeated keys, canonical units, finite numbers, release
identity from the file's bytes, source-release immutability and atomic replacement. The release
`schemaVersion` is `personal-food-catalogue-estimates-v1`; every other `SourceRelease` field follows
import v1 section 4.

Top level: exactly v1's keys plus `estimate_evidence`. Each entry: exactly v1's keys plus
`estimated_nutrients`. Both are required, and may be empty (`{}` and `[]`).

### 2.1 `estimated_nutrients`

A map from a nutrient inventory key to exactly:

| Field | Meaning |
|---|---|
| `value` | finite, non-negative number, never a boolean |
| `unit` | the key's canonical unit |
| `evidence_id` | the `id` of exactly one record in `estimate_evidence` |

The basis is the entry's `basis`. There is no per-value basis field, so a value on another basis
cannot be written.

### 2.2 `estimate_evidence`

A list sorted by `id`, each record with exactly these keys:

| Field | Meaning |
|---|---|
| `id` | `pfe:` and 16 lower-case hex digits, unique in the file; opaque to the importer |
| `entry_id`, `nutrient` | the one entry and nutrient that use this record |
| `approved_as_estimate` | literal `true` |
| `source_type` | closed: `national_composition`, `manufacturer_page`, `aggregator` |
| `composition_source` | `cofid`, `usda` or `tfda` for `national_composition`, with its corpus declared in `generic_corpora`; `null` for the page types |
| `source_reference` | by type: for `national_composition`, the record ID exactly as import v1 writes `generic_reference.record_id` (so `tfda:` only for TFDA); for the two page types, a public HTTPS URL with no user information, no query string and no fragment, at most 2,048 bytes (this contract's own limit), never on an Open Food Facts host (`openfoodfacts.org` or any subdomain) |
| `page_access` | `direct_read` or `indexed_copy` for the page types; `null` for `national_composition` |
| `source_digest` | SHA-256 of a retained source artefact, or `null` when none was kept; never a computed stand-in |
| `retrieved_on` | a real `YYYY-MM-DD` date for the page types; `null` or a date for `national_composition` |
| `source_state`, `target_state` | non-empty plain text, at most 200 characters, no control characters |
| `state_basis` | closed: `source_states_it`, `stated_assumption`, `unknown` |
| `method` | closed: `direct`, `derived`, `carried_from_same_food`, `carried_from_similar_food` |
| `assumption` | non-empty plain text, at most 500 characters, no control characters |
| `derivation` | `null` unless `method` is `derived`; then exactly `{transform_id, version, source_value: {value, unit}}` from section 6 |

The `source_type` tokens are the review v2 sidecar's `source_kind` values for the three admitted
kinds (the field is named `source_type` here because import v1 already uses `source_kind` on label
values); `state_basis` and `method` use the sidecar's tokens unchanged. The sidecar's
`pinned_release` and `owner_declaration` are not admitted. `owner_declaration` is not a source type here:
owner-typed or owner-confirmed label values stay `manual_declaration` label values in
`label_nutrients`, measured, as in import v1 decision 11.

### 2.3 Rejection rules (added to import v1 section 4.2)

The whole file is rejected, with a rule code and the active release unchanged, for: an
`evidence_id` with no record (dangling); a record used by no value (unused) or by more than one;
a record whose `entry_id` or `nutrient` differs from the value that cites it; a duplicate or
out-of-order `id`; `approved_as_estimate` other than `true`; a token outside a closed list; a
`source_reference` outside its type's form; a `composition_source` or `page_access` present or
missing against its type, or a `composition_source` whose corpus is not declared; an invalid date, or a missing date on a page type; free text that is empty,
too long or holds a control character; a `derivation` on a non-derived value, a derived value
without one, or one that fails section 6; the same nutrient in both `label_nutrients` and
`estimated_nutrients` of one entry; a page URL on an Open Food Facts host; a `national_composition`
estimate whose `composition_source` and `source_reference` name the same record as that entry's
`generic_reference`, whatever its role (a `candidate` record must not supply target-state values,
and a `merge` record already supplies its own); a `national_composition` value that does not match
its bundled record (section 4.3). Every unexpected type is a rejection, never a crash.

### 2.4 Release and evaluation identity

The release ID is `pfc:sha256:` of the exact bytes, as in v1. The evidence is bound to the release
by those bytes: the ID proves which evidence was imported, not that any upstream page was checked.
An estimates release is a new release. It never reuses the pinned evaluation release's ID, seals or
Part B answers (E3 disposition, section 5).

## 3. What the builder may write

### 3.1 Builder obligations (not checkable by the importer)

- Write an estimate only when the owner approved that value as an estimate.
- Never write an estimate whose source is a value or record withheld by an E3 consequence, a
  per-entry exclusion or as unresolved, including an Open Food Facts value dropped by the A1 consequence (E3
  disposition, section 4.1), and never an estimate whose underlying source is an Open Food Facts
  record, whatever page or route it was read through. The importer enforces the Open Food Facts
  host rule and the own-reference rule (section 2.3); the rest is a builder rule. The evaluator
  reports this count; it must be zero. For an aggregator, record its stated underlying source; a
  value with none stated is counted separately as "underlying source not stated" (E3 disposition,
  section 4.1).
- Never write a trace, below-limit, unstated or unquantified value as 0; write a zero only where
  the source states a quantified zero. The evaluator reports zero values by source type.
- Choose one source per nutrient. Never write both a label value and an estimate for one nutrient.

### 3.2 Not in v1

`recipe_estimate` (the transform vocabulary cannot express a recipe calculation, and import v1
decision 4 keeps composite dishes without another brand's recipe) and `prior_release` (an opaque
chain hides the underlying source; the builder writes the underlying source type instead, or
withholds the value). Adding either is a new schema version.

## 4. Precedence and admission

### 4.1 Per nutrient

For each nutrient of an entry, exactly one of these supplies a value, in this order:

1. a `manual_declaration` label value (measured), or an `exact_product_dataset` label value, under
   import v1 and its amendment A1 (including the fresh-whole rule for Open Food Facts values);
2. an approved estimate;
3. the merged generic reference (`role` `merge` only), for keys still unknown, under import v1's
   identity and state admission rules.

Because 1 and 2 never share a key (section 2.3), there is no last-write-wins case. For a
`fresh_whole` entry the amendment A1 order still decides between an Open Food Facts value and the
merged generic record; an estimate cannot meet an Open Food Facts value on one key, so the order is
unaffected. An approved estimate does take precedence over the merged generic record on its key:
the owner approved it for the food eaten, and the merged record still supplies every other unknown
key. This is decision C6. An approved
estimate never promotes a `candidate` generic reference to a merge. A separate generic candidate
carries only its own record's values, never the entry's estimates.

### 4.2 Value state

Every approved estimate is `NutrientValue.augmented`. It is never added to the measured provenance
allow-list, and historical `manual_declaration` semantics do not change.

### 4.3 Bundled-corpus check for national composition values

`GenericRecordResolving` is planned in import v1 and does not exist yet; its `resolve` call binds
search-time evidence and returns one `nil` for two different failures, so the importer does not use
it. Instead import v1's work adds one narrow, consumer-owned method beside it, taking and returning
domain types only: `recordNutrients(source, corpusSHA256, recordID) -> Result<NutrientSet,
GenericRecordLookupFailure>`, with failures `corpusMismatch` and `recordMissing`. The protocol is
`GenericRecordNutrientLookup`, owned by `FoodLedgerApplication` beside the importer that consumes
it. CoFID, USDA and TFDA adapters implement it and pass one shared contract suite. The importer adds
the other two rule codes itself, `valueUnquantified` and `valueMismatch`, by comparing the returned
set with the file value. This step depends on order of work
step 1 (section 8).

At import, each `national_composition` value is looked up with its declared corpus hash and record
ID, and compared with the record's value for that key **as the adapter stores it**, in the canonical
unit after the adapter's own unit conversion (and after the declared transform when `derived`). The
file is rejected with four distinct rule codes: corpus hash differs from the app's pin; record
missing; the record has no quantified value for that key (missing, trace, bounded or "N"), so a
file value can never stand in for an unknown; value differs. At zero the values must be exactly
equal; otherwise they differ when they are more than 0.5 per cent of the record's value apart. This makes copying fidelity an app-side check instead of trust in the
builder. It does not establish that the record describes the food eaten; the owner's approval and the
shown assumption carry that.

## 5. Provenance and the capture manifest

### 5.1 A dedicated provenance kind

Add `ProvenanceSourceKind.approvedEstimate` (raw value `approved_estimate`). No existing kind is
truthful for all three source types:

- `reviewed_web_proposal` requires a response hash, and a page value without a retained artefact has
  none; computing one would invent evidence;
- `generic_composition_dataset` would present a per-nutrient approval as a merged reference from a
  bundled record, which it is not (and its record ID would be the `pfe:` evidence ID, not a corpus
  record);
- `recipe_reconstruction` would label every estimate as a recipe.

Rules for the new kind, in the domain's `NutrientEntry` validation:

- admitted only inside `.augmented`, never `.measured` or `.bounded`;
- `sourceID` `personal-food-database`; `sourceReleaseID` the estimates release ID; `recordID` the
  `pfe:` evidence ID; `evidenceID` the ledger evidence that holds the capture manifest;
  `responseHash` the manifest's SHA-256; `manifestReference` `pfd-estimate-capture-v1#<nutrient key>`.
  All five are required.
- `transforms` holds the derivation's transform for a derived value, otherwise nothing.

The switches and equality rules over `ProvenanceSourceKind` are listed in section 8. Only the two
`NutrientEntry` switches are exhaustive (a missing case fails to compile); the `.bounded` branch uses
`default` and every other site is an equality test, so each gets a named test. Raw value strings of
existing kinds do not change, so stored records decode unchanged.

**Food contract 9.** `ProvenanceSourceKind` is a closed string enum, so an older build cannot decode
the new kind. Following the contract 6 precedent for `app_reference_definition`:
`CanonicalFoodArchive.minimumContractVersion` returns 9 for any record holding `approved_estimate`
provenance or `pfd-estimate-capture-v1` evidence, checked before the contract 8 rule; a
metadata-only GRDB migration `v9_approved_estimate` (`food-ledger-v9`) makes schema 8 binaries
decline the store. Three code sites change with it: `CanonicalFoodArchive.foodContractVersion`
rises from 8 to 9; the floor check scans entries, `resolutionVersions`, `candidateDecisions` and
`conflictCandidates`, as the contract 6 check does; and the GRDB open check, which names
`food-ledger-v8` today, accepts `food-ledger-v9`. Archives and stores holding neither keep their current contract and re-encode
byte-identically.

### 5.2 Capture manifest `pfd-estimate-capture-v1`

Saved evidence must not depend on the installed database. The manifest follows the reviewed web
proposal pattern (`ReviewedFoodProposalConfirmation`), not raw attachments: archives omit raw
attachments (`rawAttachmentsOmitted`), and attachment files are written outside the log transaction.

- **Content:** `schema`, `database_release_id`, `entry_id`, `basis`, and for each estimated nutrient
  of the candidate: the key, value, unit and the whole evidence record of section 2.2, as imported.
  No local path, file name, receipt text or other entry's data.
- **When:** the database route's confirmation builder creates it when the candidate is bound to
  Confirm, because `NutrientEntry` validation needs `evidenceID` and `responseHash` before any save.
  It encodes canonical JSON (`CanonicalEncoding`), hashes it (`Digesting`), takes an evidence ID
  (`LedgerIDGenerating`) and sets `capturedAt` from the injected `LedgerClock`.
- **Where:** inline `CaptureEvidence` with kind `.labelText` (the kind reviewed web proposals use,
  so no new closed `CaptureKind`), `originalPayload` `.text(<manifest>)`, `byteHash` the manifest
  SHA-256, `captureMethodVersion` `pfd-estimate-capture-v1`. Readers of `.labelText` evidence for
  pasted labels, label estimates and web proposals select by `captureMethodVersion`, so they never
  take an estimate manifest as their own (one test each). It commits in the log's
  `LedgerMutation`, so a failed save leaves neither, and archives carry it.
- **Verification** is in the application, on save and on reopen, as for web proposals: the payload
  hash must equal `byteHash` and the provenance `responseHash`. A mismatch or missing evidence shows
  "Evidence not available" and never changes stored values or their estimate state.

Replacing or removing the database leaves every manifest in place, and a restored log reopens with
its assumptions.

## 6. Transform vocabulary

A `derived` estimate is admitted only with one of the app's existing transform pairs, each limited
to its nutrient, source unit and the rules of import v1 section 4: `kj_to_kcal_v1` /
`pasted-label-conversions-v1` (energy, kJ to kcal), `salt_to_sodium_v1` /
`pasted-label-conversions-v1` (sodium from salt in g) and `mass-g-to-mg` / `v1` (a mass in g to the
key's canonical mg). The allow-list is one closed list in `FoodLedgerDomain`, beside
`NutrientDerivation.calculatedTransforms`; `mass-g-to-mg` exists in code today but in no closed
list. The importer recomputes the value from `source_value` and refuses a difference
above 0.5 per cent. No density, cooking yield, edible portion or recipe transform exists in v1;
adding one is a versioned contract change with its own tests. In the daily export, the two
calculations keep `calculated: true` and the unit conversion keeps `calculated: false`.

## 7. Presentation, totals and export

- **Confirm and the saved entry** show `Estimated` beside each estimated nutrient, in text, never
  colour alone. Details show, in plain words: the source type ("Food composition table", "Maker's
  web page", "Food database website"), the source state and assumed state, the assumption, "Page not
  read directly" for `indexed_copy`, and "Estimated from a similar food" for
  `carried_from_similar_food`. Record identifiers and digests sit behind details. When an entry's
  nutrients come from more than one source, the existing "Nutrients from more than one source"
  notice applies.
- **Totals** keep `includesEstimates` and the incomplete-contribution counts. An all-unknown
  nutrient has no numeric total; a partial total is a known minimum.
- **Settings** adds the count of estimated values to the existing "Your food database" row.
- **Daily export.** The new provenance keys change the file's shape, so a versioned revision of
  [`food-daily-export-contract-v1.md`](food-daily-export-contract-v1.md) adds origin
  `approved_estimate` to the closed origin table and raises `food_daily_schema_version` to 2 **only
  for a document holding at least one `approved_estimate` value**, following the floor pattern of
  `CanonicalFoodArchive.exportContractVersion`. A document without one keeps version 1. Its
  decision D4 URL rule (query string and fragment dropped) applies to these URLs too. The value exports as `state: "estimated"`,
  as every augmented value does today. Three new optional provenance fields carry the source type,
  method and state basis tokens; for page types the public source URL comes from the capture
  manifest (the `recordID` here is the `pfe:` evidence ID), so the export builder's snapshot carries
  the estimate manifests as it carries pasted-label manifests today. For this kind `content_hash`
  is the manifest's `source_digest`, never the provenance `responseHash` (which holds the manifest's
  own hash and never leaves the device), and it is omitted when `source_digest` is null. The export
  does not carry free-text states, the assumption or any page content. A document without an
  `approved_estimate` value exports byte-identically to before, version field included.
- **Egress record.** No new destination. The implementing change updates
  [`privacy-and-egress.md`](privacy-and-egress.md) to say that public page URLs of approved
  estimates can now appear in the daily export, and that food archives the user exports or backs up
  carry the capture manifests, including the free-text states and assumptions.

## 8. Architecture gate

**Responsibilities**

| Responsibility | Home | Boundary |
|---|---|---|
| Strict estimates decoding, evidence binding, precedence, transform check | `FoodLedgerDomain`: an estimates decoder beside the v1 codec, sharing its validation functions so the two cannot drift | pure; no filesystem, network or concrete hashing |
| New provenance kind and its validation | `FoodLedgerDomain` (`Nutrition.swift`) | pure |
| Import: validate, verify composition values, derive the ID, replace atomically | `FoodLedgerApplication` (`PersonalFoodDatabaseImporting`, from import v1), using `Digesting`, `GenericRecordNutrientLookup` (section 4.3) and `PersonalFoodDatabaseStoring` | ports only |
| Capture manifest: build at Confirm binding, commit inline with the log, verify on save and reopen | `FoodLedgerApplication` (database confirmation builder), manifest type in `FoodLedgerDomain`; existing `CanonicalEncoding`, `Digesting`, `LedgerIDGenerating` and `LedgerClock` ports and `CaptureEvidence` | ports only |
| Composition value lookup | consumer-owned `recordNutrients` method (section 4.3), implemented by the CoFID, USDA and TFDA adapters | domain types only |
| Contract 9 floor and migration | `CanonicalFoodArchive.minimumContractVersion`; `FoodLedgerMigrations` (`v9_approved_estimate`, metadata only) | closed versions |
| Protected bytes and active-release manifest | `FoodLedgerPersonalDatabase` (import v1 section 3) | complete file protection |
| `Estimated` labels and details | `FoodLedgerPresentation`, from stored provenance, never a view-only flag | presentation only |
| Export origin | `FoodLedgerApplication` (`FoodDailyExportOrigin`), after the contract amendment | closed table |

**Dependency direction.** Unchanged: presentation and infrastructure depend on application, which
depends on domain. No new target: the estimates decoder and provenance kind live in existing
targets, and the store target from import v1 still gets its `check-boundaries.sh` rule with a failing
fixture. Framework and persistence types do not cross ports.

**Invariants (closed).** Unknown is not zero; an estimate is not measured; approval is not logging;
one source per nutrient; release and source identity are immutable; a failed import keeps the active
release; saved evidence outlives the database; old records, archives and exports decode and
re-encode unchanged; no network call.

**Extension axes.** The store stays the one variation point. A new source type, transform or
provenance field is a new schema or contract version, not configuration. No provider framework,
generic repository or nutrition policy registry is introduced.

**Order of work** (each its own phase PR, only after E3 is final and this contract is approved):

1. Import v1: domain codec, importer, protected store, Settings lifecycle, search adapter without
   ranking change, Confirm and save, on synthetic fixtures.
2. Estimates: this contract's decoder, provenance kind, capture manifest, presentation, export
   amendment, on synthetic fixtures.
3. Ranking v12, after the v11 golden file is generated and its hash frozen (plan section 4.5).

**Contract tests** (synthetic fixtures only, in a new `docs/fixtures/personal-food-database-estimates-v1/`
with a manifest of expected rule codes, consumed by both the skill's checker and the Swift decoder):

- v1 files still decode and round-trip unchanged; v1 and estimates decoders refuse each other's schema.
- One rejection fixture per rule of section 2.3, including boolean and non-finite values, dangling,
  unused, shared and cross-entry evidence, a label and estimate on one key, bad tokens, bad URLs,
  page dates, over-long text and a disallowed transform.
- A composition value that differs from its bundled record, or cites an unpinned corpus, is rejected.
- Precedence: label value, then estimate, then merged generic, with no overlap; an estimate does not
  promote a candidate reference; a separate candidate carries no estimates.
- An estimate-only entry is not a generic estimate under `FoodConfirmationPolicy`, so the identity
  questions of import v1 decision 12 apply.
- Estimates save and reopen as `.augmented` with `approved_estimate`; the capture manifest verifies;
  a tampered or missing manifest shows "Evidence not available" and leaves values unchanged.
- Remove and replace the database: logs, manifests and release records remain; archive restore keeps
  the assumptions.
- Totals: unknown and partial contributions with estimates keep `includesEstimates` and never show a
  complete total.
- Export: `approved_estimate` origin, `state: "estimated"`, no free text, `calculated` as in section 6;
  `estimated` field absent; a document without an `approved_estimate` value matches its bytes from
  before the change, `food_daily_schema_version` 1 included, and one with such a value carries 2;
  `content_hash` equals the manifest's `source_digest`, is absent when that is null, and never
  equals `responseHash`.
- Every closed switch over `ProvenanceSourceKind` handles the new case (one test each, so a missing
  case fails at compile time or in a named test).
- No URL fetch: the importer and manifest builder compose no network-backed type.
- Atomic failure keeps the active release; alternate store implementations pass the shared store
  contract.

- Contract 9: an archive holding `approved_estimate` reports minimum 9; contract 1 to 8 fixtures
  decode and re-encode byte-identically at their own version; a contract 8 reader refuses a
  contract 9 archive; migration v9 is metadata only and schema 8 binaries decline schema 9;
  `foodContractVersion` is 9; the floor fires for `approved_estimate` found only in a candidate
  decision or a conflict candidate; the GRDB open check accepts `food-ledger-v9` and refuses v8
  metadata on a v9 schema.
- The manifest's `capturedAt` comes from the injected clock; the pasted-label, label-estimate and
  web-proposal readers ignore `pfd-estimate-capture-v1` evidence.
- A save failure leaves neither the manifest evidence nor the log.
- `.measured` and `.bounded` reject `approved_estimate`; `.augmented` rejects each of the five
  required fields when missing, and a wrong `sourceID` or `manifestReference` form.
- Export: a `CaseIterable` completeness test over the origin table; the new provenance fields and a
  manifest-derived URL.
- Composition lookup: corpus mismatch, missing record, no quantified value (missing, trace,
  bounded and "N" fixtures) and value mismatch give four distinct rule codes, including a
  zero-value case; every adapter passes the shared suite.

**`ProvenanceSourceKind` sites** (architecture gate review, 9 November 2026). Exhaustive:
`Nutrition.swift` measured and augmented branches of `NutrientEntry` validation. `default`:
the bounded branch. Closed table: `FoodDailyExportOrigin.bySourceKind`. Equality rules, each
re-checked by test: `FoodConfirmationPolicy` (generic-estimate test), `FoodDailyExport` (web URL),
`NutrientValueOrigin`, `ReviewedFoodProposalConfirmation`, `LabelSourceAdmission`,
`FoodNamedServingPolicy`, `CanonicalFoodArchive` (contract floor), `LabelEstimatePolicy`,
`PastedLabelSource` and `PlainWaterReference`. Presentation and the app target have none.
`FoodConfirmationPolicy.isGenericEstimate` returns false for an estimate-only or mixed entry.

**Review record.** Revision 1 went to a blind architecture-gate review, which returned NEEDS WORK
with five blocking findings: attachments are not archived or transactional; contract 9 was missing;
manifest timing conflicted with validation; the export claims did not match the code; the record
lookup port did not exist. A blind invariant review of revision 1 also returned NEEDS WORK, with
two blocking findings: Open Food Facts values could come back as page estimates, and an estimate
citing the entry's own candidate record would act as a forbidden merge. Revision 2 (this text)
applies both reviews: the Open Food Facts host and own-reference rejections, the missing-value and
zero rules, the export schema bump and URL rule, the egress note, the vocabulary mapping, and the
fresh-whole and merge precedence (C6).

Re-review of revision 2 (9 November 2026, both reviewers blind to each other, after C1 to C6 and
D1 to D5 were decided): architecture gate PASS WITH CHANGES, invariant review PASS WITH CHANGES.
Applied in this text: the export version rises only for a document holding an estimate, so other
exports stay byte-identical; `content_hash` is the manifest's `source_digest`, never `responseHash`;
the estimate export test expects `state: "estimated"`; the lookup protocol is named
`GenericRecordNutrientLookup` with four rule codes split between port and importer; the manifest's
`capturedAt` comes from `LedgerClock`; the contract 9 code sites; `.labelText` readers select by
method version; unresolved values join the no-laundering rule; the zero and aggregator-source
builder rules; and Part B binds to R2 only once this contract is accepted.

**Outcome:** the re-review reached PASS WITH CHANGES with every finding applied, and the owner
accepted this contract on 9 November 2026. No production code starts until E3 is final.

## 9. Decisions for the owner

- **C1. Decided 9 November 2026: yes.** A dedicated `approved_estimate` provenance kind (section
  5.1), with food contract 9 and the metadata-only migration `v9_approved_estimate`; no existing kind
  is reused.
- **C2. Decided 9 November 2026: yes.** `recipe_estimate` and `prior_release` stay out of v1
  (section 3.2). A prior-release value is resolved to its underlying source or withheld; a recipe
  estimate is withheld. Adding either is a new schema version.
- **C3. Decided 9 November 2026: yes.** The importer checks every national composition estimate
  against the bundled corpus through the narrow `recordNutrients` lookup (section 4.3) and rejects
  the import on a corpus mismatch, missing record, unquantified value or value difference (exact at
  zero, otherwise at most 0.5 per cent).
- **C4. Decided 9 November 2026: yes.** The daily export carries origin `approved_estimate`, state
  `estimated`, the structured provenance fields and the manifest URL under the food daily export contract's D4 URL rule, and no
  free text: source state, assumed state and assumption stay in the app's details and the archive
  (section 7).
- **C5. Decided 9 November 2026: yes.** The format accepts `page_access: indexed_copy` for the page
  source types, and the app shows "Page not read directly" for those values. This carries out E3
  disposition D3, under which R2 admits them; a later direct read changes data, not the schema.
- **C6. Decided 9 November 2026: yes.** On its own key, an approved estimate takes precedence over
  the merged generic record: label value, then estimate, then merged generic (section 4.1). The
  fresh-whole order is unchanged, and an estimate citing the entry's own generic reference is still
  refused.
