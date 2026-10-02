# Offline acceptance readiness

A preflight for the [prospective acceptance plan](../../docs/nutrition-ai-acceptance-plan-v1.md). It produces a local JSON/Markdown report explaining missing collection, reference, approval and integrity prerequisites. It executes no parser, provider, retrieval, quality scoring, save or device suite. A ready preflight never means acceptance passed or that execution is authorised.

## Architecture gate

`readiness.py` owns pure, versioned readiness policy; `run.py` owns filesystem hashing and report writing. Dependencies point from the CLI to policy. No app dependencies or evaluation packages enter production targets. Personal collection/freeze/report files remain outside Git. Closed invariants are reference exposure, roster identity, hash integrity, no fabricated quality score and no acceptance claim from preparation. Future execution adapters belong to the existing evaluation harness and must preserve its roster/stage contract; they do not alter this policy. Tests cover incomplete collection, contaminated references, duplicate groups/IDs, threshold and hash failures, and the outside-Git boundary.

## Run

Use Python 3 from the repository root. Supply owner-only files outside Git and a **new** report directory:

```sh
python3 Tools/NutritionAcceptanceReadiness/run.py \
  --collection /absolute/private/path/acceptance-collection-template-v1.json \
  --freeze /absolute/private/path/acceptance-freeze-v1.json \
  --output /absolute/private/path/new-readiness-report
```

Exit 1 means invalid integrity/input; 2 means incomplete prerequisites; 0 means these preflight checks are met. Output is `readiness.json` and `READINESS.md`; previous reports are never overwritten. Original text, reference contents and file paths are omitted from reports. The CLI has no network or process execution dependencies. It resolves paths and symlinks and rejects input/output inside a Git checkout. Keep personal files outside Git even when subsequently using other tools.

## Input contract

Collection schema is `prospective-nutrition-collection-v1`, with `cases` containing stable `case_id`, distinct `scenario_group`, `primary_stratum`, `original_input`, `intended_outcome`, `reviewer`, `reference`, `exposure` and `overlap_reviewed`. Prospective declarations use `exposure=prospective_unscored`, `overlap_reviewed=true`, `inputs_authored_by=human_after_implementation_freeze`, `references_reviewed_without_predictions=true`, `reference_review=independent_human_reviewed` and `status=frozen_unscored`. Each reference needs resolved `answerability` (answerable/needs_clarification/unsupported) and nonempty `expected` states. Unresolved mandatory references cannot pass. Single-reviewer evidence stays incomplete for this independent profile; report it descriptively under the separate plan.

Stratum minima match the proposed 60-group pilot: plain_generic 12, preparation_form 10, count_fraction 10, mass_volume 8, exact_source_gap 8, ambiguity_mixture 6 and non_food_invalid 6. Blank template slots do not count. This checks declared coverage, not representativeness or statistical sufficiency.

Freeze schema is `nutrition-acceptance-freeze-v1` with `profile=offline_nlp_retrieval`, nonempty `scorer_versions`, frozen `collection_sha256` and `pins`. Each pin has absolute local `path`, `category` and `sha256`; required categories are implementation, catalogue, metric_contract and readiness_policy. Retain every relevant file, including all source releases and implementation dependencies; the CLI verifies supplied pins, not completeness of dependency discovery. Null collection hash means preparation, not a frozen corpus.

`quality_thresholds` is an approved mapping, including AI01_route_accuracy, AI01_quantity_accuracy and AI02_hit_at_5. Each rule has finite ratio `minimum` in [0,1] and nonempty `approved_by`. Actual thresholds and additional slice requirements require human agreement before execution. The preflight checks declarations and structure, not approval authenticity, adequate thresholds, semantic truth, source support or actual reviewer independence. The execution/scoring contract must validate complete expected states and references before producing scores.

Do not turn placeholders into asserted review facts. Do not update pins or collection hashes automatically on a failure: inspect changes and explicitly freeze a new revision. Scorer versions must refer to implemented, tested scorers; this preflight does not implement the prospective scoring adapter.

## Verification

```sh
python3 -m unittest discover -s Tools/NutritionAcceptanceReadiness/tests -v
```

All fixtures are artificial infrastructure checks. Their declaration strings are not human judgements or acceptance evidence. No Swift code is changed by this tool; simulator and Xcode analysis runs are unnecessary for this phase.
