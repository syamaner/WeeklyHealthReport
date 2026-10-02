#!/usr/bin/env python3
"""Local filesystem adapter; report directories must remain outside Git."""
import argparse
import hashlib
import json
import os
from pathlib import Path
from readiness import assess


def outside_git(path):
    return not any((parent / '.git').exists() for parent in [path, *path.parents])


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_pins(freeze, collection_path):
    result = {'verified_categories': [], 'errors': [],
              'collection_hash_matches': sha(collection_path) == freeze.get('collection_sha256')}
    pins = freeze.get('pins', [])
    if not isinstance(pins, list):
        result['errors'].append('invalid_pins'); return result
    seen = set()
    for pin in pins:
        if not isinstance(pin, dict) or not isinstance(pin.get('path'), str):
            result['errors'].append('invalid_pin'); continue
        path = Path(pin['path'])
        if not path.is_absolute() or pin['path'] in seen:
            result['errors'].append('invalid_or_duplicate_pin'); continue
        seen.add(pin['path'])
        try:
            matches = path.is_file() and sha(path) == pin.get('sha256')
        except OSError:
            matches = False
        if not matches:
            result['errors'].append('pin_hash_mismatch')
        elif pin.get('category') in {'implementation', 'catalogue', 'metric_contract', 'readiness_policy'}:
            result['verified_categories'].append(pin['category'])
    result['verified_categories'] = sorted(set(result['verified_categories']))
    return result


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--collection', type=Path, required=True)
    parser.add_argument('--freeze', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    # Resolve symlinks before enforcing the local data boundary.
    collection, freeze_path, output = (p.resolve() for p in (args.collection, args.freeze, args.output))
    if not all(outside_git(p) for p in (collection, freeze_path, output)):
        parser.error('Collection, freeze and output must remain outside Git.')
    if output.exists():
        parser.error('Choose a new output directory; earlier snapshots are never overwritten.')
    output.mkdir(parents=True, mode=0o700)
    try:
        data, freeze = (json.loads(p.read_text()) for p in (collection, freeze_path))
        integrity = verify_pins(freeze, collection) if isinstance(freeze, dict) else {}
        report = assess(data, freeze, integrity)
    except (OSError, ValueError, TypeError) as error:
        report = {'status': 'invalid', 'acceptance': 'not_run', 'metrics': None,
                  'errors': ['input_read_or_schema_error'], 'blockers': [],
                  'error_type': type(error).__name__}
    report['input_hashes'] = {'collection': sha(collection) if collection.is_file() else None, 'freeze': sha(freeze_path) if freeze_path.is_file() else None,
                            'cli': sha(Path(__file__).resolve()),
                            'policy': sha(Path(__file__).with_name('readiness.py'))}
    (output / 'readiness.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['# Nutrition acceptance preflight', '', 'Status: ' + report['status'],
             'Acceptance: not run. No quality scores produced.', '',
             'Collected cases: ' + str(report.get('collected_cases', 0)),
             'Resolved references: ' + str(report.get('resolved_reference_cases', 0)), '',
             '## Blockers', '']
    for issue in report.get('blockers', []):
        lines.append('- ' + issue['reason'] + (' [' + issue['case_id'] + ']' if 'case_id' in issue else ''))
    lines += ['- Integrity error: ' + error for error in report.get('errors', [])]
    (output / 'READINESS.md').write_text('\n'.join(lines) + '\n')
    print(json.dumps({key: report.get(key) for key in ['status', 'acceptance', 'collected_cases', 'resolved_reference_cases']}))
    return 1 if report['status'] == 'invalid' else 2 if report['status'] == 'incomplete' else 0


if __name__ == '__main__':
    raise SystemExit(main())
