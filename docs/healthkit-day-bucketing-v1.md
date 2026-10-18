# HealthKit day bucketing v1 (#49)

Status: **owner-approved, 18 Oct 2026.** The owner took the recommended option for every decision in section 8. Policy identifier: `healthkit_day_buckets_injected_calendar_v1` (Developer tools only).

Every daily HealthKit statistics collection must bucket by the same local-calendar days that the report model uses. Today the model's days come from an injected `Calendar`, while HealthKit's buckets come from a calendar HealthKit chooses itself. This proposal makes the injected calendar the single authority and adds a check that refuses to attach a bucket to a day it does not match.

## 1. What goes wrong today

### 1.1 Two calendars

`ReportPeriod.make(selection:now:calendar:)` and `precedingEquivalent(calendar:)` (`Models/ReportPeriod.swift`) build `completedDays` with the injected calendar, so a DST day is 23 or 25 hours long in that calendar's time zone. `HealthKitClient` then runs `HKStatisticsCollectionQueryDescriptor` with `anchorDate: period.interval.start` and `intervalComponents: DateComponents(day: 1)`, and looks each bucket up with `statisticsByStart[day.start]`.

The descriptor takes no calendar or time zone. Apple's documentation says the anchor "sets the start time for a single time interval", that "all other time intervals must align with this interval" and that "each time interval has the same length" ([`anchorDate`](https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquery/anchordate); [Executing statistics collection queries](https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries)). It does not say which calendar or time zone turns `day: 1` into instants, nor what happens across a DST change. Apple's own samples build the anchor with `Calendar.current` or a fresh Gregorian calendar, which suggests HealthKit applies the process's current calendar, but that is an inference, not a documented contract. HealthKit's calendar is therefore outside our control and not observable from the descriptor.

### 1.2 Where the two diverge

| Case | Effect today |
|---|---|
| Injected time zone differs from the process time zone (tests, a future caller, the Daily JSON export's frozen reporting time zone after the device zone changes mid-refresh) and either zone has a DST change inside the period | After the change, HealthKit's buckets start one hour away from the model's midnights. `statisticsByStart[day.start]` misses, so every later day in the period silently becomes missing. Totals are not wrong, they are absent |
| Both calendars agree (normal production: `.autoupdatingCurrent` everywhere) | No divergence expected, including DST weeks, if HealthKit uses calendar day arithmetic in the same zone. This is the undocumented assumption the check in section 2 guards |
| Device time zone changes between building the period and running the query | Same as the first row for any DST change in either zone. Without DST, both calendars produce 24 hour days from the same anchor, so buckets still line up by accident |
| Nutrition context in the Daily JSON export (`HealthKitClient` nutrition totals) | Worse: buckets are keyed by `window.calendar.startOfDay(for: statistics.startDate)` with no alignment check, so a misaligned bucket starting at 23:00 is filed under the previous day and can overwrite that day's total. This is a wrong value, not a missing one |

`HKStatisticsQueryDescriptor` reads over one explicit interval (today so far, one export day) are not affected: they take exact start and end instants and do not bucket.

## 2. The fix

1. **One calendar.** `HealthKitClient` gets the reporting calendar explicitly. Each daily collection method takes the calendar that built the period (decision 1). No collection query relies on HealthKit's own choice of calendar to define a report day.
2. **Anchor and interval from that calendar.** A small pure value in `Models`, `DailyBucketPlan`, derives `anchorDate = calendar.startOfDay(for: period.interval.start)` and `intervalComponents = DateComponents(day: 1)`, and checks that the period's `completedDays` are exactly consecutive `calendar` days. It owns no HealthKit types. Every daily collection query in `HealthKitClient` uses it: steps, blood glucose, resting heart rate, HRV, and the export's nutrition totals.
3. **Alignment check.** A pure `DailyBucketAlignment.match(bucketStarts:days:)` maps each returned bucket start to a report day only when `bucketStart == day.start` exactly. It returns the matched days, plus any bucket that matches no report day as a mismatch. Buckets with no samples carry no statistic and are not mismatches.
4. **On mismatch** (decision 2): the adapter discards the whole collection for that read and re-reads each completed day with one `HKStatisticsQueryDescriptor` over that day's exact `DateInterval`, with the same options. That keeps HealthKit's source resolution, uses the injected day boundaries exactly and never attaches a value to the wrong day. Developer tools records that the fallback ran, for which metric and how many buckets mismatched.
5. **Nutrition** stops re-keying by `startOfDay` and uses the same alignment check, so a bucket can never be filed under a neighbouring day.

Nothing else changes: completed days stay start-inclusive and end-exclusive, today stays omitted from report periods, units stay converted at the query boundary, an absent statistic stays "no data or no access", and a returned zero stays a sampled zero.

## 3. Metrics affected

| Metric | Query | Periods read |
|---|---|---|
| Steps (Health report average, coverage, total) | `fetchDailySteps`, `cumulativeSum` | Current period |
| Steps trend ([health-steps-trend-v1.md](health-steps-trend-v1.md)) | `fetchDailySteps` | Current **and** `precedingEquivalent`, so a DST change in either period, or one between them, matters |
| Blood glucose | `fetchDailyBloodGlucose`, `discreteAverage`/`Min`/`Max` | Current period |
| Resting heart rate and its trend | `fetchDailyDiscreteAverage` | Current and previous |
| HRV and its trend | `fetchDailyDiscreteAverage` | Current and previous |
| Daily JSON export context (steps, glucose, resting heart rate, HRV) | The same four methods via `window.context` and its previous period | Context and previous |
| Daily JSON export nutrition context (`nutrition_last_7_completed_days_v1`) | Nutrition collection per nutrient | 14 completed days plus today to the cutoff |

Not affected: today-so-far reads, single-day export reads, latest-measurement lookbacks, sleep, workouts, weight, body fat, blood pressure, blood oxygen and VO₂ max, which read samples and assign days in pure code with the injected calendar already.

## 4. Expected effect on values

- **Normal production** (one calendar, no time-zone change during a refresh): no change. Every bucket already matches, the check passes and output stays byte-identical, including Copy all and Daily JSON export bytes.
- **Divergent calendars** (tests with a non-default zone, a time-zone change mid-refresh, a DST week in either zone): days that are wrongly reported missing today become sampled days with their HealthKit totals. Averages, coverage counts and trends can change, and a trend shown as "Insufficient history" may gain a percentage. These are corrections towards the documented semantics, not new behaviour.
- **Nutrition context:** a misfiled or overwritten daily total is replaced by the correct day's total or by an honest absence.
- No value ever becomes zero where it was unknown.

## 5. Apple Health comparison (owner, on device)

Simulator runs prove software behaviour only. On a signed Debug build:

1. In Settings on the iPhone, keep the automatic time zone. Pick a week that contains a DST change (for Europe/London, the week containing the last Sunday of October or March) and has visible step and heart data.
2. In the app, choose **Last week** (or **Last 7 days** if the change fell in the last seven days). Open **Settings → Developer tools → Developer Diagnostics**.
3. For each day, compare Developer Diagnostics' daily steps, glucose average, resting heart rate and HRV against Apple Health's day view (Health → Steps → D, and the equivalents). Values should match to the displayed precision, with the 23 or 25 hour day present and the days after it not missing.
4. Confirm Developer Diagnostics reports no bucket fallback in the normal case.
5. Optional: change the device time zone manually to one without DST, refresh, and repeat for the same week. Days follow the new zone (README, "All dates use the iPhone's local calendar and time zone"), so day totals may legitimately differ from step 3, but no day should be missing where Apple Health shows data in that zone.
6. Record the date, device time zone, iOS version and the per-day comparison in the PR, without personal values in the repository.

## 6. Contract tests (synthetic fixtures, no HealthKit)

All pure tests in `WeeklyHealthReportTests`, with a process-default time zone that differs from the injected one (for example the injected `Europe/London` and `America/Sao_Paulo` or `Asia/Tokyo` for the simulated HealthKit calendar).

1. **Plan, autumn DST:** Europe/London, Last week containing Sunday 25 October 2026. `DailyBucketPlan` yields seven consecutive days, one of 25 hours, anchor at local midnight.
2. **Plan, spring DST:** Europe/London, the week containing Sunday 29 March 2026, one 23 hour day.
3. **Plan, previous equivalent across DST:** current period after the change, previous period before it; both plans are consecutive in their own calendar, and the steps trend's two reads produce 7 + 7 aligned days.
4. **Alignment, matching buckets:** bucket starts generated by the same calendar match every day; no fallback.
5. **Alignment, mismatched zone:** bucket starts generated by stepping 24 hours from the anchor (what a calendar in a non-DST zone produces) across the London change: days before the change match, every bucket after it is reported as a mismatch and the result requests the per-day fallback. No bucket is attached to a neighbouring day.
6. **Alignment, time-zone change:** period built in Europe/London, bucket starts generated in Asia/Tokyo: every bucket mismatches; the fallback is requested.
7. **Midnight boundary:** a refresh at 00:00:00 and 23:59:59 local keeps today omitted and the end exclusive.
8. **No samples:** a day with no bucket stays missing (not zero) and is not a mismatch.
9. **Fake adapter contract:** a `HealthDataProviding` fake that serves misaligned collections and per-day results proves that steps, glucose, resting heart rate, HRV and the steps trend recover the per-day values, and that existing summary tests (`StepSummaryTests`, `GlucoseSummaryTests`, heart trend tests) pass unchanged.
10. **Nutrition:** a misaligned nutrition collection never overwrites a neighbouring day; Daily JSON export golden fixtures stay byte-identical in the aligned case.

The live HealthKit calendar behaviour itself cannot be proven in a unit test; section 5 covers it.

## 7. Out of scope

- Changing which time zone defines a report day (the README rule stays: the iPhone's current local calendar and time zone at refresh).
- Re-attributing samples recorded in another time zone to the zone they were recorded in.
- Any change to aggregation, coverage thresholds, units, rounding or copy.

## 8. Owner decisions

1. **How should `HealthKitClient` receive the calendar?** Options: (a) pass the calendar into each daily collection method alongside the period; (b) store the calendar's time zone on `ReportPeriod` itself; (c) inject one calendar into `HealthKitClient` at the composition root. **Decided (18 Oct 2026): (a).** The calendar that built the period travels with the call, which also covers the Daily JSON export's frozen reporting zone; (c) can drift from the export's calendar, and (b) changes a widely used model type.
2. **What happens when a bucket does not match a report day?** Options: (a) re-read each completed day with a per-day statistics query; (b) fail the metric with an explicit error; (c) keep today's behaviour and only log. **Decided (18 Oct 2026): (a).** It keeps HealthKit's source resolution and the exact injected days, and shows the user correct values instead of a failure; (c) leaves silent missing days.
3. **Should we drop collection queries altogether and always use per-day statistics queries?** That removes the dependency on HealthKit's calendar entirely, at the cost of 7 to 15 queries per metric per read instead of one. **Decided (18 Oct 2026): no, keep the collection query with the check and fallback,** since the normal case is aligned and the check makes the fallback deterministic. Revisit if device evidence shows HealthKit does not use calendar day arithmetic in DST weeks.
4. **Should the nutrition export context be fixed in the same change?** **Decided (18 Oct 2026): yes.** It is the only path where misalignment produces a wrong value rather than a missing one, and it shares the same plan and check. The aligned-case export bytes stay unchanged, so no export schema or policy version change is needed.
5. **Should the fallback be visible outside Developer tools?** **Decided (18 Oct 2026): no.** Values are correct either way; per AGENTS.md, provider stages and diagnostics stay in Developer tools.
6. **Does the bucketing change need a new policy version on the Daily JSON export?** **Decided (18 Oct 2026): no.** The contract already defines days in the reporting time zone, including 23 and 25 hour DST days; this change makes the implementation honour it. Record the policy identifier above in Developer tools only.
