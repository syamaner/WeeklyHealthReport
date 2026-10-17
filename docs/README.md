# Documentation index

Documents in this folder are **current**: they define behaviour the app relies on today. When a document is superseded, move it to [`archive/`](archive/) and update this index in the same change. Release and TestFlight records live in [`releases/`](releases/).

Start with [`../AGENTS.md`](../AGENTS.md) for working rules and [privacy and egress](privacy-and-egress.md) for what may leave the device.

## Product and UX

- [UX revamp v1](ux-revamp-v1.md): journeys, screen states, contract changes and architecture gate; wireframes in [`designs/ux-revamp-v1/`](designs/ux-revamp-v1/README.md)
- [Privacy and egress](privacy-and-egress.md) and the user-facing [privacy policy](privacy-policy.txt) (bundled in the app)

## Food ledger and confirmation

- [Food identity and nutrition contract](food-identity-nutrition-contract.md)
- [Food confirmation contract v2](food-confirmation-contract-v2.md)
- [Direct edible weight v1](direct-edible-weight-contract-v1.md), [half-item count v1](half-item-count-contract-v1.md), [recipe source serving v1](recipe-source-serving-contract-v1.md)
- [CoFID whole-milk volume admission v1](cofid-whole-milk-volume-admission-v1.md)
- [Intake home projection v1](intake-home-projection-v1.md) and [intake management v2](intake-management-v2.md) (removal, restoration, reporting day)
- [Today-so-far health projection v1](today-so-far-projection-v1.md) (Home provisional health highlights, separate from report and export) and the [phase 6 Home plan](ux-revamp-phase-6-home.md)
- Health follow-up drafts awaiting owner approval: [steps trend v1](health-steps-trend-v1.md) (#215), [food and water section v1](health-food-and-water-v1.md) (#214), [section groups v1](health-report-section-groups-v1.md) (#216), [Export included summary v1](daily-export-included-summary-v1.md) (#217)
- [Food drafts and common foods](food-drafts-and-common-foods.md), [food list import](food-list-import.md)
- [Food list lexical v4](food-list-lexical-v4.md) (locale-aware list amount grammar) and [v5](food-list-lexical-v5.md) (vague portions such as "a handful" need an amount)
- [Local inventory contract](local-inventory-contract.md)
- [Storage and backup decision](food-library-storage-and-backup-decision.md)
- [HealthKit food write plan](food-healthkit-write-plan.md) (planning; HealthKit stays read-only)

## Food search and sources

- [Unified food search contract v1](unified-food-search-contract-v1.md)
- [Search quality v3](food-search-quality-v3.md) and [generic retrieval policy v5](generic-food-retrieval-policy-v5.md), extended by [generic food ranking v7](generic-food-ranking-v7.md) (unrequested part words) and [food lexical terms v9](food-lexical-terms-v9.md) (rule-based plurals)
- [Query parser v1](food-query-parser-plan-v1.md) and [query parser v8](food-query-parser-v8.md) (cooked egg counts), [input interpretation and nutrition review v1](food-input-interpretation-and-nutrition-review-v1.md), [English street-food input v1](english-street-food-input-v1.md)
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
- [Google Cloud setup](google-drive-cloud-setup.md) and [product setup](google-drive-product-setup.md)

## Engineering

- [CI analysis and coverage](ci-analysis-and-coverage.md)
- [Internal TestFlight release from GitHub Actions v1](testflight-ci-release-v1.md) (draft; manual dispatch, protected environment, no-leak rules)
- Test fixtures: [`fixtures/`](fixtures/); screenshots: [`images/`](images/); earlier design bundles: [`designs/`](designs/)
