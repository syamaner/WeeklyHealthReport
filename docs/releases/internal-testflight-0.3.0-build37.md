# TestFlight 0.3.0 (37)

Status: **0.3.0 (37) is the build testers should install.** It was uploaded on 17 November 2026, processed as VALID, given the What to Test text below (en-GB) and added to the Internal Testing group the same day, under the owner's overnight authorisation of 16 November 2026 to prepare it in TestFlight, including the safe merge of the pull request it needed. It was exported with `testFlightInternalTestingOnly`, so App Store Connect cannot offer it to an external group or the App Store. No external group, Beta App Review submission or questionnaire change.

**This is the first build that writes version 2 of the food daily export** ([food-daily-export-contract-v2.md](../food-daily-export-contract-v2.md), #312). The reader change (PR505) and the writer (PR506) ship together here, as the contract requires; no build was released from the reader-only state between them. HealthKit stays read-only and no destination is added.

This record covers what changed after [build 36](internal-testflight-0.3.0-build36.md), which was archived from `main` at `674e63b`.

## Upload receipt

| Item | 0.3.0 (37) |
| --- | --- |
| Uploaded | 17 November 2026 |
| Source | `main` at `34a29d14ab11571240f179d83d5131b8f8637d6e` ([PR506](https://github.com/syamaner/WeeklyHealthReport/pull/506)), archived from a clean worktree |
| Bundle and version | `com.otherweather.ReportWeeklyHealth`, 0.3.0 (37) |
| Version overrides | `CURRENT_PROJECT_VERSION=37`, `WEEKLY_HEALTH_REPORT_BUNDLE_IDENTIFIER=com.otherweather.ReportWeeklyHealth`, `DEVELOPMENT_TEAM=MDNYU95CGT` |
| Signing team | `MDNYU95CGT` |
| Executable UUID | `89D204C7-A71F-3A1F-88C1-C12D51643282` (arm64) |
| Uploaded IPA SHA-256 | `dfe8c0214ccea1a8347a03e664b4e583243e0a90aa8271647525362369d36592` |
| Delivery UUID | `214944e3-a3c6-45a9-9b52-192d4fe2d411` |
| Processing | VALID (App Store Connect build id is the delivery UUID); audience `INTERNAL_ONLY` |
| TestFlight | What to Test set (en-GB); in Internal Testing and not in External Testers, confirmed through `GET /v1/betaGroups/{id}/relationships/builds` |
| Google Drive configuration | Present (the archive's Info.plist has no `MISSING` value) |

Method: as for [build 36](internal-testflight-0.3.0-build36.md): `xcodebuild archive` (Release, automatic signing with `-allowProvisioningUpdates` and the App Store Connect API key), `xcodebuild -exportArchive` with [`Config/ExportOptions-internal-testflight.plist`](../../Config/ExportOptions-internal-testflight.plist), then `xcrun altool --upload-app`. The API key stays in `~/.appstoreconnect/private_keys/` and never enters the repository, logs or this record.

## Food daily export, version 2 (#312, PR505 and PR506)

- **How each amount was obtained, in the food daily file (#312).** The food file you export to Google Drive now says, for every entry, how its amount was obtained (entered directly, weighed, estimated by eye, a count converted on a kitchen scale or from a package weight, a typical weight, or the whole-milk volume rule; an older conversion with a method typed in your own words is marked as not described), whether that amount is an estimate, and what you entered when it differs from the grams in the file (for example 3 pieces, 200 mL or 2 servings). A typical-weight or whole-milk entry used to look like any other amount; it is now marked as an estimate and names the rule behind it. The file's version is 2. What is new in the file is how each amount was obtained, what you entered and, for a typical weight or the milk rule, the name of the rule and its public source; it goes only where the file already went, your own Google Drive folder, when you choose Export. Text you typed for an older conversion method is never included.
- **Older food files still work (#312).** Files already in your Drive folder as version 1 stay valid and are not rewritten. Exporting a day again (within the last seven days) replaces that day's file with a version 2 file. After exporting with this build, do not go back to an older build to export the same day again: an older build cannot read the new file.

## Other changes since build 36

- **Web lookup explains and retries a failed selection (#500, PR503).** When the model's selection step fails, the screen says what happened, and a temporary failure is retried before giving up.
- **Label photo reading returns without reopening the app (#493, PR497).** If the app started before the phone's Keychain could be read, a saved OpenRouter key read as missing until the app was reopened. The key is now rechecked when the Keychain becomes readable. This was the known issue recorded for build 36.
- **Open Food Facts estimate refused when a trailing clause names an inclusion (#467, PR496).** A product whose name ends with a clause naming something added no longer takes the plain estimate.
- Documentation only, no behaviour: the estimates on catalogue v2 contract (PR499), the assistant-pasted estimates contract (PR504) and the AI name search proposal (PR495). Neither estimates contract is implemented in this build.

## What to Test

```
Build 37 (internal only)

Food daily export, new file version (schema 2):
- The food file you export to Drive now says how each amount was obtained and whether it is an estimate.
- On one day in the last seven, log a boiled egg by count with a typical weight, whole milk by volume (for example 200 mL), and a food weighed on a kitchen scale.
- Open Export, choose that day and refresh. In Developer tools, the food file preview should show food_daily_schema_version 2, and each entry's amount and method should match its Food Log row.
- Tap Export, then check the file in Drive matches the preview and there is exactly one food file for that day.
- After exporting a day with this build, do not export the same day again from an older build: an older build cannot read the new file.

Also new: Web lookup now explains a failed selection and retries a temporary model failure.

Your food database: import a rebuilt catalogue file as before; nothing changes in this build.
```

## Known at release

- **An informational review note was left open on PR506.** If an amount in a state the contract's table has no row for were ever stored, the export would be blocked with "The food log could not be read", and Developer tools would not say which entry caused it. No save route produces such a state and no file is written in that case. Closing the note needs new wording, which is the owner's decision.
- **Do not export a day from an older build after exporting it with this one.** An older build cannot read a version 2 file.

## Still to do

- The owner's device check of the food daily export on this build (the steps are in [PR506](https://github.com/syamaner/WeeklyHealthReport/pull/506) and in What to Test above).
- Before any external build: the items listed in the [build 36 record](internal-testflight-0.3.0-build36.md#still-to-do), and a separate archive exported without `testFlightInternalTestingOnly`.
