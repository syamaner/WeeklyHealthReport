# TestFlight 0.3.0 (38)

Status: **0.3.0 (38) is the build testers should install.** It was uploaded on 18 November 2026 at the owner's request ("Yes, upload build 38"), processed as VALID, given the What to Test text below (en-GB) and added to the Internal Testing group the same day. It was exported with `testFlightInternalTestingOnly`, so App Store Connect never offers it to an external group or the App Store.

**This is the first build that imports labelled estimates from Your food database** ([estimates on catalogue v2](../personal-food-catalogue-estimates-v2-proposal.md), #511, PR514). **It moves the food log to store version 10** the first time it opens it; build 37 cannot open the log afterwards. HealthKit stays read-only and no destination is added.

This record covers what changed after [build 37](internal-testflight-0.3.0-build37.md), which was archived from `main` at `34a29d1`.

## Upload receipt

| Item | 0.3.0 (38) |
| --- | --- |
| Uploaded | 18 November 2026 |
| Source | `main` at `74c1fa4d2948792320ed961c0a5db3e2f3084997` ([PR514](https://github.com/syamaner/WeeklyHealthReport/pull/514)), archived from a clean worktree |
| Bundle and version | `com.otherweather.ReportWeeklyHealth`, 0.3.0 (38) |
| Version overrides | `CURRENT_PROJECT_VERSION=38`, `WEEKLY_HEALTH_REPORT_BUNDLE_IDENTIFIER=com.otherweather.ReportWeeklyHealth`, `DEVELOPMENT_TEAM=MDNYU95CGT` |
| Signing team | `MDNYU95CGT` |
| Executable UUID | `03A9496C-F366-38B8-907A-8E2B535F6F2A` (arm64) |
| Uploaded IPA SHA-256 | `8430b556a219f0ab980384bdf32fc1a0afa7fd2bb4cb3a09de975c3ac6336c23` |
| Delivery UUID | `b6a93845-51a2-4731-b1c6-b45b51e1d8e0` |
| Processing | VALID (App Store Connect build id is the delivery UUID); audience `INTERNAL_ONLY` |
| TestFlight | What to Test set (en-GB); in Internal Testing and not in External Testers, confirmed through `GET /v1/betaGroups/{id}/relationships/builds` |
| Google Drive configuration | Present (the archive's Info.plist has no `MISSING` value) |

Method: as for [build 37](internal-testflight-0.3.0-build37.md): `xcodebuild archive` (Release, automatic signing with `-allowProvisioningUpdates` and the App Store Connect API key), `xcodebuild -exportArchive` with [`Config/ExportOptions-internal-testflight.plist`](../../Config/ExportOptions-internal-testflight.plist), then `xcrun altool --upload-app`. The API key stays in `~/.appstoreconnect/private_keys/` and is passed to the tools by path only.

Validation: the source commit passed all 19 CI checks on [PR514](https://github.com/syamaner/WeeklyHealthReport/pull/514) before its merge, including the app build and tests. The full app test suite was not re-run locally for this archive.

## Your food database: labelled estimates (#511, PR514)

- **Import a catalogue file that carries estimates.** A food database file of the new estimates format fills nutrients the food's own label does not give, from a food composition table (checked again against the app's bundled tables on import) or from a food's web page. A value from your own label is never replaced.
- **Shown as estimates, with a tier in words.** Confirm and the saved entry say "Estimated", with "good match", "some doubt" or "rough", and "from a similar food" where it applies; details show the source, the states and the assumption. The colour never appears without its words.
- **Leave out on Confirm.** An estimated nutrient can be left out before you log; it then stays unknown, never zero.
- **Daily food export, schema 3.** A day that holds an estimated value writes food file schema 3, with each estimate's tier; other days are unchanged.

## Other changes since build 37

- **Web lookup reads larger pages whole (#508, PR512),** and **lets you choose between competing nutrition panels on one page (#508, PR515).**
- **A clearer block line in the daily food export (#312, PR513):** an amount the food file cannot describe now says so, instead of the general "could not be read".
- Documentation only, no behaviour: the web lookup part-read pages contract (PR509, PR510) and the label photo estimates contract (PR516, not implemented).

## What to Test

```
Build 38 (internal only)

Before installing: back up or export your food log. This build moves it to store version 10 the first time it opens, and build 37 cannot open it afterwards.

Your food database, labelled estimates (new):
- This build can import a catalogue file that carries labelled estimates: values from a food composition table or a food's web page, filling nutrients your own label does not give.
- In Settings, import the new estimates catalogue file (personal-food-catalogue-estimates-v2.json). The Your food database row should count the estimated values.
- Search a food that had no nutrition before, open Confirm and check that estimated nutrients say "Estimated", with the tier in words ("some doubt" or "rough"). Details should show the source, the states and the assumption.
- Leave out one estimated nutrient on Confirm before you log: it should stay unknown, never zero.
- A value from your own label is never replaced by an estimate.

Daily food export: a day that holds an estimated value now writes food file schema 3. Do not export that day again from an older build.

Also new: Web lookup lets you choose between competing nutrition panels on one page.
```

## Before installing

- **Back up or export your food log first.** This build moves it to store version 10, and build 37 cannot open it afterwards.
- **Do not export a day from an older build after exporting it with this one.** An older build cannot read a schema 3 food file.

## Still to do

- The owner's device check of the estimates import and Confirm labels (the steps are in What to Test above).
- Before any external build: the items listed in the [build 36 record](internal-testflight-0.3.0-build36.md#still-to-do), and a separate archive exported without `testFlightInternalTestingOnly`.
