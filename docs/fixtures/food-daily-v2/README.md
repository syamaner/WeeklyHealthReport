# Food daily export v2 fixtures (#312)

Synthetic files for `food_daily_schema_version: 2` ([food daily export contract v2](../../food-daily-export-contract-v2.md)). Every identifier, time, food and value is invented.

These four files are **hand-built** (contract section 10, PR 2): the app does not write schema 2 yet. Each one is the frozen v1 golden of the same synthetic day in [`../food-daily-v1/`](../food-daily-v1/) with three changes and nothing else:

1. `food_daily_schema_version` is `2`.
2. Every entry's `quantity` carries `amount_method`, spelt from that day's stored records by the contract's section 3.2 table.
3. `notes` carries the constant `quantity_estimates` sentence (section 3.4).

| File | Entries and their `amount_method.code` |
|---|---|
| `food-daily-empty-day.json` | none |
| `food-daily-plain-water-only.json` | water, `direct` |
| `food-daily-typical-weight-day.json` | three medium boiled eggs, `typical_weight` (entered 3 `count`, size `medium`) |
| `food-daily-mixed-day.json` | soup `estimated_by_eye` (no stored original input, so `entered` is `null`), then water, crackers and a product, all `direct` |

A contract test checks that each file, with the two v2 fields removed and the schema set back to 1, equals its v1 golden byte for byte. The writer PR (PR 3) must generate these same bytes from the same synthetic days (contract test 10) and adds the days these files do not cover (a whole-milk day and a day with every code) as new files; it does not change these.
