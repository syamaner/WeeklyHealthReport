# promptfoo harness for the pasted label AI text evaluation

This directory holds the local promptfoo harness for #416 (docs/pasted-label-ai-text-v1.md 5.2). promptfoo only orchestrates: `provider.js` runs `PastedLabelAITextEval send`, and `assert.js` runs `PastedLabelAITextEval score`, so the Swift code decides every value and every count.

## Install

promptfoo is pinned to an exact version (0.125.0) and installed without running any package's install scripts:

```bash
npm ci --ignore-scripts
```

`--ignore-scripts` is deliberate (owner approval, A2). It skips the install scripts of `esbuild` and `fsevents`; promptfoo still runs the evaluation without them. Never re-run the install with scripts enabled without the owner's approval. `node_modules/` is not committed.

## Run the smoke evaluation

```bash
./run-smoke.sh /path/outside/the/repository
```

The script refuses a scratch path inside the repository or promptfoo's home default. It switches off telemetry, update checks and sharing, keeps promptfoo's config, database, cache and logs in the scratch directory, and runs five synthetic labels over the directory fake transport (`send --fake-transport`). The provider's child gets only `PATH`, so no key is ever passed and nothing is sent to OpenRouter or any provider.

## Run a live tuning cell (A3)

Only after the owner has approved the matrix, under the evaluation egress terms T1 to T6 (docs/pasted-label-ai-text-v1.md 7) and with the developer-tooling note in `docs/privacy-and-egress.md` in place:

```bash
OPENROUTER_API_KEY=... ./run-live.sh /private/folder/a3-scratch /path/to/matrix-config.yaml /private/folder/data [promptfoo eval options]
```

- The live mode is explicit: `run-live.sh` sets `PASTED_LABEL_AI_TEXT_EVAL_LIVE=1`, and `provider.js` then runs `send --live` and passes `OPENROUTER_API_KEY` to the child by environment, never on a command line. Without that variable the provider is in fake mode and never passes a key; with it, a fake transport directory set as well is refused.
- `send --live` uses the shipped OpenRouter transport for the keyless catalogue check and the completions POST, reads the key from `OPENROUTER_API_KEY` only and never prints, logs, caches or writes it. A missing, empty or malformed key is a usage error (exit 2) before anything is reserved or sent.
- Each tap makes at most three attempts. Only a transport failure, HTTP 429 or HTTP 5xx is retried, with exponential backoff and jitter, honouring `Retry-After` (seconds or an HTTP date); a `Retry-After` over 30 s ends the tap instead. Every attempt reserves its own W in the spend ledger before it is sent, and the tap's `cost_usd`, `charged_usd`, `reserved_w_usd` and latency cover all its attempts (`attempts`, `attempt_outcomes` and `retry_stop` record them).
- Use **one scratch directory for the whole A3 programme**, in the private folder: its `run/` holds the spend ledger and the response cache across runs, so the $5 cell and $25 programme stops span every run, and a re-run reuses cached answers without paying again. Each run's promptfoo results go to `results/<UTC time>.json` beside it.
- The data directory (`texts/` and `cases/`) must be outside the repository (T6). The sealed held-out set (`uk-english-v2`) is refused: the held-out run (T7) is separate.
- Telemetry, update checks, sharing and remote generation are off as in the smoke run. No dead proxy is set, since it would block the real call.

## Tests

None of these runs promptfoo, builds the tool or sends anything:

- `tests/test-scratch-path.sh` checks the scratch path refusal of both scripts (shared in `scratch-path.sh`), including a symbolic link outside the repository that points inside it.
- `tests/test-run-live.sh` checks `run-live.sh`'s argument checks and its refusal without a key; every case exits 2 before the build and creates nothing.
- `node tests/test-provider-modes.js` checks with a stub binary that the key reaches the child only in live mode, and only through its environment.
