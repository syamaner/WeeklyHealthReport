"""Keyless prospective capture audit of the first native lead for every query."""
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import urlsplit

from frozen_run import digest, write, REPO


def capture_output_hashes(folder):
    names = re.compile(r'(?:document\.json|capture-receipt\.json|source-body-[0-9]+\.bin)')
    return {p.name: digest(p) for p in sorted(folder.iterdir()) if p.is_file() and names.fullmatch(p.name)}


def verify_capture_outputs(root, plan, audit):
    if not plan.get('output_hashes_required', False):
        return 'not_recorded_legacy_capture'
    rows = {row['id']: row for row in audit['cases']}
    if len(rows) != len(audit['cases']) or set(rows) != {case['id'] for case in plan['cases']}:
        raise ValueError('capture output denominator changed')
    for case in plan['cases']:
        folder = root / 'results' / case['id']
        status_path = folder / 'status.json'
        row = rows[case['id']]
        if not status_path.exists():
            if row['status'] != 'not_run':
                raise ValueError('capture has no completion receipt')
            continue
        status = json.loads(status_path.read_text())
        if status.get('output_hashes') != capture_output_hashes(folder):
            raise ValueError('capture outputs changed after completion receipt')
        if any(row.get(key) != status.get(key) for key in ['status', 'closed_error', 'completed_at', 'output_hashes']):
            raise ValueError('capture report differs from completion receipt')
        receipt = folder / 'capture-receipt.json'
        responses = json.loads(receipt.read_text())['responses'] if receipt.exists() else []
        if row.get('responses') != responses:
            raise ValueError('capture report changed response evidence')
        if status['status'] == 'captured' and not {'document.json', 'capture-receipt.json'} <= set(status['output_hashes']):
            raise ValueError('captured source lacks its document or receipt')
    return 'verified_against_capture_completion_receipt'


def validate_capture_cases(cases):
    if not isinstance(cases, list) or not 1 <= len(cases) <= 40:
        raise ValueError('invalid capture denominator')
    identifiers = []
    for case in cases:
        identifier = case.get('id')
        if not isinstance(identifier, str) or not re.fullmatch(r'[a-z0-9-]+', identifier):
            raise ValueError('unsafe capture identifier')
        identifiers.append(identifier)
        if not isinstance(case.get('query'), str) or not 1 <= len(case['query']) <= 300:
            raise ValueError('invalid capture query')
        url = case.get('url')
        if url is not None:
            if not isinstance(url, str):
                raise ValueError('invalid capture URL')
            parsed = urlsplit(url)
            if parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None or parsed.password is not None or parsed.port not in (None, 443):
                raise ValueError('unsafe capture URL')
    if len(set(identifiers)) != len(identifiers):
        raise ValueError('duplicate capture identifier')


def freeze(discovery, executable, destination, references=False):
    source, executable, root = [Path(p).resolve() for p in (discovery, executable, destination)]
    if root.exists():
        raise ValueError('audit exists')
    plan = json.loads((source if references else source / 'plan.json').read_text())
    if not executable.is_file():
        raise ValueError('capture executable missing')
    bundle = executable.parent / 'FoodLedgerKit_FoodGenericSearch.bundle'
    if not bundle.is_dir():
        raise ValueError('capture resource bundle missing')
    cases = []
    discovery_files = []
    for case in plan['cases']:
        if references:
            cases.append(dict(id=case['id'], query=case['query'], slice=case['identity']['country'],
                              url=case['source_url'], reference_status=plan['reference_status']))
            continue
        # Validate the identifier before using it as a source path.
        validate_capture_cases([dict(id=case['id'], query=case['query'], url=None)])
        found = source / 'results' / case['id'] / 'discovery.json'
        leads = json.loads(found.read_text())['leads'] if found.exists() else []
        if found.exists():
            discovery_files.append((case['id'], found))
        cases.append(dict(id=case['id'], query=case['query'], slice=case['slice'],
                          url=leads[0]['url'] if leads else None, native_lead_count=len(leads)))
    validate_capture_cases(cases)
    (root / 'snapshot/runtime').mkdir(parents=True)
    shutil.copy2(executable, root / 'snapshot/runtime/FoodProposalProbe')
    shutil.copytree(bundle, root / 'snapshot/runtime' / bundle.name)
    files = list((REPO / 'Packages/FoodLedgerKit/Sources').rglob('*.swift'))
    files += list((REPO / 'Packages/FoodLedgerKit/Tools').rglob('*.swift'))
    files += [Path(__file__), Path(__file__).parent / 'frozen_run.py']
    for file in files:
        target = root / 'snapshot/source' / file.relative_to(REPO)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file, target)
    if references:
        shutil.copy2(source, root / 'snapshot/source-references.json')
    for identifier, found in discovery_files:
        target = root / 'snapshot/discovery' / (identifier + '.json')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(found, target)
    frozen = dict(version='keyless-source-capture-audit-v2', frozen_at=datetime.now(timezone.utc).isoformat(),
                  output_hashes_required=True,
                  policy=('Prospective reference URLs' if references else 'First native lead only') +
                         ', at most three HTTPS connections including redirects; no retries or provider calls.',
                  cases=cases, executable='snapshot/runtime/FoodProposalProbe',
                  snapshot_hashes={str(p.relative_to(root)): digest(p) for p in sorted((root / 'snapshot').rglob('*')) if p.is_file()})
    write(root / 'plan.json', frozen)
    (root / 'plan.sha256').write_text(digest(root / 'plan.json') + '\n')
    print(f'Frozen first-lead capture audit for {len(cases)} queries.')


def run(directory):
    root = Path(directory).resolve()
    plan = json.loads((root / 'plan.json').read_text())
    validate_capture_cases(plan['cases'])
    if digest(root / 'plan.json') != (root / 'plan.sha256').read_text().strip():
        raise ValueError('changed plan')
    for name, expected in plan['snapshot_hashes'].items():
        target = (root / name).resolve()
        if not target.is_relative_to(root / 'snapshot') or digest(target) != expected:
            raise ValueError('changed snapshot')
    if digest(Path(__file__)) != plan['snapshot_hashes']['snapshot/source/Tools/GenericFoodProposalEvaluation/capture_discovery.py']:
        raise ValueError('use frozen runner')
    results = root / 'results'; results.mkdir(exist_ok=True)
    for case in plan['cases']:
        destination = results / case['id']
        if destination.exists():
            continue
        if case['url'] is None:
            destination.mkdir()
            status, code = 'no_native_lead', None
        else:
            try:
                child = subprocess.run([str(root / plan['executable']), 'capture-audit', case['url'], str(destination)],
                                       check=False, capture_output=True, text=True, timeout=100)
                status = 'captured' if child.returncode == 0 else 'failed'
                output = child.stdout.strip()
                code = output if output.startswith(('capture_', 'proposal_')) and len(output) < 100 and '\n' not in output else None
            except subprocess.TimeoutExpired:
                status, code = 'timed_out', None
        destination.mkdir(exist_ok=True)
        write(destination / 'status.json', dict(status=status, closed_error=code, completed_at=datetime.now(timezone.utc).isoformat(),
                                                output_hashes=capture_output_hashes(destination)))
        print(case['id'] + ': ' + status + (' ' + code if code else ''), flush=True)
    rows = []
    for case in plan['cases']:
        folder = results / case['id']
        status = json.loads((folder / 'status.json').read_text()) if (folder / 'status.json').exists() else dict(status='not_run')
        receipt = json.loads((folder / 'capture-receipt.json').read_text()) if (folder / 'capture-receipt.json').exists() else dict(responses=[])
        rows.append(dict(**case, **status, responses=receipt['responses']))
    audit = dict(cases=rows, captured=sum(r['status'] == 'captured' for r in rows), denominator=len(rows), provider_calls=0,
                 qualification='Acquisition only; page relevance, identity and nutrition still require review.')
    audit['output_integrity'] = verify_capture_outputs(root, plan, audit)
    write(root / 'report.json', audit)


if __name__ == '__main__':
    if sys.argv[1] == 'freeze':
        freeze(*sys.argv[2:])
    elif sys.argv[1] == 'freeze-references':
        freeze(*sys.argv[2:], references=True)
    elif sys.argv[1] == 'run':
        run(sys.argv[2])
    else:
        raise SystemExit('Unknown command')
