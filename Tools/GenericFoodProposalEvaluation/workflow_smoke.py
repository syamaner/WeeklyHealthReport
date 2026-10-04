"""Prospective full Swift reviewer availability smoke; no numeric gold/scoring.

The existing private loader is the sole credential-file consumer. This harness
never reads a credential file. Frozen binaries and source snapshots are immutable.
"""
import argparse
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

VERSION = 'workflow-live-smoke-v3'
PRIVATE = Path('/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1')
LOADER = PRIVATE/'evaluation-v4/run_private_env.py'
REPO = Path(__file__).resolve().parents[2]
CRITERIA = {
    'scope': 'Agent-reviewed development orchestration/availability smoke, not independent nutrition accuracy or source correctness scoring.',
    'composition': 'GenericFoodProposalReviewer with source-market-conflict-v1; Luna/Azure discovery; Exa max_results3; qualified primary-only v1 Luna/Azure source choice; PublicFoodSourceCapture; Grok/xai/zdr extraction; mandatory Luna/Azure applicability check; no Jev.',
    'completion': 'Reviewer returns through its real semantic binder; record suggested choice and permitsConfirmation IDs. An empty allowed set is not useful nutrition coverage.',
    'abstention': 'Keep source-selector and extractor abstentions in original six-query denominator; never substitute URL, query or model.',
    'failures': 'Record partial stages and original errors; no retry or fallback. Source-capture, provider, reviewer and harness timeouts, and unknown reported costs, stop later subset cases.',
    'privacy': 'Only public food queries, native lead metadata and captured public documents reach providers. Public source transport receives no provider headers/key. Inference ZDR/data_collection deny do not establish Exa tool retention.',
    'deadline': 'One real reviewer150s deadline; harness210s kill guard, which cannot be presented as150s if cancellation cleanup exceeds it.',
    'subset': 'Explicit nonempty ordered subset of the unchanged original six-query cohort; subset and original denominators stay separate. No cross-version pooled score or reattempt inferred.',
    'cost': 'Maximum3 provider calls per selected query,3 times subset count total (at most18); reported $.05 per-case continuation stop and $1.50 global stop, not prepaid hard caps.'
}

def stamp(): return datetime.now(timezone.utc).isoformat()
def digest(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p, obj):
    p=Path(p);tmp=p.with_suffix(p.suffix+'.tmp');tmp.write_text(json.dumps(obj,ensure_ascii=False,indent=2,allow_nan=False)+'\n');tmp.replace(p)
def read(p): return json.loads(Path(p).read_text())

def select_subset(original, ids):
    cohort=[dict(id=c['id'],query=c['query'])for c in original['cases']]
    if len(cohort)!=6 or len({c['id']for c in cohort})!=6 or any(not re.fullmatch('[a-z0-9-]+',c['id'])or not 0<len(c['query'])<=300 for c in cohort):
        raise ValueError('six original queries required')
    if not isinstance(ids,list)or not ids or not all(isinstance(x,str)for x in ids)or len(set(ids))!=len(ids):
        raise ValueError('nonempty distinct subset IDs required')
    selected=[c for c in cohort if c['id']in ids]
    if [c['id']for c in selected]!=ids:raise ValueError('unknown IDs or original ordering changed')
    return cohort,selected

def freeze(discovery, executable, destination, subset_ids):
    discovery,exe,root=map(lambda p:Path(p).resolve(),[discovery,executable,destination])
    if root.exists(): raise ValueError('destination exists')
    original=read(discovery/'plan.json')
    if digest(discovery/'plan.json')!=(discovery/'plan.sha256').read_text().strip():raise ValueError('original query plan changed')
    cohort,cases=select_subset(original,subset_ids)
    bundle=exe.parent/'FoodLedgerKit_FoodGenericSearch.bundle'
    if not exe.is_file()or not bundle.is_dir():raise ValueError('compiled runtime missing')
    runtime=root/'snapshot/runtime';runtime.mkdir(parents=True)
    shutil.copy2(exe,runtime/'FoodProposalProbe');shutil.copytree(bundle,runtime/bundle.name)
    package=REPO/'Packages/FoodLedgerKit'
    sources=list((package/'Sources').rglob('*.swift'))+list((package/'Tools').rglob('*.swift'))
    sources += [package/'Package.swift',package/'Package.resolved',REPO/'WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift']
    sources += list((package/'Sources/FoodGenericSearch/Resources/OpenRouter').glob('*'))
    sources += [Path(__file__),Path(__file__).with_name('test_workflow_smoke.py')]
    for p in sources:
        if not p.is_file():continue
        target=root/'snapshot/source'/p.relative_to(REPO);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
    write(root/'snapshot/criteria.json',CRITERIA);shutil.copy2(discovery/'plan.json',root/'snapshot/original-query-plan.json')
    plan=dict(version=VERSION,frozen_at=stamp(),cases=cases,denominator=len(cases),subset_denominator=len(cases),original_cohort_denominator=6,
              original_cohort=cohort,subset_ids=subset_ids,excluded_case_ids=[c['id']for c in cohort if c['id']not in subset_ids],
              maximum_requests=4*len(cases),maximum_requests_per_case=4,
              reviewer_deadline_seconds=150,harness_timeout_seconds=210,minimum_interval_seconds=15,automatic_retries=0,
              executable='snapshot/runtime/FoodProposalProbe',reported_cost_stop_usd='1.50',per_case_reported_cost_stop_usd='0.05',
              cost_stop_is_not_prepaid_hard_cap=True,private_loader_sha256=digest(LOADER),original_plan_sha256=digest(discovery/'plan.json'),
              python_runtime=dict(executable=sys.executable,version=sys.version,sha256=digest(sys.executable)),
              snapshot_hashes={str(p.relative_to(root)):digest(p)for p in sorted((root/'snapshot').rglob('*'))if p.is_file()},
              predictions_seen=False,independent_acceptance=False,numeric_accuracy_scored=False,
              run_kind='explicit_subset_development_follow_up',
              prior_evidence='Earlier staged or live results from this cohort may be known; predictions_seen refers only to this newly frozen run. No independent acceptance or pooled cross-version result is implied.')
    write(root/'plan.json',plan);(root/'plan.sha256').write_text(digest(root/'plan.json')+'\n');return plan

def verify(root):
    root=Path(root).resolve();p=read(root/'plan.json')
    if digest(root/'plan.json')!=(root/'plan.sha256').read_text().strip():raise ValueError('plan changed')
    if (p['version']!=VERSION or not 1<=len(p['cases'])<=6 or p['maximum_requests']!=4*len(p['cases'])
            or p['maximum_requests_per_case']!=4 or p['automatic_retries']!=0 or p['original_cohort_denominator']!=6
            or p['subset_denominator']!=len(p['cases']) or p['denominator']!=len(p['cases'])):raise ValueError('contract changed')
    if digest(LOADER)!=p['private_loader_sha256']:raise ValueError('loader changed')
    if p['python_runtime']!=dict(executable=sys.executable,version=sys.version,sha256=digest(sys.executable)):raise ValueError('runtime changed')
    for name,sha in p['snapshot_hashes'].items():
        f=(root/name).resolve()
        if not f.is_relative_to(root/'snapshot')or digest(f)!=sha:raise ValueError('snapshot changed')
    if read(root/'snapshot/criteria.json')!=CRITERIA:raise ValueError('criteria changed')
    source=read(root/'snapshot/original-query-plan.json')
    if digest(root/'snapshot/original-query-plan.json')!=p['original_plan_sha256']:raise ValueError('original plan bytes changed')
    cohort,cases=select_subset(source,p['subset_ids'])
    if p['cases']!=cases or p['original_cohort']!=cohort or p['excluded_case_ids']!=[c['id']for c in cohort if c['id']not in p['subset_ids']]:raise ValueError('query subset changed')
    return p

def cost_receipt(folder):
    path=folder/'receipt.json'
    if not path.exists():return dict(request_count=0,known_cost_requests=0,cost_known=False,reported_cost_usd='0')
    receipt=read(path);rows=receipt['requests']
    if not 1<=len(rows)<=4 or receipt['maximum_requests']!=4 or receipt['automatic_retries']!=0:raise ValueError('request cap')
    total=Decimal(0);known=0
    for i,row in enumerate(rows,1):
        if row['request']!=i or digest(folder/f'request-{i}.json')!=row['request_sha256']:raise ValueError('request integrity')
        cost=row.get('reported_cost_usd')
        if cost is None:continue
        if isinstance(cost,bool):raise ValueError('cost type')
        amount=Decimal(str(cost))
        if not amount.is_finite()or amount<0:raise ValueError('cost value')
        response=folder/f'response-{i}.json'
        if not response.exists()or digest(response)!=row['response_sha256']:raise ValueError('response integrity')
        actual=read(response).get('usage',{}).get('cost')
        if actual is None or isinstance(actual,bool)or Decimal(str(actual))!=amount:raise ValueError('cost does not match response')
        known+=1;total+=amount
    return dict(request_count=len(rows),known_cost_requests=known,cost_known=known==len(rows),reported_cost_usd=str(total))

def execute(args,timeout,env):
    return subprocess.run(args,timeout=timeout,env=env,capture_output=True,check=False).returncode

def load_environment():
    sys.path.insert(0,str(LOADER.parent))
    from run_private_env import load_credentials
    load_credentials(PRIVATE/'evaluation-v2')
    return {k:v for k,v in os.environ.items() if k not in ['GEMINI_API_KEY','GOOGLE_API_KEY','ANTHROPIC_API_KEY']}

def run(root,invoke=execute,environment=load_environment,sleeper=time.sleep):
    root=Path(root).resolve();plan=verify(root)
    own='snapshot/source/Tools/GenericFoodProposalEvaluation/workflow_smoke.py'
    if digest(Path(__file__))!=plan['snapshot_hashes'][own]:raise ValueError('use frozen runner')
    with (root/'started.json').open('x') as f:json.dump({'started_at':stamp()},f)
    (root/'results').mkdir();env=environment();total=Decimal(0);calls=0
    rows=[dict(id=c['id'],query=c['query'],status='not_attempted')for c in plan['cases']]
    summary=dict(version=VERSION,status='running',denominator=plan['subset_denominator'],subset_denominator=plan['subset_denominator'],
                 original_cohort_denominator=6,subset_ids=plan['subset_ids'],excluded_case_ids=plan['excluded_case_ids'],cases=rows,request_count=0,reported_cost_usd='0',all_request_costs_known=True,numeric_accuracy_scored=False)
    for i,c in enumerate(plan['cases']):
        if i:sleeper(plan['minimum_interval_seconds'])
        folder=root/'results'/c['id'];start=time.monotonic();rc=None;timed_out=False
        # The child creates its destination; a one-shot top-level marker forbids resume/retry.
        try:rc=invoke([str(root/plan['executable']),'review-smoke',c['query'],str(folder)],plan['harness_timeout_seconds'],env)
        except subprocess.TimeoutExpired:timed_out=True
        except Exception:pass
        elapsed=time.monotonic()-start;folder.mkdir(exist_ok=True)
        try:cost=cost_receipt(folder)
        except Exception:cost=dict(request_count=len(list(folder.glob('request-*.json'))),known_cost_requests=0,cost_known=False,reported_cost_usd='0',integrity_error=True)
        total+=Decimal(cost['reported_cost_usd']);calls+=cost['request_count']
        result=read(folder/'result.json')if(folder/'result.json').exists()else{}
        stages=read(folder/'stages.json').get('stages',[])if(folder/'stages.json').exists()else[]
        row=dict(id=c['id'],query=c['query'],status='harness_timeout'if timed_out else result.get('status','process_failed'),
                 process_exit_code=rc,full_process_elapsed_seconds=elapsed,review_elapsed_seconds=result.get('review_elapsed_seconds'),
                 closed_error=result.get('closed_error'),allowed_confirmation_ids=result.get('allowed_confirmation_ids',[]),
                 suggested_choice=result.get('suggested_choice'),stages=stages,**cost)
        row['output_hashes']={f.name:digest(f)for f in sorted(folder.iterdir())if f.is_file()}
        write(folder/'completion-receipt.json',row);rows[i]=row
        summary.update(request_count=calls,reported_cost_usd=str(total),all_request_costs_known=summary['all_request_costs_known']and cost['cost_known'])
        if not cost['cost_known']or timed_out or row['closed_error'] in ['provider_timedOut','capture_timedOut','cancelled']:summary['status']='stopped_unknown_cost_or_timeout'
        elif total>=Decimal(plan['reported_cost_stop_usd'])or Decimal(cost['reported_cost_usd'])>=Decimal(plan['per_case_reported_cost_stop_usd']):summary['status']='stopped_reported_cost'
        elif calls>plan['maximum_requests']:summary['status']='request_limit_breached'
        write(root/'summary.json',summary);print(c['id']+': '+row['status'],flush=True)
        if summary['status']!='running':break
    if summary['status']=='running':summary['status']='selected_subset_attempted'
    summary['attempted_reviews']=sum(r['status']!='not_attempted'for r in rows)
    summary['review_completed']=sum(r['status']=='completed'for r in rows)
    summary['reviews_with_allowed_confirmation']=sum(bool(r.get('allowed_confirmation_ids'))for r in rows)
    summary['finished_at']=stamp();write(root/'summary.json',summary);return summary

def main():
    p=argparse.ArgumentParser();s=p.add_subparsers(dest='command',required=True)
    f=s.add_parser('freeze');f.add_argument('discovery');f.add_argument('executable');f.add_argument('destination');f.add_argument('--ids',nargs='+',required=True)
    for command in ['verify','run']:
        a=s.add_parser(command);a.add_argument('directory')
        if command=='run':a.add_argument('--live',action='store_true',required=True)
    a=p.parse_args()
    if a.command=='freeze':freeze(a.discovery,a.executable,a.destination,a.ids);print('Explicit original-query subset frozen.')
    elif a.command=='verify':verify(a.directory);print('Frozen runtime verified.')
    else:run(a.directory)
if __name__=='__main__':
    try:main()
    except Exception:raise SystemExit('Smoke stopped; no credentials or arbitrary subprocess output displayed.')
