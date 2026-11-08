// Tests make-config.js without promptfoo, the Swift tool or a network: its refusals, and the shape
// of the config it writes for the committed adversarial suite. Every data directory is synthetic;
// the `uk-english-v2` paths are empty temporary directories named so, never the sealed set.
// Usage: node tests/test-make-config.js
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const script = path.join(__dirname, '..', 'make-config.js');
const suite = path.join(__dirname, '..', 'adversarial');
const tmp = fs.realpathSync(fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'make-config-')));
const out = path.join(tmp, 'config.yaml');

function run(args) {
  const result = spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
  return { code: result.status, stderr: result.stderr };
}
function args(over = {}) {
  const base = { '--data': suite, '--candidates': 'gemini-4-argon-vertex-us,mistral-large-4-zdr', '--prompt-version': 'v1', '--suite': 'adversarial', '--out': out };
  return Object.entries({ ...base, ...over }).flat();
}

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

const sealed = path.join(tmp, 'uk-english-v2');
fs.mkdirSync(path.join(sealed, 'texts'), { recursive: true });
fs.mkdirSync(path.join(sealed, 'cases'), { recursive: true });
fs.symlinkSync(sealed, path.join(tmp, 'innocent'));

check('the sealed held-out set is refused by name', () => {
  const r = run(args({ '--data': sealed }));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /sealed held-out set/);
});
check('the sealed held-out set is refused through a symbolic link', () => {
  const r = run(args({ '--data': path.join(tmp, 'innocent') }));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /sealed held-out set/);
});
check('a config inside the repository is refused', () => {
  const r = run(args({ '--out': path.join(__dirname, 'generated.yaml') }));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /outside the repository/);
  assert.equal(fs.existsSync(path.join(__dirname, 'generated.yaml')), false);
});
check('a prompt version the builder cannot send is refused', () => {
  const r = run(args({ '--prompt-version': 'v3' }));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /cannot be sent/);
});
check('a repeated candidate, a missing option and a bad suite name are refused', () => {
  assert.equal(run(args({ '--candidates': 'mistral-large-4-zdr,mistral-large-4-zdr' })).code, 2);
  assert.equal(run(args().slice(2)).code, 2);
  assert.equal(run(args({ '--suite': 'a__b' })).code, 2);
});
check('a case without its text is refused', () => {
  const data = path.join(tmp, 'data');
  fs.mkdirSync(path.join(data, 'texts'), { recursive: true });
  fs.mkdirSync(path.join(data, 'cases'), { recursive: true });
  fs.writeFileSync(path.join(data, 'cases', 'x-01.json'), '{}');
  const r = run(args({ '--data': data }));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /texts\/x-01.txt is missing/);
});
check('one provider per candidate and one test per case, with the cell named by version, candidate and suite', () => {
  if (fs.existsSync(out)) fs.unlinkSync(out);
  const r = run(args());
  assert.equal(r.code, 0, r.stderr);
  const config = JSON.parse(fs.readFileSync(out, 'utf8').replace(/^#.*\n/gm, ''));
  const cases = fs.readdirSync(path.join(suite, 'cases')).map((n) => n.slice(0, -5)).sort();
  assert.deepEqual(config.tests.map((t) => t.vars.label_id), cases);
  assert.deepEqual(config.providers.map((p) => p.config), [
    { route: 'gemini-4-argon-vertex-us', cell: 'v1__gemini-4-argon-vertex-us__adversarial', promptVersion: 'prompt-v1' },
    { route: 'mistral-large-4-zdr', cell: 'v1__mistral-large-4-zdr__adversarial', promptVersion: 'prompt-v1' },
  ]);
  for (const p of config.providers) assert.equal(p.id, `file://${path.join(__dirname, '..', 'provider.js')}`);
  assert.equal(config.sharing, false);
  assert.equal(JSON.stringify(config).includes(suite), false, 'the config names no data path');
});

check('prompt v2 names its cells v2 and passes prompt-v2 to each provider', () => {
  if (fs.existsSync(out)) fs.unlinkSync(out);
  const r = run(args({ '--prompt-version': 'v2' }));
  assert.equal(r.code, 0, r.stderr);
  const text = fs.readFileSync(out, 'utf8');
  const config = JSON.parse(text.replace(/^#.*\n/gm, ''));
  assert.deepEqual(config.prompts, [{ id: 'prompt-v2', label: 'prompt-v2', raw: '{{label_id}}' }]);
  assert.deepEqual(config.providers.map((p) => p.config), [
    { route: 'gemini-4-argon-vertex-us', cell: 'v2__gemini-4-argon-vertex-us__adversarial', promptVersion: 'prompt-v2' },
    { route: 'mistral-large-4-zdr', cell: 'v2__mistral-large-4-zdr__adversarial', promptVersion: 'prompt-v2' },
  ]);
  assert.match(text, /prompt v2 \(prompt-v2\)/);
});

check('a fresh run names its cells by suite and run, and passes the run to each provider', () => {
  if (fs.existsSync(out)) fs.unlinkSync(out);
  const r = run(args({ '--prompt-version': 'v2', '--suite': 'tuning', '--fresh-run': 'r2' }));
  assert.equal(r.code, 0, r.stderr);
  const text = fs.readFileSync(out, 'utf8');
  const config = JSON.parse(text.replace(/^#.*\n/gm, ''));
  assert.deepEqual(config.providers.map((p) => p.config), [
    { route: 'gemini-4-argon-vertex-us', cell: 'v2__gemini-4-argon-vertex-us__tuning-r2', promptVersion: 'prompt-v2', freshRun: 'r2' },
    { route: 'mistral-large-4-zdr', cell: 'v2__mistral-large-4-zdr__tuning-r2', promptVersion: 'prompt-v2', freshRun: 'r2' },
  ]);
  assert.match(text, /Fresh run r2/);
  assert.match(config.description, /fresh run r2$/);
});
check('without --fresh-run no provider names a fresh run', () => {
  if (fs.existsSync(out)) fs.unlinkSync(out);
  const r = run(args({ '--prompt-version': 'v2', '--suite': 'tuning' }));
  assert.equal(r.code, 0, r.stderr);
  const config = JSON.parse(fs.readFileSync(out, 'utf8').replace(/^#.*\n/gm, ''));
  for (const p of config.providers) assert.equal('freshRun' in p.config, false);
  assert.deepEqual(config.providers.map((p) => p.config.cell), ['v2__gemini-4-argon-vertex-us__tuning', 'v2__mistral-large-4-zdr__tuning']);
});
check('a fresh run outside the grammar is refused, and nothing is written', () => {
  for (const bad of ['R2', '2r', 'r_2', 'r__2', 'r2-', 'r--2', 'r.2', 'r2/x', 'r12345678901234567']) {
    if (fs.existsSync(out)) fs.unlinkSync(out);
    const r = run(args({ '--fresh-run': bad }));
    assert.equal(r.code, 2, bad);
    assert.match(r.stderr, /bad fresh run/, bad);
    assert.equal(fs.existsSync(out), false, bad);
  }
  assert.equal(run([...args(), '--fresh-run', 'r2', '--fresh-run', 'r3']).code, 2);
});

// A tuning data directory whose files are symbolic links: one into a temporary directory named
// `uk-english-v2` (created here, never the sealed set) and one to a file outside the directory.
function linkedData(name, link) {
  const data = path.join(tmp, name);
  fs.mkdirSync(path.join(data, 'texts'), { recursive: true });
  fs.mkdirSync(path.join(data, 'cases'), { recursive: true });
  fs.writeFileSync(path.join(data, 'cases', 'x-01.json'), '{}');
  fs.writeFileSync(path.join(data, 'texts', 'x-01.txt'), 'Fat 5g\n');
  fs.writeFileSync(path.join(data, 'cases', 'x-02.json'), '{}');
  link(data);
  return data;
}
fs.writeFileSync(path.join(sealed, 'texts', 'held-01.txt'), 'synthetic stand-in\n');
fs.writeFileSync(path.join(sealed, 'cases', 'held-01.json'), '{}');
const outside = path.join(tmp, 'outside');
fs.mkdirSync(outside, { recursive: true });
fs.writeFileSync(path.join(outside, 'other.txt'), 'Fat 5g\n');
fs.writeFileSync(path.join(outside, 'other.json'), '{}');

check('a text file linked into the sealed set is refused, and nothing is written', () => {
  const data = linkedData('linked-text-sealed', (d) => fs.symlinkSync(path.join(sealed, 'texts', 'held-01.txt'), path.join(d, 'texts', 'x-02.txt')));
  if (fs.existsSync(out)) fs.unlinkSync(out);
  const r = run(args({ '--data': data }));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /sealed held-out set/);
  assert.equal(fs.existsSync(out), false);
});
check('a case file linked into the sealed set is refused, and nothing is written', () => {
  const data = linkedData('linked-case-sealed', (d) => {
    fs.unlinkSync(path.join(d, 'cases', 'x-02.json'));
    fs.symlinkSync(path.join(sealed, 'cases', 'held-01.json'), path.join(d, 'cases', 'x-02.json'));
    fs.writeFileSync(path.join(d, 'texts', 'x-02.txt'), 'Fat 5g\n');
  });
  if (fs.existsSync(out)) fs.unlinkSync(out);
  const r = run(args({ '--data': data }));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /sealed held-out set/);
  assert.equal(fs.existsSync(out), false);
});
check('a text or case file linked outside the data directory is refused, and nothing is written', () => {
  const text = linkedData('linked-text-outside', (d) => fs.symlinkSync(path.join(outside, 'other.txt'), path.join(d, 'texts', 'x-02.txt')));
  const kase = linkedData('linked-case-outside', (d) => {
    fs.unlinkSync(path.join(d, 'cases', 'x-02.json'));
    fs.symlinkSync(path.join(outside, 'other.json'), path.join(d, 'cases', 'x-02.json'));
    fs.writeFileSync(path.join(d, 'texts', 'x-02.txt'), 'Fat 5g\n');
  });
  for (const data of [text, kase]) {
    if (fs.existsSync(out)) fs.unlinkSync(out);
    const r = run(args({ '--data': data }));
    assert.equal(r.code, 2, data);
    assert.match(r.stderr, /resolves outside the data directory/, data);
    assert.equal(fs.existsSync(out), false, data);
  }
});
check('a link that stays inside the data directory is accepted', () => {
  const data = linkedData('linked-inside', (d) => fs.symlinkSync(path.join(d, 'texts', 'x-01.txt'), path.join(d, 'texts', 'x-02.txt')));
  if (fs.existsSync(out)) fs.unlinkSync(out);
  const r = run(args({ '--data': data }));
  assert.equal(r.code, 0, r.stderr);
});
check('an output path that is a symbolic link is refused and its target is untouched', () => {
  // A temporary file stands in for a repository file; the real repository is never a link target.
  const standIn = path.join(tmp, 'stand-in-repository-file.swift');
  fs.writeFileSync(standIn, 'unchanged\n');
  const link = path.join(tmp, 'linked-config.yaml');
  fs.symlinkSync(standIn, link);
  const r = run(args({ '--out': link }));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /may not be a symbolic link/);
  assert.equal(fs.readFileSync(standIn, 'utf8'), 'unchanged\n');
  // A dangling link is refused too, and nothing is created at its target.
  const dangling = path.join(tmp, 'dangling-config.yaml');
  fs.symlinkSync(path.join(tmp, 'never-created.yaml'), dangling);
  assert.equal(run(args({ '--out': dangling })).code, 2);
  assert.equal(fs.existsSync(path.join(tmp, 'never-created.yaml')), false);
});
check('an output whose directory links into the repository is refused', () => {
  const linkedDir = path.join(tmp, 'repo-link');
  fs.symlinkSync(__dirname, linkedDir);
  const r = run(args({ '--out': path.join(linkedDir, 'generated.yaml') }));
  assert.equal(r.code, 2);
  assert.match(r.stderr, /outside the repository/);
  assert.equal(fs.existsSync(path.join(__dirname, 'generated.yaml')), false);
});

fs.rmSync(tmp, { recursive: true, force: true });
if (failures) {
  console.log(`${failures} failed`);
  process.exit(1);
}
console.log('all passed');
