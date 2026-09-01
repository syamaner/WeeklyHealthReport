# HealthKit metric delivery checklist

Use this checklist for implementation and full reviews. Skip sections that are outside the user's requested scope.

## 1. Establish authority and state

- Read repository instructions and exact metric semantics before editing.
- Inspect the working tree, target names, deployment target, signing pattern and existing tests.
- Preserve dirty or unrelated work. Do not reuse personal signing or Health data across repositories.

## 2. Ratify semantics

- Identify the HealthKit object type: quantity, category, workout, clinical record or correlation.
- Confirm units and whether HealthKit stores a fraction, rate, count, duration or cumulative quantity.
- Determine whether HealthKit statistics resolve overlapping sources and which statistics option is appropriate.
- Confirm sample-date membership, local-calendar boundaries and whether strict start-date behaviour is required.
- For correlations, define which visible components make one complete record.
- Define latest lookback, completed-day summary, coverage, minimum history and invalid-value handling.
- For irregular samples, prefer a transparent daily-first summary when equal day weighting matches the question.
- Define rounding only at presentation. Developer Diagnostics should retain enough precision to reproduce results.
- Explain unknown source precedence instead of inventing one.

Present these semantics for approval before implementation when the user requests it or when a choice would materially change the report.

## 3. Implement through existing boundaries

- Authorization: add only the required read type and keep `toShare` empty.
- Query layer: fetch the documented object shape, resolve units and preserve source/timestamp evidence.
- Pure model: validate input and implement aggregation without HealthKit or SwiftUI dependencies.
- State flow: add explicit loading, available, no-data-or-access, unavailable and failed behaviour.
- Snapshot and formatter: keep copied text deterministic and explicit about missing data.
- Main screen: fit the existing visual hierarchy; avoid dense rows that cannot adapt to narrow screens.
- Diagnostics: expose raw visible inputs, daily values, coverage, sources and unrounded summaries needed for verification.
- Documentation: record exact semantics, exclusions, privacy impact and manual Apple Health validation.
- Project configuration: add new files to the Xcode target without disturbing local signing configuration.

## 4. Test the decisions

Use synthetic fixtures to cover, where applicable:

- unit conversion
- invalid and missing samples
- half-open interval membership and midnight
- local time zones and daylight-saving transitions
- multiple samples on one day versus unequal sampling across days
- minimum-history and coverage rules
- correlation completeness and pair preservation
- latest value including today while completed-day summaries exclude today
- exact shared date, unit and copied-report formatting
- explicit no-data output rather than zero

Add view-model tests when query coordination, refresh generation or common state transitions change.

## 5. Validate proportionately

1. Run focused tests during iteration.
2. Run the complete simulator test suite once after code stabilises.
3. Run Xcode static analysis for substantive Swift changes.
4. Review the final diff, `git diff --check` and repository status.
5. If requested and available, make a signed device build and install it using local ignored signing configuration.
6. Document an Apple Health comparison using Developer Diagnostics. Do not claim that comparison occurred unless it actually did.
7. Commit, push and verify current CI or remote heads only when requested.

Report exact commands or destinations only when they help reproduce the evidence; never hard-code a device identifier into reusable instructions.

## 6. Keep the work efficient

- Search with `rg` and read focused file ranges.
- Reuse existing formatters, policies and model patterns without copying defects.
- Avoid a generic metric framework for data with different semantics.
- Do not rerun full test or device gates after documentation-only edits.
- Use extra agents or review loops only when independent work can genuinely reduce total effort or risk.
- Record remaining uncertainty rather than spending tokens manufacturing false precision.
