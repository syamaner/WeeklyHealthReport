// Tests provider.js's two modes without promptfoo, the Swift tool or a network: a stub `send`
// binary prints the arguments it was given and the names of its environment, so the test checks
// that the key reaches the child only in live mode, and never on its command line.
// Usage: node tests/test-provider-modes.js
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const Provider = require('../provider.js');

const KEY = 'sk-or-v1-synthetic-provider-test-0123456789';
const dir = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'provider-modes-'));
const stub = path.join(dir, 'send-stub');
// The stub records the prompt version it was asked for, as `send` does, except for the label
// `uk-wrong-version`, where it records prompt-v1 whatever it was asked, and `uk-no-version`, where it
// records none. It records the cell and the fresh run it was given, as `send` does, except for
// `uk-wrong-cell` (another cell), `uk-wrong-run` (fresh run r9) and `uk-no-run` (no fresh run).
fs.writeFileSync(stub, `#!${process.execPath}
const args = process.argv.slice(2);
const label = args[args.indexOf('--label-id') + 1];
const asked = args.includes('--prompt-version') ? args[args.indexOf('--prompt-version') + 1] : 'prompt-v1';
const record = { attempt: 'responded', charged_usd: '0', cached: false, args,
  env_names: Object.keys(process.env).sort(), key_matches: process.env.OPENROUTER_API_KEY === ${JSON.stringify(KEY)} };
if (label !== 'uk-no-version') record.prompt_version = label === 'uk-wrong-version' ? 'prompt-v1' : asked;
record.cell = label === 'uk-wrong-cell' ? 'other-cell' : args[args.indexOf('--cell') + 1];
if (label === 'uk-wrong-run') record.fresh_run = 'r9';
else if (label !== 'uk-no-run' && args.includes('--fresh-run')) record.fresh_run = args[args.indexOf('--fresh-run') + 1];
process.stdout.write(JSON.stringify(record));
`, { mode: 0o700 });

const saved = { ...process.env };
function setEnv(values) {
  for (const name of Object.keys(process.env)) if (name !== 'PATH') delete process.env[name];
  Object.assign(process.env, { PASTED_LABEL_AI_TEXT_EVAL_BIN: stub, PASTED_LABEL_AI_TEXT_EVAL_DATA: dir, PASTED_LABEL_AI_TEXT_EVAL_RUN: dir }, values);
}

async function call(values, config = {}, label = 'uk-test-01') {
  setEnv(values);
  const provider = new Provider({ config: { route: 'gemini-4-argon-vertex-us', cell: 'test-cell', ...config } });
  return provider.callApi('', { vars: { label_id: label } });
}

let failures = 0;
async function check(name, body) {
  try {
    await body();
    console.log(`ok: ${name}`);
  } catch (e) {
    failures += 1;
    console.error(`FAIL: ${name}: ${e.message}`);
  }
}

(async () => {
  await check('fake mode passes --fake-transport and no key, even when one is set', async () => {
    const result = await call({ PASTED_LABEL_AI_TEXT_EVAL_FAKE_TRANSPORT: '/fake/dir', OPENROUTER_API_KEY: KEY });
    const send = JSON.parse(result.output);
    assert.deepEqual(send.args.slice(-2), ['--fake-transport', '/fake/dir']);
    assert.ok(!send.args.includes('--live'));
    assert.deepEqual(send.env_names.filter((n) => n !== '__CF_USER_TEXT_ENCODING'), ['PATH']);
  });
  await check('live mode passes --live and the key by environment only', async () => {
    const result = await call({ PASTED_LABEL_AI_TEXT_EVAL_LIVE: '1', OPENROUTER_API_KEY: KEY });
    const send = JSON.parse(result.output);
    assert.equal(send.args[send.args.length - 1], '--live');
    assert.ok(!send.args.includes('--fake-transport'));
    assert.ok(!send.args.some((a) => a.includes(KEY)), 'never on the command line');
    assert.deepEqual(send.env_names.filter((n) => n !== '__CF_USER_TEXT_ENCODING'), ['OPENROUTER_API_KEY', 'PATH']);
    assert.equal(send.key_matches, true);
    assert.ok(!JSON.stringify(result.metadata).includes(KEY));
  });
  await check('live mode refuses a fake transport directory too', async () => {
    const result = await call({ PASTED_LABEL_AI_TEXT_EVAL_LIVE: '1', OPENROUTER_API_KEY: KEY, PASTED_LABEL_AI_TEXT_EVAL_FAKE_TRANSPORT: '/fake/dir' });
    assert.match(result.error, /takes no PASTED_LABEL_AI_TEXT_EVAL_FAKE_TRANSPORT/);
  });
  await check('live mode refuses a missing key without calling send', async () => {
    const result = await call({ PASTED_LABEL_AI_TEXT_EVAL_LIVE: '1' });
    assert.match(result.error, /OPENROUTER_API_KEY must be set/);
    assert.equal(result.output, undefined);
  });
  await check('an unclear mode is refused rather than guessed', async () => {
    const result = await call({ PASTED_LABEL_AI_TEXT_EVAL_LIVE: 'true', OPENROUTER_API_KEY: KEY });
    assert.match(result.error, /must be 1 \(live\) or unset/);
    assert.ok(!result.error.includes(KEY));
  });
  await check('fake mode still needs its directory', async () => {
    const result = await call({});
    assert.match(result.error, /PASTED_LABEL_AI_TEXT_EVAL_FAKE_TRANSPORT must be set/);
  });
  const fake = { PASTED_LABEL_AI_TEXT_EVAL_FAKE_TRANSPORT: '/fake/dir' };
  await check('a config without a prompt version passes none, so send uses its default', async () => {
    const send = JSON.parse((await call(fake)).output);
    assert.ok(!send.args.includes('--prompt-version'));
  });
  await check("the cell's prompt version is passed to send, and its record accepted", async () => {
    for (const version of ['prompt-v1', 'prompt-v2']) {
      const result = await call(fake, { promptVersion: version });
      assert.equal(result.error, undefined, result.error);
      const send = JSON.parse(result.output);
      assert.deepEqual(send.args.slice(send.args.indexOf('--prompt-version'), send.args.indexOf('--prompt-version') + 2), ['--prompt-version', version]);
      assert.equal(send.prompt_version, version);
    }
  });
  await check("a send record under another prompt version than the cell's is refused", async () => {
    const result = await call(fake, { promptVersion: 'prompt-v2' }, 'uk-wrong-version');
    assert.match(result.error, /send used prompt prompt-v1, but the cell is for prompt-v2/);
    assert.equal(result.output, undefined);
  });
  await check('a send record without a prompt version is refused when the cell names one', async () => {
    const result = await call(fake, { promptVersion: 'prompt-v2' }, 'uk-no-version');
    assert.match(result.error, /but the cell is for prompt-v2/);
  });
  await check('a prompt version outside the closed set is refused without calling send', async () => {
    for (const version of ['prompt-v3', '--live', '']) {
      const result = await call(fake, { promptVersion: version });
      assert.match(result.error, /unknown prompt version/, version);
      assert.equal(result.output, undefined);
    }
  });
  await check('a config without a fresh run passes none, and its record carries none', async () => {
    const result = await call(fake, { promptVersion: 'prompt-v2' });
    assert.equal(result.error, undefined, result.error);
    const send = JSON.parse(result.output);
    assert.ok(!send.args.includes('--fresh-run'));
    assert.equal(result.metadata.freshRun, null);
  });
  await check("the cell's fresh run is passed to send, and its record accepted", async () => {
    for (const run of ['r2', 'r3', 'noise-a']) {
      const result = await call(fake, { promptVersion: 'prompt-v2', cell: `v2__gemini-4-argon-vertex-us__tuning-${run}`, freshRun: run });
      assert.equal(result.error, undefined, result.error);
      const send = JSON.parse(result.output);
      const at = send.args.indexOf('--fresh-run');
      assert.deepEqual(send.args.slice(at, at + 2), ['--fresh-run', run]);
      assert.equal(send.args[send.args.indexOf('--cell') + 1], `v2__gemini-4-argon-vertex-us__tuning-${run}`);
      assert.equal(result.metadata.freshRun, run);
    }
  });
  await check("a send record for another cell than the provider's is refused", async () => {
    const result = await call(fake, { promptVersion: 'prompt-v2' }, 'uk-wrong-cell');
    assert.match(result.error, /send recorded cell other-cell, but the provider's cell is test-cell/);
    assert.equal(result.output, undefined);
  });
  await check("a send record under another fresh run than the cell's is refused", async () => {
    const wrong = await call(fake, { freshRun: 'r2' }, 'uk-wrong-run');
    assert.match(wrong.error, /send recorded fresh run r9, but the cell's is r2/);
    assert.equal(wrong.output, undefined);
    const missing = await call(fake, { freshRun: 'r2' }, 'uk-no-run');
    assert.match(missing.error, /send recorded fresh run none, but the cell's is r2/);
    const unasked = await call(fake, {}, 'uk-wrong-run');
    assert.match(unasked.error, /send recorded fresh run r9, but the cell's is none/);
  });
  await check('a fresh run outside the grammar is refused without calling send', async () => {
    for (const run of ['', 'R2', '2r', 'r_2', 'r2-', 'r--2', '--live', 'r2\n', 'r12345678901234567', 2]) {
      const result = await call(fake, { freshRun: run });
      assert.match(result.error, /bad fresh run/, String(run));
      assert.equal(result.output, undefined);
    }
  });
  for (const name of Object.keys(process.env)) delete process.env[name];
  Object.assign(process.env, saved);
  fs.rmSync(dir, { recursive: true, force: true });
  process.exit(failures ? 1 : 0);
})();
