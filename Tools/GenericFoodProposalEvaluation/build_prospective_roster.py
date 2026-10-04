"""Prepare source-reviewed comparison inputs before any model predictions.

Reference gold is maintained separately by a reviewer who has not seen predictions.
This tool checks capture identity and retains raw evidence, never adjusts gold to
model output. No credentials or provider calls.
"""
import argparse
import json
from pathlib import Path
import shutil
from urllib.parse import urlparse

from frozen_run import digest, validate_cases, write
from capture_discovery import verify_capture_outputs


def build(references, captures, destination, routes):
    references, captures, destination = [Path(p).resolve() for p in (references, captures, destination)]
    if destination.exists() or not routes or len(routes) != len(set(routes)) or not set(routes) <= {'luna', 'sol', 'qwen', 'grok', 'opus'}:
        raise ValueError('invalid comparison')
    review = json.loads(references.read_text())
    if review.get('predictions_seen') is not False:
        raise ValueError('reference was exposed to predictions')
    audit = json.loads((captures / 'report.json').read_text())
    capture_plan = json.loads((captures / 'plan.json').read_text())
    if digest(captures / 'plan.json') != (captures / 'plan.sha256').read_text().strip():
        raise ValueError('capture plan changed')
    capture_integrity = verify_capture_outputs(captures, capture_plan, audit)
    planned = {c['id']: c for c in capture_plan['cases']}
    audited = {c['id']: c for c in audit['cases']}
    reviewed = {c['id']: c for c in review['cases']}
    if (len(planned) != len(capture_plan['cases']) or len(audited) != len(audit['cases'])
            or len(reviewed) != len(review['cases']) or set(planned) != set(audited) or set(planned) != set(reviewed)):
        raise ValueError('every originally planned acquisition must remain in the review')
    documents = {}
    excluded = []
    eligible = []
    for case in review['cases']:
        if case['query'] != planned[case['id']]['query'] or case['source_url'] != planned[case['id']]['url']:
            raise ValueError('prospective query or source URL changed after capture planning')
        if audited[case['id']]['status'] != 'captured':
            if case.get('extraction_eligible') is not False or case.get('expected_action') != 'acquisition_unavailable':
                raise ValueError('source failure needs an explicit pre-prediction acquisition-unavailable review')
            excluded.append(dict(id=case['id'], status=audited[case['id']]['status'],
                                 closed_error=audited[case['id']].get('closed_error')))
            continue
        if case.get('extraction_eligible', True) is not True or case['expected_action'] not in ['select_partial', 'abstain']:
            raise ValueError('captured source needs explicit reviewed extraction expectations')
        document = json.loads((captures / 'results' / case['id'] / 'document.json').read_text())
        if document['raw_sha256'] != case['capture_review']['raw_sha256']:
            raise ValueError('review and capture differ')
        raw_files = (captures / 'results' / case['id']).glob('source-body-*.bin')
        if not any(digest(raw) == document['raw_sha256'] for raw in raw_files):
            raise ValueError('retained source bytes do not match the reviewed document')
        if case['source_url'] in documents:
            raise ValueError('duplicate captured source URL needs an explicit case mapping')
        documents[case['source_url']] = document
        eligible.append(case)
    for case in eligible:
        decoys = case.get('decoy_source_urls', [])
        if (not isinstance(decoys, list) or not all(isinstance(url, str) for url in decoys)
                or len(set(decoys)) != len(decoys) or case['source_url'] in decoys
                or any(url not in documents for url in decoys)):
            raise ValueError('decoys must be distinct captured and reviewed source URLs')
    eligibility = {}
    if any('workflow_source_eligible' in case for case in eligible):
        if not all(isinstance(case.get('workflow_source_eligible'), bool)
                   and isinstance(case.get('source_eligibility_reason'), str)
                   and case['source_eligibility_reason'] for case in eligible):
            raise ValueError('workflow source review must cover every captured case')
        eligibility = {case['id']: dict(eligible=case['workflow_source_eligible'], reason=case['source_eligibility_reason'])
                       for case in eligible}
    documents_to_write = {}
    evidence_to_copy = {}
    cases = []
    for reference in eligible:
        identifier = reference['id']
        urls = sorted([reference['source_url']] + reference.get('decoy_source_urls', []))
        supplied = [documents[url] for url in urls]
        documents_to_write[identifier + '.json'] = supplied
        target = documents[reference['source_url']]
        if reference['expected_action'] == 'abstain':
            gold = dict(outcome='abstain', allowed_choices=['none', 'clarify'])
        else:
            gold = dict(outcome='selected', allowed_names=reference['identity']['aliases'],
                        allowed_document_ids=[target['id']],
                        basis={k: reference['source_basis'][k] for k in ['amount', 'unit']},
                        nutrients={k: v['value'] for k, v in reference['nutrients'].items()})
            equivalents = reference.get('allowed_equivalent_bases', reference.get('permissible_equivalent_bases', []))
            if equivalents:
                gold['allowed_equivalent_bases'] = [{k: b[k] for k in ['amount', 'unit']}
                                                  for b in equivalents]
        evidence = ['source-references.json', 'capture-report.json']
        for other in review['cases']:
            if other['source_url'] not in urls:
                continue
            source_folder = captures / 'results' / other['id']
            for original in sorted(source_folder.glob('source-body-*.bin')) + [source_folder / 'capture-receipt.json']:
                copied = destination / 'evidence' / other['id'] / original.name
                evidence_to_copy[copied] = original
                evidence.append(str(copied.relative_to(destination)))
        for route in routes:
            cases.append(dict(id=route + '-' + identifier, comparison_case=identifier,
                              task='provided_document', extractor=route, selection=False,
                              query=reference['query'], document=identifier + '.json', evidence_files=evidence,
                              family=reference.get('comparison_group_id', reference.get('family_group_id', identifier)),
                              layout=reference['category'], domain=urlparse(reference['source_url']).hostname,
                              slice='taiwan_market' if reference['identity']['country'] == 'TW' else 'local_general',
                              reference_status=review['reference_status'], gold=gold))
    validate_cases(cases)
    # Finish semantic validation before creating any output or copying evidence.
    destination.mkdir(parents=True)
    shutil.copy2(references, destination / 'source-references.json')
    shutil.copy2(captures / 'report.json', destination / 'capture-report.json')
    for name, value in documents_to_write.items():
        write(destination / name, value)
    for copied, original in evidence_to_copy.items():
        copied.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, copied)
    write(destination / 'roster.json', dict(cases=cases, reference_sha256=digest(references),
          capture_plan_sha256=digest(captures / 'plan.json'),
          acquisition=dict(planned_case_ids=[c['id'] for c in review['cases']],
                           captured_case_ids=[c['id'] for c in eligible], excluded_cases=excluded,
                           source_eligibility=eligibility,
                           output_integrity=capture_integrity,
                           scope='Preselected public URLs; no discovery performance is implied.'),
          comparison='Identical captured documents, order, prompt and schema; extraction only; no search or Jev.',
          independent_acceptance=False, confidence_calibrated=False,
          qualification='Agent source review before predictions; case aliases and equivalent bases fixed before inference.'))
    print(f'Prepared {len(cases)} extraction cases; capture coverage {len(eligible)}/{len(review["cases"])} remains in the frozen metadata.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('references'); parser.add_argument('captures'); parser.add_argument('destination')
    parser.add_argument('--routes', nargs='+', required=True)
    args = parser.parse_args()
    build(args.references, args.captures, args.destination, args.routes)
