#!/usr/bin/env bash
# Tests run-live.sh's argument checks, its config check and its refusal without a key, without running
# anything: every case here exits before the build. Only the config and option refusals set
# OPENROUTER_API_KEY, to a dummy value, with `node` and `swift` shims on PATH that record whether the
# key reached node (the config check) and whether the build started; nothing can be sent. Each
# refusal must exit 2 and create nothing. Usage: tests/test-run-live.sh
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
outside="$(mktemp -d "${TMPDIR:-/tmp}/run-live-test.XXXXXX")"
trap 'rm -rf "$outside"' EXIT
status=0
mkdir -p "$outside/data/texts" "$outside/data/cases" "$outside/empty-data" "$outside/sealed/uk-english-v2/texts" "$outside/sealed/uk-english-v2/cases"
# A config as make-config.js writes it, for the committed synthetic adversarial suite.
node "$here/make-config.js" --data "$here/adversarial" --candidates gemini-4-argon-vertex-us,mistral-large-4-zdr --prompt-version v1 --suite adversarial --out "$outside/config.yaml" >/dev/null
# Configs that name code promptfoo would load, each from the generated one, in make-config's exact form.
mutate() {
  node -e '
    const fs = require("node:fs");
    const [from, to, kind] = process.argv.slice(1);
    const text = fs.readFileSync(from, "utf8");
    const at = text.indexOf("{");
    const config = JSON.parse(text.slice(at));
    if (kind === "provider") config.providers[0].id = "file:///tmp/elsewhere/provider.js";
    if (kind === "assertion") config.defaultTest.assert.push({ type: "javascript", value: "output.length > 0" });
    if (kind === "prompt") config.prompts = ["file:///tmp/elsewhere/prompt.js"];
    if (kind === "extensions") config.extensions = ["file:///tmp/elsewhere/extension.js:hook"];
    if (kind === "transform") config.defaultTest.options = { transform: "file:///tmp/elsewhere/transform.js" };
    fs.writeFileSync(to, text.slice(0, at) + JSON.stringify(config, null, 2) + "\n");
  ' "$outside/config.yaml" "$outside/config-$1.yaml" "$1"
}
for kind in provider assertion prompt extensions transform; do mutate "$kind"; done
printf 'description: test\nproviders:\n  - file:///tmp/elsewhere/provider.js\n' > "$outside/config-yaml.yaml"
# Shims: node records whether it saw the key, then runs the real node; swift records that a build began.
mkdir -p "$outside/shims"
real_node="$(command -v node)"
printf '#!/bin/sh\nif [ -n "${OPENROUTER_API_KEY+x}" ]; then echo key >> "%s/node-saw-key"; fi\nexec "%s" "$@"\n' "$outside" "$real_node" > "$outside/shims/node"
printf '#!/bin/sh\nif [ -n "${OPENROUTER_API_KEY+x}" ]; then echo key >> "%s/swift-saw-key"; fi\necho build >> "%s/swift-ran"\nexit 1\n' "$outside" "$outside" > "$outside/shims/swift"
chmod +x "$outside/shims/node" "$outside/shims/swift"
# Data directories with symbolic links: into the stand-in sealed set (an empty temporary directory
# named uk-english-v2, never the sealed set) and to a file outside the data directory.
printf 'synthetic stand-in\n' > "$outside/sealed/uk-english-v2/texts/held-01.txt"
printf 'Fat 5g\n' > "$outside/other.txt"
mkdir -p "$outside/linked-sealed/texts" "$outside/linked-sealed/cases" "$outside/linked-outside/texts" "$outside/linked-outside/cases"
ln -s "$outside/sealed/uk-english-v2/texts/held-01.txt" "$outside/linked-sealed/texts/x-01.txt"
ln -s "$outside/other.txt" "$outside/linked-outside/texts/x-01.txt"
ln -s "$outside/sealed/uk-english-v2" "$outside/innocent"
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
# refused_with_key NAME WANT ARGS...: as refused, with a dummy key set and the shims first on PATH;
# the key must never reach node and the build must never start.
refused_with_key() {
  local name="$1" want="$2" out got=0; shift 2
  rm -f "$outside/node-saw-key" "$outside/swift-ran"
  out="$(env PATH="$outside/shims:$PATH" OPENROUTER_API_KEY=dummy-not-a-key "$@" 2>&1 >/dev/null)" || got=$?
  if [[ "$got" != 2 ]]; then
    echo "FAIL: $name exited $got, expected 2" >&2; status=1
  elif [[ "$out" != *"$want"* ]]; then
    echo "FAIL: $name said '$out', expected '$want'" >&2; status=1
  elif [[ -e "$outside/scratch" ]]; then
    echo "FAIL: $name created the scratch directory" >&2; status=1
  elif [[ -e "$outside/node-saw-key" ]]; then
    echo "FAIL: $name passed the key to node" >&2; status=1
  elif [[ -e "$outside/swift-ran" ]]; then
    echo "FAIL: $name started the build" >&2; status=1
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
refused "the sealed held-out set through a link" "held-out set" "$live" "$scratch" "$outside/config.yaml" "$outside/innocent"
refused "a text linked into the sealed set" "held-out set" "$live" "$scratch" "$outside/config.yaml" "$outside/linked-sealed"
refused "a text linked outside the data directory" "resolves outside the data directory" "$live" "$scratch" "$outside/config.yaml" "$outside/linked-outside"
refused "no key" "OPENROUTER_API_KEY must be set" "$live" "$scratch" "$outside/config.yaml" "$outside/data"
refused "an empty key" "OPENROUTER_API_KEY must be set" env OPENROUTER_API_KEY= "$live" "$scratch" "$outside/config.yaml" "$outside/data"
refused_with_key "a config naming a foreign provider" "not one make-config.js writes" "$live" "$scratch" "$outside/config-provider.yaml" "$outside/data"
refused_with_key "a config with an extra javascript assertion" "not one make-config.js writes" "$live" "$scratch" "$outside/config-assertion.yaml" "$outside/data"
refused_with_key "a config with a file:// prompt script" "not one make-config.js writes" "$live" "$scratch" "$outside/config-prompt.yaml" "$outside/data"
refused_with_key "a config with extensions" "not one make-config.js writes" "$live" "$scratch" "$outside/config-extensions.yaml" "$outside/data"
refused_with_key "a config with a transform" "not one make-config.js writes" "$live" "$scratch" "$outside/config-transform.yaml" "$outside/data"
refused_with_key "a hand-written YAML config" "not one make-config.js writes" "$live" "$scratch" "$outside/config-yaml.yaml" "$outside/data"
refused_with_key "a promptfoo option that loads code" "is not allowed by a live run" "$live" "$scratch" "$outside/config.yaml" "$outside/data" --prompts file:///tmp/elsewhere/prompt.js
refused_with_key "a numeric option without a number" "needs a number" "$live" "$scratch" "$outside/config.yaml" "$outside/data" -j file:///tmp/x
# The generated config passes the check: the run then stops only for the missing key, and the
# check ran without the key (none was set here, and the shim saw none).
rm -f "$outside/node-saw-key" "$outside/swift-ran"
refused "a generated config without a key" "OPENROUTER_API_KEY must be set" env PATH="$outside/shims:$PATH" "$live" "$scratch" "$outside/config.yaml" "$outside/data" --no-cache -j 2 --filter-pattern 'adv-.*'
if [[ -e "$outside/swift-ran" ]]; then echo "FAIL: the generated config started the build without a key" >&2; status=1; fi
# With a key and a generated config the run reaches the build: the builds must run without the key
# (SwiftPM evaluates package manifests), so the swift shim must never see it. The shim fails the build.
rm -f "$outside/node-saw-key" "$outside/swift-ran" "$outside/swift-saw-key"
env PATH="$outside/shims:$PATH" OPENROUTER_API_KEY=dummy-not-a-key "$live" "$scratch" "$outside/config.yaml" "$outside/data" >/dev/null 2>&1 || true
if [[ ! -e "$outside/swift-ran" ]]; then echo "FAIL: a generated config with a key did not reach the build" >&2; status=1
elif [[ -e "$outside/swift-saw-key" ]]; then echo "FAIL: the build saw the key" >&2; status=1
else echo "ok: the build runs without the key"; fi
rm -rf "$scratch"
if [[ -e "$repo/Tools/never-created" ]]; then echo "FAIL: a refused path was created" >&2; status=1; fi
exit "$status"
