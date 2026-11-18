# Food daily export v3 fixtures (#511)

Synthetic files for `food_daily_schema_version: 3`: [food daily export contract v2](../../food-daily-export-contract-v2.md)'s shape plus the estimate fields of [estimates on catalogue v2](../../personal-food-catalogue-estimates-v2-proposal.md) (section 7, "Daily export version 3"). Every identifier, time, food and value is invented.

Version 3 is written only for a document that holds at least one `approved_estimate` value. Any other document is written as version 2, byte for byte as before, so [`../food-daily-v2/`](../food-daily-v2/) is unchanged.

`ApprovedEstimateExportContractTests` holds the file here to the builder's output byte for byte; `RECORD_FOOD_DAILY_V3_GOLDENS=1` rewrites only this folder.

| File | Entries |
|---|---|
| `food-daily-estimates-day.json` | Three entries logged from the synthetic estimates v2 catalogue: a bar with scaled label values and one page estimate (`high`); a tinned fish whose three values are composition estimates from its own record; crisps with a derived sodium estimate (`medium`, calculated) and a fibre estimate the owner left out, which exports as unknown. |

Each `approved_estimate` value has `origin: "approved_estimate"`, `state: "estimated"` and, in its provenance, `estimate_source_type`, `estimate_method`, `estimate_state_basis` and `estimate_quality`. A page estimate also has `source_url` (query string and fragment dropped) and, when a source artefact was kept, `content_hash`. No free text (states or assumptions) is exported.
