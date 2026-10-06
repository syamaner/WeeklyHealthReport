# Workout interval enrichment contract — 4 October 2026

Authority: the user requested interval-based reporting, retaining planned intervals and creating executed sub-intervals for confirmed speed/inclination changes, then authorised autonomous delivery in isolated worktrees. This is software delivery; signed release and supervised device/Health/Drive acceptance remain separate checkpoints.

## Architecture gate

PacePrompt's pure execution domain owns observed interval distance and identity. Its orchestrator captures existing validated treadmill observations; the Watch projection and versioned wire carry immutable closed intervals. The Watch adapter writes only recognized metadata and the existing single workout distance sample. No new treadmill commands, timers, automatic reconnect or control policies.

WeeklyHealthReport's HealthKit adapter converts SDK values and recognized typed metadata to plain values. A pure decoder validates the entire recognized mirror and projects versioned workout enrichment. The existing export service owns one coherent snapshot; the existing Drive identity policy owns version admission, reviewed exact bytes and historical ordering. Views disclose included data. SDK types never cross the data-provider/domain boundary. Real and fake adapters exercise the same projection contract.

## Rows and values

Retain existing planned segmentIndex and executed intervalIndex. Confirmed speed/inclination changes, programme transitions and pause/resume retain existing splitting semantics. Never reset the planned clock, merge across a gap or fabricate ramp settings. Keep workout/activity start/end, pause-adjusted HealthKit duration, prescribed settings, independent effective settings/sources, settled observed settings/time, and end reason.

HR minimum/average/maximum and active energy come from materialized HKWorkout/HKWorkoutActivity statistics in bpm/kcal. Energy is a HealthKit estimate for the named interval, finalized after saving, not an instantaneous reading. Keep the independent whole-workout energy total; never label the sum of interval energy as the whole-workout total. No raw sample query fan-out or clinical interpretation.

## Distance producer extension

Watch-owned local summaries advance from schema 3 to 4; schemas 1/2/3 retain their meaning. Each new closed interval has intervalDistance with schemaVersion 1, state unavailable or observed, and reason for unavailable. Observed form contains startCumulativeMetres, endCumulativeMetres, startObservedAt, endObservedAt, metres and provenance fr30zCumulativeDistanceDelta. Values are finite nonnegative decimals, endpoints monotonically ordered within the executed interval, end time strictly after start time, and metres equals end minus start exactly. Zero is valid. Endpoint times are actual received observation times, never relabelled to the interval boundaries. A partial observation window is explicitly partial; only exact endpoint coverage may be called the complete interval distance. No speed-times-duration or workout-total allocation.

Retain first/last usable distance observation for the open interval. Include a closing observation only when its actual time belongs to that interval. Missing/reset/regressing/epoch-uncertain data makes affected interval distance unavailable. Closed interval payloads never change. Keep the existing whole-workout distance policy and source exclusion unchanged.

Wire schema 1 remains readable and byte-stable for original fixtures. New manifests with intervalDistance use schema 2; v2 requires the field on every interval. Existing control messages remain v1; upgraded peers accept both manifest versions, while old peers reject v2 without phone-save fallback. Mixed-version devices cannot establish acceptance. Saved workout interchangeSchemaVersion is 2 when its interval projection contains v2 enrichment; activity timelineSchemaVersion stays 1 and separate intervalDistanceSchemaVersion is 1. New namespaced activity keys: intervalDistanceSchemaVersion, intervalDistanceState; for observed: intervalDistanceMetres, intervalDistanceStartCumulativeMetres, intervalDistanceEndCumulativeMetres, intervalDistanceStartObservedAt, intervalDistanceEndObservedAt, intervalDistanceProvenance; for unavailable: intervalDistanceReason. Do not add per-activity HealthKit distance quantity samples or interpolate the workout aggregate.

Keep existing 64-interval, 32768-byte message and rolling send limits. Test limit/oversize failure and retained incomplete prefix; never truncate silently or claim complete when transport limits prevent delivery. Complete interchange describes a validated interval mirror, not complete physiological coverage.

## Reader/export

Read v1 and v2 recognized Watch metadata, validate identity, types, supported enums, chronological nonoverlapping bounds, unique segment/interval identity, count and ownership. States are notPacePrompt, supportedComplete, supportedIncomplete, unsupported, invalid. Retain basic workouts and visible statistics for all states. Historical iPhone metadata is not Watch ownership. Malformed recognized data cannot upgrade to complete. V1 has no interval distance; show unavailable, not zero.

Daily schema 6 is assigned to workout enrichment. Existing v3 normal exports and v4 canonical-food projections keep their meanings; v5 remains reserved by the separately proposed food-write plan. The initial runtime export emitted v6 with workout enrichmentVersion 1; current v7/enrichmentVersion 2 is defined by the accepted-distance correction below. Golden v3/v4 regression fixtures remain. Preserve reporting-time-zone offset timestamp encoding, half-open selected-day membership, historic selected days and independent daily aggregates. Update cross-repository references that previously reserved v4 for workouts.

Drive admits the reviewed v6 workout envelope with the same exact-byte validation and historical-v2 cutoff/encoding-time ordering. It must still reject food payloads and standalone v4 until their separate transport scope is authorised; do not enable food transport via a broadened schema range. Preserve v1-v3 recovery, future-version rejection, canonical identity, cancellation and no-partial-publication behaviour.

Heart-rate zones are optional native HealthKit zone durations and boundaries/source on SDK/OS 27+. Guard both compiler/SDK and runtime availability. Older builds/OS expose unsupported; absent visible zones expose noDataOrAccess. Never invent thresholds, derive zones from min/max/average, or claim raw-series export. Include available/missing zone states and source (system/user/app), bpm bounds and seconds.

Add only distanceWalkingRunning to existing user-initiated read authorization where necessary; keep toShare empty. Export preview/privacy text discloses workout HR, estimated energy, distance, recognized intervals and optional zones. No automatic or real export is authorised by software tests.

## Verification and delivery

Use shared synthetic complete/incomplete/zero-prefix v1 files unchanged, plus v2 valid/partial/reset/malformed/unsupported cases. Prove serialization, metadata mapping, retention/recovery, v1 history, idempotency, single writer, bounds, partial visibility, no raw-sample fan-out, coherent snapshots, cancellation, Drive admission and historical ordering. Focused tests first; then complete repository gates after executable content freezes. #116 remains the final signed-device producer/HealthKit/reader round trip; release availability is not acceptance.

## Versioned accepted-distance correction

The [approved aggregate-distance amendment](accepted-workout-distance-amendment.md) supersedes the original single native-distance assumption for new Wire3/Health3 and Daily7/enrichment2. Historical Wire1/2, Health1/2 and Daily6 retain their meanings. The reader performs only the explicitly bounded legacy associated-distance recovery described there; raw HR sample queries remain excluded.

## Schema 8 amendment: individual heart-rate readings

The versioned [heart-rate readings contract](workout-heart-rate-readings-contract.md) adds enrichment version 3 and individual associated quantity-series readings. Earlier versions retain their original exclusions and byte representation. Schema 8 native timestamps use reference-epoch seconds to preserve sub-millisecond interval boundaries; report timestamps remain text.
