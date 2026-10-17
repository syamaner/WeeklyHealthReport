# Route C on development photos (phase 3, #255): held

Status: **held by the owner on 17 October 2026, before any result.** The owner is reconsidering the routing restrictions (ZDR, `data_collection: "deny"`, reasoning off, the 4096-token ceiling and the $0.05 per-call stop). No route C quality result is reported here; the partial run below is a record of what was sent, not a result.

## What was prepared

- **Catalogue gate, 17 October 2026** (public OpenRouter catalogue; slugs, endpoints and prices recorded in `frozen-contract-v1.json` under `route_c.models`). All five models advertised image input and a ZDR endpoint:

| Model | Slug | Endpoint (ZDR) | Prompt / completion, USD per million tokens |
|---|---|---|---|
| GPT-6 Luna | `openai/gpt-6-luna` | `azure` | 0.10 / 0.50 |
| Grok 4.7 | `x-ai/grok-4.7` | `xai/zdr` | 2.00 / 6.00 |
| GPT-6.1 Sol | `openai/gpt-6.1-sol` | `azure` | 2.00 / 10.00 |
| Gemini 4 | `google/gemini-4-argon` (the only Gemini 4 model listed) | `google-vertex/us` (`google-vertex/global` showed status -2) | 2.20 / 11.00 |
| Claude Opus 4.7 | `anthropic/claude-opus-4.7` | `google-vertex/global` | 5.00 / 25.00 |

- **Mapping** (`route_c_mapping.py`) and **runner** (`run_route_c.py`): wire output to `label-capture-candidate-v1`, two fictional qualification labels before any real image, per-stratum summaries with cost and p50 / p90 latency.

## What was sent before the hold

- **A harness defect, found and fixed.** Inspect sends `"description": null` in the `json_schema` block when no description is set. With it, Luna on Azure answered outside the strict schema; without it (one diagnostic call each way), the answer was schema-valid. The solver now sets a description and also validates every answer against the wire schema, so a schema-invalid answer is a failed case, never mapped.
- **Luna only:** qualification passed (both fictional labels mapped, model and provider matched). The development run was stopped after 43 of 60 development photos (20 Taiwan, 39 UK, 1 muesli) when the hold arrived; its Inspect log was not summarised and no score from it is reported. The cases run in the order Taiwan, UK, muesli, so the 43 were the 20 Taiwan photos and 23 UK photos; the muesli photo was not sent. No other model received any image.
- **Spend:** route C calls in the persistent ledger total USD 0.0345623 reported over 51 recorded calls (qualification, the two diagnostic calls and the partial Luna run). One call was in flight when the run was stopped, so the ledger holds it open and charges it at the $0.05 ceiling until it is reconciled.

The Taiwan development truths were drafted by Claude, so any later Claude Opus result on that stratum carries that caveat.
