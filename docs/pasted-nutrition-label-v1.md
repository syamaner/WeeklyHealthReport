# Pasted nutrition label v1 (#93)

Status: **owner-approved, gate passed with changes, assisted-UX principle applied, 18 October 2026.** All twelve decisions in section 10 were decided by the owner, in session, on 18 October 2026; decisions 6 (convert kJ-only energy and salt-only sodium, labelled as calculated) and 12 ("Report a misread" in v1, as a user-initiated share) were **changed from the recommendation**. The architecture gate on `f58b8048` returned PASS WITH CHANGES; every finding is applied here (section 8.7), and the owner approved, in session on 18 October 2026, the two items that needed sign-off: totals with a calculated contribution set `includesEstimates` under `food-intake-summary-v3` (section 3.5), and the identity mapping `pasted-label-identity-v1` (section 6.5). The same day, in session, the owner set the **assisted-UX principle** (section 1.1), which turns partial tables into visible exceptions and lets the user correct any value before Log; it adds decision 13, since answered by the owner (no). The owner approved drafting it on 18 October 2026, after route A of the label-capture evaluation (#255) passed every reader bar on its untouched synthetic pasted-text cases. It is the "independent promotion" that evaluation decision 11 allows, for route A only. No photo route (B or C) is proposed here. Nothing here adds an app-controlled destination. The user-initiated misread report extends what the existing clipboard and share-sheet row describes; the exact privacy document wording is approved here and ships with the implementation, not with this contract (section 7).

**Launch scope (decisions 3, 4 and 11):** Taiwan 營養標示 text ships first. UK English ships only after at least 20 real public UK label texts read with zero wrong values. US "Nutrition Facts" layouts decline in v1.

This contract composes with, and does not amend, [food confirmation v5](food-confirmation-contract-v5.md) (`food_confirmation_v5`), the [food identity and nutrition contract](food-identity-nutrition-contract.md), the [review manifest v2](generic-food-review-manifest-v2.md) and [UX revamp v1](ux-revamp-v1.md). The evaluation it relies on is [`nutrition-label-capture-evaluation-v1.md`](nutrition-label-capture-evaluation-v1.md); its phase 5 results are on PR #260's branch `feat/255-label-eval-phase-5`, cited by path below.

## 1. Evidence this contract rests on, and its limits

| Evidence | What it shows | Where |
|---|---|---|
| Route A, untouched pasted text, run once on 18 October 2026 | 107 synthetic Taiwan cases (75 FDA dataset 188, 32 closed-template, 15 required declines). 1093/1093 strict cells, 1123/1123 bindings, 92/92 tables, 599/599 serving conversions, 92/92 servings per pack, 36/36 bounds, 15/15 declines, 0 false-ready, 0 false declines, 0 automatic persistence | `Tools/NutritionLabelCaptureEvaluation/results/untouched-taiwan-v1.md` section 6, on `origin/feat/255-label-eval-phase-5` |
| Arithmetic mutation detection on the same truth | 110/116: tenfold serving 69/72, basis transposition 32/35, bound replaced by exact 9/9. **6 planted mutations pass the tolerance.** The bar (100%) fails; it measures the shared arithmetic policy, not the parser | same file, section 6 |
| Route A, English development text | 191 usable tables and 16 declines rendered from the reviewed v1 and v2 development truth, all exact. **Development evidence only**: the parser and renderer were built against these cases | `Tools/NutritionLabelCaptureEvaluation/results/route-a-development-v1.md` |
| Parser | `nutrition-label-text-parser-v2`, Swift target `NutritionLabelParsing`, Foundation only | `Packages/FoodLedgerKit/Sources/NutritionLabelParsing/` (on `main`) |
| Decline gate | `label-capture-decline-gate-v2`, in Python, formats `taiwan_nutrition_labelling` and `uk_nutrition_declaration` only | `Tools/NutritionLabelCaptureEvaluation/decline_gate.py` (on the PR #260 branch) |

Limits that carry into the product:

- **Every evaluated case is synthetic.** It was rendered from verified values in known paste shapes by the same generator family the parser was developed against. Real copy-and-paste text from web pages, PDFs and messages is **unmeasured** (evaluation section 3.5). A clean result on synthetic text is not a real-world accuracy rate, and 0 false-ready on 107 cases is not proof of a zero rate.
- **The untouched pass is Taiwan only.** No untouched English pasted-text case was run. English rests on development evidence (decision 3).
- **There is no US gate format.** Gate v2 knows UK and Taiwan mandatory rows only, so a US "Nutrition Facts" paste has no decline gate to run under (decision 4).
- **Parser v2 passes fullwidth digits through.** It matches digits with `\d`, so a value printed with fullwidth digits (for example `熱量 １５０大卡`) reaches `decimal_text` as `１５０`. Gate v2's schema allows ASCII digits only, so such a candidate is `failed_candidate` and the reading is a hard decline (`unreadable_table`), never a misread value. Normalising fullwidth digits is follow-on parser work under the assisted-UX principle (a new parser version) and the owner's decision; v1 does not change parser v2 (found in PR 1, 18 October 2026).
- **The arithmetic check misses some planted errors.** It is a warning only here (section 4). Its silence is never evidence that a table is right.
- **Cell-level truth on the untouched photo set has an unknown error rate** (the owner's caveat of 18 October 2026). Route A's text cases were rendered from FDA dataset 188 and templates, not from that photo truth, so this caveat does not change route A's figures, but the general lesson stands: one reviewer can miss an error.

### 1.1 The assisted-UX principle (owner, in session, 18 October 2026)

The UX supports the user. Recognition does most of the work and says so with a plain disclaimer. The user validates the result and can optionally correct it. Every estimate or exception is visible. It is not binary: a table is not either "accepted" or "declined" as a whole, and each value carries its own origin.

### 1.2 What the evaluation's bars mean here

The evaluation's binary bars (false-ready, correct decline, full-table exact) measured **fully automatic reading**: whether a route could be trusted to offer a table with no human check. That is the right test for deciding whether to build a route at all, and route A passed it on synthetic Taiwan text. In this assisted design the user checks every value on Confirm before Log, so after release the relevant measures are different:

- **Correction burden:** how many values a user has to correct or enter per table, and the share of tables that need any correction.
- **Residual errors after the user's check:** values that are still wrong after the user looked at them and tapped Log.

Neither can be collected from users automatically (no telemetry, section 9). They are measured in the owner's release gate and local regression, where the owner acts as the user and counts corrections and residual errors, and they can be informed by misread reports users choose to share.

## 2. User journey

One intent, "log a packaged food from its nutrition label", one journey, ending on the shared Confirm screen with one Log action ([UX revamp v1](ux-revamp-v1.md), rule 1).

```
Add food ── Paste nutrition label ── Label text ──(Read label)──┬── Confirm ── Log
                                         ▲                       │
                                         └──── Declined (reason, text kept) ◄┘
```

### 2.1 Add food

Add food gains one row, **Paste nutrition label**, beside barcode, paste or dictate and favourites. It is a separate row from "Paste or dictate" because the intents differ: a food list names several foods by words and amounts; a label declares the nutrition of one food (decision 1).

### 2.2 Label text screen

- A **Name** field (required, plain text, for example "Oat granola"), and an optional **Brand** field. A pasted label rarely names the product, and the saved food needs a name the user can find again. These are identity fields, not nutrient fields; there is still no blank nutrient-entry form (#86).
- An optional **Fortified?** Yes / No choice ("Does the pack say vitamins or minerals are added?"), unanswered by default. It feeds the identity mapping (section 6.5); if it is left unanswered, Confirm raises the existing `sourceIdentityMissing` requirement and the existing "Add food details" flow resolves it.
- A multi-line **Label text** field. The user pastes or types the table. The text stays editable.
- A short line under the field: "Paste the nutrition table only. The text you read is saved with the entry as its source, on this device."
- **Read label** runs the on-device reader (section 2.4). It is disabled while Name or Label text is empty, or the text is over the length limit (section 6.2).
- "Leave without saving" writes nothing. Text that is never logged is not retained, not hashed and not logged anywhere.

### 2.3 Confirm

The shared Confirm screen, with its `food_confirmation_v5` requirements, amount, time and Log action unchanged. The route supplies the source section:

- **Disclaimer,** one plain line at the top of the source section: "Read automatically from your text. Check each value against the label." There are no confidence scores and no "checked" badge.
- **Origin on every value,** from the single `NutrientValueOrigin` projection (section 3.5): **printed**, **calculated**, **corrected by you**, **entered by you**, or **not read** / **not stated** (unknown). Origin is shown in words, not only by colour or symbol.

- **Source line:** "From pasted label · per 100 g" (or per 100 ml, or per serving), with the label language ("English, UK layout" or "Traditional Chinese, Taiwan layout").
- **Values, each beside its source text.** One row per stored nutrient: the stored value, then the printed label and printed value exactly as pasted, for example `Fat 3.2 g` beside "Fat · 3.2g", or `Saturated fat 1.1 g` beside "飽和脂肪 · 1.1公克". Bounds read as printed: "Less than 0.1 g" beside "<0.1g".
- **Basis** of the stored values: per 100 g, per 100 ml or per serving (section 6.3 says which column is stored).
- **Serving size and servings per pack** as printed, with the parsed amount: "Serving size 30 g (printed: Serving size 30g)", "Servings per pack about 8 (printed: Servings per container about 8)", "本包裝含 2.5 份". Absent lines read "Not stated".
- **Not stated:** every app nutrient the label does not print reads "Not stated". It is unknown, never zero.
- **Calculated values** (section 3.5): a kcal value calculated from printed kJ, or a sodium value calculated from printed salt, reads with a "Calculated" tag and its printed source beside it, for example `Energy about 370 kcal · Calculated` beside "Energy · 1550kJ (printed), kcal = kJ ÷ 4.184", or `Sodium about 240 mg · Calculated` beside "Salt · 0.6g (printed), sodium = salt ÷ 2.5". It is never shown as printed.
- **Read but not used:** printed rows the ledger does not store (a kJ value beside a printed kcal value, salt beside printed sodium, % RI or %DV columns, unrecognised rows) are listed with their printed text and "Not used", so nothing printed vanishes silently (section 3.4).
- **Other column:** when a second amount column was printed (for example per serving beside per 100 g), its values are shown under a disclosure as evidence, read-only.
- **Warnings** (non-blocking, section 4), above the Log bar.
- **Report a misread** (section 9.1), a secondary action that only opens a preview the user can share or cancel.
- **Pasted text:** the whole text, read-only, behind one disclosure.
- **Correct a value.** Every recognised value in the stored column (printed or calculated) can be edited before Log. An edited value reads "Corrected by you", with the recognised value and its printed source text still shown beside it. Editing a calculated value makes it "Corrected by you" and it is no longer calculated.
- **Enter a value that was not read.** A row shown as an exception ("Not read: sodium. Add it, or leave it unknown.") or a "Not stated" nutrient can be filled in; it then reads "Entered by you". Leaving it alone keeps it unknown, never zero.
- **This is correction of a pre-filled panel,** read from the user's own label text, not the blank nutrient-entry form that #86 excludes: Confirm opens only after the reader found a nutrition table, and every entry sits beside the recognised row and text it corrects or completes.
- **Edit label text** returns to the label text screen with the text and name kept, so the user can also fix a misread by editing the text and reading it again. If the user has corrected or entered any value, **Read again** first asks: "Reading the text again replaces your corrections." with **Read again** and **Cancel**; corrections are cleared only after that confirmation.

The user picks the amount and taps Log. Amount options, built only from printed facts:

- grams or millilitres, matching the stored basis (the existing per 100 g with mL notice still applies);
- **servings**, only when a serving size with a quantity and unit is printed (or corrected or entered by the user on Confirm, shown with that origin): on a per-serving column under `pasted-label-serving-v1`, and on a per 100 g (per 100 ml) column under `pasted-label-serving-v2` only when the serving size is exact (not printed as "about") and in grams (millilitres), the unit of the stored basis (section 6.3; owner, in session, 19 October 2026);
- **whole pack**, only when servings convert through a serving size in grams or millilitres (a per-serving column under `pasted-label-serving-v1`, or a per 100 g or per 100 ml column with a qualifying serving size under `pasted-label-serving-v2`), and servings per pack is either printed as an exact number (not "about") or, when the label prints none, entered by the user on Confirm (shown "Entered by you"; owner, in session, 19 October 2026). A whole pack is logged as that many servings, through the same servings conversion as any servings amount on that label; the conversion cites the pasted release and the manifest evidence, which holds the correction record for an entered count. Its caption names the serving size's origin (printed, corrected by you or entered by you). Neither method is bumped by the whole-pack option: the recorded conversion for n servings is unchanged, and the option only chooses n. A conversion cannot name the correction record itself, because the quantity conversion record has no field for it; citing it directly would be a store-format change.

Log follows `food_confirmation_v5` exactly: it is the explicit acceptance of the food, amount, time and source shown at that moment, and it is the only save. A parse result, a warning, a passed check or the absence of a warning never saves and never enables Log by itself.

### 2.4 The reader

Read label runs, on device and in this order, with no network, clock or randomness dependency:

1. `nutrition-label-text-parser-v2` (unchanged) on the exact text;
2. the decline gate ported to Swift (section 8.2), which never changes a value; its G1 and G2 findings are hard declines and its G3 to G6 findings become Confirm flags (section 3.2), then `PastedLabelLaunchScope` (section 5);
3. the labelled conversions (section 3.5), only for kJ-only energy and salt-only sodium;
4. the arithmetic and consistency checks (section 4) on printed values, which may add warnings but never change, fill or remove a value.

A hard decline (section 3.1) keeps the user on the label text screen. Anything else opens Confirm, with the gate's partial-table findings shown there as exceptions (section 3.2).

## 3. Declines, partial tables and unknowns

### 3.1 Hard declines: input that cannot be used

Only input that cannot be used declines. A hard decline stays on the label text screen, with the text kept and a plain reason above the field. Codes are for Developer tools only.

| Reason codes | Why it cannot be used | Copy |
|---|---|---|
| `not_a_food_nutrition_panel` (gate G2) | A supplement or non-food panel | "This looks like a supplement panel, which the app does not read." |
| `unsupported_language`, `unsupported_script` (parser, gate G1) | Outside the reader's languages | "This label is in a language the app cannot read yet. It reads <supported layouts> labels." (from `PastedLabelLaunchScope`: "Traditional Chinese (Taiwan layout)" at launch) |
| `no_table` | No nutrition table at all | "No nutrition table was found in this text." |
| `layout_not_supported`, `format_ambiguous` (section 5) | Launch scope: UK and US are not yet enabled, or the layout cannot be told | "The app cannot read this label layout yet. It reads <supported layouts> labels." |
| `basis_state_not_supported` (section 6.5) | An identity difference: values for the food as prepared or drained | "This table is for the food as prepared or drained (for example 沖泡 or 瀝乾). The app reads values for the food as sold only." |
| `multiple_panels`, `no_basis_header`, `duplicate_basis`, `count_mismatch`, `values_without_row`, `energy_without_unit`, `value_without_unit`, `unrecognised_unit` (parser v2) | Parser v2 returns no cells for these: the values cannot be bound safely to rows, columns or units, which is the failure #93 recorded | "The app could not match the values in this text to their rows and columns. Check that it is one table with each value on its row, then try again." |
| `text_too_long` | Over the length limit | "This text is too long to be one nutrition table. Paste the table only." |
| `unreadable_table` (fallback) | Any code without its own copy | "The app could not read this table. Check that it is one nutrition table, then try again." |

`basis_state_not_supported` stays a decline in v1 because it is an identity difference, not a reading gap; it can become an assisted choice later (for example "These values are for the food as prepared"), under a new identity mapping version.

The parser v2 group is a hard decline only because parser v2 returns a declined candidate with no cells for it. Turning those into per-cell exceptions needs a parser that returns the cells it could bind, which is a new parser version with its own evaluation (section 8.5); it is not part of v1.

**Every code maps to copy.** The renderer maps every parser decline code, every gate code and every route code; a gate code that is a flag (section 3.2) maps to its exception copy, and any code it does not know renders `unreadable_table`. A contract test enumerates every code the parser and gate can emit and fails on any code without its own mapping (section 8.4, test 27).

### 3.2 Partial tables: visible exceptions on Confirm, not declines

The gate stays a faithful port and still emits G3 to G6; the application turns them into **flags shown on Confirm**, each on the row or line it concerns:

| Gate finding | Shown on Confirm |
|---|---|
| G3 `required_row_missing` (a mandatory row of the layout has no amount) | "Not read: <row>. Add it, or leave it unknown." on that row |
| G4 `column_count_mismatch` (a mandatory row is missing a per 100 g or ml value) | "Not read: <row>, <column>. Add it, or leave it unknown." on that cell |
| G5 `required_basis_missing` (a UK table without a per 100 g or ml column) | "No per 100 g or per 100 ml values were read." above the values; the stored column falls back to per serving (section 6.3) |
| G6 `required_serving_declaration_missing` (a Taiwan table without its serving lines) | "Not read: serving size" or "Not read: servings per pack. Add it, or leave it unknown." on that line |

- The user can fill a flagged value ("Entered by you") or leave it unknown. Nothing is filled automatically.
- **Servings per pack (G6, owner, in session, 19 October 2026).** When the label prints no servings-per-pack line, the user can enter it as an exact positive number of servings. It is recorded as an `entered` correction record (`nutrient` `servings_per_pack`, unit `count`, `row_id` and `recognised` null) and resolves its flag. It sets no nutrient and no basis, and a printed line is never overwritten. It does feed the whole-pack amount option (section 2.3).
- **Trans fat (G3 on a Taiwan table).** The owner decided on 19 October 2026 that a missing 反式脂肪 row should be fillable. It is not fillable yet: the ledger's nutrient catalogue has no trans fat key, and adding one changes the closed catalogue (`NutrientSet` requires exactly the catalogue keys, so every stored record would stop decoding). It is follow-up work after pasted labels ship, under a versioned nutrient catalogue (#270); until then the flag is shown and the row stays unknown.
- **Unknown is never zero, and totals stay known minimums.** An unknown row marks the affected day and report totals incomplete under the existing summary rules; the known subtotal stays labelled as a known minimum.
- A flag never blocks Log. The existing `food_confirmation_v5` requirements still apply: for example, logging by servings needs a serving size, so an unread serving size limits the amount options until the user adds it.
- Flags shown at Log are recorded in the manifest (`flags_shown`).

### 3.3 What the user can do after a hard decline

- **Edit the text** and read it again (the text and name stay in the fields).
- **Paste again** (clear and paste).
- **Use another route:** Search or Barcode from Add food, each a one-tap link under the reason.
- **Report a misread** if the user thinks the decline is wrong (section 9.1); nothing is sent unless the user shares it.

A decline writes nothing to the ledger, keeps no copy of the text after the screen closes, and records nothing except, while the screen is open, the reason codes in Developer tools.

### 3.4 Unknowns and what is never inferred

- **Never silently completed.** No value is inferred, back-filled or defaulted to complete a table: no % RI to an amount, no per-serving value to per 100 g (or the reverse), no value copied from the other column, no zero for a missing row. The only conversions are the two labelled ones in section 3.5, and they are never silent.
- **Not printed means unknown.** A nutrient the label does not print is stored as `unknown(not_declared)` and reads "Not stated".
- **Printed but not used stays visible.** kJ beside printed kcal, salt beside printed sodium, reference-intake columns and unrecognised rows are listed on Confirm as read but not used, and kept in the stored evidence; they never become a ledger value.
- **Bounds stay bounds.** `<0.1g`, `< 0.5 公克` and `less than 1g` are stored as bounded values with their printed comparator, never as an exact value or zero.
- **Missing mandatory rows** are shown as exceptions (section 3.2); the user fills them or leaves them unknown. Any other row the label does not print reads "Not stated" and stays unknown unless the user enters it.

### 3.5 Calculated values: kJ-only energy and salt-only sodium (decision 6, changed)

The owner chose to convert these two cases rather than leave them unknown. A conversion is a labelled calculation from a printed value, never a printed value, and never silent.

**Rules** (`pasted-label-conversions-v1`):

| Case | Rule | When it applies |
|---|---|---|
| Energy printed only in kJ (`kj_to_kcal_v1`) | kcal = kJ ÷ 4.184 | The stored column prints energy in kJ and does **not** print kcal |
| Sodium not printed, salt printed (`salt_to_sodium_v1`) | sodium (mg) = salt (g) ÷ 2.5 × 1000 | The stored column prints salt and does **not** print sodium |

- **Printed always wins.** If kcal is printed, kcal is used as printed and kJ is never converted. If sodium is printed, sodium is used as printed and salt is never converted. This holds even when the printed pair disagree; the kJ / kcal check (section 4) may then warn.
- **Same cell, same column.** A conversion reads only the printed cell in the stored column (section 6.3). It never reads the other column and never chains (no conversion of a converted value).
- **Arithmetic and the conversion record.** Each conversion is computed and recorded exactly like this:
  1. **Operand:** the printed `decimal_text` of the source cell, parsed as Foundation `Decimal` (never through `Double`), with its printed unit (`kJ`, or `g_salt` for salt).
  2. **Quotient:** `NSDecimalDivide` of the operand by the factor (`4.184`, or `2.5` followed by multiplication by `1000`), at Foundation `Decimal` precision.
  3. **Intermediate:** the quotient rounded **half-even to exactly 6 decimal places**, recorded as a fixed-point string with 6 digits after the point (`370.458891`). It is audit evidence only.
  4. **Stored amount:** the intermediate rounded **half away from zero to 1 decimal place**, recorded as its canonical string: plain fixed-point, no exponent, no leading `+`, no grouping, exactly one digit after the point (`370.5`, `240.0`, `0.0`). The ledger amount is `Double(storedText)`.
  5. **Record** (`conversions[]` in the manifest, keys sorted by the canonical encoder): `nutrient`, `rule` (`kj_to_kcal_v1` or `salt_to_sodium_v1`), `rule_version` (`pasted-label-conversions-v1`), `source_header_id`, `source_row_id`, `operand_text`, `operand_unit`, `factor_text` (`4.184` or `2.5`), `intermediate_text`, `stored_text`, and for a bound `comparator` and `rounding` (`outward`).
- **Verification compares the stored amount only.** At save and reopen the verifier recomputes steps 1 to 4 from `operand_text` and the rule, compares the result's canonical string with `stored_text`, then checks that `Double(stored_text)` equals the ledger amount exactly. The intermediate is never compared, so a future platform difference in the sixth decimal place cannot invalidate an entry. Golden vectors pin the inputs, every string and the canonical JSON bytes of the record (section 8.4, test 45).
- **Worked values.** 1550 kJ: intermediate `370.458891`, stored `370.5` kcal. 0.6 g salt: `240.000000`, stored `240.0` mg. 0.03 g salt: `12.000000`, stored `12.0` mg.
- **Bounds stay bounds.** A printed bound converts endpoint by endpoint with the same factor and keeps its comparator and closedness. Each endpoint is rounded **outward** directly from the quotient to 1 decimal place (an upper endpoint up, a lower endpoint down), not from the intermediate, so the converted bound still contains every value the printed bound allows. Example: `<0.01g` salt gives sodium `< 4.0 mg`; `<0.1g` salt gives `< 40.0 mg`.
- **Zero stays printed zero.** A printed `0` converts to 0.0 and keeps the "Calculated" label; an absent row is never converted and stays unknown.
- **Display.** A calculated value always shows the "Calculated" tag and its printed source with the rule, everywhere it is shown (Confirm, the saved entry, Developer tools, the misread report). An exact calculated amount also shows "about": "Energy about 370 kcal · Calculated from 1550 kJ (printed)", rounded for display to a whole number of kcal or mg (half away from zero). A calculated bound keeps the bound's own wording instead of "about": "Less than 5 kcal · Calculated" or "4 mg or less · Calculated", and its shown end is rounded outward to a whole number (an upper end up), so the shown bound still contains the stored one. Confirm's nutrition summaries, the label rows, the saved entry and the report use this one formatter. The stored value keeps one decimal place. VoiceOver reads "calculated" as a word, so the label never relies on colour or a symbol. (Amended 19 October 2026, section 10, decision 15.)
- **Estimate labelling.** The value is labelled as calculated (an estimate) at value level wherever it is shown. Whether the entry as a whole shows the "Estimate" prefix (confirmation v5 section 5) is unchanged by a calculated value: the identity is the user's named food and is not an estimate.
- **Totals (owner-approved, in session, 18 October 2026).** A day or period total that includes a calculated contribution sets the existing `includesEstimates` flag and shows the existing estimate copy and indicator, under a new summary policy **`food-intake-summary-v3`** (v2 plus this one rule). Values corrected or entered by the user do **not** set `includesEstimates` (decision 13, decided by the owner): they are user-asserted and shown as such per value. Nothing else in the summary changes; summaries already stored under `food-intake-summary-v1` or `-v2` keep their bytes and identifiers.
- **Checks.** The section 4 checks run on printed values only, as frozen. A calculated value is never a check input, so with kJ-only energy the energy check is "not checkable".

**Storage.** A calculated value is a `measured` nutrient whose `sourceValue` is the printed value and unit (`kJ`, or `g_salt` as in the food identity contract's sodium example), whose `unit` is the canonical unit, and whose provenance carries exactly one `NutrientTransform`: `transformID` `kj_to_kcal_v1` or `salt_to_sodium_v1` (aligned with the identity contract's `salt_to_sodium_v1` example), `transformVersion` `pasted-label-conversions-v1`. `ExactNutrientValue` already requires a transform when the source unit differs. The domain's closed rule that `augmented` values never carry `user_verified_panel` provenance stays closed.

**One definition of "calculated".**
- **Domain:** `NutrientDerivation.calculatedTransform(_:)`, a pure predicate that is true only for an allow-listed `(transformID, transformVersion)` pair: `(kj_to_kcal_v1, pasted-label-conversions-v1)` and `(salt_to_sodium_v1, pasted-label-conversions-v1)`. The list is append-only; an unlisted pair is not "calculated" and is not admitted by the pasted-label verifier.
- **Application:** `NutrientValueOrigin` (`printed`, `calculated(rule)`, `correctedByYou`, `enteredByYou`, `unknown(notRead | notStated)`; a bound is a value shape that any of the first four can carry), projected from a stored value, its provenance and the manifest's correction records through that predicate, and used by `food-intake-summary-v3`, the misread report builder and every view model.
- **Presentation:** one formatter renders `NutrientValueOrigin` for Confirm, the saved entry, Developer tools and the misread report preview, so the "about", "Calculated" and source wording cannot drift between surfaces.

**Reachability under gate v2 (finding).** Gate v2's mandatory rows require kcal on both UK (`energy_kcal`) and Taiwan tables, and sodium on Taiwan tables. Under the assisted design that finding is a flag, not a decline, so a kJ-only table now reaches Confirm: kcal is calculated from the printed kJ and shown as calculated, and the G3 flag on the kcal row is satisfied by that calculated value rather than shown as "Not read". The rule is reachable and tested. Salt-only sodium is reachable on UK tables, where salt is mandatory and sodium is not, so it matters only once UK English ships (decision 3).

## 4. Arithmetic and consistency checks: warnings only

The frozen section 7 policy of the evaluation, ported to Swift with its own identifier (`label-arithmetic-checks-v1`, proposed), runs on every non-declined table:

- energy against macronutrients: `kcal ≈ 4P + 4C + 9F` (UK may also pass with `+ 2·fibre`); Taiwan, when fibre is printed, `kcal ≈ 4P + 4(C − fibre) + 2·fibre + 9F`; tolerance the larger of 15 kcal and 10% (UK, Taiwan) (US layouts decline in v1, so the US tolerance is not used);
- `kJ / kcal` within 4.184 ± 2% when both are printed;
- per serving against per 100 × serving / 100, within printed rounding;
- sub-rows not exceeding their parent (saturates ≤ fat, sugars ≤ carbohydrate, Taiwan fibre ≤ carbohydrate);
- inputs that are bounds or unknowns make a check "not checkable", never zero and never a failure.

**Product rule (deliberately different from the evaluation):** in the evaluation a failed check blocked the route's ready mark. In the product a failure is a **non-blocking warning** on Confirm, for example "Energy does not match the fat, carbohydrate and protein shown. Check the label text." It never blocks Log, never authorises Log, never changes, fills or removes a value, and is not a `FoodLogRequirement`. A pass shows **nothing**: there is no "checked" or "verified" badge, because the check misses some errors (6 of 116 planted mutations, section 1) and must not be read as confirmation. The owner decides whether the failed mutation bar stands in the way of this (decision 2).

Warnings are not persisted as nutrition. The warning codes shown at Log are recorded in the manifest (section 6.1) as evidence of what the user saw.

## 5. Languages and layouts

| Language | Layout (gate format) | v1 |
|---|---|---|
| Traditional Chinese (`zh-Hant`) | Taiwan 營養標示 (`taiwan_nutrition_labelling`) | Supported. Untouched synthetic evidence |
| English | UK nutrition declaration (`uk_nutrition_declaration`) | Ships second, only after at least 20 real public UK label texts read with zero wrong values (decisions 3 and 11). Until then it declines with `layout_not_supported` |
| English | US "Nutrition Facts" | Declines with `layout_not_supported` in v1 (decision 4) |
| Simplified Chinese, Japanese, Korean, every other language | none | Declines (`unsupported_language` or `unsupported_script`) |

**Launch scope.** `PastedLabelLaunchScope` is an application constant, `[taiwan_nutrition_labelling]` in v1. It is applied **after** the gate: the gate stays a faithful port of gate v2 for both UK and Taiwan, and a UK table that passes the gate is then declined `layout_not_supported` by the scope. Adding UK after its release gate (decision 3) changes only this constant and the copy it feeds. The scope in force is recorded in the manifest (`launch_scope`).

**Format inference.** The evaluation declared each case's format from its corpus, never from route output. The product has no corpus, so the gate's format must be inferred, deterministically, from the candidate: `zh-Hant` resolves to Taiwan; English with a per 100 g or per 100 ml column resolves to UK; English without one resolves to UK when it prints a salt or kJ row (both mandatory on a UK declaration, neither printed on a US Nutrition Facts panel), and otherwise to US, which declines in v1; `mixed` or `unknown` language declines with `format_ambiguous`. A UK table printed per serving only is therefore UK, not US: the gate flags the missing per 100 g or ml column (G5, section 3.2) rather than refusing it, and in v1 the launch scope still declines UK (owner decision, in session, 18 October 2026, after PR 1 found the frozen development case `v1:off:5060457050039:nutrition_nl.5:tab` that the earlier rule read as US). This is a deviation from the evaluation method, so it gets its own test vectors (section 8.4) built from the frozen development and untouched cases with their declared formats, and inference must agree with the declared format on every one.

## 6. Data model

### 6.1 Evidence: a pasted-label manifest

A logged label is stored as one `CaptureEvidence` whose payload is a canonical, byte-exact **pasted-label manifest**, `pasted-nutrition-label-v1`, following the review manifest pattern ([review manifest v2](generic-food-review-manifest-v2.md), "Retention"):

| Field | Content |
|---|---|
| `version` | `pasted-nutrition-label-v1` |
| `pasted_text` | The exact text that was read, verbatim (decision 5) |
| `pasted_text_sha256` | SHA-256 of its UTF-8 bytes |
| `parser_version` | `nutrition-label-text-parser-v2` |
| `gate_version` | the Swift gate version (section 7) |
| `arithmetic_version` | `label-arithmetic-checks-v1` (proposed) |
| `conversion_version` | `pasted-label-conversions-v1` |
| `label_format` | the inferred gate format |
| `launch_scope` | the `PastedLabelLaunchScope` value in force, for example `["taiwan_nutrition_labelling"]` |
| `identity_mapping` | `pasted-label-identity-v1` and the resulting facet values (section 6.5), including the fortification answer (`yes`, `no` or `unanswered`) |
| `candidate` | the `label-capture-candidate-v1` the reader produced: headers, cells (printed label, printed text, comparator, decimal text, unit, basis, parent), serving size, servings per pack, warnings |
| `stored_header_id` | the column whose values were stored (section 6.3) |
| `conversions` | the exact conversion records of section 3.5; an empty array when nothing was converted |
| `flags_shown` | the G3 to G6 exceptions on Confirm at Log, with the row or line each concerns (section 3.2) |
| `corrections` | one record per value the user corrected or entered: `kind` (`corrected` or `entered`), `nutrient`, `row_id` (null for an entered row that was not read), `header_id`, `recognised` (the recognised cell's printed text, decimal text, unit and comparator, or null when entered), `corrected` (decimal text, unit and comparator as entered), and `at` (milliseconds since 1970, from the injected clock); an empty array when nothing was changed |
| `warnings_shown` | the warning codes on Confirm at Log |
| `name`, `brand` | as entered (`brand` omitted when empty) |

- Encoding: `FoundationCanonicalJSONEncoder` (sorted keys, unescaped slashes), the same as the review manifest. The bytes are stored verbatim as the `.text` payload and are never re-encoded from the struct after save.
- `CaptureEvidence`: `kind = .labelText` (existing), `captureMethod = "User pasted nutrition label"`, `captureMethodVersion = "pasted-nutrition-label-v1"`, `byteHash` = SHA-256 of the manifest bytes, `locale` as today.
- `SourceRelease`: `sourceID = "pasted-nutrition-label"`, `sourceReleaseID = "pasted-label:" + manifestHash`, `manifestHash`, `artifactHash = pasted_text_sha256`, `schemaVersion = "pasted-nutrition-label-v1:" + label_format`, `pipelineVersion = "<parser_version>:<gate_version>:<arithmetic_version>:<conversion_version>"`, `licence = "User-supplied label text; no redistribution licence inferred."`, `attribution = "Pasted nutrition label"`.
- Provenance on every stored nutrient: `source_kind = user_verified_panel` (existing; decision 7), `source_id = pasted-nutrition-label`, the release above, `evidence_id`, and `manifestReference = "manifest-sha256=…;header=…;row=…;literal=…"` naming the cell it came from. A printed value carries no transform; a calculated value carries exactly one (section 3.5). A value **corrected or entered by the user** carries `source_kind = manual_declaration` (existing, admitted for `measured` and measured bounds), the same release and evidence, and `manifestReference = "manifest-sha256=…;correction=<index>"` naming its correction record; the recognised value it replaced stays in the manifest, not in the ledger value. When the user corrects a calculated value, its conversion record stays in `conversions` as evidence of what Confirm showed and is still verified; the correction supplies the stored value, and the correction's recognised cell is the conversion's printed source cell.
- `kind = .labelText` is already used by the reviewed web manifest. Lookups for each route discriminate by `release.sourceID` and `captureMethodVersion`, and a contract test proves neither route's verifier accepts the other's evidence (section 8.4).

**Admission of `user_verified_panel` at save.** The save service accepts a `user_verified_panel` value only through a source verifier keyed by `SourceRelease.sourceID`, looked up in an append-only admitted list whose v1 entry is `pasted-nutrition-label`. The same applies to `manual_declaration` values whose release names `pasted-nutrition-label`. A `user_verified_panel` value whose release has an unknown `sourceID` (or none) fails `invalidPastedLabelSource` before policy. Adding a verifier appends to the list; no entry is removed or rekeyed.

**Verification at save and at reopen.** As for reviewed web proposals: the service checks the manifest digest, that the stored nutrients, units, bounds and basis equal the manifest's cells for `stored_header_id`, every calculated value's stored amount matches its conversion record as defined in section 3.5, and every corrected or entered value equals its correction record's `corrected` value, and that the pipeline is an admitted one; otherwise `invalidPastedLabelSource` before policy at save and `integrityFailure` at reopen. Verification compares against the stored manifest, **not** a re-parse, so a later parser version never invalidates an old entry. Developer tools can re-run the current parser on `pasted_text` and show any difference, for reproduction only.

### 6.2 Limits on the pasted text

- At most 8,000 **Unicode scalars** (`String.unicodeScalars.count`, not grapheme clusters or UTF-16 units); longer text declines `text_too_long` before parsing.
- Text is stored exactly as read: no trimming, normalisation or redaction after Read label. The user can edit it before reading.

### 6.3 Which column is stored

One resolution has one basis. The stored column is chosen by a fixed rule, never by the user's amount:

1. the per 100 g or per 100 ml column, when one is printed (UK normally, Taiwan when 每100公克 or 每100毫升 is printed);
2. otherwise the per-serving column, with basis `perServing(serving quantity)` when the serving size prints a quantity and unit;
3. otherwise (a per-serving column with no readable serving size, flagged under section 3.2) the per-serving column, with the serving size shown as "Not read: serving size. Add it, or leave it unknown." Until the user enters it ("Entered by you", recorded as a correction), only the servings amount option is offered, under the existing `food_confirmation_v5` amount requirements; the exact basis representation is settled in PR 2 with a contract test.

**Serving policy `pasted-label-serving-v1`** (PR 2, a closed sibling of `food-source-declared-serving-v1`). A pasted label whose stored column is per serving can be logged in servings, and nutrients scale by the count. In case 2 (`perServing(q)`, q in grams or millilitres) n servings are n × q through the printed serving size, recorded as a quantity conversion whose method is `pasted-label-serving-v1` and which cites the pasted release and manifest evidence; an amount in q's unit is also accepted. In case 3 the basis is `perServing(1 count)`: servings only, never given a weight. Ordinary counts on any basis that neither v1 nor v2 covers still need a measured amount.

**Serving policy `pasted-label-serving-v2`** (owner, in session, 19 October 2026; section 10, decision 14). A pasted label whose stored column is per 100 g (per 100 ml) can also be logged in servings when it has an exact serving size q in grams (millilitres): the printed serving size unless its serving-size segment is approximate (below), or a serving size the user corrected or entered on Confirm (one `serving_size` correction record in the stored column, verified exactly as for a per-serving column and shown with its origin). n servings are the quantity n × q, scaled against the per-100 basis, recorded as a quantity conversion whose method is `pasted-label-serving-v2` and which cites the pasted release and manifest evidence, exactly like a v1 record. The basis stays per 100 g (per 100 ml): a serving size never changes a nutrient, the basis or the stored column. There is no unit mismatch: a serving in millilitres is never converted against per 100 g, nor grams against per 100 ml, and such a label offers no servings. An amount in grams (millilitres) is accepted as for any per-100 basis. The method is chosen by the stored column, never by the user: v1 for a per-serving column, v2 for a per-100 column. Both are in the append-only `PastedLabelServingPolicy.admittedVersions`. At save, a conversion naming a pasted-label method that does not apply to the label is refused (`sourceServingsRequired`); at reopen, a stored conversion naming either method must equal the conversion that method records for its source quantity on that label (method, converted quantity, release and evidence), or the entry fails with `integrityFailure`.

**Approximate serving sizes under v2 (closed; fixed for v2, any change is a new version).** The scan covers only the **serving-size segment** of the printed serving-size line, derived in the application (it cannot import the parser): from the start of the value (after the label `serving size`, `portion size`, 每份量 or 每一份量 and an optional colon, matched as parser v2 matches it, case-insensitively) to the end of the recorded quantity (the first occurrence of the recorded `decimal_text`, not preceded by a digit or point, followed by optional spaces and the recorded `unit`), plus a tolerance or range written straight after it (optional spaces, ± or one of - – ~ ～ 〜 至, optional spaces, a number). Anything else after the quantity, such as "，本包裝含約10份" or "（約2片）", is not scanned, so `每一份量30公克，本包裝含約10份` keeps an exact 30 g serving size. When the quantity cannot be found in the line, the serving size is treated as approximate. The segment is approximate when it contains:

- one of the English words `about`, `approx`, `approximately`, `around`, `circa`, `roughly`, matched as whole words (runs of ASCII letters), case-insensitively;
- one of the marks 約, 约, ~, ～, 〜, ≈, ≒, ±;
- a numeric range: a digit, up to three non-space characters (a unit), optional spaces, one of - – ~ ～ 〜 至, optional spaces, a digit (for example `25-30g`, `25–30 g`, `25~30公克`, `30g-35g`, `30公克至35公克`).

Reopen re-evaluates this rule against the stored manifest, so the list and the segment are fixed for every v2 record; a change needs `pasted-label-serving-v3`. A user's corrected or entered serving size is exact by construction and is not scanned.

**Why v1 and v2 differ on "about" (orchestrator decision, owner informed, 19 October 2026).** v1 keeps accepting an "about" serving size on a per-serving column: the nutrients there are per serving, so n servings scale the nutrients by n whatever the serving size's precision, and only the recorded gram figure depends on it. v2 rejects it, because on a per-100 column the nutrients scale by q itself.

**Measured counts on per-100 labels (orchestrator decision, owner informed, 19 October 2026).** On a per-100 label with a qualifying serving size, a count now means servings, so an older entry saved there as a count with an ordinary measured conversion would be refused on re-save (`sourceServingsRequired`). No such entry exists outside development builds (the route has never shipped, including to TestFlight), so this is accepted.

v2 is a new version rather than a change to v1, so that every v1 record keeps its bytes, its method string and its meaning: v1 still covers per-serving columns exactly as before, and v2 covers only the new per-100 case. Nothing stored under v1 is reinterpreted.

Values in the other column are kept in the manifest and shown as evidence. They are never merged into the stored column: a nutrient printed only in the other column stays unknown in the stored one. When both columns are printed and disagree beyond rounding, the scaling check warns (section 4).

### 6.4 Reuse: library food and favourites

- **Reuse in v1: Recent foods and Favourites (owner, in session, 19 October 2026).** A logged label is logged again through Recent foods, or through a favourite made from it, with today's re-log semantics: Confirm opens as a new entry built from the stored source candidate, which is re-verified against the stored manifest bytes (never re-read or re-parsed), and Log writes a new log item over the same evidence and source release with no new evidence. As for every route today, that save writes new product and resolution versions carrying the same nutrients. No `LibraryEntry` alias is written in v1, so Add food search does not find a pasted label by name; that is follow-up #269, which must settle the alias key for names the shared `food:name:` normaliser cannot key (it keeps ASCII letters and digits only), how search reuse carries the manifest evidence, and the reuse semantics.
- **Favourite.** Only by the existing explicit favourite action after save ([food quick add v1](food-quick-add-contract-v1.md)); never automatic (decision 8).
- **Re-reading.** Pasting a new label for the same name creates a new evidence record and a new product version through the ordinary correction path; earlier entries keep their versions.

### 6.5 Confirmation v5 and the assertion grammar

- The policy stays `food_confirmation_v5`; `methodVersion` on new resolutions is `food_confirmation_v5`.
- A pasted-label save is a **plain exact save**: values are measured from the user's label text, or corrected or entered by the user on Confirm, the product identity is the user's named food, and it is not a generic estimate. It writes **no new assertion row**; the parser, gate and check versions, the flags and the corrections live in the manifest. This keeps the persisted assertion grammar of v5 section 1 unchanged, so no new policy identifier is needed.
- Inline decisions, typed requirements, "When" and the amount rules apply unchanged.
- **Identity mapping `pasted-label-identity-v1`** (owner-approved, in session, 18 October 2026, as the gate proposed). The pasted label's `DecisiveIdentity` is:

  | Facet | Value |
  |---|---|
  | `preparation` | as sold. v1 declines, with `basis_state_not_supported`, any table whose header or basis is as prepared or drained (for example 沖泡, 瀝乾, "as prepared", "drained") |
  | `bone`, `skin`, `drained` | not applicable |
  | `packingMedium` | `named("as sold")` |
  | `fortification` | from the optional Fortified? answer: Yes is fortified, No is unfortified; unanswered is unknown, which raises the existing `sourceIdentityMissing` requirement, resolved by the existing "Add food details" flow |
  | `itemClass` | `food`, or `fortifiedFood` when the user answered Yes |
  | `servingBasis` | the stored column's basis (section 6.3) |

  The mapping version and the resulting values are recorded in the manifest (`identity_mapping`).
- The review manifest v2 contract is not amended. The pasted-label manifest is a sibling with the same retention and verification pattern.

### 6.6 Schema and archive version

The enum cases already exist (`CaptureKind.labelText`, `ProvenanceSourceKind.userVerifiedPanel`, `CapturePayload.text`), so no stored type gains a case. A version bump is still proposed (decision 9), because an older binary could decode a pasted-label entry but could not verify it, and would treat it as an unverifiable source:

- **Food contract 7**, migration identifier `food-ledger-v7`. `CanonicalFoodArchive.minimumContractVersion` returns 7 when any evidence has `captureMethodVersion == "pasted-nutrition-label-v1"`, and checks this **first**, before the existing contract 6 early returns (favourites, reference definitions), so an archive with both favourites and a pasted label is never reported as contract 6. A binary with this contract exports contract 7 only when such evidence exists; otherwise it exports contract 6, the existing floor, exactly as before.
- **SQLite migration `v7_pasted_label`:** metadata only (`schema_identity = food-ledger-v7`, `user_version = 7`). No immutable row is rewritten. A schema-6 opener throws `unknownSchema(7)`.
- **Existing records keep their bytes.** Every v1 to v6 record and archive decodes and re-encodes byte for byte (golden fixtures, section 8.4). The operation type stays `confirm_food_v1`, `confirm_food_v2` or `confirm_food_v3` as the save requires; no operation type is added.
- **Daily JSON:** unchanged. Food entries are not in the Daily JSON today; the pasted text and manifest never enter it.
- **Release note (decision 9),** in the same form as 0.2.0 (25) "Older builds cannot open the food data after updating" in `docs/releases/internal-testflight-0.2.0-build25.md`: when the implementation merges, `docs/releases/unreleased.md` gains a row for this change (archive contract 7, schema `food-ledger-v7`) stating that once the food log opens with the new build an older build can no longer open it, that existing records keep their bytes, and that the Daily JSON export is unchanged in shape. It is not added now because no implementation has merged.

## 7. Privacy

**Reading is fully on device, with no egress. The one change to the privacy documents is the "Report a misread" share (decision 12), which is a user-initiated share through the system share sheet, not new app egress.**

- Reading uses only `NutritionLabelParsing` and the ported gate, checks and conversions, with no network, provider, model or OCR call.
- The pasted text is stored only in the local food ledger, inside the manifest of the entry it produced, under the existing rule that the food log stays local. It leaves the device only inside an inventory backup file the user explicitly exports, which [`privacy-and-egress.md`](privacy-and-egress.md) already covers for the whole food log, or inside a misread report the user chooses to share. It is never in Daily JSON, Copy all, Full Page or any report.
- Reading the clipboard happens only when the user pastes into the field (the system paste control); the app never reads the pasteboard on its own.
- **Report a misread** (section 9.1) opens the iOS share sheet only when the user taps it. The user sees and can edit the report first, picks the destination in the share sheet, and can cancel at any point. The app has no destination of its own for it: no prefilled address, no endpoint, no upload, no background collection, no retry and no record that a report was made.
- **Required privacy document changes, shipped in the implementation PR together with the feature.** They ship in **PR 4 (presentation and UI)**, in that PR or folded in alongside it (section 8.6), and are **not** made by this contract's PR: the app bundles `privacy-policy.txt` (`PrivacyPolicyView`), and neither document may describe the route before it exists. The owner's approval of this contract covers the exact wording below; the implementation PR applies it verbatim, and any change to it needs owner approval again. Both are user-initiated shares under the existing row; no row and no destination is added.

  1. **[`privacy-and-egress.md`](privacy-and-egress.md), "Allowed egress", the existing first row.** Replace it with:

     ```
     | Clipboard, share sheet or the iOS screenshot editor | The report text, or a Full Page PDF of Health (the report) or Today (today's food totals, quick-add favourite names and amounts, today's note count and today-so-far Health values), created in memory; or a misread report for a pasted nutrition label (the pasted label text, the values read from it, and the parser, gate, check and conversion versions), as previewed and edited by the user | Only when the user chooses Copy all, Share, a screenshot's Full Page, or Report a misread, and then saves or shares it; the user picks the destination in the system share sheet and can cancel; the app has no destination of its own and nothing is sent automatically | [README.md](../README.md), [pasted-nutrition-label-v1.md](pasted-nutrition-label-v1.md) |
     ```

  2. **[`privacy-policy.txt`](privacy-policy.txt), "Sharing and Google Drive".** After the sentence ending "today's note count and today-so-far Health values." insert:

     ```
     If you choose Report a misread for a pasted nutrition label, the app shows a report containing the pasted label text, the values it read and the reader versions; you can edit it, and it goes only to the destination you pick in the share sheet, or nowhere if you cancel.
     ```

  3. **[`privacy-policy.txt`](privacy-policy.txt), "Local food records and notes".** After the sentence "Receipt text you paste and text extracted from a PDF you select can be retained as evidence." insert:

     ```
     Nutrition-label text you paste and then log is kept locally, unchanged, as the evidence for that food; it is read on your device and is not sent to any service.
     ```

  4. **[`privacy-policy.txt`](privacy-policy.txt), first line after the title.** Set "Effective" to the date of the release that ships the route.

  Contract test 35 confirms these three texts appear verbatim and that the effective date has changed.
- No telemetry, analytics or automatic report of any kind.

## 8. Architecture gate

### 8.1 Responsibilities and layers

| Layer | Owns | Must not |
|---|---|---|
| **`NutritionLabelParsing`** (pure, Foundation only) | Parser v2 (unchanged); the Swift **decline gate** port with format inference, reading gate v2's simplified-only character set from a frozen data table (section 8.2); the Swift **conversions** (`pasted-label-conversions-v1`); the Swift **arithmetic and consistency checks** port. Inputs are text and the injected hash string; output is `LabelCaptureCandidate` plus gate and check findings | Hash, read a clock, touch the ledger, know about Confirm |
| **Domain** (`FoodLedgerDomain`) | `NutrientDerivation.calculatedTransform` and its allow-list (section 3.5); `pasted-label-identity-v1` facet values; otherwise the existing evidence, provenance and nutrient types | Depend on the parser |
| **Application** (`FoodLedgerApplication`) | A small consumer-owned port **`LabelTextReading`** returning an application-owned **`LabelReading`** with an `origin` field (`pastedText` in v1, so a photo route can reuse it), cells, basis, serving facts, decline reasons, warnings and versions; `PastedLabelLaunchScope`; a `PastedLabelConfirmation` use case that builds the manifest, evidence, release, identity and `PopulatedFoodConfirmation`; the `sourceID`-keyed verifier list and save and reopen verification; `NutrientValueOrigin`; `food-intake-summary-v3`; a pure **misread report builder** (input: the reading and versions; output: the report text, with name and brand never prefilled); `minimumContractVersion` | Import `NutritionLabelParsing` types across the port (decision 10), format copy |
| **Adapter** (new target `FoodLabelTextCapture`, decision 10) | Implements `LabelTextReading` with `NutritionLabelParsing`, mapping candidate and gate output to the application reading | Persist, decide, or present |
| **Infrastructure** (`FoodLedgerGRDB`, `FoodLedgerArchive`) | Migration `v7_pasted_label`; archive contract 7 | Interpret label text |
| **Presentation** (`FoodLedgerPresentation`) | Label text screen and view model; decline copy renderer with the `unreadable_table` fallback; Confirm source section for pasted labels; the one `NutrientValueOrigin` formatter; warning copy; the misread preview and share sheet | Parse, hash, decide what is stored, import `FoodLabelTextCapture`, or store label text in `@SceneStorage` or `@AppStorage` |
| **Composition root** | Registers the "Paste nutrition label" entry route and the adapter | Contain rules |

Hashing (SHA-256 of the text and the manifest) uses the injected digester, as `ReviewedFoodProposalConfirmation` does.

### 8.2 Dependency direction and `check-boundaries`

`FoodLabelTextCapture` → `FoodLedgerApplication`, `FoodLedgerDomain`, `NutritionLabelParsing`. `FoodLedgerApplication` does not depend on `NutritionLabelParsing`. `NutritionLabelParsing` keeps its Foundation-only allow-list. `Packages/FoodLedgerKit/Scripts/check-boundaries.sh` gains `check_imports FoodLabelTextCapture '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|NutritionLabelParsing)$'`, and these checks:

- No target other than `FoodLabelTextCapture`, the `NutritionLabelTextParse` CLI and their tests imports `NutritionLabelParsing`, and no target other than the composition root and the adapter's tests imports `FoodLabelTextCapture`. In particular **`FoodLedgerPresentation` must not import `FoodLabelTextCapture`**.
- The import scan covers every form: `import X`, `@testable import X`, `@_implementationOnly import X` and `import struct|class|enum|protocol|func X.Y`, not only the bare `import X` the current `sed` pattern matches.
- The scan covers the **app target** (`WeeklyHealthReport/`) as well as the package sources, and also checks the `dependencies:` lists in `Package.swift`, so a forbidden edge cannot be added through the manifest alone.

**Frozen simplified-only table.** Gate v2 classifies Han characters with Python codecs (`is_simplified_only`: in GB 2312 and not in CP950, over `HAN_RANGES`, minus `SHARED_VARIANTS`). Swift has no equivalent codecs, so the set is frozen as a committed data table: a Python generator run once over `HAN_RANGES` writes every simplified-only code point (hexadecimal, sorted, one per line) to a resource file in `NutritionLabelParsing`, with its SHA-256 recorded in the gate's version block. The Swift gate reads only that table. Parity is exhaustive: a test walks every code point in `HAN_RANGES` and asserts that the Swift classification equals the Python classification recorded in the table, and that the table's hash matches (test 25).

### 8.3 Invariants

1. The only save is the user's Log on Confirm. Reading, a gate pass, a check pass and the absence of a warning never save and never enable Log.
2. Every stored value is one of: a printed cell of the stored column, bound by `manifestReference` to its printed label and text; a calculated value from exactly one such cell under `pasted-label-conversions-v1`; or a value corrected or entered by the user, bound to its correction record, with the recognised value kept in the manifest. Each is shown with its origin wherever it appears. No value is inferred, copied from another column or defaulted, and a printed value always wins over a calculation.
3. Unknown is never zero; bounds stay bounds; "Not stated" is unknown.
4. Hard declines write nothing and retain nothing; partial tables are flagged, never declined and never silently completed.
5. The gate and checks never change a value; checks never block or authorise Log.
6. Records are append-only and versioned; stored manifests are byte-exact and verified at save and reopen against themselves, not a re-parse.
7. No app egress: nothing leaves the device except through a share the user starts and completes in the system share sheet, or the existing user-exported backup; the app never reads the pasteboard unprompted.
8. Only `zh-Hant` (Taiwan layout) and, once its release gate passes, `en` (UK layout) are read; US layouts and everything else decline.
9. No medical classification, targets or interpretation in any copy.
10. Older records and archives decode and re-encode unchanged.
11. "Calculated" has one definition (`NutrientDerivation.calculatedTransform`) and one renderer; every total that includes a calculated contribution says it includes estimates.
12. Label text is never kept outside a logged entry's manifest: not in scene or app storage, not in logs, not read from the pasteboard by the app.

### 8.4 Contract tests (written first)

Parsing and gate (pure, `NutritionLabelParsingTests`):

1. **Gate port parity:** the Swift gate reproduces `decline_gate.py` (gate v2) on frozen vectors exported from every development and untouched pasted-text case, including the shared-variant code points (内 温 黄 …), supplement markers, missing mandatory rows and per 100 column checks.
2. **Arithmetic port parity:** the Swift checks reproduce `arithmetic.py` on the three frozen mutation families applied to the untouched truth, including the same 6 misses, the muesli example (367.2 kcal) and "not checkable" for bounds.
3. **Format inference** agrees with the declared format on every frozen case; `mixed` and `unknown` decline `format_ambiguous`.
4. **No inference:** % RI columns and one-column-only nutrients never produce a stored value; the only derived values are the section 3.5 conversions.
5. **Conversion rules (`pasted-label-conversions-v1`):** golden cases for kJ to kcal and salt to sodium with exact decimal results and one-decimal stored rounding (1550 kJ → 370.5 kcal; 0.6 g → 240.0 mg; 0.03 g → 12.0 mg; a half-way case rounds away from zero); outward rounding of bounds (`<0.01g` → `< 4.0 mg`, `<0.1g` → `< 40.0 mg`, a lower bound rounds down); printed `0` converts to 0.0; an absent row is never converted.
6. **Printed wins:** with kcal and kJ both printed, kcal is stored as printed and no transform is recorded, including when they disagree; the same for sodium and salt.
7. **No cross-column or chained conversion:** a kJ value only in the other column, or salt only in the other column, gives unknown, not a calculated value.
8. **Checks never read a calculated value:** kJ-only energy makes the energy check "not checkable".
9. **Determinism:** the same text gives byte-identical candidate and findings across runs and locales.

Application (`FoodLedgerApplicationTests`, `FoodLedgerContractTests`):

10. A non-declined reading yields a `PopulatedFoodConfirmation` whose every non-unknown nutrient cites a manifest cell of the stored column; no-other-column fill. A calculated value is `measured` with its printed `sourceValue` (`kJ` or `g_salt`) and exactly one `pasted-label-conversions-v1` transform, passes existing domain validation unchanged, and is recorded in the manifest's `conversions`.
11. Save verification fails `invalidPastedLabelSource` when a calculated amount differs from its recomputed conversion, or a conversion is recorded where the printed counterpart exists.
12. A hard-declined reading yields no confirmation and writes no evidence.
13. A failed arithmetic check yields a warning and no `FoodLogRequirement`; Log enablement with and without the warning is identical.
14. Save verification: an altered value, unit, bound, basis or manifest byte fails `invalidPastedLabelSource` before policy; reopen fails `integrityFailure`.
15. **Cross-route isolation:** the reviewed web verifier rejects pasted-label evidence and the pasted-label verifier rejects reviewed web evidence, though both use `kind = .labelText`.
16. A pasted-label save writes no assertion and records `methodVersion = food_confirmation_v5`; a named label with Fortified? answered does not raise `sourceIdentityMissing`, and one left unanswered does, resolved by the existing details flow.
17. `minimumContractVersion` returns 7 with pasted-label evidence and is unchanged without it.
18. Golden fixtures: every existing v1 to v6 record and archive decodes and re-encodes byte for byte; a contract-7 archive round-trips byte for byte; a schema-6 opener throws `unknownSchema(7)`.
19. A logged label reused through Recent foods or a favourite creates a new log item over the same evidence and source release, writes no new evidence, re-verifies the stored manifest, keeps the nutrients, and makes no reader call (section 6.4; search reuse is #269).

Presentation and UI:

20. View-model tests: Read label disabled states, each hard-decline code maps to its copy, the text and name survive a decline and Edit label text.
21. Confirm shows every stored value beside its printed source text, the basis, serving size and servings per pack (or "Not stated"), and the read-but-not-used rows; every calculated value shows "about", the "Calculated" tag, its printed source and rule, on Confirm, the saved entry and the misread report, and VoiceOver reads "calculated".
22. Report a misread: the action opens a preview with Share and Cancel; Cancel writes and sends nothing; Share passes only the previewed (possibly edited) text to the system share sheet; the report holds no other entry, health data, note or identifier; no code path sends it without the share sheet.
23. Simulator UI test: Add food → Paste nutrition label → read → Confirm → Log; and a declined paste → edit → read → Confirm.
24. Accessibility: VoiceOver reads each value with its source text; 44 pt targets; Dynamic Type at the largest size; warnings not conveyed by colour alone.

Added by the architecture gate (tests 25 to 38, as the gate report states them):

25. **Gate code-point parity:** exhaustive parity of the Swift gate's classification with gate v2 over every code point in `HAN_RANGES`, plus a hash check of the frozen simplified-only table against the gate version block.
26. **Launch scope:** in the product, `PastedLabelLaunchScope` declines a UK table with `layout_not_supported`, while UK gate parity (the gate's own output on UK vectors) still passes.
27. **Code-to-copy mapping:** every parser and gate code maps to copy, and an unmapped code fails the test. Each code is also classified as exactly one of hard decline (the section 3.1 set, and only that set) or Confirm flag (G3 to G6); `unreadable_table` is the runtime fallback.
28. **Identity mapping (`pasted-label-identity-v1`):** a Taiwan label raises no `sourceIdentityMissing` once fortification is answered; an as-prepared or drained header (沖泡, 瀝乾) declines with `basis_state_not_supported`; leaving fortification unanswered raises exactly `[.fortification]`.
29. **Aggregation:** a day with a calculated kcal has `includesEstimates == true`; a printed-only day is unchanged; a golden test pins the summary version string `food-intake-summary-v3`.
30. **Precedence:** `minimumContractVersion` returns 7 for pasted evidence together with favourites and reference data, and stays at 6 or below without pasted evidence.
31. **Migration:** a populated v6 store migrates to v7 with identical hashes for every table before and after, `ledger_metadata` being the only table allowed to change; contract-6-or-lower archives re-export byte-identical from a v7 binary.
32. **Source admission:** a `userVerifiedPanel` value whose release `sourceID` is anything other than `pasted-nutrition-label` is rejected at save; the same holds for a `manual_declaration` correction or entry that claims the pasted-label release with any other `sourceID`, or cites no correction record.
33. **One origin projection:** for one fixture, the "Calculated" projection is identical on Confirm, the saved entry, the Home total, the misread report and Developer tools; the same fixture holds for every origin (printed, calculated, corrected by you, entered by you, not read, not stated).
34. **Report builder:** it uses an allow-list of contents, with no name, brand, other entries, health data, notes or identifiers; its output is deterministic; it lives in a target that imports no networking API.
35. **Policy wording:** a test reads `docs/privacy-and-egress.md` and the bundled `privacy-policy.txt`, checks that the three section 7 texts appear verbatim, and checks that the effective date is not the old one.
36. **Decline retention:** after a decline and dismissal, no evidence is written, nothing is held in scene or app storage, and the Developer tools codes are cleared.
37. **Text length and hashing:** the length boundary is in Unicode scalars (8,000 accepted, 8,001 declined); NFC and NFD forms of the same text hash differently and byte-exactly; input is stored as typed and never normalised.
38. **Reopen after restore:** reopening an entry after an archive restore verifies against the stored manifest, not a re-parse; a manifest whose `pipelineVersion` is not admitted fails with `integrityFailure`.

Added by the assisted-UX principle:

39. **Correction saved as corrected:** editing a recognised value and tapping Log stores the corrected value with `manual_declaration` provenance and origin `correctedByYou`; the manifest's correction record holds the recognised and corrected values and the injected time; the pasted text and recognised cell are unchanged.
40. **Entered value:** filling a "Not read" or "Not stated" row stores it with origin `enteredByYou` and a correction record with `recognised: null`.
41. **Partial table saves:** a table with G3, G4, G5 or G6 findings opens Confirm (no decline), shows each flag on its row or line, and saves with the untouched flagged rows as unknown, never zero; day totals for those nutrients are incomplete, with the known subtotal labelled.
42. **Flags and origin per value:** each value on Confirm, the saved entry and the misread preview shows exactly one origin, through the single formatter; the disclaimer line is present and no confidence score or "checked" badge appears.
43. **Re-read after edits:** with any correction or entry, Read again shows the confirmation; Cancel keeps every correction; Read again clears them and re-reads; with no corrections it re-reads without asking.
44. **Totals as decided (decision 13):** a calculated contribution sets `includesEstimates`; corrected and entered contributions do not; verification rejects a corrected value that differs from its correction record.

Added by `pasted-label-serving-v2` (decision 14):

49. **Method choice:** `PastedLabelServingPolicy.admittedVersions` is exactly `[pasted-label-serving-v1, pasted-label-serving-v2]`; a per-serving column resolves to v1 and a per 100 g (per 100 ml) column with a qualifying serving size to v2; a per-100 label still opens on grams.
50. **Not offered:** no serving size, an unreadable serving size, an approximate serving-size segment (each listed word and mark, including 约, 〜, ≒ and ±, and hyphen, en-dash, 至 and ～ ranges, before or after the unit), a quantity not found in the line, a serving in millilitres against per 100 g or in grams against per 100 ml: no servings, no whole pack, and an ordinary count still needs a measured amount. English words match whole only. Exact segments with an approximation elsewhere on the line (the pack count, a piece count after the quantity) are offered, save under v2 and reopen on both stores; the closed lists are pinned.
51. **Save and reopen on both stores:** n servings save as n × q against the per-100 basis with a v2 conversion citing the pasted release and manifest evidence, the basis staying per 100 g; reopen and re-save recompute it from the count; grams save with no conversion; a per 100 ml label logs millilitres; whole pack from a printed exact or an entered count logs that many servings; a corrected or entered serving size feeds v2 and an inconsistent serving-size record fails verification.
52. **Inconsistent records:** at save, a v1 conversion on a per-100 label or a v2 conversion on a per-serving label (or on a label with no qualifying serving size) is refused; at reopen, a stored v2 record relabelled v1, a v1 record relabelled v2, or a changed source quantity fails with `integrityFailure`, while the untampered records reopen. Existing v1 tests stay unchanged in substance.
53. **Presentation and app:** a per 100 g label with a printed serving size shows the servings unit and the whole-pack option with its printed-origin caption, logs a whole pack through v2, and reopens on servings; a corrected or entered serving size shows its origin and caption; an entered size in millilitres offers nothing on per 100 g.

Kept from the gate's findings, outside its numbered list:

45. **Conversion golden vectors:** for 1550 kJ; 0.6 g, 0.03 g and 0 g salt; a half-even tie at the sixth place; a half-away tie at the first place; `<0.01g` and `<0.1g` bounds; and a lower bound: the operand, quotient, `intermediate_text`, `stored_text`, `Double(stored_text)` and the canonical JSON bytes of the conversion record equal the pinned values.
46. **Conversion verification:** a record whose `stored_text` or ledger amount differs from the recomputation fails `invalidPastedLabelSource`; a changed `intermediate_text` alone does not.
47. **Derivation predicate:** `NutrientDerivation.calculatedTransform` is true for exactly the two allow-listed pairs and false for any other id, version or transform; a fixture pins the append-only v1 entries.
48. **Boundary script:** `check-boundaries.sh` fails on fixtures using `@testable import`, `import struct NutritionLabelParsing.X`, a `Package.swift` dependency edge, an app-target import, and `FoodLedgerPresentation` importing `FoodLabelTextCapture`.

### 8.5 Extension axes

- **Photo routes.** A future on-device OCR (route B) or multimodal (route C) photo route produces the same `LabelCaptureCandidate`, runs the same gate and checks, and feeds the same Confirm source section with the image in place of the pasted text. Each needs its own contract; route C also needs a privacy and egress change and owner approval. Neither is authorised here.
- **Partial reading.** A later parser version that returns the cells it could bind (instead of declining on a count or unit mismatch) would move the parser v2 hard-decline group into Confirm flags; it needs its own evaluation first.
- **Assisted identity choices.** `basis_state_not_supported` can become an assisted choice ("as prepared" values) under a new identity mapping version.
- **Layouts.** A new layout (US, then others) is a new gate format with its own mandatory rows and test vectors, under a new gate version; the parser and Confirm do not change unless the layout needs new vocabulary (a new parser version).
- **Closed:** what counts as a stored value, unknown handling, the Log rule, provenance and the manifest's byte-exact retention.

### 8.6 Delivery: five PRs, then serving v2

As the architecture gate report sets out. Each PR runs the full validation gates, carries its ledger row in `DEVELOPMENT_NOTES.md` and its own `Refs` lines.

1. **Parity ports in `NutritionLabelParsing`:** gate v2 with its frozen tables, arithmetic checks v1, conversions v1, format inference, and the vector export script on the evaluation code. Tests 1 to 9 and 25. No app wiring.
2. **Domain and manifest:**
   - the `NutrientDerivation` predicate;
   - `food-intake-summary-v3`;
   - the `pasted-label-identity-v1` constants;
   - manifest encode and verify, including corrections;
   - `minimumContractVersion` 7;
   - migration `v7_pasted_label`;
   - golden round-trips.

   Tests 17, 18, 29 to 32 and 38.
3. **Application and adapter:** the `LabelTextReading` port, the `FoodLabelTextCapture` adapter, the launch scope, the confirmation builder including corrections and flags, save and reopen verification, and the boundary script changes. Tests 10 to 16, 19 and 26 to 28.
4. **UI:** the Label text screen, decline copy, the Confirm source section with editing and flags, the origin formatter, the disclaimer and the misread preview, plus the verbatim privacy edits (section 7) and the effective date. Tests 20 to 24, 33 to 37, 39 to 44, and a simulator journey.
5. **Release:** the `docs/releases/unreleased.md` row (section 6.6) and the owner's pre-release real-text check (Taiwan, at least 20 labels; section 9).

6. **Servings on per-100 columns (decision 14, before release):** `pasted-label-serving-v2`, the serving-size correction on any stored column, save and reopen verification of both methods. Tests 49 to 53.

Tests 45 to 48 ride with the PR that builds their code: 45 with PR 1 (conversions), 46 and 47 with PR 2 (manifest verification and the predicate), and 48 with PR 3 (boundary script).

### 8.7 Architecture gate findings applied (18 October 2026)

| Severity | Finding | Where |
|---|---|---|
| High | Freeze gate v2's simplified-only set as a hashed data table; exhaustive parity | 8.2, test 25 |
| High | Exact conversion record, 6-decimal half-even intermediate, verification on the stored 1-decimal string then `Double(String)`, golden JSON bytes | 3.5, tests 45 and 46 |
| Medium | `NutrientDerivation.calculatedTransform`, `NutrientValueOrigin`, one formatter | 3.5, 8.1, tests 33 and 47 |
| Medium | `PastedLabelLaunchScope` after a faithful gate, recorded in the manifest | 5, 6.1, test 26 |
| Medium | Every code mapped to copy, `unreadable_table` fallback | 3.1, test 27 |
| Medium | Contract 7 checked first | 6.6, test 30 |
| Medium | `check-boundaries` over the app target, `Package.swift` and every import form; Presentation never imports the adapter | 8.2, test 48 |
| Medium | Origin-neutral `LabelReading` and `LabelTextReading` | 8.1 |
| Medium | Misread report from a pure builder, no name or brand prefill | 8.1, 9.1, test 34 |
| Medium | `user_verified_panel` admitted only through a `sourceID`-keyed, append-only verifier list | 6.1, test 32 |
| Low | Transform ids aligned with the identity contract (`salt_to_sodium_v1`, `kj_to_kcal_v1`) | 3.5 |
| Low | 8,000 limit counted in Unicode scalars | 6.2, test 37 |
| Low | No-retention test (no scene or app storage, no `UIPasteboard` reads) | 8.3, test 36 |
| Owner sign-off | Totals set `includesEstimates` under `food-intake-summary-v3` | 3.5, test 29 |
| Owner sign-off | `pasted-label-identity-v1`, `basis_state_not_supported` | 6.5, 3.1, test 28 |
| Delivery | Contract tests 25 to 38 and the five-PR phasing, as the gate report states them; privacy wording ships with the UI PR | 8.4, 8.6 |
| Migration and restore | v6 to v7 table-hash migration test; reopen after restore against the manifest | 6.6, tests 31 and 38 |
| Policy wording | Verbatim wording and a new effective date checked by a test | 7, test 35 |
| Owner principle | Assisted UX: correction on Confirm, partial tables as flags, disclaimer, per-value origin; tests 39 to 44 | 1.1, 1.2, 2.3, 3.1, 3.2, 6.1 |

### 8.8 Interpretations settled in PR 3 (owner-approved, in session, 19 October 2026)

- **`flags_shown`** records the G3 to G6 flags still shown at Log. A flag whose row, cell or serving line the user has entered or corrected is no longer shown, so it is left out; the entry itself is in `corrections`.
- **Warning codes** in `warnings_shown` take the form `<check>:<basis>[:<nutrient>][:<child>]` for each failed `label-arithmetic-checks-v1` check, for example `energy:per_100g` or `subrow_not_above_parent:per_100g:sugars`.
- **Basis-state markers** for `basis_state_not_supported` (section 6.5) are "prepared", "drained", 沖泡 and 瀝乾, looked for in a header's printed text and its serving wording. The English markers match whole words only, case-insensitively (a word is a run of letters), so "unprepared", "undrained" and "preparedness" do not match; 沖泡 and 瀝乾 match as substrings (owner, in session, 19 October 2026).

## 9. Measuring real pasted text without collecting user data

Real pasted text is unmeasured, so v1 has a measurement plan that collects nothing from users automatically. **No telemetry.** The release gate below applies per shipped language: Taiwan first, then UK English (decision 3).

1. **Pre-release owner check (release gate, decision 11).** Before any user sees the route, the owner copies real labels from public pages (retailer product pages, manufacturer PDFs, Taiwan product pages) into the CLI `NutritionLabelTextParse` and on a device build. Each result is checked against its source. The texts stay outside the repository; the repository gets counts, page kinds and hashes only. Bar: zero wrong values in any non-declined table; declines and their reasons are reported, not gated. The owner also records, as the user would see them, the flags shown, the correction burden (values corrected or entered per table) and any residual error after checking (section 1.2). Any wrong value stops release and goes to a new parser or gate version.
2. **Owner-run local regression.** The owner's private real-text set is re-run against every new parser or gate version before it ships, with the same bar.
3. **Developer tools.** On the owner's own device, Developer tools show, for any logged label, the manifest, its versions, and a re-parse with the current parser with differences, so a reported misread can be reproduced locally.
4. **Report a misread (in v1, decision 12, changed).** The only way real pasted text from users reaches anyone is a report the user decides to share (section 9.1).

### 9.1 Report a misread

- **Where:** a "Report a misread" action on Confirm, on the saved entry of a logged label, and on the decline state of the label text screen.
- **What it builds:** a plain-text report, shown in a preview the user can edit, containing: the pasted text; each value read with its printed source text, basis and "Calculated" label where it applies; the serving size and servings per pack as read; the decline reasons, if declined; the warnings shown; and the parser, gate, check and conversion versions. It is built by the pure application report builder. It never prefills the name or brand, and contains no other food entry, no health data, no notes and no device or account identifier.
- **What the user does:** edits or trims the preview, then taps **Share**, which opens the iOS share sheet with that text only; the user chooses the destination (for example Mail, Messages, Notes or Copy). **Cancel** at the preview or in the share sheet sends and writes nothing.
- **What the app never does:** choose or prefill a destination, send without the share sheet, retry, queue, attach anything else, or record that a report was made. Nothing in the ledger changes.
- **Privacy:** this is a user-initiated share under the existing clipboard and share-sheet row, not new app egress (section 7).

## 10. Owner decisions

Decisions 1 to 12 were answered by the owner, in session, 18 October 2026. Ten follow the recommendation; decisions 6 and 12 were **changed from the recommendation**. Decision 13 comes from the assisted-UX principle and was answered by the owner, in session, 18 October 2026, as recommended. Decision 14 was decided by the owner, in session, 19 October 2026; decision 15 records a display amendment the owner was told of the same day.

1. **Entry point.** Should "Paste nutrition label" be its own row in Add food, rather than detected automatically inside "Paste or dictate"? *Recommendation: yes.* **Decided: yes,** its own row, separate from the paste list.
2. **The failed mutation bar.** Should route A proceed to product although arithmetic mutation detection was 110/116, given that the check is warning-only and never authorises a save? *Recommendation: yes.* **Decided: yes,** ship; the check is a warning only, with no "checked" badge.
3. **English at launch.** Should UK English labels ship in v1 on development-only evidence plus the pre-release real-text check? *Recommendation: yes only with at least 20 real UK labels and zero wrong values; otherwise Taiwan first.* **Decided: Taiwan ships first;** UK English ships only after at least 20 real public UK label texts read with zero wrong values.
4. **US layout.** Should US "Nutrition Facts" pastes decline in v1? *Recommendation: yes.* **Decided: yes,** declined in v1.
5. **Pasted text or hash.** Should the manifest keep the pasted text verbatim? *Recommendation: verbatim.* **Decided: verbatim.**
6. **Conversion.** Should kJ-only energy and salt-only sodium stay unknown in v1? *Recommendation: yes, stay unknown.* **Decided, changed from the recommendation: convert,** kcal = kJ ÷ 4.184 and sodium = salt ÷ 2.5. Each value is labelled as calculated (an estimate), shown with its printed source, never presented as printed, recorded with its rule and version, and never used when the counterpart is printed (section 3.5).
7. **Provenance kind.** Should label-sourced values use the existing `user_verified_panel` kind with `source_id = pasted-nutrition-label`? *Recommendation: yes.* **Decided: yes.**
8. **Reuse.** Should a logged label become a reusable library food under its entered name, with favouriting only by the explicit action? *Recommendation: yes.* **Decided: yes.**
9. **Version bump.** Should a logged label move the store to food contract 7 and `food-ledger-v7`? *Recommendation: yes, metadata-only.* **Decided: yes,** metadata-only migration, existing records keep their bytes, with a release note in the 0.2.0 form (section 6.6).
10. **Adapter target.** Should the parser reach the application through a new `FoodLabelTextCapture` adapter behind an application-owned port? *Recommendation: yes.* **Decided: yes.**
11. **Pre-release check size.** Should the release gate be at least 20 real public labels per shipped language, with zero wrong values? *Recommendation: yes.* **Decided: yes.**
12. **Report a misread.** Should the opt-in "Report a misread" wait for its own contract and privacy update? *Recommendation: yes, defer.* **Decided, changed from the recommendation: in v1,** because privacy is the user's decision. It is a strictly user-initiated share through the iOS share sheet, with no app-controlled destination and no background collection. The existing clipboard and share-sheet row in `privacy-and-egress.md` and the privacy policy wording are updated to cover its content, with the exact wording in section 7, applied in the implementation PR (sections 7 and 9.1).
13. **User values in totals.** Should values the user corrected or entered on Confirm count as estimates in day and report totals (setting "Includes estimates")? *Recommendation: no; they are user-asserted and shown per value as "Corrected by you" or "Entered by you".* **Decided: no.** User-corrected and user-entered values do not flag totals as including estimates; only calculated values do.

14. **Servings on a per 100 g (per 100 ml) column (19 October 2026).** Section 2.3 offered servings whenever a serving size with a quantity and a g or ml unit is printed, but `pasted-label-serving-v1` covered only a per-serving stored column, so PR 4 did not offer servings or whole pack on a per 100 g column. **Decided by the owner, in session, 19 October 2026: build it before release, as a new serving policy version** (`pasted-label-serving-v2`, section 6.3). v2 is used only for per-100 columns; v1 stays the method for per-serving columns, unchanged, so every stored v1 record keeps its bytes and meaning. The smallest change that leaves stored v1 records valid was a second, append-only method rather than superseding v1. Tests 49 to 53.

15. **Display of calculated bounds (19 October 2026).** Section 3.5 said every calculated value shows "about" and is rounded half away from zero. A calculated bound cannot honestly read "about": the implementation (PR 4) shows it as a bound with the "Calculated" tag ("Less than 5 kcal · Calculated") and rounds its upper end up so the shown bound still contains the stored value. **The owner was told in session, 19 October 2026,** and section 3.5 is amended to match; an exact calculated amount still shows "about" and rounds half away from zero.

**Follow-on work, not v1.** Parser v2 binding failures (count mismatch, missing or unrecognised unit, no or duplicate basis header, multiple panels) stay hard declines in v1, because parser v2 returns no cells for them. In line with the owner's assisted-UX principle, turning them into per-cell flags on Confirm is follow-on work: a new parser version that returns the cells it could bind, plus its own evaluation, before any product use.

## 11. Not changing

- `food_confirmation_v5`, its requirements and its assertion grammar; the review manifest v2; parser v2; the evaluation and its frozen artefacts.
- `privacy-and-egress.md` and `privacy-policy.txt` in this contract's PR. Their required wording (section 7) ships with the implementation; even then no egress row and no destination is added.
- HealthKit (read-only); the Health report, Copy all and Daily JSON.
- Photo capture of any kind (#93's photo route stays unpromoted).
