# Weekly Health Report

A small, local-only iPhone utility for producing a trustworthy weekly summary from Apple Health. The first milestone implements Steps only so its HealthKit aggregation can be validated on a real iPhone before any other metric is added.

## Privacy

The app reads HealthKit data on-device. It has no accounts, analytics, network service, cloud storage, database, telemetry, or background synchronization. Health data is not logged or uploaded.

## Current milestone: Steps validated, Weight validation

Steps are read using a daily `HKStatisticsCollectionQueryDescriptor` with `cumulativeSum`. HealthKit merges contributing sources before calculating each statistic. The app never manually sums raw Watch and iPhone samples.

Average Daily Steps is:

```text
sum of visible daily HealthKit totals / number of completed reporting days
```

For Last 7 Completed Days, the denominator is seven. If no daily statistics are visible, the app displays an unavailable state instead of zero. A successful HealthKit authorization request does not reveal whether read access was granted; Apple intentionally makes denied read access indistinguishable from no data.


Weight uses the single most recent body-mass sample visible in the preceding 30 days, regardless of the selected weekly reporting period. It is converted to kilograms and displayed to one decimal place; it is never averaged.

## Reporting periods

All boundaries use the device's local calendar and time zone.

- **Last 7 Completed Days:** local midnight seven calendar days before today through local midnight today.
- **Current Week:** locale-aware week start through local midnight today, excluding the current partial day.
- **Previous Week:** the preceding complete locale-aware calendar week.

Intervals are half-open: the start is included and the end is excluded.

## Build on a personal iPhone

1. Open `WeeklyHealthReport.xcodeproj` in Xcode 26.6 or later.
2. Select the **WeeklyHealthReport** target and choose your personal signing team.
3. Replace `com.example.WeeklyHealthReport` if that bundle identifier is unavailable for your team.
4. Confirm **HealthKit** appears under Signing & Capabilities.
5. Connect and trust your iPhone, select it as the run destination, then build and run.
6. Grant read access to Steps and Weight when iOS presents the Health permission sheet.

No App Store configuration is required.

## Validate against Apple Health

Use the default Last 7 Completed Days period. In a Debug build, compare every date in **Developer diagnostics** with Apple Health's Steps daily view for exactly the same dates. Confirm the local time zone and exclusive query end shown in diagnostics.

Do not proceed to other metrics if daily values differ beyond display rounding. First check date boundaries, Health synchronization, limited historical authorization, and source visibility. The weekly average should then be reproducible directly from the seven displayed daily totals.

This is a personal informational utility, not medical software.
