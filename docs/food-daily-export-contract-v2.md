# Food daily export contract v2 (#312)

Status: **implemented** (decided under owner delegation, 31 October 2026; readers in PR 2, #505; writer in PR 3, 16 November 2026). The app writes schema 2 and still reads schema 1. Open questions Q1 to Q8 (section 11) take the recommended answers under the owner's delegation. Architecture gate on 68f3f59a: PASS WITH CHANGES; findings F1 to F8 and the Q4 and Q7 clarifications are folded in below. Refreshed on 9 November 2026 for two changes merged after the draft, the label estimate layer ([label estimate merge v1](label-estimate-merge-v1.md), #383) and the Ciqual 2025 admission ([Ciqual 2025 admission v1](ciqual-2025-admission-v1.md), #384); neither changes the fields, codes or rules below (section 7). Readers accept schema 2 from PR 2 (section 10; the DTO, the shape rule, the Drive policy and hand-built fixtures under `docs/fixtures/food-daily-v2/`); the builder writes schema 2 from PR 3 and reproduces those fixtures byte for byte (contract test 10). Rechecked on 16 November 2026 before PR 2 against everything merged since the refresh, including the Open Food Facts label estimate (#464), the catalogue import and the web lookup retry (#500): no quantity method, estimate rule, nutrient state, source kind, summary version or export field changed. A label estimate layer can now also sit on an Open Food Facts entry; the section 7 rule reads the same for it, because a layer estimates nutrients and the amount projection is unchanged.

**Amendment, 16 November 2026 ([assistant-pasted estimates v1](assistant-pasted-estimates-v1-proposal.md) section 9, accepted, not implemented).** A later version 4 is defined as version 3's shape ([estimates on catalogue v2](personal-food-catalogue-estimates-v2-proposal.md), itself this contract's shape plus the estimate fields) plus origin `assistant_estimate`, `estimate_quality_basis` on `approved_estimate` values and one constant sentence in `notes`. It is written only for a document holding an assistant estimate or a lowered tier; every other document keeps its version and its bytes. Nothing in this contract's version 2 changes.

**Amendment, 17 November 2026 ([estimates on catalogue v2](personal-food-catalogue-estimates-v2-proposal.md) section 7, implemented in #511).** Version 3 is this contract's shape plus the estimate fields: origin `approved_estimate`, and on each such value's provenance `estimate_source_type`, `estimate_method`, `estimate_state_basis` and `estimate_quality` (closed lists; all four required), with `source_url` for a page estimate and `content_hash` only when a source artefact was kept. It is written only for a document holding at least one `approved_estimate` value; every other document stays version 2 with its bytes. The shape rule's row for 3 is the row for 2 plus: at least one such value, the four tokens on each, and no estimate field on any other value; a version 1 or 2 file carrying an estimate field is rejected. 2 and 3 replace each other for a date under the same ordering token. Goldens: [`fixtures/food-daily-v3/`](fixtures/food-daily-v3/). Nothing in this contract's version 2 changes.

**Amendment, 18 November 2026 ([label photo estimates v1](personal-food-catalogue-off-estimates-v1-proposal.md) section 4, implemented in #518).** Version 5 is version 3's shape plus the source type `product_dataset_photo`, and nothing else. It is written only for a document holding at least one label photo estimate; every other document is written as before, byte for byte. Each version keeps its own closed source-type list: version 3 rejects the token and version 5 requires at least one. A photo value carries the label photo address (query string and fragment dropped; it contains the product's barcode) and a 64-hex `content_hash`. Version 4 stays claimed by assistant-pasted estimates and is not built; a build with version 5 only rejects assistant fields, so it fails closed. A later phase needing both shapes takes a new number (6) and never widens a released version.

**Amendment, 21 November 2026 ([Confirm enrichment through OpenRouter v1](confirm-enrichment-openrouter-v1.md) CE1.7 and its [phase gate](confirm-enrichment-openrouter-v1-phase.md) section 2.8, #549).** Version 7 admits everything version 5 admits plus origin `openrouter_estimate`. On such a value's provenance: `source_release_id` is the constant `confirm-enrichment-openrouter`, `estimate_quality` is `low`, and three fields appear for this kind only, `estimate_model`, `estimate_contract` (`confirm-enrichment-openrouter-v1`) and `estimate_response_sha256`; `estimate_source_type`, `estimate_method`, `estimate_state_basis`, `source_url` and `content_hash` are absent. `notes` gains `openrouter_estimates`, one constant sentence. Version 7 is written only for a document holding at least one `openrouter_estimate` value; every other document is written as before, byte for byte. Versions 1, 2, 3 and 5 reject the origin, the three fields and the sentence; version 7 requires at least one such value and admits no assistant estimate field, so a build with version 7 only fails closed on one. No request text, response text or description is exported.

This contract amends [food daily export contract v1](food-daily-export-contract-v1.md) (#287). Everything v1 says stays in force unless a section below changes it. It closes the follow-up recorded in [count portion estimate v1](count-portion-estimate-v1.md) (C13 and section 9) and the export gap noted for the whole-milk volume rule in [CoFID whole-milk volume admission v1](cofid-whole-milk-volume-admission-v1.md).

## 1. Problem

In v1 an entry's `quantity` is the edible amount the ledger uses for nutrition (`LogItemVersion.edibleQuantity`) with `weight_basis` taken only from the weight declaration (decision D9):

- A count logged with a typical weight (`count_portion_guide_v1:*`) exports, for example, `{"amount": 132, "unit": "g", "weight_basis": "unknown"}`. The 132 g is an estimate (3 medium eggs at about 44 g each), but nothing at entry level says so, and the 3 pieces the person entered are not in the file at all.
- A whole-milk volume estimate exports `{"amount": 206, "unit": "g", "weight_basis": "unknown"}`. The 200 mL the person entered and the fact that 206 g is an estimate (1 mL taken as 1.03 g) are invisible.
- Kitchen scale and Package weight count conversions also export `weight_basis: "unknown"`, which reads the same as an estimate even though the grams were measured or read from a package.

The day `summary` already reflects quantity estimates through `includes_estimates` under `food-intake-summary-v6`, so a reader can see that a day total includes an estimate but cannot tell which entry caused it. Every nutrient value in such an entry is scaled from the estimated grams, including values whose `state` is `measured`.

## 2. Scope

In scope:

- One new entry-level object, `quantity.amount_method`, saying how the exported amount was obtained, whether it is an estimate, what the person entered and, for a source-backed estimate, which frozen rule and source release produced it.
- One new constant sentence in `notes`.
- `food_daily_schema_version: 2`, with v1 files remaining valid for every reader and validator.

Not in scope (unchanged from v1):

- Day totals and their semantics. `summary_version` stays `food-intake-summary-v6`; the summary shape is unchanged.
- Nutrient value objects, the closed origin rule, provenance, bounds, conflicts and `plain_water`.
- Photo-specific per-value origins for label photo entries (deferred to #312 by [label photo AI pre-fill v1](label-photo-ai-prefill-v1.md) 17.4; Q3, decided: a later version).
- The health Daily JSON envelope, its schemas and its rule rejecting food at every admitted version.
- Drive transport, identity, ordering tokens, registries and installation markers.
- Any new stored record, field, migration or archive contract. `amount_method` is derived at export time from records the ledger already stores.

## 3. What v2 adds

### 3.1 `quantity.amount_method`

Present on every entry in a v2 file, absent from every entry in a v1 file. Every key inside it is always written; a value that does not apply is an explicit `null`, never a missing key and never `0`.

| Field | Type | Meaning |
|---|---|---|
| `code` | string, closed set (3.2) | How the exported `quantity.amount` was obtained. The export spelling of the projection row's `quantityMethod` (`FoodIntakeLogRow.quantityMethod`, itself `FoodQuantityMethod.of(_:conversion:)`), the value the Food Log row and saved entry already show; the builder does not derive it a second time (F6). |
| `is_estimate` | bool | `FoodQuantityEstimate.isEstimate(_:conversion:)`, the one rule that also feeds `FoodIntakeContribution.quantityIsEstimate` and therefore the summary's `includes_estimates`. True for `typical_weight`, `whole_milk_volume` and `estimated_by_eye`; false otherwise. |
| `entered` | object or null | The amount the person entered when it differs from `quantity.amount` (a count, servings, or millilitres converted to grams): `{"amount", "unit"}` with `unit` from the closed set `g`, `mL`, `count`, `serving`. For a conversion it is the stored `QuantityConversionVersion.sourceQuantity`. For pasted-label and photo-label servings it is that `sourceQuantity` with unit `serving`, decided by `FoodAmountServings.isServings` over `FoodConfirmationService.lastEnteredAmount`, so the file says "2 servings" exactly where the Food Log row does (F1). For a weight declaration it is `EdibleWeightDeclaration.originalInput` **only when it differs from (`amount`, `unit`)**, otherwise `null` (F5). `null` when the exported amount is what the person entered, or when no original input was stored (unknown is not zero, and an absent original input is not the same as the exported amount). |
| `source` | object or null | Only for a source-backed estimate (`typical_weight`, `whole_milk_volume`): `{"method_version", "source_release_id", "size"}`. `method_version` and `source_release_id` are the stored conversion values, which the closed estimate table already validates as a pair (count portion estimate v1, C6). `size` is `small`, `medium`, `large` or `extra_large` for a typical weight (from the frozen `CountPortionGuideCode` table) and `null` for whole milk. `null` for every other code. |

### 3.2 Closed `code` set

| `code` | Stored records | `is_estimate` | `entered` | `source` |
|---|---|---|---|---|
| `direct` | No weight declaration and no conversion | false | `null` | `null` |
| `direct` | A pasted-label or photo-label servings conversion (`LabelServingPolicy`) | false | `sourceQuantity` with unit `serving` (F1) | `null` |
| `weighed` | Weight declaration, basis measured (shown as Kitchen scale on a direct weight, #318) | false | `originalInput` when it differs from (`amount`, `unit`), else `null` | `null` |
| `estimated_by_eye` | Weight declaration, basis estimated | true | `originalInput` when it differs from (`amount`, `unit`), else `null` | `null` |
| `kitchen_scale` | Conversion `user_count_conversion_v1:kitchen_scale` | false | `sourceQuantity` | `null` |
| `package_weight` | Conversion `user_count_conversion_v1:package_weight` | false | `sourceQuantity` | `null` |
| `typical_weight` | Conversion with a `count_portion_guide_v1:*` code and a `usda-sr-legacy-portions:` release | true | `sourceQuantity` (count) | method version, release, size |
| `whole_milk_volume` | Conversion `cofid-whole-pasteurised-milk-volume-v1` with a `phe-npm-2018:` release | true | `sourceQuantity` (mL) | method version, release, `size: null` |
| `recorded` | Any other conversion (typed legacy method text written before the closed method set) | false | `sourceQuantity` | `null` |

The table is closed and enforced row by row by the shape rule (section 5, F2): `code` is in the set; `is_estimate` equals the table value for that code; `source` is non-null if and only if `code` is `typical_weight` or `whole_milk_volume`; `source.size` is `null` if and only if `code` is `whole_milk_volume`; `entered.unit` is in {`g`, `mL`, `count`, `serving`}; `source.size` for a typical weight is in {`small`, `medium`, `large`, `extra_large`}.

`recorded` exports the code only, never the typed method text (Q2, decided). Typed text is never an estimate without the matching release, as count portion estimate v1 invariant 4 already requires; a reader must treat `recorded` as "method not described", not as measured.

The plate path (Total minus empty plate) stores a measured weight declaration and exports as `weighed`, as the Food Log shows it today. Distinguishing it is an extension (section 9).

### 3.3 `weight_basis` keeps its v1 meaning

`quantity.weight_basis` stays exactly as D9 defines it (`declared`, `estimated`, `unknown` from the weight declaration alone), so a reader that already branches on it reads every v2 file the same way. It is superseded for new readers by `amount_method`, and a typical-weight entry still reports `weight_basis: "unknown"` in v2. Redefining it would silently change the meaning of a v1 key (Q1, decided: keep it).

### 3.4 `notes.quantity_estimates`

`notes` gains a fourth constant sentence under the key `quantity_estimates`:

> quantity.amount_method.is_estimate marks an amount that was estimated (a typical weight, the whole-milk volume rule or an estimate by eye). Every nutrient value in that entry is scaled from the estimated amount, including values whose state is measured. is_estimate false means no estimate rule was recorded for the amount, not that the amount was measured. The code recorded means the method is not described.

Constant text only, as D7 requires. The last two sentences (F7) stop a reader from treating `false` or `recorded` as proof of a measurement.

## 4. Labelling vocabulary (v2, complete)

A reader should use this table rather than inferring meaning from absent keys.

| What | Where | v1 | v2 |
|---|---|---|---|
| Quantity is an estimate | entry `quantity.amount_method.is_estimate` | not stated at entry level | `true` / `false` |
| How the quantity was obtained | entry `quantity.amount_method.code` | `weight_basis` only, declaration-based | closed code (3.2) |
| What the person entered | entry `quantity.amount_method.entered` | not exported | object or `null` |
| Nutrient value from a measured source | value `state: "measured"` | unchanged | unchanged; still scaled from an estimated quantity when `is_estimate` is true |
| Nutrient value that is itself an estimate | value `state: "estimated"` (domain `augmented`) | unchanged | unchanged |
| Bound | value `state: "bounded"` with `lower`, `upper`, closedness and `estimated` | unchanged | unchanged |
| Calculated value (label conversions) | value `calculated: true` | unchanged | unchanged |
| Unknown | value `state: "unknown"` with `reason` | unchanged | unchanged |
| Day total known only in part | total `state: "known_minimum"` | unchanged | unchanged |
| Day total overflowed | total `state: "unavailable"`, `known_amount: null` | unchanged | unchanged |
| Day total includes any estimate | total `includes_estimates` | v6 rule | unchanged v6 rule |

An entry "includes estimates" for a reader exactly when `is_estimate` is true, or any of its values has `state: "estimated"`, `calculated: true`, or `state: "bounded"` with `estimated: true`. The file does not add a separate entry-level flag for this, so there is one rule and no second copy to drift.

## 5. Versioning and compatibility

- **Schema line.** `food_daily_schema_version` becomes `2` because the file shape changes (a new key inside `quantity` and inside `notes`). Under the v1 versioning rule (24 October 2026, #304) `summary_version` changes only when day-total semantics change, which v2 does not do, so it stays `food-intake-summary-v6`.
- **Writers.** From the writer PR (section 10, PR 3) the app emits only schema 2. Nothing rewrites a file already on Drive except a fresh, reviewed export of that day, which can only happen inside the existing seven-day selection window. Older days keep their v1 files indefinitely, and those files keep the meaning they were written with.
- **Validators.** `DailyFoodExportIdentityPolicy.validate`, including reconcile and recovery reads, accepts schema 1 and schema 2, each with its own admitted summary versions:

  | `food_daily_schema_version` | Accepted `summary_version` | `amount_method` | `notes.quantity_estimates` |
  |---|---|---|---|
  | 1 | v4, v5, v6 | absent from every entry | absent |
  | 2 | v6 | present on every entry | present |

  A mixed file (a v1 file carrying `amount_method`, or a v2 file missing it on any entry) is rejected, as is any other schema number. For schema 2 the shape rule also enforces the closed table in 3.2 row by row (F2). Byte-for-byte decode and re-encode stays a requirement for both versions. PR 2 replaces the policy's flat `acceptedSummaryVersions` set with this per-schema map, so schema 2 accepts v6 only (F8).
- **Drive identity.** Unchanged. The file name stays `food-daily-YYYY-MM-DD.json`; the ordering token stays `food-v1|<data_as_of>|<exported_at>` (it names the ordering format, not the schema); the owner property value stays the package-fixed `v1`; registries and markers are unchanged. A schema-2 file for a date replaces that date's verified schema-1 file under the same persisted Drive file ID, as health schema evolution does. Stale-cutoff rejection and exact-byte readback are not relaxed.
- **Downgrade.** A build that predates v2 rejects a schema-2 file in `validate` (its check is `foodDailySchemaVersion == 1`), so it fails closed during reconcile or recovery rather than overwriting it. Do not downgrade for replacement or recovery of a day already exported as v2. A reader-only build is different: it verifies a schema-2 file and, because replacement is ordered by the token alone, a later export of that day from it replaces the schema-2 file with a schema-1 file under the same Drive file ID, which drops `amount_method` for that day. No guard is added, so the Drive ordering stays unchanged; the owner accepted this on 16 November 2026. Restated with the writer (PR 3): `main` writes schema 2 from PR 3 on, so the only reader-only builds are ones cut from `main` between PR 2 (f1686b9) and PR 3. The rule is that no such build is released: PR 2 and PR 3 ship in the same build. If one ever reaches a device, do not export from it a day already exported as schema 2.
- **Readers (Cowork and others).** Branch on `food_daily_schema_version`. In a v1 file the absence of `amount_method` means "not stated", never "not an estimate"; the day's `includes_estimates` remains the only estimate signal there.
- **Goldens.** Every existing file under `docs/fixtures/food-daily-v1/` is frozen and must still decode, re-encode byte for byte and pass the policy. v2 goldens live under `docs/fixtures/food-daily-v2/`.

## 6. JSON shape and synthetic examples

All identifiers, times and values below are synthetic. Excerpts show one nutrient per entry; a real entry lists all 39 keys in catalogue order. Keys are sorted in the bytes, as in v1.

### 6.1 Typical weight (3 medium boiled eggs)

```json
{
  "basis": {"kind": "per_100_g"},
  "display_name": "Eggs, chicken, whole, boiled",
  "head_version_id": "00000000-0000-0000-0000-000000001393",
  "item_class": "food",
  "log_item_id": "00000000-0000-0000-0000-000000001392",
  "nutrients": [
    {"amount": 188.76000000000002, "calculated": false, "key": "energy_consumed", "origin": "food_database",
     "provenance": [{"source_kind": "generic_composition_dataset", "source_release_id": "cofid:2021:sha256:436e9445ef2adb2a75f3d7edd51302de3adad25385f9795fc94ba58bd030e97d", "transforms": []}],
     "state": "estimated", "unit": "kcal"}
  ],
  "occurred_at": "2023-11-14T22:13:20.000Z",
  "quantity": {
    "amount": 132,
    "amount_method": {
      "code": "typical_weight",
      "entered": {"amount": 3, "unit": "count"},
      "is_estimate": true,
      "source": {
        "method_version": "count_portion_guide_v1:usda_sr_legacy_boiled_from_171287_88378",
        "size": "medium",
        "source_release_id": "usda-sr-legacy-portions:2018-04-01:sha256:0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef"
      }
    },
    "unit": "g",
    "weight_basis": "unknown"
  },
  "scale_factor": 1.32,
  "versions": [{"occurred_at": "2023-11-14T22:13:20.000Z", "ordinal": 1, "version_id": "00000000-0000-0000-0000-000000001393"}]
}
```

### 6.2 Whole-milk volume estimate (200 mL)

```json
"quantity": {
  "amount": 206,
  "amount_method": {
    "code": "whole_milk_volume",
    "entered": {"amount": 200, "unit": "mL"},
    "is_estimate": true,
    "source": {
      "method_version": "cofid-whole-pasteurised-milk-volume-v1",
      "size": null,
      "source_release_id": "phe-npm-2018:sha256:0abf60c447ac94a075e4d2a8065061e64e8d2fd8278959b3fc284ee858510e1b"
    }
  },
  "unit": "g",
  "weight_basis": "unknown"
}
```

### 6.3 Other codes (quantity objects only)

```json
{"amount": 150, "amount_method": {"code": "direct", "entered": null, "is_estimate": false, "source": null}, "unit": "g", "weight_basis": "unknown"}
{"amount": 140, "amount_method": {"code": "estimated_by_eye", "entered": {"amount": 3, "unit": "count"}, "is_estimate": true, "source": null}, "unit": "g", "weight_basis": "estimated"}
{"amount": 120, "amount_method": {"code": "kitchen_scale", "entered": {"amount": 2, "unit": "count"}, "is_estimate": false, "source": null}, "unit": "g", "weight_basis": "unknown"}
{"amount": 170, "amount_method": {"code": "weighed", "entered": null, "is_estimate": false, "source": null}, "unit": "g", "weight_basis": "declared"}
{"amount": 250, "amount_method": {"code": "direct", "entered": null, "is_estimate": false, "source": null}, "unit": "mL", "weight_basis": "unknown"}
{"amount": 60, "amount_method": {"code": "direct", "entered": {"amount": 2, "unit": "serving"}, "is_estimate": false, "source": null}, "unit": "g", "weight_basis": "unknown"}
```

The mL line is a plain water entry: direct millilitres, not an estimate, and unchanged in `plain_water`. The last line is 2 servings of a pasted or photographed label whose serving is 30 g (F1).

### 6.4 Top level

```json
{
  "app_context": {"app_build": "30", "app_version": "0.3.1"},
  "data_as_of": "2023-11-15T00:00:00.000Z",
  "entries": ["..."],
  "exported_at": "2023-11-15T07:30:00.000Z",
  "food_daily_schema_version": 2,
  "notes": {
    "occurred_at": "…unchanged…",
    "plain_water": "…unchanged…",
    "quantity_estimates": "quantity.amount_method.is_estimate marks an amount that was estimated (a typical weight, the whole-milk volume rule or an estimate by eye). Every nutrient value in that entry is scaled from the estimated amount, including values whose state is measured. is_estimate false means no estimate rule was recorded for the amount, not that the amount was measured. The code recorded means the method is not described.",
    "unknown_values": "…unchanged…"
  },
  "nutrient_catalogue_version": 1,
  "plain_water": {"included_in_summary_water": true, "incomplete_contributions": 0, "known_amount": null, "state": "none_known", "unit": "mL"},
  "report_date": "2023-11-14",
  "summary": ["…39 totals, unchanged shape…"],
  "summary_version": "food-intake-summary-v6",
  "time_zone": "UTC"
}
```

The `"..."` and `…unchanged…` placeholders mark elisions in this document only; goldens carry the full content.

## 7. Edge cases

- **Unknown is never zero.** `entered` is `null` when nothing was entered separately or no original input was stored; it is never `{"amount": 0}`. `source.size` is `null` for whole milk, not an empty string. No new field defaults to a number.
- **Estimated quantity with unknown nutrients.** An estimated quantity does not make any nutrient known. Unknown values stay `unknown` with their v1 `reason`, and `missing_conversion` still covers an unscalable entry.
- **Water.** Plain water entries are `direct` in mL and never estimates; `plain_water` and its `included_in_summary_water: true` are unchanged. The milk volume estimate converts millilitres to grams for the milk's own nutrients (including its `water` nutrient); it is not plain water and never enters `plain_water`.
- **Partial totals.** Unchanged: a total with any bounded, unknown or unscalable contribution is `known_minimum`. `is_estimate` does not change `state`; it is visible next to the amount it qualifies.
- **`includes_estimates` on a total with nothing known.** Under v6 an estimated-quantity contribution sets `includes_estimates` for every nutrient key it can be scaled for, including keys whose value is unknown. The current typical-weight golden shows `water` with `state: "none_known"` and `includes_estimates: true`. v2 does not change this (Q4, decided: left as v6; the fix is tracked separately in #344), and contract test 4 pins the current behaviour explicitly so a later change is deliberate; the entry-level `is_estimate` now lets a reader see which entry set it.
- **Overflow.** Unchanged. `entered` and the exported amount are stored `PositiveQuantity` values and are finite by construction; a nutrient that overflows when scaled is still `unknown` with `missing_conversion`, and an overflowed total is still `unavailable`.
- **Corrected values.** `amount_method` describes the head version only, the one that contributes. If a typical-weight entry was corrected to Kitchen scale, the head exports `kitchen_scale` with `is_estimate: false`, and `versions` still lists the history for audit without per-version methods (Q6, decided). A changed egg size is a new conversion version and exports the new size.
- **Conversion mismatch.** The conversion is used only when its ID equals the head's `quantityConversionVersionID`, as `FoodQuantityEstimate.isEstimate` already checks. If a contributing head version (one on the day and not removed; superseded and removed versions are not checked) references a conversion that is not in the snapshot, the builder throws `missingReference` and no food file is produced (fail closed, like D6; Q7, decided). Home and Health would still show the day, treating the missing conversion as "not an estimate"; that divergence is accepted because the state is unreachable from stored data (the conversion reference is a foreign key and the store runs `foreign_key_check`). If it ever occurs, correcting or removing the entry recovers the day's file.
- **Half counts.** A typical weight on 0.5 pieces (half-item count v1) exports `entered: {"amount": 0.5, "unit": "count"}` and the guide grams for half an egg.
- **Label estimate layer (#383).** A pasted-label or photo-label entry whose saved version carries a label estimate layer (shown as "Partly estimated") exports its amount exactly as the same entry without a layer: the same `code` from section 3.2 (for a label entry usually `direct`, with `entered` in servings when servings were entered, F1) and the same `is_estimate`. `amount_method` describes how the amount was obtained, and a layer estimates nutrients, not the amount; `FoodQuantityEstimate.isEstimate` reads only the weight declaration and the conversion, and `FoodEntryEstimateStatus.isEstimate` keeps its meaning under #383. Each layer-estimated nutrient already carries its v1 `estimated` state and the day totals' `includes_estimates` already marks it, so a reader can see which values are estimated. v2 adds no entry-level "partly estimated" marker; that is an extension (section 9).
- **Ciqual 2025 generic rows (#384).** No new code or field. The amount of an entry saved from a Ciqual row is spelt by the same closed `code` set as any generic row, and its nutrient source travels as v1 already defines (`source_kind` and the stored `source_release_id`). `source.source_release_id` inside `amount_method` names only the release behind a source-backed amount estimate (USDA portions for `typical_weight`, PHE NPM 2018 for `whole_milk_volume`), never the nutrient source, so a Ciqual release never appears there.
- **States the closed table has no row for (PR 3 gate).** None is reachable from a save route, and each produces no file rather than an improvised row: a label servings conversion whose entered amount is not a count; a source-backed estimate read without its conversion or its source release; and any document the builder's own shape check rejects (for example a method and an estimate rule that disagree, which no record can hold because a weight declaration and a conversion cannot be stored together). The day's food file is blocked with its own line ("An entry on this day has an amount this file cannot describe yet, so no food file was prepared."; the builder reports `unsupportedAmount`), so the block points at an entry's amount instead of the general "could not be read" line. Like the other block lines it does not name the entry; correcting or removing the entry recovers the day. The missing conversion (Q7) keeps its own line.
- **Servings without a conversion (open for the owner).** A count with no conversion exports as 3.2 row 1 gives it: `direct`, `entered: null`, with `quantity.unit` `count`, as v1 already wrote it. That includes servings entered on a per-serving or named basis and on a label whose serving has no weight, where the Food Log row says "servings" (`FoodAmountServings.isServings`). So the file says `2 count` where the Food Log says "2 servings"; the `serving` unit of 3.1 (F1) is written only for a label servings conversion, where a `sourceQuantity` exists. The same holds for a weight declaration whose original input is a count. Nothing numeric differs. Stating the servings noun for these entries would need a rule the closed table does not have, so it is left for a contract revision.
- **Removed entries.** Still omitted (D1).
- **Empty day.** `entries: []`; `notes` carries the new sentence; nothing else changes.

## 8. Egress impact

**No new destination, no new trigger and no new transport.** The food file still goes only to the user's existing Google Drive destination under `drive.file`, only when the user chooses Export with Food log on, as exact reviewed bytes verified by readback. DriveExportKit, OAuth, registries and the health file are unchanged.

The file's content gains, per entry, a closed method code, an estimate flag, the amount the person entered and, for the two source-backed estimates, the frozen rule code and its public source release identifier. All of this is derived from the same local records that already produce the exported amount; no attachment, typed method text, photo, label text or search text is added. The approved privacy-policy sentence already says the file contains "the foods you logged, their amounts and times", so this contract proposes no privacy-policy wording change; the owner confirms that reading (Q5, decided). The Google Drive row in [privacy-and-egress.md](privacy-and-egress.md) gains a link to this contract in the writer PR, with no change to what it permits.

## 9. Architecture gate (proposed)

### Responsibilities

| Layer | Change |
|---|---|
| Domain (`FoodLedgerDomain`) | None. No record, field, version or summary change. `FoodIntakeSummary` stays `food-intake-summary-v6`. |
| Application (`FoodLedgerApplication`) | `FoodDailyExportDocument.schemaVersion` becomes 2. New DTO `FoodDailyExportAmountMethod` (`code`, `is_estimate`, `entered`, `source`) with explicit-null encoding, as an optional `amountMethod` on `FoodDailyExportQuantity` encoded only when present. `FoodDailyExportNotes` gains an optional `quantityEstimates`. `FoodDailyExportBuilder` derives the object from `FoodQuantityMethod.of(_:conversion:)`, `FoodQuantityEstimate.isEstimate(_:conversion:)` and `CountPortionGuideCode.entry`, using the same conversion lookup as `FoodIntakeProjection`, and throws `missingReference` for a referenced conversion that is missing. `code` comes from the projection row's `quantityMethod` and `entered` from `FoodConfirmationService.lastEnteredAmount` with `FoodAmountServings.isServings` (F1, F6); the conversion lookup is used only for `source` and the Q7 existence check. A pure `FoodDailyExportShape.validate(_:)` holds the per-version presence and summary-version map in section 5 and the row-by-row closed table in 3.2 (F2), so the Drive policy and the tests share one rule. |
| Infrastructure / app target | `DailyFoodExportIdentityPolicy.validate` calls the shared shape rule instead of `schemaVersion == 1` plus its flat `acceptedSummaryVersions` set, which is removed (F8). `DailyFoodExportService` is unchanged apart from mapping the existing `missingReference` block and, for an amount the closed table has no row for (section 7), the builder's `unsupportedAmount` to its own block line. Ordering, registries and markers are unchanged. |
| Presentation | None required. Developer tools already shows the schema version and exact bytes of the prepared preview. |

### Dependency direction

Unchanged. The builder reads domain records and application projections (`FoodQuantityMethod`, `FoodQuantityEstimate`, `CountPortionGuideCode`) that already live in `FoodLedgerApplication`; the app target depends on the package; nothing in FoodLedgerKit imports Drive, GRDB, SwiftUI or Foundation date policy beyond the existing timestamp type. `check-boundaries.sh` needs no new rule.

### Invariants (closed)

1. One estimate rule: an entry's `is_estimate` equals the `quantityIsEstimate` of its summary contribution for the same snapshot (parity test).
2. One method projection: `code` is the export spelling of `FoodQuantityMethod`, the projection the Food Log row and saved entry use; `is_estimate` equals `FoodQuantityMethod.isEstimate` for every code.
3. Unknown is never zero; no new field defaults to a number; `null` is explicit.
4. v1 files keep their bytes, meaning and validity; v1 goldens are frozen.
5. Typed method text never leaves the device and never makes a quantity an estimate.
6. The health envelope, Drive identity, ordering and egress destination are unchanged.
7. Records are append-only and nothing new is stored; `amount_method` is derived at export time.

### Extension axes (open)

- A new quantity method joins `FoodQuantityMethod` (and, if it is an estimate, the closed `FoodQuantityEstimate` table) plus one row in the closed `code` set, through a contract revision. The builder fails closed on a method it cannot spell.
- A new source-backed estimate adds its `source` fields through the same table.
- Plate-path detail, photo-specific origins and per-version methods are later schema versions, each with its own goldens.
- An entry-level marker for a label estimate layer (#383's "Partly estimated", `FoodEntryEstimateStatus.showsPartlyEstimated`) would be a later schema version with its own goldens; v2 leaves per-value `estimated` states as the only export signal for layer estimates.

### Contract tests to add

The gate's amended list (12 tests).

1. Code mapping: every `FoodQuantityMethod` case maps to exactly one `code`; `is_estimate` matches `FoodQuantityMethod.isEstimate` and `FoodQuantityEstimate.isEstimate`; the builder's `code` equals the projection row's `quantityMethod` (F6).
2. Builder, one synthetic entry per row of the 3.2 table: typical weight (each size, raw and boiled, and 0.5 pieces), whole milk, estimated by eye with an original input that differs and with one equal to (`amount`, `unit`) (exports `null`, F5) and without one, weighed, kitchen scale, package weight, direct grams, direct mL, plain water, pasted-label servings and photo-label servings (both `entered.unit` `serving`, matching the Food Log row, F1), and a legacy typed method exporting `recorded` without its text.
3. Guide code without the matching release prefix exports `recorded` and `is_estimate: false` (gate F6 of count portion estimate v1).
4. Parity: for a mixed snapshot, each entry's `is_estimate` equals its contribution's `quantityIsEstimate`. The v6 quirk is pinned explicitly: an estimated-quantity entry with an unknown `water` value gives `water` `state: "none_known"` with `includes_estimates: true` (Q4, #344).
5. Q7: a synthetic `LedgerMutation` whose contributing head references a missing conversion produces no document (`missingReference`) and the service maps it to the existing blocked state; a superseded or removed version with a missing conversion does not block.
6. Corrected entry: typical weight then kitchen scale exports the head's method only.
7. Shape rule, one rejection per rule: schema 1 with any `amount_method` or `quantity_estimates`; schema 2 missing either; schema 2 with summary v4 or v5; an unknown schema number; and for schema 2 (F2) a code outside the set, `is_estimate` differing from the table, `source` present for another code, `source` missing for `typical_weight` or `whole_milk_volume`, `size` null for a typical weight, `size` non-null for whole milk, an `entered.unit` outside the set, and a `size` outside the set.
8. Frozen v1 goldens: every file under `docs/fixtures/food-daily-v1/` is decode, re-encode and validate only (never rewritten by the recorder) and still passes byte for byte; the typical-weight v2 golden asserts `amount_method` while `weight_basis` stays `unknown` (F4).
9. v2 goldens under `docs/fixtures/food-daily-v2/` (mixed day with every code, typical-weight day, milk day, empty day, plain-water-only day) are byte-stable and pass the policy; `RECORD_FOOD_DAILY_GOLDENS` writes only this folder (F4).
10. PR 2's hand-built v2 fixtures equal the PR 3 builder output byte for byte (F3).
11. Drive policy: a schema-2 file replaces a schema-1 file for the same date under the same file ID; token ordering is unchanged; the per-schema summary map replaces the flat set (F8).
12. Explicit nulls: `entered`, `source` and `source.size` are written as `null`, never omitted, in a v2 file.

## 10. Implementation plan

Small PRs, each green on its own gates, in this order. None needs a HealthKit device check; the owner's device check is a comparison of the exported file with the Food Log.

1. **PR 1, this contract (docs only).** Draft, owner decisions on section 11, then the `architecture-gate` review, folded in before any code.
2. **PR 2, readers accept v2 (no writer change).** `FoodDailyExportAmountMethod` and the optional fields, the pure shape rule, the Drive policy switched to it, hand-built synthetic v2 fixtures, the per-schema summary map replacing `acceptedSummaryVersions` (F8), contract tests 7, 8, 11 and 12. The app still writes v1, so a build from this PR can already verify, reconcile and recover v2 files. Gates: FoodLedgerKit tests, boundary check, app tests, analyze, `git diff --check`.
3. **PR 3, writer emits v2.** Builder derivation, the notes sentence, `missingReference` for a missing conversion, the recorder limited to `docs/fixtures/food-daily-v2/` (F4), the generated v2 goldens asserted equal byte for byte to PR 2's hand-built fixtures (F3), contract tests 1 to 6, 9 and 10, the privacy-and-egress link, a forward pointer in the v1 contract, this contract's status set to implemented, and the docs index. Full gates. Ledger row.
4. **Device check (owner).** Export a day with a typical-weight egg, a whole-milk volume entry and a weighed food; compare the file in Developer tools and in Drive with the Food Log rows. Simulator runs prove software behaviour only.

Photo-specific per-value origins (Q3) become their own contract and schema version after PR 3.

## 11. Owner decisions

Decided under the owner's delegation, 31 October 2026: each question takes its recommendation, as recorded below.

- **Q1. `weight_basis`.** Keep its v1 meaning (declaration only) and add `amount_method` beside it, or redefine it so a typical weight reads `estimated`? *Decided: keep it; redefining a v1 key changes what existing readers see.*
- **Q2. Legacy typed method text.** Export `recorded` with the code only, or include the person's typed text? *Decided: code only; typed text is user input that v1 never exported, and it carries no estimate meaning.*
- **Q3. Label photo per-value origins** (found, checked, corrected), deferred to #312 by label photo v1 17.4. Fold into v2, or a later version? *Decided: a later version with its own contract; no photo-origin projection exists in the application layer yet, and it would need its own gate.*
- **Q4. `includes_estimates` on totals where nothing is known** (section 7). Leave the v6 rule as it is, or fix it as `food-intake-summary-v7` (only known contributions set the flag)? *Decided: leave it in #312; the separate issue is #344; changing summary semantics touches Home, Health and Copy all, not just the export.*
- **Q5. Privacy policy wording.** Is "their amounts" enough for the entered amount and method, or should the sentence add "and how each amount was obtained"? *Decided: no wording change; the content is a description of amounts already covered, with no new destination or trigger.*
- **Q6. Version history.** Head version only, or a method per listed version? *Decided: head only; earlier versions do not contribute and the history already records that a correction happened.*
- **Q7. Missing referenced conversion.** Block the day's food file (`missingReference`), or export `is_estimate: false` as the summary projection effectively does? *Decided: block; no save route is known to create it, and fail closed matches D6.*
- **Q8. Past days already on Drive as v1.** Leave them until the person re-exports a day (only possible within the seven-day window), with no automatic rewrite? *Decided: yes, no backfill; the export stays manual and user-initiated.*
