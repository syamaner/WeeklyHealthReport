"""Reproject an exposed frozen run for a separately labelled repair experiment.

Expected outputs remain byte-equivalent JSON values; no new capture or provider
call occurs here. The later frozen run retains the repaired projection and runtime.
"""
import json
from pathlib import Path
import subprocess
import sys

from frozen_run import digest, verify, write


def main(previous, executable, destination):
    previous, executable, destination = [Path(p).resolve() for p in (previous, executable, destination)]
    plan = verify(previous)
    if destination.exists():
        raise ValueError('repair already exists')
    destination.mkdir()
    cases = []
    for original in plan['cases']:
        case = dict(original)
        if case['task'] != 'provided_document':
            raise ValueError('provided documents required')
        folder = destination / case['id']; folder.mkdir()
        value = json.loads((previous / case['document']).read_text())
        documents = value if isinstance(value, list) else [value]
        evidence_files = [previous / name for name in case['evidence_files']]
        projected = []
        for index, document in enumerate(documents):
            raw = next(p for p in evidence_files if p.suffix == '.bin' and digest(p) == document['raw_sha256'])
            media = None
            for receipt in evidence_files:
                if receipt.name.endswith('capture-receipt.json'):
                    for response in json.loads(receipt.read_text())['responses']:
                        if response['body_sha256'] == document['raw_sha256']:
                            media = response['media_type'].split(';')[0].lower()
            if media is None:
                raise ValueError('capture media type required')
            original_path = folder / f'original-{index}.json'
            output = folder / f'projected-{index}.json'
            write(original_path, document)
            subprocess.run([str(executable), 'reproject', str(original_path), str(raw), media, str(output)], check=True)
            projected.append(json.loads(output.read_text()))
        document_path = folder / 'documents.json'
        write(document_path, projected)
        case.update(document=str(document_path.relative_to(destination)),
                    evidence_files=[str(p) for p in evidence_files],
                    reference_status='Previously exposed source-reviewed repair set; unchanged gold, not independent acceptance')
        cases.append(case)
    write(destination / 'roster.json', dict(cases=cases, previous_plan_sha256=digest(previous / 'plan.json'),
          previous_run=previous.name, gold_changed=False, fresh_sources=False,
          experiment='Repaired generic projection and extraction instruction; unchanged source bytes and gold.'))
    print(f'Reprojected {len(cases)} exposed cases without network or credentials.')


if __name__ == '__main__':
    main(*sys.argv[1:])
