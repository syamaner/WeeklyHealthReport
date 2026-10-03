"""Frozen multi-source and record-bound conversion journeys, using production modules."""
import hashlib,json
from pathlib import Path
from journey import same
HERE=Path(__file__).resolve().parent
SCHEMA='synthetic-multi-source-report-v1'


def score(reference, observations):
    if reference.get('schema')!='synthetic-multi-source-reference-v1':raise ValueError('multi_schema')
    expected={r['case_id']:r for r in reference['cases']};actual={r['case_id']:r for r in observations}
    if not expected or len(expected)!=len(reference['cases']) or len(actual)!=len(observations) or expected.keys()!=actual.keys():raise ValueError('multi_roster')
    details=[];guards=0;conversions=[]
    for cid,case in expected.items():
        ref=case['expected'];obs=actual[cid]
        failed=[k for k,v in ref.items() if not same(obs.get(k,'missing'),v)]
        guard_keys=['initially_undecided','preaccept_blocked']
        if case['kind']=='block':guard_keys+=['validation','error','operations','saved_versions','rows']
        if ref['handoff_unit']=='mL':
            guard_keys+=['conversion_offered','conversion_applied','edible_value','edible_unit','totals']
            conversions.append({'passed':not failed})
        guards+=int(all(same(obs.get(k,'missing'),ref[k]) for k in guard_keys))
        details.append({'case_id':cid,'kind':case['kind'],'passed':not failed,'failures':failed})
    metric=lambda rows:{'correct':sum(r['passed'] for r in rows),'total':len(rows)}
    return {'schema':SCHEMA,'status':'descriptive_synthetic_multi_source_journeys','reference_quality':reference['reference_quality'],
      'backend':'cofid_usda_composite','entry_boundary':'typed_query_and_list','persistence':'in_memory',
      'model_quality':'not_run','independent_acceptance':'not_run',
      'metrics':{'all_journeys':metric(details),'saved_outcomes':metric([r for r in details if r['kind']=='save']),
        'blocked_outcomes':metric([r for r in details if r['kind']=='block']),'volume_outcomes':metric(conversions),
        'safeguards':{'correct':guards,'total':len(details)}},
      'details':details,'passed_exercised_contract':all(r['passed'] for r in details)}


def run(output,execute):
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    inputs=HERE/'multi-input-v3.json';ref=HERE/'multi-reference-v3.json';freeze=HERE/'multi-freeze-v3.json'
    reference=json.loads(ref.read_text());pins=json.loads(freeze.read_text())
    if sha(inputs)!=pins['input_sha256'] or sha(ref)!=pins['reference_sha256']:raise ValueError('multi_freeze_changed')
    res=HERE.parents[1]/'Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources'
    if any(sha(res/n)!=h for n,h in reference['source_sha256'].items()):raise ValueError('multi_corpus_changed')
    build=output/'linked-build';linked_report=output/'linked-report.json';dependency=json.loads(linked_report.read_text())
    if any(sha(Path(p))!=h for p,h in dependency['input_sha256'].items()):raise ValueError('multi_dependency_source_changed')
    libraries=[*build.glob('*.dylib'),*build.glob('*.swiftmodule')]
    if len(libraries)!=8:raise ValueError('multi_dependency_roster')
    paths=[HERE/'multi_source.py',HERE/'multi_source.swift',HERE/'journey.py',HERE/'freeze_multi_source.py',inputs,ref,freeze,linked_report,*libraries,*[res/n for n in reference['source_sha256']]]
    before={str(p):sha(p) for p in paths};(output/'multi-input-pins.json').write_text(json.dumps(before,indent=2)+'\n')
    (output/'multi-reference.json').write_bytes(ref.read_bytes());(output/'multi-input.json').write_bytes(inputs.read_bytes())
    execution=[]
    def invoke(args):
        r=execute(args,output,output/('multi-command-'+str(len(execution))+'.log'));execution.append(r)
        if r['exit_code']!=0:raise ValueError('multi_execution_failure')
    invoke(['swiftc','-module-cache-path',build/'module-cache','-parse-as-library',HERE/'multi_source.swift','-I',build,'-L',build,'-lFoodLedgerDomain','-lFoodLedgerApplication','-lFoodLedgerTestSupport','-lFoodGenericSearch','-Xlinker','-rpath','-Xlinker',build,'-o',build/'multi-runner'])
    invoke([build/'multi-runner',output/'multi-input.json',res/'cofid-2021-generic-search-v1.json',res/'usda-generic-v1.json',output/'multi-observations.json'])
    if any(sha(Path(p))!=h for p,h in before.items()) or any(sha(Path(p))!=h for p,h in dependency['input_sha256'].items()):raise ValueError('multi_inputs_changed')
    report=score(reference,json.loads((output/'multi-observations.json').read_text()))
    report['input_sha256']=before;report['production_dependency_sha256']=dependency['input_sha256'];report['execution']=execution
    (output/'multi-report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report
