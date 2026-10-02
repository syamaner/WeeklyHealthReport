"""Evidence-bound evaluation; four one-time holdouts require a selected passing candidate."""
import argparse
from datetime import datetime,timezone
import json
import os
from pathlib import Path
import collect as base
import evaluate as ev
import candidate_v2 as previous
from evidence_binding import Evidence,RequestEnvelope
from resolve_discovery import evaluate_leads

ROOT=ev.ROOT

def frozen(documents):
    corpus,_,docs=previous.frozen(documents)
    contract=ev.load(ROOT/'frozen-contract-v3.json')
    for name,sha in contract['sha256'].items():
        if ev.digest(ROOT/name)!=sha:raise ValueError('changed frozen file: '+name)
    return corpus,contract,docs

def tasks(corpus,split):
    if split=='development':return previous.tasks(corpus)
    if split=='holdout':return [(c,'panel') for c in corpus['cases'] if c['split']=='holdout']
    raise ValueError('unknown split')

def request(case,source,arm,doc=None):
    if arm not in ('panel','document'):raise ValueError('unknown evidence arm')
    content=source['panel'] if arm=='panel' else doc['text']
    if arm=='document' and doc['selected_url']!=source['url']:raise ValueError('source mismatch')
    evidence=Evidence.selected(case['source'],source['url'],content)
    payload=dict(selected_source_id=evidence.source_id,evidence_sha256=evidence.content_sha256,mode=arm,food=case['food'],preparation=case['preparation'],requested_nutrients=case['requested'],selected_url=source['url'],consumed=case.get('consumed'))
    payload['evidence_panel' if arm=='panel' else 'source_document']=content
    body=dict(model=base.MODEL,input=json.dumps(payload,ensure_ascii=False),system_instruction=(ROOT/'prompt-v3.txt').read_text(),tools=[],store=False,
              generation_config=dict(max_output_tokens=4096,thinking_level='low'),response_format=dict(type='text',mime_type='application/json',schema=ev.load(ROOT/'response-schema-v3.json')))
    return RequestEnvelope.create(evidence,body)

def score(case,arm,row,envelope,doc):
    try:
        ev.validate(row['model_extraction'],ev.load(ROOT/'response-schema-v3.json'))
        bound=envelope.bind(row['model_extraction'])
        if row['bound']!=bound:raise ValueError('saved binding mismatch')
    except (ValueError,KeyError,TypeError):return dict(passed=False,errors=['schema_or_binding'])
    return previous.score(case,arm,bound['extraction'],doc,ev.load(ROOT/'response-schema-v2.json'))

def report(corpus,contract,docs,replay):
    if replay['contract']!=contract:raise ValueError('contract mismatch')
    todo=tasks(corpus,replay['split']);keys={(c['id'],a) for c,a in todo}
    rows={(r['case_id'],r['arm']):r for r in replay['results']}
    if len(rows)!=len(replay['results']) or rows.keys()-keys:raise ValueError('unexpected or duplicate cases')
    details=[]
    for c,arm in todo:
        row=rows.get((c['id'],arm));result=None
        if row:
            envelope=request(c,corpus['sources'][c['source']],arm,docs.get(c['source']))
            result=score(c,arm,row,envelope,docs.get(c['source']))
        details.append(dict(case_id=c['id'],arm=arm,completed=row is not None,score=result))
    return dict(version='nutrition-v3-report',split=replay['split'],planned=len(todo),completed=len(rows),
                passed=sum(bool(d['score'] and d['score']['passed']) for d in details),details=details)

def capture(corpus,contract,docs,out,key,split,max_requests,transport=base.fetch):
    todo=tasks(corpus,split)
    if max_requests!=len(todo):raise ValueError('exact request budget required')
    envelopes=[request(c,corpus['sources'][c['source']],arm,docs.get(c['source'])) for c,arm in todo]
    out.mkdir(mode=0o700,exist_ok=False)
    replay=dict(version='nutrition-v3-replay',model=base.MODEL,contract=contract,split=split,started_at=datetime.now(timezone.utc).isoformat(),results=[])
    journal=dict(max_requests=max_requests,attempts=[])
    base.private_write(out/'replay.json',replay);base.private_write(out/'attempts.json',journal)
    for (c,arm),envelope in zip(todo,envelopes):
        attempt=dict(case_id=c['id'],arm=arm,outcome='started');journal['attempts'].append(attempt);base.private_write(out/'attempts.json',journal)
        try:
            status,raw=transport(envelope.body(),key);attempt['http_status']=status
            if status!=200 or len(raw)>base.LIMIT or key.encode() in raw:raise ValueError('rejected response')
            projected=base.project(json.loads(raw));model=projected.pop('extraction')
            try:
                ev.validate(model,ev.load(ROOT/'response-schema-v3.json'));bound=envelope.bind(model)
            except (ValueError,TypeError,KeyError):bound=None
        except TimeoutError:attempt['outcome']='timeout'
        except Exception:attempt['outcome']='response_or_transport_failed'
        else:
            replay['results'].append(dict(case_id=c['id'],arm=arm,model_extraction=model,bound=bound,**projected))
            base.private_write(out/'replay.json',replay);attempt['outcome']='completed'
        base.private_write(out/'attempts.json',journal);print(json.dumps(attempt),flush=True)
        if attempt['outcome']!='completed':break
    result=report(corpus,contract,docs,replay);base.private_write(out/'report.json',result)
    return result

def claim_holdout(selection_path,contract,corpus,docs):
    selection=ev.load(selection_path)
    if selection['contract']!=contract or selection['evidence_review']!='passed':raise ValueError('candidate not selected')
    development=Path(selection['development_replay'])
    if ev.digest(development)!=selection['development_replay_sha256']:raise ValueError('development replay changed')
    replay=ev.load(development)
    result=report(corpus,contract,docs,replay)
    if replay['split']!='development' or result['planned']!=20 or result['passed']!=20 or not all(r['passed'] for r in evaluate_leads()):raise ValueError('development gate not passed')
    # An exclusive marker is created before reading the key or making any holdout POST.
    marker=ROOT/'holdout-claimed-v3.json'
    fd=os.open(marker,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
    with os.fdopen(fd,'w') as file:json.dump(dict(selection_sha256=ev.digest(selection_path),claimed_at=datetime.now(timezone.utc).isoformat()),file)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--documents',type=Path,required=True);ap.add_argument('--split',choices=['development','holdout'],default='development')
    ap.add_argument('--output-dir',type=Path);ap.add_argument('--keychain-service');ap.add_argument('--max-requests',type=int);ap.add_argument('--replay',type=Path);ap.add_argument('--selection',type=Path)
    a=ap.parse_args();corpus,contract,docs=frozen(a.documents)
    if a.replay:print(json.dumps(report(corpus,contract,docs,ev.load(a.replay)),indent=2))
    else:
        if not a.output_dir or a.output_dir.exists() or not a.keychain_service or a.max_requests!=len(tasks(corpus,a.split)):ap.error('new directory, service and exact request cap required')
        if a.split=='holdout':
            if not a.selection:ap.error('selected passing development candidate required')
            claim_holdout(a.selection,contract,corpus,docs)
        result=capture(corpus,contract,docs,a.output_dir,base.keychain(a.keychain_service),a.split,a.max_requests)
        raise SystemExit(0 if result['completed']==result['planned'] else 2)
