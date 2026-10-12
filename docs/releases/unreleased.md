# Unreleased changes since build 23

Release notes to carry into the next internal TestFlight build. Each entry names the merged change; when a build ships, move the relevant entries into that build's record and clear them here.

## Older builds cannot open the food data after updating

Three storage changes in the UX revamp (#140) each move the food ledger to a new schema. Once a device opens the food log with a build that contains one of them, the stored data is migrated forward and **an older build can no longer open it**. Reinstalling an earlier TestFlight build after updating is therefore not a safe way back; export or back up first.

| Change | Merged in | Archive contract | Schema |
| --- | --- | --- | --- |
| Confirmation contract v5: one Log action (`food_confirmation_v5`, `confirm_food_v3`) | [PR206](https://github.com/syamaner/WeeklyHealthReport/pull/206) (#195) | 4 | `food-ledger-v4` |
| Web source review manifest v2 | [PR207](https://github.com/syamaner/WeeklyHealthReport/pull/207) (#196) | 5 | `food-ledger-v5` |
| Favourites, quick add and plain water (approved, not yet merged) | #198, contract [PR209](https://github.com/syamaner/WeeklyHealthReport/pull/209) | 6 | `food-ledger-v6` |

Existing records keep their bytes in each migration; the new versions add record types and fields alongside them. The Daily JSON export stays pinned to food contract 3, so exported files are unchanged in shape.

## User-visible changes

- New navigation: Home, Food Log, Health, Export and Settings behind a gear (#194, [PR205](https://github.com/syamaner/WeeklyHealthReport/pull/205)).
- One Confirm screen with a single Log action for every food entry route (#195).
- Redesigned Add food, search results and web lookup, with recent foods (#196).
- Food Log with day navigation and a read-only saved entry with history, edit, remove and restore (#197, [PR211](https://github.com/syamaner/WeeklyHealthReport/pull/211)).
- Health screen with a period picker, summary tiles, collapsible sections and an always-expanded Full Page; Export screen with fewer steps; Google Drive setup moved to Settings (#200, [PR210](https://github.com/syamaner/WeeklyHealthReport/pull/210), once merged).

HealthKit access stays read-only and no new data leaves the device in these changes.
