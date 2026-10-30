# TestFlight 0.2.0 (28) and 0.3.0 (29)

Status: **0.3.0 (29) is the build testers should install.** It was uploaded on 30 October 2026, processed as VALID and added to the Internal Testing group (In Beta Testing). 0.2.0 (28) was uploaded on 28 October 2026 from the same source and is also VALID and In Beta Testing for Internal Testing, but TestFlight files it under the older 0.2.0 version (see [Why build 29](#why-build-29)). Neither build has been submitted to external testers or Beta App Review.

Builds 28 and 29 follow [0.2.0 (26)](internal-testflight-0.2.0-build25.md#build-26-for-external-testers). The changes below are listed since build 26.

## Build 27

App Store Connect shows a build 0.3.0 (27), uploaded on 23 October 2026 at 21:49 PDT (24 October UTC), processed as VALID and in internal beta testing. It was uploaded outside this repository's records: there is no release record, notes entry or commit for it, and its source commit is unknown. Because the changes in this record are listed relative to build 26, they are a superset of anything build 27 contained; this record makes no claim about which of them build 27 included.

## Why build 29

Build 28 was archived with the project's `MARKETING_VERSION` at the time, 0.2.0. Build 27 already carried 0.3.0, so TestFlight filed build 28 under the older 0.2.0 version and the owner could not see it alongside the newest build. On 30 October 2026, with the owner's explicit approval, the same source was archived again as 0.3.0 (29) and uploaded the same way. The executable is identical to build 28 (same UUID below); only the version and build number differ. The project's `MARKETING_VERSION` is now 0.3.0, so later builds stay under 0.3.0.

## Upload receipts

Both builds come from the same source: `main` at `50a356c574f8f91694664e372e2a7f723968c6c9` ([PR334](https://github.com/syamaner/WeeklyHealthReport/pull/334)); the archived tree is `98a88a5793502336a09f5a6de15d98e4ae6f8e8f`.

| Item | 0.2.0 (28) | 0.3.0 (29) |
| --- | --- | --- |
| Uploaded | 28 October 2026 | 30 October 2026 |
| Bundle and version | `com.otherweather.ReportWeeklyHealth`, 0.2.0 (28) | `com.otherweather.ReportWeeklyHealth`, 0.3.0 (29) |
| Version overrides | none (project values) | `MARKETING_VERSION=0.3.0`, `CURRENT_PROJECT_VERSION=29` |
| Executable and dSYM UUID | `F203572B-8F19-3842-9481-0EEBF7E773D0` (arm64) | `F203572B-8F19-3842-9481-0EEBF7E773D0` (arm64), identical binary |
| Uploaded IPA SHA-256 | `5e087e4b30c603faf0f604490a95510e81414698c2568847e3c4a89ba225cb89` | `73dd0e5855e0e9600cea0d595f624e383f3b0a601e48d2730524ffa5d09394d8` |
| Delivery UUID | `f3136a8b-e184-4690-ba0b-6f124b91449c` | `19f8aa2c-5c87-4744-af9d-539b76ad278b` |

HealthKit stays read-only.

## Upload method

Headless, the same way as builds 25 and 26, with an App Store Connect API team key kept only in `~/.appstoreconnect/private_keys/`; its contents never enter the repository, logs or this record. Each external step had the owner's explicit approval at the time. Build 29 repeated these steps with the version overrides in the table above.

1. `xcodebuild archive`, Release, build number 28 (29 for the second upload), automatic signing with `-allowProvisioningUpdates` and the API key, team `MDNYU95CGT`.
2. `xcodebuild -exportArchive` with `method` `app-store-connect`, `destination` `export`, `manageAppVersionAndBuildNumber` false and `uploadSymbols` true. Unlike build 25, `testFlightInternalTestingOnly` was not set, so the build can reach external groups later without a new upload.
3. `xcrun altool --upload-app` with the same key. App Store Connect processed each build as VALID.
4. Each build was added to the Internal Testing group only (In Beta Testing) and What to Test was set. No external group, Beta App Review submission or questionnaire change.

## Label photo reading is in the code but off for users

The label photo AI pre-fill work (#316, [contract](../label-photo-ai-prefill-v1.md), [PR319](https://github.com/syamaner/WeeklyHealthReport/pull/319) and the L1 to L5 PRs ending with [PR329](https://github.com/syamaner/WeeklyHealthReport/pull/329)) is in builds 28 and 29, but the route is off: there is no user-visible setting, and the live OpenRouter route is reachable only through a launch argument that is compiled into Debug builds only. A TestFlight install of either build therefore offers no label photo screen and sends no label photo.

## Older builds cannot open the food data after updating

Pasted nutrition label v1 ([contract](../pasted-nutrition-label-v1.md), #93) moves the food ledger to a new schema. Once a device opens the food log with this build, the stored data is migrated forward and **builds 26 and earlier can no longer open it** (they report an unknown schema). Reinstalling an earlier build after updating is not a safe way back; export or back up first.

| Change | Merged in | Archive contract | Schema |
| --- | --- | --- | --- |
| Pasted nutrition label: domain, manifest and storage | [PR267](https://github.com/syamaner/WeeklyHealthReport/pull/267) (#93) | 7 | `food-ledger-v7` |

The migration (`v7_pasted_label`) changes metadata only: existing records keep their bytes and no table is added. A backup exports contract 7 only when it holds a pasted-label entry; otherwise it exports contract 6 exactly as before. The health Daily JSON export stays pinned to food contract 3, so its files are unchanged in shape.

## User-visible changes since build 26

### Paste a nutrition label

- **Paste nutrition label** in Add food ([contract](../pasted-nutrition-label-v1.md), [reader v3](../pasted-nutrition-label-reader-v3.md), #93, [PR271](https://github.com/syamaner/WeeklyHealthReport/pull/271) and the reader v3 PRs [PR280](https://github.com/syamaner/WeeklyHealthReport/pull/280), [PR281](https://github.com/syamaner/WeeklyHealthReport/pull/281), [PR283](https://github.com/syamaner/WeeklyHealthReport/pull/283) and [PR284](https://github.com/syamaner/WeeklyHealthReport/pull/284)): copy the Taiwan nutrition table (營養標示) from a product page as text, paste it with a name for the food, and tap Read label. The app reads the table on your device, with no network call, and fills in Confirm with the values it read; you check them against the label, correct or add anything, and nothing is saved until you tap Log. Values the label does not state are left as not read, never as zero.
- This version reads Taiwan 營養標示 text only, not photos, PDFs or labels in other languages. Some layouts are declined with a reason, for example a page with more than one nutrition panel or a table without a per serving or per 100 g heading; you can then edit the text, use Search or Barcode instead, or share the text with Report a misread, which goes only where you choose in the share sheet.
- The pre-release check on 24 real Taiwan labels found no wrong values in the 11 tables that reached Confirm and declined the other 13 ([results](../pasted-nutrition-label-reader-v3-release-check.md), [PR302](https://github.com/syamaner/WeeklyHealthReport/pull/302)); fewer declines are the aim of reader v4 (#301).
- Pasted label Confirm asks about fortification once (Yes, No or Not stated), puts the amount first and defaults to servings (#306, [PR311](https://github.com/syamaner/WeeklyHealthReport/pull/311)).

### Food totals and export

- Summary policy `food-intake-summary-v3` ([PR267](https://github.com/syamaner/WeeklyHealthReport/pull/267), #93): a day or period total that includes a calculated value (kcal from a printed kJ value, or sodium from a printed salt value, `pasted-label-conversions-v1`) shows the existing "Includes estimates" indicator. Values the user corrected or entered do not. No stored record changes.
- Fibre on Today, the Food Log and the Health report's Food and water section, with partial-fibre days left out of the average and counted, never shown as 0 g (#288, [PR292](https://github.com/syamaner/WeeklyHealthReport/pull/292)).
- Food daily export ([contract](../food-daily-export-contract-v1.md), #287, [PR294](https://github.com/syamaner/WeeklyHealthReport/pull/294), [PR295](https://github.com/syamaner/WeeklyHealthReport/pull/295)): with Food log on, Export also sends a separate `food-daily-YYYY-MM-DD.json` for the selected day to the same Drive folder, verified on its own with its own result. The health file is unchanged. The summary policy became `food-intake-summary-v4`, which adds only an `overflowed` flag; totals on Home and Health read as before.
- Water no longer turns an unknown nutrient into 0 (#304, `food-intake-summary-v5`, [health-food-and-water-v1.md](../health-food-and-water-v1.md) decision 10, [PR309](https://github.com/syamaner/WeeklyHealthReport/pull/309)): plain water's exact zeros are left out of day totals, so a food with unknown carbohydrates plus water still reads "Unknown" on Home and in the Food Log instead of "0 g+", a day with only water shows "No food logged" on Home and in the Food Log (with the water figure) instead of nutrient rows, and Home's entry count leaves water out. Known totals are unchanged.
- Quantity estimates from typical egg weights are marked in the Daily JSON summary as `food-intake-summary-v6` (#307, [PR313](https://github.com/syamaner/WeeklyHealthReport/pull/313)); entries and file shapes are unchanged, and files already sent as v4 or v5 stay valid.

### Counted foods and Confirm

- Eggs by count can be logged again: the "how measured" field has a visible label and the warning names the missing part (#296, [PR298](https://github.com/syamaner/WeeklyHealthReport/pull/298)). The method is now a closed choice of Kitchen scale, Package weight or Estimated by eye ([contract](../count-conversion-method-v1.md), #299, [PR300](https://github.com/syamaner/WeeklyHealthReport/pull/300)); methods typed earlier still display unchanged.
- Typical egg weights by size: whole raw and boiled eggs counted in pieces pre-fill Large (about 50 g each, USDA SR Legacy) as a labelled estimate, with a one-tap size choice; counts read "pieces" everywhere, and the estimate and method show on the Food Log row, saved entry and history ([contract](../count-portion-estimate-v1.md), #307, [PR313](https://github.com/syamaner/WeeklyHealthReport/pull/313)).
- One set of method words, a Log bar that names the missing count field, and one weight layout above When (#318, #303, [PR331](https://github.com/syamaner/WeeklyHealthReport/pull/331)).
- Plate weighing: the food and plate total, the empty plate and the computed "For N g eaten" sit together under "Weighed on a plate"; at the largest text sizes labels sit above their fields and route rows, favourites and the food query wrap instead of truncating (#332, #315, [PR336](https://github.com/syamaner/WeeklyHealthReport/pull/336)).
- Food details sheet: no truncation at the largest text sizes, Return finishes the reason, and Apply closes the sheet with "Food details corrected" (#285, #276, [PR293](https://github.com/syamaner/WeeklyHealthReport/pull/293)).

### Search

- Query parser v9: "2 hard boiled eggs" pre-fills the count, and "3 pieces banana" reads as a count ([parser v9](../food-query-parser-v9.md), #317, [PR330](https://github.com/syamaner/WeeklyHealthReport/pull/330)).
- Interpretation v2: when a household portion such as "3 pieces cheese", "1 cup rice" or "a glass of milk" needs confirming, search uses the food text without the amount and unit, so it finds results; Confirm opens with the amount empty ([contract](../food-query-interpretation-v2.md), #333, [PR334](https://github.com/syamaner/WeeklyHealthReport/pull/334)).
- Search rows state energy per 100 g or 100 mL (never 0 for unknown), and Best matches keeps close name matches with the rest under Other matches (#308, [PR314](https://github.com/syamaner/WeeklyHealthReport/pull/314)).

### Health, navigation and accessibility

- Presentation follow-ups (#308, [PR314](https://github.com/syamaner/WeeklyHealthReport/pull/314)): one read-failure banner on Health, a "no visible data or no access" note, Copy all v2 using the screen's wording ([health-copy-all-v2.md](../health-copy-all-v2.md)), and Dynamic Type fixes for titles, chips, placeholders and Home's estimates note.
- First launch lands on Home, and a build without Google Drive export never restores the unavailable Export screen (#305, [PR310](https://github.com/syamaner/WeeklyHealthReport/pull/310)).
- HealthKit daily collections (steps and its trend, blood glucose, resting heart rate, HRV and the Daily JSON nutrition context) are bucketed by the report's own calendar, with a per-day fallback shown only in Developer tools ([healthkit-day-bucketing-v1.md](../healthkit-day-bucketing-v1.md), #49, [PR266](https://github.com/syamaner/WeeklyHealthReport/pull/266)).
- Accessibility and diagnostics polish: Health section headers and the Export day picker wrap at accessibility sizes, and Developer diagnostics omits an empty Activity section (#248, #249, #250, [PR264](https://github.com/syamaner/WeeklyHealthReport/pull/264)).

Evaluation, planning and CI changes in the same range (the label capture evaluation #255, the reader v3 fresh-set protocol and scorer, and the CI timeout) change no app behaviour and are not listed.

HealthKit access stays read-only. Egress changes since build 26, recorded in [privacy and egress](../privacy-and-egress.md) and the [privacy policy](../privacy-policy.txt) (effective 26 October 2026):

- The food daily export goes to the same Google Drive folder as the health export, only when the user chooses Export with Food log on.
- Report a misread for a pasted label goes only where the user picks in the share sheet; pasting and reading a label sends nothing.
- Label photo reading through OpenRouter has owner-approved egress terms (25 October 2026), but its route is off for users in these builds, so builds 28 and 29 send no label photo.

## What to Test (owner approved, 28 October 2026)

Set in English (U.K.) for the Internal Testing build and read back identical. A shorter interim text was set first and replaced the same day because it omitted the storage warning. Build 29 was given the same text on 30 October 2026.

```text
0.2.0 (28). Please back up or export before installing: once this build opens your food log, builds 26 and earlier cannot open it.

New since build 26:
- Paste nutrition label (Add food): paste a Taiwan nutrition table as text, check the values on Confirm, then Log. Read on your device, no network.
- Fibre on Today, the Food Log and the Health report.
- Export also sends a separate daily food file to Drive when Food log is on.
- Plain water no longer turns an unknown nutrient into zero.
- Counted foods: typical egg weights by size, one set of method words, clearer Log bar messages.
- Plate weighing: total, empty plate and amount eaten grouped, with labels above the fields at the largest text sizes.
- Search: better handling of "N pieces", "hard boiled" and portions such as "1 cup" or "a glass of".
- First launch lands on Home.

Label photo reading is not in this build. Report anything that shows zero where you expect "no data", unclear wording, and anything that looks wrong at large text sizes or in dark mode.
```

"Label photo reading is not in this build" describes what testers can reach: the code is present but the route is off (see above).
