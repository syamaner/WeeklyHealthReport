# Weekly Health Report

A small native iPhone utility that reads selected Apple Health data, produces a weekly summary, and copies it as plain text. It is a personal informational utility, not medical software.

## Screenshot

<img src="docs/images/weekly-health-report-simulator.png" alt="Weekly Health Report running on an iPhone simulator" width="390">

The simulator has no personal HealthKit records, so this capture intentionally demonstrates the app's explicit **No data** state. Real values are only available when the app runs on an authorised iPhone.

## Privacy

All HealthKit reading and aggregation happens on the device. The app has no accounts, analytics, telemetry, network service, backend, database, cloud storage, background sync, or remote transport. The only export is an explicit copy to the iOS clipboard. The repository contains synthetic health fixtures only, not exported HealthKit data.

The app requests read-only access to Steps, Weight, Body Fat Percentage, Heart Rate, Resting Heart Rate, Heart Rate Variability (SDNN), Apple Exercise Time, Active Energy, Workouts, and Sleep Analysis. HealthKit intentionally does not reveal whether read permission was denied, so an authorised query with no visible samples is presented as **No data**, never as a misleading zero.

## Reporting periods

All boundaries use the device's local calendar and time zone. Intervals are half-open: start included, end excluded.

- **Last 7 Completed Days** (default): local midnight seven calendar days before today through local midnight today.
- **Current Week:** locale-aware week start through local midnight today, excluding the current partial day.
- **Previous Week:** the preceding complete locale-aware calendar week.

This is calendar-based, not a rolling 168-hour window, and remains seven days across daylight-saving changes.

## Clipboard output

**Copy Report** places plain text on the clipboard. The report period covers completed days, while the independently selected latest weight may have been recorded today. The following is a synthetic formatting example:

```text
Weekly Health Report
19–25 Aug 2026
Generated: 26 Aug 2026 at 08:30

Latest Weight: 100.6 kg
Weight Recorded: 26 Aug 2026 at 08:12
Weight 7-day Avg: 100.8 kg
Weight Trend: -0.4 kg vs previous 7d
Body Fat: 26.5%
Body Fat 28-day Avg: 26.7%
Body Fat Trend: -0.9 pp vs previous 28d
Average Daily Steps: 2,727
Resting HR Average: 73 bpm
Resting HR Trend: +3.0 bpm vs previous 7d
HRV Average: 42 ms
HRV Trend: -5.0 ms vs previous 7d
Watch Data Coverage: 4 / 7 days
Average Sleep: 6h 48m
Active Energy: 1,974 kcal
Exercise: 89 min
Workouts: 2
Workout: Walking — 31m
Workout: Functional Strength Training — 18m
```

## Aggregation semantics

- **Weight:** the latest visible body-mass sample in the preceding 30 days is shown independently. For trend, multiple readings on a day are averaged first; the mean of sampled days in the latest seven completed days is compared with the preceding seven completed days. Each side requires at least three sampled days. The signed difference is reported in kg.
- **Body Fat:** HealthKit percent values are fractional (`0.30` means `30.0%`) and are converted to percentage points at the query boundary. Up to 60 days of visible samples are read. Multiple readings on one calendar day are averaged first, then sampled days receive equal weight. Seven-day and current/previous 28-day averages require at least two sampled days. Trend is the current 28-day daily mean minus the previous 28-day daily mean, in percentage points.
- **Steps:** one local-calendar-day `HKStatisticsCollectionQueryDescriptor` using `cumulativeSum`. HealthKit resolves contributing sources; raw iPhone and Watch samples are never manually summed. Weekly average is the sum of the daily totals divided by every complete reporting day, normally seven.
- **Resting Heart Rate:** one HealthKit `discreteAverage` statistic per complete calendar day, followed by the arithmetic mean of valid daily values. Days without a visible value are omitted; days with more samples do not receive extra weight. The selected period is compared with the immediately preceding period containing the same number of complete days. A signed bpm trend requires at least three valid days on each side.
- **HRV:** the same daily-first and equivalent-period comparison using `heartRateVariabilitySDNN`, converted to milliseconds. A signed trend requires at least three valid days on each side. It is not a readiness score or medical interpretation.
- **Apple Watch coverage:** the number of complete reporting days containing at least one heart-rate sample whose HealthKit device metadata identifies an Apple Watch. This is evidence of Watch data on a day, not continuous wear time. An empty query is shown as **No data** because it may also mean heart-rate read access was denied.
- **Apple Exercise Time:** one HealthKit `cumulativeSum` statistic over the exact report interval, converted to minutes. Raw samples are not summed manually.
- **Active Energy:** one HealthKit `cumulativeSum` statistic over the exact report interval, converted to kcal. This is an activity metric, not total energy expenditure.
- **Workouts:** `HKWorkout` samples whose start date is within the report interval. The app shows count, summed duration, and each workout's HealthKit activity type and duration. Because missing read visibility is indistinguishable from an empty history, an empty result is shown as **No data** rather than a potentially misleading zero.
- **Sleep:** only `asleepUnspecified`, `asleepCore`, `asleepDeep`, and `asleepREM` samples are included. `awake` and `inBed` are excluded. Included intervals from all sources are clipped and unioned so overlaps are counted once. Each report date is a local noon-to-noon night bucket ending on that wake date; only nights with visible asleep time enter the average.

Sleep source precedence in Apple's Health UI is not fully documented. Interval union is the closest transparent, defensible calculation, and nightly Debug diagnostics are provided for comparison.

## Build on a personal iPhone

1. Open `WeeklyHealthReport.xcodeproj` in the current stable Xcode.
2. Select the **WeeklyHealthReport** target, then **Signing & Capabilities**.
3. Choose your personal development team and replace the example `com.example.WeeklyHealthReport` bundle identifier with one unique to your team.
4. Confirm the **HealthKit** capability is present. No background delivery or clinical-health-record access is required.
5. Connect and trust the iPhone, enable Developer Mode if prompted, select it as the run destination, then Run.
6. On the new Health permission sheet, enable read access for every listed metric. If the app was installed before new metrics were added, iOS should ask for the additional permissions on the next run.

No App Store distribution configuration is required.

## Validate against Apple Health

Use a Debug build and select **Last 7 Completed Days**. Keep the app and Health on exactly the same dates and local time zone. Open **Developer Diagnostics** from the bottom of the report screen for daily values and exact totals.

1. **Steps:** compare every daily diagnostic value, then calculate the seven-day average from those displayed values.
2. **Weight:** compare the current and previous seven-day daily values, confirming that today's partial day is excluded from the averages while the latest measurement can still be today.
3. **Resting HR and HRV:** compare each valid day's diagnostic value with Health's daily view for both the selected and immediately preceding equivalent periods, then average only those valid days.
4. **Active Energy and Exercise:** compare the exact unrounded diagnostic totals over the selected dates before comparing rounded display values.
5. **Workouts:** compare workout start dates, count, and total duration. A workout crossing midnight is assigned by its start date.
6. **Sleep:** compare each diagnostic night with the Health date on which you woke. Check overlapping third-party or manually entered records if a night differs.
7. Tap **Copy Report**, paste into Notes, and confirm all Weight, RHR and HRV average/trend lines match the screen. Diagnostics must not appear in copied text.

The copied report includes the local date and time at which it was generated, Watch data-day coverage, and each workout type and duration.

Daily Steps totals have been compared successfully with Apple Health on a real iPhone. A one-step difference can still appear in the final displayed average when the two UIs round the same daily inputs differently. Simulator tests validate boundaries, daily-first means, overlap handling, workout totals, duration formatting, and clipboard output but cannot supply representative personal HealthKit data.

Possible legitimate differences include Health data not yet synchronised, limited historical read access, different selected dates, display rounding, workouts crossing a boundary, and Apple's undocumented sleep source precedence. Material discrepancies should be investigated at the daily/nightly diagnostic level rather than hidden by rounding.

## Licence

Licensed under the [MIT License](LICENSE).
