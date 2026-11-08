// Custom promptfoo provider (docs/pasted-label-ai-text-v1.md 5.2 item 1, #416 A2 and A3). promptfoo
// only orchestrates: every call runs `PastedLabelAITextEval send`, which builds the request with the
// shipped Swift builder, reserves W in the spend ledger and refuses past a stop, and keeps its own
// response cache. This file never opens a network connection.
//
// Two modes, chosen explicitly:
// - fake (the default; run-smoke.sh): `send --fake-transport DIR`; the child's environment is PATH only.
// - live (PASTED_LABEL_AI_TEXT_EVAL_LIVE=1; run-live.sh, A3 under T1 to T6): `send --live`; the
//   child's environment is PATH and OPENROUTER_API_KEY, passed through without being read, logged
//   or put on a command line. A fake transport directory set at the same time is refused.
'use strict';

const { execFile } = require('node:child_process');
const path = require('node:path');

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} must be set (see run-smoke.sh or run-live.sh)`);
  return value;
}

// 'live' or 'fake'; anything but unset, empty, 0 or 1 is refused rather than guessed.
function mode() {
  const value = process.env.PASTED_LABEL_AI_TEXT_EVAL_LIVE;
  if (value === undefined || value === '' || value === '0') return 'fake';
  if (value === '1') return 'live';
  throw new Error('PASTED_LABEL_AI_TEXT_EVAL_LIVE must be 1 (live) or unset (fake)');
}

// The transport arguments and the child's whole environment for one mode.
function connection() {
  const env = { PATH: process.env.PATH };
  if (mode() === 'live') {
    if (process.env.PASTED_LABEL_AI_TEXT_EVAL_FAKE_TRANSPORT) {
      throw new Error('a live run takes no PASTED_LABEL_AI_TEXT_EVAL_FAKE_TRANSPORT');
    }
    if (!process.env.OPENROUTER_API_KEY) throw new Error('OPENROUTER_API_KEY must be set for a live run (see run-live.sh)');
    env.OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
    return { args: ['--live'], env };
  }
  return { args: ['--fake-transport', required('PASTED_LABEL_AI_TEXT_EVAL_FAKE_TRANSPORT')], env };
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
    // The route and the cell come from the provider's config (make-config.js writes one provider per
    // route candidate, cell `<prompt-version>__<candidate>__<suite>`); neither is ever guessed.
    const { route, cell, promptVersion } = this.config;
    if (typeof route !== 'string' || !route || typeof cell !== 'string' || !cell) return { error: 'the provider config needs route and cell' };
    const bin = required('PASTED_LABEL_AI_TEXT_EVAL_BIN');
    const data = required('PASTED_LABEL_AI_TEXT_EVAL_DATA');
    const run = required('PASTED_LABEL_AI_TEXT_EVAL_RUN');
    let link;
    try {
      link = connection();
    } catch (e) {
      return { error: e.message };
    }
    const args = [
      'send', '--label-id', label, '--text', path.join(data, 'texts', `${label}.txt`),
      '--route', route, '--cell', cell,
      '--ledger', path.join(run, 'spend-ledger.json'), '--cache', path.join(run, 'response-cache'),
      ...link.args,
    ];
    // The tap starts here (5.3: latency per tap, from the tap to Confirm or failure, including
    // retries): before the catalogue check, the reservation, the send and the settle. assert.js
    // records the end after scoring, and the statistics report end minus start.
    const started = Date.now();
    const result = await new Promise((resolve) => {
      execFile(bin, args, { maxBuffer: 4 * 1024 * 1024, env: link.env }, (error, stdout, stderr) => {
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
    // The cell names a prompt version; a record sent under another one is refused, not scored (A3b).
    if (promptVersion !== undefined && send.prompt_version !== undefined && send.prompt_version !== promptVersion) {
      return { error: `send used prompt ${send.prompt_version}, but the cell is for ${promptVersion}` };
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
      metadata: {
        attempt: send.attempt, attempts: send.attempts, requestSha256: send.request_sha256, costKnown: send.cost_usd != null, cell: send.cell,
      },
    };
  }
}

module.exports = PastedLabelAITextSendProvider;
module.exports.connection = connection;
