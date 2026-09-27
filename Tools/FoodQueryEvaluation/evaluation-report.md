# Food query evaluation — repair checkpoint

Same-author synthetic development data. The 511 cases include correlated variants; these scores are not estimates of real-world accuracy or independent acceptance. No provider calls were made.

## Comparable v5 results

| Metric | First run | Repaired |
|---|---:|---:|
| Routing | 508/511 | 511/511 |
| Quantity (including expected absence) | 509/511 | 511/511 |
| Strict food extraction | 382/511 | 382/511 |
| Strict attributes | 492/511 | 492/511 |
| All four fields | 378/511 | 378/511 |
| Unexpected quantity prefills | 2 | 0 |

All 347 search-eligible cases match every scored field after repair. Remaining strict food/attribute disagreements occur in clarification/rejection cases, where the parser may retain tentative terms. They remain recorded rather than relabelled to inflate accuracy.

## Route confusion matrix

Rows are expected routes; columns are predicted routes.

| Expected / predicted | Search | Clarify | Reject |
|---|---:|---:|---:|
| Search | 347 | 0 | 0 |
| Clarify | 0 | 124 | 0 |
| Reject | 0 | 0 | 40 |

Per-class precision, recall and F1: 1.000 each. Macro F1 and balanced accuracy: 1.000. False search eligibility: 0/164 non-search cases. Original query retained: 511/511.

## Extraction and safety metrics

Attribute-pair micro precision: 0.887; recall: 1.000; F1: 0.940. This counts attribute pairs rather than whole-query exactness.

Quantity presence precision/recall/F1: 1.000. All 324 expected quantities match value and unit; zero missing, unexpected, wrong-unit or wrong-value quantities. Relative magnitude error is zero on comparable pairs. Units are never mixed into one absolute-error average.

JSON reports also retain per-family counts and scenario-group macro scores. Historical cases without a scenario group use their case ID; group weighting reduces some repetition effects but does not make this an independent sample. Undefined metric denominators are null.

## Audit and scope

First-run reports and raw compressed predictions are retained. Fixture hashes are validated by versioned manifests. v5 fixes one annotation (boiled preparation) explicitly; earlier files are unchanged. Metric schema 2 treats numeric percentage representations as equivalent. Use the same schema for before/after comparisons.

This evaluation measures parsing, routing and safe quantity hints. It does not measure catalogue coverage, ranked retrieval relevance, source nutrition correctness, Gemini grounding or actual device behaviour. A separately authored holdout and user search review remain necessary before broader quality claims.
