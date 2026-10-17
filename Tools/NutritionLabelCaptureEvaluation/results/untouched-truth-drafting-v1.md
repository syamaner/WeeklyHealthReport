# Untouched truth drafting, Taiwan (decision A, phases 2 and 3, #255)

Status: **rounds 1 and 2 owner-verified (17 October 2026); 40 usable untouched tables.** The verified records are committed as [`fixtures/ground-truth-off-taiwan-untouched-v1.json`](../fixtures/ground-truth-off-taiwan-untouched-v1.json), evidence label **model-drafted, owner-verified (no owner corrections)**, pinned by hash in the contract. Drafts, raw response bodies, the journal and the review sheet stay outside the repository under `~/WHR-label-eval-private/drafts/untouched-taiwan-v1/`. No route reads that folder or the truth; routes A, B and C have still not run on any untouched photo.

## Owner verification, round 1 (phase 3)

The owner checked all 40 untouched photos in a private review page on 17 October 2026, each photo beside its draft: every drafted value, serving line and table decision.

- **527 of 527 cells confirmed, with no corrections.** Because nothing was corrected, **anchoring on the draft cannot be ruled out**: a value accepted because the draft showed it looks the same as one confirmed independently. The evidence label says so ("no owner corrections"), and this is weaker than an independent human transcription.
- **Table decisions:** the 11 proposed exclusions were agreed (orders 25, 38, 39, 40, 44, 46, 50, 52 and 54 are not Traditional Chinese tables; 28 and 48 have no nutrition table); order 23 (drafting failed on length) is excluded; **order 34 was kept**: Qwen had proposed excluding it as a US-style bilingual English and Traditional Chinese label, and the owner counts it as a Taiwan label.
- **Merge:** the answers were written into `review.csv` through the existing merge (`merge_owner_entries`, after copying the sheet aside): 539 owner entries, the 527 cells plus 12 table decisions that have a sheet row (order 23 has none).
- **Truth file:** 38 records, 27 usable tables (434 scored cells) and 11 exclusion records; 0 required declines. Twelve drafted values that are not printed amounts (ten reference-intake cells printed as `*`, and order 53's sodium values, obscured on the pack) are kept as unscored cells, never as values.
- **What the page did not show:** parent rows and nutrient keys. Parentage is therefore structural: a draft parent naming the row itself or a row absent from the table is cleared (188 cells; Qwen mostly recorded a top-level row as its own parent). Nutrient keys and bases were checked mechanically against the printed labels and headers, and every printed label maps to one key. This is recorded as a deviation in the contract.

## Refills (decision B, phase 3)

Twelve untouched photos were excluded (the 11 agreed plus order 23), so refills were downloaded in hash order from order 63 (CC BY-SA 3.0, revision pinned, recorded in the manifest with attribution and a per-order reason, written read-only to the sealed folder). Three refills were themselves proposed for exclusion by their drafts and replaced by the next order at once, as the owner allowed: 66 (Thai) by 75, 71 (Simplified Chinese) by 76, and 75 (English) by 77. Those three exclusions await the owner's round-2 confirmation.

| Batch | Orders | Replaces | Bytes |
|---|---|---|---:|
| 1 | 63 to 68 | 23, 25, 28, 38, 39, 40 | 2,758,088 |
| 2 | 69 to 74 | 44, 46, 48, 50, 52, 54 | 1,855,753 |
| 3 | 75, 76 | 66, 71 | 992,562 |
| 4 | 77 | 75 | 170,265 |
| **Total** | 15 photos | | **5,776,668** (10 MB hard stop) |

The untouched set is 40 photos again: orders 21 to 60 less the 12 exclusions (28, including 34), plus 63, 64, 65, 67, 68, 69, 70, 72, 73, 74, 76 and 77.

## Round 2 drafting (phase 3)

Same contract-bound route as round 1 (`qwen/qwen3.5-397b-a17b` on `deepinfra/fp8`; catalogue checked on the day: image input, ZDR endpoint "DeepInfra | qwen/qwen3.5-397b-a17b-20260216", $0.45 / $3.00 per million prompt / completion tokens, unchanged), with the persistent spend ledger. Every response reported the requested model and provider.

- **Refills 63 to 77:** instruction v1 unchanged. Twelve are proposed usable; 66, 71 and 75 are proposed exclusions (refilled as above).
- **Order 34:** drafted with a bilingual instruction, recorded as a deviation. The minimum change is one clause in the `taiwan_nutrition_label` bullet. The first wording (v1.1: a bilingual table that prints Traditional Chinese beside English counts, transcribing its Traditional Chinese labels and headers, and each value as printed) was sent once and Qwen still proposed an exclusion because the values carry English units and the layout is US style. v1.2 adds "in a Taiwan or a US layout and whether its units are printed in Chinese or in English (g, mg, mcg)". Under v1.2 Qwen transcribed the table (30 cells, with the Traditional Chinese labels beside the English ones, 6 uncertain) but still labelled it `other_language_nutrition_table`; the owner's keep decision stands, and the round-2 page asks for every value. Both earlier drafts and raw responses are kept aside, not used.
- **Spend:** 17 calls, **$0.0651708** reported (round 1 was $0.14616675 over 40 calls; drafting total $0.21133755 over 57 calls).

## Owner verification, round 2 (phase 3)

The owner reviewed the 16 round-2 cases on 17 October 2026: **268 of 268 cells confirmed, with no corrections** (the same anchoring caveat applies), and the refill exclusions 66, 71 and 75 agreed. For order 34 the owner confirmed Qwen's printed values as drafted, including 熱量 "100" printed with no unit; that value is kept exactly as printed as an unscored, ungradable cell, and no unit is inferred. The draft had left "Sodium/鈉" unrecognised; the agent's mechanical check maps it to sodium (its Traditional Chinese part is exactly the closed row name 鈉), recorded in the record and not owner-verified. The owner's round-1 keep decision for order 34 was applied to its new draft's table decision.

The truth file now holds **40 usable tables** (654 scored cells, 22 unscored cells) and 14 exclusion records, with no required declines, evidence label "model-drafted, owner-verified (no owner corrections)", and its hash is re-pinned in the contract. Order 34's draft records its language as `en` (Qwen's reading of the primary language); it is kept as drafted.

## Phase 2 record

## What ran

- **Inputs:** the 40 untouched Open Food Facts Taiwan photos (orders 21 to 60), read from the read-only sealed folder after a hash-bound `--unseal-for-drafting`. This opening is the set's **unsealing for truth purposes only** (17 October 2026). Routes A, B and C have still not run on these photos and may not before the single frozen untouched run.
- **Not run:** the 40 sealed UK v2 images, which were never acquired. UK untouched set deferred by the owner on 17 Oct 2026; acquire a fresh sealed UK set only if Taiwan results justify it. Until then no promotion decision for UK label photos.
- **Model:** `qwen/qwen3.5-397b-a17b` (Qwen 3.5, natively multimodal; OpenRouter lists no separate Qwen 3.5 VL model) on endpoint `deepinfra/fp8` (provider DeepInfra). Catalogue check on the day: image input advertised; listed among OpenRouter's ZDR endpoints; structured outputs supported; $0.45 per million prompt tokens and $3.00 per million completion tokens. Every response reported model `qwen/qwen3.5-397b-a17b` and provider DeepInfra.
- **Request:** `openrouter/truth-drafting-instruction-v1.txt` with the image, strict `json_schema` output (`openrouter/truth-drafting-wire-schema-v1.json`, no unions), the route C provider block (`only` and `order` set to `deepinfra/fp8`, no fallbacks, parameters required, data collection denied, ZDR), 4096 output tokens, temperature 0, reasoning disabled, no tools, no retries, no streaming.
- **Key:** read from the owner-approved dotenv file into the process only; never printed, logged or written. Saved raw files are response bodies only.

## Coverage

| | Count |
|---|---:|
| Photos requested | 40 |
| Drafted | 39 |
| Failed | 1 (order 23: `finish_reason` `length` at the 4096-token ceiling; no draft, not retried) |
| Proposed usable 營養標示 tables | 27 |
| Proposed exclusions (refill candidates) | 12 (10 `other_language_nutrition_table`, 2 `no_nutrition_table`) |
| Proposed required declines | 0 |
| Drafted cells | 446 |
| Cells listed as uncertain | 13 (model-marked, or a printed value that is not an amount such as `*` or `unknown`) |
| Serving lines listed as uncertain | 17 (mostly on the proposed exclusions) |

Every table decision is a **proposal**. If the owner confirms the 12 exclusions (and decides how to treat order 23), refills come from orders 63 onwards under decision B, each drafted the same way before any route sees it; the untouched minimum of 40 stays.

## Spend

Reported `usage.cost`, recorded in the persistent spend ledger shared with route C: **$0.14616675** over 40 calls (median $0.0043; largest $0.0130, the truncated call; no unknown-cost call). The ledger still holds back the 200-call sealed reservation ($10). Latency: median 27.8 s, largest 100.8 s. The 90 s limit is a socket read timeout, so one successful call ran past 90 s of wall-clock time; route C needs a total deadline before it is enabled.

## Owner verification

Open `~/WHR-label-eval-private/drafts/untouched-taiwan-v1/review.html`: each photo sits beside its drafted table, with uncertain rows highlighted; clicking the photo opens it full size. Record each check in `review.csv` (one row per cell, serving line and table decision): `owner_verified` yes, or the corrected printed text in `owner_correction`. The verified records become `model-drafted, owner-verified` truth, are frozen by hash in the contract, and only then can the untouched run be planned.

## Regeneration after review (17 October 2026)

The invariant review of PR #257 found that a value the mapper could not parse (such as `*` or `unknown`) was stored with invented defaults (decimal text `0`, unit `g`, and basis `per_serving` for an unknown header). The 39 drafts were re-mapped offline from the saved raw responses, with no new call (the ledger still holds 40 calls and $0.14616675). Such cells now carry a null comparator, decimal text and units, and an unknown basis; none of the 12 unparsed cells carries a value. The review sheet was regenerated. `review.csv` had no owner entries yet, so nothing needed merging; any later regeneration copies the old sheet aside and merges every non-empty owner entry.
