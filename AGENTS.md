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

## Architecture defaults and gates

- Apply SOLID pragmatically to new features and substantial changes. Separate domain rules, application orchestration, infrastructure adapters and presentation.
- Before substantial implementation, identify responsibilities, dependency direction, stable invariants, credible extension axes and the contract tests that protect them. Resolve architecture concerns before writing production code.
- Keep pure domain code independent of SwiftUI, UIKit, HealthKit, databases, filesystems, networks, provider SDKs and concrete clocks or identifier generators.
- Put extension points at volatile boundaries such as capture mechanisms, providers, persistence adapters, policies and projections. Adding an ordinary adapter must not require modifying settled domain logic.
- Keep correctness, privacy, identity, provenance, aggregation and schema invariants intentionally closed. Changing one requires an explicit contract or schema version, not a plug-in override.
- Prefer cohesive, consumer-owned capability protocols over universal repositories, broad service interfaces or protocol-per-method frameworks.
- Do not expose framework- or persistence-specific types across an abstraction boundary. Wire concrete implementations only at the composition root.
- Require alternate implementations of a port to pass the same behavioural contract tests. Inject clocks, identifiers, randomness, hashing and external clients when determinism or substitution matters.
- Enforce important boundaries with Swift target/package dependencies, forbidden-import checks or equivalent compile-time/CI mechanisms where practical; instructions alone are not proof.
- Avoid speculative abstraction for small or genuinely fixed behaviour. If a requested implementation conflicts with these defaults, explain the concrete trade-off and obtain agreement before proceeding.

## HealthKit and reporting invariants

- Request read access only. Keep HealthKit authorization `toShare` empty.
- Do not add analytics, background delivery, backends or unrelated accounts/persistence/networking. The user-approved exception is manual Google Drive export under `docs/daily-export-contract.md` and `docs/google-drive-export-plan.md`: narrow `drive.file` consent, secure credentials, minimal export-identity metadata and direct user-initiated transport. Prove synthetic transport before HealthKit integration; no personal-data export without explicit authority.
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

## Repository skills

- Canonical cross-agent skills live in `.agents/skills/`.
- `.claude/skills/` contains relative symlinks to the canonical skills so Claude Code and Codex use one maintained copy.
- Keep skill entrypoints compatible with the Agent Skills `SKILL.md` format. Tool-specific metadata may be ignored by the other agent.
- Validate both the canonical path and the Claude Code symlink after changing a skill.

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
