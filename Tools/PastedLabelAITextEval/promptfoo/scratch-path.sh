# Shared by run-smoke.sh, run-live.sh and run-adversarial-fake.sh (sourced, not run): the scratch path checks (Qodo finding 5
# on A2). `resolve_scratch PATH HERE` prints the fully resolved scratch path, or prints the reason to
# stderr and returns 2. It creates nothing, so a refused path is never created.
#
# - An existing path is resolved through `cd -P` (every symbolic link, the last component included);
#   a new one through its existing parent. A dangling symbolic link is refused.
# - The path may not be inside the repository (any path under its top level) or promptfoo's home
#   default (~/.promptfoo).
resolve_scratch() {
  local scratch="$1" here="$2" parent repo home
  if [[ -L "$scratch" && ! -e "$scratch" ]]; then echo "the scratch directory is a dangling symbolic link" >&2; return 2; fi
  if [[ -e "$scratch" ]]; then
    scratch="$(cd -P "$scratch" 2>/dev/null && pwd -P)" || { echo "the scratch path is not a directory" >&2; return 2; }
  else
    parent="$(cd -P "$(dirname "$scratch")" 2>/dev/null && pwd -P)" || { echo "the scratch directory's parent must exist" >&2; return 2; }
    case "$(basename "$scratch")" in .|..) echo "the scratch directory must be named" >&2; return 2 ;; esac
    scratch="$parent/$(basename "$scratch")"
  fi
  repo="$(git -C "$here" rev-parse --show-toplevel)"
  repo="$(cd -P "$repo" && pwd -P)"
  case "$scratch/" in
    "$repo"/*) echo "the scratch directory must be outside the repository ($repo)" >&2; return 2 ;;
  esac
  home="$(cd -P "$HOME" && pwd -P)"
  case "$scratch/" in "$home"/.promptfoo/*) echo "the scratch directory must not be promptfoo's home default" >&2; return 2 ;; esac
  echo "$scratch"
}
