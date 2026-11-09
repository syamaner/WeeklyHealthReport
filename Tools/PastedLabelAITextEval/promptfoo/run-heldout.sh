#!/usr/bin/env bash
# The single A4 held-out run (docs/pasted-label-ai-text-v1.md 5.5 item 4, #416, T7). It sits beside
# run-live.sh for discovery, but runs no promptfoo: `PastedLabelAITextHeldOut run` sends, scores and
# journals each label in process, then writes results.json for the statistics script.
#
# Usage: run-heldout.sh [--private-root DIR]
#
# Before anything is built or sent, in this order:
# - OPENROUTER_API_KEY must be set (T4); it is passed down by inheritance only, never on a command line.
# - `git fetch origin` must succeed, the checkout must be clean (no change, staged, unstaged or
#   untracked) and HEAD must be origin/main, so the run is of the merged, frozen code.
# - FreezePinTests and SealedTextPathTests must pass.
# - `PastedLabelAITextHeldOut check`, without the key, must pass: it makes every refusal the run makes
#   before the key and the catalogue (seals, label IDs, conversion, ledger, an existing output or
#   cache) and creates, reserves and sends nothing, so a refusal there costs the held-out set nothing.
# Every git call, the tests and the build run with the key unset (SwiftPM evaluates manifests). Only
# the held-out executable receives the key. The private root defaults to ~/WHR-label-eval-private;
# every path under it is fixed by the runner, which refuses a second run, an existing cache, a ledger
# with no A3 entry or with an A4 entry, a changed seal and a worst case past either stop before it
# reserves anything. After a crash, run `PastedLabelAITextHeldOut finalise [--private-root DIR]` to
# write results.json from the journal; the run itself is never resumed or repeated.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
package="$(cd "$here/.." && pwd -P)"
repo="$(cd "$package/../.." && pwd -P)"
usage="usage: run-heldout.sh [--private-root DIR]"
refuse() { echo "run-heldout.sh: $1; nothing was built or sent" >&2; exit 2; }
root_args=()
case $# in
  0) ;;
  2) [[ "$1" == "--private-root" && -n "$2" ]] || { echo "$usage" >&2; exit 2; }; root_args=(--private-root "$2") ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then refuse "OPENROUTER_API_KEY must be set: the run reads the key from the environment only (T4)"; fi
nokey() { env -u OPENROUTER_API_KEY "$@"; }
nokey git -C "$repo" fetch --quiet origin || refuse "git fetch origin failed"
[[ -z "$(nokey git -C "$repo" status --porcelain --untracked-files=all)" ]] || refuse "the checkout is not clean"
head="$(nokey git -C "$repo" rev-parse HEAD)" || refuse "HEAD could not be read"
main="$(nokey git -C "$repo" rev-parse origin/main)" || refuse "origin/main could not be read"
[[ -n "$head" && "$head" == "$main" ]] || refuse "HEAD is not origin/main"
nokey swift test --package-path "$package" --filter 'FreezePinTests|SealedTextPathTests' >&2 || refuse "FreezePinTests or SealedTextPathTests failed"
nokey swift build --package-path "$package" -c debug --product PastedLabelAITextHeldOut >&2 || refuse "the build failed"
bin="$(nokey swift build --package-path "$package" -c debug --show-bin-path)/PastedLabelAITextHeldOut" || refuse "the build path could not be read"
[[ -x "$bin" ]] || refuse "the held-out executable was not built"
# The checkout is checked again just before the run, so a change made during the tests or the build
# is refused (Qodo, A4). A change in the moment between this check and the exec is not covered: the
# run is a single local operator's, on a checkout nothing else is writing to.
[[ -z "$(nokey git -C "$repo" status --porcelain --untracked-files=all)" ]] || refuse "the checkout changed during the tests or the build"
[[ "$(nokey git -C "$repo" rev-parse HEAD)" == "$head" ]] || refuse "HEAD moved during the tests or the build"
nokey "$bin" check ${root_args[@]+"${root_args[@]}"} >&2 || refuse "the held-out check refused the run"
exec "$bin" run ${root_args[@]+"${root_args[@]}"}
