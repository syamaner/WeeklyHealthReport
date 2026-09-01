# Weekly Health Report

A small native iPhone utility that reads selected Apple Health data, produces a weekly summary, and copies it as plain text. It is a personal informational utility, not medical software.

## Screenshot

<img src="docs/images/weekly-health-report-simulator.png" alt="Weekly Health Report running on an iPhone simulator" width="390">

The simulator screenshot uses an invented fixture created only for documentation. It contains no exported or personal HealthKit values. The production app reads real values only when it runs on an authorised iPhone.

## Privacy

All HealthKit reading and aggregation happens on the device. The app has no accounts, analytics, telemetry, network service, backend, database, cloud storage, background sync, or remote transport. The only export is an explicit copy to the iOS clipboard. The repository contains synthetic health fixtures only, not exported HealthKit data.

The app requests read-only access to Steps, Weight, Body Fat Percentage, Waist Circumference, Blood Glucose, VO₂ Max, Oxygen Saturation, Heart Rate, Resting Heart Rate, Heart Rate Variability (SDNN), Apple Exercise Time, Active Energy, Workouts, Sleep Analysis, and, on iOS 26 or later, individually selected Medications. HealthKit intentionally does not reveal whether read permission was denied, so an authorised query with no visible samples is presented as **No data**, never as a misleading zero.

Glucose is read only from HealthKit. The app does not connect to Abbott, Lingo, or any other sensor account and does not upload glucose data. A sensor vendor's app must first write `bloodGlucose` samples into Apple Health.

## Reporting periods

All boundaries use the device's local calendar and time zone. Intervals are half-open: start included, end excluded.

- **Last 7 Completed Days** (default): local midnight seven calendar days before today through local midnight today.
- **Current Week:** locale-aware week start through local midnight today, excluding the current partial day.
- **Previous Week:** the preceding complete locale-aware calendar week.

This is calendar-based, not a rolling 168-hour window, and remains seven days across daylight-saving changes.

## Clipboard output

**Copy Report** places plain text on the clipboard. The report period covers completed days, while the independently selected latest weight and waist measurements may have been recorded today. The following is a synthetic formatting example:

```text
Weekly Health Report
3–9 Feb 2025
Generated: 10 Feb 2025 at 09:41

Latest Weight: 72.4 kg
Weight Recorded: 10 Feb 2025 at 09:11
Weight 7-day Avg: 72.6 kg
Weight Trend: -0.5 kg vs previous 7d
Body Fat: 18.2%
Body Fat 28-day Avg: 18.7%
Body Fat Trend: -0.6 pp vs previous 28d
Waist Circumference: 84.7 cm
Waist Recorded: 8 Feb 2025 at 08:15
Waist 4-week Trend: -1.8 cm vs ~4 weeks earlier
Glucose Daily Average: 5.7 mmol/L
Glucose Observed Range: 3.9–8.6 mmol/L
Glucose Data Coverage: 7 / 7 days
Latest VO₂ Max: 32.1 mL/kg/min (9 Feb 2025 at 08:42)
VO₂ Max — 4 Weeks: 31.8 mL/kg/min (8 days)
VO₂ Max — 3 Months: 30.9 mL/kg/min (24 days)
VO₂ Max — 6 Months: 29.7 mL/kg/min (51 days)
Latest Blood Oxygen: 97% (10 Feb 2025 at 07:21)
Typical Blood Oxygen: 97%
Blood Oxygen Daily Range: 96–98%
Blood Oxygen Data Coverage: 7 / 7 days
Average Daily Steps: 8,432
Resting HR Average: 61 bpm
Resting HR Trend: -2.0 bpm vs previous 7d
HRV Average: 58 ms
HRV Trend: +4.0 ms vs previous 7d
Watch Data Coverage: 6 / 7 days
Average Sleep: 7h 32m
Active Energy: 3,456 kcal
Exercise: 143 min
Workouts: 2
Workout: Cycling — 42m — 05/02/2025 - 18:12
Workout: Yoga — 36m — 08/02/2025 - 09:05
Medication Taken: ExampleMed 20 mg — 1 dose at 9 Feb 2025 at 08:30; 1 taken event
```

## Aggregation semantics

- **Weight:** the latest visible body-mass sample in the preceding 30 days is shown independently. For trend, multiple readings on a day are averaged first; the mean of sampled days in the latest seven completed days is compared with the preceding seven completed days. Each side requires at least three sampled days. The signed difference is reported in kg.
- **Body Fat:** HealthKit percent values are fractional (`0.30` means `30.0%`) and are converted to percentage points at the query boundary. Up to 60 days of visible samples are read. Multiple readings on one calendar day are averaged first, then sampled days receive equal weight. Seven-day and current/previous 28-day averages require at least two sampled days. Trend is the current 28-day daily mean minus the previous 28-day daily mean, in percentage points.
- **Waist Circumference:** the latest visible manual measurement from an eight-week lookback ending at refresh time is displayed in centimetres with its timestamp, independently of the selected weekly period. Sparse measurements are not averaged. For a four-week trend, the app compares it with the visible sample closest to 28 days earlier, but only when that sample is 21–35 days older; otherwise it reports insufficient history. A measurement entered today can therefore appear immediately.
- **Blood Glucose:** HealthKit's daily `discreteAverage`, `discreteMin`, and `discreteMax` statistics are calculated for each complete local calendar day. All source values are converted using HealthKit's blood-glucose molar mass and displayed in mmol/L. The weekly average is the arithmetic mean of valid daily averages, so days with more sensor readings do not dominate. The observed range is the minimum and maximum visible statistic across the period, and coverage reports days with data. No target range, time-in-range score, diagnosis, or medical interpretation is applied.
- **VO₂ Max:** the latest visible estimate and timestamp from the preceding six calendar months are displayed. Multiple estimates on one local calendar day are averaged first, then sampled days receive equal weight in rolling four-week, three-month, and six-month averages ending at refresh time. Each average requires at least three sampled days and reports its sampled-day count. VO₂ max is a discrete Watch estimate, not a clinical exercise test, and no fitness classification or medical interpretation is applied.
- **Blood Oxygen:** the latest visible oxygen-saturation sample from a 30-day lookback is displayed with its timestamp. For the selected completed-day period, all visible discrete samples are converted from HealthKit fractions to percentage points. The median is calculated within each complete day, followed by the median and range of valid daily medians, so days with more background measurements do not dominate and isolated outliers have less influence. Coverage reports valid days. Apple Watch blood-oxygen values are general wellness estimates, not medical measurements.
- **Steps:** one local-calendar-day `HKStatisticsCollectionQueryDescriptor` using `cumulativeSum`. HealthKit resolves contributing sources; raw iPhone and Watch samples are never manually summed. Weekly average is the sum of the daily totals divided by every complete reporting day, normally seven.
- **Resting Heart Rate:** one HealthKit `discreteAverage` statistic per complete calendar day, followed by the arithmetic mean of valid daily values. Days without a visible value are omitted; days with more samples do not receive extra weight. The selected period is compared with the immediately preceding period containing the same number of complete days. A signed bpm trend requires at least three valid days on each side.
- **HRV:** the same daily-first and equivalent-period comparison using `heartRateVariabilitySDNN`, converted to milliseconds. A signed trend requires at least three valid days on each side. It is not a readiness score or medical interpretation.
- **Apple Watch coverage:** the number of complete reporting days containing at least one heart-rate sample whose HealthKit device metadata identifies an Apple Watch. This is evidence of Watch data on a day, not continuous wear time. An empty query is shown as **No data** because it may also mean heart-rate read access was denied.
- **Apple Exercise Time:** one HealthKit `cumulativeSum` statistic over the exact report interval, converted to minutes. Raw samples are not summed manually.
- **Active Energy:** one HealthKit `cumulativeSum` statistic over the exact report interval, converted to kcal. This is an activity metric, not total energy expenditure.
- **Workouts:** `HKWorkout` samples whose start date is within the report interval. The app shows count, summed duration, and each workout's HealthKit activity type, duration, and local start date/time in `dd/MM/yyyy - HH:mm` format. Because missing read visibility is indistinguishable from an empty history, an empty result is shown as **No data** rather than a potentially misleading zero.
- **Sleep:** only `asleepUnspecified`, `asleepCore`, `asleepDeep`, and `asleepREM` samples are included. `awake` and `inBed` are excluded. Included intervals from all sources are clipped and unioned so overlaps are counted once. Each report date is a local noon-to-noon night bucket ending on that wake date; only nights with visible asleep time enter the average.
- **Medications (iOS 26+):** the person chooses individual medications through Apple's per-medication Health access sheet on first use. Existing access is subsequently managed in Health under profile > Apps > WeeklyHealthReport. When a new medication is added, Health offers a WeeklyHealthReport sharing switch on the final add screen. The app queries active and archived authorised concepts, then includes only `HKMedicationDoseEvent` samples whose status is `taken` and whose start time falls inside the selected completed-day period. Events are grouped by HealthKit's exact medication concept, so a changed strength appears as a separate row automatically. Each row reports the latest logged quantity and time plus the number of taken events; Diagnostics lists every event. Medications without a visible taken event are omitted from copied text. Missing events are never interpreted as a missed dose or non-adherence.

Sleep source precedence in Apple's Health UI is not fully documented. Interval union is the closest transparent, defensible calculation, and nightly Debug diagnostics are provided for comparison.

## Build on a personal iPhone

1. Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig`.
2. In the local file, replace `YOUR_TEAM_ID` with your Apple development team ID and use a bundle identifier unique to that team. The local file is ignored by Git.
3. Open `WeeklyHealthReport.xcodeproj` in the current stable Xcode.
4. Select the **WeeklyHealthReport** target, open **Signing & Capabilities**, and confirm the values from the local configuration are shown with the **HealthKit** capability. No background delivery or clinical-health-record access is required.
5. Connect and trust the iPhone, enable Developer Mode if prompted, select it as the run destination, then Run.
6. On the new Health permission sheet, enable read access for every listed metric. If the app was installed before new metrics were added, iOS should ask for the additional permissions on the next run.
7. On iOS 26 or later, select the medications the app may read when the per-medication chooser appears. To change existing access later, open Health, tap your profile picture, then **Apps > WeeklyHealthReport**. When adding a new medication in Health, enable WeeklyHealthReport on the final screen before saving it.

No App Store distribution configuration is required.

## Validate against Apple Health

Use a Debug build and select **Last 7 Completed Days**. Keep the app and Health on exactly the same dates and local time zone. Open **Developer Diagnostics** from the bottom of the report screen for daily values and exact totals.

1. **Steps:** compare every daily diagnostic value, then calculate the seven-day average from those displayed values.
2. **Weight:** compare the current and previous seven-day daily values, confirming that today's partial day is excluded from the averages while the latest measurement can still be today.
3. **Waist:** compare the latest diagnostic measurement and timestamp with Health's Waist Circumference detail. For trend, confirm Diagnostics selected the closest sample to 28 days earlier and that it is 21–35 days older than the latest sample.
4. **Blood Glucose:** first confirm Lingo samples appear in Health. Compare each daily diagnostic average and range with Health for the same complete day, then average the valid daily averages. Allow for vendor-to-Health synchronisation delay.
5. **VO₂ Max:** compare every raw diagnostic estimate and timestamp with Health's Cardio Fitness data. Recalculate the daily means, then compare the four-week, three-month, and six-month windows. Confirm each displayed sampled-day count before comparing rounded averages.
6. **Blood Oxygen:** compare each raw diagnostic value with Health, then independently calculate each completed day's median. Compare the median and range of those daily medians, not Health's raw-sample average or range. The latest value can be from today even though the period summary excludes today.
7. **Resting HR and HRV:** compare each valid day's diagnostic value with Health's daily view for both the selected and immediately preceding equivalent periods, then average only those valid days.
8. **Active Energy and Exercise:** compare the exact unrounded diagnostic totals over the selected dates before comparing rounded display values.
9. **Workouts:** compare workout start dates, count, and total duration. A workout crossing midnight is assigned by its start date.
10. **Sleep:** compare each diagnostic night with the Health date on which you woke. Check overlapping third-party or manually entered records if a night differs.
11. **Medications:** compare every taken-event timestamp in Diagnostics with Health. Confirm an unlogged medicine is absent and a changed strength appears as its own row. Today's event enters the default report only after that day is complete.
12. Tap **Copy Report**, paste into Notes, and confirm the Waist, Glucose, VO₂ Max, Blood Oxygen, Weight, RHR, HRV and medication lines match the screen. Diagnostics must not appear in copied text.

The copied report includes the local date and time at which it was generated, Watch data-day coverage, and each workout type, duration, and local start date/time.

Daily Steps totals have been compared successfully with Apple Health on a real iPhone. A one-step difference can still appear in the final displayed average when the two UIs round the same daily inputs differently. Simulator tests validate boundaries, daily-first means, overlap handling, workout totals, duration formatting, and clipboard output but cannot supply representative personal HealthKit data.

Possible legitimate differences include Health or Lingo data not yet synchronised, limited historical read access, different selected dates, display rounding, workouts crossing a boundary, and Apple's undocumented sleep source precedence. Material discrepancies should be investigated at the daily/nightly diagnostic level rather than hidden by rounding. Glucose sensor values are informational and must not be used by this app to make treatment decisions.

## Licence

Licensed under the [MIT License](LICENSE).
