# WeeklyHealthReport agent guide

This file applies to the whole repository. Keep it concise; exact metric semantics and Apple Health validation steps live in `README.md`.

## Priorities

1. Correctness and privacy before feature count or speed.
2. Preserve completed-day periods, daily-first aggregation and explicit `No data` states.
3. Keep calculations transparent enough to reproduce from Developer Diagnostics.
4. Make the smallest coherent change and preserve unrelated user work.

## Before changing code

- Read the relevant README semantics, model, HealthKit query, formatter, view-model flow and tests.
- Check `git status` and do not overwrite unrelated or uncommitted changes.
- For a new HealthKit metric, investigate current official Apple documentation and propose the aggregation semantics before implementation.
- Treat unavailable reads as either no visible data or no access. HealthKit does not disclose read denial, so never report zero or a definite denial without evidence.

## HealthKit and reporting invariants

- Request read access only. Keep HealthKit authorization `toShare` empty.
- Do not add accounts, analytics, persistence, networking, background delivery or remote transport.
- Use HealthKit statistics for cumulative or source-resolved values; do not manually sum overlapping sources.
- Preserve correlated records, such as systolic and diastolic blood pressure, as intact pairs. Never join unrelated samples.
- Convert HealthKit units at the query boundary and pass plain values into pure models.
- Reporting intervals use the local calendar, include the start, exclude the end and omit the current partial day.
- Aggregate within each completed day first, then aggregate days with equal weight unless the README explicitly defines another method.
- A latest measurement may use its documented lookback and include today independently of the completed-day summary.
- Put aggregation in pure model code, presentation in `HealthReportFormatter`, and HealthKit access in `HealthKitClient`.
- Show every metric consistently in the main screen, copied report and Developer Diagnostics unless its specification says otherwise.
- Preserve explicit loading, unavailable, failed and no-data states.
- Do not add medical classification, interpretation, targets, diagnosis or treatment advice.

## Implementation and efficiency protocol

- Use `rg` for discovery and read focused ranges instead of repeatedly dumping large files.
- Confirm semantics and edge cases before editing; correctness repairs are more expensive than a short design pass.
- Extend existing pure types and formatters before adding abstraction. Do not build a universal metric framework for unlike data.
- Centralise shared dates, units and machine-used policy values so query and aggregation windows cannot drift.
- Add pure aggregation and formatting tests with synthetic fixtures. Add view-model tests when orchestration changes.
- Run the narrowest relevant tests while iterating. Run the complete simulator suite once after code stabilises.
- Run Xcode static analysis for substantive Swift changes. Do not repeat full builds after documentation-only changes.
- Parallelise independent read-only checks when useful, but avoid delegation or extra review loops for small, tightly coupled changes.
- Review `git diff --check`, the final diff and repository status before handoff.

## Validation and delivery

- The simulator proves pure logic and UI compilation, not representative personal HealthKit behaviour.
- For HealthKit changes, document a reproducible Apple Health comparison using Developer Diagnostics.
- If device installation is requested and a trusted iPhone is available, build with local signing and install the app. Report locked-device or signing failures precisely.
- Never describe a signed build or successful installation as live HealthKit validation. The user must approve access and compare visible values on the device.
- Do not commit, push, create issues or otherwise change remote state unless the user requests it.
- When asked to commit, stage only files in scope. When asked to push, verify local and remote heads afterwards.
- Report the tests, analysis, device result, commit or push state and any remaining manual validation boundary.

## Cost accounting

- For a substantial implementation phase, append one bounded usage row to `DEVELOPMENT_NOTES.md` when requested or already included in the task.
- Record total input, cached input, output and total tokens from the measured phase; use the rate assumptions documented in that file.
- Label API-equivalent cost as a comparison, not an actual ChatGPT subscription charge.
- State what discussion, subagent, hosted-review or ledger-edit usage is included or excluded. Do not estimate missing usage.
- Do not present token totals as productivity, quality or provider-causation evidence.
