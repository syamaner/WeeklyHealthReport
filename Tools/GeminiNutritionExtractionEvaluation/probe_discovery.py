"""Two bounded descriptive-food search probes, separate from extraction scores."""
import argparse
from pathlib import Path
import json
from datetime import datetime,timezone
import collect as base
import evaluate as ev

PROMPT='''Find at most two primary published sources with declared nutrition for the displayed food. A generic recipe or composition record is only a representative candidate, not the user's actual food. Explain the recipe, cooking and lean/fat assumptions and the declared denominator, and whether the displayed amount can be supported without guessing density or cooking yield. Do not invent nutrition, mix sources, use a raw record for cooked weight, or treat consumed weight as pack size. Link the exact source record/page with provider citations. Do not save or select for the user. If no source supports the query, say so. Keep the answer concise.'''
QUERIES=['lentil and tomato soup','250g cooked weight sirloin']

def project(reply):
    if reply.get('status')!='completed':raise ValueError('incomplete')
    blocks=[]
    for step in reply.get('steps',[]):
        if step.get('type')!='model_output':continue
        for b in step.get('content',[]):
            if b.get('type')!='text':continue
            blocks.append(dict(text=b['text'],citations=[{k:a[k] for k in ('url','title','start_index','end_index') if k in a} for a in b.get('annotations',[]) or [] if a.get('type')=='url_citation']))
    if not blocks:raise ValueError('missing text')
    return dict(blocks=blocks,usage={k:v for k,v in (reply.get('usage') or {}).items() if type(v)is int and v>=0})

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--output-dir',type=Path,required=True);ap.add_argument('--keychain-service',required=True);a=ap.parse_args()
    if a.output_dir.exists():ap.error('new private directory required')
    a.output_dir.mkdir(mode=0o700)
    journal=dict(max_requests=2,attempts=[]);replay=dict(model=base.MODEL,adapter_sha256=ev.digest(Path(__file__)),prompt=PROMPT,started_at=datetime.now(timezone.utc).isoformat(),results=[])
    base.private_write(a.output_dir/'replay.json',replay)
    key=base.keychain(a.keychain_service)
    for query in QUERIES:
        attempt=dict(query=query,outcome='started');journal['attempts'].append(attempt);base.private_write(a.output_dir/'attempts.json',journal)
        body=dict(model=base.MODEL,input=query,system_instruction=PROMPT,tools=[dict(type='google_search')],store=False,generation_config=dict(max_output_tokens=2048,thinking_level='low'))
        try:
            status,raw=base.fetch(body,key);attempt['http_status']=status
            if status!=200 or len(raw)>base.LIMIT or key.encode() in raw:raise ValueError('rejected')
            projection=project(json.loads(raw))
        except Exception:attempt['outcome']='failed_no_retry'
        else:
            replay['results'].append(dict(query=query,**projection));base.private_write(a.output_dir/'replay.json',replay);attempt['outcome']='completed'
        base.private_write(a.output_dir/'attempts.json',journal);print(json.dumps(attempt),flush=True)
        if attempt['outcome']!='completed':raise SystemExit(2)
