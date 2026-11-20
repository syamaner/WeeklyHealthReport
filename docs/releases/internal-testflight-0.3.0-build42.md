# TestFlight 0.3.0 (42)

Status: **0.3.0 (42) is the build testers should install.** It was uploaded on 20 November 2026 on the owner's request, processed as VALID, given the What to Test text below (en-GB) and added to the Internal Testing group the same day on the owner's yes. It was exported with `testFlightInternalTestingOnly`, so App Store Connect never offers it to an external group or the App Store. Not yet checked on the device.

**This build collects four small fixes since [build 41](internal-testflight-0.3.0-build41.md).** **No store, food contract or export schema changes**: the food log is not migrated.

## Upload receipt

| Item | 0.3.0 (42) |
| --- | --- |
| Uploaded | 20 November 2026 |
| Source | `main` at `25b855e3` (merge of PR544) |
| Bundle and version | `com.otherweather.ReportWeeklyHealth`, 0.3.0 (42) |
| Version overrides | `CURRENT_PROJECT_VERSION=42`, `WEEKLY_HEALTH_REPORT_BUNDLE_IDENTIFIER=com.otherweather.ReportWeeklyHealth`, `DEVELOPMENT_TEAM=MDNYU95CGT` |
| Signing team | `MDNYU95CGT` |
| Executable UUID | `E8B35837-3FBA-3D7E-AC95-9F62F4D77EFA` (arm64) |
| Uploaded IPA SHA-256 | `181cbe8dc737f63ca53ef6ea24f316a61b1862501081fe519b28bff6af2cd184` |
| Delivery UUID | `318895db-f092-4ad1-9f9c-551ae4ccdd5b` |
| Processing | VALID (App Store Connect build id is the delivery UUID); internal state ready for beta testing |
| TestFlight | What to Test set (en-GB); in Internal Testing and not in External Testers, confirmed through `GET /v1/betaGroups/{id}/relationships/builds` |
| Google Drive configuration | Present (the archive's Info.plist has no `MISSING` value) |

Method: as for [build 41](internal-testflight-0.3.0-build41.md), from a detached worktree of `main` with its own derived data folder and the local Drive configuration copied in: `xcodebuild archive`, `xcodebuild -exportArchive` with [`Config/ExportOptions-internal-testflight.plist`](../../Config/ExportOptions-internal-testflight.plist), then `xcrun altool --upload-app`. The API key stays in `~/.appstoreconnect/private_keys/` and is passed to the tools by path only.

Validation: iOS CI passed on `main` at `25b855e3`. Each change below passed CI and a blind review before merging; PR544 also passed `xcodebuild analyze` and `xcodebuild test` locally.

## Changes since build 41

- **Your food database no longer stays "Locked"** after the phone is unlocked ([issue 543](https://github.com/syamaner/WeeklyHealthReport/issues/543), [PR544](https://github.com/syamaner/WeeklyHealthReport/pull/544)). A pending lock cleared only on "protected data did become available", which a suspended app does not receive and an unlock within the grace period never posts. Becoming active with protected data readable now clears it and reloads the Settings row.
- **One spelling for millilitres, "mL"** ([issue 491](https://github.com/syamaner/WeeklyHealthReport/issues/491), [PR540](https://github.com/syamaner/WeeklyHealthReport/pull/540)).
- **Barcode Confirm shows the scaled-serving line** for a product whose panel is per serving, as Your food database entries do ([issue 490](https://github.com/syamaner/WeeklyHealthReport/issues/490), [PR541](https://github.com/syamaner/WeeklyHealthReport/pull/541)).
- **One error for an over-limit dictation result**, on the speech review card only ([issue 47](https://github.com/syamaner/WeeklyHealthReport/issues/47), [PR542](https://github.com/syamaner/WeeklyHealthReport/pull/542)).

## What to Test

```
Build 42 (internal only)

Small fixes since build 41. No store or file format change.

To check:
- Your food database: with the app in the background, lock the phone, wait more than 10 seconds, unlock and open the app. Settings should show your foods, not "Locked", without locking again. Repeat, unlocking within 10 seconds.
- Millilitres read "mL" everywhere (for example "per 100 mL" on a drink).
- Scan a product whose label is per serving only: Confirm now shows "Some values scaled from a ... serving", as it does for your own foods. A per 100 g product shows no such line.
- Dictate a daily note longer than the limit: one error shows, on the speech review card, and the text stays editable.
```

## Still to do

- Device check of the lock fix (both cases in What to Test).
- Before any external build: the items in [issue 539](https://github.com/syamaner/WeeklyHealthReport/issues/539) and the [build 36 record](internal-testflight-0.3.0-build36.md#still-to-do), and a separate archive exported without `testFlightInternalTestingOnly`.
