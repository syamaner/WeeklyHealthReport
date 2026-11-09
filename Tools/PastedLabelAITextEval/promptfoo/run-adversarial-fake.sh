#!/usr/bin/env bash
# End-to-end fake check of the synthetic adversarial suite (docs/pasted-label-ai-text-v1.md 4.9 and
# 5.1, #416 A3b): the suite's committed config (adversarial/promptfooconfig.yaml), promptfoo,
# provider.js, `send --fake-transport`, assert.js and `score`, over canned replies only. Nothing is sent to OpenRouter or any provider.
# Usage: run-adversarial-fake.sh SCRATCH_DIR
#
# The gate passes only when every adversarial text passes: it ends declined, or reaches Confirm with
# no silent-error table (`ScoreCommand.passes`). Three runs, each with its own ledger and response
# cache (the request bodies are the same, so a shared cache would replay the first run's replies):
# - correct: what a correct model answers (adversarial/fake-correct). The gate must PASS.
# - flagged: eight deliberately wrong answers the shipped checks catch (adversarial/fake-flagged),
#   over the correct ones. Every wrong value carries an attention item, so the gate must still PASS.
# - silent: one deliberately wrong answer the checks cannot catch (adversarial/fake-silent: a table
#   read out of a chat message), over the correct ones. That text must FAIL as a silent-error table,
#   so the gate must FAIL. This proves the gate can fail.
# The script exits 0 only when all three verdicts are as expected.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scratch="${1:?usage: run-adversarial-fake.sh SCRATCH_DIR}"
# shellcheck source=scratch-path.sh
source "$here/scratch-path.sh"
scratch="$(resolve_scratch "$scratch" "$here")" || exit 2
mkdir -p "$scratch"
swift build --package-path "$here/.." -c debug --product PastedLabelAITextEval >&2
bin="$(swift build --package-path "$here/.." -c debug --show-bin-path)/PastedLabelAITextEval"
suite="$here/adversarial"
config="$suite/promptfooconfig.yaml"

# run KIND OVERLAY: one promptfoo run over the correct replies, with OVERLAY's replies (if any) on top.
run() {
  local kind="$1" overlay="$2" dir="$scratch/$1"
  rm -rf "$dir"
  mkdir -p "$dir/run" "$dir/fake"
  cp -R "$suite/fake-correct/catalogue" "$suite/fake-correct/responses" "$dir/fake/"
  if [[ -n "$overlay" ]]; then cp "$suite/$overlay/responses/"*.json "$dir/fake/responses/"; fi
  (
    cd "$here"
    env -i PATH="$PATH" HOME="$dir/home" \
      PROMPTFOO_DISABLE_TELEMETRY=1 PROMPTFOO_DISABLE_UPDATE=1 PROMPTFOO_DISABLE_SHARING=1 PROMPTFOO_DISABLE_REMOTE_GENERATION=1 \
      PROMPTFOO_CONFIG_DIR="$dir/promptfoo-config" PROMPTFOO_CACHE_PATH="$dir/promptfoo-cache" PROMPTFOO_LOG_DIR="$dir/promptfoo-logs" \
      HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 NO_PROXY= \
      PASTED_LABEL_AI_TEXT_EVAL_BIN="$bin" PASTED_LABEL_AI_TEXT_EVAL_DATA="$suite" PASTED_LABEL_AI_TEXT_EVAL_RUN="$dir/run" \
      PASTED_LABEL_AI_TEXT_EVAL_FAKE_TRANSPORT="$dir/fake" \
      "$here/node_modules/.bin/promptfoo" eval -c "$config" --no-progress-bar --no-cache --output "$dir/results.json" >"$dir/promptfoo.log" 2>&1 || true
  )
}

run correct ""
run flagged fake-flagged
run silent fake-silent

node - "$scratch" "$suite" <<'EOF'
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const [scratch, suite] = process.argv.slice(2);
const labels = fs.readdirSync(path.join(suite, 'cases')).filter((n) => n.endsWith('.json')).map((n) => n.slice(0, -5)).sort();
let ok = true;
// The committed config must test exactly the cases in cases/.
const listed = [...fs.readFileSync(path.join(suite, 'promptfooconfig.yaml'), 'utf8').matchAll(/label_id: ([A-Za-z0-9._-]+)/g)].map((m) => m[1]).sort();
if (listed.join() !== labels.join()) { console.log(`promptfooconfig.yaml tests ${listed.join(',')}, but cases/ holds ${labels.join(',')}`); ok = false; }
function verdict(kind, expectGate, expectFailing) {
  const file = path.join(scratch, kind, 'results.json');
  if (!fs.existsSync(file)) { console.log(`${kind}: no results (see ${path.join(scratch, kind, 'promptfoo.log')})`); ok = false; return; }
  const rows = JSON.parse(fs.readFileSync(file, 'utf8')).results.results;
  const byLabel = new Map(rows.map((r) => [r.vars.label_id, r]));
  const failing = labels.filter((l) => !byLabel.get(l) || !byLabel.get(l).success);
  const gate = labels.every((l) => byLabel.has(l)) && failing.length === 0 ? 'PASS' : 'FAIL';
  for (const l of labels) {
    const r = byLabel.get(l);
    const s = (r && r.namedScores) || {};
    const outcome = s.declined ? 'declined' : s.reached_confirm ? 'reached_confirm' : s.failed ? 'failed' : 'missing';
    console.log(`${kind}: ${r && r.success ? 'pass' : 'FAIL'} ${l} ${outcome} wrong=${s.fields_wrong ?? '-'} silent=${s.wrong_silent ?? '-'} attention=${s.attention_items ?? '-'}`);
  }
  const same = failing.length === expectFailing.length && failing.every((l, i) => l === expectFailing[i]);
  const silentShown = expectFailing.every((l) => (byLabel.get(l)?.namedScores || {}).silent_error_table === 1);
  const as = gate === expectGate && same && silentShown;
  console.log(`${kind}: gate ${gate} (${labels.length - failing.length}/${labels.length} texts pass); expected ${expectGate}${expectFailing.length ? ', failing ' + expectFailing.join(',') + ' as a silent-error table' : ''}: ${as ? 'as expected' : 'NOT AS EXPECTED'}`);
  ok = ok && as;
}
verdict('correct', 'PASS', []);
verdict('flagged', 'PASS', []);
verdict('silent', 'FAIL', ['adv-nonlabel-uk-01']);
console.log(ok ? 'adversarial fake check: OK' : 'adversarial fake check: FAILED');
process.exit(ok ? 0 : 1);
EOF
