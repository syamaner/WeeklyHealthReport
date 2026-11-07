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

The script refuses a scratch path inside the repository or promptfoo's home default. It switches off telemetry, update checks and sharing, keeps promptfoo's config, database, cache and logs in the scratch directory, and runs five synthetic labels over the directory fake transport. A2 wires no live transport, so nothing is sent to OpenRouter or any provider.

`tests/test-scratch-path.sh` checks the scratch path refusal, including a symbolic link outside the repository that points inside it.
