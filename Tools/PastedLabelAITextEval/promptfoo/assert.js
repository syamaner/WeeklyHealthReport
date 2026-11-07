// Custom promptfoo assertion (docs/pasted-label-ai-text-v1.md 5.2 item 2, #416 A2). Scoring stays in
// the shipped Swift code: this passes the provider's send record to `PastedLabelAITextEval score`,
// which runs the envelope check, the reader and its checks in product order and the scorer, and
// returns its pass, score and per-label counts. promptfoo's own pass rates are not results (5.2 item 4).
'use strict';

const { execFileSync } = require('node:child_process');
const path = require('node:path');

module.exports = (output, context) => {
  const label = String(context.vars.label_id || '');
  if (!/^[A-Za-z0-9._-]+$/.test(label) || label.startsWith('.')) return { pass: false, score: 0, reason: `bad label_id ${label}` };
  const data = process.env.PASTED_LABEL_AI_TEXT_EVAL_DATA;
  const bin = process.env.PASTED_LABEL_AI_TEXT_EVAL_BIN;
  let scored;
  try {
    const stdout = execFileSync(bin, [
      'score', '--case', path.join(data, 'cases', `${label}.json`), '--text', path.join(data, 'texts', `${label}.txt`), '--send', '-',
    ], { input: String(output), maxBuffer: 4 * 1024 * 1024, env: { PATH: process.env.PATH } });
    scored = JSON.parse(String(stdout));
  } catch (e) {
    return { pass: false, score: 0, reason: `score failed: ${String(e.stderr || e.message).trim()}` };
  }
  // The tap ends after scoring (5.3): the tap latency is end minus the provider's start. The
  // attempt-only time from `send` is kept apart as a diagnostic.
  const ended = Date.now();
  let started = null;
  try {
    started = JSON.parse(String(output)).tap_started_at_ms;
  } catch (e) {
    started = null;
  }
  const named = Object.assign({}, scored.named_scores);
  if (typeof started === 'number' && ended >= started) named.tap_latency_seconds = (ended - started) / 1000;
  if (typeof scored.latency_seconds === 'number') named.attempt_latency_seconds = scored.latency_seconds;
  const s = scored.score;
  return {
    pass: scored.pass,
    score: scored.f1,
    reason: `${s.outcome}${s.decline_reasons.length ? ' ' + s.decline_reasons.join(',') : ''}${s.failure ? ' ' + s.failure : ''}: `
      + `${s.fields_correct}/${s.fields_printed} printed fields correct, ${s.fields_wrong} wrong (${s.wrong_silent} silent), `
      + `${s.attention_items} attention items`,
    namedScores: named,
  };
};
