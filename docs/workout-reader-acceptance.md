# Workout reader acceptance — issue 80

Software scope is [the shared interval contract](workout-interval-enrichment-contract.md). Producer dependency is [PacePrompt #233](https://github.com/syamaner/paceprompt-ios/issues/233); final signed-device acceptance remains [#116](https://github.com/syamaner/paceprompt-ios/issues/116).

## Sources and compatibility

The reader uses existing materialized [workout statistics](https://developer.apple.com/documentation/healthkit/hkworkout/statistics(for:)) and [activity statistics](https://developer.apple.com/documentation/healthkit/hkworkoutactivity/statistics(for:)). Native [workout zones](https://developer.apple.com/documentation/healthkit/hkworkoutzonegroup) use the iOS 27 SDK API, gated by compiler >=6.4 and OS availability. The installed Xcode 27 interface confirms `zoneGroup(for:)`, `configuration.source`, and `zoneDurations`. Earlier SDK/OS combinations produce unsupported; missing visible zones produce noDataOrAccess. Time in zones is HealthKit data, not medical classification or an estimate from summary HR.

Shared v1 fixtures originate unchanged from PacePrompt a6809ec983ec8d06a491f26975ef6ec90b4f856d. Shared v2 fixtures are the producer #233 extension. SHA256SUMS beside each bundle records exact bytes. Public fixture values are invented. The zero-prefix fixture means no stored workout and cannot be exported as a successful complete workout.

## Separately authorised device round trip

1. Record exact compatible phone, Watch and reader builds and OS versions. A mixed v1-only receiver/v2 sender is not acceptance.
2. Use the producer runbook for a supervised workout with a normal step, manual speed change, inclination change and pause/resume. Console/safety-key authority is unchanged.
3. Confirm one saved Watch-owned workout, HealthKit activity start/end and pause-adjusted duration. Retain programme segment identity across executed sub-intervals; gaps remain gaps.
4. In the reader, request read access through the existing explicit flow (including walking/running distance), choose the reporting day and prepare the Daily JSON preview. Compare exact JSON locally with HealthKit/Apple Health. Do not publish personal diagnostics or screenshots in GitHub.
5. Check independent HR minimum/average/maximum and estimated active energy at workout/activity level. Missing values are noDataOrAccess, never invented zero or a claim of denial. A real reported zero is retained distinctly from absence, including HR and energy; the reader does not apply physiological interpretation. Do not force activity sums to equal the workout total; interpolation and coverage can differ.
6. Check accepted workout distance separately from activity observation windows. Actual distance endpoints must be within the interval, delta exact and provenance recognised. Partial endpoints must say partialObservationWindow. Reset/uncertain windows stay unavailable; v1 intervals remain unavailable.
7. On supported OS, compare native zone durations, source and optional first/last BPM boundaries. If absent, preserve noDataOrAccess; on older OS preserve unsupported. No invented thresholds.
8. Verify complete, incomplete and unsupported/invalid reader states using retained synthetic fixtures for malformed cases; do not corrupt real Health data. Complete means validated interval mirror only.
9. Review privacy disclosure and exact JSON before any separately authorised Drive export. Verify selected historical date, offset/DST timestamp, canonical replacement/recovery and no food payload. Test identity failures with the synthetic Drive harness, not personal data.

## Numeric metadata compatibility

The HealthKit adapter treats an `NSNumber` as an integer only when `Int(exactly:)` succeeds, after excluding Boolean and nonfinite values. This admits whole-valued floating or decimal representations without rounding fractions, truncating out-of-range values or coercing strings. Other finite numeric values retain their exact `Decimal` projection. The pure reader's version, ownership, identity, count, timestamp, enum and completeness rules remain unchanged, as do schema6 and the exported metadata allowlist.

A device export with `recognition: invalid` and no exported interchange version narrows the failure to the version's type projection: a missing version key would be unsupported, while a later validation failure would retain a parsed version. The raw live metadata representation is not present in the export, so a Health-store conversion to floating representation is not a proven cause. Synthetic native workout/activity secure-archive cases reproduce the earlier failure for a whole-valued floating `NSNumber`; they test adapter compatibility, not Health-store persistence.

Acceptance uses the **same existing saved workout** with the repaired reader. Prepare a fresh Daily JSON preview and locally compare recognition, version, interval identity, targets, timestamps, statistics and available distance evidence. Retain unsupported, incomplete or unavailable states when the underlying evidence requires them. A new workout or Health write is not needed for this comparison, and successful numeric decoding alone does not establish the later metadata invariants or the full device round trip.

## Release boundary

Software tests, simulator compilation and static analysis do not establish HealthKit metadata survival, native zone visibility, sensor accuracy, calorimetry, distance accuracy or physical treadmill behaviour. Signed release, App Store privacy/compliance review and real Health/Drive comparison remain distinct acceptance evidence. No real Health read or external export is part of automated validation.

## Software validation receipt

On 4 October 2026, Xcode 27 / Swift 6.4 built the frozen implementation against the iOS 27 SDK. The dedicated iOS 26.5 simulator passed all **308 tests**, including the 112 focused workout/export/Drive cases. The existing coverage gate passed at **97.27%** for models, formatting and presentation (95% minimum). Xcode static analysis succeeded. Independent read-only review findings were resolved; a subsequent bounded admission review reported no remaining P1/P2 finding.

V1/v2 fixture digests matched the producer's five shared files. Separate Foundation-only checks confirmed malformed revision/count metadata is classified invalid and omitted without blocking basic-workout export. All 79 Swift/project inputs were hashed before the complete gate and checked unchanged afterwards. The full result bundle, coverage summary and input hash manifest are retained locally for the parent delivery handoff; none contains personal Health reads.

A separate in-memory SDK adapter test also passed on the dedicated iOS 27 simulator. It exercised the native `zoneGroup(for:)` path and preserved noDataOrAccess for absent zones, without a Health store query; populated personal zone visibility remains a device acceptance check.

These checks do not complete the signed-device or real Health/Drive steps above.
