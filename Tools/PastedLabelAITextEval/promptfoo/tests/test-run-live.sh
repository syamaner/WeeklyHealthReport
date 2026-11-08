#!/usr/bin/env bash
# Tests run-live.sh's argument checks and its refusal without a key, without running anything: every
# case here exits before the build, and none sets OPENROUTER_API_KEY, so nothing can be sent. Each
# refusal must exit 2 and create nothing. Usage: tests/test-run-live.sh
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
outside="$(mktemp -d "${TMPDIR:-/tmp}/run-live-test.XXXXXX")"
trap 'rm -rf "$outside"' EXIT
status=0
mkdir -p "$outside/data/texts" "$outside/data/cases" "$outside/empty-data" "$outside/sealed/uk-english-v2/texts" "$outside/sealed/uk-english-v2/cases"
printf 'description: test\n' > "$outside/config.yaml"
refused() {
  local name="$1" want="$2" out got=0; shift 2
  out="$(env -u OPENROUTER_API_KEY "$@" 2>&1 >/dev/null)" || got=$?
  if [[ "$got" != 2 ]]; then
    echo "FAIL: $name exited $got, expected 2" >&2; status=1
  elif [[ "$out" != *"$want"* ]]; then
    echo "FAIL: $name said '$out', expected '$want'" >&2; status=1
  elif [[ -e "$outside/scratch" ]]; then
    echo "FAIL: $name created the scratch directory" >&2; status=1
  else
    echo "ok: $name"
  fi
}
live="$here/run-live.sh"
scratch="$outside/scratch"
refused "no arguments" "usage" "$live"
refused "scratch only" "usage" "$live" "$scratch"
refused "scratch inside the repository" "outside the repository" "$live" "$repo/Tools/never-created" "$outside/config.yaml" "$outside/data"
refused "missing config" "config must be an existing file" "$live" "$scratch" "$outside/missing.yaml" "$outside/data"
refused "missing data" "data directory must exist" "$live" "$scratch" "$outside/config.yaml" "$outside/missing"
refused "data without texts and cases" "must hold texts/ and cases/" "$live" "$scratch" "$outside/config.yaml" "$outside/empty-data"
refused "data inside the repository" "outside the repository (T6)" "$live" "$scratch" "$outside/config.yaml" "$here/smoke"
refused "the sealed held-out set" "held-out set" "$live" "$scratch" "$outside/config.yaml" "$outside/sealed/uk-english-v2"
refused "no key" "OPENROUTER_API_KEY must be set" "$live" "$scratch" "$outside/config.yaml" "$outside/data"
refused "an empty key" "OPENROUTER_API_KEY must be set" env OPENROUTER_API_KEY= "$live" "$scratch" "$outside/config.yaml" "$outside/data"
if [[ -e "$repo/Tools/never-created" ]]; then echo "FAIL: a refused path was created" >&2; status=1; fi
exit "$status"
