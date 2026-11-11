# TestFlight 0.3.0 (30)

Status: **0.3.0 (30) is the build testers should install.** It was uploaded on 10 November 2026, processed as VALID, given the What to Test text below (en-GB) and added to the Internal Testing group only, each step with the owner's explicit approval. No external group, Beta App Review submission or questionnaire change. This record covers what a tester of a Release build would notice since [0.3.0 (29)](internal-testflight-0.3.0-build29.md) (uploaded 30 October 2026, source `main` at `50a356c`). It was checked against `origin/main` at `da7d1ae`, which includes #459. Every entry was checked against the PR text and, where a switch or mode decides reachability, against the code at the composition root.

**Older builds cannot open the food data after updating.** The label estimate layer (#396) adds the metadata-only migration `v8_label_estimate`, which runs when this build first opens the food log, whether or not an estimate is ever chosen. After that, builds 29 and earlier decline the store, so reinstalling an earlier build is not a safe way back; export or back up first. Existing records keep their bytes, and a contract 8 archive is rejected by older readers (#396 PR text).

HealthKit stays read-only. No new egress destination in this range. Label photo reading is still off in Release (`LabelPhotoRouteMode` returns `.off` without a launch argument, and `live` is compiled into Debug only), and the pasted-label AI text route has no shipped route (`PastedLabelAITextRoute.current` is nil).


## Upload receipt

| Item | 0.3.0 (30) |
| --- | --- |
| Uploaded | 10 November 2026 |
| Source | `main` at `da7d1aecafef77de47597bd12e01b3f560198844` ([PR459](https://github.com/syamaner/WeeklyHealthReport/pull/459)); archived tree `d9d5aec027731b72e94a016cd8ce6fc5c445cef4` |
| Bundle and version | `com.otherweather.ReportWeeklyHealth`, 0.3.0 (30) |
| Version overrides | `MARKETING_VERSION=0.3.0`, `CURRENT_PROJECT_VERSION=30` |
| Signing team | `MDNYU95CGT` |
| Executable UUID | `3432EFF6-B82A-3E07-BCB9-3495F2071E43` (arm64) |
| Uploaded IPA SHA-256 | `c19148500693b88b12986908caa61a2c3f3b4d2eea9d28cd8313b87cfdc95f87` |
| Delivery UUID | `91293427-b306-4686-8537-d2a57b457389` |
| Processing | VALID (App Store Connect build id is the delivery UUID) |
| TestFlight | What to Test set (en-GB, 1,732 characters); in Internal Testing, confirmed through `GET /v1/betaGroups/{id}/relationships/builds` |

Method: as for [build 29](internal-testflight-0.3.0-build29.md#upload-method). `xcodebuild archive` (Release, automatic signing with `-allowProvisioningUpdates` and the App Store Connect API key, team `MDNYU95CGT`), then `xcodebuild -exportArchive` (`app-store-connect`, `destination` `export`, `manageAppVersionAndBuildNumber` false, `uploadSymbols` true, `testFlightInternalTestingOnly` not set), then `xcrun altool --upload-app`. The key stays in `~/.appstoreconnect/private_keys/` and never enters the repository, logs or this record. HealthKit stays read-only.

## Nutrition label

- **Add food has one Nutrition label row in place of the two label rows.** It opens a Nutrition label screen. In this build, with the photo route off, the screen offers only **Paste** (the system paste control, which reads label text on the device) and **Type or paste text** (the text screen, empty, as before); its subtitle reads "Paste or type the label text. Read on this device." Pasted text goes to the same offline Taiwan reader, unchanged, and every path still ends on Confirm with one Log action (#455).
- **Dark chocolate labels can borrow estimates for nutrients the label does not print.** On Confirm for a pasted chocolate label (not milk, white or ruby), an optional "Estimate unprinted nutrients" section offers a cocoa percentage pre-filled from the name or text, then lists compatible bundled reference rows with nothing chosen. Choosing one adds only the missing nutrients, each marked as an estimate with its source; printed values always win, and the section never blocks Log. Such entries show "Partly estimated" on the Food Log, saved entries, Recents and Favourites, and re-logging one saves the label values only (#395, #396, #397; #395 and #396 are the policy and storage slices behind it).
- **A per 100 header the reader cannot classify now declines instead of saving under the wrong basis.** A Taiwan paste with an English header such as `Per 100gm`, `per 100 grams` or a bare `Per 100` used to reach Confirm with per 100 values stored as per serving. It now declines with the message that the values could not be matched to their rows and columns; accepted readings are unchanged (#375, PR #377).

## Search

- **Cocoa percentages rank and label dark chocolate results.** "dark chocolate 70%" or "85%" puts the USDA 70 to 85% row first with a note on the range it covers; 86 to 99% shows the same row noted as an estimate; 100% shows unsweetened baking chocolate as a labelled 100% estimate. Phrasings such as "100% cacao" or "85% cocoa chocolate" now search chocolate, with "Searched as chocolate with N% cocoa." on the Search screen, and "dark chocolate" also finds CoFID "Chocolate, plain" (#387, #392).
- **More cocoa phrasings keep their percentage.** "dark chocolate, 90%", "90 % dark chocolate" and "90 per cent dark chocolate" now keep the cocoa ranking and note instead of losing the percentage or reading 90 as a count. With the online database on, Open Food Facts hits that name the requested percentage are read first (#453).
- **French reference values (Ciqual 2025) for dark chocolate are bundled on the device.** Twenty-nine chocolate foods from Ciqual 2025 appear after all UK, US and Taiwan rows, labelled "Ciqual · on device" in search and "French reference · estimate" on Confirm; they are never promoted above other sources. Two of them (70% and 50%) are also offered in the label estimate list (#400, #401).
- **A named dish with an exact amount now pre-fills Confirm.** "200g porridge made with milk" fills 200 g on Confirm, still editable, as plain searches already did. When a named dish has no amount, Search results now say so (#386).
- **Mugs, plural containers and household measures leave the search text and never set an amount.** "3 mugs of tea" or "250 ml mug of milk" now searches "tea" or "milk" and asks you to confirm the portion; "cup noodles" and "mug cake" keep their names (#340, #366).
- **Paste or dictate a list handles household measures the same way.** "2 mugs of tea" finds tea, "2 slices of bread" finds bread, and lines with bottles, cans, jars, spoonfuls and similar words carry the household-measure notice with no amount instead of a guessed count (#358, #366).
- **Open Food Facts products without a pack size are accepted when the label panel says per 100 g or per 100 ml.** Barcode lookup and online search no longer decline a product whose pack quantity is missing or unreadable (for example "1 bar") when it has exactly one as-sold panel per 100 g or per 100 ml; the source line drops the empty pack segment. This found results for "85% dark chocolate" that came back empty before (#459).

## Food Log and Today

- **The Logged banner is steadier.** Taps on the banner before it slides in no longer reach the row underneath, a tap on Undo at the moment the banner expires still removes the entry, and changing the Food Log day dismisses the banner without undoing anything (#360, #364).
- **Food details closes cleanly.** Every Food details field offers Done on the keyboard, and closing the sheet without Apply discards unapplied edits (#365).
- **Edit food reads more clearly.** An unchanged reopened entry says "No changes to save" at every text size, and its Source footer now points to Correct food details (#348, #351).
- **The Food Log's loading state recovers on its own.** If loading is still running after three seconds the screen says "The food log is taking longer than usual to load." with Try again. The original blank screen report was not reproduced, so this hardens the state rather than claiming a fix (#368).
- **The Add food button on the Food Log is centred and shows its plus icon** (#367).

## Health report

- **The Health report reads every metric even if the access request reports an error.** Previously any request error showed "Could not read Apple Health" for all metrics, while Home read the same data. Each metric now shows its own value, "no visible data or no access" or its own error, as Home does; Health unavailable is unchanged (#376).

## Export

- **The exact file preview is readable and copyable.** The Health and Food exact-file sheets wrap the JSON and show a labelled excerpt for large files, and Copy JSON copies the complete file to the local clipboard for ten minutes. The file sent to Drive is unchanged (#390).

## Accessibility

- **"How you got it" stays whole at accessibility text sizes.** On Confirm the picker's title sits above a full-width menu whose value wraps, so "Kitchen scale" is no longer cut short (#341).
- **Food details fields wrap at accessibility sizes,** so long product names and variants are shown whole, and the field shrinks back after Done (#348, #351).
- **VoiceOver reads Confirm's source line,** for example "French reference, estimate" (#404).

## Performance

- **Add food opens without freezing.** The Health report's food refresh reads the food archive once instead of once per day and entry, and Add food loads recent foods and favourites in the background behind "Loading recent foods" and "Loading favourites" rows. On the owner's device the longest hang fell from about 4 s to 0.5 s (#408).
- **Returning to Today no longer stutters.** The food card reads off the main thread, keeps its current values while it refreshes on the same day, and shows loading when the day has changed (#411).

## Developer tools

- **Ciqual source details.** For Ciqual rows, Developer tools shows the French name, source manifest and corpus hash, attribution, licence and each value's published literal and Ciqual confidence code (#404).
- **Label estimate details.** Entries with an estimate list both source releases and both decisions (#397).
- The Health report no longer shows an authorisation request's own error text in Developer tools; per-metric query errors still appear (#376).

## Excluded (no Release-visible change)

- #378: UK English pasted-label reader, P2a; behind the UK development policy, not wired at the composition root (no app reference to `UKEnglishLabelTextReader`).
- #380: reading policy seam and UK energy units, P2b; the product policy is unchanged and `.ukDevelopment` is used only in tests.
- #413: UK parser uk-v3 rules; development policy only, product path unchanged (UK pasted label v2 was not shipped).
- #421: pasted-label AI text route A1, pure checks and evaluation core; no route shipped.
- #426: AI text route A2, reader and fake-transport harness; no live transport in the app.
- #429: fixes to the #426 tooling; no app behaviour.
- #444: AI text route A3 tuning and freeze; evaluation egress only, `PastedLabelAITextRoute.current` stays nil (#416 later closed, not shipped).
- #403: README front page and doc links; Swift changes are comments only.

## What to Test (draft, plain text, under 4,000 characters)

```text
0.3.0 (30). New since build 29:

- Nutrition label: Add food now has one Nutrition label row. In this build it offers Paste (reads the label text on your device) and Type or paste text. Label photo reading is not in this build.
- Dark chocolate: on Confirm for a pasted chocolate label, you can optionally choose a reference row to estimate nutrients the label does not print. Printed values always win. Check that estimated entries show "Partly estimated".
- Search: try cocoa percentages ("dark chocolate 85%", "90% dark chocolate", "dark chocolate, 90%", "100% cacao"). French reference rows (Ciqual) appear after the others, marked as estimates.
- Online search and barcode: products without a pack size, such as some chocolate bars, should now be found when their label is per 100 g or per 100 ml.
- Search and lists: "3 mugs of tea", "2 slices of bread" or "250 ml mug of milk" should search the food and ask you for the amount, never guess one. "200g porridge made with milk" should fill 200 g on Confirm.
- Food Log: the Logged banner, Undo and changing day; Food details Done and Close; Edit food wording.
- Health report: every metric should show its own value or "no visible data or no access", never a blanket error while Today shows data.
- Export: View exact file wraps the JSON, and Copy JSON copies the whole file.
- Speed: Add food and returning to Today should open without a pause.

Please back up or export before installing: once this build opens your food log, builds 29 and earlier cannot open it.

Report anything that shows zero where you expect "no data", any amount the app fills in that you did not type, unclear wording, and anything that looks wrong at large text sizes, with VoiceOver or in dark mode.
```
