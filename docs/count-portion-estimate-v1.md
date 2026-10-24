# Count portion estimate v1 (#307)

Status: **design spec and architecture gate, 24 October 2026. Documents only; no production code has changed.** The owner approved autonomous delivery of #307, including any contract, on 24 October 2026. Owner principle: the app pre-fills, the user validates and corrects, and every estimate stays visible.

This contract amends [count-conversion-method-v1.md](count-conversion-method-v1.md) (a count without a guide asks for a measured amount), [food-confirmation-contract-v5.md](food-confirmation-contract-v5.md) (`countNeedsMeasuredAmount`, the Log press as acceptance) and [direct-edible-weight-contract-v1.md](direct-edible-weight-contract-v1.md) (no guide estimates admitted). It admits the first source-backed count guide that [count-portion-guide-research-v1.md](archive/count-portion-guide-research-v1.md) prepared, and reuses the persistence pattern of [cofid-whole-milk-volume-admission-v1.md](cofid-whole-milk-volume-admission-v1.md).

## 1. Problem (UX review of main 53450fb7, screenshots 20 to 30, 35 and 42)

1. **Eggs by count are blocked behind four fields.** "3 eggs" on Confirm shows "No source-backed size guide is available for this food", then "Converted edible amount", "Converted unit", "How you got this amount" (Choose one) and a warning, and Log stays disabled with "For a count, enter the measured edible weight or volume and how it was measured, or change the unit to g or mL." The commonest count food in the app cannot be logged without a scale or a guess the app gives no help with.
2. **Choosing a method rebuilds the section.** "Estimated by eye" switches to the direct-weight layout: a gram field, "How you got the weight", the note "The original amount below is kept as well…", "Use original amount instead", a second amount field (3) and a second unit picker (count). Two amounts are on screen for one food.
3. **Three words for one count.** The Amount sheet and Recent say "pieces", Confirm's unit picker says "count", and the saved entry and history say "units" ("3 units · 150 g", "Amount changed 3 units to 3 units (150 g to 120 g)").
4. **The method disappears after saving.** The saved entry header shows only "Estimate · Unknown details stay unknown" (a generic-source estimate wins over "The weight was estimated"), the Food Log row shows only "Estimate", and nothing says the weight was estimated by eye, weighed or read from a package. The history line repeats the unchanged count instead of naming what changed.

## 2. Decisions

| ID | Decision |
|---|---|
| C1 | A **count portion guide** is a reviewed, versioned, per-record typical edible weight for one piece, from a cited source. v1 admits exactly one value, a whole chicken egg without shell, 50 g, for four allow-listed raw and boiled records (section 3). Every other food keeps today's measured flow. |
| C2 | When a guide applies to the selected record and the unit is pieces, Confirm **pre-fills** "About 150 g" with "Typical weight, about 50 g each · Estimate" in one row with a **Change** action. Log accepts it, as the v5 Log press accepts everything shown. No separate opt-in tap, no size selector, nothing silently saved. |
| C3 | The pre-fill is a **labelled estimate everywhere**: Confirm, the Food Log row, the saved entry, day totals ("includes estimates"), Recent and the Health report. |
| C4 | Correction is **one layout**: Change opens a single "Total weight" field and "How you got it" (Kitchen scale, Package weight, Estimated by eye). The count stays the only amount on screen; "Use original amount instead" and the second amount and unit pickers are not shown on a count. "Use typical weight" returns to the pre-fill. Foods without a guide use the same single layout, with no pre-fill. |
| C5 | **Persistence reuses existing records only**: a guide save is the existing `QuantityConversionVersion` with a versioned guide code in `methodVersion` and the guide's own `SourceRelease`, exactly as the whole-milk volume estimate is stored. Kitchen scale and Package weight stay `user_count_conversion_v1:*` conversions; Estimated by eye stays a `weightDeclaration` with basis `estimated`. No new field, operation type, archive contract or schema identity. |
| C6 | **Quantity estimate is one pure rule** over stored records: estimated when the weight declaration basis is `estimated`, or the conversion code is an admitted source estimate (the guide v1 codes and the whole-milk volume rule). Every projection that asks "is this quantity an estimate" uses it. |
| C7 | **Quantity method is one pure projection** (`FoodQuantityMethod`) over the log version and its conversion, rendered by one presentation formatter, so Confirm, the Food Log row, the saved entry and history show the same words. |
| C8 | **One count word: "piece" / "pieces"** on every surface (Amount sheet, Recent, Confirm, Quick add, Favourites, Common foods, inventory, list import, Food Log, saved entry, history, VoiceOver). A pasted-label or source serving stays "serving" / "servings", which means something different. Food-specific nouns ("3 eggs") are deferred: they need per-food plural data and would bring variance back. |
| C9 | **Closed set at save**: any `methodVersion` with the prefix `count_portion_guide_v` must be an admitted v1 code, name the selected record, carry the guide's source release and equal count × the guide's grams exactly; otherwise the save fails closed (`invalidQuantity`). |
| C10 | **No new egress, no new nutrient data.** The guide value comes from the USDA SR Legacy April 2018 archive whose hash the app already pins for its USDA nutrition records, projected offline into a small bundled, hash-pinned manifest. The Daily JSON food export is unchanged in v1 (section 9). |

## 3. Source, citation and data provenance

### Admitted value

USDA FoodData Central, SR Legacy, final release April 2018, archive `FoodData_Central_sr_legacy_food_json_2018-04.zip`, SHA-256 `0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef`. This is the same archive, by hash, as the app's bundled `usda-legacy:2018-04-01` nutrition release, so the guide adds a projection of an already admitted artefact, not a new source. The values were read offline from that archive on 27 September 2026 ([research v1](archive/count-portion-guide-research-v1.md)):

| Guide entry | FDC record | Portion ID | Descriptor | Grams for 1 |
|---|---|---|---|---:|
| `usda_sr_legacy_171287_88374` | 171287 Egg, whole, raw, fresh | 88374 | large | 50 |
| `usda_sr_legacy_173424_92500` | 173424 Egg, whole, cooked, hard-boiled | 92500 | large | 50 |

SR Legacy gram weights are for the edible portion ([SR Legacy documentation](https://www.ars.usda.gov/ARSUserFiles/80400525/Data/SR-Legacy/SR-Legacy_Doc.pdf)); the shell is refuse. FoodData Central data are published in the public domain under CC0 1.0 ([FDC documentation](https://fdc.nal.usda.gov/data-documentation/)); the app attributes them anyway.

Only the "large" piece entry is admitted. The cup measure and the other size descriptors on 171287 are not projected, and no size menu is offered. The portion unit ID is the undetermined 9999, so piece semantics rest on the reviewed descriptor and record, recorded in the manifest, not on the unit ID.

### Record allow-list

| Nutrition record (release and record ID) | Guide entry | Basis of the mapping |
|---|---|---|
| `usda-legacy:2018-04-01:…:fdc:171287` Egg, whole, raw, fresh | `usda_sr_legacy_171287_88374` | Same record |
| `usda-legacy:2018-04-01:…:fdc:173424` Egg, whole, cooked, hard-boiled | `usda_sr_legacy_173424_92500` | Same record |
| `cofid:2021:…:row:1096:a72b3e44d2dadad3` Eggs, chicken, whole, raw | `usda_sr_legacy_171287_88374` | Reviewed cross-source: same food, part and preparation |
| `cofid:2021:…:row:1091:0fe190b81c244ccf` Eggs, chicken, whole, boiled | `usda_sr_legacy_173424_92500` | Reviewed cross-source: same food, part and preparation |

Full release IDs are the ones in the bundled `usda-generic-v1.json` and `cofid-2021-generic-search-v1.json`. A different release or row never inherits a guide. Whites, yolks, fried, poached, scrambled, omelette, dried, frozen, duck, quail and turkey eggs, recipes and every non-egg food have no guide in v1. Fried eggs are excluded on purpose: frying changes mass and adds fat, and the app never infers oil.

### Why this value, and its limits

- It is a typical value for a US large egg, not a UK carton size. UK sizes are graded by shell-on weight (medium 53 to under 63 g, large 63 to under 73 g, [APHA egg marketing guidance](https://assets.publishing.service.gov.uk/media/69382d2de447374889cd8f73/EMR01_Guidance_on_legislation_covering_egg_marketing_November_2025.pdf)). The Department of Health 2012 egg sampling report gives averages from which a boiled UK medium egg without shell works out at about 52 g and a large one at about 58 g ([research v1](archive/count-portion-guide-research-v1.md)). That report is corroboration only; it is not admitted, and no UK figure is shown or stored.
- 50 g is therefore close to a UK medium egg and may under-read a UK large one by about a seventh. This is why the value is always shown as "about", always labelled an estimate, and corrected in one tap.
- The app never shows the word "large", which would read as a UK size. The details disclosure names the source size honestly.

### Projection tooling and manifest

- New developer tool `Tools/FoodSourceEvaluation/project_usda_count_portions.py` takes a **local path** to the archive, verifies its SHA-256 equals `0fe8ae48…`, reads the two named records and portions, refuses if either value differs from the table above, and writes `Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources/count-portion-guides-v1.json`. It never downloads; the developer fetches the archive from the FDC downloads page. App egress is unchanged.
- **Implementation precondition:** the archive copy used for the research (`/private/tmp/whr-source-probe/…`) no longer exists. The implementing phase must re-obtain the archive, confirm the hash and re-read both portions with the tool before writing any production code. If either value differs, stop and report; do not adjust the value.
- Manifest fields: `guide_set_id` (`count-portion-guides-v1`), `source` (title, archive file name, archive SHA-256, licence `CC0 1.0`, attribution text, documentation URL), and per guide `guide_id`, `source_fdc_id`, `source_portion_id`, `source_descriptor`, `source_grams`, `part` (`whole_without_shell`), `preparation` (`raw` or `boiled`), and `applies_to` (release ID and record ID pairs from the allow-list). The adapter pins the manifest's SHA-256 in code, as the milk rule does, and rejects any mismatch or malformed entry.
- Guide `SourceRelease`: `sourceReleaseID = usda-sr-legacy-portions:2018-04-01:sha256:0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef`, `sourceID = usda-sr-legacy-portions`, `artifactHash` = the archive hash, `manifestHash` = the guide manifest hash, `pipelineVersion = count-portion-guides-v1`, `schemaVersion = count-portion-guide-v1`, licence and attribution from the manifest. It is deliberately distinct from the nutrition release ID so the two release records never collide.

## 4. Behaviour

### Confirm, guide available (egg, unit pieces)

1. The selected record is on the allow-list and the unit is pieces with a positive count. The view model asks the guide port, which returns the guide; the reducer sets a **pending guide estimate** (not a conversion yet) with total = count × 50 g.
2. The amount section shows the count once and the estimate row. Log is enabled (no `countNeedsMeasuredAmount`), and the button reads "Log 215 kcal" from the estimated total.
3. Pressing Log saves the estimate as a guide conversion (section 6). This is the explicit acceptance of the displayed estimate.
4. Changing the count recomputes the estimate (it is derived, never typed). Changing the candidate or preparation recomputes or clears it: a record without a guide falls back to the measured flow with nothing pre-filled.
5. **Change** opens the correction layout below with "Total weight" empty and "How you got it" at "Choose one". The estimate is no longer applied while the correction is open; **Use typical weight** restores it.

### Confirm, correcting or no guide (one layout)

- Rows: amount and unit (count once), "Total weight" with g / mL, "How you got it" (Kitchen scale, Package weight, Estimated by eye), "Weighed on a plate".
- Kitchen scale and Package weight save `user_count_conversion_v1:*` conversions exactly as count-conversion-method-v1 says.
- Estimated by eye saves the existing estimated weight declaration with the count as original input. The reducer still uses the direct-weight draft; the **presentation** keeps the correction layout and does not show the direct-weight block, "Use original amount instead" or a second amount. Estimated by eye with mL shows a field-local message (estimates are in grams) and blocks Log.
- Requirements are unchanged in kind: `countNeedsMeasuredAmount`, `measuredWeightMissing`, `weightBasisMissing` and the plate requirements keep their meaning; their copy changes (section 5).

### Reopen and edit

- A saved guide entry reopens with the guide row, showing the stored per-piece weight (converted ÷ count) and Change. Re-saving without changes writes the same code, release and grams.
- If the guide port no longer offers the stored guide (a later manifest withdrew it), the stored entry still displays from its stored values and label; editing the count then needs a measured amount, as for any food without a guide. Nothing is relabelled.
- Entries saved before this contract keep their meaning and labels (section 7).

### After saving

- Food Log row: amount line "3 pieces · about 150 g"; flags "Estimate · Typical weight" (plus any unknown-nutrient flags).
- Saved entry header: "3 pieces · about 150 g · today, 13:00", then the estimate line (section 5).
- History: names what changed, never a repeated unchanged count.

## 5. Copy (British spelling, no emoji)

### Confirm

| Element | Text |
|---|---|
| Unit picker option for counts | `pieces` |
| Guide row title | `Weight` |
| Guide row value | `About 150 g` |
| Guide row subtitle | `Typical weight, about 50 g each · Estimate` |
| Guide row action | `Change` |
| Guide row VoiceOver | `Weight, about 150 grams, typical weight, about 50 grams each, estimate. Change` |
| Guide details disclosure title | `About this estimate` |
| Guide details text | `Typical weight of one egg without shell: 50 g, from USDA FoodData Central SR Legacy (April 2018), egg listed as large. US and UK egg sizes differ, so your eggs may weigh more or less. Change it if you know the weight.` |
| Guide details source line | `Source: USDA FoodData Central, SR Legacy, April 2018 · public domain (CC0 1.0)` |
| Correction layout field | `Total weight` with placeholder `Without shell, bone or skin you did not eat` |
| Correction layout picker | `How you got it`: `Kitchen scale`, `Package weight`, `Estimated by eye`; start `Choose one` |
| Return to guide (guide foods only) | `Use typical weight` |
| No-guide intro (replaces "No source-backed size guide is available…") | `Enter the total weight you ate, without shell, bone or other parts.` |
| Field-local, weight missing | `Enter the total weight.` |
| Field-local, method missing | `Choose how you got the weight.` |
| Field-local, estimate in mL | `Estimates are in grams. Enter the weight in g.` |
| Log bar, `countNeedsMeasuredAmount` | `Enter the total weight and how you got it, or change the unit to g or mL.` |

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
- Saved entry header line 2 combines both estimate kinds once: `Estimate · Typical weight, about 50 g each · Unknown details stay unknown`, or `Estimate · Estimated by eye`, or `Estimate · Unknown details stay unknown` when only the source is an estimate. Measured methods add their label without `Estimate`: `Kitchen scale`.
- Food Log row VoiceOver: `13:00, Eggs, chicken, whole, boiled, 3 pieces, about 150 grams, 215 kcal, estimate, typical weight`.
- History lines:
  - count changed: `Amount changed 3 pieces to 4 pieces (about 150 g to about 200 g)`
  - only the weight changed: `Weight changed about 150 g to 120 g`
  - the method changed: append ` · now Kitchen scale` (or the new method label), for example `Weight changed about 150 g to 120 g · now Kitchen scale`
  - nothing changed: `Saved again without changes` (unchanged)
- Recent: `3 pieces` (already "pieces"); a guide entry relogged from Recent opens Confirm with the guide pre-fill recomputed for the current guide set.

## 6. Persistence

| Save | Records written | `methodVersion` | `sourceReleaseID` | Operation |
|---|---|---|---|---|
| Typical weight | `QuantityConversionVersion` (source 3 count, converted 150 g) plus the guide `SourceRelease` on first use | `count_portion_guide_v1:usda_sr_legacy_173424_92500` (or `…171287_88374`) | `usda-sr-legacy-portions:2018-04-01:sha256:0fe8…` | unchanged (`confirm_food_v1`/`v3` per v5) |
| Kitchen scale, Package weight | as count-conversion-method-v1 | `user_count_conversion_v1:*` | empty | unchanged |
| Estimated by eye | `weightDeclaration` basis `estimated` | none | none | `confirm_food_v2`/`v3` as today |

- `evidenceID` is empty on a guide conversion, as on the milk rule; the code names the record and portion, and the release pins the archive and manifest.
- The shown label is a pure function of the code family. The frozen v1 code table lives in the application layer, so a stored v1 code always has a label even if a later adapter withdraws the guide. A new value, record or wording needs `count_portion_guide_v2:…`.
- **No persisted format changes.** No new field, operation type, registry entry, archive food contract, SQLite schema identity or migration. Existing records decode, re-encode and verify byte for byte. Older binaries already accept arbitrary `methodVersion` text and conversion source releases (the milk rule), so archives stay importable at the same contract version.
- Estimate status, method and amount wording are derived at read time and never stored.

## 7. Records written before this contract

- Typed legacy methods, `user_count_conversion_v1:*` codes, estimated and measured declarations and milk conversions keep their bytes. Only their **derived** display changes: the method label appears on the Food Log row and saved entry, and milk volume conversions become visible estimates (C6), which they always were on Confirm.
- "units" disappears from display; stored units are the raw `count` value and do not change.

## 8. Architecture gate

### Responsibilities

| Layer | Owns |
|---|---|
| Domain (`FoodLedgerDomain`) | Nothing new. `QuantityConversionVersion`, `EdibleWeightDeclaration`, `PositiveQuantity` and `FoodIntakeContribution.quantityIsEstimate` already exist. |
| Application (`FoodLedgerApplication`) | `CountPortionGuideMethod` (frozen v1 code table, `admits`, code parsing, the closed-set rule of C9); `FoodQuantityEstimate.isEstimate(log:conversion:)` (C6); `FoodQuantityMethod` projection (C7); reducer state for the pending guide estimate, Change and Use typical weight; `FoodLogPolicy` treating a pending guide estimate as satisfying `countNeedsMeasuredAmount`; service save-time verification (recompute count × grams through the injected port, check record, release and code); the existing consumer-owned port `FoodEdibleWeightGuideProviding` and value `FoodEdibleWeightGuide`, reused; projections (`FoodIntakeProjection`, `FoodLogDayContent`, `SavedFoodEntryDetail`, `FoodRecentItems`, `FoodEntryHistory`) switched to the shared rules. |
| Infrastructure (`FoodGenericSearch`) | `USDACountPortionGuides` adapter: loads and hash-verifies `count-portion-guides-v1.json`, builds the guide `SourceRelease`, answers the allow-list. No network, no other data. |
| Presentation (`FoodLedgerPresentation`) | Guide row, correction layout, disclosure; one `FoodAmountText` formatter for the count word and amount line; method labels and history wording in `FoodLogText`; requirement copy in `FoodLogRequirementText`. |
| Composition root | Injects the adapter into the Confirm view model and `FoodConfirmationService`, next to the milk offering. |

### Dependency direction

Presentation and infrastructure depend on application; application depends on domain. The adapter implements the application-owned port; nothing in domain or application imports Foundation bundles, CryptoKit, GRDB or SwiftUI for this feature. `check-boundaries.sh` is unchanged because no target is added.

### Invariants (closed)

1. A guide estimate is offered only for an allow-listed record and release, unit pieces and a positive finite count; never for grams, millilitres, servings, recipes or source-declared servings.
2. Nothing is saved without the Log press; the pre-fill is visible on the primary screen with "Estimate" whenever Log would save it.
3. A guide save equals count × guide grams exactly, with the admitted code and guide release; the service recomputes and refuses anything else, even with the view model bypassed.
4. A guide estimate is always a quantity estimate in every projection; a user correction to Kitchen scale or Package weight is measured; Estimated by eye stays an estimate.
5. Nutrition provenance is untouched: the selected record's nutrients scale from the estimated grams; no USDA nutrient enters a CoFID entry; unknown nutrients stay unknown.
6. Food records stay append-only; edits write a new log version and, for a new amount, a new conversion version.
7. No new egress. The ReaderV3Freeze pinned files are not touched.

### Extension axes (open)

- **More guides**: a new manifest version (`count-portion-guides-v2.json`, codes `count_portion_guide_v2:…`) adds records or foods after their own source review. No change to the reducer, policy or projections.
- **Another guide source** (for example a UK or Taiwan table once admitted): a second adapter conforming to `FoodEdibleWeightGuideProviding`, composed at the root. The port returns at most one guide per record in v1; a second source for the same record needs a contract on precedence.
- **More estimate methods** join `FoodQuantityEstimate` only through its closed table.
- Not opened: size menus, per-food count nouns, a universal portion service, inferred oil or density.

### Contract tests (written first)

1. Adapter: manifest hash pinned; tampered or malformed manifest throws; exactly the four allow-listed records get a guide; whites, yolks, fried, poached, duck, other releases and rows get none.
2. Calculation: 3 pieces gives 150 g; 0.5 pieces (half-item count v1) gives 25 g; non-finite or non-positive counts give no estimate.
3. Policy: a pending guide estimate clears `countNeedsMeasuredAmount`; without a guide the requirement stays; Change without a method or weight blocks with the same requirements as today.
4. Service closed set: refuses a `count_portion_guide_v…` code that is unknown, names another record, carries another release or grams not equal to count × 50; accepts the exact save; works with the view model bypassed.
5. Save and reopen in the memory and GRDB stores and after an archive round trip: the conversion carries the code and release; reopen restores the guide row; re-save without changes writes the same values.
6. Byte stability: existing conversion, declaration, release and operation fixtures, including `legacy-v1` and `legacy-v2`, re-encode and verify unchanged; archive food contract and schema identity unchanged.
7. Estimate rule table: guide code, estimated declaration and milk rule are estimates; `user_count_conversion_v1:*`, measured declaration, typed legacy text and plain grams are not. Every projection named in section 8 uses it (day totals "includes estimates", saved entry, Recent, Food Log flags, Health report food totals).
8. Method projection table: each row of section 5 maps to its label; legacy typed text renders `Recorded: <text>`.
9. Count word: formatter outputs `1 piece`, `3 pieces`, `2 servings`; a source scan test fails if presentation code contains a user-facing `"units"`, `"unit"` for counts or a `Text("count")` tag.
10. History: count change, weight-only change, method change and no change produce the section 5 strings; "3 pieces to 3 pieces" never appears.
11. Retry recovery and removal and restoration keep the guide conversion.
12. Daily JSON food export bytes for a guide entry match v1 expectations (unit g, `weight_basis` `unknown`), so the export contract is untouched.

## 9. Not changing, or deferred

- **Daily JSON food export v1** stays as is: a guide entry exports its edible grams with `weight_basis: "unknown"`, which is true because there is no weight declaration. Exporting the guide as `estimated` needs a food export v2. Deferred; see the owner question in the handover.
- Health report aggregation, nutrient values, source search and ranking, the query parser, list grammar (`count`, `piece`, `pieces` still parse), plate subtraction, recipe and source servings, pasted-label servings and reader v3.
- Food-specific count nouns, size menus, UK or Taiwan egg guides, fried and poached egg guides, guides for any other food.

## 10. Test plan

- Package tests: contract tests 1 to 12 in `FoodLedgerApplicationTests`, `FoodGenericSearchTests`, store adapter tests and `FoodLedgerPresentationTests`.
- View-model tests: guide pre-fill appears and enables Log; count edit recomputes; candidate switch clears; Change and Use typical weight; Estimated by eye stays in the one layout; reopen of each method.
- Simulator UI tests: egg 3 pieces logs with the pre-fill; egg corrected by kitchen scale; egg corrected by eye; banana by count shows the no-guide layout and stays blocked until completed.
- Gates from `AGENTS.md`, run singly; FoodSearchQuality and FoodQueryEvaluation are not required because search and query code do not change.
- Device: none needed for HealthKit (no HealthKit change). The owner checks the copy and the estimate visibility on device.

## 11. Journey QA checklist

1. Add food, search `3 eggs`, choose "Eggs, chicken, whole, boiled": the Amount shows `3` and `pieces`; one row reads `Weight · About 150 g`, `Typical weight, about 50 g each · Estimate`, `Change`; Log reads `Log 215 kcal` (or the current kcal) and is enabled.
2. Open `About this estimate`: source, CC0 note and the US / UK size sentence are shown; no "large" appears outside it.
3. Change count to 4: the row shows `About 200 g`; nothing else moves.
4. Log. Food Log row: `3 pieces · about 150 g` and `Estimate · Typical weight`. Saved entry header: `3 pieces · about 150 g · today, HH:MM` and `Estimate · Typical weight, about 50 g each · Unknown details stay unknown`.
5. Edit, Change, enter 120 g, choose Kitchen scale, save. History: `Weight changed about 150 g to 120 g · now Kitchen scale`; header shows `Kitchen scale` and no weight estimate.
6. Edit, choose Estimated by eye with 140 g: the screen keeps one amount (the count), no `Use original amount instead`, no second unit picker. Save: Food Log flags `Estimate · Estimated by eye`.
7. Edit, choose `Use typical weight`, save: back to the guide estimate.
8. Search `2 eggs fried`, choose a fried record: no pre-fill; the one-layout measured flow; Log blocked with `Enter the total weight and how you got it, or change the unit to g or mL.`
9. Search `1 banana`, choose by count: same as step 8 with `1 piece`.
10. Recent on Add food shows `3 pieces`; relogging it shows the pre-fill again.
11. Confirm unit picker, Quick add, Favourites, Common foods and list import show `pieces`; no screen says `units` or `count` for an amount.
12. Day total on Food Log and Home reads `includes estimates` when a guide entry is in the day.
13. Largest Dynamic Type: the guide row and Change stay readable and tappable (44 pt); VoiceOver reads the row as in section 5.
14. Pasted-label servings still read `servings`.
