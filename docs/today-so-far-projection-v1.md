# Today-so-far health projection v1

Status: **owner-approved, 12 October 2026: D1 to D11 (section 11) approved with every recommended answer (approval comment on PR #208). Architecture gate passed with changes, 11 October 2026; changes folded in below. File and type references after the phase 3, 4, 5 and 7 rebase are in the phase plan's Rebase notes.** Contract change 1 of [ux-revamp-v1.md](ux-revamp-v1.md), delivered by #199 (phase plan: [ux-revamp-phase-6-home.md](ux-revamp-phase-6-home.md)). Policy identifier: `today_so_far_health_v1`. Wireframe: [`designs/ux-revamp-v1/Main.dc.html`](designs/ux-revamp-v1/Main.dc.html), "Health · today so far".

Home shows a few provisional health values for the current local day. This document fixes what each value means, how it is queried, how absence is shown and why the Health report and Daily JSON export cannot change as a result.

## 1. Three day rules stay distinct

| Surface | Window | Owner |
|---|---|---|
| Health report | Completed local days only; today excluded from period summaries; latest measurements use their documented lookbacks | `ReportPeriod`, README "How the calculations work" |
| Daily JSON export | Selected day: today from local midnight to the frozen refresh cutoff, or one of the previous seven complete days | [daily-export-contract.md](daily-export-contract.md), `DailyExportWindow` |
| Home "today so far" | Today from local midnight to the projection's captured instant; provisional, labelled, never stored or exported | this document |

The Home projection is a third, separate path. It never feeds the report, the copied text, the Full Page document or the Daily JSON export, and none of those feed it. The README gains one line under "How the calculations work" stating this third rule (D10).

## 2. Window

`TodaySoFarWindow.capture(at now: Date, calendar: Calendar)` is pure and is the only place the Home window is computed:

- **Calendar snapshot.** Like `DailyExportWindow.capture` (`Models/DailyHealthExport.swift`, lines 40 to 44), it builds a new `Calendar(identifier:)` and copies `timeZone`, `locale`, `firstWeekday` and `minimumDaysInFirstWeek`, so a later system time-zone change cannot move a captured window. An `autoupdatingCurrent` calendar is never stored.
- `asOf = now`, captured once per refresh. Every read in one refresh uses the same `asOf` and the same snapshotted calendar.
- `day = [calendar.startOfDay(for: asOf), asOf)`, start inclusive, end exclusive. On a 23- or 25-hour DST day the window is still local midnight to now; no fixed 24-hour arithmetic is used.
- `sleep = [noon on the previous local day, min(noon today, asOf))`, the existing noon-to-noon wake-date bucket ending today (`SleepSummary`, `DailyExportWindow.sleep`), clipped to `asOf`. `sleepIsComplete = asOf >= noon today` (D1).
- `weightLookbackStart = HealthReportingPolicy.weightLatestLookbackStart(asOf:calendar:)`, a new function over a new constant `HealthReportingPolicy.weightLatestLookbackDays = 30`, computing `asOf` minus 30 calendar days (the existing rule). The existing `HealthKitClient.fetchWeightMeasurements(asOf:calendar:)` replaces its literal `-30` with this function; that edit is a no-op and is the only changed existing line in `HealthKitClient.swift` (section 7).
- `bloodPressureLookbackStart = HealthReportingPolicy.bloodPressureLatestLookbackStart(asOf:calendar:)`, the existing 30-day lookback from local start of today.

The clock and calendar are injected (`FixtureClock` in tests, the composition root's clock and calendar in the app). The window type has no HealthKit, SwiftUI or concrete-clock dependency. If `asOf` equals local midnight exactly, `day` is empty and both cumulative rows are no data without a query.

## 3. Values

| Highlight | HealthKit type (already authorised) | Adapter call | Pure rule | Shown as |
|---|---|---|---|---|
| Steps so far | `stepCount` | Existing private `fetchStepTotal(in: day)`: `HKStatisticsQueryDescriptor`, `.cumulativeSum`, predicate options `[]`, returns sources | Absent statistic or sum is no data; a returned 0 is a visible 0 (D6) | "6,412 so far" |
| Active energy so far | `activeEnergyBurned` | Existing private `fetchActiveEnergyKilocalories(in: day)` (via `fetchCumulativeTotal`), kcal | As steps. Activity measurement only; never combined with food energy (D9). No source names (section 8) | "312 kcal so far" |
| Last night's sleep | `sleepAnalysis` | Existing private `fetchAsleepIntervals(in: sleep)` | Only `asleepUnspecified`, `asleepCore`, `asleepDeep`, `asleepREM` (filtered in the adapter as today); clip to `sleep`, merge overlaps with `SleepSummary.mergeOverlaps`; zero merged duration is no data | Complete: "7 h 12 min · last night"; before noon: "6 h 10 min so far · last night" (D1) |
| Latest weight | `bodyMass` | Existing private `fetchWeightMeasurements(asOf:calendar:)` | Projection filters to `[weightLookbackStart, asOf)` itself, then `WeightMeasurement.latest(in:)` (latest end date, then smallest UUID) | "72.4 kg · 07:05" or with day (D4) |
| Latest blood pressure | `bloodPressure` correlation with `bloodPressureSystolic`, `bloodPressureDiastolic` | Existing private `fetchBloodPressureReadings(for: ReportPeriod.make(selection: .lastSevenCompletedDays, now: asOf, calendar:), asOf:calendar:)`. Its query start is `min(period start, 30-day lookback)`, which is the lookback, so the predicate is identical to the report's | Only correlations with exactly one visible systolic and one diastolic sample (existing adapter rule); never join independent samples; then the extracted pure `BloodPressureReading.latestValid(in:lookbackStart:asOf:)` | "123/78 mmHg · 07:10" |

`BloodPressureReading.latestValid(in:lookbackStart:asOf:)` is extracted from `BloodPressureSummary.calculate` without behaviour change: the same `>= lookbackStart`, `<= asOf`, finite and positive filter, and the same `max(by: date)` selection with no added tie-break. `BloodPressureSummary` calls it; the existing `BloodPressureSummaryTests` pass unchanged and pin the extraction.

Statistics, not manual sums: HealthKit merges overlapping sources before applying `cumulativeSum` (README "Steps"; Apple: [HKStatisticsQuery](https://developer.apple.com/documentation/healthkit/hkstatisticsquery), [HKStatisticsQueryDescriptor](https://developer.apple.com/documentation/healthkit/hkstatisticsquerydescriptor), [cumulativeSum](https://developer.apple.com/documentation/healthkit/hkstatisticsoptions/cumulativesum), [HKStatistics.sources](https://developer.apple.com/documentation/healthkit/hkstatistics/sources)). The app never adds raw iPhone and Watch samples. Sleep stages: [HKCategoryValueSleepAnalysis](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis). Blood pressure correlation: [HKCorrelationTypeIdentifier.bloodPressure](https://developer.apple.com/documentation/healthkit/hkcorrelationtypeidentifier/bloodpressure). Latest-sample query shape: [HKSampleQueryDescriptor](https://developer.apple.com/documentation/healthkit/hksamplequerydescriptor). Read-authorisation privacy: [Protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy). Apple's pages are script-rendered and could not be machine-read while drafting; the semantics above are the ones the repository already relies on, and the implementer re-checks the pages at implementation time.

Units are converted at the query boundary; the projection receives plain `Double`, `Date` and existing model values. Rounding happens only in presentation. Diagnostics keep unrounded values.

No medical interpretation: no targets, rings, goals, ranges, colours, classifications, comparisons with previous days or net energy balance.

## 4. Port and states

The port returns domain values only:

```swift
enum TodaySoFarRead<Value: Equatable>: Equatable { case value(Value), noData, failed, healthUnavailable }
struct TodaySoFarHealthInputs: Equatable {
    let steps: TodaySoFarRead<DailyStepTotal>           // value plus source names; nil steps map to .noData
    let activeEnergyKilocalories: TodaySoFarRead<Double>
    let asleepIntervals: TodaySoFarRead<[AsleepInterval]>
    let weights: TodaySoFarRead<[WeightMeasurement]>
    let bloodPressure: TodaySoFarRead<[BloodPressureReading]>
}
protocol TodaySoFarHealthReading: Sendable { func todaySoFarInputs(for window: TodaySoFarWindow) async -> TodaySoFarHealthInputs }
```

No `Error`, `HK*` or framework type appears in `TodaySoFarHealthInputs`. The adapter maps errors: if health data is unavailable (`isHealthDataAvailable == false` or `HealthDataError.unavailable`), every row is `.healthUnavailable`; any other thrown error makes only that row `.failed`. An empty successful result is `.noData`. The pure projection then produces one state per row, so one failed read never hides the others:

| State | When | Copy (house style) |
|---|---|---|
| Loading | Refresh in progress and no earlier value for the same `day` | Placeholder row, "Loading" for VoiceOver |
| Available | A value exists | Value plus "so far", "last night" or timestamp |
| No data or no access | Read succeeded with nothing visible | "No visible data, or Health access was not granted." (short form on the card: "No data") |
| Failed | That row's read threw | "Could not read Apple Health." with Try again |
| Health unavailable | Device has no Apple Health | Card shows "Apple Health is not available on this device." (D8) |

An unavailable read is never 0, never a dash that reads as 0 and never "access denied": HealthKit does not disclose read denial. A value from a previous `day` is never shown after rollover; the row returns to Loading for the new day.

## 5. Authorisation

A consumer-owned capability `HealthReadAuthorizationRequesting { func requestReadAuthorization() async throws }` is declared beside the Home model. `HealthKitClient` already has this method, so its conformance is an empty extension; the composition root wires the same client instance. `toShare` stays `[]` and the read set is unchanged. `TodaySoFarHealthModel` calls the requester at most once per app session, on first Home appearance, then refreshes regardless of the outcome (a completed sheet says nothing about read access). A thrown error leaves rows in their read-derived states (D5).

## 6. Refresh

- Home appears; scene becomes active (existing `scenePhase` handler).
- `UIApplication.significantTimeChangeNotification` (local midnight, time-zone change, DST) and `NSCalendarDayChanged`.
- After the authorisation request in section 5 returns.
- Manual pull to refresh on Home.

Each refresh captures a new window with the then-current calendar snapshot and increments a generation; a result from an older generation is discarded, as in `WeeklyReportViewModel`. No `HKObserverQuery`, background delivery, timer or polling (AGENTS.md). The card footer shows "As of 14:32" from `asOf` so staleness is visible (D7).

## 7. Architecture and adapter non-drift

| Layer | Owns | File (app target) |
|---|---|---|
| Domain | `TodaySoFarWindow`, `TodaySoFarRead`, `TodaySoFarHealthInputs`, `TodaySoFarHealthProjection.make(inputs:window:)`, `TodaySoFarHealthReading` port; `HealthReportingPolicy.weightLatestLookbackDays` and `weightLatestLookbackStart`; `BloodPressureReading.latestValid` | `Models/TodaySoFarHealth.swift`, `Models/ReportPeriod.swift`, `Models/BloodPressureSummary.swift` |
| Infrastructure | `HealthKitClient: TodaySoFarHealthReading, HealthReadAuthorizationRequesting` | appended extension at the end of `HealthKit/HealthKitClient.swift` |
| Application | `TodaySoFarHealthModel` (`@MainActor`): clock, calendar, generation, authorisation once, triggers | `Views/TodaySoFarHealthModel.swift` |
| Presentation | Copy and number and time formatting | `Utilities/HealthReportFormatter.swift` (new `todaySoFar` functions) |

**Access.** The helpers Home calls are `private` (`fetchWeightMeasurements(asOf:calendar:)`, `fetchActiveEnergyKilocalories(in:)`, `fetchStepTotal(in:)`, `fetchAsleepIntervals(in:)`, `fetchCumulativeTotal`, `fetchBloodPressureReadings(for:asOf:calendar:)`). Swift lets an extension in the same file use `private` members, so the conformance lives in `HealthKitClient.swift` and no access modifier changes. The PR diff of that file shows only appended lines plus the single no-op `-30` to `HealthReportingPolicy.weightLatestLookbackStart` replacement; no existing body, predicate or options line changes.

**Proof is diff review, not tests.** The export golden snapshots and report view-model tests run on `FakeHealthDataProvider`, so they prove the pure and orchestration paths but cannot detect a changed HealthKit predicate. Adapter non-drift is proven by reviewing the `HealthKitClient.swift` diff against the rule above, recorded in the PR. Extracting shared HealthKit primitives is banned in this phase. The two pure-model extractions (weight lookback function and `latestValid`) land first as their own behaviour-neutral commit, with existing tests unchanged, before any Home code.

`HealthDataProviding` (the report's port) and `FakeHealthDataProvider` are not changed.

## 8. Developer Diagnostics

A "Today so far (Home)" section in `DeveloperDiagnosticsView` lists: time zone, `day.start`, `asOf`, sleep window and whether it is complete; unrounded steps with HealthKit source names; unrounded active energy without source names (the existing helper returns none, and no new helper is added); merged asleep intervals and total seconds; latest weight value and end date; latest blood-pressure pair, start date and source; each row's state. No UUIDs or device identifiers are shown.

## 9. Contract tests (written first)

Pure (`TodaySoFarHealthTests`, synthetic fixtures, `Europe/London` and `America/New_York`):

1. Window: start is local midnight; end is `asOf`; on spring-forward (23 h) and fall-back (25 h) days the window starts at local midnight with no fixed 86,400-second assumption.
2. Midnight: `asOf` exactly at local midnight gives an empty `day`; a sleep interval and a weight sample at 23:59:59 yesterday are classified correctly against the window bounds. (Steps and energy at the midnight boundary are HealthKit statistics behaviour and are checked on device, section 10.)
3. Calendar snapshot: a window captured in London is unchanged after the supplied calendar's time zone is later changed to New York.
4. Rollover: projections at 23:59 and 00:01 use different days; earlier values are not carried over.
5. Steps and energy: `.noData` is no data; value 0 is a visible 0; positive values pass through unrounded.
6. Sleep: only the four asleep categories count; overlapping sources counted once; intervals crossing noon yesterday or `asOf` are clipped; zero merged duration is no data; before noon the row is in progress ("so far"), at or after noon it is complete.
7. Weight: shared lookback function used by window and adapter; a sample at exactly `asOf` minus 30 days is included, one at 30 days plus 1 s earlier is excluded by the projection's own filter; latest by end date with UUID tie-break.
8. Blood pressure: `latestValid` used by `BloodPressureSummary` and Home; latest complete pair; incomplete correlations never paired; non-finite or non-positive excluded; existing `BloodPressureSummaryTests` unchanged.
9. Port error mapping (a pure function the adapter calls, tested directly): health unavailable gives `.healthUnavailable` for all five rows; another error gives `.failed` for that row only.
10. Formatter: exact strings for every state; time formatting uses the system time style (`.shortened`), pinned with `en_GB` (24-hour, "07:05") and `en_US` (12-hour, "7:05 AM") locales; "Yesterday" and dated forms (D4).

Unchanged outputs (regression):

11. `DailyHealthExportGoldenSnapshots`, `DailyHealthExportTests`, `WeeklyReportViewModelTests`, `HealthReportFormatterTests` and `WeeklyReportScreenshotTests` pass with no fixture edits.
12. The copied report text, the Full Page document text and the Daily JSON bytes contain none of the Home strings ("so far", "last night", "As of").
13. `HealthDataProviding` gains no members: `FakeHealthDataProvider.swift` compiles with no diff (checked in review, since compilation alone does not show the absence of a diff).

View model (`TodaySoFarHealthModelTests`): the authorisation requester fake is called exactly once across two Home appearances and a refresh follows; stale generation discarded; refresh on day change, time change and foreground; previous-day values cleared on rollover; injected clock drives `asOf`.

Boundary: the app model import check (phase plan) fails on a planted `import HealthKit` in a temporary copy of `Models/`.

Native render (simulator, in the phase plan): each state at default and accessibility Dynamic Type sizes, with VoiceOver labels including units and "so far".

## 10. Apple Health comparison (device, manual)

Simulator evidence proves software behaviour only. On a device, with Developer tools enabled:

1. Pull to refresh Home, note `asOf` in Settings → Developer tools → Developer Diagnostics → Today so far.
2. Steps: Health → Steps → D (today). Compare the total with the unrounded diagnostic value. Health may update after `asOf`; refresh both and compare again.
3. Active energy: Health → Active Energy → D, same method.
4. Midnight boundary: shortly after local midnight, refresh Home and confirm steps and active energy start from the new day and match Health's D view.
5. Sleep: Health → Sleep → the night ending today. Compare asleep time (not time in bed) with the diagnostic total; before noon the row says "so far". If they differ, inspect the merged intervals for overlapping third-party or manual records (README "Sleep").
6. Weight: Health → Weight → Show All Data; the newest sample's value and time match Home.
7. Blood pressure: Health → Blood Pressure → Show All Data; the newest reading's pair and time match Home, and the source matches Diagnostics.
8. Export unchanged: export today's Daily JSON with the same data; its today step and active-energy values use the export's own frozen cutoff and are not taken from Home.
9. Record the result in the PR without personal values.

## 11. Owner decisions

| ID | Question | Answer | Status |
|---|---|---|---|
| D1 | Which night is "last night", and its label? | Today's wake-date noon-to-noon bucket clipped to `asOf`, matching report and export. Before the bucket's noon the row reads "… so far · last night"; with no asleep time, "No sleep visible yet, or no access" | Approved |
| D2 | Weight lookback | Existing 30 days ending at `asOf`, now a named constant; date shown when not today. The export's today-only weight rule is not used on Home | Approved |
| D3 | Blood-pressure lookback | Existing 30 days from local start of today; latest complete pair only, no batches or slots | Approved |
| D4 | Timestamp format | System time style (`.shortened`): today time only; "Yesterday, <time>"; older "8 Oct, <time>" | Approved |
| D5 | May Home trigger read authorisation? | Yes, via `HealthReadAuthorizationRequesting`, once per session, same read set, `toShare` empty, then refresh | Approved |
| D6 | Visible zero | A returned 0 is "0 so far"; absence is "No data" | Approved |
| D7 | Live updating | No observer queries or timers; triggers in section 6; "As of HH:mm" | Approved |
| D8 | Health unavailable device | Show the card in the unavailable state, not hidden | Approved |
| D9 | Active energy beside food energy | Never a net or balance; separate cards | Approved |
| D10 | Exception to "show every metric in the main screen, copied report and Diagnostics" (AGENTS.md) | Home highlights appear on Home and in Diagnostics only. They are provisional, partial-day values; adding them to the copied report or export would mix a third day rule into completed-day and selected-day outputs. README records the rule | Approved |
| D11 | Home notes row day | Pinned to today, independent of the export's selected day (phase plan) | Approved |

## 12. Known gaps carried, not fixed here

- Weight lookback is 30 days back from `asOf` while blood pressure is 30 days back from local start of today; both are kept, because unifying them would change report outputs.
- `latestValid` keeps `max(by:)` with no identifier tie-break; a deterministic tie-break is a separate report change with its own tests.
- No new HealthKit type is read. Any additional highlight is a new owner decision and touches only the health feature's files.
