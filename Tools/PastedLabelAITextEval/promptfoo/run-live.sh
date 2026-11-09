#!/usr/bin/env bash
# A3 live tuning run of the promptfoo harness (docs/pasted-label-ai-text-v1.md 5.2, #416), under the
# evaluation egress terms T1 to T6: each label is sent by `PastedLabelAITextEval send --live`, which
# reaches only OpenRouter's completions endpoint and its keyless catalogue listings through the
# shipped transport, with every attempt reserved in the spend ledger first.
#
# Usage: run-live.sh [--check-scratch] SCRATCH_DIR CONFIG DATA_DIR [promptfoo eval options...]
#
# - SCRATCH_DIR holds everything the run writes, outside the repository (scratch-path.sh): the spend
#   ledger and the response cache in SCRATCH_DIR/run, kept across runs, so the $5 cell and $25
#   programme stops span every run that uses the same SCRATCH_DIR, and a re-run reuses cached
#   answers without paying again. Use one SCRATCH_DIR for the whole A3 programme, in the private folder.
# - CONFIG is the promptfoo config of the approved matrix; DATA_DIR holds texts/ and cases/ for its
#   labels, outside the repository (T6). The sealed held-out set (uk-english-v2) is refused: T7 is a
#   separate, single run by the frozen version.
# - OPENROUTER_API_KEY must be set in the environment (T4). It is passed down by inheritance only,
#   never on a command line, and never printed or written.
# - Telemetry, update checks, sharing and remote generation are switched off as in run-smoke.sh.
#   Unlike run-smoke.sh, no dead proxy is set: it would block the real call.
#
# - CONFIG must be exactly what make-config.js writes (validate-config.js): its only providers are this
#   checkout's provider.js and its only assertion this checkout's assert.js, with nothing else that
#   promptfoo would load and run. Any other config is refused before the build, with the key never
#   passed on, and promptfoo reads a copy of the validated text in SCRATCH_DIR/configs, so the file
#   cannot change between the check and the run.
# - The promptfoo eval options are limited to ones that load no code: --no-cache, --verbose,
#   --filter-pattern REGEX, --filter-providers REGEX, -n/--filter-first-n N, --filter-sample N,
#   -j/--max-concurrency N, --delay MS. Any other option is refused before the build.
#
# `--check-scratch SCRATCH_DIR` only checks and prints the resolved scratch path. Every check runs
# before anything is created, built or sent.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
usage="usage: run-live.sh [--check-scratch] SCRATCH_DIR CONFIG DATA_DIR [promptfoo eval options...]"
check_only=0
if [[ "${1:-}" == "--check-scratch" ]]; then check_only=1; shift; fi
if [[ $# -lt 1 ]]; then echo "$usage" >&2; exit 2; fi
scratch="$1"
# shellcheck source=scratch-path.sh
source "$here/scratch-path.sh"
scratch="$(resolve_scratch "$scratch" "$here")" || exit 2
if [[ "$check_only" == 1 ]]; then echo "$scratch"; exit 0; fi
if [[ $# -lt 3 ]]; then echo "$usage" >&2; exit 2; fi
config="$2"
data="$3"
repo="$(cd -P "$(git -C "$here" rev-parse --show-toplevel)" && pwd -P)"
if [[ ! -f "$config" ]]; then echo "the config must be an existing file" >&2; exit 2; fi
config="$(cd -P "$(dirname "$config")" && pwd -P)/$(basename "$config")"
# The held-out refusal comes first, on the path as given, so a refused path is never resolved (T7).
case "$data" in *uk-english-v2*) echo "the sealed held-out set is never used by a tuning run (T7)" >&2; exit 2 ;; esac
if [[ ! -d "$data" ]]; then echo "the data directory must exist" >&2; exit 2; fi
data="$(cd -P "$data" && pwd -P)"
case "$data/" in "$repo"/*) echo "the data directory must be outside the repository (T6)" >&2; exit 2 ;; esac
case "$data/" in */uk-english-v2/*) echo "the sealed held-out set is never used by a tuning run (T7)" >&2; exit 2 ;; esac
if [[ ! -d "$data/texts" || ! -d "$data/cases" ]]; then echo "the data directory must hold texts/ and cases/" >&2; exit 2; fi
# Every text and case file, resolved: one naming the sealed set, as given or resolved, or resolving
# outside the data directory (a symbolic link inside an approved directory) is refused. provider.js,
# assert.js and `send --data` refuse the same per call; this refuses the whole run before it starts.
shopt -s nullglob
for file in "$data"/texts/* "$data"/cases/*; do
  case "$file" in *uk-english-v2*) echo "the sealed held-out set is never used by a tuning run (T7)" >&2; exit 2 ;; esac
  resolved="$(realpath "$file" 2>/dev/null)" || { echo "${file#"$data"/} does not resolve" >&2; exit 2; }
  case "$resolved" in *uk-english-v2*) echo "the sealed held-out set is never used by a tuning run (T7)" >&2; exit 2 ;; esac
  case "$resolved" in "$data"/*) ;; *) echo "${file#"$data"/} resolves outside the data directory" >&2; exit 2 ;; esac
done
shopt -u nullglob
# promptfoo eval options after DATA_DIR: only these, so no option names a provider, prompt, test,
# assertion, var or environment file for promptfoo to load (which could read the key).
options=("${@:4}")
i=0
while (( i < ${#options[@]} )); do
  case "${options[$i]}" in
    --no-cache|--verbose) i=$((i + 1)) ;;
    --filter-pattern|--filter-providers)
      [[ -n "${options[$((i + 1))]:-}" ]] || { echo "${options[$i]} needs a value" >&2; exit 2; }; i=$((i + 2)) ;;
    -n|--filter-first-n|--filter-sample|-j|--max-concurrency|--delay)
      [[ "${options[$((i + 1))]:-}" =~ ^[0-9]+$ ]] || { echo "${options[$i]} needs a number" >&2; exit 2; }; i=$((i + 2)) ;;
    *) echo "promptfoo option ${options[$i]} is not allowed by a live run" >&2; exit 2 ;;
  esac
done
# The config is checked without the key in the environment, and its validated text is what promptfoo reads.
validated="$(env -u OPENROUTER_API_KEY node "$here/validate-config.js" "$config")" || { echo "the config is not one make-config.js writes; nothing was run" >&2; exit 2; }
if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "OPENROUTER_API_KEY must be set: a live run reads the key from the environment only (T4)" >&2; exit 2
fi
mkdir -p "$scratch"
env -u OPENROUTER_API_KEY swift build --package-path "$here/.." -c debug --product PastedLabelAITextEval >&2
bin="$(env -u OPENROUTER_API_KEY swift build --package-path "$here/.." -c debug --show-bin-path)/PastedLabelAITextEval"
run="$scratch/run"
mkdir -p "$run" "$scratch/results" "$scratch/configs"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
results="$scratch/results/$stamp.json"
# A new file (noclobber), never one already there or a link, holding exactly the validated text.
checked="$scratch/configs/$stamp-$$.yaml"
( set -o noclobber; umask 077; printf '%s\n' "$validated" > "$checked" )
cd "$here"
(
  # A clean environment, as `env -i` gives run-smoke.sh, but the key is kept by inheritance rather
  # than written on env's command line, where other local processes could read it.
  while IFS= read -r name; do
    case "$name" in PATH|OPENROUTER_API_KEY) ;; *) unset "$name" 2>/dev/null || true ;; esac
  done < <(compgen -e)
  export HOME="$scratch/home"
  export PROMPTFOO_DISABLE_TELEMETRY=1 PROMPTFOO_DISABLE_UPDATE=1 PROMPTFOO_DISABLE_SHARING=1 PROMPTFOO_DISABLE_REMOTE_GENERATION=1
  export PROMPTFOO_CONFIG_DIR="$scratch/promptfoo-config" PROMPTFOO_CACHE_PATH="$scratch/promptfoo-cache" PROMPTFOO_LOG_DIR="$scratch/promptfoo-logs"
  export PASTED_LABEL_AI_TEXT_EVAL_LIVE=1
  export PASTED_LABEL_AI_TEXT_EVAL_BIN="$bin" PASTED_LABEL_AI_TEXT_EVAL_DATA="$data" PASTED_LABEL_AI_TEXT_EVAL_RUN="$run"
  exec "$here/node_modules/.bin/promptfoo" eval -c "$checked" --no-progress-bar --output "$results" ${options[@]+"${options[@]}"}
)
