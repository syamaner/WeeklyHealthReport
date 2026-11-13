# Open Food Facts values label v1

Status: owner decision taken, 12 November 2026 ("keep them as estimates and say why"). Presentation only: no stored record, total, export or contract value changes.

## Problem

An Open Food Facts product's values are stored as `augmented`, because the barcode contract ([`off-barcode-candidate-plan-v1.md`](off-barcode-candidate-plan-v1.md), rule 5) treats a selected external record as an estimate. So a product logged exactly as sold reads "Estimate" on its Food Log row and "· Estimated" beside every value on the saved entry, with nothing saying why. Found in the #470 journey (D3, 11 November 2026).

## Decision

The values stay estimates. The labels name the source instead of a bare "Estimate", and keep the word estimate, so a product value is never read as checked (invariant review, 12 November 2026):

1. **An Open Food Facts value** is an `augmented` value, or a bound whose origin is `augmented`, whose provenance is non-empty and names only `sourceKind == exactProductDataset` and `sourceID == "open-food-facts"`. One pure application predicate, `OpenFoodFactsValues`, decides this; nothing else re-implements it.
2. **Food Log row and Recent foods:** where the entry would read "Estimate" and its only estimated values are Open Food Facts values, the flag reads "Open Food Facts estimate" instead. "Estimate" still wins when any other reason holds: a generic or decided estimate (`FoodEntryEstimateStatus.isEstimate`), an estimated amount, a calculated energy bound, or any estimated value from another source. "Partly estimated" (an estimate layer) is unchanged and still wins over both.
3. **Saved entry values:** an Open Food Facts value reads "· Open Food Facts estimate" instead of "· Estimated". Values filled by an estimate layer keep their own estimate marking. An Open Food Facts bound has no consumed amount, so it is stated as stored for the entry's basis with the same marking, never as "Unknown" or zero: "Less than 0.5 g per 100 g · Open Food Facts estimate", "0.5 g or less per 100 g · …", and for a lower bound "More than 3 g per 100 g · …" or "3 g or more per 100 g · …".
4. **Unchanged:** stored values and provenance; `includesEstimates` in totals, the Food Log strip caption, Health, Copy all and the daily export (the values are still estimates); Confirm; the source line ("Open Food Facts · source estimate", stored in the candidate's variant); Favourites and quick add, which already show no estimate for these entries.

## Tests

- The predicate: an Open Food Facts augmented value and bound qualify; a generic augmented value, a measured value, a mixed-provenance value and a value with no provenance do not.
- Food Log row: an Open Food Facts entry reads "Open Food Facts estimate"; with an estimated amount or a decided estimate it reads "Estimate"; with a layer it reads "Partly estimated".
- Recent foods follows the row's rule.
- Saved entry: "12 g · Open Food Facts estimate" for an Open Food Facts value, "· Estimated" for a generic one.
- Saved entry bounds: each of "<", "<=", ">" and ">=" reads as the bound per 100 g with the marking; the stored bound and its missing consumed amount are unchanged.
