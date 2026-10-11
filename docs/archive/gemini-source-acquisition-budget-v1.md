# Gemini source-acquisition budget proposal v1

Status: explicitly approved by the user on 30 September 2026: one Gemini call plus at most three source-page HTTPS attempts, redirects included. This authorises bounded runtime composition; it does not authorise paid live evaluation spend.

## Concrete proposed normal-search stage

When local/OFF results remain insufficient, automatic Gemini is explicitly enabled and BYOK has been validated, permit one Gemini grounded discovery request using displayed food terms only. Select at most one native-cited source lead. Independently acquire that source through at most three HTTPS attempts total, including up to two redirects. Every destination must match the composition-owned exact-host admission list. No additional Gemini extraction request, retries, alternate-page fetching or per-keystroke calls.

The Gemini request retains its existing 30-second limit. Source acquisition has a separate 20-second whole-operation deadline, seven-second pacing and 2 MB raw HTML per response (with a separate 500 KB table-projection limit); the composed stage must therefore end within 50 seconds and cancel when its search run ends. Local results remain usable. Acquisition failure or unsupported source content leaves existing results available and does not start a different source attempt. Only independently captured table declarations that pass versioned value/unit/basis binding can proceed to candidate review; product/preparation identity and save eligibility remain separate.

## Approval boundary

Issue #148 still preserves the one-request budget for providers other than OFF. The earlier approved relaxation was specifically one OFF discovery plus two detail requests. The user has now separately approved the source HTTP reads after Gemini discovery. The proposed ceiling is one Gemini call plus three source HTTP attempts, not four Gemini calls.

## Historical foundations through v60

The existing unified-food-search worktree contains `HTTPSFoodSourcePageAcquirer`, `HTMLFoodSourceTableProjector`, `FoodSourceDocumentDecoder` and the application-owned `FoodSourceNutritionBinding`. They are not wired into automatic search. v56 proves request/redirect/pacing/size/deadline/cancellation boundaries using URLProtocol, and preserves source-table coordinates and declared values through HTML projection and binding. It does not prove live reachability or new food-search recall.

Validated acquisition/binding foundations through v58: 388 package tests (one optional skip), 279 simulator tests and static analysis. The v59 actual-HTML replay then exposed the raw-size issue: Alpro is 1.46 MB. v60 separates the raw HTML and projection ceilings and recovers its exact four macros from the saved page. Request count, timing and source admission remain unchanged; final v60 gates are recorded in its evidence folder. No source/Gemini calls, keys or new provider charges.

This approved runtime policy allows composition and synthetic integration within the stated ceilings. A paid live evaluation still needs its own frozen corpus and remaining call/cost budget.

## Current implementation status (v73)

The approved limits are now wired into default-off automatic search with exact-session validated BYOK. Alpro, Arla and Oatly UK are the reviewed candidate adapters. See [delivery readiness](unified-food-search-delivery-readiness-v1.md) for the local evidence, gaps and device checklist. The foundation paragraph above describes v60, not current wiring. No new live-evaluation budget is granted.
