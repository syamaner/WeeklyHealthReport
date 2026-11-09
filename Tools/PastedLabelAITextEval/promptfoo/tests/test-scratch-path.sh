#!/usr/bin/env bash
# Tests the scratch path refusal of run-smoke.sh and run-live.sh, which share scratch-path.sh (Qodo
# finding 5 on A2): run with a temporary directory outside the repository. Only `--check-scratch` is
# run, which builds and sends nothing. Usage: tests/test-scratch-path.sh
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
outside="$(mktemp -d "${TMPDIR:-/tmp}/scratch-path-test.XXXXXX")"
trap 'rm -rf "$outside"' EXIT
status=0
expect() {
  local want="$1" path="$2" got script
  for script in run-smoke.sh run-live.sh; do
    got=0
    env -u OPENROUTER_API_KEY "$here/$script" --check-scratch "$path" >/dev/null 2>&1 || got=$?
    if [[ "$want" == ok && "$got" != 0 ]] || [[ "$want" == refused && "$got" != 2 ]]; then
      echo "FAIL: $script $path expected $want, exit $got" >&2; status=1
    else
      echo "ok: $script $path $want"
    fi
  done
}
ln -s "$repo/Tools" "$outside/into-repo"
ln -s "$outside" "$outside/loop-out"
ln -s "$outside/missing-target" "$outside/dangling"
expect refused "$outside/into-repo"
expect refused "$outside/into-repo/new-dir"
expect refused "$repo/Tools/never-created"
expect refused "$outside/dangling"
expect ok "$outside/new-dir"
expect ok "$outside/loop-out"
if [[ -e "$repo/Tools/never-created" ]]; then echo "FAIL: a refused path was created" >&2; status=1; fi
exit "$status"
