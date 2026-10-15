# Health steps trend v1 (#215)

Status: **approved by the owner, 16 October 2026; every decision in section 9 takes its recommended option.** Policy identifier: `steps_trend_previous_equivalent_v1`. Deferred from UX revamp phase 7 ([ux-revamp-phase-7-health-export.md](ux-revamp-phase-7-health-export.md), "Deferred wireframe items"); wireframe `designs/ux-revamp-v1/Health.dc.html` ("↑ 6% vs previous" on the steps tile).

The Health report gains one descriptive row: how the selected period's average daily steps compares with the equivalent previous period, as a signed whole percentage. Nothing else about steps changes.

## 1. Day rules

This is a Health report value only, so it uses **completed local-calendar days** (start included, end excluded, today omitted). It never uses Home's today-so-far projection ([today-so-far-projection-v1.md](today-so-far-projection-v1.md)) and is not added to the Daily JSON export, whose `app_context.steps` keeps its current fields and bytes ([daily-export-contract.md](daily-export-contract.md)).

## 2. Periods

- **Current period:** the selected `ReportPeriod` (Last 7 days, This week or Last week), unchanged.
- **Previous period:** `ReportPeriod.precedingEquivalent(calendar:)` (`Models/ReportPeriod.swift`), the same function the resting heart rate and HRV trends already use: the N completed days immediately before the current period's start, where N is the current period's completed-day count. Calendar day arithmetic, so 23 and 25 hour days still count as one day each.
- For Last 7 days and Last week the previous period is the 7 days before. For This week with k completed days it is the k days immediately before this week's start (the end of last week), not the same weekdays a week earlier (decision 1).
- With no completed days (Monday morning on This week) there is no previous period and no trend.

## 3. Values compared

Each side uses the existing `StepSummary.aggregate` rule: the sum of visible HealthKit daily totals divided by the number of **sampled days**. A day with no statistic is missing (not zero) and is left out of both numerator and denominator. A returned daily total of 0 is a sampled day with 0 steps, as today.

## 4. Minimum coverage

A trend needs, on **each** side, at least `max(3, ceil(5 × N / 7))` sampled days (decision 2):

| N completed days | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Sampled days needed per side | none possible | none possible | 3 | 3 | 4 | 5 | 5 |

This is stricter than the heart trends' 3 valid days because a percentage of an average with few days moves a lot and steps have strong weekday patterns.

## 5. Formula and rounding

```
change = (currentAverage − previousAverage) / previousAverage × 100
```

- Computed from the unrounded averages in `Double`.
- Rounded half away from zero to a whole percent only in presentation.
- A result that rounds to 0 shows `0%` with no sign and no arrow. Never `-0%`.
- Shown as `+6% vs previous 7d` or `-3% vs previous 7d`, using the same `"previous \(N)d"` comparison text as the heart trends (`ReportDocument.swift` line 363) and the sign style of `HealthReportFormatter.signedChange`. The tile may add `↑`/`↓` before the number. The sign is always in the text, so colour is never needed.

## 6. When nothing is shown

The row value is the existing `MetricRowVocabulary.insufficientHistory` ("Insufficient history") when the current side has data but:

- either side is below the minimum in section 4;
- the previous average is 0, so a percentage cannot be calculated;
- the period is too short (N below 3).

The row copies the steps section's state when there is no current data: loading, "No data", unavailable, failed ("Could not read Apple Health." in Copy all and Full Page), or no completed days. If only the previous-period read fails, the current rows stay as they are and the trend row says "Insufficient history". Developer tools records the failure. The trend never shows 0% in place of an unknown value.

## 7. Consistency

| Surface | Change |
|---|---|
| Health screen | New row `steps-trend`, label "Steps Trend", after `steps-coverage` and before `steps-total`. The steps tile adds it as its trend line, as the resting heart rate and weight tiles do. A pinned-id test covers it |
| Copy all | One added line, `Steps Trend: +6% vs previous 7d`, or `Steps Trend: Insufficient history` |
| Full Page | The same row with display wording (sentence case: "Steps trend") |
| Developer tools | The steps section adds the previous period's dates and per-day totals, both averages unrounded, both sampled-day counts, the required minimum and the unrounded percentage |
| Daily JSON | No change. No byte, key or schema change |

Copied text gains one line in the Steps block. No stored record or export format changes.

## 8. Query and architecture gate

- **Query.** `HealthKitClient.fetchDailySteps(for:)` keeps its shape. The view model calls it a second time with `precedingEquivalent`, as `loadPeriodMetrics` already does for resting heart rate and HRV (`Views/WeeklyReportViewModel.swift` around line 387). There is no new HealthKit type, no change to the read set, and `toShare` stays empty. The other choice, one collection query over 2N days, saves a query but changes an existing predicate. It is not recommended.
- **#49 (calendar bucketing).** `fetchDailySteps` builds its days with `HKStatisticsCollectionQueryDescriptor` (anchor at the period start, `DateComponents(day: 1)`) and matches them by start date against `period.completedDays`. HealthKit buckets with the system calendar, not the injected one. The previous window has the same exposure as today's steps rows and adds no new risk. #49 is not a blocker (decision 4), but its fix must cover both calls.
- **Domain** (`Models/`, Foundation only): `StepTrendSummary.calculate(current: [DailyStepTotal], previous: [DailyStepTotal], completedDayCount: Int) -> StepTrendSummary?` returns both summaries, the required minimum and `change: Double?`. It has no clock, locale or HealthKit dependency.
- **Application:** the view model loads the previous totals under the same refresh generation and publishes them in the existing steps state, so a stale result is dropped.
- **Presentation:** `ReportDocument` adds the row, and `HealthReportFormatter.signedPercent` does the rounding. The tiles copy the row verbatim.
- **Invariants:** the current average, coverage and Weekly Total rows are byte-identical to before. A missing day is never 0. The trend uses only completed days.
- **Contract tests (written first):** the coverage table for N = 1 to 7; missing days excluded; a 0-step sampled day included; previous average 0 gives no trend; half-away rounding at ±0.5 and no `-0%`; This week with 2, 3 and 6 completed days; DST spring and autumn weeks in `Europe/London`; a failed previous read keeps the current rows; existing Copy all golden text unchanged apart from the one line; a pinned tile id; Daily JSON golden snapshots unchanged.
- **Apple Health check (device):** Health → Steps → W lists daily totals; average the visible days for both periods by hand and compare with the unrounded Developer tools values.

No medical interpretation: no goal, target, colour coding, "good" or "bad" wording. HealthKit stays read-only. No new egress.

## 9. Owner decisions

1. **Which earlier period counts as "previous" for This week?** Recommended: the immediately preceding days of the same count (`precedingEquivalent`), the rule resting heart rate and HRV already use. The alternative is the same weekdays one week earlier, which matches weekly rhythm better but gives the app two meanings of "vs previous".
2. **Minimum coverage per side?** Recommended: at least `max(3, ceil(5N/7))` sampled days on each side (5 of 7 for a full week). Alternatives: 3 days (the heart rule) or all N days (the export nutrition rule).
3. **Percentage or absolute steps?** Recommended: a signed whole percentage, as in the wireframe, with the unrounded averages in Developer tools. The alternative is a signed difference in steps per day, which matches the other trend rows.
4. **Does #215 wait for #49?** Recommended: no. The previous window reuses the same query and the same exposure, and the #49 fix must cover both calls.
5. **Show the trend on the steps tile too?** Recommended: yes, copied verbatim from the row, like the resting heart rate and weight tiles.
