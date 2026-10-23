# Unreleased changes since 0.2.0 (25)

Release notes to carry into the next internal TestFlight build. Each entry names the merged change; when a build ships, move the relevant entries into that build's record and clear them here. The UX revamp entries moved to [0.2.0 (25)](internal-testflight-0.2.0-build25.md).

## Older builds cannot open the food data after updating

Pasted nutrition label v1 ([contract](../pasted-nutrition-label-v1.md), #93) moves the food ledger to a new schema. Once a device opens the food log with a build that contains this change, the stored data is migrated forward and **an older build can no longer open it** (it reports an unknown schema). Reinstalling an earlier build after updating is not a safe way back; export or back up first.

| Change | Merged in | Archive contract | Schema |
| --- | --- | --- | --- |
| Pasted nutrition label: domain, manifest and storage (PR 2 of 5; no route or screen yet) | [PR267](https://github.com/syamaner/WeeklyHealthReport/pull/267) (#93) | 7 | `food-ledger-v7` |

The migration (`v7_pasted_label`) changes metadata only: existing records keep their bytes and no table is added. A backup exports contract 7 only when it holds a pasted-label entry; otherwise it exports contract 6 exactly as before. The Daily JSON export stays pinned to food contract 3, so exported files are unchanged in shape.

## Paste a nutrition label

- **Paste nutrition label** in Add food ([contract](../pasted-nutrition-label-v1.md), [reader v3](../pasted-nutrition-label-reader-v3.md), #93): copy the Taiwan nutrition table (營養標示) from a product page as text, paste it with a name for the food, and tap Read label. The app reads the table on your device, with no network call, and fills in Confirm with the values it read; you check them against the label, correct or add anything, and nothing is saved until you tap Log. Values the label does not state are left as not read, never as zero.
- This version reads Taiwan 營養標示 text only, not photos, PDFs or labels in other languages. Some layouts are declined with a reason, for example a page with more than one nutrition panel or a table without a per serving or per 100 g heading; you can then edit the text, use Search or Barcode instead, or share the text with Report a misread, which goes only where you choose in the share sheet.
- The pre-release check on 24 real Taiwan labels found no wrong values in the 11 tables that reached Confirm and declined the other 13 ([results](../pasted-nutrition-label-reader-v3-release-check.md)); fewer declines are the aim of reader v4 (#301).

## Food totals

- Summary policy `food-intake-summary-v3` ([PR267](https://github.com/syamaner/WeeklyHealthReport/pull/267), #93): a day or period total that includes a calculated value (kcal from a printed kJ value, or sodium from a printed salt value, `pasted-label-conversions-v1`) shows the existing "Includes estimates" indicator. Values the user corrected or entered do not. Nothing else in the totals changes, and no stored record changes; until the paste route ships, no entry has a calculated value, so every total reads as before.
