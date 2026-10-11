# Today-so-far health projection v1

Status: **draft for owner review, 11 October 2026.** Contract change 1 of [ux-revamp-v1.md](ux-revamp-v1.md), delivered by #199 (phase plan: [ux-revamp-phase-6-home.md](ux-revamp-phase-6-home.md)). Policy identifier: `today_so_far_health_v1`. Wireframe: [`designs/ux-revamp-v1/Main.dc.html`](designs/ux-revamp-v1/Main.dc.html), "Health · today so far".

Home shows a few provisional health values for the current local day. This document fixes what each value means, how it is queried, how absence is shown and why the Health report and Daily JSON export cannot change as a result. Owner decisions D1 to D9 (section 10) are approved before production code is written.

## 1. Three day rules stay distinct

| Surface | Window | Owner |
|---|---|---|
| Health report | Completed local days only; today excluded from period summaries; latest measurements use their documented lookbacks | `ReportPeriod`, README "How the calculations work" |
| Daily JSON export | Selected day: today from local midnight to the frozen refresh cutoff, or one of the previous seven complete days | [daily-export-contract.md](daily-export-contract.md), `DailyExportWindow` |
| Home "today so far" | Today from local midnight to the projection's captured instant; provisional, labelled, never stored or exported | this document |

The Home projection is a third, separate path. It never feeds the report, the copied text, the Full Page document or the Daily JSON export, and none of those feed it.

## 2. Window

`TodaySoFarWindow.capture(at now: Date, calendar: Calendar)` is pure and is the only place the Home window is computed:

- `asOf = now`, captured once per refresh. Every read in one refresh uses the same `asOf` and the same calendar (and therefore the same time zone).
- `day = [calendar.startOfDay(for: asOf), asOf)`, start inclusive, end exclusive. On a 23- or 25-hour DST day the window is still local midnight to now; no fixed 24-hour arithmetic is used.
- `sleep = [noon on the previous local day, min(noon today, asOf))`, the existing noon-to-noon wake-date bucket ending today (`SleepSummary`, `DailyExportWindow.sleep`), clipped to `asOf`. See D1.
- `weightLookbackStart = calendar.date(byAdding: .day, value: -30, to: asOf)`, the existing weight lookback (`HealthKitClient.fetchWeightMeasurements`, README "Weight").
- `bloodPressureLookbackStart = HealthReportingPolicy.bloodPressureLatestLookbackStart(asOf:calendar:)`, the existing 30-day lookback from local start of today.

The clock and calendar are injected (`FixtureClock` in tests, the composition root's clock and `Calendar.autoupdatingCurrent` in the app). The window type has no HealthKit, SwiftUI or concrete-clock dependency. If `asOf` equals local midnight exactly, `day` is empty and both cumulative values are "No data so far" without a query.

## 3. Values

| Highlight | HealthKit type (already authorised) | Query | Pure rule | Shown as |
|---|---|---|---|---|
| Steps so far | `stepCount` | One `HKStatisticsQueryDescriptor` with `.cumulativeSum` over `day`, predicate options `[]` (same as the export's `fetchStepTotal(in:)`) | `sumQuantity` in count; absent statistic or absent sum is no data; a returned 0 is a visible 0 | "6,412 so far" |
| Active energy so far | `activeEnergyBurned` | Same descriptor via the existing `fetchCumulativeTotal`, unit kcal | As steps. Activity measurement only; never combined with food energy | "312 kcal so far" |
| Last night's sleep | `sleepAnalysis` | Category samples overlapping `sleep` (same predicate as `fetchAsleepIntervals(in:)`) | Only `asleepUnspecified`, `asleepCore`, `asleepDeep`, `asleepREM`; `inBed` and `awake` excluded; clip to `sleep`, merge overlaps across sources with `SleepSummary.mergeOverlaps`; zero merged duration is no data | "7 h 12 min · last night" |
| Latest weight | `bodyMass` | Samples in `[weightLookbackStart, asOf)` (existing weight fetch) | `WeightMeasurement.latest(in:)`: latest end date, then smallest UUID | "72.4 kg · 07:05" (today) or with date (D4) |
| Latest blood pressure | `bloodPressure` correlation (`bloodPressureSystolic`, `bloodPressureDiastolic`) | Correlations with `.strictStartDate` in `[bloodPressureLookbackStart, asOf)` | Only correlations with exactly one visible systolic and one diastolic sample (existing client rule); never join independent samples; same latest-selection and validity filter as `BloodPressureSummary` | "123/78 mmHg · 07:10" |

Statistics, not manual sums: HealthKit merges overlapping sources before applying `cumulativeSum` (README "Steps"; Apple: [HKStatisticsQuery](https://developer.apple.com/documentation/healthkit/hkstatisticsquery), [HKStatisticsQueryDescriptor](https://developer.apple.com/documentation/healthkit/hkstatisticsquerydescriptor), [cumulativeSum](https://developer.apple.com/documentation/healthkit/hkstatisticsoptions/cumulativesum), [HKStatistics.sources](https://developer.apple.com/documentation/healthkit/hkstatistics/sources)). The app never adds raw iPhone and Watch samples. Sleep stages: [HKCategoryValueSleepAnalysis](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis). Blood pressure correlation: [HKCorrelationTypeIdentifier.bloodPressure](https://developer.apple.com/documentation/healthkit/hkcorrelationtypeidentifier/bloodpressure). Latest-sample query shape: [HKSampleQueryDescriptor](https://developer.apple.com/documentation/healthkit/hksamplequerydescriptor). Read-authorisation privacy: [Protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy). Apple's pages are script-rendered and could not be machine-read while drafting; the semantics above are the ones the repository already relies on, and the implementer re-checks the pages at implementation time.

Units are converted at the query boundary; the projection receives plain `Double`, `Date` and existing model values. Rounding happens only in presentation. Diagnostics keep unrounded values.

No medical interpretation: no targets, rings, goals, ranges, colours, classifications, comparisons with previous days or net energy balance.

## 4. States

Each highlight carries its own `MetricState`-style value, so one failed read never hides the others:

| State | When | Copy (house style) |
|---|---|---|
| Loading | Refresh in progress and no earlier value for the same `day` | Placeholder row, "Loading" for VoiceOver |
| Available | A value exists | Value plus "so far", "last night" or timestamp |
| No data or no access | Query succeeded with nothing visible | "No visible data, or Health access was not granted." (short form on the card: "No data") |
| Failed | Query threw | "Could not read Apple Health." with Try again |
| Health unavailable | `HKHealthStore.isHealthDataAvailable()` is false | Card shows "Apple Health is not available on this device." (D8) |

An unavailable read is never 0, never a dash that reads as 0 and never "access denied": HealthKit does not disclose read denial. A value from a previous `day` is never shown after rollover; the row returns to Loading for the new day.

## 5. Refresh

- Home appears; scene becomes active (existing `scenePhase` handler).
- `UIApplication.significantTimeChangeNotification` (covers local midnight, time-zone change and DST) and `NSCalendarDayChanged`.
- After the existing read-authorisation request completes (D5).
- Manual pull to refresh on Home.

Each refresh increments a generation; a result from an older generation is discarded, as in `WeeklyReportViewModel`. No `HKObserverQuery`, background delivery, timer or polling (AGENTS.md). The card footer shows "As of 14:32" from `asOf`, so a stale on-screen value is visible as stale.

## 6. Architecture

| Layer | Owns | File (app target) |
|---|---|---|
| Domain | `TodaySoFarWindow`, `TodaySoFarHealthInputs` (plain values, each wrapped in a per-metric result), `TodaySoFarHealthProjection.make(inputs:window:)` | `Models/TodaySoFarHealth.swift` |
| Port | Consumer-owned `TodaySoFarHealthReading` with one method `todaySoFarInputs(for: TodaySoFarWindow) async -> TodaySoFarHealthInputs` | same file |
| Infrastructure | `HealthKitClient` conformance in an extension that calls the existing private primitives (`fetchStepTotal(in:)`, `fetchActiveEnergyKilocalories(in:)`, `fetchAsleepIntervals(in:)`, `fetchWeightMeasurements(asOf:calendar:)`, a lookback-bounded blood-pressure fetch) | `HealthKit/HealthKitClient+TodaySoFar.swift` |
| Application | `TodaySoFarHealthModel` (`@MainActor`): clock, calendar, generation, refresh triggers | `Views/TodaySoFarHealthModel.swift` |
| Presentation | Copy and number formatting | `Utilities/HealthReportFormatter.swift` (new `todaySoFar` functions) |

`HealthDataProviding` (the report's port) and its fake are not changed. The existing public `fetch...` signatures, predicates and `fetchDailyHealthExportInputs` stay byte-identical. The blood-pressure fetch currently requires a `ReportPeriod`; the Home path adds a separate private helper with the same predicate options and pair rule rather than editing the report's function. If the implementer prefers to extract a shared primitive, the report and export tests in section 8 must pass unchanged before and after the extraction.

## 7. Developer Diagnostics

A "Today so far (Home)" section in `DeveloperDiagnosticsView` lists: time zone, `day.start`, `asOf`, sleep window; unrounded steps and active energy with HealthKit source names; merged asleep intervals and total seconds; latest weight value and end date; latest blood-pressure pair, start date and source; each highlight's state. No UUIDs or device identifiers are shown. The highlights are not added to the copied report, Full Page document or Daily JSON (an explicit exception to "every metric everywhere": these are not report metrics).

## 8. Contract tests (written first)

Pure (`TodaySoFarHealthTests`, synthetic fixtures, fixed `Europe/London` and `America/New_York` calendars):

1. Window: start is local midnight; end is `asOf`; on the spring-forward day (23 h) and fall-back day (25 h) the window starts at local midnight and contains no fixed-86,400-second assumption.
2. Midnight: `asOf` exactly at local midnight gives an empty `day` and no-data cumulative states; a sample ending 23:59:59 yesterday is not today's.
3. Rollover: a projection made at 23:59 and one at 00:01 use different days; the earlier day's values are not carried over.
4. Steps and energy: absent statistic is no data; statistic 0 is a visible 0; positive value passes through unrounded.
5. Sleep: only the four asleep categories count; `inBed` and `awake` ignored; overlapping sources counted once; interval crossing noon yesterday or `asOf` is clipped; zero merged duration is no data; window clipped at `asOf` before noon.
6. Weight: latest by end date, UUID tie-break; sample 31 days old is excluded; sample today is shown with time only.
7. Blood pressure: latest complete pair; an incomplete correlation is skipped, never paired with another reading; non-finite or non-positive components excluded; reading from today and reading from 29 days ago both eligible.
8. States: each metric's failure is independent; Health unavailable produces the unavailable state for all five; nothing maps to 0.
9. Formatter: exact strings for every state, "so far" and timestamp forms (D4), Dynamic Type safe (no truncation of numbers).

Unchanged outputs (regression):

10. `DailyHealthExportGoldenSnapshots` and `DailyHealthExportTests` pass byte for byte with no fixture edits.
11. `WeeklyReportViewModelTests`, `HealthReportFormatterTests` and `WeeklyReportScreenshotTests` pass with no fixture edits; a test asserts the copied report text contains none of the Home copy ("so far", "last night").
12. A compile-level check: `HealthDataProviding` gains no members and `FakeHealthDataProvider` needs no change.

View model (`TodaySoFarHealthModelTests`): stale generation discarded; refresh on day change, time change and foreground; previous-day values cleared on rollover; injected clock drives `asOf`.

Native render (simulator, in the phase plan): Home health card renders each state at default and accessibility Dynamic Type sizes with VoiceOver labels that include units and "so far".

## 9. Apple Health comparison (device, manual)

Simulator evidence proves software behaviour only. On a device, with Developer tools enabled:

1. Pull to refresh Home, note `asOf` in Settings → Developer tools → Developer Diagnostics → Today so far.
2. Steps: Health → Steps → D (today). Compare the total with the unrounded diagnostic value. Small differences can come from Health updating after `asOf`; refresh both and compare again.
3. Active energy: Health → Active Energy → D, same method.
4. Sleep: Health → Sleep → the night ending today. Compare asleep time (not time in bed) with the diagnostic total; if they differ, inspect the merged intervals for overlapping third-party or manual records (README "Sleep").
5. Weight: Health → Weight → Show All Data; the newest sample's value and time match Home.
6. Blood pressure: Health → Blood Pressure → Show All Data; the newest reading's pair and time match Home, and the source matches Diagnostics.
7. Export unchanged: export today's Daily JSON before and after installing the phase build with the same data; the exported today step and active-energy values use the export's own frozen cutoff, are byte-identical in structure and are not taken from Home.
8. Record the result in the PR without personal values.

## 10. Owner decisions

| ID | Question | Recommended answer |
|---|---|---|
| D1 | Which night is "last night"? | Today's wake-date noon-to-noon bucket, clipped to `asOf`, matching the report and export bucket. Before waking it may show partial or no sleep; copy says "last night" only when the bucket has asleep time, otherwise "No sleep visible yet, or no access". Alternative (latest bucket with sleep) would introduce a fourth day rule. |
| D2 | Weight lookback | Reuse the existing 30-day lookback ending at `asOf`, showing the date when not today. The export's "today only" weight rule is not used on Home. |
| D3 | Blood-pressure lookback | Reuse the existing 30 days from local start of today; latest complete pair only, no batches or slots on Home. |
| D4 | Timestamp format | Today: "07:05"; yesterday: "Yesterday, 07:05"; older: "8 Oct, 07:05", locale 24-hour per system setting. |
| D5 | May Home trigger the existing read-authorisation request? | Yes, the same read set, `toShare` empty, once on first Home appearance; no new types. |
| D6 | Visible zero | A returned statistic of 0 is shown as "0 so far" (README steps rule); absence is "No data". |
| D7 | Live updating | No observer queries or timers; refresh on the triggers in section 5 and show "As of HH:mm". |
| D8 | Health unavailable device | Show the card with the unavailable state rather than hide it, so absence is explicit. |
| D9 | Active energy beside food energy | Never compute or display a net or balance; the two cards stay separate. |

## 11. Known gaps carried, not fixed here

- Weight lookback is 30 days back from `asOf` while blood pressure is 30 days back from local start of today; both are reused as documented rather than unified, because unifying would change report outputs.
- `BloodPressureSummary` selects the latest reading with `max(by:)` and no identifier tie-break; Home reuses it unchanged. A deterministic tie-break, if wanted, is a separate report change with its own tests.
- No new HealthKit type is read. Any additional highlight (for example exercise minutes) is a new owner decision and a contribution, not a Home change.
