# Prospective OpenRouter food evaluation — 4 October 2026

The new holdout does **not** pass its predeclared qualification gates. The OpenRouter route runs without Gemini, but source applicability and generic unit handling need repair before treating this implementation as ready for delivery. The successful earlier development runs remain valid historical observations; they did not predict this result.

## Results

| Measure | Result |
| --- | --- |
| Fixed public source cases | 24: eight Taiwan-market, eight local UK, eight general pantry/product cases |
| Public sources captured | 20/24 (83.3%); four failures retained |
| Extraction requests completed | 20/20; no retry or replacement |
| Fully correct review outcome on captured sources | 13/20 (65%); required at least 90% |
| Fully correct review outcome including capture failures | 13/24 (54.2%) |
| Correct partial nutrition panels | 10/14 answerable captured sources; 10/24 original cases (41.7%) |
| Correct abstention/clarification | 3/6 expected abstentions |
| Preferred claims correct for requested food and basis | 46/61 (75.4%) |
| Required declared fields recovered | 46/64 (71.9%) |
| Unknown slots preserved in correct-context answers | 14/20 (70%); no invented known values in expected-unknown slots |
| Search: matching primary product/market source, first or any of three leads | 4/6 (66.7%); required at least 80% |
| New OpenRouter requests and reported cost | 26 calls, all costs known: $0.584324675 |

The 15 claims excluded from precision come from three preferred proposals that did not satisfy the requested identity, exclusion or basis. They are **not 15 fabricated source numbers**. All 46 declared fields in the ten fully correct partial panels match their reference values. The unknown-preservation denominator retains answerable cases whose proposals were blocked; missing answers are not counted as preserved unknowns.

No entries were saved and no physical-device acceptance was performed. A bound, preferred proposal here means it could reach explicit review under the existing preference guard; it does not mean it was automatically admitted.

| Slice | Planned | Captured | Correct review outcome | Correct partial panel |
| --- | ---: | ---: | ---: | ---: |
| local_uk | 8 | 7 | 5 | 4 |
| taiwan_market | 8 | 6 | 4 | 3 |
| general | 8 | 7 | 4 | 3 |

## Actionable findings

1. **Enforce query applicability separately from literal binding.** The model preferred the sesame-peanut panel although the query excluded sesame/other flavours. It also preferred an Alpro per-100ml panel for a per-100g request. Alpro retained the correct ml label; this was a requested-basis mismatch, not a false density conversion. A third case selected a product despite a brand spelling mismatch. That spelling error originated in the authored test query and was declared as an ambiguity control before inference; it must not be portrayed as a measured frequency of user typos. All three candidates passed literal binding.

2. **Extend unit representation at the generic contract boundary.** Belazu prints “100mls”, which the current boundary rejects. Merchant Gourmet prints a single row “Energy kJ/kcal | 624/148”; the model extracted the correct 148 but the binder rejected it. These are general syntax gaps, not reasons to add website adapters.

3. **Prevent one unsupported field from losing a useful partial panel.** Mutti and Jolly Time use a “Calories” label without a literal kcal token. The frozen contract requires an explicit canonical unit; their energy gold therefore stays unknown, with the source declaration retained in the review notes. Grok nevertheless declared the energy, causing candidate rejection; Jolly Time also preferred clarification. A future version may explicitly support this representation or preserve a reviewed partial result, but must not silently relax binding or overwrite source facts.

4. **Qualify search and acquisition separately.** For Cathedral City, all three search leads were retailers; the first two described a different chilled recipe, while the third matched the frozen variant but failed the current primary-source criterion. Search found a primary source on 4/5 non-typo queries; the original six-case denominator is retained. This was discovery-only testing, not a fresh measurement of source choice, capture and extraction in one tap.

Capture failures: SunnyHills returned HTTP 200 with no readable text in the response; Barilla returned 403; the Agric URL returned 404 despite appearing in web-search results; Biona triggered `capture_responseTooLarge`. The Biona raw response was about 1.23 MB, so the error alone must not be described as exceeding the 3 MB raw HTML cap; the bounded projection has additional limits. None was replaced.

## Method and limits

The 24 public URLs, query order, gates and cost rules were written before capture. Gold was reviewed from retained raw HTML and projected blocks before any new inference. The brand-spelling ambiguity was corrected in a retained pre-prediction reference amendment; the original query and draft remain unchanged. Aliases, values, unknowns and acceptable bases were then frozen with executable, source, prompts, schema and evaluator hashes. No model, prompt, source or gold was changed after observing predictions.

The mechanical holdout gate checked all 33 retained Swift frozen development plans (301 planned case instances), including unattempted cases. No candidate overlap was detected. Six external search/selection/workflow experiments were also checked; their queries already occur in that history. The checker now preserves query/family exposure for 18 historical discovery cases with unknown domains and derives domains from captured URLs, including redirect hosts. These repairs have regression tests.

This is agent-reviewed prospective evidence, not independent human acceptance or calibrated confidence. Sources were purposively located with web search, not sampled from a user-query population. The general slice is mostly UK pantry products plus Canadian/US products; it is not a world-market sample. Brand/product families and source hosts are new relative to the checked history, but broad ingredients can overlap prior foods. Older Gemini/Python exploration and the unretained-runtime pilot are not fully certified by the mechanical format. Hidden model-training exposure is unknown. All 20 captured sources were HTML; this run provides no fresh PDF/OCR coverage.

The existing closed literal-unit contract is scored explicitly: kJ, bounded values, salt-only declarations and noncanonical units are not inferred into known target values. Source declarations that cannot be represented are retained in reference notes. Merchant Gourmet’s explicitly paired kJ/kcal header remains a required 148 kcal reference despite the current parser limitation. Thus this measures the declared application contract, not complete recovery of every scientifically interpretable nutrition label.

## Cost, latency and verification

Extraction cost was $0.540802 for 20 requests, with median request latency 15.08s and p90 25.82s. Search cost was $0.043522675 for 6 requests, median 3.59s and p90 4.92s. These timings cover provider requests, not end-to-end UI or user review.

Cumulative recorded scopes now contain 387 requests, 381 known charges totalling $3.415415425, plus 6 historical unknown charges. The new run adds no unknown cost. These are reported costs, not an account balance or prepaid cap.

Main was refreshed and documentation-only PR #183 integrated to `79efe83526668e47608e33cbf00655638c2d4826` before freezing. The production Swift code and route configuration remain unchanged from the final combined simulator/static-analysis gate. Comparing the 314-file prior source index found only the two holdout-audit Python files changed. The current evaluation-tool suite passes 112 tests; the Swift probe build and `git diff --check` pass. No simulator suite was repeated for this evaluation-only change. All nutrition work remains uncommitted; the shared dirty checkout is preserved.

## Case ledger

| Case/source | Slice | Frozen expected result | Observed outcome |
| --- | --- | --- | --- |
| [tiptree-conserve](https://www.tiptree.com/collections/all-products/products/tiptree-strawberry-conserve) | local_uk | select_partial | Pass |
| [sunnyhills-pineapple](https://www.sunnyhills.com.tw/product) | taiwan_market | acquisition_unavailable | proposal_invalidDocument |
| [barilla-spaghetti](https://www.barilla.com/uae/products/pasta/classic-blue-box/spaghetti) | general | acquisition_unavailable | capture_unavailable |
| [belazu-harissa](https://belazu.com/shop-all/rose-harissa/) | local_uk | select_partial | No usable answer: invalidBasis |
| [zenweixiang-pork-paper](https://www.zenweixiang.com/page/product/show.aspx?lang=TW&num=1127) | taiwan_market | abstain | Preferred proposal contradicts reference |
| [mutti-polpa](https://mutti-parma.com/can-en/products/polpa/) | general | select_partial | No usable answer: invalidNutrient |
| [greenblacks-dark](https://www.greenandblacks.co.uk/green-black-s-organic-dark-70-chocolate-90g-bar.html) | local_uk | select_partial | Pass |
| [lyb-aiyu-seed](https://www.lyb189.com.tw/product_info.php?pid=866) | taiwan_market | select_partial | Pass |
| [sacla-basil-pesto](https://www.sacla.co.uk/products/sacla-classic-basil-pesto) | general | select_partial | Pass |
| [meridian-peanut](https://shop.meridianfoods.co.uk/products/meridian-smooth-peanut-butter-no-salt-280-g) | local_uk | abstain | Pass |
| [pcfarmer-plum](https://www.pcfarmer.tw/ec99/rwd1816/product.asp?prodid=d022) | taiwan_market | select_partial | Pass |
| [silverspoon-sugar](https://www.silverspoon.co.uk/our-products) | general | abstain | Pass |
| [cathedral-cauliflower](https://www.cathedralcity.co.uk/en/our-cheese/frozen/cauliflower-cheese) | local_uk | select_partial | Pass |
| [kaohsiung-peanut-brittle](https://shop.mjac.moj.gov.tw/13/_pages/product/show.php?kind=47&num=31) | taiwan_market | abstain | Preferred proposal contradicts reference |
| [hartleys-strawberry-jelly](https://www.hartleysfruit.co.uk/our-range/hartleys-jelly/hartleys-no-added-sugar-jelly-pots/hartleys-no-added-sugar-strawberry-jelly-pot/) | general | select_partial | Pass |
| [merchant-puy-lentils](https://www.merchant-gourmet.com/collections/pulses-grains/products/puy-lentils) | local_uk | select_partial | No usable answer: invalidNutrient |
| [agric-dried-pineapple](https://www.agric.tw/products/%E8%80%98%E9%84%89%E5%A5%BD%E6%9E%9C-%E9%B3%B3%E6%A2%A8%E4%B9%BE) | taiwan_market | acquisition_unavailable | capture_unavailable |
| [jollytime-popcorn](https://www.jollytime.com/popcorn-products/microwave-classics/simply-popped-sea-salt/) | general | select_partial | No usable answer: invalidNutrient |
| [biona-chickpeas](https://biona.co.uk/products/biona-organic-chickpeas) | local_uk | acquisition_unavailable | capture_responseTooLarge |
| [chishya-mullet-roe](https://www.chishya.com.tw/products/%E4%B8%80%E5%8F%A3%E5%90%83%E7%83%8F%E9%AD%9A%E5%AD%90-68d74d98a10109a7.html?path=%2Fcategories%2F%E7%83%8F%E9%AD%9A%E5%AD%90%E6%B2%B9%E9%AD%9A%E5%AD%90%E9%A1%9E) | taiwan_market | abstain | Pass |
| [alpro-vanilla-custard](https://www.alpro.com/en-gb/products/desserts/deliciously-dairy-free-custard) | general | abstain | Preferred proposal contradicts reference |
| [baxters-beetroot](https://www.baxters.com/products/sliced-beetroot) | local_uk | select_partial | Pass |
| [taiguang-mushroom-meatballs](https://www.taiguang.com.tw/products/mushroommeatballs) | taiwan_market | select_partial | Pass |
| [whitworths-coated-raisins](https://whitworths.co.uk/product/favourites-yogurt-coated-raisins/) | general | select_partial | Pass |

## Reproduction and next gate

Fix query applicability and unit handling under explicit versioned contracts. Keep these 24 cases as exposed regression evidence, then reserve different untouched families/domains for the next qualification. Do not turn repairs on these same cases into a new independent-accuracy claim. Any optional Jev or second-stage verification must be evaluated as a separately frozen route with its extra cost and failure modes; these results do not establish that it would help.

Evidence root: [holdout-20261004-v1](</Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/holdout-20261004-v1>)

- [Frozen protocol](</Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/holdout-20261004-v1/protocol.json>)
- [Source-reviewed references](</Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/holdout-20261004-v1/source-references-v2.json>)
- [Result and per-case diagnostics](</Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/holdout-20261004-v1/result.json>)
- [Exposure supplement](</Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/holdout-20261004-v1/exposure-supplement.json>)
- [Cost inventory](</Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/holdout-20261004-v1/cost-inventory.json>)
- [Frozen extraction plan](</Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/holdout-20261004-v1/extraction-run/plan.json>)
- [Frozen search plan](</Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/holdout-20261004-v1/discovery-run/plan.json>)
- [Local recomputation script](</Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/holdout-20261004-v1/summarise_holdout.py>)

The result can be recomputed with `python3 -B summarise_holdout.py` at its recorded local path after both retained runs complete. It verifies frozen plan/source hashes and completion output receipts. The raw source review and source-finding adjudication remain agent-reviewed inputs, not automated proof of source truth.
