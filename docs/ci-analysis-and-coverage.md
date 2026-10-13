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
- pure domain code under `WeeklyHealthReport/Models`, formatting under
  `WeeklyHealthReport/Utilities`, and deterministic report construction under
  `WeeklyHealthReport/Presentation`;
- report orchestration in `WeeklyReportViewModel.swift`; and
- the framework-bound `HealthKitClient.swift`.

Only the models, formatting and presentation layer has a regression gate, with
a conservative minimum of 95.0%. App-wide, view-model and HealthKit-client
values remain informational. Presentation joined the gate after its state and
available-value branches were covered and a Phase 4 measurement reported
3,870 / 4,013 lines (96.44%). This avoids equating SwiftUI-generated executable
lines or code that requires Apple frameworks with directly testable report
logic.

Codecov's project and patch statuses are also explicitly informational in
`codecov.yml`; they do not replace or broaden the repository-owned 95.0% gate.
The Codecov action fails CI for local generation or transport errors. Codecov
processes accepted uploads asynchronously, so its hosted result must still be
checked independently when reviewing a pull request.

The summariser fails closed if the app target or a named layer disappears from
Xcode's coverage report. Its standard-library unit tests also run before Xcode
analysis and testing.

## Measurement and shadow policy

Every pull request and `main` push still runs the complete unsigned Xcode
analysis, simulator suite, coverage gate and uploads. The workflow also records a
shadow decision describing what a future selective post-merge policy would have
chosen. That decision is evidence only: no job condition or command consumes it.

The shadow classifier is deliberately fail-closed. Executable pull requests are
always classified as full. A `main` push can report documentation or focused mode
only when it matches exactly one merged pull request targeting `main`, its before
and after revisions match that pull request, and the exact pull-request head has
one successful GitHub Actions `Build and test` check. Forced pushes, missing
comparison bases, ambiguous pull requests, absent checks, renames, copies,
multiple focused subsystems and unrecognised paths all report full mode. Project,
workflow, classifier, test-infrastructure, HealthKit, model, formatter and shared
reporting changes also report full mode.

The current focused path groups are Notes, production Google Drive and the
separate synthetic Drive harness. They exist only to collect shadow evidence and
must be revalidated before activation. In particular, a full production-app run
does not exercise the synthetic harness's separate project and deterministic
checks.

The workflow writes `ci-policy.json`, `ci-timing.json` and a Markdown timing
summary to the `ios-ci-measurement` artifact. Timing combines completed GitHub
Actions step timestamps with the `.xcresult` activity log. It records package
resolution, build activity, launch/test-host activity, time from launch activity
to the first suite, every suite and the ten slowest tests. Xcode build, launch and
test activity can overlap, so those durations must not be added together. The
launch-to-first-suite interval is an observable preparation boundary, not proof
that every second was simulator startup.

The shadow decision above remains evidence only. The one enforced selection is
the documentation-only gate below.

## Documentation-only gate

The `main required CI` ruleset requires `Build and test`, the two DriveExportKit
checks and the four Synthetic Drive checks, and requires branches to be up to
date. Workflow-level `paths` filters would leave those checks unreported and
block every documentation pull request, so selection happens inside the
workflow instead.

A first `Classify changes` job runs `.github/scripts/ci_changes.py` on the
changed paths (three-dot diff for pull requests, `before..after` for `main`
pushes). Every other job depends on it and runs unless its output is exactly
`false`; a job skipped through its condition reports as skipped, which satisfies
a required check.

Only an allowlist counts as documentation: `README.md`, `AGENTS.md`,
`CLAUDE.md`, `DEVELOPMENT_NOTES.md`, `LICENSE`, `docs/`, and Markdown files
under `.agents/` and `.claude/` (role and skill files; scripts and other
configuration there run the full workflow). `.github/` is never documentation,
whatever the allowlist says. Paths under `docs/` that code, tests or CI read
(`docs/fixtures/`, `docs/privacy-policy.txt`, `docs/food-healthkit-write-plan.md`, `docs/generic-food-review-manifest-v2.md`, `docs/today-so-far-projection-v1.md`)
always run the full workflow, as does Markdown under `Tools/` or `Packages/`,
which can be test data or checked inventory. A drift-guard test fails when a
non-documentation file starts referencing a `docs/` path the classifier would
skip.

The gate fails closed. Unknown paths, an empty diff, missing or zero
revisions, unsupported events, a `git` failure, a classifier exception or a
failed `Classify changes` job all run every job.

The gate cannot loosen itself. `Classify changes` runs the classifier tests
unconditionally before any decision, and decides with the base revision's
reviewed `ci_changes.py` (falling back to the change's own copy only when the
base has none). A change that edits the allowlist is therefore judged by the
previous rules, and because it touches `.github/` it always runs every job,
including the helper tests in `Build and test`.

## Serial simulator testing

The test step passes `-parallel-testing-enabled NO`. On the hosted three-core runner a second simulator clone took minutes to boot and competed for CPU with the real test runner; on one `main` run it never finished booting, and on a PR run the contention slowed render tests enough to fail a readiness deadline and push the job past its 20-minute timeout (run 38198192162). Running serially matches the local gate command.

## FoodLedgerKit job timeout

The "FoodLedgerKit build and contracts" job runs the whole package suite and then
scores the retrieval replay. Before search ranking v7 / composite v9 it took 8m08s
to 8m31s on `main` against a 10-minute timeout. The replay now also covers the
production three-source composite with each scenario's market (retrieval scenarios
v5). It reuses the CoFID and USDA rows and derives the two-source composite rows
from the regional composite instead of searching a third time, which brought the
local replay test from 70.3 s (first version) to 53.0 s for 87 cases; the 72-case
replay on `main` took about 42 s locally. The remaining 10 to 15 s locally, more on
the hosted runner, would leave under a minute of margin, so the job timeout is 15
minutes. Revisit it if the job's measured duration falls back well below 10 minutes.

Food lexical terms v9 adds 18 replay cases (105 in all) and a same-number ranking
check. Locally the replay test took 70.1 s against 53.0 s, and the whole package
suite 189 s of test time (250 s with the build), so the 15-minute timeout still
leaves several minutes of margin on the hosted runner.

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
| Models and formatting (historical scope) | 2,840 / 2,960 | 95.95% |
| Report orchestration | 374 / 452 | 82.74% |
| HealthKit client | 4 / 1,211 | 0.33% |

One repeated run over the same app sources reported 5,174 rather than 5,175
covered app-target lines (49.72% rather than 49.73%), while the pure-domain and
two orchestration rows were unchanged. This observed generated/runtime variance
is another reason the whole-app percentage is informational.

The 95.0% threshold protects the extensively tested deterministic report layer
without creating a misleading whole-app target. The table above predates the
Phase 5 widening; the current gate additionally includes `Presentation/` as
described above.

## Runtime evidence

Issue #44's read-only baseline sampled seven matched pull-request and post-merge
`main` pairs from 10–12 September 2026: #35, #43, #45, #46, #59, #60 and #61.
Across those 14 successful runs, median pull-request runner occupancy was 8
minutes 53 seconds and median post-merge occupancy was 7 minutes 28 seconds. The
median Xcode test-and-coverage step was 7 minutes 15 seconds on pull requests and
6 minutes 12 seconds on `main`; median analysis was 46 and 43 seconds
respectively. The seven repeated `main` jobs occupied 56 minutes 11 seconds in
total.

The exact result bundle from `main` run
[34716161541](https://github.com/syamaner/WeeklyHealthReport/actions/runs/34716161541)
contained 198 tests. Its Xcode test step took 491.70 seconds, while the result
reported 11.23 seconds of build activity, 477.50 seconds of launch/test-host
activity and 41.08 seconds across named test bodies. A faster comparison run,
[34695869474](https://github.com/syamaner/WeeklyHealthReport/actions/runs/34695869474),
reported 9.40 seconds of build activity, 256.70 seconds of launch/test-host
activity and 20.02 seconds across named test bodies. The dominant and variable
cost was therefore outside the test bodies themselves.

On run 34716161541, the first AppAuth package fetch and resolution took about
10.1 seconds; the subsequent resolution in the same job took about 1.2 seconds.
That small single-job observation does not establish a cache benefit. The shadow
slice adds no cache and makes no cache-performance claim.

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

python3 .github/scripts/ci_policy.py --help
python3 .github/scripts/summarize_ci_timing.py --help

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
