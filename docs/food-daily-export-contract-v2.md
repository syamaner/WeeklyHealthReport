# Food daily export contract v2 (#312)

Status: **draft for owner review, 31 October 2026.** Not approved and not implemented. The architecture gate below is the proposal; it has not yet been reviewed by the `architecture-gate` role. Open questions for the owner are listed in section 11 and are not decided here.

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

Not in scope (unchanged from v1 unless an open question says otherwise):

- Day totals and their semantics. `summary_version` stays `food-intake-summary-v6`; the summary shape is unchanged.
- Nutrient value objects, the closed origin rule, provenance, bounds, conflicts and `plain_water`.
- Photo-specific per-value origins for label photo entries (deferred to #312 by [label photo AI pre-fill v1](label-photo-ai-prefill-v1.md) 17.4; see open question Q3).
- The health Daily JSON envelope, its schemas and its rule rejecting food at every admitted version.
- Drive transport, identity, ordering tokens, registries and installation markers.
- Any new stored record, field, migration or archive contract. `amount_method` is derived at export time from records the ledger already stores.

## 3. What v2 adds

### 3.1 `quantity.amount_method`

Present on every entry in a v2 file, absent from every entry in a v1 file. Every key inside it is always written; a value that does not apply is an explicit `null`, never a missing key and never `0`.

| Field | Type | Meaning |
|---|---|---|
| `code` | string, closed set (3.2) | How the exported `quantity.amount` was obtained. Derived by `FoodQuantityMethod.of(_:conversion:)`, the projection the Food Log row and saved entry already use. |
| `is_estimate` | bool | `FoodQuantityEstimate.isEstimate(_:conversion:)`, the one rule that also feeds `FoodIntakeContribution.quantityIsEstimate` and therefore the summary's `includes_estimates`. True for `typical_weight`, `whole_milk_volume` and `estimated_by_eye`; false otherwise. |
| `entered` | object or null | The amount the person entered when it differs from `quantity.amount` (a count, or millilitres converted to grams): `{"amount", "unit"}` with `unit` one of `g`, `mL`, `count`. For a conversion it is the stored `QuantityConversionVersion.sourceQuantity`; for a weight declaration it is `EdibleWeightDeclaration.originalInput`. `null` when the exported amount is what the person entered, or when no original input was stored (unknown is not zero, and an absent original input is not the same as the exported amount). |
| `source` | object or null | Only for a source-backed estimate (`typical_weight`, `whole_milk_volume`): `{"method_version", "source_release_id", "size"}`. `method_version` and `source_release_id` are the stored conversion values, which the closed estimate table already validates as a pair (count portion estimate v1, C6). `size` is `small`, `medium`, `large` or `extra_large` for a typical weight (from the frozen `CountPortionGuideCode` table) and `null` for whole milk. `null` for every other code. |

### 3.2 Closed `code` set

| `code` | Stored records | `is_estimate` | `entered` | `source` |
|---|---|---|---|---|
| `direct` | No weight declaration and no conversion, or a pasted-label servings conversion (`LabelServingPolicy`) | false | `null` | `null` |
| `weighed` | Weight declaration, basis measured (shown as Kitchen scale on a direct weight, #318) | false | `originalInput` or `null` | `null` |
| `estimated_by_eye` | Weight declaration, basis estimated | true | `originalInput` or `null` | `null` |
| `kitchen_scale` | Conversion `user_count_conversion_v1:kitchen_scale` | false | `sourceQuantity` | `null` |
| `package_weight` | Conversion `user_count_conversion_v1:package_weight` | false | `sourceQuantity` | `null` |
| `typical_weight` | Conversion with a `count_portion_guide_v1:*` code and a `usda-sr-legacy-portions:` release | true | `sourceQuantity` (count) | method version, release, size |
| `whole_milk_volume` | Conversion `cofid-whole-pasteurised-milk-volume-v1` with a `phe-npm-2018:` release | true | `sourceQuantity` (mL) | method version, release, `size: null` |
| `recorded` | Any other conversion (typed legacy method text written before the closed method set) | false | `sourceQuantity` | `null` |

`recorded` exports the code only, never the typed method text (open question Q2). Typed text is never an estimate without the matching release, as count portion estimate v1 invariant 4 already requires; a reader must treat `recorded` as "method not described", not as measured.

The plate path (Total minus empty plate) stores a measured weight declaration and exports as `weighed`, as the Food Log shows it today. Distinguishing it is an extension (section 9).

### 3.3 `weight_basis` keeps its v1 meaning

`quantity.weight_basis` stays exactly as D9 defines it (`declared`, `estimated`, `unknown` from the weight declaration alone), so a reader that already branches on it reads every v2 file the same way. It is superseded for new readers by `amount_method`, and a typical-weight entry still reports `weight_basis: "unknown"` in v2. Redefining it would silently change the meaning of a v1 key (open question Q1).

### 3.4 `notes.quantity_estimates`

`notes` gains a fourth constant sentence under the key `quantity_estimates`:

> quantity.amount_method.is_estimate marks an amount that was estimated (a typical weight, the whole-milk volume rule or an estimate by eye). Every nutrient value in that entry is scaled from the estimated amount, including values whose state is measured.

Constant text only, as D7 requires.

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

  A mixed file (a v1 file carrying `amount_method`, or a v2 file missing it on any entry) is rejected, as is any other schema number. Byte-for-byte decode and re-encode stays a requirement for both versions.
- **Drive identity.** Unchanged. The file name stays `food-daily-YYYY-MM-DD.json`; the ordering token stays `food-v1|<data_as_of>|<exported_at>` (it names the ordering format, not the schema); the owner property value stays the package-fixed `v1`; registries and markers are unchanged. A schema-2 file for a date replaces that date's verified schema-1 file under the same persisted Drive file ID, as health schema evolution does. Stale-cutoff rejection and exact-byte readback are not relaxed.
- **Downgrade.** A build that predates v2 rejects a schema-2 file in `validate` (its check is `foodDailySchemaVersion == 1`), so it fails closed during reconcile or recovery rather than overwriting it. Do not downgrade for replacement or recovery of a day already exported as v2.
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
```

The last line is a plain water entry: direct millilitres, not an estimate, and unchanged in `plain_water`.

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
    "quantity_estimates": "quantity.amount_method.is_estimate marks an amount that was estimated (a typical weight, the whole-milk volume rule or an estimate by eye). Every nutrient value in that entry is scaled from the estimated amount, including values whose state is measured.",
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
- **`includes_estimates` on a total with nothing known.** Under v6 an estimated-quantity contribution sets `includes_estimates` for every nutrient key it can be scaled for, including keys whose value is unknown. The current typical-weight golden shows `water` with `state: "none_known"` and `includes_estimates: true`. v2 does not change this (open question Q4); the entry-level `is_estimate` now lets a reader see which entry set it.
- **Overflow.** Unchanged. `entered` and the exported amount are stored `PositiveQuantity` values and are finite by construction; a nutrient that overflows when scaled is still `unknown` with `missing_conversion`, and an overflowed total is still `unavailable`.
- **Corrected values.** `amount_method` describes the head version only, the one that contributes. If a typical-weight entry was corrected to Kitchen scale, the head exports `kitchen_scale` with `is_estimate: false`, and `versions` still lists the history for audit without per-version methods (open question Q6). A changed egg size is a new conversion version and exports the new size.
- **Conversion mismatch.** The conversion is used only when its ID equals the head's `quantityConversionVersionID`, as `FoodQuantityEstimate.isEstimate` already checks. If the head references a conversion that is not in the snapshot, the builder throws `missingReference` and no food file is produced (fail closed, like D6). Today the summary projection treats a missing conversion as "not an estimate"; failing closed in the export avoids exporting a guessed `is_estimate: false` (open question Q7).
- **Half counts.** A typical weight on 0.5 pieces (half-item count v1) exports `entered: {"amount": 0.5, "unit": "count"}` and the guide grams for half an egg.
- **Removed entries.** Still omitted (D1).
- **Empty day.** `entries: []`; `notes` carries the new sentence; nothing else changes.

## 8. Egress impact

**No new destination, no new trigger and no new transport.** The food file still goes only to the user's existing Google Drive destination under `drive.file`, only when the user chooses Export with Food log on, as exact reviewed bytes verified by readback. DriveExportKit, OAuth, registries and the health file are unchanged.

The file's content gains, per entry, a closed method code, an estimate flag, the amount the person entered and, for the two source-backed estimates, the frozen rule code and its public source release identifier. All of this is derived from the same local records that already produce the exported amount; no attachment, typed method text, photo, label text or search text is added. The approved privacy-policy sentence already says the file contains "the foods you logged, their amounts and times", so this contract proposes no privacy-policy wording change; the owner confirms that reading (open question Q5). The Google Drive row in [privacy-and-egress.md](privacy-and-egress.md) gains a link to this contract in the writer PR, with no change to what it permits.

## 9. Architecture gate (proposed)

### Responsibilities

| Layer | Change |
|---|---|
| Domain (`FoodLedgerDomain`) | None. No record, field, version or summary change. `FoodIntakeSummary` stays `food-intake-summary-v6`. |
| Application (`FoodLedgerApplication`) | `FoodDailyExportDocument.schemaVersion` becomes 2. New DTO `FoodDailyExportAmountMethod` (`code`, `is_estimate`, `entered`, `source`) with explicit-null encoding, as an optional `amountMethod` on `FoodDailyExportQuantity` encoded only when present. `FoodDailyExportNotes` gains an optional `quantityEstimates`. `FoodDailyExportBuilder` derives the object from `FoodQuantityMethod.of(_:conversion:)`, `FoodQuantityEstimate.isEstimate(_:conversion:)` and `CountPortionGuideCode.entry`, using the same conversion lookup as `FoodIntakeProjection`, and throws `missingReference` for a referenced conversion that is missing. A pure `FoodDailyExportShape.validate(_:)` holds the per-version presence and summary-version table in section 5, so the Drive policy and the tests share one rule. |
| Infrastructure / app target | `DailyFoodExportIdentityPolicy.validate` calls the shared shape rule instead of `schemaVersion == 1` plus its own summary set. `DailyFoodExportService` is unchanged apart from mapping the existing `missingReference` block. Ordering, registries and markers are unchanged. |
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

### Contract tests to add

1. Code mapping: every `FoodQuantityMethod` case maps to exactly one `code`; `is_estimate` matches `FoodQuantityMethod.isEstimate` and `FoodQuantityEstimate.isEstimate`.
2. Builder, one synthetic entry per code: typical weight (each size, raw and boiled, and 0.5 pieces), whole milk, estimated by eye with and without original input, weighed, kitchen scale, package weight, direct grams, direct mL, plain water, pasted-label servings, and a legacy typed method exporting `recorded` without its text.
3. Guide code without the matching release prefix exports `recorded` and `is_estimate: false` (gate F6 parity).
4. Parity: for a mixed snapshot, each entry's `is_estimate` equals its contribution's `quantityIsEstimate`, and a total's `includes_estimates` is true only when some contributing entry has `is_estimate`, an estimated or calculated value, or the v6 quirk in section 7 applies.
5. A head referencing a missing conversion produces no document (`missingReference`), and the service maps it to the existing blocked state.
6. Corrected entry: typical weight then kitchen scale exports the head's method only.
7. Shape rule: schema 1 with any `amount_method` or `quantity_estimates` is rejected; schema 2 missing either is rejected; schema 2 with summary v4 or v5 is rejected; schema 3 is rejected.
8. Frozen v1 goldens (all of `docs/fixtures/food-daily-v1/`) still decode, re-encode byte for byte and pass the policy.
9. v2 goldens under `docs/fixtures/food-daily-v2/` (mixed day with every code, typical-weight day, milk day, empty day, plain-water-only day) are byte-stable and pass the policy.
10. Drive policy: a schema-2 file replaces a schema-1 file for the same date under the same file ID; token ordering is unchanged.
11. Explicit nulls: `entered` and `source` are written as `null`, never omitted, in a v2 file.

## 10. Implementation plan

Small PRs, each green on its own gates, in this order. None needs a HealthKit device check; the owner's device check is a comparison of the exported file with the Food Log.

1. **PR 1, this contract (docs only).** Draft, owner decisions on section 11, then the `architecture-gate` review, folded in before any code.
2. **PR 2, readers accept v2 (no writer change).** `FoodDailyExportAmountMethod` and the optional fields, the pure shape rule, the Drive policy switched to it, hand-built synthetic v2 fixtures, contract tests 7, 8, 10 and 11. The app still writes v1, so a build from this PR can already verify, reconcile and recover v2 files. Gates: FoodLedgerKit tests, boundary check, app tests, analyze, `git diff --check`.
3. **PR 3, writer emits v2.** Builder derivation, the notes sentence, `missingReference` for a missing conversion, the generated v2 goldens, contract tests 1 to 6 and 9, the privacy-and-egress link, a forward pointer in the v1 contract, this contract's status set to implemented, and the docs index. Full gates. Ledger row.
4. **Device check (owner).** Export a day with a typical-weight egg, a whole-milk volume entry and a weighed food; compare the file in Developer tools and in Drive with the Food Log rows. Simulator runs prove software behaviour only.

Photo-specific per-value origins, if the owner wants them (Q3), become their own contract and schema version after PR 3.

## 11. Open questions for the owner

Each has a recommendation; none is decided by this draft.

- **Q1. `weight_basis`.** Keep its v1 meaning (declaration only) and add `amount_method` beside it, or redefine it so a typical weight reads `estimated`? *Recommendation: keep it; redefining a v1 key changes what existing readers see.*
- **Q2. Legacy typed method text.** Export `recorded` with the code only, or include the person's typed text? *Recommendation: code only; typed text is user input that v1 never exported, and it carries no estimate meaning.*
- **Q3. Label photo per-value origins** (found, checked, corrected), deferred to #312 by label photo v1 17.4. Fold into v2, or a later version? *Recommendation: a later version with its own contract; no photo-origin projection exists in the application layer yet, and it would need its own gate.*
- **Q4. `includes_estimates` on totals where nothing is known** (section 7). Leave the v6 rule as it is, or fix it as `food-intake-summary-v7` (only known contributions set the flag)? *Recommendation: leave it in #312 and open a separate issue; changing summary semantics touches Home, Health and Copy all, not just the export.*
- **Q5. Privacy policy wording.** Is "their amounts" enough for the entered amount and method, or should the sentence add "and how each amount was obtained"? *Recommendation: no wording change; the content is a description of amounts already covered, with no new destination or trigger.*
- **Q6. Version history.** Head version only, or a method per listed version? *Recommendation: head only; earlier versions do not contribute and the history already records that a correction happened.*
- **Q7. Missing referenced conversion.** Block the day's food file (`missingReference`), or export `is_estimate: false` as the summary projection effectively does? *Recommendation: block; no save route is known to create it, and fail closed matches D6.*
- **Q8. Past days already on Drive as v1.** Leave them until the person re-exports a day (only possible within the seven-day window), with no automatic rewrite? *Recommendation: yes, no backfill; the export stays manual and user-initiated.*
