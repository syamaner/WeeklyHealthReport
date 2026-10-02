"""Versioned extraction candidate; v1 reference values and results remain unchanged."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
import re
from pathlib import Path
import collect as base
import evaluate as ev

ROOT=ev.ROOT

def frozen(documents):
    corpus,old=ev.verify()
    contract=ev.load(ROOT/'frozen-contract-v2.json')
    for name,sha in contract['sha256'].items():
        if ev.digest(ROOT/name)!=sha: raise ValueError('changed experiment file: '+name)
    if ev.digest(documents/'manifest.json')!=contract['document_manifest_sha256']:
        raise ValueError('changed document manifest')
    manifest=ev.load(documents/'manifest.json')
    docs={}
    for name,meta in manifest['sources'].items():
        if meta['outcome']!='fetched': continue
        doc=ev.load(documents/(name+'.json'))
        if hashlib.sha256(doc['text'].encode()).hexdigest()!=meta['text_sha256']:
            raise ValueError('changed document text')
        if doc['selected_url']!=corpus['sources'][name]['url'] or doc['retrieved_url']!=meta['retrieved_url']:
            raise ValueError('changed document identity')
        docs[name]=doc
    return corpus,contract,docs

def tasks(corpus):
    return [(c,'document' if arm=='url' else arm) for c,arm in ev.plan(corpus)]

def request(case,source,arm,doc=None):
    if case['split']!='development' or arm not in ('panel','document'):
        raise ValueError('development cases only')
    body=base.request(case,source,'panel',(ROOT/'prompt-v2.txt').read_text(),ev.load(ROOT/'response-schema-v2.json'))
    payload=json.loads(body['input'])
    if arm=='document':
        if not doc or doc['selected_url']!=source['url']: raise ValueError('missing_selected_document')
        payload.pop('evidence_panel');payload.update(mode='document',source_document=doc['text'])
    body['input']=json.dumps(payload,ensure_ascii=False)
    return body

def score(case,arm,extraction,doc,schema):
    result=ev.score(case,extraction,schema)
    if not result['schema_valid']: return result
    for field in extraction['nutrients']:
        line=field['evidence_line']
        if arm=='panel' or field['state']=='unknown':
            if line is not None: result['errors'].append('unexpected_line:'+field['id'])
        elif not doc or type(line) not in (int,float) or not float(line).is_integer() or not 1<=line<=len(doc['text'].splitlines()):
            result['errors'].append('invalid_line:'+field['id'])
        else:
            # Syntactic value attachment only; human/agent page review still checks the field/column.
            text=doc['text'].splitlines()[int(line)-1].split(': ',1)[-1]
            values=[float(x) for x in re.findall(r'(?<![\w.])\d+(?:\.\d+)?',text)]
            if field['value'] not in values: result['errors'].append('line_value_missing:'+field['id'])
    portion=None
    if not result['errors']:
        portion=ev.scale_portion(extraction,case.get('consumed'))
        if portion!=case.get('expected_portion'): result['errors'].append('portion')
    result.update(passed=not result['errors'],portion=portion)
    return result

def report(corpus,replay,docs):
    planned=tasks(corpus);keys={(c['id'],a) for c,a in planned}
    actual={(r['case_id'],r['arm']):r for r in replay['results']}
    if len(actual)!=len(replay['results']) or actual.keys()-keys: raise ValueError('duplicate or unexpected replay')
    schema=ev.load(ROOT/'response-schema-v2.json');details=[]
    for c,arm in planned:
        row=actual.get((c['id'],arm))
        result=score(c,arm,row['extraction'],docs.get(c['source']),schema) if row else None
        details.append(dict(case_id=c['id'],arm=arm,completed=row is not None,score=result))
    return dict(version='nutrition-candidate-v2-report',planned=len(planned),completed=len(actual),
                passed=sum(bool(x['score'] and x['score']['passed']) for x in details),details=details,
                independent_evidence_review_required=True)

def capture(corpus,contract,docs,out,key,max_requests,transport=base.fetch):
    todo=tasks(corpus)
    if max_requests!=20 or len(todo)>max_requests: raise ValueError('expected bounded 20-call plan')
    out.mkdir(mode=0o700,exist_ok=False)
    replay=dict(version='nutrition-extraction-replay-v2',contract=contract,model=base.MODEL,
                started_at=datetime.now(timezone.utc).isoformat(),results=[])
    journal=dict(max_requests=max_requests,attempts=[])
    base.private_write(out/'replay.json',replay);base.private_write(out/'attempts.json',journal)
    for c,arm in todo:
        attempt=dict(case_id=c['id'],arm=arm,outcome='started')
        journal['attempts'].append(attempt);base.private_write(out/'attempts.json',journal)
        if arm=='document' and c['source'] not in docs:
            attempt['outcome']='source_unavailable';base.private_write(out/'attempts.json',journal);continue
        body=request(c,corpus['sources'][c['source']],arm,docs.get(c['source']))
        try:
            status,raw=transport(body,key);attempt['http_status']=status
            if status!=200 or len(raw)>base.LIMIT or key.encode() in raw: raise ValueError()
            projection=base.project(json.loads(raw))
        except TimeoutError: attempt['outcome']='timeout'
        except Exception: attempt['outcome']='response_or_transport_failed'
        else:
            replay['results'].append(dict(case_id=c['id'],arm=arm,**projection))
            base.private_write(out/'replay.json',replay);attempt['outcome']='completed'
        base.private_write(out/'attempts.json',journal);print(json.dumps(attempt),flush=True)
        if attempt['outcome']!='completed': break
    base.private_write(out/'report.json',report(corpus,replay,docs))
    return len(replay['results'])==len(todo)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--documents',type=Path,required=True)
    ap.add_argument('--output-dir',type=Path);ap.add_argument('--keychain-service');ap.add_argument('--max-requests',type=int)
    ap.add_argument('--replay',type=Path);a=ap.parse_args()
    corpus,contract,docs=frozen(a.documents)
    if a.replay:
        replay=ev.load(a.replay)
        if replay['contract']!=contract: raise ValueError('replay contract mismatch')
        print(json.dumps(report(corpus,replay,docs),indent=2))
    else:
        if not a.output_dir or a.output_dir.exists() or a.max_requests!=20 or not a.keychain_service: ap.error('new directory, keychain service and 20-call cap required')
        success=capture(corpus,contract,docs,a.output_dir,base.keychain(a.keychain_service),a.max_requests)
        raise SystemExit(0 if success else 2)
