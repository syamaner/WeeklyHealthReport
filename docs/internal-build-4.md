# Internal build 0.1.1 (4)

This manual internal TestFlight release includes the food-feature delivery through
PR #136. Release identity is the existing App Store Connect app
`com.otherweather.ReportWeeklyHealth`; the primary checkout remains untouched.

On 26 September 2026, App Store Connect showed builds 1 through 3, and the existing
Internal Testing group contained one tester (the operator) with manual Xcode build
distribution. The operator authorised an internal release and declared no
non-exempt encryption. No external group, public link or App Store submission is
authorised. Export must set `testFlightInternalTestingOnly=true`, preserve build 4,
and make at most one upload; an ambiguous upload requires read-only reconciliation.

The existing exact-head food delivery passed 148 package and 262 simulator tests,
static analysis and 13 CI checks. These are not physical capture, HealthKit or
Drive validation. The release metadata change requires its own CI validation.

This does not implement the GitHub release automation proposed in #85.
