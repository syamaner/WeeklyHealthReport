# Offline nutrition evaluation spike result

Completed 1 October 2026 using Promptfoo 0.123.1. The spike demonstrates that local production runners, retained extraction scoring and deterministic assertions can share one comparison report. Recommend retaining Promptfoo for the next development harness phase. This does not establish nutrition accuracy or independent acceptance.

## Observed results

| Suite | Result | Meaning |
| --- | --- | --- |
| Query NLP | 511/511 legacy regression expectations met | Routing and quantity match all cases; all four fields match the 347 search-eligible cases |
| Strict query diagnostics | Food 382/511; attributes 492/511; all four fields 378/511 | Remaining tentative extraction differences on clarify/reject cases stay visible rather than being relabelled |
| Nutrition extraction | 20/20 historical development cases reproduced | Original v3 report matches after retained document hash, source identity and response-binding checks |
| Unsupported count conversion | `missingConversion`, zero saved records | Actual production save service blocks count without evidenced edible-weight conversion |
| Supported grams control | One saved record | The same production service can save a compatible quantity |
| Promptfoo | 533 successes, zero failures/errors | Case expectation assertions were executed through the local adapter; this is not an AI-quality aggregate |
| Scorer/adapter contracts | Six tests passed | Missing/duplicate/extra rows, wrong identities, unexpected saves, blanket blocking, wrong basis and invented unknown-zero output are rejected |

Two fresh runs produced identical query predictions, query/extraction reports, safeguard observations and summary results. The second run verified the final dependency-lock and complete Promptfoo-roster checks. No full simulator suite was run because this change adds evaluation tooling without changing production Swift or package dependencies. The standalone Swift probe and its production domain/application/test-support dependencies compiled and ran successfully.

## Reports and provenance

- [Scorecard overview](/private/tmp/whr-nutrition-spike-20261001-2/report.html)
- [Promptfoo case comparison](/private/tmp/whr-nutrition-spike-20261001-2/promptfoo.html)
- [Structured summary](/private/tmp/whr-nutrition-spike-20261001-2/summary.json)
- [Run manifest](/private/tmp/whr-nutrition-spike-20261001-2/manifest.json)
- [Local runner and reproduction instructions](../Tools/NutritionEvaluationSpike/README.md)

The reports are local temporary files. Summary and manifest copies are retained under `Tools/NutritionEvaluationSpike/evidence/`; detailed report reproduction also requires the retained private source documents. Installed transitive dependency versions are retained in the run's dependency lock. Source code was compiled from the dirty working tree and hashed; historical extraction resource drift is explicitly recorded.

During each evaluation, the OS sandbox denied networking and the Keychain command executable, and a network probe returned EPERM. Promptfoo telemetry, updates, caching and sharing were disabled. No model/provider calls or model judges ran. Promptfoo's 533 `numRequests` are local adapter invocations, not external requests. Package installation used the npm registry before evaluation.

HTML outputs were generated and their local links/content checked. Visual browser inspection was unavailable because the browser tool rejects local `file:` URLs; no alternate serving route was attempted. Rendered layout remains visually unverified.

## Interpretation and remaining work

The deliberate unsupported 80 g proposal is synthetic fault injection. It remains a proposal-stage failure even though the save block meets the safeguard expectation. The control records only a synthetic save; full daily projections and representative user effort remain unmeasured.

Extraction uses historical agent-reviewed references and the original field scorer. Common-contract supported-field precision/recall and new independent source-support judgements remain future work. The extraction adapter excludes record-resolver evaluation, so the changed USDA resource cannot be treated as newly validated by its successful replay.

The next coherent implementation slice is to stabilise the neutral case/result schema, add retrieval as separately labelled historical/current evidence, and implement common nutrient-field scores with explicit evidence status. List NLP and full save/reopen/edit/delete/daily-total scenarios then extend the same report. Voice, independent acceptance and live cost/latency require their own datasets and separately bounded execution.
