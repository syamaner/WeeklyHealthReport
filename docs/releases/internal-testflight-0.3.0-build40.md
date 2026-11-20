# TestFlight 0.3.0 (40)

Status: **0.3.0 (40) is the build testers should install.** It was uploaded on 19 November 2026 on the owner's yes, processed as VALID, given the What to Test text below (en-GB) and added to the Internal Testing group the same day, each external step on the owner's yes to setting that text and adding the build to the group. It was exported with `testFlightInternalTestingOnly`, so App Store Connect never offers it to an external group or the App Store.

**This build reads the catalogue files written under amendments G1 to G8** (G6 deferred). Build 39 rejects such a file whole with `estimate-own-merge` or `estimate-basis`, so the rebuilt catalogue needs this build. **No store, food contract or export schema changes since build 39**: the food log is not migrated. HealthKit stays read-only, and the app adds no destination.

This record covers what changed after [build 39](internal-testflight-0.3.0-build39.md), which was archived from `main` at `71756937`.

## Upload receipt

| Item | 0.3.0 (40) |
| --- | --- |
| Uploaded | 19 November 2026 |
| Source | `main` at `f4a6db9588636bdb345064ebd7dbb67b593758aa` ([PR533](https://github.com/syamaner/WeeklyHealthReport/pull/533)), archived from a clean worktree |
| Ancestry checked before archiving | `befecdb7` (PR525), `cf69ec1d` (PR527), `781565fd` (PR531), `05587add` (PR529), `f4a6db95` (PR533); PR534 is in too |
| Bundle and version | `com.otherweather.ReportWeeklyHealth`, 0.3.0 (40) |
| Version overrides | `CURRENT_PROJECT_VERSION=40`, `WEEKLY_HEALTH_REPORT_BUNDLE_IDENTIFIER=com.otherweather.ReportWeeklyHealth`, `DEVELOPMENT_TEAM=MDNYU95CGT` |
| Signing team | `MDNYU95CGT` |
| Executable UUID | `847F3FE2-D5FA-3786-958D-C1824722D303` (arm64) |
| Uploaded IPA SHA-256 | `9fd49d1b3f9705e62fb4d4792a0011dd4297a8f7acd99f7c6061e40562ad1b11` |
| Delivery UUID | `b5f61dd9-a38d-46ee-b769-406a056899b8` |
| Processing | VALID (App Store Connect build id is the delivery UUID); internal state ready for beta testing |
| TestFlight | What to Test set (en-GB); in Internal Testing and not in External Testers, confirmed through `GET /v1/betaGroups/{id}/relationships/builds` |
| Google Drive configuration | Present (the archive's Info.plist has no `MISSING` value) |

Method: as for [build 39](internal-testflight-0.3.0-build39.md): `xcodebuild archive` (Release, automatic signing with `-allowProvisioningUpdates` and the App Store Connect API key), `xcodebuild -exportArchive` with [`Config/ExportOptions-internal-testflight.plist`](../../Config/ExportOptions-internal-testflight.plist), then `xcrun altool --upload-app`. The API key stays in `~/.appstoreconnect/private_keys/` and is passed to the tools by path only. The first archive attempt stopped with a disk I/O error in the shared Xcode build database (infrastructure, not code); the archive was re-run once with its own derived data folder and succeeded.

Validation: the amendment PRs in this build (PR525, PR527, PR529, PR533) each passed the six AGENTS.md gates locally before merging (PR533 at `eaf99440`, including `xcodebuild test`) and a blind invariant review; PR531 and PR534 are documentation only. The full app test suite was not re-run locally for this archive. The owner's private catalogue was rebuilt with the skill writer at this commit and passed the app's own importer check locally; no private data is in this record.

## Your food database: gap estimate amendments

- **G1 to G3 (PR525).** A national table's generic dish record may fill a composite dish at `low` with the fixed sentence "A generic recipe, not this product's."; per 100 ml rules (`estimate-basis` moved to the importer); label photos admitted over an Open Food Facts refusal row. See [the amendment](../personal-food-catalogue-gap-estimates-v1-amendment.md).
- **G4 (PR527).** An estimate from the entry's own merge record that the app does not merge is admitted at most `medium`; a merged value always wins. See [the amendment](../personal-food-catalogue-own-merge-amendment-v1.md).
- **G5 (PR529).** A generic web page for the same kind of dish may fill a composite dish at `low` with the fixed sentence. See [the amendment](../personal-food-catalogue-composite-web-amendment-v1.md).
- **G7 and G8 (PR533).** Another brand's label may fill a composite dish at `low` with the fixed sentence; page addresses may carry their query string only for two composition-table record addresses (the MEXT food composition database and nutritionvalue.org's 100 g view). Exports keep dropping query strings. G6 (density) was deferred. See [the amendment](../personal-food-catalogue-tables-composites-amendment-v1.md).
- **MyFoodData (PR531).** Documentation and skill only: a named source for the catalogue skill, with its egress wording approved by the owner. No app change.

## What to Test

```
Build 40 (internal only)

No store or file format change since build 39: your food log is not migrated.

Your food database, rebuilt catalogue (new rules):
- In Settings, import the rebuilt catalogue file (personal-food-catalogue-estimates-v3.json from iCloud). Build 39 rejects this file; this build should accept it.
- Almost every food should now open with energy, protein, fat and fibre filled. Check a few that were empty before.
- Ready meals may show rough estimates from a generic recipe or another brand's label. Each says "Estimated", is at the lowest tier, and its details say "A generic recipe, not this product's."
- Some drinks and sauces are now filed per 100 ml.
- Estimates read from a Japanese food table or nutritionvalue.org page show that page in details.
- Leave out one estimated nutrient on Confirm before you log: it should stay unknown, never zero. A value from your own label is never replaced.
```

## Still to do

- The owner's device check: import the rebuilt catalogue on build 40 and walk the What to Test steps above.
- Before any external build: the items listed in the [build 36 record](internal-testflight-0.3.0-build36.md#still-to-do), and a separate archive exported without `testFlightInternalTestingOnly`.
