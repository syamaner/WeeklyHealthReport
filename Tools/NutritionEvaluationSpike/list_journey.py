"""Pure list/line scoring and a runner over freshly built production dependencies."""
import hashlib
import json
from pathlib import Path
from journey import same
HERE=Path(__file__).resolve().parent
SCHEMA='synthetic-list-report-v1'


def score(reference,observations):
    if reference['schema']!='synthetic-list-reference-v1':raise ValueError('list_reference_schema')
    expected={c['case_id']:c for c in reference['cases']};actual={c['case_id']:c for c in observations}
    if not expected or len(expected)!=len(reference['cases']) or len(actual)!=len(observations) or expected.keys()!=actual.keys():raise ValueError('list_case_roster')
    details=[];line_details=[];guards=0;parse_correct=0
    parser_keys=['line','original','query','quantity','unit','preparation','notices']
    for cid,case in expected.items():
        ref=case['expected'];obs=actual[cid]
        observed_lines=obs.get('lines',[])
        if not isinstance(observed_lines,list):observed_lines=[]
        nums=[l.get('line') for l in observed_lines]
        roster_ok=len(nums)==len(set(nums)) and set(nums)=={l['line'] for l in ref['lines']}
        rows={l.get('line'):l for l in observed_lines}
        failures=[] if roster_ok else ['line_roster']
        for line in ref['lines']:
            observed=rows.get(line['line'],{})
            failed=[k for k,v in line.items() if not same(observed.get(k,'missing'),v)]
            if not roster_ok:failed.append('line_roster')
            parser_ok=not(set(parser_keys)&set(failed)) and roster_ok
            parse_correct+=int(parser_ok)
            guard_keys=(['initially_undecided','preaccept_blocked'] if line['record'] else ['write_delta']) + (['write_delta','outcome'] if line['outcome']=='blocked' else [])
            # Supported-save refusal is an outcome failure, not an unsafe admission.
            # Quantity-specific rejection can be masked by an earlier identity gate;
            # only the reference outcome/error earns that case's correctness credit.
            guard_ok=roster_ok and all(same(observed.get(k,'missing'),line[k]) for k in guard_keys)
            guards+=int(guard_ok)
            line_details.append({'case_id':cid,'line':line['line'],'passed':not failed,'failures':failed,'parser_passed':parser_ok,'safeguard_passed':guard_ok})
            if failed:failures.append('line:'+str(line['line']))
        for k,v in ref.items():
            if k!='lines' and not same(obs.get(k,'missing'),v):failures.append(k)
        details.append({'case_id':cid,'passed':not failures,'failures':failures,'daily_passed':'totals' not in failures})
    metric=lambda rows:{'correct':sum(r['passed'] for r in rows),'total':len(rows)}
    return {'schema':SCHEMA,'status':'descriptive_synthetic_list_journeys','backend':'cofid','persistence':'in_memory',
        'reference_quality':reference['reference_quality'],'model_quality':'not_run','independent_acceptance':'not_run',
        'metrics':{'whole_lists':metric(details),'line_outcomes':metric(line_details),
            'line_parsing':{'correct':parse_correct,'total':len(line_details)},
            'list_safeguards':{'correct':guards,'total':len(line_details)},
            'daily_totals':{'correct':sum(c['daily_passed'] for c in details),'total':len(details)}},
        'details':details,'line_details':line_details,'passed_exercised_contract':all(c['passed'] for c in details)}


def run(output,execute,compiled_root=None):
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    inputs=HERE/'list-input-v1.json';ref=HERE/'list-reference-v3.json';freeze=HERE/'list-freeze-v3.json'
    pins=json.loads(freeze.read_text());reference=json.loads(ref.read_text())
    if sha(inputs)!=pins['input_sha256'] or sha(ref)!=pins['reference_sha256']:raise ValueError('list_freeze_changed')
    # Master runs the linked adapter first. Reuse only its hash-verified modules,
    # avoiding another compilation of identical production code in this run.
    build=compiled_root or output/'linked-build'
    linked_report=build.parent/'linked-report.json'
    dependency=json.loads(linked_report.read_text())
    if any(sha(Path(p))!=h for p,h in dependency['input_sha256'].items()):raise ValueError('list_dependency_source_changed')
    corpus=HERE.parents[1]/'Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources/cofid-2021-generic-search-v1.json'
    if sha(corpus)!=reference['source_sha256']:raise ValueError('list_corpus_changed')
    dependencies=[*build.glob('*.dylib'),*build.glob('*.swiftmodule')]
    if len(dependencies)!=8:raise ValueError('list_dependency_module_roster')
    paths=[HERE/'list_journey.py',HERE/'list_journey.swift',HERE/'journey.py',inputs,ref,freeze,corpus,linked_report,*dependencies]
    before={str(p):sha(p) for p in paths}
    (output/'list-input-pins.json').write_text(json.dumps(before,indent=2)+'\n')
    (output/'list-reference.json').write_bytes(ref.read_bytes());(output/'list-input.json').write_bytes(inputs.read_bytes())
    target=output/'list-build';target.mkdir(mode=0o700);execution=[]
    def invoke(args):
        r=execute(args,output,output/('list-command-'+str(len(execution))+'.log'));execution.append(r)
        if r['exit_code']!=0:raise ValueError('list_execution_failure')
    invoke(['swiftc','-module-cache-path',target/'module-cache','-parse-as-library',HERE/'list_journey.swift','-I',build,'-L',build,'-lFoodLedgerDomain','-lFoodLedgerApplication','-lFoodLedgerTestSupport','-lFoodGenericSearch','-Xlinker','-rpath','-Xlinker',build,'-o',target/'list-runner'])
    invoke([target/'list-runner',output/'list-input.json',corpus,output/'list-observations.json'])
    if any(sha(Path(p))!=h for p,h in before.items()) or any(sha(Path(p))!=h for p,h in dependency['input_sha256'].items()):raise ValueError('list_inputs_changed')
    report=score(reference,json.loads((output/'list-observations.json').read_text()))
    report['input_sha256']=before;report['production_dependency_sha256']=dependency['input_sha256'];report['execution']=execution
    (output/'list-report.json').write_text(json.dumps(report,indent=2)+'\n');return report
