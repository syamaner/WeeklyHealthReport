---
name: healthkit-metric-delivery
description: Research, design, implement, or review HealthKit metrics in local iOS reports when source semantics, read-only privacy, completed-day periods, defensible aggregation, and device validation matter. Use for HealthKit query-to-report changes, not generic SwiftUI work or medical interpretation.
---

# HealthKit Metric Delivery

Deliver a HealthKit metric without losing the meaning of the underlying record or implying knowledge HealthKit does not expose.

## Start with repository authority

Read the repository's `AGENTS.md`, relevant README semantics, existing query, model, formatter, view-model flow and tests. Repository rules and the user's explicit scope override this skill.

Preserve unrelated work and determine whether the request is research, design, implementation, review or validation before changing files.

## Semantics-first mode

When aggregation or layout is unsettled:

1. Investigate current official Apple documentation for the sample or correlation type, units, query/statistics behaviour and permission limitations. Cite the sources used.
2. Describe the actual data shape, including correlations, source resolution, sampling frequency and time semantics.
3. Propose latest-value, period-summary, coverage and explicit no-data behaviour. Account for irregular sampling and prevent heavily sampled days from dominating unless the data type requires sample weighting.
4. State what is excluded and why. Do not add trends, thresholds or clinical meaning merely because they are common elsewhere.
5. If the user requested planning or review only, stop before implementation.

## Delivery mode

For implementation or a full review, read [references/delivery-checklist.md](references/delivery-checklist.md) completely and apply the relevant sections.

Keep these boundaries explicit:

- Request read access only unless the user clearly authorises a different product scope.
- Never infer read denial from an empty query or present missing data as zero.
- Preserve correlated records as records; do not join independent samples.
- Convert HealthKit units at the query boundary and aggregate plain values in pure code.
- Separate latest measurements from completed-day period summaries when their windows differ.
- Keep medical classification, targets, diagnosis and treatment advice out of informational reporting.
- Use synthetic fixtures only. Do not place personal HealthKit data, signing identifiers or certificates in the repository.

## Evidence

Match validation cost to risk: focused pure tests while iterating, then the complete simulator suite and static analysis after substantive code stabilises. A simulator, signed build or installation is not live HealthKit validation. State the remaining Apple Health comparison clearly.

Do not commit, push, install, create issues or mutate remote state unless the user requested that action.
