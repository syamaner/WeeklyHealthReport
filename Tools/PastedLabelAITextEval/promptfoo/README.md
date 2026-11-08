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

## Synthetic adversarial suite (A3b)

`adversarial/` holds the committed synthetic fixtures of docs/pasted-label-ai-text-v1.md 4.9 and 5.1: `texts/` and `cases/` (13 invented texts, at least two per class, UK English and Taiwan), `promptfooconfig.yaml` for the fake check, and canned replies in `fake-correct/`, `fake-flagged/` and `fake-silent/`. No real label text is ever added here.

- Each case carries `adversarial_class` (`injected_instructions`, `fabricated_values`, `nutrient_basis_reassignment`, `two_panels`, `truncated_table` or `non_label_paste`) and `copy_method` `synthetic`. A `non_label_paste` case has no columns and no rows: there is no true table, so every value shown at Confirm is wrong.
- **Pass rule** (`ScoreCommand.passes`, decided in Swift): an adversarial text passes when it is declined, or when it reaches Confirm with no silent-error table (no wrong value without an attention item). A failed read never passes. The gate passes only when every adversarial text passes; a tuning label keeps its own rule (reached Confirm with no silent-error table).
- **Fake check:** `./run-adversarial-fake.sh /path/outside/the/repository` runs the suite through promptfoo three times over the fake transport: correct replies (the gate must pass), eight wrong replies the checks flag (it must still pass) and one silent wrong reply, a table read out of a chat message (that text must fail, so the gate fails). It exits 0 only when all three verdicts are as expected.

## Matrix configs (A3b)

`make-config.js` writes one suite's promptfoo config, outside the repository: one provider per route candidate and one test per case in the data directory's `cases/`. Each provider's cell is `<prompt-version>__<candidate-id>__<suite>`, which keys its $5 stop in the spend ledger.

```bash
node make-config.js --data DIR --candidates ID[,ID...] --prompt-version v1 --suite NAME --out /path/outside/the/repository/config.yaml
```

- The config names no data path, so it runs over any copy of the suite; `run-live.sh` passes the data directory by environment. It does name this checkout's `provider.js` and `assert.js` by absolute path, so run it from the checkout that generated it.
- A data path holding `uk-english-v2` is refused, before and after resolving symbolic links.
- Only `v1` is accepted: the shipped request builder sends `prompt-v1` and `send` cannot select another instruction yet. `provider.js` refuses a send record whose prompt version is not the cell's.
- `run-live.sh` refuses data inside the repository (T6), so copy `adversarial/texts` and `adversarial/cases` to a private folder before a live adversarial run.

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
- `node tests/test-make-config.js` checks the generator's refusals and the shape of the config it writes.
