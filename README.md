# Weekly Health Report

A small native iPhone utility that reads selected Apple Health data, produces a weekly summary, and copies it as plain text. It is a personal informational utility, not medical software.

## Privacy

All HealthKit reading and aggregation happens on the device. The app has no accounts, analytics, telemetry, network service, backend, database, cloud storage, background sync, or remote transport. The only export is an explicit copy to the iOS clipboard.

The app requests read-only access to Steps, Weight, Body Fat Percentage, BMI, Resting Heart Rate, Heart Rate Variability (SDNN), Apple Exercise Time, Active Energy, Workouts, and Sleep Analysis. HealthKit intentionally does not reveal whether read permission was denied, so an authorised query with no visible samples is presented as **No data**, never as a misleading zero.

## Reporting periods

All boundaries use the device's local calendar and time zone. Intervals are half-open: start included, end excluded.

- **Last 7 Completed Days** (default): local midnight seven calendar days before today through local midnight today.
- **Current Week:** locale-aware week start through local midnight today, excluding the current partial day.
- **Previous Week:** the preceding complete locale-aware calendar week.

This is calendar-based, not a rolling 168-hour window, and remains seven days across daylight-saving changes.

## Aggregation semantics

- **Weight:** the latest visible body-mass sample in the preceding 30 days, converted to kg. It is not averaged and need not be inside the report period.
- **BMI:** the latest visible BMI sample in the preceding 30 days. It is context only and is not used to infer body composition.
- **Body Fat:** up to 60 days of visible samples. Multiple readings on one calendar day are averaged first, then sampled days receive equal weight. Seven-day and current/previous 28-day averages require at least two sampled days. Trend is the current 28-day daily mean minus the previous 28-day daily mean, in percentage points.
- **Steps:** one local-calendar-day `HKStatisticsCollectionQueryDescriptor` using `cumulativeSum`. HealthKit resolves contributing sources; raw iPhone and Watch samples are never manually summed. Weekly average is the sum of the daily totals divided by every complete reporting day, normally seven.
- **Resting Heart Rate:** one HealthKit `discreteAverage` statistic per complete calendar day, followed by the arithmetic mean of valid daily values. Days without a visible value are omitted; days with more samples do not receive extra weight.
- **HRV:** the same daily-first rule using `heartRateVariabilitySDNN`, converted to milliseconds. It is not a readiness score or medical interpretation.
- **Apple Exercise Time:** one HealthKit `cumulativeSum` statistic over the exact report interval, converted to minutes. Raw samples are not summed manually.
- **Active Energy:** one HealthKit `cumulativeSum` statistic over the exact report interval, converted to kcal. This is an activity metric, not total energy expenditure.
- **Workouts:** `HKWorkout` samples whose start date is within the report interval. The app shows count and summed workout duration. Because missing read visibility is indistinguishable from an empty history, an empty result is shown as **No data** rather than a potentially misleading zero.
- **Sleep:** only `asleepUnspecified`, `asleepCore`, `asleepDeep`, and `asleepREM` samples are included. `awake` and `inBed` are excluded. Included intervals from all sources are clipped and unioned so overlaps are counted once. Each report date is a local noon-to-noon night bucket ending on that wake date; only nights with visible asleep time enter the average.

Sleep source precedence in Apple's Health UI is not fully documented. Interval union is the closest transparent, defensible calculation, and nightly Debug diagnostics are provided for comparison.

## Build on a personal iPhone

1. Open `WeeklyHealthReport.xcodeproj` in the current stable Xcode.
2. Select the **WeeklyHealthReport** target, then **Signing & Capabilities**.
3. Choose your personal development team and change `com.example.WeeklyHealthReport` if it is unavailable to that team.
4. Confirm the **HealthKit** capability is present. No background delivery or clinical-health-record access is required.
5. Connect and trust the iPhone, enable Developer Mode if prompted, select it as the run destination, then Run.
6. On the new Health permission sheet, enable read access for every listed metric. If the app was installed before new metrics were added, iOS should ask for the additional permissions on the next run.

No App Store distribution configuration is required.

## Validate against Apple Health

Use a Debug build and select **Last 7 Completed Days**. Keep the app and Health on exactly the same dates and local time zone.

1. **Steps:** compare every daily diagnostic value, then calculate the seven-day average from those displayed values.
2. **Resting HR and HRV:** compare each valid day's diagnostic value with Health's daily view, then average only those valid days.
3. **Active Energy and Exercise:** compare the exact unrounded diagnostic totals over the selected dates before comparing rounded display values.
4. **Workouts:** compare workout start dates, count, and total duration. A workout crossing midnight is assigned by its start date.
5. **Sleep:** compare each diagnostic night with the Health date on which you woke. Check overlapping third-party or manually entered records if a night differs.
6. Tap **Copy Report**, paste into Notes, and confirm the period and visible values match the screen. Diagnostics must not appear in copied text.


Possible legitimate differences include Health data not yet synchronised, limited historical read access, different selected dates, display rounding, workouts crossing a boundary, and Apple's undocumented sleep source precedence. Material discrepancies should be investigated at the daily/nightly diagnostic level rather than hidden by rounding.
