# Development Notes

## Codex build experiment

This repository was developed with Codex as an experiment in agent-assisted iOS engineering. The measurement below covers the work from the initial project request through completion of the local signing configuration on 26 August 2026. It excludes the later conversation used to inspect and calculate token usage.

Recorded usage:

- Main task: 23,666,651 tokens
- Linked internal review work: 7,001,292 tokens
- Total: 30,667,943 tokens
- Input: 30,622,876 tokens
  - Cached input: 29,055,616 tokens
  - Uncached input: 1,567,260 tokens
- Output: 45,067 tokens, including 15,589 reasoning tokens

The high total does not represent 30.7 million unique tokens of source code or conversation. Codex repeatedly processes the growing task context, and 94.9% of the recorded input was served from cache.

At the GPT-5.6 Sol promotional API rates available on 27 August 2026 ($4.00 per million uncached input tokens, $0.40 per million cached input tokens, and $20.00 per million output tokens), applying that rate to every recorded token gives an API-equivalent estimate of **$18.79 USD**. The main task alone accounts for approximately **$12.60** of that estimate. The remaining internal review work used a non-public review model, so treating it as GPT-5.6 Sol is a comparison assumption rather than an actual price.

This work ran under a ChatGPT Pro subscription and was not billed through the API. The estimate excludes any separate tool charges and should not be treated as a reproducible benchmark: model pricing, cache behaviour, task history, review activity, and implementation choices can all change the result. See the [current OpenAI model pricing](https://developers.openai.com/api/docs/models/gpt-5.6-sol) before making a later comparison.
