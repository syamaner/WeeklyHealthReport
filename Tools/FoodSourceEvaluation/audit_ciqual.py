#!/usr/bin/env python3
"""Offline Ciqual source-to-projection audit: traces every corpus value back to its compo literal.

This checks literal fidelity only. It does not measure food-match quality or user coverage.
"""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('project_ciqual', Path(__file__).resolve().parent / 'project_ciqual.py')
projector = importlib.util.module_from_spec(spec); spec.loader.exec_module(projector)


def expected_state(key, form):
    if form == 'missing': return 'unknown', 'not_declared'
    if form == 'traces': return 'unknown', 'no_compatible_source'
    if key in projector.UNPROJECTED: return 'unknown', projector.UNPROJECTED[key]
    return ('exact', None) if form == 'number' else ('bounded', None)


def audit(folder, corpus_path, files=projector.FILES):
    corpus_raw = corpus_path.read_bytes()
    corpus = json.loads(corpus_raw)
    manifest, contents = projector.verify(folder, files)
    if manifest != corpus['sourceManifest']: raise ValueError('manifest binding')
    if hashlib.sha256(projector.manifest_bytes(manifest)).hexdigest() != corpus['sourceManifestSHA256']:
        raise ValueError('manifest hash binding')
    compo_name = projector._name(contents, 'compo')
    if hashlib.sha256(contents[compo_name]).hexdigest() != corpus['compoSHA256']: raise ValueError('compo binding')
    foods = {f['alim_code']: f for f in projector.parse_rows(contents[projector._name(contents, 'alim')], 'alim')}
    rows = {(r['alim_code'], r['const_code']): r for r in projector.parse_rows(contents[compo_name], 'compo')}
    mapped_codes = {m[0] for m in projector.MAPPING.values() if m}
    scoped_codes = {r['alimCode'] for r in corpus['records']}
    admitted = {code for code, f in foods.items() if f['alim_ssgrp_code'] in projector.SUBGROUPS}
    if scoped_codes != admitted: raise ValueError('scope binding: corpus records differ from the admitted subgroup foods')

    values, failures = [], []
    for record in corpus['records']:
        code = record['alimCode']
        food = foods[code]
        if (food['alim_nom_eng'], food['alim_nom_fr'], food['alim_grp_code'], food['alim_ssgrp_code'], food['alim_ssssgrp_code']) != (
                record['name'], record['frenchName'], record.get('groupCode'), record['subgroupCode'], record.get('subSubgroupCode')):
            failures.append(dict(alimCode=code, field='identity'))
        # Every catalogue key must be present: a dropped key is a failure, never a smaller denominator.
        if set(record['nutrients']) != set(projector.MAPPING):
            failures.append(dict(alimCode=code, field='nutrientKeys'))
        if record['recordID'] != corpus['sourceReleaseID'] + ':alim:' + code:
            failures.append(dict(alimCode=code, field='recordID'))
        for key in sorted(record['nutrients']):
            value = record['nutrients'][key]
            mapped = projector.MAPPING[key]
            if mapped is None or 'constCode' not in value:
                ok = value == dict(state='unknown', reason='not_declared') and (mapped is None or (code, mapped[0]) not in rows)
                values.append(dict(alimCode=code, key=key, constCode=mapped[0] if mapped else None, compoLine=None,
                                   literal=None, state=value['state'], reason=value.get('reason'), passed=ok))
                if not ok: failures.append(dict(alimCode=code, key=key))
                continue
            row = rows[(code, mapped[0])]
            form, decimal = projector.classify(row['teneur'])
            state, reason = expected_state(key, form)
            ok = (value['constCode'] == mapped[0] and value['unit'] == mapped[1] and value['literal'] == row['teneur']
                  and value.get('confidence') == row['code_confiance'] and value.get('sourceCode') == row['source_code']
                  and value.get('min') == row['min'] and value.get('max') == row['max']
                  and value['state'] == state and value.get('reason') == reason
                  and (state != 'exact' or value['value'] == decimal)
                  and (state != 'bounded' or (value['upper'] == decimal and value['upperClosed'] is False)))
            entry = dict(alimCode=code, key=key, constCode=mapped[0], compoLine=row['_lines']['teneur'],
                         literal=row['teneur'], confidence=row['code_confiance'], state=value['state'], passed=ok)
            if state == 'exact': entry['value'] = value['value']
            if state == 'bounded': entry['upper'] = value['upper']
            if reason: entry['reason'] = reason
            values.append(entry)
            if not ok: failures.append(dict(alimCode=code, key=key))

    unprojected = Counter()
    energy_differences = []
    for (code, const), row in rows.items():
        if code not in scoped_codes: continue
        if const not in mapped_codes: unprojected[(const, projector.classify(row['teneur'])[0])] += 1
    for code in sorted(scoped_codes, key=int):
        kcal, jones = rows.get((code, '328')), rows.get((code, '333'))
        if kcal is None or jones is None or kcal['teneur'] != jones['teneur']:
            energy_differences.append(dict(alimCode=code, energy328=kcal and kcal['teneur'], energy333=jones and jones['teneur']))

    states = Counter((v['state'], v.get('reason')) for v in values)
    passed = sum(v['passed'] for v in values)
    return dict(
        schema='ciqual-source-audit-v1', projectionVersion=corpus['projectionVersion'], groupScope=corpus['groupScope'],
        doi=corpus['doi'], datasetVersion=corpus['datasetVersion'], sourceManifestSHA256=corpus['sourceManifestSHA256'],
        compoSHA256=corpus['compoSHA256'], projectionSHA256=hashlib.sha256(corpus_raw).hexdigest(),
        sourceFoods=corpus['sourceFoods'], sourceCompositionRows=corpus['sourceCompositionRows'],
        admittedRecords=len(corpus['records']), admittedSubgroups=corpus['subgroups'],
        valueCorrespondence=dict(passed=passed, denominator=len(values)),
        identityFailures=sum(1 for f in failures if 'field' in f),
        stateCounts={('%s:%s' % k if k[1] else k[0]): n for k, n in sorted(states.items(), key=lambda kv: (kv[0][0], kv[0][1] or ''))},
        confidenceCounts=dict(sorted(Counter(v.get('confidence') or '-' for v in values if v['literal'] is not None).items())),
        retainedZeroValues=sum(v['state'] == 'exact' and float(v['value']) == 0 for v in values),
        preparationCounts=dict(sorted(Counter(r['preparation'] for r in corpus['records']).items())),
        energy328Differs333=energy_differences,
        unprojectedConstituents=[dict(constCode=c, form=f, rows=n) for (c, f), n in sorted(unprojected.items(), key=lambda kv: (int(kv[0][0]), kv[0][1]))],
        providerCalls=0, independentAcceptance='not_run',
        limitations=['Literal source fidelity for one admitted subgroup, not a representative coverage rate.',
                     'Ciqual values are French averages per 100 g as sold; they do not establish a user product.',
                     'Water, vitamin A (decision A3), traces and "-" stay unknown; "< n" stays an open upper bound.'],
        values=values)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('downloads', type=Path); parser.add_argument('projection', type=Path); parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = audit(args.downloads, args.projection)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=False) + '\n', encoding='utf-8')
    summary = {k: v for k, v in result.items() if k not in ('values', 'unprojectedConstituents')}
    print(json.dumps(summary, ensure_ascii=False))
    if result['valueCorrespondence']['passed'] != result['valueCorrespondence']['denominator'] or result['identityFailures']:
        raise SystemExit(1)
