# TestFlight 0.3.0 (39)

Status: **0.3.0 (39) is the build testers should install.** It was uploaded on 19 November 2026 under the owner's yes to all TestFlight preparation for this build, processed as VALID, given the What to Test text below (en-GB) and added to the Internal Testing group the same day. It was exported with `testFlightInternalTestingOnly`, so App Store Connect never offers it to an external group or the App Store.

**This build imports catalogue estimates v3, with label photo estimates** ([label photo estimates v1](../personal-food-catalogue-off-estimates-v1-proposal.md), #518, PR520). **It moves the food log to store version 11** the first time it opens it; build 38 cannot open the log afterwards. **It carries all of issue #508** (web lookup part-read pages). HealthKit stays read-only. Photo fetches are developer tooling only, as [privacy and egress](../privacy-and-egress.md) records; the app adds no destination.

This record covers what changed after [build 38](internal-testflight-0.3.0-build38.md), which was archived from `main` at `74c1fa4d`.

## Upload receipt

| Item | 0.3.0 (39) |
| --- | --- |
| Uploaded | 19 November 2026 |
| Source | `main` at `717569378147cb4f266f752ac546dbd28f7a7485` ([PR522](https://github.com/syamaner/WeeklyHealthReport/pull/522)), archived from a clean worktree |
| Ancestry checked before archiving | `0042ffa9` (PR520), `c55f7233` (PR519), `0b582293` (PR521), `71756937` (PR522); PR512 and PR515 were already in build 38 |
| Bundle and version | `com.otherweather.ReportWeeklyHealth`, 0.3.0 (39) |
| Version overrides | `CURRENT_PROJECT_VERSION=39`, `WEEKLY_HEALTH_REPORT_BUNDLE_IDENTIFIER=com.otherweather.ReportWeeklyHealth`, `DEVELOPMENT_TEAM=MDNYU95CGT` |
| Signing team | `MDNYU95CGT` |
| Executable UUID | `948D9E96-6B03-3AF6-86AF-D123BA47C190` (arm64) |
| Uploaded IPA SHA-256 | `f0f6ec3bcda878a15cc041ca53548e6d27914c503a5eb188b2161744cc3736bc` |
| Delivery UUID | `2b8aee5d-b5c2-4392-a6ff-490da2aa13ad` |
| Processing | VALID (App Store Connect build id is the delivery UUID); audience `INTERNAL_ONLY` |
| TestFlight | What to Test set (en-GB); in Internal Testing and not in External Testers, confirmed through `GET /v1/betaGroups/{id}/relationships/builds` |
| Google Drive configuration | Present (the archive's Info.plist has no `MISSING` value) |

Method: as for [build 37](internal-testflight-0.3.0-build37.md): `xcodebuild archive` (Release, automatic signing with `-allowProvisioningUpdates` and the App Store Connect API key), `xcodebuild -exportArchive` with [`Config/ExportOptions-internal-testflight.plist`](../../Config/ExportOptions-internal-testflight.plist), then `xcrun altool --upload-app`. The API key stays in `~/.appstoreconnect/private_keys/` and is passed to the tools by path only.

Validation: PR520, PR519 and PR522 each passed every required CI check before merging, including the app build and tests. The full app test suite was not re-run locally for this archive. The owner's private catalogue was rebuilt with the skill writer at this commit and passed the app's own importer check locally; no private data is in this record.

## Your food database: label photo estimates (#518, PR520)

- **Catalogue estimates v3.** A food database file can now carry values read from a product's nutrition panel photo in Open Food Facts, labelled "Product database label photo" in details, with the photo's address and its SHA-256. Their tier is never above medium ("some doubt"). An older build rejects a v3 file whole.
- **Food contract 11, store version 11** (`v11_label_photo_estimate`).
- **Daily food export, schema 5.** A day that holds a label photo estimate writes food file schema 5; every other day is written as before.
- **Estimates writer reads CoFID units as the app does (PR522).** A CoFID value held in another unit (today, water) is unknown, never converted, so the importer no longer refuses the file.

## Web lookup: all of issue #508

- Build 38 carried phases 1 and 2 without phase 3: larger pages read whole (PR512) and the choice between competing nutrition panels (PR515).
- **New in this build, phase 3 (PR519):** a page beyond 2,048 blocks or 100,000 characters is read in part, and the app says so.
- Contract test 21 results are recorded in [the test 21 results](../web-lookup-part-read-test21-results.md) (PR521), with two accepted gaps: the competing-panel case was tested on a constructed page, and a suggested panel with a competing panel beside it was not reached on a live page.

## What to Test

```
Build 39 (internal only)

Before installing: back up or export your food log. This build moves it to store version 11 the first time it opens, and build 38 cannot open it afterwards.

Your food database, rebuilt catalogue with label photo estimates (new):
- In Settings, import the rebuilt catalogue file (personal-food-catalogue-estimates-v3.json). Build 38 cannot read this file.
- Most foods that had no nutrition before should now open with estimated values, each saying "Estimated" with its tier in words.
- A value read from a product's label photo in Open Food Facts shows as "Product database label photo" in details. Its tier is never better than "some doubt".
- Fibre should now be known for far more foods. Check a few that had no fibre before.
- Leave out one estimated nutrient on Confirm before you log: it should stay unknown, never zero. A value from your own label is never replaced.

Daily food export: a day that holds a label photo estimate now writes food file schema 5. Do not export that day again from an older build.

Web lookup (all of issue 508):
- Build 38 already had larger pages read whole and the choice between competing nutrition panels.
- New in this build: a page beyond the reading bounds is read in part, and the app says so.
- Known gaps from testing: the competing-panel case was tested on a constructed page, and a suggested panel with a competing panel beside it was not reached on a live page.
```

## Before installing

- **Back up or export your food log first.** This build moves it to store version 11, and build 38 cannot open it afterwards.
- **Do not export a day from an older build after exporting it with this one.** An older build cannot read a schema 5 food file.

## Still to do

- The owner's device check of the v3 catalogue import, the label photo details and the part-read page message (the steps are in What to Test above).
- Before any external build: the items listed in the [build 36 record](internal-testflight-0.3.0-build36.md#still-to-do), and a separate archive exported without `testFlightInternalTestingOnly`.
