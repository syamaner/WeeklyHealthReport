# TestFlight 0.3.0 (36)

Status: **0.3.0 (36) is the build testers should install.** It was uploaded on 14 November 2026, processed as VALID, given the What to Test text below (en-GB) and added to the Internal Testing group on 15 November 2026, each step with the owner's explicit approval. It was exported with `testFlightInternalTestingOnly`, so App Store Connect cannot offer it to an external group or the App Store. No external group, Beta App Review submission or questionnaire change.

**This is the first build in which label photo reading can be used in Release.** It stays off until you turn on Settings › Food search › Read label photos with AI, and it needs your own validated OpenRouter key ([label-photo-ai-prefill-v1.md](../label-photo-ai-prefill-v1.md) section 17.22, [privacy-and-egress.md](../privacy-and-egress.md)). With the switch off, the build sends no label photo. HealthKit stays read-only.

Builds 31 to 35 have no record of their own here; the entries in [unreleased.md](unreleased.md) shipped across them and are not repeated below. This record covers what changed after build 35, which was archived from `main` on 13 November 2026 after [PR480](https://github.com/syamaner/WeeklyHealthReport/pull/480).

## Upload receipt

| Item | 0.3.0 (36) |
| --- | --- |
| Uploaded | 14 November 2026 |
| Source | `main` at `674e63b5e73dcc13a494df631847d54835f7d352` ([PR492](https://github.com/syamaner/WeeklyHealthReport/pull/492)); archived tree `cc3fe24ab44186b43e1b1f9d4d299a6415c8df86` |
| Bundle and version | `com.otherweather.ReportWeeklyHealth`, 0.3.0 (36) |
| Version overrides | `CURRENT_PROJECT_VERSION=36`, `WEEKLY_HEALTH_REPORT_BUNDLE_IDENTIFIER=com.otherweather.ReportWeeklyHealth` |
| Signing team | `MDNYU95CGT` |
| Executable UUID | `EAD38D84-FC25-3BAF-8494-822683E71F9B` (arm64) |
| Uploaded IPA SHA-256 | `1216ac3d7ba1ba80b6a55b99aad5e41fe81a3d2cfad5ae1807278676f1f82b35` |
| Delivery UUID | `a1566fe1-81df-435a-abde-d693b6fd55b8` |
| Processing | VALID (App Store Connect build id is the delivery UUID) |
| TestFlight | What to Test set (en-GB); in Internal Testing, confirmed through `GET /v1/betaGroups/{id}/relationships/builds` |
| Google Drive configuration | Present (the archive's Info.plist has no `MISSING` value) |

Method: as for [build 29](internal-testflight-0.3.0-build29.md#upload-method), except the export step: `xcodebuild -exportArchive` with [`Config/ExportOptions-internal-testflight.plist`](../../Config/ExportOptions-internal-testflight.plist) (`app-store-connect`, `destination` `export`, `manageAppVersionAndBuildNumber` false, `uploadSymbols` true, `testFlightInternalTestingOnly` true), then `xcrun altool --upload-app`. The App Store Connect API key stays in `~/.appstoreconnect/private_keys/` and never enters the repository, logs or this record.

## Label photo reading (#316, PR492)

- **Settings › Food search › Read label photos with AI**, off by default. With it on and a validated OpenRouter key, Add food › Nutrition label offers camera, photo library and paste image.
- The route, consent sheet, per-read and daily limits and the Confirm checks are those approved in [label-photo-ai-prefill-v1.md](../label-photo-ai-prefill-v1.md): one named model endpoint on OpenRouter with zero data retention and no fallback, the cropped photo sent with its metadata removed, 30 reads or $0.50 of reported cost a day.
- Turning the switch off while the photo screen is open disables Read label with AI and sends nothing; turning it back on brings Read back.
- Release builds ignore developer launch arguments.
- **Gate waived for internal builds only.** The recorded iPhone run of `FoodLabelPhotoCaptureTests` (17.17 (c)) could not run as written, because a package test target has no host app on a device. On 14 November 2026 the owner asked for the build to go out for their own testing, waiving it for internal builds; the owner's device check takes its place. It stays required, together with the App Store privacy answers, before any external build.
- **Known issue (#493).** If the app starts before the phone's Keychain can be read (for example before first unlock), a saved key reads as missing until the app is reopened, so the switch's route and Web lookup's revalidation are unavailable. Nothing is sent while this happens.

## Your food database (PR482, PR487)

- **Database foods stay available across a device lock (PR482).** A read that failed while the phone was locking was reported as damaged until relaunch; it is now treated as locked and retried on unlock.
- **Catalogue import v2 (PR487).** The app now imports a `personal-food-catalogue-v2` file as well as v1. Values the catalogue scaled from a per-serving panel keep a per-serving source basis, and Confirm says "Some values scaled from a N g serving". The on-device store keeps its file name, so nothing migrates; a v1 import still works unchanged.

## What to Test

```
Build 36 (internal only)

Label photo reading, off by default:
- Turn on Settings > Food search > Read label photos with AI. It needs your validated OpenRouter key.
- Add food > Nutrition label then offers camera, photo library and paste image.
- Crop to the nutrition table, tap Read label with AI, and check every value on Confirm before logging. Each read costs up to about 5p, with a 50p daily limit.
- Turn the switch off with the screen open: Read should be disabled and nothing sent. Turn it back on: Read should return.

Also new: once you import a rebuilt (v2) catalogue, its foods can show "Some values scaled from a N g serving" on Confirm.

If Read label photos with AI is missing after launch with a key saved, close and reopen the app (#493).
```

## Still to do

- The owner's device check of label photo reading on this build.
- Before any external build: the host-app iPhone run of `FoodLabelPhotoCaptureTests`, the App Store privacy answers, and a separate archive exported without `testFlightInternalTestingOnly`.
