#!/usr/bin/env python3
"""Assemble a private, source-hashed simulator harness; never launches or authorises HealthKit."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import uuid

ROOT = Path(__file__).resolve().parent
PARTS = ('ConsumerAssertions.swift', 'ConsumerStoreProbe.swift', 'ConsumerNativeAssertions.swift')

def digest(path):
    return hashlib.sha256(str(path.readlink()).encode() if path.is_symlink() else path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument('--source-ref')
    choice.add_argument('--working-tree', action='store_true', help='Explicitly snapshot scoped uncommitted work, including nonignored untracked files')
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--phone-udid', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--synthetic-only', action='store_true', required=True)
    args = parser.parse_args()
    phone = str(uuid.UUID(args.phone_udid)).upper()
    source, inputs, output = args.source_root.resolve(), args.inputs.resolve(), args.output.resolve()
    if output.exists() or output == source or source in output.parents:
        parser.error('Output must be absent and outside the source checkout')
    scenarios = json.loads((inputs / 'scenarios.json').read_text())
    if not isinstance(scenarios, list) or not scenarios:
        parser.error('Nonempty independently declared scenarios are required')
    names = set()
    for item in scenarios:
        name, archive = item['name'], item['archive']
        if not name or name in names or Path(name).name != name or name in ('.', '..'):
            parser.error('Unique plain scenario names required')
        names.add(name)
        if Path(archive).name != archive or archive in ('.', '..') or not (inputs / archive).is_file():
            parser.error('Archive must be an existing plain filename within inputs')
        if item.get('reboxWholeMetadata') or not item.get('expectedJSONPaths'):
            parser.error('Unmodified native objects and independent expectations required')
        uuid.UUID(item['nativeWorkoutUUID'])
    commit = subprocess.check_output(['git', 'rev-parse', args.source_ref or 'HEAD'], cwd=source, text=True).strip()
    output.mkdir(mode=0o700, parents=True)
    if args.working_tree:
        files = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=source).decode().split('\0')
        for name in filter(None, files):
            origin, target = source / name, output / name
            if origin.is_file() or origin.is_symlink():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(origin, target, follow_symlinks=False)
        (output / 'source-working-diff.patch').write_bytes(subprocess.check_output(['git', 'diff', '--binary', 'HEAD'], cwd=source))
    else:
        archive = subprocess.check_output(['git', 'archive', '--format=tar', commit], cwd=source)
        with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
            bundle.extractall(output, filter='data')
    source_hashes = {str(path.relative_to(output)): digest(path) for path in sorted(output.rglob('*')) if path.is_file() or path.is_symlink()}
    copied = output / 'JoinedInputs'
    copied.mkdir()
    for name in ['scenarios.json'] + [item['archive'] for item in scenarios]:
        shutil.copyfile(inputs / name, copied / name)
    helpers = output / 'HarnessHelpers'
    helpers.mkdir()
    for part in PARTS:
        shutil.copyfile(ROOT / part, helpers / part)
    identity = {'baseCommit': commit, 'workingTree': args.working_tree, 'phoneUDID': phone,
                'files': source_hashes, 'helpers': {part: digest(ROOT / part) for part in PARTS},
                'inputs': {path.name: digest(path) for path in sorted(copied.iterdir())}}
    assembly = {'id': str(uuid.uuid4()), 'sourceInputDigest': hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(',', ':')).encode()).hexdigest()}
    test = output / 'WeeklyHealthReportTests/DailyHealthExportTests.swift'
    test.write_text(test.read_text() + '\nimport CoreFoundation\n' + '\n'.join((ROOT / part).read_text().replace('__SYNTHETIC_PHONE_UDID__', phone).replace('__ASSEMBLY_ID__', assembly['id']).replace('__SOURCE_INPUT_DIGEST__', assembly['sourceInputDigest']) for part in PARTS))
    project = output / 'WeeklyHealthReport.xcodeproj/project.pbxproj'
    text = project.read_text()
    for sentinel in ['EE0000000000000000000001', 'EE0000000000000000000002']:
        if sentinel in text:
            raise ValueError('Harness resource identity already present')
    text = text.replace('/* Begin PBXBuildFile section */', '/* Begin PBXBuildFile section */\n\t\tEE0000000000000000000001 = {isa = PBXBuildFile; fileRef = EE0000000000000000000002; };')
    text = text.replace('/* Begin PBXFileReference section */', '/* Begin PBXFileReference section */\n\t\tEE0000000000000000000002 = {isa = PBXFileReference; lastKnownFileType = folder; path = JoinedInputs; sourceTree = SOURCE_ROOT; };')
    needle = 'J00000000000000000000002 /* Resources */ = {\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = ('
    if text.count(needle) != 1:
        raise ValueError('Test resource phase changed; review integration before proceeding')
    project.write_text(text.replace(needle, needle + '\n\t\t\t\tEE0000000000000000000001,'))
    manifest = dict(identity, assembly=assembly, assembledTestSHA256=digest(test), assembledProjectSHA256=digest(project))
    (output / 'source-inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(output)

if __name__ == '__main__':
    main()
