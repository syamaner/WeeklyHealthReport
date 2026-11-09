#!/usr/bin/env node
// Writes the promptfoo config of one A3 matrix suite (docs/pasted-label-ai-text-v1.md 5.2, #416 A3b):
// one provider per route candidate and one test per case in DATA/cases. The config names no data
// path: run-live.sh and run-adversarial-fake.sh pass the data directory to provider.js and assert.js
// by environment, so the same config runs over any copy of the suite.
//
// Usage: node make-config.js --data DIR --candidates ID[,ID...] --prompt-version V --suite NAME [--fresh-run RUN] --out FILE
//
// - DATA holds texts/ and cases/. A path holding `uk-english-v2` (the sealed held-out set, T7) is
//   refused, before and after resolving symbolic links, and nothing in it is opened. Each text and
//   case file is checked the same way and must resolve inside the resolved data directory, so a
//   symbolic link inside an approved directory never reaches the sealed set or any other file.
// - Each provider's cell is `<prompt-version>__<candidate-id>__<suite>`, the key of its $5 stop in
//   the spend ledger. The candidate IDs are checked by `send` against the closed route set.
// - The prompt version is one the shipped request builder can send (revision 11): `v1` (`prompt-v1`,
//   the app's) or `v2` (`prompt-v2`). provider.js passes it to `send --prompt-version`, and refuses a
//   send record whose prompt version is not the cell's.
// - `--fresh-run RUN` (revision 16) writes a fresh repeat of the suite for a noise measurement: the
//   cells are `<prompt-version>__<candidate-id>__<suite>-<RUN>`, each with its own $5 stop, and
//   provider.js passes RUN to `send --fresh-run`, which sends the same request bodies again under
//   their own cache entries. RUN is a lower-case letter, then up to 15 lower-case letters, digits or
//   single hyphens (`r2`, `r3`).
// - FILE must be outside the repository, after resolving its directory, and may not be a symbolic
//   link; this script writes nothing else.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
// validate-config.js holds the names and the whole shape this script writes; run-live.sh refuses
// any config that is not exactly that shape.
const { PROMPT_VERSIONS, NAME, FRESH_RUN, ConfigRefusal, validateConfigText } = require('./validate-config.js');

const OPTIONS = ['--data', '--candidates', '--prompt-version', '--suite', '--fresh-run', '--out'];
const REQUIRED = ['--data', '--candidates', '--prompt-version', '--suite', '--out'];

function fail(message) {
  process.stderr.write(`make-config: ${message}\n`);
  process.exit(2);
}

function parse(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    const name = argv[i];
    const value = argv[i + 1];
    if (!OPTIONS.includes(name)) fail(`unknown option ${name}`);
    if (value === undefined || value.startsWith('--')) fail(`${name} needs a value`);
    if (out[name] !== undefined) fail(`${name} given twice`);
    out[name] = value;
  }
  for (const name of REQUIRED) if (out[name] === undefined) fail(`${name} is required`);
  return out;
}

const SEALED = 'uk-english-v2';
const SEALED_REFUSAL = 'the sealed held-out set (uk-english-v2) is never used by a tuning run (T7)';

// One text or case file, checked before anything is written: the path as given is refused first if
// it names the sealed set, so a refused path is never resolved; then its symbolic links are
// resolved, and the file is refused if the resolved path names the sealed set or lies outside the
// resolved data directory (a link inside an approved directory never reaches another set).
function dataFile(file, data, name) {
  if (file.includes(SEALED)) fail(SEALED_REFUSAL);
  let resolved;
  try {
    resolved = fs.realpathSync(file);
  } catch (e) {
    fail(`${name} is missing`);
  }
  if (resolved.includes(SEALED)) fail(SEALED_REFUSAL);
  if (!resolved.startsWith(data + path.sep)) fail(`${name} resolves outside the data directory (${data})`);
  if (!fs.statSync(resolved).isFile()) fail(`${name} is not a file`);
}

function main() {
  const options = parse(process.argv.slice(2));
  const here = __dirname;
  // The held-out refusal comes first, on the path as given, so a refused path is never resolved or read.
  if (options['--data'].includes(SEALED)) fail(SEALED_REFUSAL);
  let data;
  try {
    data = fs.realpathSync(options['--data']);
  } catch (e) {
    fail('the data directory must exist');
  }
  if (data.includes(SEALED)) fail(SEALED_REFUSAL);
  for (const sub of ['texts', 'cases']) {
    if (!fs.statSync(path.join(data, sub), { throwIfNoEntry: false })?.isDirectory()) fail(`the data directory must hold ${sub}/`);
  }
  const candidates = options['--candidates'].split(',').map((id) => id.trim()).filter(Boolean);
  if (candidates.length === 0) fail('--candidates needs at least one route candidate ID');
  if (new Set(candidates).size !== candidates.length) fail('a route candidate is named twice');
  for (const id of candidates) if (!NAME.test(id)) fail(`bad route candidate ID ${id}`);
  const version = options['--prompt-version'];
  if (!PROMPT_VERSIONS[version]) {
    fail(`prompt version ${version} cannot be sent: the shipped request builder sends only ${Object.keys(PROMPT_VERSIONS).join(', ')}`);
  }
  const freshRun = options['--fresh-run'];
  if (freshRun !== undefined && !FRESH_RUN.test(freshRun)) fail(`bad fresh run ${freshRun}: a lower-case letter, then up to 15 lower-case letters, digits or single hyphens`);
  const baseSuite = options['--suite'];
  if (!NAME.test(baseSuite) || baseSuite.includes('__')) fail(`bad suite name ${baseSuite}`);
  // A fresh run's cells carry its name, so its $5 stops are its own and its records are told apart.
  const suite = freshRun === undefined ? baseSuite : `${baseSuite}-${freshRun}`;

  const repo = fs.realpathSync(execFileSync('git', ['-C', here, 'rev-parse', '--show-toplevel']).toString().trim());
  const outPath = path.resolve(options['--out']);
  // An existing output that is a symbolic link is refused, so the write can never follow it (into
  // the repository or anywhere else); the target checked and written is the resolved directory
  // plus the file name, and it is opened with O_NOFOLLOW.
  if (fs.lstatSync(outPath, { throwIfNoEntry: false })?.isSymbolicLink()) fail('the output file may not be a symbolic link');
  let outDir;
  try {
    outDir = fs.realpathSync(path.dirname(outPath));
  } catch (e) {
    fail("the output file's directory must exist");
  }
  const outTarget = path.join(outDir, path.basename(outPath));
  if ((outTarget + path.sep).startsWith(repo + path.sep)) fail(`the config must be written outside the repository (${repo})`);

  const labels = fs.readdirSync(path.join(data, 'cases')).filter((name) => name.endsWith('.json')).map((name) => name.slice(0, -5)).sort();
  if (labels.length === 0) fail('cases/ holds no case');
  for (const label of labels) {
    if (!NAME.test(label)) fail(`bad case file name ${label}.json`);
    dataFile(path.join(data, 'cases', `${label}.json`), data, `cases/${label}.json`);
    dataFile(path.join(data, 'texts', `${label}.txt`), data, `texts/${label}.txt`);
  }

  const promptVersion = PROMPT_VERSIONS[version];
  const config = {
    description: `pasted-label-ai-text A3 ${suite}: ${version} x ${candidates.length} route candidates x ${labels.length} cases${freshRun === undefined ? '' : `, fresh run ${freshRun}`}`,
    sharing: false,
    prompts: [{ id: promptVersion, label: promptVersion, raw: '{{label_id}}' }],
    providers: candidates.map((id) => ({
      id: `file://${path.join(here, 'provider.js')}`,
      label: id,
      config: { route: id, cell: `${version}__${id}__${suite}`, promptVersion, ...(freshRun === undefined ? {} : { freshRun }) },
    })),
    defaultTest: { assert: [{ type: 'javascript', value: `file://${path.join(here, 'assert.js')}` }] },
    tests: labels.map((label) => ({ vars: { label_id: label } })),
  };
  const header = [
    `# Generated by make-config.js (#416 A3b); do not edit by hand.`,
    `# suite ${suite}, prompt ${version} (${promptVersion}), ${candidates.length} candidates, ${labels.length} cases.`,
    ...(freshRun === undefined ? [] : [`# Fresh run ${freshRun}: the same request bodies sent again under their own cache entries (revision 16).`]),
    `# Cells: ${candidates.map((id) => `${version}__${id}__${suite}`).join(', ')}`,
    '',
  ].join('\n');
  // JSON is YAML: promptfoo reads the file as YAML, and the comments above stay readable.
  const text = header + JSON.stringify(config, null, 2) + '\n';
  // The same check run-live.sh makes, so this script never writes a config run-live.sh refuses.
  try {
    validateConfigText(text, here);
  } catch (e) {
    if (e instanceof ConfigRefusal) fail(`the generated config fails its own check: ${e.message}`);
    throw e;
  }
  let descriptor;
  try {
    descriptor = fs.openSync(outTarget, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_TRUNC | fs.constants.O_NOFOLLOW, 0o644);
  } catch (e) {
    fail(`the config could not be written: ${e.code || e.message}`);
  }
  fs.writeFileSync(descriptor, text);
  fs.closeSync(descriptor);
  process.stdout.write(`${outPath}: ${candidates.length} providers x ${labels.length} tests\n`);
}

main();
