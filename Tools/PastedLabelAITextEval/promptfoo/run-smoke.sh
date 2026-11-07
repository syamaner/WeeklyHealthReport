#!/usr/bin/env bash
# A2 smoke run of the promptfoo harness (docs/pasted-label-ai-text-v1.md 5.2, #416): synthetic labels
# over the directory fake transport. Usage: run-smoke.sh SCRATCH_DIR
#
# promptfoo 0.125.0 reads these (checked in its dist/ sources on 7 November 2026):
# - PROMPTFOO_DISABLE_TELEMETRY: no PostHog client is created (telemetry);
# - PROMPTFOO_DISABLE_UPDATE: checkForUpdates and checkModelAuditUpdates return before any request;
# - PROMPTFOO_DISABLE_SHARING: config sharing is forced off and the share URL is never built;
# - PROMPTFOO_DISABLE_REMOTE_GENERATION: no remote generation (not needed here; off for safety);
# - PROMPTFOO_CONFIG_DIR: the config directory, which also holds promptfoo.db (the database);
# - PROMPTFOO_CACHE_PATH and PROMPTFOO_LOG_DIR: the disk cache and the logs.
# The proxy variables point at a closed local port, as a tripwire: any HTTP request promptfoo
# tried would fail and show in the log.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scratch="${1:?usage: run-smoke.sh SCRATCH_DIR}"
mkdir -p "$scratch"
scratch="$(cd "$scratch" && pwd)"
case "$scratch" in "$here"/*|"$HOME"/.promptfoo*) echo "the scratch directory must be outside the repository and the home default" >&2; exit 2 ;; esac
swift build --package-path "$here/.." -c debug --product PastedLabelAITextEval >&2
bin="$(swift build --package-path "$here/.." -c debug --show-bin-path)/PastedLabelAITextEval"
run="$scratch/run"
# The ledger and the response cache persist across runs in the same scratch directory, so a re-run
# reuses cached responses and is never charged again.
mkdir -p "$run"
cd "$here"
env -i PATH="$PATH" HOME="$scratch/home" \
  PROMPTFOO_DISABLE_TELEMETRY=1 PROMPTFOO_DISABLE_UPDATE=1 PROMPTFOO_DISABLE_SHARING=1 PROMPTFOO_DISABLE_REMOTE_GENERATION=1 \
  PROMPTFOO_CONFIG_DIR="$scratch/promptfoo-config" PROMPTFOO_CACHE_PATH="$scratch/promptfoo-cache" PROMPTFOO_LOG_DIR="$scratch/promptfoo-logs" \
  HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 NO_PROXY= \
  PASTED_LABEL_AI_TEXT_EVAL_BIN="$bin" PASTED_LABEL_AI_TEXT_EVAL_DATA="$here/smoke" PASTED_LABEL_AI_TEXT_EVAL_RUN="$run" \
  PASTED_LABEL_AI_TEXT_EVAL_FAKE_TRANSPORT="$here/smoke/fake" \
  "$here/node_modules/.bin/promptfoo" eval -c promptfooconfig.yaml --no-progress-bar --output "$scratch/results.json" "${@:2}"
