# Untouched truth drafting, Taiwan (decision A, phase 2, #255)

Status: **draft, owner verification pending.** No drafted value is committed; the drafts, raw response bodies, journal and review sheet are outside the repository under `~/WHR-label-eval-private/drafts/untouched-taiwan-v1/`. No route reads that folder.

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
