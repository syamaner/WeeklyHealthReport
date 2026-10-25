# Food daily export contract v1 (#287)

Status: **owner-approved 23 October 2026** (decisions D1 to D3, recorded inline, and the egress amendment; the privacy policy wording lands with the implementation). Architecture gate: passed on re-review 23 October 2026, with its corrections folded in.

## Purpose

Export the app's own food log as a separate daily JSON file, next to the existing Daily JSON health export, in the same Google Drive account and folder. The health export stays HealthKit-and-notes only: its schemas, bytes and the Drive rule rejecting `today.food_log` / `today.food_nutrition_summary` at every admitted version are unchanged.

The file carries macros and micronutrients (all 39 keys in `NutrientKey`, catalogue version 1) at two levels: per log entry, with provenance and value state, and as a daily summary. Most micronutrients will be unknown or partial on most days until nutrition augmentation lands; this is expected and stated in the file rather than hidden.

## Architecture gate

- **Domain** (`FoodLedgerDomain`): one additive change. `FoodIntakeSummary` becomes `food-intake-summary-v4`, adding `overflowed: Bool` (default `false` in the public initialiser, so existing call sites compile unchanged) to each `FoodIntakeTotal` so an arithmetic overflow is distinguishable from a day where nothing is known. On overflow, `knownAmount` stays `nil` and every contribution still counts as incomplete, exactly as in v3; only the flag is new. Home and Health keep their current display. The implementation updates the two tests that pin `food-intake-summary-v3` (`PastedLabelDomainTests`, `FoodIntakeScalingPredicateTests`) and the v3 references in `FoodLogPeriodSummary.swift` and `health-food-and-water-v1.md`.
- **Application** (`FoodLedgerApplication`): a new pure `FoodDailyExportBuilder` projects one reporting date from a ledger snapshot into a `FoodDailyExportDocument` (export DTOs, not domain types). It reuses `FoodIntakeProjection` for head-version selection, `FoodIntakeSummary` (`food-intake-summary-v4`) for totals and `PlainWaterDayTotal.total` for plain water, so Home, the Health food section and the export cannot disagree. Clock, time zone and snapshot are injected. No Foundation date formatting policy lives in the domain.
- **Serialisation:** a dedicated `FoodDailyExportSerializer` in the application layer, separate from `FoundationCanonicalJSONEncoder` and from `DailyHealthExportSerializer`, so neither existing byte form can drift.
- **Infrastructure / app target:** a new `DailyFoodExportIdentityPolicy` conforming to `DrivePayloadIdentityPolicy`, a second `DailyDriveExportCoordinator` instance and its own identity registry. FoodLedgerKit boundary rules forbid Drive imports, so the adapter lives in the app target. `DriveExportKit` needs no change because the food registry also has its own installation marker (see File identity). `check-boundaries.sh` needs no new rule; nothing currently forbids `DriveExportKit` from importing FoodLedgerKit, and this contract does not add such an import.
- **Presentation:** the Export screen gains the food file (see UI). Developer tools gain an exact-bytes view.
- **Invariants (closed):** read-only HealthKit; food records append-only; unknown never zero; known minimums labelled; no medical interpretation; one canonical file per local date per document type; verified only after exact-byte readback.
- **Extension axis:** a later document type (for example a HealthKit food-write projection under #97) adds another identity policy and registry, not a change to the coordinator.
- **Contract tests:** listed under Tests.

## File identity

- Name: `food-daily-YYYY-MM-DD.json`, where the date is the reporting date.
- `food_daily_schema_version: 1`. This is its own version line; it is not a health-export schema number, and health schema 4 (the in-envelope projection) remains a test-only projection that this contract does not revive.
- Drive `appProperties`: `whrDailyFood` = `v1` (owner key, distinct from the health file's `whrDailyCanonical`), `whrDataAsOf` (ordering token), plus the package-fixed `whrReportDate`, `whrInstallationID`, `whrPayloadSHA256`.
- Ordering token: `food-v1|<data_as_of>|<exported_at>` for every day, today included. A past day's `data_as_of` is fixed at the next local midnight, so the cutoff alone would reject every corrected re-export as stale (equal token, different bytes). Adding `exported_at` lets a later preview of the same day replace the earlier file, matching the health policy's `historical-v2` rule. As in the health policy, `validate` and the token parser reject a payload whose `exported_at` is earlier than its `data_as_of`. The food policy's `compare` parses its own millisecond ISO 8601 format; it does not reuse the health parser, which reads `data_as_of` without fractional seconds.
- Identity registry and installation marker: separate Keychain keys, `google.drive.daily-food-export-identities.v1` and `google.drive.daily-food-export-installation.v1`. The existing registry has no document-type dimension, so a shared one would collide by date. The marker is also separate: `DriveExportCoordinator` throws `identityRecoveryAmbiguous` when a registry is missing while its marker exists, and rejects a new registry whose installation ID differs from the marker, so a shared marker would make the first food export fail after any health export. Each registry recovers independently through the existing Picker path.
- Destination lifecycle: on every path the food registry does exactly what the health registry does. Forgetting a trashed or missing folder abandons both registries' identities for that destination (`DailyDriveSessionController` currently abandons only the health coordinator; the implementation extends it). Disconnect keeps both registries and destinations, as it does for health today.
- Missing or trashed file override: the file replacement candidate gains a document type (health or food), so confirming a replacement abandons only that file's identity; a missing food file never abandons the health identity for the same date, and the reverse.
- Destination bindings and the OAuth session are reused as they are; `drive.file` stays the only scope.

## Day rules

Same window as the Daily JSON export: today, or one of the previous seven complete local days (`DailyExportWindow.availableDays`).

- An entry belongs to the day when its current head `LogItemVersion.reportingDate` equals the selected date. This is the ledger's own reporting day (the one Home and Food log use), not a recomputation from `occurred_at`.
- If `FoodIntakeProjection` or `PlainWaterDayTotal` throws (`competingVersions`, `unsupportedMixture`, `missingReference`, or any other error), **no food file is produced**: the food preview shows a blocked state naming the problem, Export does not send a food file, and the earlier Drive file is left untouched. A failure is never turned into an empty-day file.
- The ledger snapshot is captured once at refresh. Today's file contains the ledger as it was at the frozen cutoff; past days use the same snapshot capture. Changing the day clears the preview.
- `time_zone` is the frozen reporting time zone of the export. Log entries do not store a time zone, so `occurred_at` is rendered with that zone's offset. The file states this; it does not claim the zone in force when the food was logged.

## Content

Top level, in this order of meaning (keys are sorted in the bytes):

| Field | Meaning |
|---|---|
| `food_daily_schema_version` | `1` |
| `report_date` | `YYYY-MM-DD` |
| `time_zone` | IANA identifier frozen at refresh |
| `data_as_of` | frozen cutoff; for a past day, the next local midnight |
| `exported_at` | preview preparation time |
| `nutrient_catalogue_version` | `1` |
| `summary_version` | `food-intake-summary-v6` (v6 from #307: `includes_estimates` also covers source-backed quantity estimates, count portion guides and the whole-milk volume rule, see [count-portion-estimate-v1.md](count-portion-estimate-v1.md); v5 until #307; v4 until #304; v5 leaves plain water's exact zeros out of every total except water, see [health-food-and-water-v1.md](health-food-and-water-v1.md) decision 10) |
| `entries` | the day's log entries, in deterministic order |
| `summary` | the day's totals for all 39 nutrients |
| `plain_water` | plain-water total, separately from water inside foods |
| `app_context` | app version and build, as in the health export |

### Entries

One element per log item whose head version is on the day and not removed, sorted by `occurred_at`, then `log_item_id`.

- `log_item_id`, `head_version_id` (the current head of the log item, which for an omitted removed item would be the removal version), `occurred_at` (from the head's effective version), `display_name`, `item_class`, `quantity` (amount and unit as recorded, with `weight_basis`: declared, estimated, or unknown).
- `versions`: the complete version history of that log item, oldest first, each with `version_id`, `ordinal`, `supersedes_version_id`, `correction_reason` and `occurred_at`. Earlier versions are listed for audit but do not contribute to totals.
- `basis`: the resolution basis of the stored values (per 100 g, per 100 mL, per serving, per unit, named or unknown) and `scale_factor` used for this entry.
- `nutrients`: all 39 keys, **scaled to the quantity eaten** exactly as `FoodIntakeLogRow.totals` scales them (bounds scaled the same way; an unscalable value becomes `unknown` with reason `missing_conversion`). Each value is an explicit state object:
  - `{"state": "measured", "amount", "unit"}`
  - `{"state": "estimated", "amount", "unit"}` (domain `augmented`)
  - `{"state": "bounded", "lower", "upper", "unit", "origin"}`
  - `{"state": "unknown", "reason"}` with `not_declared`, `no_compatible_source`, `missing_conversion` or `conflicting_evidence`
  - a conflicting nutrient carries `conflict: true` and its candidate values; it is never resolved silently.
- Each known or bounded value carries `provenance` (`source_kind`, `source_release_id`, `transforms`) and `calculated` (true when `NutrientDerivation.isCalculated` holds for its transforms). Every value, including unknowns, carries `origin` from this closed rule; for unknowns only the pasted-label row yields a specific origin (`not_read` / `not_stated`), and other sources give the source row's origin alongside the unknown `reason`. A new source kind needs a contract revision; the builder fails closed on an unmapped kind.

| `ProvenanceSourceKind` | `origin` |
|---|---|
| `user_verified_panel` with a pasted-label evidence manifest | from `NutrientValueOrigin.project`: `printed`, `calculated`, `corrected_by_you`, `entered_by_you`, or `not_read` / `not_stated` for unknowns |
| `user_verified_panel` without a pasted-label manifest | `label_checked_by_you` |
| `manual_declaration` | `entered_by_you` |
| `exact_product_dataset` | `product_database` |
| `generic_composition_dataset` | `food_database` |
| `recipe_reconstruction` | `recipe` |
| `reviewed_web_proposal` | `web_review` |
| `app_reference_definition` | `app_reference` (plain water) |

- **Label photo entries ([label photo AI pre-fill v1](label-photo-ai-prefill-v1.md), #316): no field change.** Their values are `user_verified_panel` without a pasted-label manifest, so they export as `label_checked_by_you` (corrected or entered values as `entered_by_you`), with `source_release_id` `label-photo-ai:<manifest SHA-256>`. Photo-specific per-value origins are deferred to food export v2 (#312).

- The basis choice is reported once per entry, not per value: `basis_origin` is `chosen_by_you` when the entry's stored `PastedLabelEvidenceManifest.basisOrigin` records an assisted choice (manifest v2), otherwise absent. The ledger snapshot passed to the builder includes the pasted-label evidence manifests for the day's entries; `PastedLabelBasisChoice` is the in-review value and is not read.

Removed entries (head version is a removal) are **omitted** from `entries` and from totals: the file describes what the day's log says now, and the ledger keeps removal history locally. (D1, owner decision 23 October 2026.)

### Summary

For each of the 39 nutrients, from `FoodIntakeSummary` v5 (v4 before #304):

- `known_amount` (null when no contribution is known), `unit`
- `state`: `complete` (every contributing entry known), `known_minimum` (some contributions bounded, unknown or unscalable), `none_known`, or `unavailable` (v4 reports `overflowed`; no amount, never a clamped number)
- `incomplete_contributions` (count) and `includes_estimates` (bool)
- `log_item_version_ids`: the head versions whose values contributed a known amount (a plain water entry only for `water`, v5), computed by the builder (not part of `FoodIntakeTotal`) and checked by a parity test

No targets, reference values, percentages or interpretation.

**Versioning rule (24 October 2026, #304).** `summary_version` changes whenever the day-total semantics change (which contributions count, how they combine, what makes a total known or incomplete), even when the file shape stays the same. `food_daily_schema_version` changes only when the file shape changes (keys, value forms, byte form). A writer emits only the current `summary_version`; validators, including the Drive identity policy's reconcile and recovery reads, accept every published `summary_version` (currently `food-intake-summary-v4`, `food-intake-summary-v5` and `food-intake-summary-v6`), so files already on Drive stay valid. A file keeps the values it was written with; nothing rewrites an earlier file except a fresh export of that day. A frozen v4 golden (`docs/fixtures/food-daily-v1/food-daily-plain-water-only-summary-v4.json`) pins that a v4 file still decodes, re-encodes byte for byte and passes the policy. From #307 the v5 goldens are frozen the same way and a v6 golden pins a day with a count portion guide entry. Entry fields, including `weight_basis`, are unchanged by v6; entry-level estimate fields are #312.

### Plain water

`plain_water` reports `PlainWaterDayTotal.total` for entries backed by `PlainWaterReference` (`weeklyhealthreport.reference:plain-water-v1`) in mL, with the same `complete` / `known_minimum` state. The `water` nutrient in `summary` still includes water in foods; the two are labelled so they are not added together by a reader. `PlainWaterDayTotal` rejects competing heads more widely than `FoodIntakeProjection` (any item with a head on the day and more than one head on any date); the builder runs both checks, and either failure blocks the file.

### Empty day

A day with no entries still produces a file: `entries: []`, every nutrient `none_known`, plain water `none_known`. Empty is not zero. Exporting it replaces an earlier file for that day, for example after every entry was removed.

### Excluded

Raw attachments, receipts, pasted label text, OCR geometry, captured web page text and quotations, search queries, credentials, Keychain data, search indexes, drafts, favourites, inventory and transient diagnostics never enter this file.

For reviewed web proposals, `provenance` includes the public source URL and its content hash, which identify where a value came from and hold no personal data; nothing else from the proposal is exported. (D2, owner decision 23 October 2026.) The URL is exported as scheme, host, port and path only: its query string and fragment are dropped, so search words in a page address never leave (owner decision 24 October 2026).

## Byte form

- UTF-8 JSON, `sortedKeys`, `withoutEscapingSlashes`, snake_case keys written explicitly in the DTO coding keys (no automatic key conversion).
- Dates as ISO 8601 text with milliseconds and the frozen zone's offset (`yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX`).
- Tagged values are encoded as `state` / `kind` discriminators. Synthesized `_0` keys never appear.
- Amounts are the stored `Double` values written as JSON numbers in Foundation's shortest round-trip form; no rounding or unit conversion at the export boundary.
- Decoding and re-encoding a file reproduces it byte for byte; Drive admission requires this, as it does for the health file.

## Export screen

A single Export action with a **Food log** row (on when Drive is connected; the person can switch it off). Preview shows both files, each with its own size and preview. Export sends the health file first, then the food file; each is verified independently and shows its own result. A failure in one never marks the other as failed, retries only the failed file, and note cleanup stays bound to the health file's verification alone. (D3, owner decision 23 October 2026.)

Opening the screen never uploads. Health and food previews share one refresh, so both carry the same `data_as_of`.

## Developer tools

A **Food daily export** row shows, for the prepared preview: schema version, byte count, SHA-256, entry count and the exact JSON, plus the Drive record (file ID, last verified token) like the existing #217 rows. This makes the export reproducible on device.

## Egress amendment (owner-approved 23 October 2026)

`privacy-and-egress.md`: the "Stays on the device" food bullet now states that one selected day's food log leaves only inside this file, keeps the existing Full Page and Copy all statements, and replaces the closing #97 sentence.

Allowed egress table, Google Drive row: now also lists the exact reviewed food daily JSON bytes when Food log is on, and this contract. Applied in this docs change.

`privacy-policy.txt` is bundled in the app and served from `main`, so it changes **in the implementation PR**, when the feature ships (owner decision 23 October 2026). Approved wording:

- Effective date: the implementation PR's merge date.
- Sharing and Google Drive, after the sentence ending "send those exact bytes to your chosen Google Drive destination.": "With Food log on, the same Export also sends a separate food file for the selected day to that destination: the foods you logged, their amounts and times, nutrient values with their sources (for example a printed label, a food database or a web source page address) and the day's totals. It does not include pasted label text, receipts, photos, captured web page text or search queries."
- Local food records and notes: "they are separate from the HealthKit JSON export." becomes "they are separate from the HealthKit JSON export and from the daily food file."

`daily-export-contract.md`: one line now states that food leaves only through this separate file and the health envelope rule is unchanged. Applied in this docs change.

## Tests

- Pure builder tests (synthetic ledgers): day selection by reporting date, superseded and removed versions, every projection error producing no document, conflicts, every nutrient state, scaled per-entry values and bounds, plain water vs food water, empty day.
- Summary v4: an overflowed total keeps v3's `knownAmount` and `incompleteContributions` with `overflowed == true`; a day where nothing is known has `overflowed == false`.
- Origin rule: every `ProvenanceSourceKind` maps to its origin; an unmapped kind fails closed.
- Golden files under `docs/fixtures/food-daily-v1/`: a mixed day (printed, calculated, estimated, bounded, unknown, corrected), an empty day and a plain-water-only day. Byte-stable decode and re-encode.
- Summary parity: for the same snapshot, export totals equal `FoodIntakeSummary` used by Home and Health.
- Drive identity policy: filename, owner key, rejection of non-canonical bytes and of a health payload under the food policy (and the reverse); separate registry and marker with no collision on the same date.
- First food export succeeds after a health export has already created the health marker.
- A corrected past-day re-export is accepted; an older token is still stale. The food token parser accepts its millisecond format.
- A projection failure sends nothing and leaves the earlier Drive file unchanged.
- Forgetting a trashed folder clears both registries; disconnect keeps both.
- A missing-file override for food leaves the health identity for the same date untouched, and the reverse.
- The two registries keep distinct installation IDs; recovering a file of one type under the other policy is rejected.
- A food payload with `exported_at` earlier than `data_as_of` is rejected.
- `basis_origin` is `chosen_by_you` exactly when the stored manifest records an assisted choice.
- View-model tests: independent results per file, note cleanup bound only to health verification, Food log off sends nothing.
- Simulator UI test: Export with Food log on shows both previews and results.
- Privacy policy: the implementation PR applies the approved wording above and bumps the effective date.
- Device: the owner exports a day and compares the food file with the app's Food log and Developer tools. Simulator runs prove software behaviour only.

## Implementation decisions (owner, 24 October 2026)

Decided one at a time during review of the implementation PR; each confirms the shape the implementation already had, except D4, which changed the exported URL.

- **D4** Web source URLs drop their query string and fragment (see Excluded).
- **D5** A reviewed web value keeps `source_release_id` (`reviewed-web:<manifest SHA-256>`). It is an opaque hash that matches the value to its local review record, and it is not "something else from the proposal" under D2.
- **D6** An entry with no known value and no provenance anywhere blocks the day's food file (fail closed), like an unmapped source kind. No save route is known to create one.
- **D7** The file carries a top-level `notes` object of three fixed sentences: `occurred_at` rendering, unknown never zero with sparse micronutrients expected, and plain water already inside `summary.water`. Constant text only.
- **D8** Bounded values also carry `estimated` (an estimated bound) and `lower_closed` / `upper_closed`; `plain_water` carries `included_in_summary_water: true`.
- **D9** `weight_basis` maps the ledger's measured to `declared`, estimated to `estimated`, and no weight declaration (water in mL included) to `unknown`.
- **D10** `app_context` holds `app_version` and `app_build` from the app's Info.plist. The health export has no such fields, so "as in the health export" above means "in the same position", not the same keys.
- **D11** The bundled privacy policy's effective date is 24 October 2026, the intended merge date; bump it if the merge slips.

## Out of scope

Adding food to the health envelope, HealthKit food writes (#97), range or multi-day food files, background or automatic export, and any new nutrient keys (augmentation adds values through new ledger versions without changing this file's meaning).
