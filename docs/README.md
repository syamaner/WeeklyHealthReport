# Documentation index

Documents in this folder are **current**: they define behaviour the app relies on today. When a document is superseded, move it to [`archive/`](archive/) and update this index in the same change. Release and TestFlight records live in [`releases/`](releases/).

Start with [`../AGENTS.md`](../AGENTS.md) for working rules and [privacy and egress](privacy-and-egress.md) for what may leave the device.

## Product and UX

- [App reference](app-reference.md): screens, export workflow, privacy, setup and the metric-by-metric calculation and validation rules (moved from the repository README)
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
- [Nutrition label entry v1](nutrition-label-entry-v1.md) (#454): one Add food entry for a label photo, a screenshot, a pasted image or pasted or typed text, routed to the label photo route or the pasted-label reader; owner decisions Q1 to Q3 10 November 2026; architecture gate PASS at revision 3
- [Pasted nutrition label reader v3 release check](pasted-nutrition-label-reader-v3-release-check.md) (#93): counts from the fresh-set release check of 24 October 2026 (bar passed; owner decision to ship)
- [Pasted nutrition label, UK English v1](pasted-nutrition-label-uk-english-v1.md) (#371): plan to pass the UK English release gate (development set, reader changes, fresh-set check, then the launch scope); owner-approved 2 November 2026; architecture gate PASS WITH CHANGES applied; all eleven decisions made; P1 [development set results](pasted-nutrition-label-uk-english-v1-development-set.md) (counts only); P2a [UK reader spec](pasted-nutrition-label-uk-english-v1-p2.md); P2b [seam and energy labels spec](pasted-nutrition-label-uk-english-v1-p2b.md); P3 [freeze and fresh-set protocol](pasted-nutrition-label-uk-english-v1-p3.md); P4 [release check results](pasted-nutrition-label-uk-english-v1-release-check.md) (counts only; harness bar passed 5 November 2026, decline goal missed; owner decision: not shipped); [UK English v2 plan](pasted-nutrition-label-uk-english-v2.md) (draft: decline causes and reader changes)
- [Pasted nutrition label, UK English v2](pasted-nutrition-label-uk-english-v2.md) (#371): plan to improve the UK reader after the owner held v1 back on 5 November 2026; all five owner decisions made.
  - [P1 rule spec](pasted-nutrition-label-uk-english-v2-p1.md): parser `nutrition-label-text-parser-uk-v3` and identity `pasted-label-identity-v3`; architecture gate PASS WITH CHANGES applied, 6 November 2026.
  - [P3 freeze and fresh-set protocol](pasted-nutrition-label-uk-english-v2-p3.md): freeze re-pin 2, scorer `uk-fresh-scorer-v2` (closed rules R1 to R3), set-aside files in the release run, and the v2 fresh-set protocol with site tiers.
  - [P4 release check record](pasted-nutrition-label-uk-english-v2-p4.md): protocol amendments made during the v2 fresh-set collection (Amendment 1: Co-op's fixed postcode) and, once scored, the release check results.
- [HealthKit day bucketing v1](healthkit-day-bucketing-v1.md) (#49): daily collection queries honour the injected calendar, with an alignment check and a per-day fallback (owner-approved 18 October 2026)
- [Food drafts and common foods](food-drafts-and-common-foods.md), [food list import](food-list-import.md)
- [Food list lexical v4](food-list-lexical-v4.md) (locale-aware list amount grammar), [v5](food-list-lexical-v5.md) (vague portions such as "a handful" need an amount) [v6](food-list-lexical-v6.md) (household containers such as "2 mugs of tea" leave the food name, as in search) and [v7](food-list-lexical-v7.md) (the other containers and household measures, such as "2 slices of bread" and "a bottle of water", leave the food name and give no amount)
- [Food query interpretation v4](food-query-interpretation-v4.md) (a household unit with no amount before it, as in "mugs of tea" or "250 ml mug of milk", leaves the search text); current version v5 is recorded in [unified food search contract v73](unified-food-search-contract-v1.md) (#370, a named dish's exact amount)
- [Local inventory contract](local-inventory-contract.md)
- [Personal food database import v1](personal-food-catalogue-import-v1.md) (#419): local import of the owner's private nutrition database built with the [`personal-food-catalogue`](../.agents/skills/personal-food-catalogue/SKILL.md) skill; accepted by the owner on 7 November 2026 (revision 5, twelve owner decisions); implementation not started, it is a separate phase with its own architecture gate; synthetic [fixtures](fixtures/personal-food-database-v1/)
- [Personal food database evaluation v1](personal-food-database-evaluation-v1.md) (#424): phase E0 plan for measuring the private database and its search before the importer is built; owner-set acceptance bars, a sealed held-out query set and counts-only results; revision 7, E3 accepted 10 November 2026
- [Personal food database E3 disposition](personal-food-database-e3-disposition.md) (#424): E3 gate status, the A1 disposition and the evidence audit disposition for approved estimates; D1 to D5 decided, R1 built and its ID recorded, E3 final (plan revision 7)
- [Personal food database approved estimates v1](personal-food-catalogue-estimates-v1.md) (#419): versioned contract and architecture gate for importing owner-approved estimates with per-nutrient evidence; accepted 9 November 2026, not implemented
- [Storage and backup decision](food-library-storage-and-backup-decision.md)
- [HealthKit food write plan](food-healthkit-write-plan.md) (planning; HealthKit stays read-only)

## Food search and sources

- [Unified food search contract v1](unified-food-search-contract-v1.md); current amendment v73 (#370): `food-query-discovery-v4` and `food-query-interpretation-v5` pre-fill one exact leading or trailing whole-dish amount for a named dish (owner-approved 3 November 2026)
- [Search quality v3](food-search-quality-v3.md) and [generic retrieval policy v5](generic-food-retrieval-policy-v5.md), extended by [generic food ranking v7](generic-food-ranking-v7.md) (unrequested part words) and [food lexical terms v9](food-lexical-terms-v9.md) (rule-based plurals)
- [Query parser v1](food-query-parser-plan-v1.md) and [query parser v8](food-query-parser-v8.md) (cooked egg counts), [query parser v9](food-query-parser-v9.md) (hard boiled eggs, numbered pieces), [query parser v10](food-query-parser-v10.md) (plural cups, mugs and other containers are portions), [input interpretation and nutrition review v1](food-input-interpretation-and-nutrition-review-v1.md), [query interpretation v2](food-query-interpretation-v2.md) (household portions leave the search text), [English street-food input v1](english-street-food-input-v1.md)
- [Online search recovery v1](online-food-search-recovery-v1.md)
- [Generic web proposal integration v1](generic-food-proposal-integration-v1.md) and [repair v2](generic-food-proposal-repair-v2.md)
- [Open Food Facts barcode candidates v1](off-barcode-candidate-plan-v1.md), with the panel-stated basis amendment (`off-product-projection-v5`, #458)
- [Taiwan food catalogue v1](taiwan-food-catalogue-v1.md) and [composite regional source order v9](composite-regional-order-v9.md) (Taiwan rows after UK and US unless the market or query indicates Taiwan)
- [Source coverage and licence evaluation](food-source-coverage-and-licence-evaluation.md)
- [Dark chocolate nutrient sources investigation](dark-chocolate-nutrient-sources-investigation.md) (#381): why 70% to 100% cocoa searches give poor nutrition, the source survey (CoFID, USDA, Ciqual 2025 and others) and the owner-approved phase plan A (#382), B (#383) and C (#384)
- [Cocoa-aware generic food search v1](cocoa-aware-search-v1.md) (#382, phase A of #381): parser v11 cocoa and per cent rules, `cocoa-percent-policy-v1` bands, the owner-approved 100% estimate, tier ordering and notes; architecture gate PASS WITH CHANGES applied; amendment of 10 November 2026 (#452): `food-query-interpretation-v6` and `off-search-detail-transport-v5` keep the cocoa percentage for comma and spaced phrasings
- [Label plus generic estimate v1](label-estimate-merge-v1.md) (#383, phase B of #381): owner decisions on cocoa compatibility, the Confirm estimate section and the cocoa % field; compatibility and merge rules, stored estimate layer, `confirmFoodV4`, archive contract 8 and reopen verification; architecture gate PASS WITH CHANGES applied
- [Ciqual 2025 admission v1](ciqual-2025-admission-v1.md) (#384, phase C of #381): owner decisions 4 and 5 and decisions D1 to D10, pinned files and hashes, the chocolate subgroup 0702 scope (29 foods), constituent mapping and value-form rules, `cocoa-percent-policy-v2`, `composite-generic-ranking-v11`; architecture gate PASS WITH CHANGES applied

## Nutrition evaluation

- [Evaluation plan v1](nutrition-ai-evaluation-plan-v1.md), [metric contract v1](nutrition-ai-metric-contract-v1.md), [acceptance plan v1](nutrition-ai-acceptance-plan-v1.md), [inventory v1](nutrition-ai-evaluation-inventory-v1.md)
- [Nutrition-label capture evaluation v1](nutrition-label-capture-evaluation-v1.md): pasted text, on-device OCR and multimodal LLM routes (plan only)

## Health report, workouts and export

- [Workout interval enrichment contract](workout-interval-enrichment-contract.md), [accepted distance amendment](accepted-workout-distance-amendment.md), [heart-rate readings contract](workout-heart-rate-readings-contract.md)
- [Daily export contract](daily-export-contract.md) and [Google Drive export plan](google-drive-export-plan.md)
- [Food daily export v1](food-daily-export-contract-v1.md) (#287): the food log as a separate daily JSON file in the same Drive folder (owner-approved 23 October 2026)
- [Food daily export v2](food-daily-export-contract-v2.md) (#312): entry-level quantity method, estimate flag and entered amount for typical-weight and whole-milk volume estimates; v1 files stay valid (decided under owner delegation and gate PASS WITH CHANGES folded in, 31 October 2026; not implemented)
- [Google Cloud setup](google-drive-cloud-setup.md) and [product setup](google-drive-product-setup.md)

## Engineering

- [CI analysis and coverage](ci-analysis-and-coverage.md)
- Test fixtures: [`fixtures/`](fixtures/); screenshots: [`images/`](images/); earlier design bundles: [`designs/`](designs/)
