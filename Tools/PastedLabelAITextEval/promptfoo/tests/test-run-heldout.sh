#!/usr/bin/env bash
# Tests run-heldout.sh's gates without a network, a real key or the sealed set: `git` and `swift` are
# shims on PATH that answer from files in a temporary directory, record what they were asked and
# whether they saw OPENROUTER_API_KEY, and the "built" held-out executable is a stub that records its
# arguments and whether it got the key. Each refusal must exit 2 and never reach the stub; the happy
# path must run the pin tests and the build without the key, then the stub with it.
# Usage: tests/test-run-heldout.sh
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
outside="$(mktemp -d "${TMPDIR:-/tmp}/run-heldout-test.XXXXXX")"
trap 'rm -rf "$outside"' EXIT
status=0
state="$outside/state"
mkdir -p "$outside/shims" "$outside/bin" "$state"
# git: fetch fails when state/fetch-fails exists; status fails when state/status-fails exists, else prints state/status; rev-parse prints state/head or state/main.
cat > "$outside/shims/git" <<EOF
#!/bin/sh
if [ -n "\${OPENROUTER_API_KEY+x}" ]; then echo git >> "$state/saw-key"; fi
for arg in "\$@"; do
  case "\$arg" in
    fetch) [ -e "$state/fetch-fails" ] && exit 1; exit 0 ;;
    status) [ -e "$state/status-fails" ] && exit 1; cat "$state/status" 2>/dev/null; exit 0 ;;
    HEAD) cat "$state/head"; exit 0 ;;
    origin/main) cat "$state/main"; exit 0 ;;
  esac
done
exit 1
EOF
# swift: records each call; test fails when state/tests-fail exists; --show-bin-path prints the stub's directory.
cat > "$outside/shims/swift" <<EOF
#!/bin/sh
if [ -n "\${OPENROUTER_API_KEY+x}" ]; then echo swift >> "$state/saw-key"; fi
echo "\$*" >> "$state/swift-calls"
case "\$1" in
  test) [ -e "$state/tests-fail" ] && exit 1; exit 0 ;;
  build) for arg in "\$@"; do [ "\$arg" = "--show-bin-path" ] && { echo "$outside/bin"; exit 0; }; done; exit 0 ;;
esac
exit 1
EOF
cat > "$outside/bin/PastedLabelAITextHeldOut" <<EOF
#!/bin/sh
if [ "\$1" = check ]; then
  echo "\$*" > "$state/checked"
  if [ -n "\${OPENROUTER_API_KEY:-}" ]; then echo key > "$state/check-had-key"; fi
  if [ -e "$state/check-fails" ]; then echo "check: refused" >&2; exit 2; fi
  echo '{"labels":24,"tier_a_labels":9}'
  exit 0
fi
echo "\$*" > "$state/ran"
if [ "\${OPENROUTER_API_KEY:-}" = "dummy-not-a-key" ]; then echo key > "$state/run-had-key"; fi
echo '{"labels":24}'
EOF
chmod +x "$outside/shims/git" "$outside/shims/swift" "$outside/bin/PastedLabelAITextHeldOut"
reset() {
  rm -f "$state"/*
  printf '%s\n' 1111111111111111111111111111111111111111 > "$state/head"
  printf '%s\n' 1111111111111111111111111111111111111111 > "$state/main"
}
wrapper="$here/run-heldout.sh"
# refused NAME WANT [KEY] ARGS...: exits 2 saying WANT, never reaches the stub, and git and swift never see the key.
refused() {
  local name="$1" want="$2" key="$3" out got=0; shift 3
  if [[ -n "$key" ]]; then
    out="$(env PATH="$outside/shims:$PATH" OPENROUTER_API_KEY="$key" "$wrapper" "$@" 2>&1 >/dev/null)" || got=$?
  else
    out="$(env -u OPENROUTER_API_KEY PATH="$outside/shims:$PATH" "$wrapper" "$@" 2>&1 >/dev/null)" || got=$?
  fi
  if [[ "$got" != 2 ]]; then echo "FAIL: $name exited $got, expected 2" >&2; status=1
  elif [[ "$out" != *"$want"* ]]; then echo "FAIL: $name said '$out', expected '$want'" >&2; status=1
  elif [[ -e "$state/ran" ]]; then echo "FAIL: $name ran the held-out executable" >&2; status=1
  elif [[ -e "$state/saw-key" ]]; then echo "FAIL: $name passed the key to git or swift" >&2; status=1
  else echo "ok: $name"; fi
}
reset; refused "a bad option" "usage" dummy-not-a-key --root /tmp/x
reset; refused "too many arguments" "usage" dummy-not-a-key --private-root /tmp/x extra
reset; refused "no key" "OPENROUTER_API_KEY must be set" ""
reset; out="$(env PATH="$outside/shims:$PATH" OPENROUTER_API_KEY= "$wrapper" 2>&1 >/dev/null)" && got=0 || got=$?
if [[ "$got" == 2 && "$out" == *"OPENROUTER_API_KEY must be set"* && ! -e "$state/swift-calls" ]]; then echo "ok: a key set to empty"; else echo "FAIL: a key set to empty" >&2; status=1; fi
reset; touch "$state/fetch-fails"; refused "a failed fetch" "git fetch origin failed" dummy-not-a-key
reset; printf ' M Tools/x.swift\n' > "$state/status"; refused "a dirty checkout" "not clean" dummy-not-a-key
reset; printf '?? scratch.txt\n' > "$state/status"; refused "an untracked file" "not clean" dummy-not-a-key
reset; touch "$state/status-fails"; refused "a failing git status" "git status failed" dummy-not-a-key
reset; printf '%s\n' 2222222222222222222222222222222222222222 > "$state/main"; refused "HEAD behind origin/main" "HEAD is not origin/main" dummy-not-a-key
reset; touch "$state/tests-fail"; refused "failing pin tests" "FreezePinTests or SealedTextPathTests failed" dummy-not-a-key
if [[ -e "$state/swift-calls" ]] && grep -q "^build" "$state/swift-calls"; then echo "FAIL: failing pin tests still built" >&2; status=1; fi
reset; touch "$state/check-fails"; refused "a refusing held-out check" "the held-out check refused the run" dummy-not-a-key
# The happy path: pin tests, then the build, both without the key; then the stub, with it.
reset
out="$(env PATH="$outside/shims:$PATH" OPENROUTER_API_KEY=dummy-not-a-key "$wrapper" --private-root "$outside/private" 2>/dev/null)" && got=0 || got=$?
if [[ "$got" != 0 ]]; then echo "FAIL: the happy path exited $got" >&2; status=1
elif [[ "$(cat "$state/ran")" != "run --private-root $outside/private" ]]; then echo "FAIL: the stub ran with '$(cat "$state/ran")'" >&2; status=1
elif [[ "$(cat "$state/checked" 2>/dev/null)" != "check --private-root $outside/private" ]]; then echo "FAIL: the check did not run first" >&2; status=1
elif [[ -e "$state/check-had-key" ]]; then echo "FAIL: the check saw the key" >&2; status=1
elif [[ ! -e "$state/run-had-key" ]]; then echo "FAIL: the held-out executable did not get the key" >&2; status=1
elif [[ -e "$state/saw-key" ]]; then echo "FAIL: git or swift saw the key" >&2; status=1
elif ! head -1 "$state/swift-calls" | grep -q "^test .*--filter FreezePinTests|SealedTextPathTests"; then echo "FAIL: the pin tests did not run first" >&2; status=1
elif ! grep -q "^build .*--product PastedLabelAITextHeldOut" "$state/swift-calls"; then echo "FAIL: the held-out product was not built" >&2; status=1
elif [[ "$out" != '{"labels":24}' ]]; then echo "FAIL: the output was '$out'" >&2; status=1
else echo "ok: the happy path runs the pins and the build without the key, then the runner with it"; fi
exit "$status"
