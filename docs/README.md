# Documentation index

Documents in this folder are **current**: they define behaviour the app relies on today. When a document is superseded, move it to [`archive/`](archive/) and update this index in the same change. Release and TestFlight records live in [`releases/`](releases/).

Start with [`../AGENTS.md`](../AGENTS.md) for working rules and [privacy and egress](privacy-and-egress.md) for what may leave the device.

## Product and UX

- [UX revamp v1](ux-revamp-v1.md): journeys, screen states, contract changes and architecture gate; wireframes in [`designs/ux-revamp-v1/`](designs/ux-revamp-v1/README.md)
- [Privacy and egress](privacy-and-egress.md) and the user-facing [privacy policy](privacy-policy.txt) (bundled in the app)

## Food ledger and confirmation

- [Food identity and nutrition contract](food-identity-nutrition-contract.md)
- [Food confirmation contract v2](food-confirmation-contract-v2.md)
- [Direct edible weight v1](direct-edible-weight-contract-v1.md), [count conversion method v1](count-conversion-method-v1.md), [half-item count v1](half-item-count-contract-v1.md), [recipe source serving v1](recipe-source-serving-contract-v1.md)
- [Count portion estimate v1](count-portion-estimate-v1.md) (#307): cited typical egg weights by size (Large pre-filled) as a labelled estimate, one count word ("pieces") and the amount method shown after saving (owner-approved 24 October 2026)
- [CoFID whole-milk volume admission v1](cofid-whole-milk-volume-admission-v1.md)
- [Intake home projection v1](intake-home-projection-v1.md) and [intake management v2](intake-management-v2.md) (removal, restoration, reporting day)
- [Today-so-far health projection v1](today-so-far-projection-v1.md) (Home provisional health highlights, separate from report and export) and the [phase 6 Home plan](ux-revamp-phase-6-home.md)
- Health follow-up drafts awaiting owner approval: [steps trend v1](health-steps-trend-v1.md) (#215), [food and water section v1](health-food-and-water-v1.md) (#214), [section groups v1](health-report-section-groups-v1.md) (#216), [Export included summary v1](daily-export-included-summary-v1.md) (#217)
- [Health Copy all v2](health-copy-all-v2.md) (#308): Copy all uses the Health screen's titles, labels and footers (decided under owner delegation, 24 October 2026; revertible)
- [Pasted nutrition label v1](pasted-nutrition-label-v1.md) (#93): pasted or typed label text read on device to Confirm (owner-approved 18 October 2026; awaiting architecture-gate review)
- [Pasted nutrition label reader v3](pasted-nutrition-label-reader-v3.md) (#93): parser v3 for the real Taiwan paste layouts v2 declines, with an assisted basis choice and a fresh-set release check (owner-approved 20 October 2026)
- [Pasted label Confirm v1](pasted-label-confirm-v1.md) (#306): fortification asked once on Confirm (Yes / No / Not stated), Amount eaten before the label values, servings by default when the label states a serving; amends confirmation v5 and pasted label v1 (owner-approved 24 October 2026)
- [Label photo AI pre-fill v1](label-photo-ai-prefill-v1.md) (#316): Taiwan label photo read by an OpenRouter model to pre-fill Confirm, checked beside a zoomable photo; egress terms E1 to E16 owner-approved 25 October 2026, in force with the transport PR; architecture gate PASS WITH CHANGES applied; L0 locate-rate measurement in section 17.9
- [Pasted nutrition label reader v3 release check](pasted-nutrition-label-reader-v3-release-check.md) (#93): counts from the fresh-set release check of 24 October 2026 (bar passed; owner decision to ship)
- [HealthKit day bucketing v1](healthkit-day-bucketing-v1.md) (#49): daily collection queries honour the injected calendar, with an alignment check and a per-day fallback (owner-approved 18 October 2026)
- [Food drafts and common foods](food-drafts-and-common-foods.md), [food list import](food-list-import.md)
- [Food list lexical v4](food-list-lexical-v4.md) (locale-aware list amount grammar) and [v5](food-list-lexical-v5.md) (vague portions such as "a handful" need an amount)
- [Local inventory contract](local-inventory-contract.md)
- [Storage and backup decision](food-library-storage-and-backup-decision.md)
- [HealthKit food write plan](food-healthkit-write-plan.md) (planning; HealthKit stays read-only)

## Food search and sources

- [Unified food search contract v1](unified-food-search-contract-v1.md)
- [Search quality v3](food-search-quality-v3.md) and [generic retrieval policy v5](generic-food-retrieval-policy-v5.md), extended by [generic food ranking v7](generic-food-ranking-v7.md) (unrequested part words) and [food lexical terms v9](food-lexical-terms-v9.md) (rule-based plurals)
- [Query parser v1](food-query-parser-plan-v1.md) and [query parser v8](food-query-parser-v8.md) (cooked egg counts), [query parser v9](food-query-parser-v9.md) (hard boiled eggs, numbered pieces), [input interpretation and nutrition review v1](food-input-interpretation-and-nutrition-review-v1.md), [English street-food input v1](english-street-food-input-v1.md)
- [Online search recovery v1](online-food-search-recovery-v1.md)
- [Generic web proposal integration v1](generic-food-proposal-integration-v1.md) and [repair v2](generic-food-proposal-repair-v2.md)
- [Open Food Facts barcode candidates v1](off-barcode-candidate-plan-v1.md)
- [Taiwan food catalogue v1](taiwan-food-catalogue-v1.md) and [composite regional source order v9](composite-regional-order-v9.md) (Taiwan rows after UK and US unless the market or query indicates Taiwan)
- [Source coverage and licence evaluation](food-source-coverage-and-licence-evaluation.md)

## Nutrition evaluation

- [Evaluation plan v1](nutrition-ai-evaluation-plan-v1.md), [metric contract v1](nutrition-ai-metric-contract-v1.md), [acceptance plan v1](nutrition-ai-acceptance-plan-v1.md), [inventory v1](nutrition-ai-evaluation-inventory-v1.md)
- [Nutrition-label capture evaluation v1](nutrition-label-capture-evaluation-v1.md): pasted text, on-device OCR and multimodal LLM routes (plan only)

## Health report, workouts and export

- [Workout interval enrichment contract](workout-interval-enrichment-contract.md), [accepted distance amendment](accepted-workout-distance-amendment.md), [heart-rate readings contract](workout-heart-rate-readings-contract.md)
- [Daily export contract](daily-export-contract.md) and [Google Drive export plan](google-drive-export-plan.md)
- [Food daily export v1](food-daily-export-contract-v1.md) (#287): the food log as a separate daily JSON file in the same Drive folder (owner-approved 23 October 2026)
- [Google Cloud setup](google-drive-cloud-setup.md) and [product setup](google-drive-product-setup.md)

## Engineering

- [CI analysis and coverage](ci-analysis-and-coverage.md)
- Test fixtures: [`fixtures/`](fixtures/); screenshots: [`images/`](images/); earlier design bundles: [`designs/`](designs/)
