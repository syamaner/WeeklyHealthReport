# Count conversion method v1 (#299)

Status: **owner decision of 23 October 2026, in session.** It amends [food-confirmation-contract-v2.md](food-confirmation-contract-v2.md) (a count needs a measured edible weight or volume), [food-confirmation-contract-v5.md](food-confirmation-contract-v5.md) (`countNeedsMeasuredAmount`) and [direct-edible-weight-contract-v1.md](direct-edible-weight-contract-v1.md) (the estimated weight basis). Follow-up to #296 (PR #298), which labelled the free-text method field.

## 1. Decision

On Confirm, a count without a source-backed size guide asks for the total edible weight or volume and how it was obtained. The method is no longer free text. It is one choice from a closed set:

| Shown label | Meaning | Stored as |
|---|---|---|
| Kitchen scale | The user weighed or measured the food they ate | A measured count conversion with method code `user_count_conversion_v1:kitchen_scale` |
| Package weight | The amount comes from the package (for example a stated pack or piece weight) | A measured count conversion with method code `user_count_conversion_v1:package_weight` |
| Estimated by eye | The user guessed the amount | **Not a conversion.** The existing direct edible weight declaration with basis `estimated` (section 3) |

There is no free-text option on a new entry, and nothing is chosen for the user: the picker starts at "Choose one" and Log stays blocked by `countNeedsMeasuredAmount` until a method and a positive amount are given.

## 2. Measured choices: code and label

- The method code is written to the existing `QuantityConversionVersion.methodVersion` text, the same field and record a typed method used, so **no persisted format, operation type, archive contract or schema identity changes**. This follows the pattern already used for pasted-label serving conversions, whose `methodVersion` names an admitted method.
- The shown label is a pure function of the versioned code: the v1 table above is frozen, and a new or renamed label needs a new code version (`user_count_conversion_v2:…`). The label is therefore not stored a second time; storing it would need a new field and a format version for no gain in what can be shown.
- Closed set: a save whose conversion `methodVersion` starts with `user_count_conversion_v` and is not one of the two v1 codes is rejected (`invalidQuantity`), so a mistyped or future code fails closed. There is no estimate code.
- The amount may be in g or mL, as today. The conversion keeps `sourceReleaseID` and `evidenceID` empty, as a typed conversion did. Nutrition, unit conversion and totals are unchanged.

## 3. Estimated by eye

- Choosing "Estimated by eye" moves the entry to the direct edible weight path of [direct-edible-weight-contract-v1.md](direct-edible-weight-contract-v1.md) with basis **`estimated` already selected**, because the user has just made that explicit choice. The count stays as the original input (for example 3 count). A gram amount already typed is carried into the gram field; a millilitre amount is not reinterpreted as grams, so the gram field starts empty.
- The saved record is the existing `weightDeclaration` v1 with `basis = estimated` under `confirm_food_v2`. It is never a `QuantityConversionVersion`.
- The entry is therefore an estimate everywhere the estimated basis already reaches: Confirm, the saved entry, the Food Log estimate tag, day totals that include estimates, recent foods and the Health report. Nothing new is added to those surfaces.
- The user can still switch that basis to "I weighed it" or return to the count with "Use original amount instead", exactly as in direct weight v1.

## 4. Records written before this amendment

- Typed methods already stored (any `methodVersion` text that is not a v1 code) decode, re-encode and verify byte for byte unchanged. No record is rewritten or relabelled.
- On reopen, a stored typed method is shown as typed ("Recorded: …") and kept as the selected method, so re-saving the entry without changing the amount writes the same method text. Choosing one of the three options replaces it, as any edit does.
- The Confirm row "Weight or volume method" shows the v1 label for a v1 code and the stored text otherwise.

## 5. Unchanged

The count rule itself, source-backed and offered volume conversions, pasted-label servings, recipe and source servings, plate subtraction, direct weight v1, the Daily JSON food export (it carries no conversion method), and the absence of any size guide. A source-backed egg size guide still needs a new source, a contract and owner approval.

Amended 24 October 2026 by [count-portion-estimate-v1.md](count-portion-estimate-v1.md) (#307): allow-listed whole raw and boiled egg records pre-fill a cited typical weight as a labelled estimate (`count_portion_guide_v1:*`), the method choice and amount use one layout, and counts read "pieces" everywhere.

## 6. Contract tests

1. Kitchen scale and package weight save a conversion with exactly their v1 code; reopen restores the same choice and the shown label.
2. Estimated by eye writes no conversion: the saved log item carries `weightDeclaration.basis = estimated`, the original count input, and the intake and Food Log projections mark it as an estimate.
3. A legacy typed method round-trips: save, reopen and re-save keep the same text; the stored conversion record re-encodes to identical bytes.
4. An unknown `user_count_conversion_v…` code is rejected at save.
5. Log is blocked until a method and a positive amount are chosen, with a field-local message naming the missing part.
6. Simulator: egg, count 3, 168 g with each of the three options; the first two log as measured, the third logs as an estimate.
