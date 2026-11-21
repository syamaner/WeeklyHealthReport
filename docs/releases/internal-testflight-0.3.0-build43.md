# TestFlight 0.3.0 (43)

Status: **0.3.0 (43) is the build testers should install.** It was uploaded on 20 November 2026 on the owner's request, processed as VALID, given the What to Test text below (en-GB) and added to the Internal Testing group the same day on the owner's yes. It was exported with `testFlightInternalTestingOnly`, so App Store Connect never offers it to an external group or the App Store. Not yet checked on the device.

**This build adds food details from Your food database** ([issue 546](https://github.com/syamaner/WeeklyHealthReport/issues/546), [PR547](https://github.com/syamaner/WeeklyHealthReport/pull/547)). It imports catalogue schema `personal-food-catalogue-estimates-v4`, which [build 42](internal-testflight-0.3.0-build42.md) rejects. No store, food contract or export schema change for saved records; the food log is not migrated.

## Upload receipt

| Item | 0.3.0 (43) |
| --- | --- |
| Uploaded | 20 November 2026 |
| Source | `main` at `91fa7479` (merge of PR547; iOS CI passed on it) |
| Bundle and version | `com.otherweather.ReportWeeklyHealth`, 0.3.0 (43) |
| Version overrides | `CURRENT_PROJECT_VERSION=43`, `WEEKLY_HEALTH_REPORT_BUNDLE_IDENTIFIER=com.otherweather.ReportWeeklyHealth`, `DEVELOPMENT_TEAM=MDNYU95CGT` |
| Signing team | `MDNYU95CGT` |
| Executable UUID | `73E25337-DBE1-3001-9B74-9CBD2A8A2B1B` (arm64) |
| Uploaded IPA SHA-256 | `e44c027814912d7f43c7045f9d1fc3877d8c281411f251e4c4e6badc009f930d` |
| Delivery UUID | `28fe448b-4477-4d31-9b7b-39fb2843bfd6` |
| Processing | VALID (App Store Connect build id is the delivery UUID); internal state ready for beta testing |
| TestFlight | What to Test set (en-GB); in Internal Testing and not in External Testers, confirmed through `GET /v1/betaGroups/{id}/relationships/builds` |
| Google Drive configuration | Present (the archive's Info.plist has no `MISSING` value) |

Method: as for [build 42](internal-testflight-0.3.0-build42.md), from a detached worktree of `main` with its own derived data folder and the local Drive configuration copied in.

Validation: PR547 passed every AGENTS.md gate locally and iOS CI on `main` at `91fa7479`. Before upload, the owner's private v4 catalogue was imported and searched locally through the app's own composite search and Confirm code: every test search returned database rows, 833 of 836 foods were found by their own title, and of the 793 foods with food details, 785 showed the Confirm line and 570 needed no detail on Confirm. No private data is in this record.

## Changes since build 42

- **Food details from Your food database** (amendment I1): catalogue entries carry owner-reviewed food details; Confirm shows them, Log needs only an amount where every detail is known, and a catalogue detail can be corrected without a typed reason.
- **Search** (`composite-generic-ranking-v12`): a database row that contradicts a "raw" or "cooked" request is left out instead of failing the whole local search.

## What to Test

```
Build 43 (internal only)

Food details from your food database. Needs the new catalogue file personal-food-catalogue-estimates-v4.json (in iCloud, Projects/Health); build 42 cannot import it.

To check:
- Settings > Your food database: import the v4 file. The row should show your foods.
- Search a food from your list and open it: Confirm shows "Food details from your food database:" with the details, and for most foods Log needs only an amount.
- "Correct food details" still lets you change a detail; a detail from your food database can be changed without typing a reason.
- Foods whose details are not known still ask, as before (for example fortification on cereals and milks).
- Search "raw ..." or "cooked ..." for a food in your list: results still appear and nothing fails.
```

## Still to do

- Device check: import the v4 catalogue and walk the What to Test list.
- Before any external build: the items in [issue 539](https://github.com/syamaner/WeeklyHealthReport/issues/539) and the [build 36 record](internal-testflight-0.3.0-build36.md#still-to-do), and a separate archive exported without `testFlightInternalTestingOnly`.
