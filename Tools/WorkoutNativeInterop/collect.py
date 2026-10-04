#!/usr/bin/env python3
"""Retain only the exact current synthetic scenario set; reject incomplete or unequal evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assembled', type=Path, required=True)
    parser.add_argument('--documents-output', type=Path, required=True, help='Only the dedicated synthetic app Documents/JoinedOutput directory')
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--xcresult', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or any(root.resolve() == args.output.resolve() or root.resolve() in args.output.resolve().parents for root in [args.assembled, args.documents_output, args.xcresult]):
        parser.error('Retention destination must be absent and outside all input directories')
    manifest = json.loads((args.assembled / 'source-inputs.json').read_text())
    summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(args.xcresult)]))
    if summary.get('result') != 'Passed' or summary.get('totalTestCount') != 2 or summary.get('passedTests') != 2 or summary.get('failedTests') != 0 or summary.get('skippedTests') != 0:
        raise ValueError('Both native test methods must actually execute and pass; zero tests is not acceptance')
    configurations = summary.get('devicesAndConfigurations', [])
    if len(configurations) != 1 or configurations[0].get('device', {}).get('deviceId') != manifest['phoneUDID'] or configurations[0].get('device', {}).get('platform') != 'iOS Simulator':
        raise ValueError('Result bundle used a different destination')
    tree = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(args.xcresult)]))
    def test_cases(nodes):
        return [node for parent in nodes for node in ([parent] if parent.get('nodeType') == 'Test Case' else test_cases(parent.get('children', [])))]
    tests = test_cases(tree.get('testNodes', []))
    required = {'DailyHealthExportTests/testJoinedFreshPhoneStoreReadback()', 'DailyHealthExportTests/testJoinedProducerNativeArchivesToCanonicalDailyJSON()'}
    if len(tests) != 2 or {test.get('nodeIdentifier') for test in tests} != required or any(test.get('result') != 'Passed' for test in tests):
        raise ValueError('Unexpected native test identities or result')
    identity = {key: manifest[key] for key in ['baseCommit', 'workingTree', 'phoneUDID', 'files', 'helpers', 'inputs']}
    assembly = manifest['assembly']
    if hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(',', ':')).encode()).hexdigest() != assembly['sourceInputDigest']:
        raise ValueError('Source/input identity digest changed')
    def verify(path, expected):
        actual = hashlib.sha256(str(path.readlink()).encode() if path.is_symlink() else path.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError('Frozen input changed: ' + str(path))
    overridden = {'WeeklyHealthReportTests/DailyHealthExportTests.swift', 'WeeklyHealthReport.xcodeproj/project.pbxproj'}
    for name, expected in manifest['files'].items():
        if name not in overridden:
            verify(args.assembled / name, expected)
    for name, expected in manifest['helpers'].items():
        verify(args.assembled / 'HarnessHelpers' / name, expected)
    for name, expected in manifest['inputs'].items():
        verify(args.assembled / 'JoinedInputs' / name, expected)
    verify(args.assembled / 'WeeklyHealthReportTests/DailyHealthExportTests.swift', manifest['assembledTestSHA256'])
    verify(args.assembled / 'WeeklyHealthReport.xcodeproj/project.pbxproj', manifest['assembledProjectSHA256'])
    def verify_binding(value):
        if value.get('assemblyID') != assembly['id'] or value.get('sourceInputDigest') != assembly['sourceInputDigest']:
            raise ValueError('Output belongs to a different source/input assembly')
    scenarios = json.loads((args.assembled / 'JoinedInputs/scenarios.json').read_text())
    visibility = json.loads((args.documents_output / 'phone-store-visibility.json').read_text())
    if len(visibility) != len(scenarios):
        raise ValueError('Visibility evidence must contain exactly the current cases')
    selected = []
    for case in scenarios:
        name = case['name']
        if not name or Path(name).name != name or name in ('.', '..'):
            raise ValueError('Plain scenario name required')
        rows = [row for row in visibility if row.get('name') == name]
        if len(rows) != 1:
            raise ValueError('Missing or duplicate case visibility')
        row = rows[0]
        verify_binding(row)
        if row.get('requestedSyntheticUUID', '').upper() != case['nativeWorkoutUUID'].upper() or row.get('visibleCount') != 1:
            raise ValueError('Native identity/visibility mismatch')
        for field in ['actualSelectedDayFetchCompleted', 'pipelineCompleted', 'pipelineAssertionsPassed', 'associatedDistanceAssertionsPassed']:
            if row.get(field) is not True:
                raise ValueError('Incomplete native pipeline: ' + field)
        direct = args.documents_output / 'DirectPhoneRead' / (name + '.json')
        archived = args.documents_output / (name + '.json')
        if direct.read_bytes() != archived.read_bytes():
            raise ValueError('Direct/archive canonical bytes differ: ' + name)
        for folder in [args.documents_output, args.documents_output / 'DirectPhoneRead']:
            diagnostic = json.loads((folder / (name + '-native.json')).read_text())
            verify_binding(diagnostic)
            if diagnostic.get('caseAssertionsPassed') is not True or diagnostic.get('strictIdentity') != 'passed' or diagnostic.get('representationPerturbation') is not False:
                raise ValueError('Native diagnostic did not pass: ' + name)
            if diagnostic['expectedFieldCount'] != len(case['expectedJSONPaths']):
                raise ValueError('Descriptor field count differs')
        selected.append({'name': name, 'nativeWorkoutUUID': case['nativeWorkoutUUID'],
                         'independentFieldCountPerTransport': len(case['expectedJSONPaths']),
                         'canonicalSHA256': hashlib.sha256(direct.read_bytes()).hexdigest(),
                         'directArchiveBytesEqual': True})
    args.output.mkdir(parents=True, mode=0o700)
    shutil.copytree(args.assembled, args.output / 'assembled', symlinks=True)
    shutil.copytree(args.assembled / 'JoinedInputs', args.output / 'inputs')
    shutil.copyfile(args.assembled / 'source-inputs.json', args.output / 'source-inputs.json')
    (args.output / 'test-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    shutil.copyfile(args.log, args.output / 'run.log')
    shutil.copytree(args.xcresult, args.output / 'run.xcresult')
    shutil.copyfile(args.documents_output / 'phone-store-visibility.json', args.output / 'phone-store-visibility.json')
    for case in scenarios:
        name = case['name']
        for folder in ['', 'DirectPhoneRead']:
            target = args.output / 'outputs' / folder
            target.mkdir(parents=True, exist_ok=True)
            for suffix in ['.json', '-native.json']:
                shutil.copyfile(args.documents_output / folder / (name + suffix), target / (name + suffix))
        shutil.copyfile(args.documents_output / (name + '-phone-readback.archive'), args.output / 'outputs' / (name + '-phone-readback.archive'))
    (args.output / 'index.json').write_text(json.dumps({'assembly': assembly, 'cases': selected, 'caseCount': len(selected),
        'scope': 'Synthetic native save/sync/read evidence only; exact two native test identities, destination and passing xcresult verified' }, indent=2) + '\n')
    hashes = {str(path.relative_to(args.output)): hashlib.sha256(str(path.readlink()).encode() if path.is_symlink() else path.read_bytes()).hexdigest() for path in sorted(args.output.rglob('*')) if path.is_file() or path.is_symlink()}
    (args.output / 'sha256.json').write_text(json.dumps(hashes, indent=2) + '\n')
    print(json.dumps({'cases': len(selected), 'independentFieldsPerTransport': sum(row['independentFieldCountPerTransport'] for row in selected), 'retainedFiles': len(hashes)}))

if __name__ == '__main__':
    main()
