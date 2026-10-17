# Route C on development photos (phase 3, #255): interim

Status: **interim, 17 October 2026.** Six arms are complete. Sol and Sol Pro are invalid on the UK stratum because the OpenRouter account ran out of credit mid-run (HTTP 402). Opus 5.5 and Fable 5.1 have not run. No route C call will be made until the owner confirms a top-up. Development data only: no untouched or sealed photo, untouched truth or draft was read. Machine-readable summaries (aggregate counts and per-case flags only, no model answers) are in [`route-c-development-v1.json`](route-c-development-v1.json).

These are **development** results on exposed images, with the limits in plan section 3.5. The Taiwan development truths were drafted by Claude (the assistant, Claude Opus 5.5), so Claude Opus 5.5 and Claude Fable 5.1 results on the Taiwan stratum will carry a self-agreement caveat. The UK stratum's truth records no serving-size or servings-per-pack line, so serving conversions there are scored against per-serving headers only.

## Configuration (owner decisions of 17 October 2026, evaluation only)

- **Routing.** One pinned provider per model (`only` and `order`, no fallbacks, parameters required). ZDR and `data_collection: "deny"` are dropped for the evaluation and recorded as information only; product routing is unchanged and any product use would still need ZDR.
- **Limits.** 16384 output tokens; $0.20 per-call stop; $65 total stop, with 200 sealed calls reserved at $0.20 ($40), leaving $25 for development.
- **Requests.** One request per image through `openrouter_client`: at most 5 attempts in 180 s, with exponential backoff and jitter that respects `Retry-After`. Content outcomes are never retried. Strict JSON schema, which also carries a description; `$comment` is stripped. Every answer is validated against the wire schema.
- **Reasoning.** Each model runs off and on where the endpoint allows. Grok 4.7, GPT-6.1 Sol, GPT-6.1 Sol Pro, Gemini 4 Argon, Claude Opus 5.5 and Claude Fable 5.1 all answer HTTP 400 "Reasoning is mandatory for this endpoint and cannot be disabled", so for them reasoning off is **not available**, with no substitute.
- **Models.** The latest in each family on 17 October 2026, all with image input, from the public catalogue:

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

Strata: Taiwan (20 Open Food Facts development photos; the plan's 22 less the two English-only exclusions), UK (39 of the 40 local v2 development review images; one is excluded by the owner's review), and the muesli photo. Every arm passed two fictional qualification labels before any real image.

## Results against the bars

Each cell shows numerator / denominator. **fail** means the bar is missed; "n/d" means there is no denominator. False-ready must be 0. Cost and latency are per call; product ceilings are median $0.02 and p90 20 s.

### Taiwan (20 photos)

| Arm | Strict cells | Binding | Unit and basis | Full table | Serving conv. | Servings / pack | Correct decline | False-ready | Cost USD | Median USD | p50 s | p90 s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Luna, off | 207/214 | 229/238 **fail** | 214/214 | 11/15 **fail** | 123/123 | 15/15 | 3/5 **fail** | **4** | 0.0137 | 0.0006 | 5.6 | 7.9 |
| Luna, on | 205/214 | 229/238 **fail** | 208/214 **fail** | 12/15 | 120/123 **fail** | 15/15 | 2/5 **fail** | **2** | 0.0207 | 0.0008 | 10.8 | 15.9 |
| Luna Pro, off | 200/214 **fail** | 223/238 **fail** | 208/214 **fail** | 10/15 **fail** | 120/123 **fail** | 15/15 | 4/5 **fail** | **5** | 0.0237 | 0.0010 | 6.9 | 8.7 |
| Luna Pro, on | 209/214 | 233/238 **fail** | 214/214 | 13/15 | 123/123 | 15/15 | 2/5 **fail** | **3** | 0.0441 | 0.0019 | 14.6 | 21.8 |
| Grok, on | 213/214 | 237/238 | 214/214 | 14/15 | 123/123 | 15/15 | 3/5 **fail** | **1** | 0.5975 | 0.0194 | 26.2 | 116.1 |
| Gemini 4, on | 214/214 | 238/238 | 214/214 | 15/15 | 123/123 | 15/15 | 3/5 **fail** | **1** | 0.1966 | 0.0103 | 9.9 | 17.1 |
| Sol, on | 213/214 | 237/238 | 214/214 | 14/15 | 123/123 | 15/15 | 3/5 **fail** | **2** | 0.3344 | 0.0139 | 15.8 | 25.4 |

Sol Pro's Taiwan run is invalid (18 of 20 calls failed with HTTP 402).

### UK (39 images)

| Arm | Strict cells | Binding | Unit and basis | Full table | Serving conv. | Bounds | Correct decline | False-ready | Cost USD | Median USD | p50 s | p90 s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Luna, off | 253/311 **fail** | 262/325 **fail** | 253/311 **fail** | 14/22 **fail** | 7/116 **fail** | 9/11 **fail** | 5/17 **fail** | **2** | 0.0302 | 0.0005 | 5.7 | 9.2 |
| Luna, on | 238/311 **fail** | 247/325 **fail** | 239/311 **fail** | 10/22 **fail** | 9/116 **fail** | 8/11 **fail** | 6/17 **fail** | **3** | 0.0422 | 0.0009 | 10.8 | 23.4 |
| Luna Pro, off | 241/311 **fail** | 249/325 **fail** | 241/311 **fail** | 13/22 **fail** | 18/116 **fail** | 8/11 **fail** | 3/17 **fail** | **3** | 0.0502 | 0.0011 | 6.9 | 9.5 |
| Luna Pro, on | 227/311 **fail** | 236/325 **fail** | 227/311 **fail** | 10/22 **fail** | 7/116 **fail** | 8/11 **fail** | 7/17 **fail** | **2** | 0.0911 | 0.0020 | 18.8 | 50.3 |
| Grok, on | 225/311 **fail** | 234/325 **fail** | 226/311 **fail** | 10/22 **fail** | 16/116 **fail** | 8/11 **fail** | 5/17 **fail** | **2** | 1.7684 | 0.0377 | 65.6 | 175.2 |
| Gemini 4, on | 269/311 **fail** | 279/325 **fail** | 269/311 **fail** | 13/22 **fail** | 33/116 **fail** | 9/11 **fail** | 3/17 **fail** | **6** | 0.4510 | 0.0111 | 13.6 | 20.7 |

The Sol and Sol Pro UK runs are invalid: 32 and 35 of 39 calls failed with HTTP 402.

### Muesli photo

Every complete arm (Luna off and on, Luna Pro off and on, Grok on, Gemini 4 on) read the muesli table exactly: 18 of 18 cells, the full table, 9 of 9 serving conversions and the servings per pack, and none was false-ready. This includes the binding stress case, where the right-hand column is offset by a row. Sol and Sol Pro failed on it with HTTP 402. Route B declines this photo, and route A on the typed text is exact.

## Calls, retries and spend

| Arm | Calls | Retries | Unknown-cost calls | Reported USD | p50 s | p90 s | Max s |
|---|---:|---:|---:|---:|---:|---:|---:|
| Luna, off | 60 | 0 | 0 | 0.0447 | 5.6 | 8.3 | 11.6 |
| Luna, on | 60 | 0 | 0 | 0.0640 | 10.9 | 19.1 | 27.2 |
| Luna Pro, off | 60 | 0 | 0 | 0.0753 | 6.9 | 8.9 | 14.7 |
| Luna Pro, on | 60 | 0 | 0 | 0.1371 | 17.5 | 41.3 | 58.6 |
| Grok, on | 60 | 0 | 0 | 2.4105 | 48.6 | 133.9 | 263.4 |
| Gemini 4, on | 60 | 0 | 0 | 0.6584 | 11.5 | 20.5 | 30.7 |
| Sol, on (invalid on UK) | 60 | 0 | 33 (HTTP 402) | 0.4694 | | | |
| Sol Pro, on (invalid) | 60 | 0 | 54 (HTTP 402) | 0.1772 | | | |

No retryable error occurred in these arms, so no retries were made. The HTTP 402 answers are final rejections with no generation, logged as `rejected_no_generation_unknown_cost`. **Ledger total reported spend: $6.13** of the $65 total stop. That includes the Qwen drafting ($0.21), the held and discarded azure Luna run, the earlier partial Grok run, the qualification probes and diagnostics, and one in-flight call from the hold charged at its $0.05 ceiling.

## Findings

- **The account ran out of credit.** The key still had $58 of its limit left, but the account balance was $0.76, and OpenRouter answered HTTP 402 ("This request would exceed your available credits given your current in-flight requests"). The runner now checks both the key limit and the account balance (both free calls) and refuses to start an arm whose projected cost, plus a margin, exceeds the smaller of the two.
- **Latency.** Grok 4.7 with reasoning on is slow: p90 134 s and a maximum of 263 s. It misses the product ceiling of p90 20 s and is also above the median cost ceiling of $0.02. The 180 s per-call deadline bounds when retries start, but one slow attempt can run past it, because urllib's timeout applies to each socket read. A whole-call deadline will be implemented before the sealed run, not during development, so all development arms run on the same client.
- **Harness defects found and fixed.**
  - Inspect's `"description": null` made Luna on Azure ignore the strict schema.
  - Anthropic rejects the schema's `$comment` key.
  - Inspect's own retry ignores `Retry-After`, and the OpenAI SDK underneath it retries on its own. Route C now posts through one client with one retry loop.
- **False-ready is above zero in every complete arm,** so no arm meets that bar on development. Across the six complete arms, 20 of the 34 false-ready tables are images that need a decline and that the model read as a table anyway; correct-decline is below 95% everywhere. The other 14 are tables the model would have offered with a value or binding wrong. For Gemini 4 the split is 6 of 7, for Grok 2 of 3, and for Luna (off) 2 of 6.

## Still to run (after the owner confirms a top-up)

Projected from measured per-call costs:

| Arm | Projected USD |
|---|---:|
| Sol, on (rerun) | about 0.9 |
| Sol Pro, on (rerun) | about 1.7 |
| Opus 5.5, on | about 3.3 |
| Fable 5.1, on (all 60 photos; starts only if available credit covers it plus the $40 reservation) | about 8.3 |

That takes development spend to about $20 of the $25 allowance.

## Superseded or discarded runs (kept outside the repository, never scored)

- The held run before the owner's decisions: Luna on `azure` (ZDR), 4096 tokens, $0.05 per call, 43 of 60 photos.
- Grok, reasoning on: 41 of 60 photos, paused for the latest-model check and rerun in full.
- The attempts blocked by the unknown-cost stop before rejected requests were relabelled.
