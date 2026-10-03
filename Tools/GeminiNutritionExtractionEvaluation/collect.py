"""Bounded development-only extraction experiment. Never logs credentials/raw envelopes."""
import argparse
import http.client
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from evaluate import ROOT, digest, load, plan, verify

MODEL='gemini-3.8-flash'
LIMIT=1_000_000
MAX_REQUESTS=20

def private_write(path, obj):
    temp=path.with_suffix('.tmp')
    fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    try:
        with os.fdopen(fd,'w') as out:
            json.dump(obj,out,indent=2,ensure_ascii=False,allow_nan=False)
            out.write('\n'); out.flush(); os.fsync(out.fileno())
        os.replace(temp,path)
    finally:
        if temp.exists(): temp.unlink()

def keychain(service):
    result=subprocess.run(['security','find-generic-password','-s',service,'-w'],capture_output=True,text=True)
    if result.returncode: raise ValueError('Keychain item unavailable')
    key=result.stdout.rstrip('\r\n')
    if not 20<=len(key)<=512 or any(not 33<=ord(c)<=126 for c in key):
        raise ValueError('Keychain item not a header-safe credential')
    return key

def request(case,source,arm,prompt,schema):
    if case['split']!='development' or arm not in ('panel','url'):
        raise ValueError('development cases only')
    if arm=='url' and not source['url']: raise ValueError('no URL for synthetic case')
    payload=dict(mode=arm,food=case['food'],preparation=case['preparation'],
                 requested_nutrients=case['requested'],selected_url=source['url'],consumed=case.get('consumed'))
    if arm=='panel': payload['evidence_panel']=source['panel']
    return dict(model=MODEL,input=json.dumps(payload,ensure_ascii=False),system_instruction=prompt,
                tools=[{'type':'url_context'}] if arm=='url' else [],store=False,
                generation_config=dict(max_output_tokens=4096,thinking_level='low'),
                response_format=dict(type='text',mime_type='application/json',schema=schema))

def fetch(body,key):
    conn=http.client.HTTPSConnection('generativelanguage.googleapis.com',timeout=55)
    try:
        conn.request('POST','/v1beta/interactions',body=json.dumps(body).encode(),
                     headers={'x-goog-api-key':key,'Content-Type':'application/json'})
        response=conn.getresponse()
        return response.status,response.read(LIMIT+1)
    finally: conn.close()

def project(reply):
    if type(reply) is not dict or reply.get('status')!='completed': raise ValueError('non_completed')
    texts=[]; citations=[]; retrieval=[]
    def metadata(node):
        if isinstance(node,dict):
            selected={k:v for k,v in node.items() if k in ('url','retrieved_url','status','url_retrieval_status') and type(v) is str}
            if selected: retrieval.append(selected)
            for v in node.values():
                if isinstance(v,(dict,list)): metadata(v)
        elif isinstance(node,list):
            for v in node: metadata(v)
    for step in reply.get('steps',[]):
        if step.get('type')=='url_context_result': metadata(step.get('result',step))
        if step.get('type')!='model_output': continue
        for block in step.get('content',[]):
            if block.get('type')!='text': continue
            texts.append(block['text'])
            for a in block.get('annotations',[]) or []:
                if a.get('type')=='url_citation':
                    citations.append({k:a[k] for k in ('url','start_index','end_index') if k in a})
    if not texts: raise ValueError('no_model_text')
    try: extraction=json.loads(''.join(texts),parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    except (ValueError,TypeError): raise ValueError('invalid_model_json') from None
    usage={k:v for k,v in (reply.get('usage') or {}).items() if type(v) is int and v>=0}
    return dict(extraction=extraction,citations=citations,retrieval=retrieval,usage=usage)

def capture(corpus,contract,out,key,max_requests,transport=fetch):
    tasks=plan(corpus)
    if not 1<=max_requests<=MAX_REQUESTS or len(tasks)>max_requests: raise ValueError('request cap excludes plan')
    prompt=(ROOT/'prompt-v1.txt').read_text(); schema=load(ROOT/'response-schema-v1.json')
    # Construct and validate all requests before creating output or making any POST.
    requests=[request(c,corpus['sources'][c['source']],arm,prompt,schema) for c,arm in tasks]
    out.mkdir(mode=0o700,parents=False,exist_ok=False)
    replay=dict(version='nutrition-extraction-replay-v1',contract=contract,model=MODEL,
                started_at=datetime.now(timezone.utc).isoformat(),
                adapter_sha256=digest(Path(__file__)),scorer_sha256=digest(ROOT/'evaluate.py'),results=[])
    journal=dict(max_requests=max_requests,attempts=[])
    private_write(out/'replay.json',replay); private_write(out/'attempts.json',journal)
    for (case,arm),body in zip(tasks,requests):
        attempt=dict(case_id=case['id'],arm=arm,outcome='started')
        journal['attempts'].append(attempt); private_write(out/'attempts.json',journal)
        try:
            status,raw=transport(body,key)
            attempt['http_status']=status
            if status!=200 or len(raw)>LIMIT or key.encode() in raw:
                raise ValueError('response_rejected')
            reply=json.loads(raw)
            result=project(reply)
        except TimeoutError: attempt['outcome']='timeout'
        except ValueError as error:
            # Only fixed adapter diagnostics; never persist provider error text.
            allowed={'response_rejected','non_completed','no_model_text','invalid_model_json'}
            attempt['outcome']=str(error) if str(error) in allowed else 'invalid_response'
        except Exception: attempt['outcome']='transport_or_projection_error'
        else:
            replay['results'].append(dict(case_id=case['id'],arm=arm,**result))
            private_write(out/'replay.json',replay)
            attempt['outcome']='completed'
        private_write(out/'attempts.json',journal)
        print(json.dumps(attempt),flush=True)
        if attempt['outcome']!='completed': break
    return journal

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--keychain-service',required=True)
    parser.add_argument('--max-requests',type=int,required=True)
    parser.add_argument('--output-dir',type=Path,required=True)
    args=parser.parse_args()
    corpus,contract=verify()
    if args.output_dir.exists() or not len(plan(corpus))<=args.max_requests<=MAX_REQUESTS:
        parser.error('requires new output directory and cap covering full development plan')
    capture(corpus,contract,args.output_dir,keychain(args.keychain_service),args.max_requests)
