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
node make-config.js --data DIR --candidates ID[,ID...] --prompt-version v1|v2 --suite NAME [--fresh-run RUN] --out /path/outside/the/repository/config.yaml
```

- The config names no data path, so it runs over any copy of the suite; `run-live.sh` passes the data directory by environment. It does name this checkout's `provider.js` and `assert.js` by absolute path, so run it from the checkout that generated it.
- A data path holding `uk-english-v2` is refused, before and after resolving symbolic links.
- `--prompt-version` is `v1` (`prompt-v1`, the instruction the app sends) or `v2` (`prompt-v2`, revision 11). `provider.js` passes it to `send --prompt-version`, and refuses a send record whose prompt version is not the cell's. Each version's requests have their own SHA-256, so their responses are cached apart.
- `--fresh-run RUN` (revision 16) writes a fresh repeat of the suite, to measure run-to-run noise. Its cells are `<prompt-version>__<candidate-id>__<suite>-<RUN>` (for example `v2__gpt-6-luna-azure-4k__tuning-r2`), so each has its own $5 stop. RUN is a lower-case letter, then up to 15 lower-case letters, digits or single hyphens (`r2`, `r3`). `provider.js` passes it to `send --fresh-run`, and refuses a send record whose cell or fresh run is not the provider's.
- `run-live.sh` refuses data inside the repository (T6), so copy `adversarial/texts` and `adversarial/cases` to a private folder before a live adversarial run.

## Run a live tuning cell (A3)

Only after the owner has approved the matrix, under the evaluation egress terms T1 to T6 (docs/pasted-label-ai-text-v1.md 7) and with the developer-tooling note in `docs/privacy-and-egress.md` in place:

```bash
OPENROUTER_API_KEY=... ./run-live.sh /private/folder/a3-scratch /path/to/matrix-config.yaml /private/folder/data [promptfoo eval options]
```

- The live mode is explicit: `run-live.sh` sets `PASTED_LABEL_AI_TEXT_EVAL_LIVE=1`, and `provider.js` then runs `send --live` and passes `OPENROUTER_API_KEY` to the child by environment, never on a command line. Without that variable the provider is in fake mode and never passes a key; with it, a fake transport directory set as well is refused.
- `send --live` uses the shipped OpenRouter transport for the keyless catalogue check and the completions POST, reads the key from `OPENROUTER_API_KEY` only and never prints, logs, caches or writes it. A missing, empty or malformed key is a usage error (exit 2) before anything is reserved or sent.
- Each tap makes at most three attempts. Only a transport failure, HTTP 429 or HTTP 5xx is retried, with exponential backoff and jitter, honouring `Retry-After` (seconds or an HTTP date); a `Retry-After` over 30 s ends the tap instead. Every attempt reserves its own W in the spend ledger before it is sent, and the tap's `cost_usd`, `charged_usd`, `reserved_w_usd` and latency cover all its attempts (`attempts`, `attempt_outcomes` and `retry_stop` record them).
- A re-run of a default cell returns the cached answers and measures nothing. To measure noise, generate a fresh run's config (`--fresh-run r2`) and run it as any other: `send --fresh-run` never reads the default cache entry, sends the same request body through the same transport, reservation, retries and ledger, and caches the reply under `<request SHA-256>.fresh-<RUN>.json`. A repeat of the same fresh run is then a cache hit and sends nothing; the default entry is never read or overwritten. Each send record carries `fresh_run` (absent in the default run and in older records). There is no new egress: the destinations, terms and stops are unchanged.
- Use **one scratch directory for the whole A3 programme**, in the private folder: its `run/` holds the spend ledger and the response cache across runs, so the $5 cell and $25 programme stops span every run, and a re-run reuses cached answers without paying again. Each run's promptfoo results go to `results/<UTC time>.json` beside it.
- The config must be exactly what `make-config.js` writes, as `validate-config.js` checks before the build and without the key in its environment: its only providers are this checkout's `provider.js` and its only assertion this checkout's `assert.js`, with no other provider, assertion, prompt or var script, transform, extension, hook or other key that promptfoo would load and run. Anything else is refused (exit 2), nothing is built or run and the key is never passed on. promptfoo reads a copy of the validated text in `configs/` beside `run/`, so the file cannot change between the check and the run.
- The promptfoo eval options are limited to ones that load no code: `--no-cache`, `--verbose`, `--filter-pattern`, `--filter-providers`, `-n`/`--filter-first-n`, `--filter-sample`, `-j`/`--max-concurrency` and `--delay`.
- The data directory (`texts/` and `cases/`) must be outside the repository (T6). The sealed held-out set (`uk-english-v2`) is refused: the held-out run (T7) is separate.
- Telemetry, update checks, sharing and remote generation are off as in the smoke run. No dead proxy is set, since it would block the real call.

## The held-out run (A4)

The single held-out run (T7, docs/pasted-label-ai-text-v1.md 5.5) is not a promptfoo run: every tuning path here refuses the sealed set, and `send` refuses any cell ending `__a4-heldout`. The wrapper sits beside `run-live.sh` and runs the separate executable `PastedLabelAITextHeldOut`:

```bash
OPENROUTER_API_KEY=... ./run-heldout.sh [--private-root DIR]
```

- The wrapper refuses, before anything is built or sent, unless the key is set, `git fetch origin` succeeds, the checkout is clean and HEAD is `origin/main`, `FreezePinTests` and `SealedTextPathTests` pass, and `PastedLabelAITextHeldOut check` passes. `check` makes the runner's refusals that come before the key and the catalogue (seals, label IDs, conversion, the ledger, an existing output or cache) and creates, reserves and sends nothing. Every git call, the tests, the build and `check` run with the key unset; only `run` receives it.
- The configuration is closed: `prompt-v2` on `gpt-6.1-sol-azure-4k`, scorer v5, the cell `v2__gpt-6.1-sol-azure-4k__a4-heldout` with its $5 stop, inside A3's ledger and the $25 programme stop. The only option is the private root (default `~/WHR-label-eval-private`); the held-out folder (`uk-english-v2/fresh`), the A3 ledger (`ai-text-v1/runs/a3/run/spend-ledger.json`), the output folder (`ai-text-v1/runs/a4/`) and the A4 cache (`ai-text-v1/runs/a4-response-cache/`) are fixed under it.
- The runner reads every text, transcription and collection record once through one descriptor, checks the text seal and seal 2 against those bytes, and refuses a second run, an existing cache, a ledger with no A3 entry or with an A4 entry, a worst case past either stop, a key or catalogue check that fails, and any link or file outside its folder, all before anything is reserved or created. It then creates `a4-run.json` exclusively: from that moment the run has happened, and it is never resumed or repeated.
- Each label's row is appended to `journal.jsonl` as it finishes. At the end the journal becomes `results.json` and `cases/`, plus `results-tier-a.json` and `cases-tier-a/`; after a crash, `PastedLabelAITextHeldOut finalise [--private-root DIR]` writes them from the journal, counting every label not run as failed. Read the bar with `python3 -I ../statistics/pasted_label_ai_text_stats.py summary results.json --cases cases`, and tier A with the same command on its subset.
- Tap latency is measured in process, from the start of the send to the end of the score (`in_process_send_to_score_end`), so it is lower than A3's by the `send` and `score` process start-up; report it as a deviation beside A3's p90 of 15.0 s.
- Standard output is one line of counts and standard error fixed reasons only; the raw records stay in the private output folder.

## Tests

None of these runs promptfoo, builds the tool or sends anything:

- `tests/test-scratch-path.sh` checks the scratch path refusal of both scripts (shared in `scratch-path.sh`), including a symbolic link outside the repository that points inside it.
- `tests/test-run-live.sh` checks `run-live.sh`'s argument checks, its config and option checks and its refusal without a key; every case exits 2 before the build and creates nothing, and with a dummy key set, shims on `PATH` show that a refused config never reaches the build and that the key never reaches the config check.
- `tests/test-run-heldout.sh` checks `run-heldout.sh`'s gates with `git` and `swift` shims and a stub runner: a missing key, a failed fetch, a dirty checkout, HEAD other than `origin/main` and failing pin tests each exit 2 without reaching the runner, git and swift never see the key, and the happy path runs the pin tests and the build first, then the runner with the key. The runner itself is tested in `Tests/PastedLabelAITextEvalHarnessTests/HeldOutRunTests.swift`, over synthetic folders and fake transports, including the statistics script reading its results.
- `node tests/test-validate-config.js` checks that a generated config passes `validate-config.js` and that every other shape is refused for its own reason (a foreign provider, another assertion, a prompt or var script, a transform, extensions and other keys).
- `node tests/test-provider-modes.js` checks with a stub binary that the key reaches the child only in live mode, and only through its environment, that the prompt version and fresh run are passed through, and that a record for another prompt version, cell or fresh run is refused.
- `node tests/test-make-config.js` checks the generator's refusals and the shape of the config it writes, with and without a fresh run.
- The Swift side of fresh runs (cache keys, the untouched default entry, W and the ledger) is in `Tests/PastedLabelAITextEvalHarnessTests/FreshRunTests.swift`, over a scripted transport.
