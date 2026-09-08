# CI static analysis and coverage

The iOS workflow runs Xcode static analysis as a required step, collects line
coverage during the unsigned simulator test run, writes a layer-aware table to
the GitHub Actions job summary and retains the `xcresult` plus Markdown summary
as a normal workflow artifact for 14 days. It also sends app-target coverage to
Codecov for hosted history, source-line navigation and pull-request visibility.

Both analysis and tests set `CODE_SIGNING_ALLOWED=NO`. Coverage therefore needs
neither signing nor HealthKit permission, and it never reads personal health
data. This remains simulator evidence rather than physical-device or live
HealthKit validation.

## Coverage layers and gate

The summary reports executable-line coverage for:

- the complete `WeeklyHealthReport.app` target;
- pure domain code under `WeeklyHealthReport/Models` and formatting under
  `WeeklyHealthReport/Utilities`;
- report orchestration in `WeeklyReportViewModel.swift`; and
- the framework-bound `HealthKitClient.swift`.

Only the pure models-and-formatting layer has a regression gate, with a
conservative minimum of 95.0%. App-wide, view-model and HealthKit-client values
remain informational. That avoids equating SwiftUI-generated executable lines
or code that requires Apple frameworks with directly testable domain logic.

Codecov's project and patch statuses are also explicitly informational in
`codecov.yml`; they do not replace or broaden the repository-owned 95.0% gate.
The Codecov action fails CI for local generation or transport errors. Codecov
processes accepted uploads asynchronously, so its hosted result must still be
checked independently when reviewing a pull request.

The summariser fails closed if the app target or a named layer disappears from
Xcode's coverage report. Its standard-library unit tests also run before Xcode
analysis and testing.

## Codecov disclosure boundary

The pinned Codecov action runs only after the local coverage gate passes. Its
Xcode plugin converts the app target's local profiling data into
`WeeklyHealthReport.app.coverage.txt`; search is disabled so only that named
report is uploaded. The action receives the repository's `CODECOV_TOKEN`, with
its optional telemetry disabled.

Codecov receives repository source paths, line-level execution data, source
text embedded by Xcode's coverage rendering, and Git metadata needed to attach
the report to a commit or pull request. It does not receive the `xcresult`,
HealthKit permission, personal health data, signing credentials or the Google
Drive credentials used by the app. The `xcresult` remains a GitHub Actions
artifact under the retention policy above.

## Reviewed baseline

The baseline below was measured from an unmodified checkout of
`1abec688ce3d583a713c380931cec804da3bff74` (`origin/main` on 8 September 2026)
using Xcode 26.6, an iOS 26.5 iPhone 17 Pro simulator and all 90 tests:

| Layer | Covered / executable lines | Line coverage |
| --- | ---: | ---: |
| App target | 5,175 / 10,406 | 49.73% |
| Pure models and formatting | 2,840 / 2,960 | 95.95% |
| Report orchestration | 374 / 452 | 82.74% |
| HealthKit client | 4 / 1,211 | 0.33% |

One repeated run over the same app sources reported 5,174 rather than 5,175
covered app-target lines (49.72% rather than 49.73%), while the pure-domain and
two orchestration rows were unchanged. This observed generated/runtime variance
is another reason the whole-app percentage is informational.

The 95.0% pure-domain threshold leaves just under one percentage point below
the measured baseline. It protects the extensively tested deterministic layer
without creating a misleading whole-app target.

## Runtime evidence

The [existing hosted run for the same reviewed
commit](https://github.com/syamaner/WeeklyHealthReport/actions/runs/34191409074)
spent 8 minutes 31 seconds in its test step and 8 minutes 47 seconds in the job
overall. The job keeps its existing 20-minute timeout.

Local warm-cache measurements on the baseline checkout were 26.69 seconds for
the existing unsigned test command and 24.87 seconds with coverage enabled, so
that single-run comparison shows no measurable coverage penalty. A clean local
run in the workflow's final order took 9.43 seconds for analysis and 30.77
seconds for the following coverage test, 40.20 seconds in total. These timings
are noisy and are not a substitute for exact-head hosted results. Together with
the hosted job's 11-minute-plus timeout margin, they do not justify increasing
the timeout before that evidence exists.

## Reproduce locally

Choose an available iPhone simulator identifier, then run:

```bash
python3 -m unittest discover -s .github/scripts/tests -v

result_directory="$(mktemp -d)"
result_bundle="$result_directory/WeeklyHealthReportTests.xcresult"
coverage_summary="$result_directory/coverage-summary.md"

xcodebuild analyze \
  -project WeeklyHealthReport.xcodeproj \
  -scheme WeeklyHealthReport \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -project WeeklyHealthReport.xcodeproj \
  -scheme WeeklyHealthReport \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -enableCodeCoverage YES \
  -resultBundlePath "$result_bundle" \
  CODE_SIGNING_ALLOWED=NO

python3 .github/scripts/summarize_coverage.py \
  --xcresult "$result_bundle" \
  --commit "$(git rev-parse HEAD)" \
  --output "$coverage_summary" \
  --minimum-domain-coverage 95
```

The commit printed in each report is the exact revision whose instrumented app
binary was tested; do not reuse a percentage after the reviewed commit changes.
