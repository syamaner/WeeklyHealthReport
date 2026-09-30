# Captured recipe nutrition and named servings v1

This extension implements the user-approved recipe source adapter and explicit alternative-selection flow. The first reviewed recipe is Auntie Emily’s Kitchen’s Taiwan Night Market Steak. It is a representative home recipe, not verified nutrition for a vendor plate. Captured development evidence is in the primary checkout’s `Tools/LocalHybridSearchEvaluation/diagnostics/taiwan-live-v2/` and `taiwan-swift-recipe-v1/`.

## Architecture and admission

- `FoodSourceRecipeProfile` is application-owned source evidence v1. It carries raw HTML SHA-256, recipe identity/pointer, source yield, named serving, four declared macros, JSON pointers and versioned HTML node positions. Its cooked gram weight is unknown.
- `WPRecipeSourceParser` is an infrastructure adapter for one JSON-LD Recipe and one matching WP Recipe Maker card. Duplicate JSON keys, multiple recipes/cards, wrong name/record/yield, missing serving basis/macros, hidden content, wrong labels/values/units and conflicting declarations are unsupported. It never executes JavaScript, fetches assets, computes ingredients or infers serving weight.
- `FoodReviewedSource` carries recipes separately from per-100-g/mL table panels. Existing table binder and domain schema remain unchanged.
- `AuntieEmilyRecipeCandidateAdmission` accepts only `https://auntieemily.com/taiwan-night-market-steak/` without query/fragment changes. It recomputes the profile before trusting the review, requires exact profile equality and rejects other hosts, paths and unrelated foods/brands/descriptors. Noodle/pasta spelling at retrieval is an explicitly labelled recipe alternative. Ingredient wording, preparation and proportions are not asserted as the user’s recipe.
- `GroundedFoodSourceCandidateAdmission` composes this adapter and the unchanged manufacturer adapters at the composition root. The reviewed host is added to acquisition; arbitrary recipe hosts remain unsupported. One native-cited source job and three HTTPS attempts including redirects remain the runtime budget. No additional Gemini extraction call exists.

The exact frozen food-record discovery prompt v2 is now used by the Gemini discovery adapter. Its generated nutrient prose remains untrusted. The prior live comparison found prompt-compliance/attribution failures, so no number from that prose enters a candidate. No further live request was needed for this implementation.

## Explicit selection and quantity

Source recipe declarations use the already-supported domain `.named("1 recipe serving", 1 count)` basis. This is a source-defined serving, not a food piece, measured cooked weight, density or universal portion guide. Recipe yield describes the full source recipe; it is not the amount the user ate.

`FoodNamedServingPolicy` v1 permits direct count/fraction input only for the closed recipe schema with matching retained recipe provenance. All other count quantities still need their existing measured conversion. Recipe candidates begin with an empty quantity even if the food query contains a count or gram amount. Changing between recipe and other candidates clears the amount and acceptance. Merged search results retain mandatory closest-match explanation.

The user must explicitly select the representative recipe, explain why it is acceptable and enter source recipe servings eaten, e.g. 0.5. Gram/mL quantities, plate weights, direct edible weight and conversions are rejected for this unweighed recipe basis. No cooked gram yield is inferred. If the user only has a weighed vendor portion, this source cannot convert it to nutrition; choose a measured-basis source or leave unresolved.

`FoodConfirmationPolicy` is versioned to `food_confirmation_v3` for this narrow recipe-estimate exception. Exact-product unknown identity still blocks save. Unknown recipe preparation, bone, skin, drained state, packing medium and fortification stay unknown. Only four source macros are populated; remaining nutrients stay not declared. Source-based nutrition is displayed as an estimate.

Existing persistence/summary types already support named/count basis. Save/reopen preserves source values, source serving basis, raw hash, JSON/HTML references, user explanation and fractional count. No count-to-mass conversion record is fabricated. Independent user edits version the consumed amount without rewriting the source recipe.

## Evidence and limits

The Swift replay uses the exact retained 303,536-byte steak page and the registered synthetic source cases. Store contracts run both in-memory and GRDB adapters. Presentation tests verify empty input, explicit acceptance, fractional preview and missing-weight guidance. Manufacturer mass/volume contracts and retrieval gates remain required.

This first adapter has one exposed real positive and authored negative controls. It is not a broad recipe parser, held-out quality proof, current vendor validation or device acceptance. FCDC oyster-omelette prose, BodyPal’s secondary bubble-tea table, Fat Daddy partial calories and pancake recipe mismatch still require separate source contracts. No additional source permissions or nutrients are inferred from those pages.

Changes are local until separately published. TestFlight build 14 does not contain this adapter or the prior local Taiwan input repair. Device checks after a future release: search the steak meal with enabled/validated BYOK; review the source recipe differences; confirm no portion prefill; explicitly accept an alternative; enter 0.5 source servings; save/reopen; verify grams cannot be silently treated as source servings; verify ordinary count foods still request measured conversion.
