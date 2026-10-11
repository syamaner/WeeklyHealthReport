# Build 21 device feedback and search repair

The user reports installing TestFlight 0.1.1 (21) and trying scallion pancake and Fat Daddy fried chicken through Review web nutrition. Neither produced useful results. The English Fat Daddy screenshot shows USA/Philippines sources with no recommended source. A later Taiwan query screenshot shows capture from health.ettoday.net with no accepted proposals. The exact original spelling, later query, ETtoday URL, captured bytes and provider response remain unavailable; no exact extraction failure has been diagnosed from the screenshot alone. This is device failure evidence, not acceptance.

## Architecture and implementation

Market context belongs in presentation request orchestration; it is explicit, optional, visible, and sent with the food terms throughout discovery, extraction and applicability. Changing it cancels the request and invalidates results and alternative source leads. Default Unspecified preserves the user's market ambiguity. Taiwan and United Kingdom are offered; other markets can be included in the food description.

Nutrition retrieval intent belongs in the OpenRouter infrastructure adapter. The adapter adds nutrition/calorie/protein/serving search terms; native Chinese nutrition terms are added only for an explicitly named Taiwan market. Original food terms remain the extraction/applicability input. No brand alias, food equivalent, cut, portion weight or nutrient is inferred by the suffix.

Presentation now distinguishes an empty extraction from proposals rejected by literal source checks. Rejections explain identity, serving basis, nutrient or quote failures. Empty extraction describes possible causes as uncertainty and offers source inspection. Domain binding, admission and confirmation policies are unchanged.

## Bounded exposed search observations

Ten calls, no retries, all costs known: **$0.073381500**. Plans, request hashes, raw responses, generation IDs and individual costs are retained under `/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-device-search-20261004`, `nutrition-device-search-intent-20261004`, and `nutrition-device-search-controls-20261004`. Only the established private credential loader consumed credentials.

* English Fat Daddy reproduced the three wrong-country sources from the device. Taiwan market found the Taiwan brand, but menus/locations supplied no demonstrated usable nutrition. Nutrition-specific Taiwan search still returned menus/locations. Retain this unresolved outcome.
* Plain scallion pancake found recipes/Wikipedia. Taiwan market alone found restaurants/travel material. Nutrition-specific Taiwan search found an explanatory article and two manufacturer pancake pages. These are capture leads, not verified cooked-dish equivalents; frozen/packaged variants may be unsuitable.
* Arla Cravendale whole milk UK retained the exact primary product page after adding nutrition intent.
* Mutti finely chopped tomatoes UK changed from retailer-only leads to the primary Polpa page plus a retailer. Titles/URLs indicate retrieval relevance only; exact-market nutrition still requires capture and applicability review.

These are exposed development probes, with one observation per query/arm and no statistical superiority claim. Search metadata is not nutrition accuracy evidence. No extraction/applicability calls were made in this diagnostic search experiment, and no end-to-end success is claimed.

## Remaining boundary

The changes are local and uncommitted and are absent from already installed build 21. No new build upload is performed. Fat Daddy lacks a demonstrated usable source in these observations. The exact ETtoday source is needed to separate missing evidence from capture, extraction or binding failure. Independent nutrition/calibration and successful physical-device review/save/reopen remain open.

## Validation

Full FoodLedgerKit run: 698 cases, six optional skips, no failures. After narrowing Chinese search vocabulary to explicit Taiwan requests, final focused provider/presentation tests: 37 passed. Complete simulator app suite: 317 passed, one expected opt-in skip. Xcode static analysis and diff whitespace checks passed. Final four changed source/test hashes and all validation logs are retained in `nutrition-device-search-20261004/repair-validation.json`. No new upload or physical acceptance is claimed.

## Full workflow reproduction and manual source inspection

At the user's request, ran the revised queries and chose actual returned sources rather than waiting for the unavailable ETtoday URL. Retained evidence: `/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-device-workflow-20261004`.

* Fat Daddy Taiwan: two provider calls; source selection abstained. Manually captured the first offered FonFood menu (81 text blocks). It has prices and descriptions, with no nutrition declaration in captured text. This supports a source-availability failure on this observation; it does not establish that no useful Fat Daddy source exists anywhere.
* Scallion pancake Taiwan: four provider calls; selected `https://www.tenyufoods.tw/product_detail/18/`, captured and bound its per-100g manufacturer panel, then passed Luna applicability. Source declares energy 253kcal, protein 7.9g, carbohydrate 47.1g, fat 3.7g and sodium 332mg; fibre stays unknown. This is a manufacturer product proposal requiring human review, not proof of equivalence to a street-vendor pancake or added egg/cheese.
* Manually captured `https://hlife.tw/article/scallion-pancake-and-flaky-scallion-pancake`, then used two calls for Grok extraction and Luna applicability. Three proposals bound without rejections. The generic table has protein/carbohydrate/fat/fibre/sodium but no declared energy; energy stayed unknown. Two branded energy-only proposals remained separate. The generic table was suggested for review. This confirms that the generic parser can preserve partial nutrition from this article; no independent correctness/calibration or original ETtoday success is claimed.

New calls: **8**, all reported costs known, **$0.075755175**. Earlier search diagnostics remain separate ($0.073381500). No provider retry occurred. The first wrapper stopped after the first completed case because of an accounting-helper name error; its existing receipt was recovered offline and only the unattempted second case ran. Both frozen inputs and original/recovery scripts are retained. No production code changed or build was uploaded in this phase.

## Current search logic and review findings

1. The harness retains food terms and an explicit optional market; it does not infer the user's location, brand alias or consumed quantity.
2. OpenRouter's Exa plugin retrieves three results from the adapter's nutrition-intent query. Luna returns native citation leads. Extraction and applicability receive the original food description plus chosen market, without the retrieval suffix.
3. A separate Luna call chooses a lead using title, URL and excerpt. The current instruction requires an exact primary source and rejects retailer/aggregator sources. This may prevent useful representative secondary sources from reaching capture; it is a policy limitation to review separately, not evidence that the parser cannot read them.
4. One selected page is captured by the generic bounded HTML/text/PDF adapter. Grok proposes structured identity/basis/nutrients with literal quotations; domain binding checks these against the capture. Missing values remain unknown.
5. Luna independently checks applicability. A successful suggestion still requires explicit human review, match scope and quantity before saving. A failed or absent check prevents confirmation.
6. The orchestration captures one selected source; it does not automatically try all leads or refine/repeat search after failure. Alternative leads can be tried manually in the harness.

Priority review topics: distinguish branded exact-product discovery from representative dish discovery; search for a nutrition-bearing declaration rather than menu relevance; make abstention reasons observable; define a bounded follow-up search/capture strategy; measure source acquisition, binding and applicability separately. Retain conservative unknowns and food/market/preparation identity. UX redesign remains deferred as requested.

## Subsequent source policy refinement

The earlier primary-only selection described here is historical. See [source policy v2](generic-food-search-policy-v2-20261004.md) for representative generic-dish sources, bounded two-source fallback, retained evaluation failure and current validation.
