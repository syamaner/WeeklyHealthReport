# Generic retrieval and quantity handoff — v3 / issue #160

This supersedes the draft's narrow v2 implementation at 8a69363. All v1/v2 fixtures, baseline/intermediate captures and metrics remain historical. Following device feedback, 72 versioned exposed development scenarios were judged before generic tuning, including yoghurt, milk, rice, five transfer families and explicit qualifiers. They run through the actual build 9 CoFID/USDA adapters and composite for the baseline and through the new shared policy for the final replay (216 rows each). This is same-author development/regression evidence, not independent acceptance or production accuracy.

Architecture: one source-neutral application policy ranks primary food names, unrequested specialisations and ordinary representation descriptors; the same comparison runs before adapter limits and across sources. No branch inspects an individual food family or query. Shared canonical lexical terms preserve the existing spelling/plural contract. Stable source interleaving is a tiebreak; source-local numeric scores are never compared. Raw/cooked identity checks and whole-record provenance remain separate and hard. No new data source is admitted.

The representation vocabulary (plain/average/regular/whole/white; unrequested flavours, concentrated forms and specialised species) is a versioned presentation preference, not established identity or a universal food default. Explicit named terms remain required by retrieval and remove the corresponding unrequested-specialisation penalty. The original parser and shipped numeric fat hint remain; the draft's added adapter-level numeric variant promotion and food-specific bonuses are removed. Detailed variant matching is deferred.

## Comparable generic-ranking results

V3 labels deliberately judge generic yoghurt relevance even when a fat percentage was supplied, because issue #160 defers detailed variants. Numeric mismatch exposure remains separate. V2's stricter numeric-variant labels remain available; do not compare its aggregate scores directly to v3. Both v3 before/final runs use identical labels and queries. The legacy JSON key `exactCoverageCases` means availability of a grade >=2 relevant record, not exact product identity.

| Source | Relevant coverage / 72 | Hit@1 before → final | Hit@5 before → final | MRR before → final | nDCG@5 before → final |
|---|---:|---:|---:|---:|---:|
| cofid | 41 | 0.268 → 0.976 | 0.878 → 0.976 | 0.569 → 0.976 | 0.654 → 0.920 |
| usda | 60 | 0.833 → 0.933 | 1.000 → 1.000 | 0.894 → 0.967 | 0.699 → 0.976 |
| composite | 60 | 0.500 → 1.000 | 0.933 → 1.000 | 0.708 → 1.000 | 0.635 → 0.978 |

| Composite family | Cases | Relevant coverage | Hit@1 before → final | MRR before → final |
|---|---:|---:|---:|---:|
| catalogue-miss | 5 | 0 | — → — | — → — |
| clementine | 5 | 5 | 1.000 → 1.000 | 1.000 → 1.000 |
| explicit-qualifiers | 6 | 6 | 1.000 → 1.000 | 1.000 → 1.000 |
| milk | 4 | 4 | 0.000 → 1.000 | 0.167 → 1.000 |
| ribeye | 6 | 6 | 1.000 → 1.000 | 1.000 → 1.000 |
| ribeye-preparation | 4 | 4 | 0.500 → 1.000 | 0.750 → 1.000 |
| rice | 4 | 4 | 0.000 → 1.000 | 0.200 → 1.000 |
| transfer-apple | 2 | 2 | 1.000 → 1.000 | 1.000 → 1.000 |
| transfer-banana | 2 | 2 | 1.000 → 1.000 | 1.000 → 1.000 |
| transfer-lentil | 2 | 2 | 1.000 → 1.000 | 1.000 → 1.000 |
| transfer-oats | 2 | 2 | 0.000 → 1.000 | 0.500 → 1.000 |
| transfer-salmon | 2 | 2 | 1.000 → 1.000 | 1.000 → 1.000 |
| unrelated | 7 | 0 | — → — | — → — |
| yoghurt-fat | 15 | 15 | 0.200 → 1.000 | 0.600 → 1.000 |
| yoghurt-spelling | 6 | 6 | 0.000 → 1.000 | 0.500 → 1.000 |

All 12 composite expected-empty cases remain empty. Before, 4 milk cases have relevant records in the catalogue but none at ranks 1–5; rice is relevant around fifth. Final generic ranking retrieves relevant records first in all 60 covered cases. Per-family/source confusion matrices and grades remain in the JSON. Milk nDCG@5 is still 0.771; top-five quality is not perfect merely because Hit@1 passes. Transfer cases and correlated query variants do not prove generalisation to unseen foods.

Numeric-fat mismatch exposure remains 9 at rank 1 and 69 in the first five across 15 numeric-fat queries. Those counters describe visible alternatives, not accepted identity or invented nutrient changes. Exact 0%, 2% and 10% source-fat coverage is not established; no tolerance-based variant equivalence was added. All 147 common whole records retain identical source, identity, edible basis and nutrients/provenance. The resources themselves are unchanged.

## Quantity handoff evidence and repair boundary

The build 9 code already forwarded parsed quantities; automated model checks did not reproduce the reported device loss, so its device cause remains unconfirmed. The native flow previously created a fresh confirmation model inside the navigation destination builder. It now snapshots the chosen candidate and parsed quantity once at selection and owns that model throughout navigation, preserving edits. Confirmation state shares one exact-unit handoff (g, kg normalised to g, mL, count) and the field is initialised from that state. Invalid candidate indices cannot silently select another record. Quantity remains editable and no save occurs automatically.

Two real-adapter presentation contracts exercise later candidate selection, original evidence, editing/candidate changes, all four units, and ambiguity. The native simulator test mounts the actual SwiftUI confirmation screen and checks the rendered editable field. Cross-basis mL/g incompatibility is visible; no density or count weight is inferred, and count still requires a measured conversion before save. Clarification for bounds asks for the actual consumed amount. These are simulator/software results, not build 9 device acceptance; use `device-retest-v3.md` after a separately authorised delivery.

Validation: 203 package tests (one opt-in offline replay skipped, zero failures), unchanged 511-case parser routing/quantity gate, four retrieval scorer tests, six parser scorer tests, 26 CI-helper tests, package boundaries, 274 simulator tests (including native field rendering/editing), and Xcode analysis passed. The final simulator launch initially hit a Busy preflight state; restarting only the dedicated simulator and rerunning the entire gate passed. Historical evidence remains intact. No provider calls/spend, credentials, HealthKit writes or TestFlight upload.
