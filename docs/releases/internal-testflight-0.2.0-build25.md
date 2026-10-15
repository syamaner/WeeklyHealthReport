# Internal TestFlight 0.2.0 (25): preparation

Status: **prepared, not uploaded.** This record is updated with the upload receipt (source commit, CI run, archive and dSYM UUIDs, Apple readback) once the owner approves each external step.

Version 0.2.0 marks the UX revamp (#140, phases #194 to #200) and its follow-ups. Build 25 follows 0.1.1 (24), which is in TestFlight but has no record in this repository; its expiry (83 days left on 15 October 2026) puts its upload around 7 to 8 October, before the revamp merged.

## Upload method

Headless, with an App Store Connect API team key (App Manager role) held only in `~/.appstoreconnect/private_keys/`. The key and its identifiers never enter the repository, logs or this record.

1. Archive protected `main` at the recorded source commit, Release configuration, bundle `com.otherweather.ReportWeeklyHealth`, `MARKETING_VERSION` 0.2.0 from the project and `CURRENT_PROJECT_VERSION=25` on the command line, with `-allowProvisioningUpdates` and the API key for automatic signing.
2. Export and upload with `xcodebuild -exportArchive` (`method` `app-store-connect`, `destination` `upload`, `manageAppVersionAndBuildNumber` false, internal testing only).
3. Once processing finishes, set What to Test for the existing Internal Testing group and read it back.

Each of these steps needs the owner's explicit yes at the time. No external testers, public submission or questionnaire changes.

## Older builds cannot open the food data after updating

Three storage changes in the UX revamp each move the food ledger to a new schema. Once a device opens the food log with this build, the stored data is migrated forward and **an older build can no longer open it**. Reinstalling build 24 or earlier after updating is not a safe way back; export or back up first.

| Change | Merged in | Archive contract | Schema |
| --- | --- | --- | --- |
| Confirmation contract v5: one Log action (`food_confirmation_v5`, `confirm_food_v3`) | [PR206](https://github.com/syamaner/WeeklyHealthReport/pull/206) (#195) | 4 | `food-ledger-v4` |
| Web source review manifest v2 | [PR207](https://github.com/syamaner/WeeklyHealthReport/pull/207) (#196) | 5 | `food-ledger-v5` |
| Favourites, quick add and plain water (quick-add v1) | [PR209](https://github.com/syamaner/WeeklyHealthReport/pull/209) (#198) | 6 | `food-ledger-v6` |

Existing records keep their bytes in each migration; the new versions add record types and fields alongside them. The Daily JSON export stays pinned to food contract 3, so exported files are unchanged in shape.

## User-visible changes since build 23

- New navigation: Home, Food Log, Health, Export and Settings behind a gear (#194, [PR205](https://github.com/syamaner/WeeklyHealthReport/pull/205)).
- One Confirm screen with a single Log action for every food entry route (#195). Log now closes Confirm and shows "Logged" with Undo for a few seconds ([PR240](https://github.com/syamaner/WeeklyHealthReport/pull/240)).
- Redesigned Add food, search results and web lookup, with recent foods (#196, [PR207](https://github.com/syamaner/WeeklyHealthReport/pull/207)).
- Food Log with day navigation and a read-only saved entry with history, edit, remove and restore (#197, [PR211](https://github.com/syamaner/WeeklyHealthReport/pull/211)). Add food is offered only on days within the backdating window ([PR239](https://github.com/syamaner/WeeklyHealthReport/pull/239)).
- Favourites, quick add and plain water; favourites can be created from logged food (#198, [PR209](https://github.com/syamaner/WeeklyHealthReport/pull/209), [PR235](https://github.com/syamaner/WeeklyHealthReport/pull/235)).
- Home with "today so far", a labelled projection separate from completed-day averages (#199, [PR208](https://github.com/syamaner/WeeklyHealthReport/pull/208)).
- Health screen with a period picker, summary tiles, collapsible sections and Full Page; Export works without Google Drive set up; Drive setup is in Settings (#200, [PR210](https://github.com/syamaner/WeeklyHealthReport/pull/210), [PR234](https://github.com/syamaner/WeeklyHealthReport/pull/234)).
- Full Page screenshots work on Today and Health ([PR228](https://github.com/syamaner/WeeklyHealthReport/pull/228)).
- Search: better ranking for part words and same-number ties, UK and US sources ahead of Taiwan unless asked, and egg counts such as "2 scrambled eggs" ([PR232](https://github.com/syamaner/WeeklyHealthReport/pull/232), [PR236](https://github.com/syamaner/WeeklyHealthReport/pull/236)).
- Pasted lists: locale-aware amounts, and vague portions ("a handful") ask for an amount ([PR226](https://github.com/syamaner/WeeklyHealthReport/pull/226), [PR231](https://github.com/syamaner/WeeklyHealthReport/pull/231)).
- Confirm: units, past-day logging and a whole-milk volume estimate shown next to Log ([PR234](https://github.com/syamaner/WeeklyHealthReport/pull/234), [PR237](https://github.com/syamaner/WeeklyHealthReport/pull/237)).
- Fix: Workouts no longer intermittently show "Query failed" after Home refreshes ([PR229](https://github.com/syamaner/WeeklyHealthReport/pull/229)).
- Plainer copy throughout, including failure wording in Copy all ([PR230](https://github.com/syamaner/WeeklyHealthReport/pull/230), [PR233](https://github.com/syamaner/WeeklyHealthReport/pull/233)).
- Workout export includes individual timestamped heart-rate readings ([PR191](https://github.com/syamaner/WeeklyHealthReport/pull/191)); this may already be in build 24.

HealthKit access stays read-only. The only egress change is that Today's Full Page can be shared by the user, recorded in [privacy and egress](../privacy-and-egress.md) and the [privacy policy](../privacy-policy.txt) ([PR228](https://github.com/syamaner/WeeklyHealthReport/pull/228)).

## What to Test (draft for owner approval)

```text
0.2.0 is the redesigned app. Please back up or export before installing: once this build opens your food log, builds 24 and earlier cannot open it.

Navigation: Home, Food Log, Health and Export, with Settings behind the gear. Check each opens and that Home's "today so far" matches Apple Health for today.

Logging food: Add food, search, recent foods, favourites, pasted lists and barcode all end on one Confirm screen with one Log button. After Log, Confirm closes and a "Logged" banner offers Undo for a few seconds (longer at large text sizes, until dismissed with VoiceOver). Try Undo, and try it with VoiceOver on.

Food Log: move between days, open a saved entry, edit, remove and restore. Logging for a past day should stay on that day.

Quick add: water and favourites from Home.

Health: change the period, expand and collapse sections, and take a Full Page screenshot on Health and on Today.

Export: export without Google Drive set up.

Report anything that shows zero where you expect "no data", any wording that is unclear, and anything that looks wrong at large text sizes or in dark mode.
```
