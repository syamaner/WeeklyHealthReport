# Route C on development photos (phase 3, #255)

Status: **development runs complete, 17 October 2026.** Ten arms ran across eight models, on development data only. No untouched or sealed photo, untouched truth or draft was read. Machine-readable summaries (aggregate counts and per-case flags only, no model answers) are in [`route-c-development-v1.json`](route-c-development-v1.json).

These are **development** results on exposed images, with the limits in plan section 3.5. The Taiwan development truths were drafted by Claude (the assistant, Claude Opus 5.5), so the Claude Opus 5.5 and Claude Fable 5.1 results on the Taiwan stratum carry a self-agreement caveat. The UK stratum's truth records no serving-size or servings-per-pack line, so serving conversions there are scored against per-serving headers only. The UK set has no untouched stratum (deferred by the owner), so no UK result can promote a route.

## Configuration (owner decisions of 17 October 2026, evaluation only)

- **Routing.** One pinned provider per model (`only` and `order`, no fallbacks, parameters required). ZDR and `data_collection: "deny"` are dropped for the evaluation and recorded as information only. Product routing is unchanged, and any product use would still need ZDR.
- **Limits.** 16384 output tokens, and a $0.20 per-call stop. The total stop is $65, of which 200 sealed calls are reserved at $0.20 ($40), leaving $25 for development. Before each arm, a credit gate checks the key limit and the account balance.
- **Requests.** One request per image through `openrouter_client`. Up to 5 attempts within 180 s, with exponential backoff and jitter that respects `Retry-After`. Content outcomes are never retried. Strict JSON schema, which carries a description and has `$comment` stripped. Every answer is validated against the wire schema.
- **Reasoning.** Each model ran with reasoning off and on where the endpoint allows. Grok 4.7, GPT-6.1 Sol, GPT-6.1 Sol Pro, Gemini 4 Argon, Claude Opus 5.5 and Claude Fable 5.1 answer HTTP 400 "Reasoning is mandatory for this endpoint and cannot be disabled". For them, reasoning off is **not available**, and nothing was substituted.
- **Models.** The latest in each family on 17 October 2026, all with image input:

| Arm | Slug | Release | Endpoint | USD per M in / out | ZDR endpoint exists (information only) |
|---|---|---|---|---|---|
| Luna | `openai/gpt-6-luna` | 2026-09-22 | `openai` | 0.10 / 0.50 | yes (Azure) |
| Luna Pro | `openai/gpt-6-luna-pro` | 2026-09-22 | `openai` | 0.10 / 0.50 | yes (Azure) |
| Grok | `x-ai/grok-4.7` | 2026-09-21 | `xai` | 2.00 / 6.00 | yes (`xai/zdr`) |
| Gemini 4 | `google/gemini-4-argon` | 2026-10-13 | `google-ai-studio` | 2.00 / 10.00 | yes (Vertex) |
| Sol | `openai/gpt-6.1-sol` | 2026-09-29 | `openai` | 2.00 / 10.00 | yes (Azure) |
| Sol Pro | `openai/gpt-6.1-sol-pro` | 2026-09-29 | `openai` | 2.00 / 10.00 | yes (Azure) |
| Opus 5.5 | `anthropic/claude-opus-5.5` | 2026-09-22 | `anthropic` | 4.00 / 20.00 | yes (Vertex) |
| Fable 5.1 | `anthropic/claude-fable-5.1` | 2026-09-01 | `anthropic` | 10.00 / 50.00 | none listed |

**Strata:**
- **Taiwan:** 20 Open Food Facts development photos (the plan's 22, less the two English-only exclusions).
- **UK:** 39 of the 40 local v2 development review images (one is excluded by the owner's review).
- **Muesli:** the owner's photo.

Every arm passed two fictional qualification labels before any real image.

## Results against the bars

Each cell shows numerator / denominator, and **fail** marks a missed bar. False-ready must be 0. Costs and latencies are per photo. The product ceilings are a median of $0.02 per photo and a p90 of 20 s.

### Taiwan (20 photos)

| Arm | Strict cells | Binding | Unit and basis | Full table | Serving conv. | Servings / pack | Correct decline | False-ready | Median USD | p50 s | p90 s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Luna, off | 207/214 | 229/238 **fail** | 214/214 | 11/15 **fail** | 123/123 | 15/15 | 3/5 **fail** | **4** | 0.0006 | 5.6 | 7.9 |
| Luna, on | 205/214 | 229/238 **fail** | 208/214 **fail** | 12/15 | 120/123 **fail** | 15/15 | 2/5 **fail** | **2** | 0.0008 | 10.8 | 15.9 |
| Luna Pro, off | 200/214 **fail** | 223/238 **fail** | 208/214 **fail** | 10/15 **fail** | 120/123 **fail** | 15/15 | 4/5 **fail** | **5** | 0.0010 | 6.9 | 8.7 |
| Luna Pro, on | 209/214 | 233/238 **fail** | 214/214 | 13/15 | 123/123 | 15/15 | 2/5 **fail** | **3** | 0.0019 | 14.6 | 21.8 |
| Grok, on | 213/214 | 237/238 | 214/214 | 14/15 | 123/123 | 15/15 | 3/5 **fail** | **1** | 0.0194 | 26.2 | 116.1 |
| Gemini 4, on | **214/214** | **238/238** | 214/214 | **15/15** | 123/123 | 15/15 | 3/5 **fail** | **1** | 0.0103 | 9.9 | 17.1 |
| Sol, on | 213/214 | 237/238 | 214/214 | 14/15 | 123/123 | 15/15 | 3/5 **fail** | **2** | 0.0094 | 15.2 | 18.5 |
| Sol Pro, on | 213/214 | 237/238 | 214/214 | 14/15 | 123/123 | 15/15 | 3/5 **fail** | **2** | 0.0262 | 18.6 | 23.3 |
| Opus 5.5, on | 202/214 | 226/238 **fail** | 202/214 **fail** | 13/15 | 114/123 **fail** | 15/15 | 3/5 **fail** | **1** | 0.0316 | 11.3 | 15.1 |
| Fable 5.1, on | 212/214 | 236/238 | 212/214 **fail** | 13/15 | 122/123 | 15/15 | 3/5 **fail** | **1** | 0.0866 | 13.1 | 20.0 |

### UK (39 images)

| Arm | Strict cells | Binding | Unit and basis | Full table | Serving conv. | Bounds | Correct decline | False-ready | Median USD | p50 s | p90 s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Luna, off | 253/311 **fail** | 262/325 **fail** | 253/311 **fail** | 14/22 **fail** | 7/116 **fail** | 9/11 **fail** | 5/17 **fail** | **2** | 0.0005 | 5.7 | 9.2 |
| Luna, on | 238/311 **fail** | 247/325 **fail** | 239/311 **fail** | 10/22 **fail** | 9/116 **fail** | 8/11 **fail** | 6/17 **fail** | **3** | 0.0009 | 10.8 | 23.4 |
| Luna Pro, off | 241/311 **fail** | 249/325 **fail** | 241/311 **fail** | 13/22 **fail** | 18/116 **fail** | 8/11 **fail** | 3/17 **fail** | **3** | 0.0011 | 6.9 | 9.5 |
| Luna Pro, on | 227/311 **fail** | 236/325 **fail** | 227/311 **fail** | 10/22 **fail** | 7/116 **fail** | 8/11 **fail** | 7/17 **fail** | **2** | 0.0020 | 18.8 | 50.3 |
| Grok, on | 225/311 **fail** | 234/325 **fail** | 226/311 **fail** | 10/22 **fail** | 16/116 **fail** | 8/11 **fail** | 5/17 **fail** | **2** | 0.0377 | 65.6 | 175.2 |
| Gemini 4, on | 269/311 **fail** | 279/325 **fail** | 269/311 **fail** | 13/22 **fail** | 33/116 **fail** | 9/11 **fail** | 3/17 **fail** | **6** | 0.0111 | 13.6 | 20.7 |
| Sol, on | 214/311 **fail** | 225/325 **fail** | 215/311 **fail** | 10/22 **fail** | 9/116 **fail** | 7/11 **fail** | 8/17 **fail** | **3** | 0.0122 | 16.5 | 31.0 |
| Sol Pro, on | 215/311 **fail** | 225/325 **fail** | 215/311 **fail** | 11/22 **fail** | 9/116 **fail** | 7/11 **fail** | 8/17 **fail** | **2** | 0.0268 | 20.3 | 40.1 |
| Opus 5.5, on | 194/311 **fail** | 204/325 **fail** | 194/311 **fail** | 9/22 **fail** | 15/116 **fail** | 7/11 **fail** | 4/17 **fail** | **3** | 0.0322 | 11.7 | 19.3 |
| Fable 5.1, on | 250/311 **fail** | 260/325 **fail** | 250/311 **fail** | 12/22 **fail** | 24/116 **fail** | 9/11 **fail** | 3/17 **fail** | **5** | 0.0960 | 16.6 | 28.1 |

### Muesli photo

All ten arms read the muesli table exactly:

- 18 of 18 cells;
- the full table;
- 9 of 9 serving conversions;
- the servings per pack;
- no false-ready result.

This includes the binding stress case, where the right-hand column is offset by a row. For comparison, route B declines this photo, and route A on the typed text is exact.

## Calls, retries and spend (all 60 photos per arm)

| Arm | Calls | Retries | Reported USD | Median USD per photo | p50 s | p90 s | Max s | False-ready (all strata) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Luna, off | 60 | 0 | 0.0447 | 0.0006 | 5.6 | 8.3 | 11.6 | 6 |
| Luna, on | 60 | 0 | 0.0640 | 0.0009 | 10.9 | 19.1 | 27.2 | 5 |
| Luna Pro, off | 60 | 0 | 0.0753 | 0.0011 | 6.9 | 8.9 | 14.7 | 8 |
| Luna Pro, on | 60 | 0 | 0.1371 | 0.0019 | 17.5 | 41.3 | 58.6 | 5 |
| Grok, on | 60 | 0 | 2.4105 | 0.0320 | 48.6 | 133.9 | 263.4 | 3 |
| Gemini 4, on | 60 | 0 | 0.6584 | 0.0105 | 11.5 | 20.5 | 30.7 | 7 |
| Sol, on | 60 | 0 | 0.8106 | 0.0100 | 16.0 | 24.0 | 51.5 | 5 |
| Sol Pro, on | 60 | 0 | 1.5165 | 0.0266 | 19.7 | 33.7 | 65.8 | 4 |
| Opus 5.5, on | 60 | 1 | 2.1110 | 0.0323 | 11.7 | 16.8 | 22.5 | 4 |
| Fable 5.1, on | 60 | 0 | 5.9357 | 0.0938 | 15.2 | 25.1 | 35.0 | 6 |

There was one retry in total. An Opus 5.5 call answered HTTP 502 "Provider returned error" and succeeded on the second attempt. The failed attempt is logged as `retryable_error_unknown_cost`.

**Spend.** The ledger reports **$16.77**: $16.56 for route C and $0.21 for the Qwen drafting. Route C's share includes superseded and discarded runs, probes, qualification calls and one in-flight call from the hold, charged at the $0.05 ceiling. The $40 sealed reservation is untouched.

## Findings

- **No arm meets every bar on development.** False-ready is above zero everywhere, and correct-decline is at most 4 of 5 (Taiwan) and 8 of 17 (UK). Across the six arms first completed, 20 of the 34 false-ready tables came from images that needed a decline: the model read a table anyway. The rest were offered with a wrong value or binding.
- **Taiwan is close for the frontier models; UK is not.** On Taiwan, Gemini 4 is exact on all 214 product cells and all 15 tables. Sol, Sol Pro and Grok miss one cell each. On UK, the best is Gemini 4 (269/311), then Fable 5.1 (250/311). UK serving conversions are low for every arm (at most 33/116). The UK truth records no serving line, so the per-serving header must carry the quantity, and most answers do not supply one.
- **Reasoning.** It could be switched off only on Luna and Luna Pro, so the off / on comparison exists only for them. Reasoning on did not help Luna (Taiwan strict 207 off against 205 on; UK 253 against 238). It helped Luna Pro on Taiwan (200 against 209) but not on UK (241 against 227).
- **Cost and latency against the product ceilings** (median at most $0.02, p90 at most 20 s):

| Within both ceilings | Over a ceiling |
|---|---|
| Luna (off; on is borderline at p90 19.1 s) | Grok (p90 134 s, median $0.032) |
| Luna Pro off | Sol (p90 24 s) |
| Opus 5.5 is within p90 (16.8 s) but over median cost ($0.032) | Sol Pro (p90 34 s, median $0.027) |
| Gemini 4 sits at the edge (median $0.0105, p90 20.5 s) | Fable 5.1 (median $0.094) |

- **Deadline gap.** Grok's slowest call took 263 s, past the 180 s per-call deadline, because the timeout applies to each socket read. A whole-call deadline is implemented before the sealed run, not during development.
- **Harness defects found and fixed:**
  - Inspect's `"description": null` made Luna on Azure ignore the strict schema.
  - Anthropic rejects `$comment` in the schema.
  - Inspect's own retry ignores `Retry-After`, and the OpenAI SDK under it retries on its own.
  - The key limit alone hid an exhausted account balance (HTTP 402). Sol and Sol Pro were rerun in full after the top-up.

## Superseded or discarded runs (kept outside the repository, never scored)

- The held run before the owner's decisions: Luna on `azure` (ZDR), 4096 tokens, $0.05 per call, 43 of 60 photos.
- Grok, reasoning on, 41 of 60 photos: paused for the latest-model check and rerun in full.
- Attempts blocked by the unknown-cost stop before rejected requests were relabelled.
- Sol and Sol Pro runs invalidated by HTTP 402 (account credit exhausted), and Opus 5.5's 402-failed qualification. All were rerun in full.
