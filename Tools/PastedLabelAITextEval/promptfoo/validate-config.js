#!/usr/bin/env node
// Checks that a promptfoo config is exactly the shape make-config.js writes, before run-live.sh lets
// promptfoo read it with OPENROUTER_API_KEY in the environment (#416 A3). promptfoo loads and runs
// code named by a config (a `file://` provider, a javascript or python assertion, a transform, an
// extension, a prompt or var given as a `file://` script, and more), so a config naming anything but
// this checkout's provider.js and assert.js could read the key or send requests without going
// through `PastedLabelAITextEval send`. This is a whitelist of what make-config.js emits, not a list
// of what promptfoo can load: any other key, value or shape is refused.
//
// Usage: node validate-config.js CONFIG
// Exits 0 and prints the validated config on standard output (run-live.sh hands promptfoo that
// copy, so the file cannot change between the check and the run), or exits 2 with a reason.
//
// The accepted file is make-config.js's: `#` comment lines, then the config as
// `JSON.stringify(config, null, 2)` and a newline, byte for byte. JSON is YAML, and requiring the
// canonical form means promptfoo's YAML reading and this JSON reading are the same document.
// make-config.js runs this same check on what it is about to write, so the two cannot drift.
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const PROMPT_VERSIONS = { v1: 'prompt-v1', v2: 'prompt-v2' };
const NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const FRESH_RUN = /^[a-z](?:[a-z0-9]|-(?=[a-z0-9])){0,15}$/;
const HEADER_LINE = /^#[ -~]*$/;
const DESCRIPTION = /^pasted-label-ai-text A3 ([A-Za-z0-9._-]+): (v1|v2) x (\d+) route candidates x (\d+) cases(?:, fresh run ([a-z0-9-]+))?$/;

class ConfigRefusal extends Error {}

function refuse(message) {
  throw new ConfigRefusal(message);
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
}

// Exactly these keys, in any order; the optional ones may be absent.
function keys(value, where, required, optional = []) {
  if (!isPlainObject(value)) refuse(`${where} must be an object`);
  const allowed = new Set([...required, ...optional]);
  for (const key of Object.keys(value)) if (!allowed.has(key)) refuse(`${where} may not hold ${JSON.stringify(key)}`);
  for (const key of required) if (!Object.prototype.hasOwnProperty.call(value, key)) refuse(`${where} must hold ${key}`);
}

function nonEmptyArray(value, where) {
  if (!Array.isArray(value) || value.length === 0) refuse(`${where} must be a non-empty list`);
  return value;
}

function name(value, where) {
  if (typeof value !== 'string' || !NAME.test(value)) refuse(`${where} must be a name (${NAME})`);
  return value;
}

// The code a config may name: this checkout's provider.js and assert.js, resolved.
function allowedCode(here) {
  const dir = fs.realpathSync(here);
  return {
    provider: `file://${fs.realpathSync(path.join(dir, 'provider.js'))}`,
    assert: `file://${fs.realpathSync(path.join(dir, 'assert.js'))}`,
  };
}

// The config object, as make-config.js builds it.
function validateConfig(config, here) {
  const code = allowedCode(here);
  keys(config, 'the config', ['description', 'sharing', 'prompts', 'providers', 'defaultTest', 'tests']);
  if (config.sharing !== false) refuse('sharing must be false');

  const prompts = nonEmptyArray(config.prompts, 'prompts');
  if (prompts.length !== 1) refuse('prompts must hold exactly one prompt');
  keys(prompts[0], 'the prompt', ['id', 'label', 'raw']);
  const version = Object.keys(PROMPT_VERSIONS).find((v) => PROMPT_VERSIONS[v] === prompts[0].id);
  if (version === undefined) refuse(`the prompt id must be one of ${Object.values(PROMPT_VERSIONS).join(', ')}`);
  if (prompts[0].label !== prompts[0].id) refuse('the prompt label must equal its id');
  if (prompts[0].raw !== '{{label_id}}') refuse('the prompt must be the raw template {{label_id}}');

  if (typeof config.description !== 'string') refuse('description must be a string');
  const described = DESCRIPTION.exec(config.description);
  if (!described) refuse('description is not one make-config.js writes');
  const [, suite, describedVersion, describedCandidates, describedCases, describedFreshRun] = described;
  if (describedVersion !== version) refuse('description names another prompt version');

  const providers = nonEmptyArray(config.providers, 'providers');
  if (Number(describedCandidates) !== providers.length) refuse('description counts another number of providers');
  const routes = new Set();
  let freshRun;
  providers.forEach((provider, index) => {
    const where = `provider ${index + 1}`;
    keys(provider, where, ['id', 'label', 'config']);
    if (provider.id !== code.provider) refuse(`${where} must be this checkout's provider.js (${code.provider})`);
    const route = name(provider.label, `${where} label`);
    if (routes.has(route)) refuse(`route candidate ${route} is named twice`);
    routes.add(route);
    keys(provider.config, `${where} config`, ['route', 'cell', 'promptVersion'], ['freshRun']);
    if (provider.config.route !== route) refuse(`${where} config route must equal its label`);
    if (provider.config.promptVersion !== prompts[0].id) refuse(`${where} config promptVersion must be the prompt's`);
    const own = provider.config.freshRun;
    if (own !== undefined && (typeof own !== 'string' || !FRESH_RUN.test(own))) refuse(`${where} config freshRun is not a fresh run name`);
    if (index === 0) freshRun = own;
    else if (own !== freshRun) refuse('every provider must name the same fresh run');
    if (provider.config.cell !== `${version}__${route}__${suite}`) refuse(`${where} config cell must be ${version}__${route}__${suite}`);
  });
  if (describedFreshRun !== freshRun) refuse('description names another fresh run');
  const baseSuite = freshRun === undefined ? suite : suite.endsWith(`-${freshRun}`) ? suite.slice(0, -(freshRun.length + 1)) : undefined;
  if (baseSuite === undefined || !NAME.test(baseSuite) || baseSuite.includes('__')) refuse(`bad suite name ${suite}`);

  keys(config.defaultTest, 'defaultTest', ['assert']);
  const asserts = nonEmptyArray(config.defaultTest.assert, 'defaultTest assert');
  if (asserts.length !== 1) refuse('defaultTest must hold exactly one assertion');
  keys(asserts[0], 'the assertion', ['type', 'value']);
  if (asserts[0].type !== 'javascript' || asserts[0].value !== code.assert) refuse(`the assertion must be this checkout's assert.js (${code.assert})`);

  const tests = nonEmptyArray(config.tests, 'tests');
  if (Number(describedCases) !== tests.length) refuse('description counts another number of cases');
  const labels = new Set();
  tests.forEach((test, index) => {
    const where = `test ${index + 1}`;
    keys(test, where, ['vars']);
    keys(test.vars, `${where} vars`, ['label_id']);
    const label = name(test.vars.label_id, `${where} label_id`);
    if (labels.has(label)) refuse(`case ${label} is tested twice`);
    labels.add(label);
  });
  return config;
}

// The file's text: `#` header lines, then the canonical JSON. Returns the config object.
function validateConfigText(text, here) {
  if (typeof text !== 'string') refuse('the config must be text');
  const lines = text.split('\n');
  let start = 0;
  while (start < lines.length && lines[start].startsWith('#')) {
    if (!HEADER_LINE.test(lines[start])) refuse(`header line ${start + 1} holds characters make-config.js never writes`);
    start += 1;
  }
  const body = lines.slice(start).join('\n');
  let config;
  try {
    config = JSON.parse(body);
  } catch (e) {
    refuse('the config is not the JSON make-config.js writes');
  }
  if (body !== JSON.stringify(config, null, 2) + '\n') refuse('the config is not in the exact form make-config.js writes');
  return validateConfig(config, here);
}

module.exports = { PROMPT_VERSIONS, NAME, FRESH_RUN, ConfigRefusal, validateConfig, validateConfigText };

if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.length !== 1) {
    process.stderr.write('usage: node validate-config.js CONFIG\n');
    process.exit(2);
  }
  let text;
  try {
    text = fs.readFileSync(args[0], 'utf8');
    validateConfigText(text, __dirname);
  } catch (e) {
    const reason = e instanceof ConfigRefusal ? e.message : `the config could not be read (${e.code || e.message})`;
    process.stderr.write(`validate-config: refused: ${reason}\n`);
    process.exit(2);
  }
  process.stdout.write(text);
}
