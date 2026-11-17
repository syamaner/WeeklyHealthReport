# Food daily export v2 fixtures (#312)

Synthetic files for `food_daily_schema_version: 2` ([food daily export contract v2](../../food-daily-export-contract-v2.md)). Every identifier, time, food and value is invented.

The app writes this schema from PR 3 (contract section 10). The contract tests hold every file here to the builder's output byte for byte for its synthetic day; `RECORD_FOOD_DAILY_GOLDENS=1` rewrites only this folder, never [`../food-daily-v1/`](../food-daily-v1/), which is frozen.

Four files were **hand-built** in PR 2, before any build wrote schema 2: each is the frozen v1 golden of the same synthetic day with `food_daily_schema_version` set to `2`, `amount_method` added to every entry's `quantity` (spelt from that day's stored records by the contract's section 3.2 table) and the constant `quantity_estimates` sentence added to `notes` (section 3.4). The PR 3 builder reproduced all four without re-recording (contract test 10), and a contract test still checks that each, with the two v2 fields removed and the schema set back to 1, equals its v1 golden. Two files were generated in PR 3 for the days the first four do not cover.

| File | Origin | Entries and their `amount_method.code` |
|---|---|---|
| `food-daily-empty-day.json` | hand-built, PR 2 | none |
| `food-daily-plain-water-only.json` | hand-built, PR 2 | water, `direct` |
| `food-daily-typical-weight-day.json` | hand-built, PR 2 | three medium boiled eggs, `typical_weight` (entered 3 `count`, size `medium`) |
| `food-daily-mixed-day.json` | hand-built, PR 2 | soup `estimated_by_eye` (no stored original input, so `entered` is `null`), then water, crackers and a product, all `direct` |
| `food-daily-whole-milk-day.json` | generated, PR 3 | 200 mL of whole milk as 206 g, `whole_milk_volume` (entered 200 `mL`, `size` `null`) |
| `food-daily-every-code-day.json` | generated, PR 3 | one entry per row of section 3.2: `direct`, `direct` with 2 `serving`, `weighed`, `estimated_by_eye` (3 `count`), `kitchen_scale`, `package_weight`, `typical_weight`, `whole_milk_volume`, `recorded` |
