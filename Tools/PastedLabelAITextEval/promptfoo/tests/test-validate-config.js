// Tests validate-config.js without promptfoo, the Swift tool or a network: a config make-config.js
// writes passes, and every other shape is refused for its own reason, above all anything promptfoo
// would load and run (a foreign provider, another assertion, a prompt or var script, a transform,
// extensions, hooks). The data directory is the committed synthetic adversarial suite.
// Usage: node tests/test-validate-config.js
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const here = path.join(__dirname, '..');
const { validateConfigText, ConfigRefusal } = require('../validate-config.js');
const tmp = fs.realpathSync(fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'validate-config-')));

let failures = 0;
function check(name, body) {
  try {
    body();
    console.log(`ok: ${name}`);
  } catch (e) {
    failures += 1;
    console.log(`FAIL: ${name}: ${e.message}`);
  }
}

function generate(file, extra = []) {
  const args = ['--data', path.join(here, 'adversarial'), '--candidates', 'gemini-4-argon-vertex-us,mistral-large-4-zdr', '--prompt-version', 'v1', '--suite', 'adversarial', ...extra, '--out', file];
  const result = spawnSync(process.execPath, [path.join(here, 'make-config.js'), ...args], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return fs.readFileSync(file, 'utf8');
}

const text = generate(path.join(tmp, 'config.yaml'));
const freshText = generate(path.join(tmp, 'fresh.yaml'), ['--fresh-run', 'r2']);
const at = text.indexOf('{');
const header = text.slice(0, at);

// The generated text with its config changed, in make-config's exact form.
function mutated(change) {
  const config = JSON.parse(text.slice(at));
  change(config);
  return header + JSON.stringify(config, null, 2) + '\n';
}

function refused(textToCheck, want) {
  assert.throws(() => validateConfigText(textToCheck, here), (e) => e instanceof ConfigRefusal && e.message.includes(want), `expected a refusal saying '${want}'`);
}

const elsewhere = 'file:///tmp/elsewhere';
check('a config make-config.js writes passes', () => validateConfigText(text, here));
check('a fresh-run config make-config.js writes passes', () => validateConfigText(freshText, here));
check('the command line passes a generated config and prints it unchanged', () => {
  const result = spawnSync(process.execPath, [path.join(here, 'validate-config.js'), path.join(tmp, 'config.yaml')], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, text);
});
check('the command line refuses with exit 2 and prints nothing', () => {
  fs.writeFileSync(path.join(tmp, 'bad.yaml'), mutated((c) => { c.extensions = [`${elsewhere}/x.js:hook`]; }));
  const result = spawnSync(process.execPath, [path.join(here, 'validate-config.js'), path.join(tmp, 'bad.yaml')], { encoding: 'utf8' });
  assert.equal(result.status, 2);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /refused/);
});
check('a missing config is refused', () => {
  const result = spawnSync(process.execPath, [path.join(here, 'validate-config.js'), path.join(tmp, 'missing.yaml')], { encoding: 'utf8' });
  assert.equal(result.status, 2);
});

check('a foreign provider path is refused', () => refused(mutated((c) => { c.providers[0].id = `${elsewhere}/provider.js`; }), "this checkout's provider.js"));
check('another checkout\'s provider.js is refused', () => refused(mutated((c) => { c.providers[1].id = 'file:///Users/someone/other/Tools/PastedLabelAITextEval/promptfoo/provider.js'; }), "this checkout's provider.js"));
check('a built-in provider is refused', () => refused(mutated((c) => { c.providers[0].id = 'openrouter:some/model'; }), "this checkout's provider.js"));
check('a provider written as a string is refused', () => refused(mutated((c) => { c.providers[0] = `file://${path.join(fs.realpathSync(here), 'provider.js')}`; }), 'must be an object'));
check('a provider with extra keys is refused', () => refused(mutated((c) => { c.providers[0].transform = 'output'; }), 'may not hold "transform"'));
check('a provider config with extra keys is refused', () => refused(mutated((c) => { c.providers[0].config.apiKeyEnvar = 'OPENROUTER_API_KEY'; }), 'may not hold "apiKeyEnvar"'));
check('a provider whose cell is not its own is refused', () => refused(mutated((c) => { c.providers[0].config.cell = 'v1__other__adversarial'; }), 'cell must be'));
check('an extra javascript assertion is refused', () => refused(mutated((c) => { c.defaultTest.assert.push({ type: 'javascript', value: 'output.length > 0' }); }), 'exactly one assertion'));
check('another assertion script is refused', () => refused(mutated((c) => { c.defaultTest.assert[0].value = `${elsewhere}/assert.js`; }), "this checkout's assert.js"));
check('a python assertion is refused', () => refused(mutated((c) => { c.defaultTest.assert[0].type = 'python'; }), "this checkout's assert.js"));
check('a file:// prompt script is refused', () => refused(mutated((c) => { c.prompts = [`${elsewhere}/prompt.js`]; }), 'must be an object'));
check('a prompt with a function or another template is refused', () => refused(mutated((c) => { c.prompts[0].raw = `${elsewhere}/prompt.js`; }), 'raw template'));
check('extensions are refused', () => refused(mutated((c) => { c.extensions = [`${elsewhere}/extension.js:hook`]; }), 'may not hold "extensions"'));
check('a defaultTest transform is refused', () => refused(mutated((c) => { c.defaultTest.options = { transform: `${elsewhere}/transform.js` }; }), 'may not hold "options"'));
check('a defaultTest vars script is refused', () => refused(mutated((c) => { c.defaultTest.vars = { x: `${elsewhere}/vars.js` }; }), 'may not hold "vars"'));
check('a test assertion is refused', () => refused(mutated((c) => { c.tests[0].assert = [{ type: 'javascript', value: 'true' }]; }), 'may not hold "assert"'));
check('a var naming a file is refused', () => refused(mutated((c) => { c.tests[0].vars.label_id = `${elsewhere}/vars.js`; }), 'label_id must be a name'));
check('an extra var is refused', () => refused(mutated((c) => { c.tests[0].vars.other = 'x'; }), 'may not hold "other"'));
check('tests given as a file are refused', () => refused(mutated((c) => { c.tests = `${elsewhere}/tests.csv`; }), 'non-empty list'));
for (const key of ['scenarios', 'derivedMetrics', 'nunjucksFilters', 'env', 'evaluateOptions', 'outputPath', 'redteam', 'commandLineOptions', '__proto__']) {
  check(`a top-level ${key} is refused`, () => refused(mutated((c) => { Object.defineProperty(c, key, { value: `${elsewhere}/x.js`, enumerable: true }); }), `may not hold "${key}"`));
}
check('sharing switched on is refused', () => refused(mutated((c) => { c.sharing = true; }), 'sharing must be false'));
check('a description make-config.js never writes is refused', () => refused(mutated((c) => { c.description = '{{ env.OPENROUTER_API_KEY }}'; }), 'description'));
check('a provider count that disagrees with the description is refused', () => refused(mutated((c) => { c.providers.pop(); }), 'number of providers'));
check('a hand-written YAML config is refused', () => refused('description: x\nproviders:\n  - file:///tmp/elsewhere/provider.js\n', 'not the JSON'));
check('YAML after the JSON is refused', () => refused(text + 'extensions:\n  - x\n', 'not the JSON'));
check('JSON not in make-config.js form is refused', () => refused(header + JSON.stringify(JSON.parse(text.slice(at))) + '\n', 'exact form'));
check('a duplicate key is refused', () => refused(text.replace('"sharing": false,', '"sharing": false,\n  "sharing": false,'), 'exact form'));
check('a header line with a control character is refused', () => refused(`#\u0085 x\n${text}`, 'header line'));

fs.rmSync(tmp, { recursive: true, force: true });
if (failures > 0) {
  console.log(`${failures} failed`);
  process.exit(1);
}
console.log('all passed');
