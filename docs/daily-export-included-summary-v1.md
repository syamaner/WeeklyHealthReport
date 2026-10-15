# Export included summary and last export of the day v1 (#217)

Status: **approved by the owner, 16 October 2026; every decision in section 7 takes its recommended option.** Deferred from UX revamp phase 7 ([ux-revamp-phase-7-health-export.md](ux-revamp-phase-7-health-export.md), open question 5); wireframe `designs/ux-revamp-v1/Export.dc.html` ("14 metrics · 2 workouts", "Last export of this day: none.").

The Export screen's "Included" list gains a count of Health metrics with data and of workouts for the selected day, and one line saying when this day was last exported from this iPhone. The Daily JSON bytes, schema and Drive behaviour do not change, and no new state is stored.

## 1. Day rule

Everything here describes the **selected export day** under [daily-export-contract.md](daily-export-contract.md): today from local midnight to the frozen refresh cutoff, or one of the previous seven complete days. It never uses the Health report's completed-day period or Home's today-so-far values.

## 2. What counts as "a metric"

A metric is one of these 15 per-day entries in the prepared envelope's `today` block (`DailyHealthMetrics`, `Models/DailyHealthExport.swift`), in this order:

weight, bodyFat, waist, bloodPressure, glucose, restingHeartRate, hrv, bloodOxygen, vo2Max, sleep, activity.steps, activity.activeEnergy, activity.exercise, watchCoverage, medications.

- **With data:** `availability == available`.
- **Denominator:** the 15 entries minus any whose availability is `unsupported` (for example medications before iOS 26).
- **Not counted as metrics:** workouts (counted separately), nutrition (its own row, "Selected Health source"), notes (their own row), `app_context` context values, and the schema-4 food fields (never present in a Drive export).
- Shown as `9 of 14 metrics have data`. With no metric available: `No Health data visible for this day, or no access`. A `no_data_or_access` entry is never shown as a zero value.

## 3. What counts as "a workout"

A workout is one element of `today.workouts.data` when `today.workouts.availability == available`: an `HKWorkout` whose start falls in the selected day window (the export's existing rule; a workout crossing midnight belongs to its start day).

| State | Text |
|---|---|
| available, n ≥ 1 | `1 workout`, `2 workouts` |
| available with an empty list, or `no_data_or_access` | `no workouts visible` (never "0 workouts") |

Full line: `Health · 9 of 14 metrics have data · 2 workouts`.

## 4. Source of the counts

The counts come from a pure function over the **in-memory prepared preview envelope**, the same value whose bytes the user reviews (`DailyDriveSessionController.preview.envelope`). They are added to `DailyExportPreviewSummary` as two plain fields. JSON is never parsed and no extra HealthKit read is made. With no preview (preparing, failed or not set up) the line is not shown; there is no placeholder count. When the day changes, the preview is cleared and the line goes with it.

## 5. "Last export of this day"

**Source: the existing persisted Drive export registry, read only.** `DailyDriveExportRegistry` (`Packages/DriveExportKit/Sources/DriveExportKit/DriveExportCoordinator.swift`) holds one `DailyDriveExportIdentity` per account, folder and report date, with `lastVerified { dataAsOf, payloadSHA256, verifiedAt }`. It is already written by every verified export and already read on restore (`restoreLastVerifiedLabel`, `DailyDriveSessionController.swift` around line 959). No new store, key or field is added.

- **Lookup:** the identity for (connected account, active folder, selected `reportDate`). This is a local Keychain read with no Drive or network request.
- **Shown:** `Last export of this day: 11/10/26 - 13:05, data up to 13:02`. The first time is `verifiedAt` and the second is the display form of `dataAsOf` (`DailyHealthExportIdentityPolicy.displayOrderingToken`), both in the shared `dd/MM/yy - HH:mm` format.
- **None:** `Last export of this day from this iPhone: none`. The registry only knows this installation's verified exports, and the copy says so.
- **No account restored, or no active folder:** the line is not shown.
- **Registry unreadable or ambiguous:** `Last export of this day: unknown`. The existing recovery state already handles the rest.
- **Not shown as an export:** `pending` operations, failures, cancellations before submission, and anything not verified. A pending operation keeps the existing needs-attention wording.
- **Refreshed:** on appearance, on day change and after any export outcome. It is read, never written, by this feature.

This replaces the session-only `lastVerifiedLabel` on the Export screen only. Developer tools keeps the existing label and adds the raw identity fields for the selected day (report date, `dataAsOf` token, `verifiedAt`, whether pending). File and account identifiers are not shown.

## 6. Consistency, privacy and architecture gate

- **Surfaces:** Export screen only. The Health screen, Copy all, Full Page and the Daily JSON are unchanged. Developer tools is as above.
- **Formats:** no change to the envelope, schema, canonical bytes, registry format or Keychain item. The counts and line are display-only.
- **Rules:** no medical interpretation (counts are of records, not health); HealthKit read-only; no new egress and no new request.
- **Presentation** (Foundation only): `DailyExportIncludedSummary.make(today: DailyHealthMetrics) -> (metricsWithData: Int, metricsApplicable: Int, workouts: Int?)` and `DailyExportLastExport` (a plain value: `verifiedAt`, `dataAsOfDisplay` or a state). The formatter produces the copy.
- **Application:** the session controller gains one read-only member, `lastVerifiedExport(for reportDate:)`, mapping the DriveExportKit identity to the plain app value. DriveExportKit types do not cross into Presentation.
- **Invariants:** the counts are derived from the reviewed preview only; nothing unverified is presented as an export; the export bytes are unchanged (golden snapshots).
- **Contract tests (written first):** the count for each availability combination, including all unsupported, all no data and workouts `no_data_or_access`; a fixed metric order and denominator; registry lookups for match, other date, other folder, other account, pending only and unreadable; zero network or transport calls during lookup (spy); `DailyHealthExportGoldenSnapshots` unchanged; `DailyExportPhaseTests` unchanged.

## 7. Owner decisions

1. **What counts as "a metric"?** Recommended: the 15 per-day Health entries listed in section 2, counted when `available`, shown as "X of Y have data", with unsupported entries left out of Y. The alternative is the wireframe's bare "14 metrics", which hides missing ones.
2. **What counts as "a workout"?** Recommended: one entry in `today.workouts.data`, with "no workouts visible" instead of 0.
3. **Where does "last export" come from?** Recommended: the existing local registry's `lastVerified` for the selected day, with no new stored state and no Drive request, labelled as this iPhone's record. Alternatives: a Drive metadata read (adds a network request) or a new local store (adds stored state).
4. **Which time is shown?** Recommended: both, the verification time and the data cutoff ("13:05, data up to 13:02"). The alternative is the verification time only.
5. **Replace the session label on Export?** Recommended: yes on Export, with Developer tools keeping the existing label and adding the raw fields.
