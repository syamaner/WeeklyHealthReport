#!/usr/bin/env python3
"""One-command offline composition of trusted private runners and public preflight."""
import argparse
import hashlib
import html
import json
import os
import re
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
from current_report import compose, attach_fixed_source, attach_journeys, attach_linked, attach_lists, attach_multi_source
from fixed_source import run_private as run_fixed_source
from journey import run as run_journeys
from linked import run as run_linked
from list_journey import run as run_lists
from multi_source import run as run_multi_source

FILES = ['run-private.sh', 'run_private.py', 'nlp-runner.swift', 'score_private.py', 'render_private.py',
         'run-retrieval.sh', 'run_retrieval.py', 'retrieval-runner.swift', 'score_retrieval.py',
         'nlp-labels-v2.json', 'retrieval-labels-v1.json', 'retrieval-labels-v1.sha256']


def outside_git(path):
    return not any((p / '.git').exists() for p in [path, *path.parents])


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pin_bundle(bundle):
    manifest = json.loads((bundle / 'ranking-verification-v5.json').read_text())
    pins = {r['name']: r['sha256'] for r in manifest['artifacts']}
    for name in FILES:
        if not (bundle / name).is_file() or sha(bundle / name) != pins.get(name):
            raise ValueError('runner_bundle_hash_mismatch')
    return pins


def bind_runner_workspace(work, repo):
    """Rebind verified legacy runner copies; never edit originals or reference labels."""
    original = "Path('/Users/sertanyamaner/git/WeeklyHealthReport')"
    changed = {}
    for name in ['run_private.py', 'run_retrieval.py']:
        path = work / name
        content = path.read_text()
        if content.count(original) != 1:
            raise ValueError('runner_workspace_binding_contract')
        content = content.replace(original, 'Path(' + repr(str(repo)) + ')')
        if name == 'run_private.py' and (repo / 'Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryDiscoveryPolicy.swift').exists():
            anchor = "+[parser,ROOT/'nlp-runner.swift']"
            if content.count(anchor) != 1:
                raise ValueError('runner_parser_dependency_contract')
            content = content.replace(anchor, "+[parser,parser.with_name('FoodQueryDiscoveryPolicy.swift'),ROOT/'nlp-runner.swift']")
        path.write_text(content)
        changed[name] = sha(path)
    return {'repository': str(repo), 'effective_runner_sha256': changed,
            'changes': 'workspace path and required parser policy dependency only; original bundle and labels unchanged'}


def source_integrity(root):
    profile = json.loads((root / 'current-profile-config-v1.json').read_text())
    if profile.get('schema') != 'private-current-evaluation-profile-v1':
        raise ValueError('private_profile_schema')
    folder = (root / profile['source_capture_directory']).resolve()
    if not folder.is_relative_to(root.resolve()) or not outside_git(folder):
        raise ValueError('source_capture_boundary')
    manifest = folder / 'source-capture-manifest.json'
    if sha(manifest) != profile['capture_manifest_sha256']:
        raise ValueError('source_manifest_hash_mismatch')
    capture = json.loads(manifest.read_text())
    expected = profile['expected_source_ids']
    retained = profile['required_retained_source_ids']
    if not isinstance(expected, list) or not isinstance(retained, list) or len(expected) != len(set(expected)) or not set(retained) <= set(expected):
        raise ValueError('source_profile_roster')
    rows, errors = [], []
    for r in capture['sources']:
        if r['status'] == 'retained':
            # Closed retained-artifact roster, never a source-supplied command/path.
            if r['id'] not in retained or re.fullmatch(r'[a-z0-9-]+', r['id']) is None or sha(folder / (r['id'] + '.html')) != r['sha256']:
                errors.append('source_bytes_changed')
        rows.append({'id': r['id'], 'status': r['status']})
    if {r['id'] for r in rows if r['status'] == 'retained'} != set(retained):
        errors.append('retained_source_missing')
    if len(rows) != len(expected) or {r['id'] for r in rows} != set(expected):
        errors.append('source_roster_mismatch')
    return {'status': 'invalid' if errors else 'retained_bytes_verified', 'retained_pages': sum(r['status'] == 'retained' for r in rows),
            'attempted_pages': len(rows), 'pages': rows, 'errors': errors, 'source_nutrient_fidelity': 'not_run'}


def execute(args, cwd, logfile, clock=time.monotonic):
    start = clock()
    # Do not inherit provider credentials. The outer OS sandbox denies networking
    # and /usr/bin/security for compiler and every child process.
    env = {k: v for k, v in os.environ.items() if k in ['PATH', 'HOME', 'TMPDIR', 'LANG', 'LC_ALL', 'DEVELOPER_DIR']}
    with logfile.open('w') as stream:
        proc = subprocess.run([str(x) for x in args], cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=900)
    return {'exit_code': proc.returncode, 'elapsed_seconds': round(clock() - start, 3)}


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    root, output = args.private_root.resolve(), args.output.resolve()
    if not outside_git(root) or not outside_git(output):
        parser.error('Private input and output must remain outside Git.')
    if output.exists():
        parser.error('Choose a fresh snapshot directory.')
    with socket.socket() as probe:
        try:
            probe.connect(('127.0.0.1', 9))
        except PermissionError:
            pass
        except OSError:
            parser.error('Network denial not proven; use run-current.sh.')
        else:
            parser.error('Unexpected network availability.')
    output.mkdir(parents=True, mode=0o700)
    bundle = root / 'ranking-v5-final-development-rerun'
    outcomes = {}
    try:
        pins = pin_bundle(bundle)
        work = output / 'components';work.mkdir(mode=0o700)
        for name in FILES:
            shutil.copyfile(bundle / name, work / name)
        # Renderer expects its parent NLP baseline. Retain it privately.
        shutil.copyfile(root / 'nlp-report-v2.json', output / 'nlp-report-v2.json')
        repo = Path(__file__).resolve().parents[2]
        binding = bind_runner_workspace(work, repo)
        before = {'runner_binding': binding, 'labels': {n: sha(work / n) for n in ['nlp-labels-v2.json', 'retrieval-labels-v1.json']},
                  'bundle': {n: pins[n] for n in FILES}, 'private_profile_sha256': sha(root / 'current-profile-config-v1.json'), 'public_harness': {n: sha(Path(__file__).with_name(n)) for n in ['run_current.py', 'current_report.py', 'run-current.sh', 'fixed_source.py', 'journey.py', 'journey.swift', 'journey-reference-v3.json', 'journey-freeze-v3.json', 'linked.py', 'linked.swift', 'linked-input-v1.json', 'linked-reference-v3.json', 'linked-freeze-v3.json', 'list_journey.py', 'list_journey.swift', 'list-input-v1.json', 'list-reference-v3.json', 'list-freeze-v3.json', 'multi_source.py', 'multi_source.swift', 'freeze_multi_source.py', 'multi-input-v3.json', 'multi-reference-v3.json', 'multi-freeze-v3.json']}}
        repo = Path(__file__).resolve().parents[2]
        outcomes['nlp'] = execute(['/bin/sh', work / 'run-private.sh'], work, output / 'nlp.log')
        outcomes['retrieval'] = execute(['/bin/sh', work / 'run-retrieval.sh'], work, output / 'retrieval.log')
        outcomes['readiness'] = execute([sys.executable, repo / 'Tools/NutritionAcceptanceReadiness/run.py',
            '--collection', root / 'acceptance-collection-template-v1.json', '--freeze', root / 'acceptance-freeze-preparation-v1.json',
            '--output', output / 'acceptance-readiness'], repo, output / 'readiness.log')
        for n, h in before['runner_binding']['effective_runner_sha256'].items():
            if sha(work / n) != h:
                raise ValueError('effective_runner_changed')
        for n, h in before['labels'].items():
            if sha(work / n) != h:
                raise ValueError('labels_changed_during_execution')
        nlp = json.loads((work / 'nlp-report-v2.json').read_text()) if outcomes['nlp']['exit_code'] == 0 else None
        retrieval = json.loads((work / 'retrieval-report-v1.json').read_text()) if outcomes['retrieval']['exit_code'] == 0 else None
        readiness = json.loads((output / 'acceptance-readiness/readiness.json').read_text())
        completed = outcomes['nlp']['exit_code'] == outcomes['retrieval']['exit_code'] == 0 and outcomes['readiness']['exit_code'] in [0, 1, 2]
        report = compose(nlp, retrieval, source_integrity(root), readiness, {'all_required_commands_completed': completed, 'expected_retrieval_ids': [r['id'] for r in json.loads((work / 'retrieval-labels-v1.json').read_text())['records']]})
        report['execution'] = outcomes
        if (root / 'fixed-source-config-v1.json').exists():
            report = attach_fixed_source(report, run_fixed_source(root, output))
        report = attach_journeys(report, run_journeys(output, execute))
        report = attach_linked(report, run_linked(output, execute))
        report = attach_lists(report, run_lists(output, execute))
        report = attach_multi_source(report, run_multi_source(output, execute))
        if sha(root / 'current-profile-config-v1.json') != before['private_profile_sha256']:
            raise ValueError('private_profile_changed_during_execution')
        harness = output / 'harness-source';harness.mkdir(mode=0o700)
        for name, digest in before['public_harness'].items():
            source = Path(__file__).with_name(name)
            if sha(source) != digest:
                raise ValueError('public_harness_changed_during_execution')
            shutil.copyfile(source, harness / name)
        before['outputs'] = {str(f.relative_to(output)): sha(f) for f in output.rglob('*.json')}
        (output / 'run-manifest.json').write_text(json.dumps(before, indent=2) + '\n')
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        report = {'schema': 'current-nutrition-report-v8', 'decision': 'incomplete', 'integrity': 'invalid',
                  'errors': [type(error).__name__], 'acceptance': 'not_run', 'execution': outcomes, 'scorecards': {}}
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['# Current offline nutrition evaluation', '', 'Overall: ' + report['decision'] + '. Acceptance: not run.',
             'Profile integrity: ' + report['integrity'] + '.', '',
             '## Scorecards', '']
    for key, card in report['scorecards'].items():
        lines += ['### ' + key.replace('_', ' '), '', 'Status: ' + card['status'], '']
        for metric, m in card.get('metrics', {}).items():
            lines.append('- ' + metric + ': ' + str(m['correct']) + '/' + str(m['total']))
        lines.append('')
    lines += ['## Evidence gaps', ''] + ['- ' + key for key in report.get('missing_profiles', [])]
    lines += ['', '## Readiness and sources', '',
              'Acceptance preflight: ' + report.get('acceptance_readiness', {}).get('status', 'unavailable') + '.',
              'The earlier acceptance preparation pins can be stale after code repairs. This does not invalidate current component observations; prospective acceptance is still uncollected and unrun.',
              'Retained source bytes are checked. The fixed-source scorecard, when configured, scores one frozen page with an evaluation-only adapter; broad source/provider fidelity remains incomplete. No page fetch occurs.', '',
              'No provider inference, source acquisition, personal-ledger write or device action occurred. Synthetic journeys write only an isolated in-memory store.', '',
              'Details: report.json; components/NLP-REPORT.md; components/RETRIEVAL-REPORT.md; acceptance-readiness/READINESS.md.', '']
    text = '\n'.join(lines)
    (output / 'REPORT.md').write_text(text)
    (output / 'report.html').write_text('<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src &#39;none&#39;; style-src &#39;unsafe-inline&#39;"><title>Current nutrition evaluation</title><style>body{max-width:1100px;margin:40px auto;font:16px system-ui}pre{white-space:pre-wrap}</style><pre>' + html.escape(text) + '</pre>')
    for f in output.rglob('*'):
        if f.is_dir():f.chmod(0o700)
        elif f.is_file():f.chmod(0o700 if f.name in ['nlp-runner', 'retrieval-runner', 'journey-runner', 'linked-runner','list-runner','multi-runner'] else 0o600)
    print(json.dumps({'decision': report['decision'], 'integrity': report['integrity'], 'acceptance': 'not_run'}))
    return 1 if report['integrity'] == 'invalid' or report['decision'].startswith('fail') else 2


if __name__ == '__main__':
    raise SystemExit(main())
