# Food descriptions and nutrition-first review v1

The user resumed implementation after the four-area research and Swift design review on 1 October 2026. This is a local, unreleased change against `389590d69b90a0c4578c63a0447e746325160749`.

## Behaviour

A meaningful description such as “Scallion pancake with eggs and american chese” can reach search before an intake amount is known. The screen, request, coordinator and OFF/Gemini adapters use the same closed interpretation policy. Requests carry an immutable interpretation of their exact original text; reconstructed requests retain it. Remote ports still store displayed food terms only and validate those terms locally. Original wording, including uncertain dictation, is retained as evidence. Discovery does not verify a dish or its nutrients.

Existing local-first orchestration, enabled-service settings, valid-key authority, source acquisition budgets and nutrition admission remain unchanged. Disabled services and a Gemini key needing validation are explained in source status. An unreported ready stage says Not searched; readiness alone is not evidence that enrichment was unnecessary. No live provider evaluation is included.

The existing numerical parser remains the authority for automatic quantities. Bounds, prices and component amounts cannot initialise a whole-meal quantity. A recovered half-pancake count is offered for explicit review, never grams or recipe servings. Preparation from fried egg or melted cheese wording cannot become the pancake’s preparation. Same-input preparation conflicts remain conservative refusals; this is not a complete food entity/relationship parser.

After explicit result choice, reference energy, protein, carbohydrate and fat appear first. Compatible entered quantities switch those values to consumed nutrition using the existing `FoodIntakeSummary`. Unknown values stay Not provided, source bounds remain bounds, and an incompatible unit keeps the reference basis visible. Estimated nutrition and material Greek/Greek-style, requested-fat and preparation cautions remain visible. More nutrients, source descriptions, licences and identifiers are disclosures. Source reference amounts do not prefill intake in the generic-search flow. Other capture flows retain their existing initialisation contract.

Amount fields accept `1/2`, `0.5` and `half` within the explicitly selected unit. Measured edible weight remains directly available without a size guide. Count-to-weight and volume-to-weight still require evidenced conversions; source recipe servings cannot be inferred from vendor counts or cooked grams. Saving, reopening and explicit acceptance retain existing versioned rules.

## Architecture gate

- **Application:** `FoodQueryInterpretation` preserves the baseline parse, closed discovery decision, tentative component slices in UTF-16 coordinates, main preparation, safe automatic quantity and review-only count suggestion. `FoodAmountTextParser` reuses existing numerical guards. Neither supplies source facts or nutrition.
- **Orchestration:** existing `GenericFoodSearching` and `FoodSearchEnriching` ports remain. Request interpretations cannot be supplied for a different original text. The remote value keeps only displayed terms as stored fields; no capture evidence, ledger/history, credentials or SDK objects cross it.
- **Infrastructure:** OFF and Gemini apply shared eligibility. Their transport, identity binding and nutrition admission contracts remain closed. Manufacturer and recipe source-admission parsers are unchanged.
- **Presentation:** the Foundation-only nutrition projection lives in Application and uses existing intake totals; SwiftUI renders ordinary native grouped forms, system fonts/colours and disclosures. No arithmetic or source conversion is added to the view.
- **Invariants:** identity/provenance/unit rules, unknown metadata, five-nutrient search coverage, `food_confirmation_v3` and persistence schemas remain unchanged. No platform NLP SDK or speculative proposal-provider abstraction is added.
- **Contracts:** frozen quantity compatibility; bounds/component/Unicode/sign controls; scalar fields; request copies; actual synthetic OFF/Gemini adapters; provider availability; query cancellation and selection; reference/consumed basis, unknowns/bounds/estimates; save/reopen; native light/dark/large-text capture.

## Validation and limits

Measured results and exact-source artifacts are recorded in the primary checkout under `Tools/LocalHybridSearchEvaluation/diagnostics/food-input-implementation-v1/`. The 42-case eligibility panel is exposed, author-reviewed development evidence. It is not independent gold or a measurement of full entity/attachment accuracy. The 511-case gate establishes numerical/parser compatibility, not representative source or user quality.

Native captures use bundled food candidates and synthetic intake. Rendering/OCR, simulator tests and static analysis do not establish physical-device, VoiceOver, live-source or user acceptance. The reported “ounces results” have not been independently reproduced as a provider/conversion defect. These changes do not add food coverage. No commit, push, PR, merge or TestFlight distribution is part of this implementation phase.
