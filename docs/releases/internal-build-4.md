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

## Build 4 rejection and build 5 repair

Xcode's one internal-only upload attempt rejected build 4 for a missing
`NSHealthUpdateUsageDescription`. App Store Connect's build list still showed only
builds 1 through 3 after the rejection. Build 4 is consumed and will not be retried.
Build 5 adds the purpose string explicitly stating that this version does not
request permission to save or change Health data. Both authorisation call sites
retain empty `toShare` sets; no writer or capability is introduced. The same
operator-approved encryption declaration and single-tester internal audience apply.
