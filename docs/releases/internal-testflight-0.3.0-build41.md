# TestFlight 0.3.0 (41)

Status: **0.3.0 (41) is the build testers should install.** It was uploaded on 19 November 2026 on the owner's request, archived before merging so it could be checked on the device first, processed as VALID, given the What to Test text below (en-GB) and added to the Internal Testing group the same day on the owner's yes. It was exported with `testFlightInternalTestingOnly`, so App Store Connect never offers it to an external group or the App Store. The owner confirmed on the device the same evening that food search works with the rebuilt catalogue.

**This build fixes food search with Your food database** ([issue 536](https://github.com/syamaner/WeeklyHealthReport/issues/536), [PR537](https://github.com/syamaner/WeeklyHealthReport/pull/537)). On [build 40](internal-testflight-0.3.0-build40.md), importing a catalogue file with estimates made every offline search result disappear, and search went straight to the online lookup. **No store, food contract or export schema changes since build 40**: the food log is not migrated.

## Upload receipt

| Item | 0.3.0 (41) |
| --- | --- |
| Uploaded | 19 November 2026 |
| Source | branch `fix/536-composite-estimate-evidence` at `8efa6835f723ee42ec0028e660f76ec64ce6f680`, archived before PR537 merged at the owner's request; PR537 then merged that same head into `main` as `d1f8f9e7` |
| Bundle and version | `com.otherweather.ReportWeeklyHealth`, 0.3.0 (41) |
| Version overrides | `CURRENT_PROJECT_VERSION=41`, `WEEKLY_HEALTH_REPORT_BUNDLE_IDENTIFIER=com.otherweather.ReportWeeklyHealth`, `DEVELOPMENT_TEAM=MDNYU95CGT` |
| Signing team | `MDNYU95CGT` |
| Executable UUID | `0A5F597A-5EF3-373A-B4E9-38A9D1FA863F` (arm64) |
| Uploaded IPA SHA-256 | `866d64d7207017497eb2a2797b29749f78667c3b247dcf9b4e9fb84f6ccc520e` |
| Delivery UUID | `d32f75c6-35bf-4955-b5fa-f11d59d022b7` |
| Processing | VALID (App Store Connect build id is the delivery UUID); internal state ready for beta testing |
| TestFlight | What to Test set (en-GB); in Internal Testing and not in External Testers, confirmed through `GET /v1/betaGroups/{id}/relationships/builds` |
| Google Drive configuration | Present (the archive's Info.plist has no `MISSING` value) |

Method: as for [build 40](internal-testflight-0.3.0-build40.md), with its own derived data folder: `xcodebuild archive` (Release, automatic signing with `-allowProvisioningUpdates` and the App Store Connect API key), `xcodebuild -exportArchive` with [`Config/ExportOptions-internal-testflight.plist`](../../Config/ExportOptions-internal-testflight.plist), then `xcrun altool --upload-app`. The API key stays in `~/.appstoreconnect/private_keys/` and is passed to the tools by path only.

Validation: PR537 passed the six AGENTS.md gates locally at `ff73b8a8` (including `xcodebuild test`); the commit on top, `8efa6835`, changed only the evidence merge's conflict check and its test, and the personal food database search tests passed after it. A blind `invariant-reviewer` and a general defect review ran at `ff73b8a8`. The owner's private catalogue was searched locally with the app's own composite wiring before and after the fix; no private data is in this record.

## Food search with Your food database (#536, PR537)

- **Cause.** Your food database binds each candidate with estimates to a capture manifest and returns it in its route's evidence. The composite search built the combined confirmation from the first route's evidence only, so when a CoFID or USDA route came first the manifest was missing, the confirmation threw `missingProvenance` and every offline row was dropped.
- **Fix.** The composite keeps the evidence of every route, first route first, each evidence ID once, and throws when two routes send the same ID with different content. Saving is unchanged: only the selected candidate's manifest is stored, as before.
- **Why build 40 did not show it in testing.** The catalogue installed before build 40 carried no estimates, so the path had not run on a device. The importer check run before build 40 covered the codec and importer only, not the full composite search.

## What to Test

```
Build 41 (internal only)

Fixes food search with your food database: on build 40, importing a catalogue with estimates made every offline search result disappear (search went straight to "Looking for more matches online"). No store or file format change.

To check:
- Keep the rebuilt catalogue you imported on build 40 (or import personal-food-catalogue-estimates-v3.json from iCloud again).
- Search "Orange", "tea", "chicken" or a food from your own list: rows from the built-in tables and from your food database should both appear again.
- Open one of your foods with estimates: each estimated value says "Estimated" with its tier, and its details name the source.
- Log one: only the food you chose is saved, with its estimates.
```

## Still to do

- Before any external build: the items listed in the [build 36 record](internal-testflight-0.3.0-build36.md#still-to-do), and a separate archive exported without `testFlightInternalTestingOnly`.
