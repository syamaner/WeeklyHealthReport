# Synthetic native workout round trip

This optional local harness executes the real reader adapter and selected-day workout query through the Daily JSON builder, serializer and strict Drive identity validator. It is outside the application and normal test targets. It does not upload, read personal Health data, fabricate populated HR/zones, or prove physical Watch/treadmill behaviour.

Use it only after explicit authorisation for a **fresh, dedicated synthetic iOS/watchOS simulator pair**. Keep the pair's creation record and exact UDIDs. Never select a physical device or an existing personal simulator. The producer's separately retained `Tools/NativeHealthRoundTrip` harness compiles the actual Watch writer and saves synthetic cases. Its mirroring no-op and in-process transport are separate from the measured native Watch save → paired-phone Health visibility boundary. Retain both source refs and producer file hashes; do not describe a handwritten metadata fixture as this round trip.

## Prepare independently expected cases

Python 3.12+ and the native SDK that supports these APIs are required (the initial run used Xcode 27 / Swift 6.4). Keep producer outputs, archives and all generated outputs private and outside Git. The producer output directory supplies `CASE.manifest.json`, `CASE.receipt.json` and `CASE.hkworkout`. The legacy directory supplies the same files for `v2-paused` from the unchanged released writer and the same released companion graph.

The declared synthetic quantities and interval fields in `expectations.py` are independent of the producer's metadata builder. Only varying native identities and sent timestamps come from receipts. Each naturally timed safe/rich case requires a separately reviewed `--decision`: inspect exact native collection bounds and pause/resume events against the [shared contract](../../docs/accepted-workout-distance-amendment.md), including the narrow final point-pause exception. Do not obtain the expectation by copying `nativeSampleIncluded` or its reason. The generator checks the measured writer decision against that independent expectation. Never shift timestamps or relax a tolerance to make a safe case pass.

```sh
python3 Tools/WorkoutNativeInterop/expectations.py \
  --producer-output /private/tmp/PRIVATE_PRODUCER_OUTPUT \
  --legacy-output /private/tmp/PRIVATE_LEGACY_OUTPUT \
  --output /private/tmp/FRESH_EXPECTED_INPUTS \
  --decision v3-safe-0=included --decision v3-rich=included \
  v2-paused v3-paused v3-zero v3-incomplete v3-safe-0 v3-rich
```

Supported safe attempts are `v3-safe-0` through `v3-safe-7`. Retain unsuccessful or suppressed attempts too; `pauseOverlap` and `uncertainTemporalCoverage` are distinct expectations. The fixed paused/zero/incomplete cases have predeclared reasons. An included sample must preserve the independently declared quantity in the associated sample, native statistic and accepted aggregate exactly. Suppressed samples must be absent while accepted metadata remains independent. Legacy recovery preserves its associated accepted value separately from the already clipped native statistic; it never rewrites the saved workout.

## Assemble a private source snapshot

```sh
python3 Tools/WorkoutNativeInterop/prepare.py \
  --source-root /PATH/TO/ISOLATED/WeeklyHealthReport \
  --source-ref EXACT_REVIEWED_COMMIT \
  --inputs /private/tmp/FRESH_EXPECTED_INPUTS \
  --phone-udid FRESH_SYNTHETIC_PHONE_UUID \
  --output /private/tmp/FRESH_CONSUMER_CHECKOUT --synthetic-only
```

`--working-tree` may replace `--source-ref` only when intentionally validating the scoped uncommitted isolated checkout. It copies nonignored tracked/untracked files and retains the exact diff and file hashes; it is not evidence of a committed source. Review the manifest before running. Assembly requires an absent destination, copies native archives only into that private snapshot, adds test resources only in the snapshot, and records source/helper/input/assembled-file digests in `source-inputs.json`. A unique assembly ID and a digest of the frozen source/input identity are embedded in the compiled diagnostics and phone visibility records. Neither application source nor repository project membership is edited by the assembler.

Both native entrypoints require the selected simulator UUID. The phone path authorises only read access to workout, heart rate, active energy and walking/running distance (`toShare` is empty), queries an exact synthetic UUID, then invokes the actual `HealthKitClient.fetchWorkouts` for that single synthetic window with recovery enabled and disabled. The archive path uses the real projection/recovery adapter against the same synthetic store. Query timeout/error/missing UUID fails after retaining diagnostics. Do not bypass native permission prompts; leave them for the authorised operator.

```sh
cd /private/tmp/FRESH_CONSUMER_CHECKOUT
xcodebuild test -project WeeklyHealthReport.xcodeproj -scheme WeeklyHealthReport \
  -destination 'platform=iOS Simulator,id=FRESH_SYNTHETIC_PHONE_UUID' \
  -derivedDataPath /private/tmp/FRESH_NATIVE_DERIVED \
  -xcconfig /PATH/TO/REPO/Tools/WorkoutNativeInterop/simulator-signing.xcconfig \
  -parallel-testing-enabled NO \
  -only-testing:WeeklyHealthReportTests/DailyHealthExportTests/testJoinedFreshPhoneStoreReadback \
  -only-testing:WeeklyHealthReportTests/DailyHealthExportTests/testJoinedProducerNativeArchivesToCanonicalDailyJSON \
  -resultBundlePath /private/tmp/FRESH_NATIVE_RESULT.xcresult
```

The local ad-hoc simulator signing configuration is required for native HealthKit capability; it has no developer credentials and must not be used for a device/archive. A separately selected `testJoinedMissingSyntheticUUIDIsAFailure` is a deliberately failing control, never part of the passing acceptance suite.

## Retain and assess evidence

Read only this dedicated app container's `Documents/JoinedOutput` after the run. Retain the result bundle/log, source manifest, descriptors, source refs, producer input manifests/receipts, native archives, phone visibility/sample diagnostics and canonical JSON. Hash the retained copies in a new private directory. Do not overwrite earlier failed/negative evidence.

The app container can retain files from earlier runs. Count **only cases in the exact current `scenarios.json`**, not every file in the directory. For each case, require one requested native UUID, successful direct and archive assertions, strict identity validation, declared field count, and byte-identical direct/archive canonical JSON. Link input and output hashes explicitly. `phone-store-visibility.json` records actual selected-day fetch completion, source, associated sample identity/version/quantity and enabled/disabled recovery results. An empty query is not evidence of denied access; an absent record is a failed integration probe.

The native assertions compare exported numbers to SDK values exactly. Dates must equal the exact canonical millisecond projection. Raw namespaced metadata, food payloads and reboxed metadata are forbidden in this native acceptance path. Positive populated HR/zone coverage requires actual corresponding synthetic/native evidence; absence is preserved rather than invented zero. Strict source/identity/enum/schema/precision tests remain in the normal app test suite.

This harness is a reproducible local validation tool, not a release gate bypass. Run the normal focused/full/analysis gates, independent exact-source review and protected CI for implementation changes. Public receipts contain only synthetic aggregate outcomes and immutable source links; keep native archives, signing details and any personal values out of Git.

`collect.py` automates the exact-case retention checks without locating or querying any Health store:

```sh
python3 Tools/WorkoutNativeInterop/collect.py \
  --assembled /private/tmp/FRESH_CONSUMER_CHECKOUT \
  --documents-output /EXACT/SYNTHETIC/APP/CONTAINER/Documents/JoinedOutput \
  --log /private/tmp/FRESH_NATIVE_RUN.log \
  --xcresult /private/tmp/FRESH_NATIVE_RESULT.xcresult \
  --output /private/tmp/FRESH_IMMUTABLE_EVIDENCE
```

It verifies every frozen source/helper/input and assembled file hash, the compiled assembly ID/source-input digest in every current-case diagnostic, and byte equality, then retains the assembled snapshot, inputs, selected outputs, log/result bundle, index and SHA-256 manifest. It requires exactly the two named native test methods to pass on the declared simulator; zero tests, skipped/failed tests and the wrong destination are rejected. Independently inspect the retained `xcresult` summary too.
