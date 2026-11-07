// Custom promptfoo provider (docs/pasted-label-ai-text-v1.md 5.2 item 1, #416 A2). promptfoo only
// orchestrates: every call runs `PastedLabelAITextEval send`, which builds the request with the
// shipped Swift builder, reserves W in the spend ledger and refuses past a stop, keeps its own
// response cache, and in A2 sends only through the directory fake transport. This file never
// opens a network connection and never sees a key.
'use strict';

const { execFile } = require('node:child_process');
const path = require('node:path');

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} must be set (see run-smoke.sh)`);
  return value;
}

class PastedLabelAITextSendProvider {
  constructor(options = {}) {
    this.providerId = options.id || 'pasted-label-ai-text-send';
    this.config = options.config || {};
  }

  id() {
    return this.providerId;
  }

  async callApi(_prompt, context) {
    const vars = (context && context.vars) || {};
    const label = String(vars.label_id || '');
    if (!/^[A-Za-z0-9._-]+$/.test(label) || label.startsWith('.')) return { error: `bad label_id ${label}` };
    const bin = required('PASTED_LABEL_AI_TEXT_EVAL_BIN');
    const data = required('PASTED_LABEL_AI_TEXT_EVAL_DATA');
    const run = required('PASTED_LABEL_AI_TEXT_EVAL_RUN');
    const fake = required('PASTED_LABEL_AI_TEXT_EVAL_FAKE_TRANSPORT');
    const args = [
      'send', '--label-id', label, '--text', path.join(data, 'texts', `${label}.txt`),
      '--route', String(this.config.route), '--cell', String(this.config.cell),
      '--ledger', path.join(run, 'spend-ledger.json'), '--cache', path.join(run, 'response-cache'),
      '--fake-transport', fake,
    ];
    // The tap starts here (5.3: latency per tap, from the tap to Confirm or failure, including
    // retries): before the catalogue check, the reservation, the send and the settle. assert.js
    // records the end after scoring, and the statistics report end minus start.
    const started = Date.now();
    const result = await new Promise((resolve) => {
      execFile(bin, args, { maxBuffer: 4 * 1024 * 1024, env: { PATH: process.env.PATH } }, (error, stdout, stderr) => {
        resolve({ code: error ? error.code : 0, stdout, stderr });
      });
    });
    if (!result.stdout) return { error: `send failed (${result.code}): ${String(result.stderr).trim()}` };
    let send;
    try {
      send = JSON.parse(result.stdout);
    } catch (e) {
      return { error: `send printed no JSON: ${e.message}` };
    }
    // The send record, with the tap's start added; `score` ignores the extra member.
    send.tap_started_at_ms = started;
    return {
      output: JSON.stringify(send),
      cost: Number(send.charged_usd),
      cached: Boolean(send.cached),
      // promptfoo's latency field holds the send process's wall time; the tap latency comes from assert.js.
      latencyMs: Date.now() - started,
      tokenUsage: {
        prompt: send.prompt_tokens || 0,
        completion: send.completion_tokens || 0,
        total: (send.prompt_tokens || 0) + (send.completion_tokens || 0),
      },
      metadata: { attempt: send.attempt, requestSha256: send.request_sha256, costKnown: send.cost_usd != null, cell: send.cell },
    };
  }
}

module.exports = PastedLabelAITextSendProvider;
