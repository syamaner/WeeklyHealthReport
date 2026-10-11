# WeeklyHealthReport agent guide

Shared rules for every coding agent in this repository (Codex reads this file directly; Claude Code reads it through `CLAUDE.md`). Keep it short. Metric semantics live in `README.md`, contracts in [`docs/`](docs/README.md), egress in [`docs/privacy-and-egress.md`](docs/privacy-and-egress.md) and the current product direction in [`docs/ux-revamp-v1.md`](docs/ux-revamp-v1.md).

## Priorities

1. Correctness and privacy before feature count or speed.
2. The current programme is the UX revamp (#140, phases #194 to #200). Broader feature expansion is paused until it lands.
3. Make the smallest coherent change, keep calculations reproducible from Developer tools, and preserve unrelated work.

## Product rules (closed; change only through a versioned contract)

- **HealthKit is read-only.** Authorisation `toShare` stays empty. HealthKit does not disclose read denial: say "no visible data or no access", never zero or a definite denial.
- **Egress** is limited to the destinations in [`docs/privacy-and-egress.md`](docs/privacy-and-egress.md). Adding or widening one needs a contract, a policy update and explicit user approval.
- **Unknown is never zero; empty is not zero.** Bounds stay bounds, estimates are labelled, partial totals are known minimums.
- **Three day rules stay distinct.** Health report period averages use local-calendar completed days (start included, end excluded, today omitted), aggregated within each day first and then weighting days equally unless `README.md` defines otherwise. The Daily JSON export covers one selected day under [`docs/daily-export-contract.md`](docs/daily-export-contract.md): today from local midnight to the frozen refresh cutoff, or one of the previous seven complete days. Home's "today so far" values are a separate, labelled projection. A latest measurement may use its documented lookback and may include today independently of completed-day summaries.
- **Use HealthKit statistics** for cumulative and source-resolved values; never sum overlapping sources by hand. Convert units at the query boundary. Keep correlated records (systolic/diastolic) as intact pairs.
- **Food records are versioned and append-only.** Every save is an explicit user action bound to its source evidence; no automatic selection or saving. Model output, citations or confidence never authorise nutrition by themselves.
- **Show every metric consistently** on the Health screen, in Copy all and in Developer tools unless its specification says otherwise.
- **No medical classification,** interpretation, targets, diagnosis or treatment advice.
- Stored records, archives and exports must decode and re-encode unchanged across versions.

## Architecture

- Layers: **domain** (pure rules and types) → **application** (policies, orchestration, ports) → **infrastructure** (HealthKit, GRDB, providers, Keychain, Drive) and **presentation** (SwiftUI, view models, copy). Wire concrete adapters only at the composition root.
- Apply SOLID pragmatically to new features and substantial changes: separate domain rules, application orchestration, infrastructure adapters and presentation.
- Domain and application code never depend on SwiftUI, UIKit, HealthKit, databases (GRDB or otherwise), filesystems, networks, provider SDKs, or concrete clocks, identifier generators, randomness or hashing. Inject these where determinism or substitution matters.
- Health report homes: aggregation in pure model code, presentation in `HealthReportFormatter`, HealthKit access in `HealthKitClient`. Centralise shared dates, units and policy values so query and aggregation windows cannot drift.
- Put extension points only where variation is real: entry routes, confirmation requirements, Home cards and Health tiles, Settings sections, providers and stores. Adding an ordinary adapter must not require modifying settled domain logic. Keep correctness, privacy, identity, provenance, aggregation and schema rules closed.
- Extend existing pure types and formatters before adding abstraction. Prefer small consumer-owned protocols. No universal metric framework, generic repository or protocol per method. Framework and persistence types do not cross ports.
- Alternate implementations of a port pass the same contract tests. Package targets and `Packages/FoodLedgerKit/Scripts/check-boundaries.sh` enforce dependencies; extend them when adding targets.
- Before substantial work, write the architecture gate (responsibilities, dependency direction, invariants, extension axes, contract tests) in the phase spec or PR. Resolve concerns before production code. If a request conflicts with these defaults, explain the trade-off and get agreement first.

## UX rules

- One journey per intent; every food entry route ends on the shared Confirm screen with one Log action.
- Show a rule where it blocks saving; put source identifiers, scores and provider stages behind details or in Developer tools.
- Preserve explicit loading, empty, partial, blocked, failed and no-data states. Copy uses British spelling, plain language and no emoji.
- Native grouped iOS style, Dynamic Type, VoiceOver labels and 44 pt targets; never rely on colour alone.
- Wireframes in `docs/designs/` are design input; they do not authorise capabilities.

## Working method

- Check `git status` first and never overwrite unrelated changes. Use `rg` and focused reads.
- Before changing code, read the relevant README semantics, contracts, models, queries, formatters, view-model flow and tests, and confirm semantics and edge cases. Correctness repairs cost more than a short design pass.
- For a HealthKit metric, use the `healthkit-metric-delivery` skill and current Apple documentation; propose semantics before code.
- Add pure tests with synthetic fixtures for rules, view-model tests for orchestration and simulator UI tests for routes. Run the narrowest tests while iterating and the full gates once the code is stable.
- Parallelise independent read-only checks; skip extra review loops for small, tightly coupled changes.

## Delivery

- One branch per issue (`feat/<issue>-<slug>`, `fix/…`, `docs/…`, `chore/…`), one PR per phase, `Closes #<issue>` in the body. Stage only files in scope.
- Commit, push and open PRs only when the user asks for delivery. Never merge, push to `main`, tag, release, upload to TestFlight or change other remote state unless asked; the user owns the merge decision.
- Before handoff, review `git diff --check`, the final diff and the final `git status`. After pushing, confirm local and remote heads match. Report tests, analysis, device result, commit or PR state and any manual validation still outstanding.
- For HealthKit changes, document a reproducible Apple Health comparison using Developer tools.
- If device installation is requested and a trusted iPhone is available, build with local signing and install; report locked-device or signing failures precisely.
- Simulator runs prove software behaviour only. Never describe a signed build or installation as HealthKit validation; the user approves access and compares values on the device.

## Validation gates

Run each command on its own and report its real output. Documentation-only changes need only `git diff --check`, with no toolchain preflight.

```bash
swift test --package-path Packages/FoodLedgerKit
bash Packages/FoodLedgerKit/Scripts/check-boundaries.sh
swift test --package-path Packages/DriveExportKit
xcodebuild analyze -project WeeklyHealthReport.xcodeproj -scheme WeeklyHealthReport -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project WeeklyHealthReport.xcodeproj -scheme WeeklyHealthReport -destination 'platform=iOS Simulator,name=iPhone 17 Pro' ENABLE_DEBUG_DYLIB=NO CODE_SIGNING_ALLOWED=NO
git diff --check
```

When search or query code changes, also run the evaluation steps in `.github/workflows/ios-ci.yml` (FoodSearchQuality and FoodQueryEvaluation). CI is the reference if these drift.

## Agent roles and handover

Named roles live in [`.agents/agents/`](.agents/agents/) (symlinked into `.claude/agents/`, where Claude Code registers them as subagents). Codex does not register them automatically: adopt a role by reading its file and mapping its tool list to the equivalent Codex tools (read-only roles use only read and search commands).

| Role | Use |
|---|---|
| `architecture-gate` | Read-only check of a planned change before code |
| `invariant-reviewer` | Read-only review of a diff against the product rules and egress list |
| `validator` | Runs the validation gates and reports verbatim |
| `journey-qa` | Walks a phase's journey in the simulator against its checklist |

Work moves between Codex and Claude Code through durable records, not chat history. Before stopping, write a handover: what changed (branch, commits, PR), evidence run, what is next and open questions.

- If the task authorises remote writes and a phase issue or PR exists, post the handover as a comment there.
- Otherwise (read-only reviews, no authority for remote writes, or no issue), give the handover in the final reply as a paste-ready block for the user to post or pass on.

On pickup, read this file, the issue thread and the PR before acting.

## Skills

Canonical skills live in `.agents/skills/` with relative symlinks in `.claude/skills/`; keep `SKILL.md` compatible with both agents and check both paths after changing one.

- `healthkit-metric-delivery`: HealthKit query-to-report changes.
- `agent-phase-accounting`: token and API-equivalent cost for a phase, only when the user asks or the task already includes it. Record rows in `DEVELOPMENT_NOTES.md` with the rate assumptions documented there; label costs as comparisons, state exclusions, and never present totals as productivity or quality evidence.
