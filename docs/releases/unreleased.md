# Unreleased changes since 0.2.0 (25)

Release notes to carry into the next internal TestFlight build. Each entry names the merged change; when a build ships, move the relevant entries into that build's record and clear them here. The UX revamp entries moved to [0.2.0 (25)](internal-testflight-0.2.0-build25.md).

## Older builds cannot open the food data after updating

Pasted nutrition label v1 ([contract](../pasted-nutrition-label-v1.md), #93) moves the food ledger to a new schema. Once a device opens the food log with a build that contains this change, the stored data is migrated forward and **an older build can no longer open it** (it reports an unknown schema). Reinstalling an earlier build after updating is not a safe way back; export or back up first.

| Change | Merged in | Archive contract | Schema |
| --- | --- | --- | --- |
| Pasted nutrition label: domain, manifest and storage (PR 2 of 5; no route or screen yet) | PR 2 (#93) | 7 | `food-ledger-v7` |

The migration (`v7_pasted_label`) changes metadata only: existing records keep their bytes and no table is added. A backup exports contract 7 only when it holds a pasted-label entry; otherwise it exports contract 6 exactly as before. The Daily JSON export stays pinned to food contract 3, so exported files are unchanged in shape.

## Food totals

- Summary policy `food-intake-summary-v3` (#93, PR 2): a day or period total that includes a calculated value (kcal from a printed kJ value, or sodium from a printed salt value, `pasted-label-conversions-v1`) shows the existing "Includes estimates" indicator. Values the user corrected or entered do not. Nothing else in the totals changes, and no stored record changes; until the paste route ships, no entry has a calculated value, so every total reads as before.
