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
fs.writeFileSync(stub, `#!${process.execPath}
process.stdout.write(JSON.stringify({ attempt: 'responded', charged_usd: '0', cached: false, args: process.argv.slice(2),
  env_names: Object.keys(process.env).sort(), key_matches: process.env.OPENROUTER_API_KEY === ${JSON.stringify(KEY)} }));
`, { mode: 0o700 });

const saved = { ...process.env };
function setEnv(values) {
  for (const name of Object.keys(process.env)) if (name !== 'PATH') delete process.env[name];
  Object.assign(process.env, { PASTED_LABEL_AI_TEXT_EVAL_BIN: stub, PASTED_LABEL_AI_TEXT_EVAL_DATA: dir, PASTED_LABEL_AI_TEXT_EVAL_RUN: dir }, values);
}

async function call(values) {
  setEnv(values);
  const provider = new Provider({ config: { route: 'gemini-4-argon-vertex-us', cell: 'test-cell' } });
  return provider.callApi('', { vars: { label_id: 'uk-test-01' } });
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
  for (const name of Object.keys(process.env)) delete process.env[name];
  Object.assign(process.env, saved);
  fs.rmSync(dir, { recursive: true, force: true });
  process.exit(failures ? 1 : 0);
})();
