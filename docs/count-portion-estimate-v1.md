# Count portion estimate v1 (#307)

Status: **design spec and architecture gate, 24 October 2026. Documents only; no production code has changed.** The owner approved autonomous delivery of #307, including any contract, on 24 October 2026. Owner principle: the app pre-fills, the user validates and corrects, and every estimate stays visible.

Amendment 1 (24 October 2026, owner input: "Small, medium, large, X-Large estimates could help"): eggs get a one-tap size choice (Small, Medium, Large, Extra large) with Large pre-filled; each size is its own closed code; boiled sizes other than Large are a documented derivation from the raw sizes; the USDA archive was re-downloaded with owner approval and the values re-verified (section 3); the Daily JSON summary moves to food-intake-summary-v6 while entry fields stay unchanged (follow-up #312); the architecture gate findings F1 to F11 on 435783ba are folded in.

This contract amends [count-conversion-method-v1.md](count-conversion-method-v1.md) (a count without a guide asks for a measured amount), [food-confirmation-contract-v5.md](food-confirmation-contract-v5.md) (`countNeedsMeasuredAmount`, the Log press as acceptance) and [direct-edible-weight-contract-v1.md](direct-edible-weight-contract-v1.md) (no guide estimates admitted). It admits the first source-backed count guide that [count-portion-guide-research-v1.md](archive/count-portion-guide-research-v1.md) prepared, and reuses the persistence pattern of [cofid-whole-milk-volume-admission-v1.md](cofid-whole-milk-volume-admission-v1.md).

## 1. Problem (UX review of main 53450fb7, screenshots 20 to 30, 35 and 42)

1. **Eggs by count are blocked behind four fields.** "3 eggs" on Confirm shows "No source-backed size guide is available for this food", then "Converted edible amount", "Converted unit", "How you got this amount" (Choose one) and a warning, and Log stays disabled with "For a count, enter the measured edible weight or volume and how it was measured, or change the unit to g or mL." The commonest count food in the app cannot be logged without a scale or a guess the app gives no help with.
2. **Choosing a method rebuilds the section.** "Estimated by eye" switches to the direct-weight layout: a gram field, "How you got the weight", the note "The original amount below is kept as well…", "Use original amount instead", a second amount field (3) and a second unit picker (count). Two amounts are on screen for one food.
3. **Three words for one count.** The Amount sheet and Recent say "pieces", Confirm's unit picker says "count", and the saved entry and history say "units" ("3 units · 150 g", "Amount changed 3 units to 3 units (150 g to 120 g)").
4. **The method disappears after saving.** The saved entry header shows only "Estimate · Unknown details stay unknown" (a generic-source estimate wins over "The weight was estimated"), the Food Log row shows only "Estimate", and nothing says the weight was estimated by eye, weighed or read from a package. The history line repeats the unchanged count instead of naming what changed.

## 2. Decisions

| ID | Decision |
|---|---|
| C1 | A **count portion guide** is a reviewed, versioned, per-record set of typical edible weights for one piece, one per size, from a cited source. v1 admits whole chicken eggs without shell in four sizes, Small 38 g, Medium 44 g, Large 50 g and Extra large 56 g, for four allow-listed raw and boiled records (section 3). Every other food keeps today's measured flow. |
| C2 | When a guide applies to the selected record and the unit is pieces, Confirm **pre-fills Large** and shows "About 150 g · Estimate" with a one-tap **size choice** (each size shows its weight, "Large, about 50 g each") and a **Change** action for a measured or own weight. Log accepts what is shown, as the v5 Log press accepts everything shown. Large is pre-filled on the owner's instruction because it is the one size USDA gives for both raw and boiled eggs. This is a deliberate departure from the whole-milk opt-in tap, scoped to `count_portion_guide_v*` (section 4, "Why the pre-fill is still an explicit save"). Milk stays opt-in. |
| C3 | The pre-fill is a **labelled estimate everywhere**: Confirm (including "Log about 215 kcal"), the Food Log row, the saved entry, day totals ("includes estimates"), Recent, the Health report food section, Copy all and the Daily JSON food summary. |
| C4 | Correction is **one layout**: Change opens a single "Total weight" field and "How you got it" (Kitchen scale, Package weight, Estimated by eye). The count stays the only amount on screen; "Use original amount instead" and the second amount and unit pickers are not shown on a count. "Use typical weight" returns to the size choice. Foods without a guide use the same single layout, with no pre-fill. |
| C5 | **Persistence reuses existing records only**: a guide save is the existing `QuantityConversionVersion` with a per-size guide code in `methodVersion` and the guide's own `SourceRelease`, exactly as the whole-milk volume estimate is stored. Kitchen scale and Package weight stay `user_count_conversion_v1:*` conversions; Estimated by eye stays a `weightDeclaration` with basis `estimated`. No new field, operation type, archive contract or schema identity. |
| C6 | **Quantity estimate is one pure rule** over stored records: estimated when the weight declaration basis is `estimated`, or the conversion is an admitted source estimate, identified by **method version and source release ID prefix together** from a frozen application table (the guide v1 codes with `usda-sr-legacy-portions:`, and the whole-milk rule ID with `phe-npm-2018:`). Every projection that asks "is this quantity an estimate" uses it. Because day totals now see quantity estimates, the summary semantics change: **`food-intake-summary-v6`** (C13). |
| C7 | **Quantity method is one pure projection** (`FoodQuantityMethod`) over the log version and its conversion, rendered by one presentation formatter, so Confirm, the Food Log row, the saved entry and history show the same words. |
| C8 | **One count word: "piece" / "pieces"** on every surface (Amount sheet, Recent, Confirm, Quick add, Favourites, Common foods, inventory, list import, Food Log, saved entry, history, VoiceOver). The noun comes from one pure application function that presentation wraps. A pasted-label or source serving stays "serving" / "servings", which means something different. Stored, parsed and exported `count` is data, not copy, and is unchanged. Food-specific nouns ("3 eggs") are deferred: they need per-food plural data and would bring variance back. |
| C9 | **Closed set at save**: any `methodVersion` with the prefix `count_portion_guide_v` must be an admitted v1 per-size code, name an entry that applies to the selected record, carry the guide's source release and equal count × that size's grams exactly; otherwise the save fails closed (`invalidQuantity`). The check sits in `makeConversion` beside `CountConversionMethod.admits`. |
| C10 | **No new egress, no new nutrient data.** The guide values come from the USDA SR Legacy April 2018 archive whose hash the app already pins for its USDA nutrition records, projected offline into a small bundled, hash-pinned manifest. |
| C11 | **Boiled egg sizes are a labelled derivation.** USDA gives a hard-boiled egg only as Large, 50 g, the same as a raw Large egg. Small, Medium and Extra large for boiled records use the raw weights, each under its own code that says it is derived, and the details text says so. |
| C12 | **Sizes are US grading; the weight is the meaning.** Every size option shows its weight, and the details note says "US sizes; carton sizes differ by country". Jumbo (63 g) is in the source but not offered, to keep four choices; the user can enter any other weight through Change. |
| C13 | **Daily JSON food export.** Entry fields are unchanged for #307: a guide entry exports its edible grams with `weight_basis: "unknown"` (there is no weight declaration); entry-level estimate fields are follow-up #312. The **summary** changes: `summary_version` becomes `food-intake-summary-v6`, whose `includes_estimates` also covers source-backed quantity estimates (count guides and whole-milk volume). This narrows the earlier "export unchanged" decision to entry fields only (architecture gate F1, option a, decided under the owner's delegation). |

## 3. Source, citation and data provenance

### Admitted values

USDA FoodData Central, SR Legacy, final release April 2018, archive `FoodData_Central_sr_legacy_food_json_2018-04.zip`, SHA-256 `0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef`. This is the same archive, by hash, as the app's bundled `usda-legacy:2018-04-01` nutrition release, so the guide adds a projection of an already admitted artefact, not a new source. With owner approval the archive was downloaded again on 24 October 2026 to the session scratchpad (`usda-sr-legacy/FoodData_Central_sr_legacy_food_json_2018-04.zip`), its hash matched, and the portions were read offline from the JSON inside it, then read again independently while amending this spec (same values, gate F9):

| FDC record | Portion ID | Descriptor | Grams for 1 | Admitted |
|---|---|---|---:|---|
| 171287 Egg, whole, raw, fresh | 88379 | small | 38 | yes |
| 171287 | 88378 | medium | 44 | yes |
| 171287 | 88374 | large | 50 | yes |
| 171287 | 88375 | extra large | 56 | yes |
| 171287 | 88376 | jumbo | 63 | no (C12) |
| 171287 | 88377 | cup (4.86 large eggs) | 243 | no, not a piece |
| 173424 Egg, whole, cooked, hard-boiled | 92500 | large | 50 | yes |
| 173424 | 92499, 92498 | tbsp, cup chopped | 8.5, 136 | no, not a piece |

SR Legacy gram weights are for the edible portion ([SR Legacy documentation](https://www.ars.usda.gov/ARSUserFiles/80400525/Data/SR-Legacy/SR-Legacy_Doc.pdf)); the shell is refuse. FoodData Central data are published in the public domain under CC0 1.0 ([FDC documentation](https://fdc.nal.usda.gov/data-documentation/)); the app attributes them anyway. Every portion uses the undetermined measure unit 9999, so piece semantics rest on the reviewed descriptor and record, recorded in the manifest, not on the unit ID.

### Guide entries and codes

Each size is its own closed entry and code (`count_portion_guide_v1:<entry>`):

| Size | Raw entry (FDC 171287) | Boiled entry (FDC 173424 record set) | Grams |
|---|---|---|---:|
| Small | `usda_sr_legacy_171287_88379` | `usda_sr_legacy_boiled_from_171287_88379` | 38 |
| Medium | `usda_sr_legacy_171287_88378` | `usda_sr_legacy_boiled_from_171287_88378` | 44 |
| Large | `usda_sr_legacy_171287_88374` | `usda_sr_legacy_173424_92500` | 50 |
| Extra large | `usda_sr_legacy_171287_88375` | `usda_sr_legacy_boiled_from_171287_88375` | 56 |

### Boiled derivation (C11)

USDA lists a large hard-boiled egg (portion 92500) at 50 g and a large raw egg (88374) at 50 g: at the one size where both are given, boiling in the shell leaves the edible weight unchanged to the gram. The derivation therefore states only this: for a boiled egg of another size, the app uses the raw-egg weight for that size from the same release, as an estimate. It does not claim USDA measured boiled Small, Medium or Extra large eggs. The `boiled_from_171287_*` codes keep that difference visible in the stored record, and the details text names it. The Department of Health 2012 UK sampling report (not admitted, corroboration only) is consistent: its averages give raw and boiled edible weights within about a gram of each other at medium and large ([research v1](archive/count-portion-guide-research-v1.md)). If a future review rejects the derivation, a v2 guide set offers boiled eggs as Large only; stored v1 codes keep their labels.

### Record allow-list

| Nutrition record (release and record ID) | Entries | Basis of the mapping |
|---|---|---|
| `usda-legacy:2018-04-01:…:fdc:171287` Egg, whole, raw, fresh | the four raw entries | Same record |
| `usda-legacy:2018-04-01:…:fdc:173424` Egg, whole, cooked, hard-boiled | the four boiled entries | Same record (Large); derivation (others) |
| `cofid:2021:…:row:1096:a72b3e44d2dadad3` Eggs, chicken, whole, raw | the four raw entries | Reviewed cross-source: same food, part and preparation |
| `cofid:2021:…:row:1091:0fe190b81c244ccf` Eggs, chicken, whole, boiled | the four boiled entries | Reviewed cross-source: same food, part and preparation |

Full release IDs are the ones in the bundled `usda-generic-v1.json` and `cofid-2021-generic-search-v1.json`. A different release or row never inherits a guide. Whites, yolks, fried, poached, scrambled, omelette, dried, frozen, duck, quail and turkey eggs, recipes and every non-egg food have no guide in v1. Fried eggs are excluded on purpose: frying changes mass and adds fat, and the app never infers oil.

### Size names and their limits (C12)

- The names are US grading, set by shell-on weight per dozen. UK and EU cartons grade single eggs by shell-on weight (medium 53 to under 63 g, large 63 to under 73 g, [APHA egg marketing guidance](https://assets.publishing.service.gov.uk/media/69382d2de447374889cd8f73/EMR01_Guidance_on_legislation_covering_egg_marketing_November_2025.pdf)), and Taiwan cartons differ again. A UK "large" egg is heavier than a US large one: the DH 2012 averages work out at about 58 g without shell for a boiled UK large egg, nearer the US Extra large.
- So the weight, not the name, is the meaning: every option reads "Large, about 50 g each", and the details note says "US sizes; carton sizes differ by country". No UK, EU or Taiwan figure is shown or stored.
- Every choice stays "about", stays labelled an estimate, and can be replaced in one tap.

### Projection tooling and manifest

- New developer tool `Tools/FoodSourceEvaluation/project_usda_count_portions.py` takes a **local path** to the archive, verifies its SHA-256 equals `0fe8ae48…`, reads portions 88379, 88378, 88374, 88375 (record 171287) and 92500 (record 173424), refuses if any descriptor or gram value differs from the table above, adds the derived boiled entries, and writes `Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources/count-portion-guides-v1.json`. It never downloads. App egress is unchanged.
- The owner authorised running the preprocessing on 24 October 2026: the implementer generates the manifest from the verified scratchpad archive and records the archive hash, the manifest hash and the command line in the PR.
- Manifest fields: `guide_set_id` (`count-portion-guides-v1`), `source` (title, archive file name, archive SHA-256, licence `CC0 1.0`, attribution text, documentation URL), and per entry `guide_id`, `size` (`small`, `medium`, `large`, `extra_large`), `grams`, `part` (`whole_without_shell`), `preparation` (`raw` or `boiled`), `source_fdc_id`, `source_portion_id`, `source_descriptor`, `derivation` (`none` or `raw_size_weight_for_boiled`), `default` (true only for Large), and `applies_to` (release ID and record ID pairs from the allow-list). The adapter pins the manifest's SHA-256 in code, as the milk rule does, and rejects any mismatch, a malformed entry, a missing size or more than one default per record.
- Guide `SourceRelease`: `sourceReleaseID = usda-sr-legacy-portions:2018-04-01:sha256:0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef`, `sourceID = usda-sr-legacy-portions`, `artifactHash` = the archive hash, `manifestHash` = the guide manifest hash, `pipelineVersion = count-portion-guides-v1`, `schemaVersion = count-portion-guide-v1`, licence and attribution from the manifest. It is deliberately distinct from the nutrition release ID so the two release records never collide.

## 4. Behaviour

### Confirm, guide available (egg, unit pieces)

1. The selected record is on the allow-list and the unit is pieces with a positive finite count. The reducer state holds only the **selected guide entry ID** (Large by default), never grams or a conversion; the view model reads the entry's size and grams from the guide port for display.
2. The amount section shows the count once, the size choice (four rows, Large selected) and the weight row "About 150 g · Estimate". Log is enabled (`countNeedsMeasuredAmount` is satisfied by a selected guide entry) and reads "Log about 215 kcal".
3. One tap on another size selects it and recomputes the total (Medium: "About 132 g"). Changing the count recomputes the total; it is derived, never typed.
4. Pressing Log sends the state to the service, which **resolves the entry ID through its own injected port**, builds the conversion (count × that size's grams, the per-size code, the guide release) and writes it (section 6). The service never trusts grams from the view model.
5. A guide applies only to unit pieces. It never applies to servings, a source-declared serving, a recipe serving, pasted-label servings, grams or millilitres. Switching to a candidate that is not allow-listed clears the entry ID and falls back to the measured flow with nothing pre-filled; switching between allow-listed raw and boiled records keeps the size and swaps to that record's entry.
6. **Change** opens the correction layout below with "Total weight" empty and "How you got it" at "Choose one", and clears the entry ID while it is open. **Use typical weight** restores the size choice at the last selected size.

### Why the pre-fill is still an explicit save (gate F2)

The whole-milk volume rule asks for a separate tap; count guides do not. This departure is scoped to `count_portion_guide_v*` and holds because:

- the food is the user's own choice: the guide appears only after the user selected an allow-listed record and entered a count in pieces;
- the estimate and the word **Estimate** are on the primary row, beside the count, whenever Log would save them, and the Log button itself reads "Log about … kcal";
- nothing is persisted until the user presses Log, which v5 defines as accepting everything displayed;
- the size is changed in one tap and the weight replaced through Change, so correcting costs no more than accepting.

It is not `retainedWeightNeedsConfirmation`. That requirement protects a weight the **user** typed earlier from silently carrying over to a different food or preparation after a candidate change; the user must reconfirm their own number. A guide estimate is never carried over: it is recomputed from the current record, size and count each time, so there is no stale user value to reconfirm. Milk stays opt-in because a volume estimate changes the unit the user typed (mL to g), whereas the guide fills in a weight the count could not provide.

### Confirm, correcting or no guide (one layout)

- Rows: amount and unit (count once), "Total weight" with g / mL, "How you got it" (Kitchen scale, Package weight, Estimated by eye), "Weighed on a plate".
- Kitchen scale and Package weight save `user_count_conversion_v1:*` conversions exactly as count-conversion-method-v1 says.
- Estimated by eye saves the existing estimated weight declaration with the count as original input. The reducer still uses the direct-weight draft; the **presentation** keeps the correction layout and does not show the direct-weight block, "Use original amount instead" or a second amount. Estimated by eye with mL shows a field-local message (estimates are in grams) and blocks Log.
- Requirements are unchanged in kind: `countNeedsMeasuredAmount`, `measuredWeightMissing`, `weightBasisMissing` and the plate requirements keep their meaning; their copy changes (section 5).

### Reopen and edit (gate F4)

- A saved guide entry reopens with the entry ID parsed from its stored code, so the chosen size is selected again, with the stored total shown.
- **Unchanged re-save:** `FoodLogEditComparison.reusesConversion` keeps the stored conversion when the count and the stored conversion are unchanged, so no new conversion is written and the C9 check is not re-run. This also holds when a later manifest has withdrawn the guide: the stored record stays valid and keeps its label.
- **Count or size change:** the service resolves the entry ID through the port and writes a new conversion version. If the port no longer offers the stored entry, the reducer clears the entry ID and `countNeedsMeasuredAmount` is raised, so the user enters a measured or estimated weight; nothing is relabelled.
- Entries saved before this contract keep their meaning (section 7).

### After saving

- Food Log row: amount line "3 pieces · about 150 g"; flags "Estimate · Typical weight" (plus any unknown-nutrient flags).
- Saved entry header: "3 pieces · about 150 g · today, 13:00", then the estimate line (section 5).
- History: names what changed, never a repeated unchanged count.

## 5. Copy (British spelling, no emoji)

### Confirm

| Element | Text |
|---|---|
| Unit picker option for counts | `pieces` |
| Size choice header | `Egg size` |
| Size options (one tap each, checkmark on the selected one) | `Small, about 38 g each`, `Medium, about 44 g each`, `Large, about 50 g each`, `Extra large, about 56 g each` |
| Size option VoiceOver | `Large, about 50 grams each, selected` |
| Weight row title | `Weight` |
| Weight row value | `About 150 g` |
| Weight row subtitle | `Typical weight · Estimate` |
| Weight row action | `Change` |
| Weight row VoiceOver | `Weight, about 150 grams, typical weight, estimate. Change` |
| Log button with an estimated quantity (guide, estimated by eye, milk volume) | `Log about 215 kcal` |
| Log button otherwise | `Log 215 kcal` (unchanged) |
| Details disclosure title | `About this estimate` |
| Details text, raw egg | `Typical weights of one egg without shell, from USDA FoodData Central SR Legacy (April 2018). US sizes; carton sizes differ by country, so your eggs may weigh more or less. Change it if you know the weight.` |
| Details text, boiled egg (added sentence) | `USDA gives a boiled egg only as large, 50 g, the same as a raw large egg, so the other boiled sizes use the raw weights.` |
| Details source line (plain text, no link in v1) | `Source: USDA FoodData Central, SR Legacy, April 2018 · public domain (CC0 1.0)` |
| Correction layout field | `Total weight` with placeholder `Without shell, bone or skin you did not eat` |
| Correction layout picker | `How you got it`: `Kitchen scale`, `Package weight`, `Estimated by eye`; start `Choose one` |
| Return to guide (guide foods only) | `Use typical weight` |
| No-guide intro (replaces "No source-backed size guide is available…") | `Enter the total weight you ate, without shell, bone or other parts.` |
| Field-local, weight missing | `Enter the total weight.` |
| Field-local, method missing | `Choose how you got the weight.` |
| Field-local, estimate in mL | `Estimates are in grams. Enter the weight in g.` |
| Log bar, `countNeedsMeasuredAmount` | `Enter the total weight and how you got it, or change the unit to g or mL.` |

The details disclosure shows no tappable link in v1 (gate F11); the source is named in plain text.

### Food Log, saved entry, Recent and history

The amount line is `<count> · <edible>`, where the edible amount carries `about` only when the quantity is an estimate. The method label comes from `FoodQuantityMethod`.

| Method | Amount line | Method label (Food Log flags, saved entry) |
|---|---|---|
| Typical weight (guide) | `3 pieces · about 150 g` | `Estimate · Typical weight` |
| Estimated by eye | `3 pieces · about 150 g` | `Estimate · Estimated by eye` |
| Kitchen scale | `3 pieces · 150 g` | `Kitchen scale` |
| Package weight | `3 pieces · 150 g` | `Package weight` |
| Weighed (direct weight, measured) | `150 g` (or `3 pieces · 150 g` when a count was kept) | `Weighed` |
| Whole-milk volume estimate | `200 mL · about 206 g` | `Estimate · Whole milk volume estimate` |
| Legacy typed method | `3 pieces · 150 g` | `Recorded: <stored text>` |
| Grams or millilitres entered directly | `150 g` | none |

- Singular: `1 piece`. Servings stay `1 serving` / `2 servings`.
- Saved entry header line 2 combines both estimate kinds once: `Estimate · Typical weight, Large, about 50 g each · Unknown details stay unknown`, or `Estimate · Estimated by eye`, or `Estimate · Unknown details stay unknown` when only the source is an estimate. Measured methods add their label without `Estimate`: `Kitchen scale`.
- Food Log row VoiceOver: `13:00, Eggs, chicken, whole, boiled, 3 pieces, about 150 grams, 215 kcal, estimate, typical weight`.
- History lines:
  - count changed: `Amount changed 3 pieces to 4 pieces (about 150 g to about 200 g)`
  - size changed: `Weight changed about 150 g to about 132 g · now Medium`
  - only the weight changed: `Weight changed about 150 g to 120 g`
  - the method changed: append ` · now Kitchen scale` (or the new method label), for example `Weight changed about 150 g to 120 g · now Kitchen scale`
  - nothing changed: `Saved again without changes` (unchanged)
- Recent: `3 pieces`; a guide entry relogged from Recent opens Confirm with its stored size selected when that entry is still offered, otherwise Large.

## 6. Persistence

| Save | Records written | `methodVersion` | `sourceReleaseID` | Operation |
|---|---|---|---|---|
| Typical weight, any size | `QuantityConversionVersion` (source 3 count, converted count × size grams) plus the guide `SourceRelease` on first use | the per-size code from section 3, for example `count_portion_guide_v1:usda_sr_legacy_171287_88378` (raw Medium) or `count_portion_guide_v1:usda_sr_legacy_boiled_from_171287_88375` (boiled Extra large) | `usda-sr-legacy-portions:2018-04-01:sha256:0fe8…` | unchanged (`confirm_food_v1`/`v3` per v5) |
| Kitchen scale, Package weight | as count-conversion-method-v1 | `user_count_conversion_v1:*` | empty | unchanged |
| Estimated by eye | `weightDeclaration` basis `estimated` | none | none | `confirm_food_v2`/`v3` as today |

- `evidenceID` is empty on a guide conversion, as on the milk rule; the code names the record, portion and derivation, and the release pins the archive and manifest.
- The size and label are a pure function of the code. The frozen v1 code table (eight codes, their size, grams and derivation flag) lives in the application layer, so a stored v1 code always has its size and label even if a later adapter withdraws the guide. A new value, record or wording needs `count_portion_guide_v2:…`.
- **No ledger or archive format changes.** No new field, operation type, registry entry, archive food contract, SQLite schema identity or migration. Existing records decode, re-encode and verify byte for byte. Older binaries already accept arbitrary `methodVersion` text and conversion source releases (the milk rule), so archives stay importable at the same contract version.
- **Daily JSON food summary** advances to `food-intake-summary-v6` (C13): `FoodIntakeSummary.version` changes, `docs/food-daily-export-contract-v1.md` is amended under its 24 October versioning rule, writers emit v6 only, and validators (including the Drive identity policy's reconcile and recovery reads) accept v4, v5 and v6. A new v6 golden is added; the existing v4 and v5 goldens still decode, re-encode byte for byte and pass the policy. `food_daily_schema_version` stays 1 (the file shape does not change), and entry `weight_basis` stays as it is (#312).
- Estimate status, method, size and amount wording are derived at read time and never stored.

## 7. Records written before this contract

- Typed legacy methods, `user_count_conversion_v1:*` codes, estimated and measured declarations and milk conversions keep their bytes. Only their **derived** display changes: the method label appears on the Food Log row and saved entry, and milk volume conversions become visible estimates (C6), which they always were on Confirm. A day that contains a milk volume entry therefore exports `includes_estimates: true` under v6 where v5 said false; earlier files keep the values they were written with.
- "units" disappears from display; stored units are the raw `count` value and do not change.

## 8. Architecture gate

### Responsibilities

| Layer | Owns |
|---|---|
| Domain (`FoodLedgerDomain`) | `FoodIntakeSummary.version` becomes `food-intake-summary-v6` (doc comment: v5 plus quantity estimates from source-backed conversions set `includesEstimates`). No other change; `QuantityConversionVersion`, `EdibleWeightDeclaration`, `PositiveQuantity` and `FoodIntakeContribution.quantityIsEstimate` already exist. |
| Application (`FoodLedgerApplication`) | `CountPortionGuideCode` (frozen v1 table of eight codes with size, grams and derivation, `admits`, parsing, the C9 rule); `FoodQuantityEstimate.isEstimate(log:conversion:)` with its frozen table of method version plus release prefix (C6); `FoodQuantityMethod` projection (C7); `FoodAmountNoun.count(_:)` returning `piece` / `pieces` (C8), next to `FoodNutritionReviewPresentation` which already lives in this layer; reducer state holding only the selected guide entry ID; `FoodLogPolicy` treating a selected entry as satisfying `countNeedsMeasuredAmount`; the service resolving the entry through its injected port in `makeConversion` (C9 beside `CountConversionMethod.admits`, after the `reusesConversion` bypass); the amended port (below); projections (`FoodIntakeProjection`, `FoodLogDayContent`, `SavedFoodEntryDetail`, `FoodRecentItems`, `FoodEntryHistory`, `FoodDailyExportBuilder` summary) switched to the shared rules. |
| Infrastructure (`FoodGenericSearch`) | `USDACountPortionGuides` adapter: loads and hash-verifies `count-portion-guides-v1.json`, builds the guide `SourceRelease`, answers the allow-list. No network, no other data. |
| Presentation (`FoodLedgerPresentation`) | Size choice, weight row, correction layout, disclosure; one formatter wrapping `FoodAmountNoun` for the amount line; method labels and history wording in `FoodLogText`; requirement copy in `FoodLogRequirementText`. |
| Composition root (`WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift`) | Creates the adapter once and injects it into the Confirm view model and `FoodConfirmationService`. A new `withCountPortionGuideSource(_:)`, beside `withMilkVolumeSource(_:)`, appends `guides.sourceRelease` to `input.sourceReleases` (once, if absent) whenever any candidate is allow-listed, so the release is in the saved transaction exactly as the PHE milk release is. |

### Port shape (gate F3)

The existing `FoodEdibleWeightGuideProviding` and `FoodEdibleWeightGuide` were placeholders with no caller. They are amended, not duplicated:

```swift
public protocol FoodEdibleWeightGuideProviding: Sendable {
    var sourceRelease: SourceRelease { get }
    /// The allow-listed sizes for exactly this record, in size order, or empty.
    func guide(for candidate: PopulatedFoodCandidate) throws -> FoodEdibleWeightGuideSet?
    /// The entry a stored or selected code names, if this record still offers it.
    func entry(_ code: LedgerText, for candidate: PopulatedFoodCandidate) throws -> FoodEdibleWeightGuide?
}

public struct FoodEdibleWeightGuideSet: Equatable, Sendable {
    public let foodRecordID: ExternalIdentifier
    public let foodSourceReleaseID: ExternalIdentifier
    public let entries: [FoodEdibleWeightGuide]   // one per size, Small to Extra large
    public let defaultCode: LedgerText            // Large
}

public struct FoodEdibleWeightGuide: Equatable, Sendable {
    public let code: LedgerText                   // count_portion_guide_v1:…
    public let size: FoodEdibleWeightGuideSize    // small, medium, large, extraLarge
    public let sourceDescriptor: LedgerText       // "large" as in the source
    public let edibleGramsPerPiece: Double
    public let isDerived: Bool
}
```

`evidenceID` and `measuredOverride` are removed (a user correction is a separate method, not an override of the guide); `guideID` and `guideVersion` fold into `code`; the release moves to the port. `FoodEdibleWeightEstimate` is removed; the calculation is `FoodQuantityCalculator` count × grams.

### v5 sites updated to v6 (gate G1, G2)

| Site | Today | Change and effect |
|---|---|---|
| `WeeklyHealthReport/GoogleDrive/DailyFoodDriveExport.swift:19` | `summaryVersion = "food-intake-summary-v5"` hard-coded | Derived from `FoodIntakeSummary.version` (the existing equality test at `DailyFoodDriveExportTests.swift:127` stays) so the writer cannot drift |
| `WeeklyHealthReport/GoogleDrive/DailyFoodDriveExport.swift:22` | accepted set {v4, v5} | {v4, v5, v6}; files already on Drive keep passing reconcile and recovery |
| `Packages/FoodLedgerKit/Sources/FoodLedgerDomain/FoodIntakeSummary.swift:40,48` | v5 | v6 and its doc comment |
| `WeeklyHealthReport/Models/FoodLogPeriodSummary.swift:8` | describes v5 | Describes v6; the Health report period food summary takes `includesEstimates` from the same v6 day projection, so a day with a guide or milk volume entry reads as including estimates in the report |
| `WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift:509` | describes v5 | Describes v6; `FoodLogPeriodReader` logic unchanged (it already copies `includesEstimates`) |
| `WeeklyHealthReport/FoodLedger/FoodHomeCards.swift:58` | describes v5 plain water rule | Comment names v6 (the plain water rule is unchanged); the Home card's estimate caption now also reflects quantity estimates |
| `FoodIntakeProjection.swift:22`, `FoodLogDayContent.swift:56`, `FoodDailyExport.swift:397` | v5 in comments | v6 in comments; no logic change beyond C6 |

### Dependency direction

Presentation and infrastructure depend on application; application depends on domain. The adapter implements the application-owned port; nothing in domain or application imports Foundation bundles, CryptoKit, GRDB or SwiftUI for this feature. `check-boundaries.sh` is unchanged because no target is added.

### Invariants (closed)

1. A guide is offered only for an allow-listed record and release, unit pieces and a positive finite count; never for grams, millilitres, servings, source-declared servings, recipe servings or pasted-label servings. Applicability is decided by the existing serving policies, not by `unit == .count` alone: no guide when `FoodSourceServingPolicy.applies`, `PastedLabelServingPolicy.servingsOnly` or the source-recipe check holds for the selected candidate (gate G6).
2. Nothing is saved without the Log press; the estimate and the word Estimate are on the primary screen whenever Log would save them, and the Log button says "about".
3. A guide save equals count × the selected size's grams exactly, with that size's code and the guide release; the service resolves the entry itself and refuses anything else, even with the view model bypassed.
4. A guide estimate is always a quantity estimate in every projection; Kitchen scale and Package weight are measured; Estimated by eye stays an estimate. Typed method text is never an estimate without the matching release.
5. Nutrition provenance is untouched: the selected record's nutrients scale from the estimated grams; no USDA nutrient enters a CoFID entry; unknown nutrients stay unknown.
6. Food records stay append-only; edits write a new log version and, for a new amount or size, a new conversion version.
7. No new egress. The ReaderV3Freeze pinned files are out of scope; the authoritative list is `ReaderV3FreezeTests.frozenSources` in `Packages/FoodLedgerKit/Tests/FoodLabelTextCaptureTests/ReaderV3FreezeTests.swift` (gate G5), and `ReaderV3FreezeTests` must pass unchanged as a gate.

### Extension axes (open)

- **More guides**: a new manifest version (`count-portion-guides-v2.json`, codes `count_portion_guide_v2:…`) adds records, sizes or foods after their own source review. No change to the reducer, policy or projections.
- **Another guide source** (a UK or Taiwan table once admitted): a second adapter conforming to the port, composed at the root. v1 has at most one guide set per record; a second source for the same record needs a contract on precedence.
- **More estimate methods** join `FoodQuantityEstimate` only through its closed table, each with its release prefix.
- Not opened: per-food count nouns, a universal portion service, inferred oil or density.

### Contract tests (written first)

1. Adapter: manifest hash pinned; tampered or malformed manifest, a missing size or two defaults throw; exactly the four allow-listed records get a set of four sizes with Large as default; whites, yolks, fried, poached, duck, other releases and rows get none.
2. Calculation: 3 Large gives 150 g, 3 Medium 132 g, 3 Small 114 g, 3 Extra large 168 g; 0.5 pieces (half-item count v1) Large gives 25 g; non-finite or non-positive counts give no estimate.
3. Applicability (F2): no guide for servings, a source-declared serving, a recipe serving, pasted-label servings, g or mL; a switch to a non-allow-listed candidate clears the entry ID and raises `countNeedsMeasuredAmount`; a raw to boiled switch keeps the size.
4. Service closed set (C9, F4): refuses a `count_portion_guide_v…` code that is unknown, names another record or a raw code on a boiled record, carries another release, or grams not equal to count × that size; accepts each exact save; works with the view model bypassed; the state carries no grams.
5. Reopen and edit (F4): each size reopens selected; an unchanged re-save reuses the conversion (no new version) even with an adapter that withdrew the entry; a count change with a withdrawn entry raises `countNeedsMeasuredAmount`; a size change writes a new conversion version.
6. Save and reopen in the memory and GRDB stores and after an archive round trip: code, release and size survive.
7. Byte stability: existing conversion, declaration, release and operation fixtures, including `legacy-v1` and `legacy-v2`, re-encode and verify unchanged; archive food contract and schema identity unchanged.
8. Estimate rule (C6, F6): guide codes with the guide release, the milk rule ID with the PHE release, and estimated declarations are estimates; the same method text without the matching release prefix, `user_count_conversion_v1:*`, measured declarations, typed legacy text and plain grams are not.
9. Summary v6 (F1): a day with a guide entry and a day with a milk volume entry set `includesEstimates` in `FoodIntakeSummary` and in the Daily JSON summary; `summary_version` is `food-intake-summary-v6`; validators and the Drive identity policy accept v4, v5 and v6 and reject an unknown version; the v4 and v5 goldens still decode, re-encode byte for byte and pass; a new v6 golden pins a guide day; entry `weight_basis` for a guide entry is `unknown`.
10. Cross-surface consistency (F7, G2): one guide fixture and one milk fixture produce the same estimate status and amount wording on the Food Log row, saved entry, Recent, Health report food section and Copy all, the matching v6 summary flag, and the same `includesEstimates` on the Health report period food summary (`FoodLogDayFacts` energy and fibre), which reads the same v6 day projection.
11. Method projection table: each row of section 5 maps to its label; legacy typed text renders `Recorded: <text>`.
12. Count word (F5): `FoodAmountNoun` gives `1 piece`, `3 pieces`; servings give `2 servings`. A source scan over `Packages/FoodLedgerKit/Sources/FoodLedgerPresentation`, the application files named `*Presentation*.swift` and `WeeklyHealthReport/FoodLedger` fails on `.unit.rawValue` inside user-facing string interpolation and on the literals `"count"`, `"unit"` and `"units"` used as amount words; persisted, parsed and export uses of `count` are exempt by an explicit named allow-list in the test.
13. Log label (F8): an estimated quantity (guide, estimated by eye, milk volume) reads `Log about 215 kcal`; a measured or direct amount reads `Log 215 kcal`.
14. History: count, size, weight-only, method and no change produce the section 5 strings; "3 pieces to 3 pieces" never appears.
15. Retry recovery, removal and restoration keep the guide conversion.
16. `ReaderV3FreezeTests` passes with no change to the pinned hashes (F10).
17. Manifest and frozen table agree (G3): every manifest entry's code, size, grams and derivation equals the frozen application table, and every frozen code is in the manifest; C9 refuses a save when the port's grams for a code differ from the frozen table.
18. No save without Log (G4): with the pre-fill shown and no Log press, the service records zero saves and the ledger zero writes.
19. Release present (G4): whenever the size choice shows, the guide `SourceRelease` is in `input.sourceReleases`; a guide save whose release is in neither the input nor the store fails closed.
20. Applicability through the serving policies (G6): explicit cases for a source-declared serving, pasted-label servings only, a source recipe, grams and millilitres on an allow-listed record, each with no guide.

## 9. Not changing, or deferred

- **Daily JSON food export entries**: a guide entry exports its edible grams with `weight_basis: "unknown"`. Entry-level estimate and method fields are follow-up **#312** (a food export contract change). Only the summary version and its `includes_estimates` rule change here (C13).
- Health report period aggregation rules, nutrient values, source search and ranking, the query parser, list grammar (`count`, `piece`, `pieces` still parse), plate subtraction, recipe and source servings, pasted-label servings and reader v3.
- Food-specific count nouns, Jumbo, UK or Taiwan egg guides, fried and poached egg guides, guides for any other food, a tappable source link.

## 10. Test plan

- Package tests: contract tests 1 to 16 in `FoodLedgerApplicationTests`, `FoodGenericSearchTests`, the store adapter tests, `FoodLedgerPresentationTests` and the existing Daily JSON food export tests (summary goldens).
- App tests: the Drive identity policy accepting v4, v5 and v6 food summaries; the cross-surface test for Health report and Copy all.
- View-model tests: Large pre-fill appears and enables Log with "Log about"; one tap changes size; count edit recomputes; candidate switch clears; Change and Use typical weight; Estimated by eye stays in the one layout; reopen of each method and size.
- Simulator UI tests: egg 3 pieces logs with Large; egg changed to Medium in one tap; egg corrected by kitchen scale; egg corrected by eye; banana by count shows the no-guide layout and stays blocked until completed.
- Gates from `AGENTS.md`, run singly, plus `ReaderV3FreezeTests` unchanged. FoodSearchQuality and FoodQueryEvaluation are not required because search and query code do not change.
- Data provenance: the PR records the archive hash, the manifest hash and the exact `project_usda_count_portions.py` command used to generate the manifest from the verified local archive.
- Device: none needed for HealthKit (no HealthKit change). The owner checks the copy, the size choice and estimate visibility on device.

## 11. Journey QA checklist

1. Add food, search `3 eggs`, choose "Eggs, chicken, whole, boiled": the Amount shows `3` and `pieces`; `Egg size` lists Small 38 g, Medium 44 g, Large 50 g (selected) and Extra large 56 g, each `about … g each`; the weight row reads `About 150 g`, `Typical weight · Estimate`, `Change`; Log reads `Log about 215 kcal` (or the current kcal) and is enabled.
2. Tap Medium once: the weight row shows `About 132 g` and Log updates; nothing else moves.
3. Open `About this estimate`: USDA source, CC0 note, `US sizes; carton sizes differ by country`, and the boiled-derivation sentence; no tappable link.
4. Change count to 4: the weight row shows `About 176 g` at Medium.
5. Log. Food Log row: `4 pieces · about 176 g` and `Estimate · Typical weight`. Saved entry header: `4 pieces · about 176 g · today, HH:MM` and `Estimate · Typical weight, Medium, about 44 g each · Unknown details stay unknown`. The day total says `includes estimates`.
6. Edit: Medium is still selected. Tap Large and save. History: `Weight changed about 176 g to about 200 g · now Large`.
7. Edit, Change, enter 120 g, choose Kitchen scale, save. History: `Weight changed about 200 g to 120 g · now Kitchen scale`; the header shows `Kitchen scale` and no weight estimate; Log read `Log 172 kcal` (no `about`) before saving.
8. Edit, choose Estimated by eye with 140 g: the screen keeps one amount (the count), no `Use original amount instead`, no second unit picker. Save: Food Log flags `Estimate · Estimated by eye`.
9. Edit, choose `Use typical weight`, save: back to the size choice at the last size.
10. Search `2 eggs` and choose "Eggs, chicken, whole, raw": the same four sizes, without the boiled sentence in details.
11. Search `2 eggs fried`, choose a fried record: no size choice; the one-layout measured flow; Log blocked with `Enter the total weight and how you got it, or change the unit to g or mL.`
12. Search `1 banana`, choose by count: same as step 11 with `1 piece`.
13. Recent on Add food shows `pieces`; relogging the egg opens with its saved size selected.
14. Confirm unit picker, Quick add, Favourites, Common foods, inventory and list import show `pieces`; no screen says `units` or `count` for an amount.
15. Health report food section and Copy all for the day mark the totals as including estimates; Developer tools Food daily export preview shows `summary_version` `food-intake-summary-v6` and the guide entry with `weight_basis` `unknown`.
16. `200ml whole milk` with the volume estimate tapped: after saving, the Food Log row shows `200 mL · about 206 g` and `Estimate · Whole milk volume estimate`.
17. Largest Dynamic Type: the size rows, weight row and Change stay readable and tappable (44 pt); VoiceOver reads them as in section 5.
18. Pasted-label servings still read `servings`.
