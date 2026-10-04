# Workout reader acceptance — issue 80

Software scope is [the shared interval contract](workout-interval-enrichment-contract.md) and [the versioned accepted-distance amendment](accepted-workout-distance-amendment.md). Producer dependency is [PacePrompt #233](https://github.com/syamaner/paceprompt-ios/issues/233); final signed-device acceptance remains [#116](https://github.com/syamaner/paceprompt-ios/issues/116).

## Sources and compatibility

The reader uses existing materialized [workout statistics](https://developer.apple.com/documentation/healthkit/hkworkout/statistics(for:)) and [activity statistics](https://developer.apple.com/documentation/healthkit/hkworkoutactivity/statistics(for:)). Native [workout zones](https://developer.apple.com/documentation/healthkit/hkworkoutzonegroup) use the iOS 27 SDK API, gated by compiler >=6.4 and OS availability. The installed Xcode 27 interface confirms `zoneGroup(for:)`, `configuration.source`, and `zoneDurations`. Earlier SDK/OS combinations produce unsupported; missing visible zones produce noDataOrAccess. Time in zones is HealthKit data, not medical classification or an estimate from summary HR.

Shared v1 fixtures originate unchanged from PacePrompt a6809ec983ec8d06a491f26975ef6ec90b4f856d. Shared v2 fixtures are the producer #233 extension. SHA256SUMS beside each bundle records exact bytes. Public fixture values are invented. The zero-prefix fixture means no stored workout and cannot be exported as a successful complete workout.

## Separately authorised device round trip

1. Record exact compatible phone, Watch and reader builds and OS versions. A mixed v1-only receiver/v2 sender is not acceptance.
2. Use the producer runbook for a supervised workout with a normal step, manual speed change, inclination change and pause/resume. Console/safety-key authority is unchanged.
3. Confirm one saved Watch-owned workout, HealthKit activity start/end and pause-adjusted duration. Retain programme segment identity across executed sub-intervals; gaps remain gaps.
4. In the reader, request read access through the existing explicit flow (including walking/running distance), choose the reporting day and prepare the Daily JSON preview. Compare exact JSON locally with HealthKit/Apple Health. Do not publish personal diagnostics or screenshots in GitHub.
5. Check independent HR minimum/average/maximum and estimated active energy at workout/activity level. Missing values are noDataOrAccess, never invented zero or a claim of denial. A real reported zero is retained distinctly from absence, including HR and energy; the reader does not apply physiological interpretation. Do not force activity sums to equal the workout total; interpolation and coverage can differ.
6. Compare `accepted_distance` independently from native `distance_metres` and activity observation windows. A recovered legacy total can be 100 m while the unchanged gated native statistic is 57.09 m; the reader does not rewrite Health records. For new v3 paused workouts, accepted distance can remain 100 m while the unsafe native sample is omitted: Apple Health/Fitness may therefore lack native distance. This repair does not claim to change Apple Health’s displayed total. Actual distance endpoints must be within the interval, delta exact and provenance recognised. Partial endpoints must say partialObservationWindow. Reset/uncertain windows stay unavailable; v1 intervals remain unavailable.
7. On supported OS, compare native zone durations, source and optional first/last BPM boundaries. If absent, preserve noDataOrAccess; on older OS preserve unsupported. No invented thresholds.
8. Verify complete, incomplete and unsupported/invalid reader states using retained synthetic fixtures for malformed cases; do not corrupt real Health data. Complete means validated interval mirror only.
9. Review privacy disclosure and exact JSON before any separately authorised Drive export. Verify selected historical date, offset/DST timestamp, canonical replacement/recovery and no food payload. Test identity failures with the synthetic Drive harness, not personal data.

## Numeric metadata compatibility

The HealthKit adapter treats an `NSNumber` as an integer only when `Int(exactly:)` succeeds, after excluding Boolean and nonfinite values. This admits whole-valued floating or decimal representations without rounding fractions, truncating out-of-range values or coercing strings. Other finite numeric values retain their exact `Decimal` projection. The pure reader's version, ownership, identity, count, timestamp, enum and completeness rules remain unchanged, as do schema6 and the exported metadata allowlist.

A device export with `recognition: invalid` and no exported interchange version narrows the failure to the version's type projection: a missing version key would be unsupported, while a later validation failure would retain a parsed version. The raw live metadata representation is not present in the export, so a Health-store conversion to floating representation is not a proven cause. Synthetic native workout/activity secure-archive cases reproduce the earlier failure for a whole-valued floating `NSNumber`; they test adapter compatibility, not Health-store persistence.

Acceptance uses the **same existing saved workout** with the repaired reader. Prepare a fresh Daily JSON preview and locally compare recognition, version, interval identity, targets, timestamps, statistics and available distance evidence. Retain unsupported, incomplete or unavailable states when the underlying evidence requires them. A new workout or Health write is not needed for this comparison, and successful numeric decoding alone does not establish the later metadata invariants or the full device round trip.

## Release boundary

Pure tests, simulator compilation and static analysis do not establish native persistence by themselves. Separately authorised synthetic Health-store round trips establish only their measured simulator save/sync/read boundaries; physical-device metadata survival, populated zone visibility, sensor accuracy, calorimetry, distance accuracy and physical treadmill behaviour remain separate. Signed release, App Store privacy/compliance review and real Health/Drive comparison remain distinct acceptance evidence. No real Health read or external export is part of automated validation.

## Software validation receipt

On 4 October 2026, Xcode 27 / Swift 6.4 built the frozen implementation against the iOS 27 SDK. The dedicated iOS 26.5 simulator passed all **308 tests**, including the 112 focused workout/export/Drive cases. The existing coverage gate passed at **97.27%** for models, formatting and presentation (95% minimum). Xcode static analysis succeeded. Independent read-only review findings were resolved; a subsequent bounded admission review reported no remaining P1/P2 finding.

V1/v2 fixture digests matched the producer's five shared files. Separate Foundation-only checks confirmed malformed revision/count metadata is classified invalid and omitted without blocking basic-workout export. All 79 Swift/project inputs were hashed before the complete gate and checked unchanged afterwards. The full result bundle, coverage summary and input hash manifest are retained locally for the parent delivery handoff; none contains personal Health reads.

A separate in-memory SDK adapter test also passed on the dedicated iOS 27 simulator. It exercised the native `zoneGroup(for:)` path and preserved noDataOrAccess for absent zones, without a Health store query; populated personal zone visibility remains a device acceptance check.

These checks do not complete the signed-device or real Health/Drive steps above.

## Native simulator interoperability evidence and new repair gate

The original numeric repair was exercised with the unchanged real Watch writer, native save/query, paired iPhone Health query and the actual reader/JSON serializer on isolated synthetic-only simulators. HealthKit naturally returned the integer schema metadata as a whole-valued floating NSNumber; the old reader failed and repaired reader passed on the same native archive. Six original cases preserved metadata/statistics through direct and archived paths. No positive HR samples or zones were injected; their populated coverage remains synthetic DTO testing or later supervised device acceptance.

Those same probes exposed a distinct distance bug: a persisted 100 m sample spanning a native pause produced a 57.091177886041649 m workout statistic. The reader preserved it exactly. The approved Wire3/Health3 repair now carries the accepted aggregate independently and omits unsafe native samples. Daily7/enrichment2 preserves the old native field semantics; Daily6 remains readable and unchanged. Old Health1/2 totals can be recovered only from one exact associated trusted-source/sync/version/bounds-matched quantity; recovered evidence describes its persisted Double value, not unrecorded pre-conversion precision.

The selected-day enriched export path alone enables legacy recovery. Weekly/context count/duration paths and non-enriched exports issue no recovery query. Empty visibility is noDataOrAccess; query errors and cancellation block export. The new production path must pass the paired native legacy recovery and v3 acceptance matrix, focused contracts, full simulator/analysis gates and exact-source protected delivery before a new signed build is released. Build20 is retained as superseded and never uploaded; its earlier signature, policy and CI evidence is not reused as validation of this repair.

The legacy query combines Apple’s [workout association predicate](https://developer.apple.com/documentation/healthkit/hkquery/predicateforobjects(from:)-5irg9) with its [metadata allowed-values predicate](https://developer.apple.com/documentation/healthkit/hkquery/predicateforobjects(withmetadatakey:allowedvalues:)). Association and exact sync identity are both required; a matching timestamp or quantity alone never establishes identity.

The repaired native run has now verified the same legacy saved workout through `HealthKitClient.fetchWorkouts`: the enabled selected-day path recovered the sole associated 100 m sample while preserving the native 57.80511489100649 m statistic exactly. The disabled path retained unavailable accepted distance. New v3 paused and observed-zero cases exported accepted 100 m and 0 m respectively, with no associated native distance samples. Each passed the direct paired-phone query and secure-archive path, canonical Daily7 serialization and strict Drive identity validation. Native numeric assertions use exact Double equality; no metadata reboxing is permitted in these acceptance paths. The released companion graph reported the exact phone bundle as both workout and sample source, so the reviewed source policy permits that measured alias while retaining exact sample/workout source equality. This remains synthetic simulator evidence.

The bound native harness has also checked incomplete, naturally safe and fractional cases through both transports:

| Synthetic case | Accepted distance | Native distance | Interval evidence |
| --- | --- | --- | --- |
| Legacy paused | Recovered 100 m | Unchanged 57.80511489100649 m | 30 m and 70 m |
| Health3 paused | 100 m | Absent; pauseOverlap | 30 m and 70 m |
| Observed zero | 0 m | Absent; zeroAggregate | Observed 0 m |
| Incomplete deadline | Unavailable; notAccepted | Absent | Observed 10 m remains independent |
| Naturally safe sample | 10 m | Exactly 10 m | 10 m |
| Fractional targets and gap | 30.625 m | Exactly 30.625 m | Partial 12.375 m; second interval unavailable |
| Uncertain strict start bounds | 10 m | Absent; uncertainTemporalCoverage | 10 m |

The durable [native interoperability runbook](../Tools/WorkoutNativeInterop/README.md) retains the consumer assembler, independent declarations, native assertions and evidence collector outside application/test targets. Compiled assembly IDs and source/input digests bind diagnostics to their exact snapshot; collection rechecks all hashes and rejects stale or modified inputs. The negative controls rejected old outputs for the same UUIDs and a modified source file. Both sides independently declare the same 13 supported synthetic case identities. Native archives and output records remain private.

The accepted-distance implementation passed 134 focused tests, then all **334 complete simulator tests**, the **96.93%** domain coverage gate and Xcode static analysis. All 83 application/test/project/policy input hashes remained unchanged. One earlier focused run's terminated test process and the unchanged successful recheck are retained; the full gate passed without a retry. The standalone harness separately passed Python compilation, exact-ref snapshot comparison and actual generated native execution; the application's full suite is not claimed as coverage of these separate tools. Independent source and harness review found no remaining P1/P2 issue after the evidence-binding correction.

Eight naturally timed safe-sample attempts were retained without shifting timestamps: three included the exact 10 m sample; five suppressed it because the rounded start did not satisfy the strict native collection bound. None isolated a final-only sub-millisecond pause overlap with otherwise valid bounds. That precise boundary remains covered by deterministic producer policy tests and the shared synthetic fixture, not by a claimed successful native reproduction. The native run did independently verify a genuine mid-workout pause suppression and the permitted post-collection final point-pause case. No further attempts were made after the bounded eight.

Final consolidation executed **13 native cases** through both the direct paired-phone query and archive paths: **728 independently declared fields per transport**, 13 byte-identical canonical JSON pairs and strict Drive identity validation for all 26 payloads. Both named native test methods passed with zero failures/skips on the dedicated iOS 27 simulator. Collection verified source/input assembly binding, actual file hashes, method identities and destination. An earlier wrong-checkout invocation executed zero tests and is explicitly excluded; the collector's negative control rejects that result. The final private snapshot retains 949 hashed files and its exact case index. The eight-attempt limitation above remains unchanged.
