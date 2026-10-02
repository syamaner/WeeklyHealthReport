"""Typed query to production save/projection: frozen synthetic actions, pure scorer."""
import hashlib
import json
import shutil
from pathlib import Path
from journey import same
HERE = Path(__file__).resolve().parent
SCHEMA = 'synthetic-linked-report-v1'


def score(reference, observations):
    if reference['schema'] != 'synthetic-linked-reference-v1': raise ValueError('linked_reference_schema')
    expected = {r['case_id']: r for r in reference['cases']}
    actual = {r['case_id']: r for r in observations}
    if not expected or len(expected) != len(reference['cases']) or len(actual) != len(observations) or expected.keys() != actual.keys():
        raise ValueError('linked_roster')
    details = []; guard_correct = 0; guard_total = 0
    stages = {'parser':['parser_route','parsed_quantity','parsed_unit'],
        'retrieval':['retrieval','target_found','selected_record'],
        'handoff':['initially_undecided','preaccept_blocked','handoff_value','handoff_unit','generic_estimate'],
        'save':['validation','error','saved_versions','operations','assertions','rows','original_preserved','provenance_preserved'],
        'daily_projection':['totals']}
    for cid, r in expected.items():
        if r['kind'] in ['save','block']:
            guard_total += 1
            guard_keys = ['initially_undecided','preaccept_blocked'] + (['validation','error','saved_versions','operations','rows'] if r['kind']=='block' else [])
            guard_correct += int(all(same(actual[cid].get(k,'missing'),r['expected'][k]) for k in guard_keys))
        failures = [k for k,v in r['expected'].items() if not same(actual[cid].get(k,'missing'),v)]
        details.append({'case_id':cid,'kind':r['kind'],'passed':not failures,'failures':failures,
            'stage_failures':[s for s,keys in stages.items() if set(keys)&set(failures)]})
    def metric(rows):return {'correct':sum(r['passed'] for r in rows),'total':len(rows)}
    # Every scheduled case remains in the full denominator; skipped stages are explicit.
    stage_counts = {}
    for stage in stages:
        eligible = [r for r in details if stage=='parser' or r['kind']!='parser_stop' and (stage=='retrieval' or r['kind']!='no_result')]
        stage_counts[stage] = {'correct':sum(stage not in r['stage_failures'] for r in eligible),'total':len(eligible)}
    return {'schema':SCHEMA,'status':'descriptive_synthetic_linked_journeys','reference_quality':reference['reference_quality'],
        'backend':'cofid','persistence':'in_memory','entry_boundary':'typed_query','model_quality':'not_run','independent_acceptance':'not_run',
        'metrics':{'all_linked_journeys':metric(details),'linked_saves':metric([r for r in details if r['kind']=='save']),
            'linked_blocks':metric([r for r in details if r['kind']=='block']),
            'expected_stops':metric([r for r in details if r['kind'] in ['parser_stop','no_result']]),
            'linked_safeguards':{'correct':guard_correct,'total':guard_total}},
        'stage_metrics':stage_counts,'details':details,'passed_exercised_contract':all(r['passed'] for r in details)}


def run(output, execute):
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    ref=HERE/'linked-reference-v3.json'; inputs=HERE/'linked-input-v1.json';freeze=HERE/'linked-freeze-v3.json'
    pins=json.loads(freeze.read_text());reference=json.loads(ref.read_text())
    sources=HERE.parents[1]/'Packages/FoodLedgerKit/Sources';corpus=sources/'FoodGenericSearch/Resources/cofid-2021-generic-search-v1.json'
    if sha(ref)!=pins['reference_sha256'] or sha(inputs)!=pins['input_sha256'] or sha(corpus)!=reference['source_sha256']:
        raise ValueError('linked_freeze_changed')
    build=output/'linked-build';build.mkdir(mode=0o700)
    resources=build/'Resources';resources.mkdir(mode=0o700)
    milk=sources/'FoodGenericSearch/Resources/cofid-whole-milk-volume-v1.json'
    retained_milk=resources/milk.name;shutil.copyfile(milk,retained_milk)
    accessor=build/'ModuleBundle.swift';accessor.write_text('import Foundation\nextension Bundle { static var module: Bundle { .main } }\n')
    generic=[sources/'FoodGenericSearch'/n for n in ['CoFIDGenericFoodSearch.swift','GenericFoodSearchTerms.swift','USDAGenericFoodSearch.swift','CoFIDWholeMilkVolumeConversion.swift']]
    paths=[HERE/'linked.py',HERE/'linked.swift',HERE/'journey.py',ref,inputs,freeze,corpus,accessor,milk,retained_milk,*generic]
    for m in ['FoodLedgerDomain','FoodLedgerApplication','FoodLedgerTestSupport']:paths.extend(sorted((sources/m).glob('*.swift')))
    before={str(p):sha(p) for p in paths}
    (output/'linked-input-pins.json').write_text(json.dumps(before,indent=2)+'\n')
    (output/'linked-reference.json').write_bytes(ref.read_bytes());(output/'linked-input.json').write_bytes(inputs.read_bytes())
    common=['swiftc','-module-cache-path',build/'module-cache'];execution=[]
    def invoke(args):
        r=execute(args,output,output/('linked-command-'+str(len(execution))+'.log'));execution.append(r)
        if r['exit_code']!=0:raise ValueError('linked_execution_failure')
    for m in ['FoodLedgerDomain','FoodLedgerApplication','FoodLedgerTestSupport']:
        deps=[] if m=='FoodLedgerDomain' else ['-I',build,'-L',build,'-lFoodLedgerDomain']
        if m=='FoodLedgerTestSupport':deps+=['-lFoodLedgerApplication']
        invoke(common+['-emit-library','-emit-module','-module-name',m,'-emit-module-path',build/(m+'.swiftmodule'),'-o',build/('lib'+m+'.dylib')]+deps+sorted((sources/m).glob('*.swift')))
    invoke(common+['-emit-library','-emit-module','-module-name','FoodGenericSearch','-emit-module-path',build/'FoodGenericSearch.swiftmodule','-I',build,'-L',build,'-lFoodLedgerDomain','-lFoodLedgerApplication','-o',build/'libFoodGenericSearch.dylib',*generic,accessor])
    invoke(common+[HERE/'linked.swift','-parse-as-library','-I',build,'-L',build,'-lFoodLedgerDomain','-lFoodLedgerApplication','-lFoodLedgerTestSupport','-lFoodGenericSearch','-Xlinker','-rpath','-Xlinker',build,'-o',build/'linked-runner'])
    invoke([build/'linked-runner',output/'linked-input.json',corpus,output/'linked-observations.json'])
    if any(sha(Path(p))!=h for p,h in before.items()):raise ValueError('linked_inputs_changed')
    report=score(reference,json.loads((output/'linked-observations.json').read_text()))
    report['input_sha256']=before;report['execution']=execution
    (output/'linked-report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report
