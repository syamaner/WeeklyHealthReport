"""Paired frozen Exa breadth requests; evaluation only, no production changes.

The approved private loader is the sole credential consumer. Never inspect its
credential file. Only public queries reach inference and search. No retries.
"""
import argparse
import copy
from decimal import Decimal
import json
from pathlib import Path
import re
import shutil
import sys
import time
from urllib.parse import urlparse

import lead_selection_experiment as base

VERSION = 'discovery-breadth-v1'
EXPECTED_PROVIDER = {'only': ['azure'], 'order': ['azure'], 'allow_fallbacks': False,
                     'require_parameters': True, 'data_collection': 'deny', 'zdr': True}
MAXIMUM_REQUESTS = 12


def checked_request(body, query):
    expected = {'model', 'stream', 'max_completion_tokens', 'messages', 'plugins', 'provider', 'reasoning'}
    if set(body) != expected or body['model'] != base.MODEL or body['stream'] is not False:
        raise ValueError('discovery request shape or model')
    if body['provider'] != EXPECTED_PROVIDER or body['reasoning'] != {'effort': 'none'} or body['max_completion_tokens'] != 1800:
        raise ValueError('discovery request controls')
    if body['plugins'] != [{'id': 'web', 'engine': 'exa', 'max_results': 3}]:
        raise ValueError('baseline plugin drift')
    messages = body['messages']
    if (not isinstance(messages, list) or len(messages) != 2 or
            set(messages[0]) != {'role', 'content'} or messages[0]['role'] != 'system' or
            not isinstance(messages[0]['content'], str) or not messages[0]['content'] or
            messages[1] != {'role': 'user', 'content': query}):
        raise ValueError('discovery message drift')
    return body


def paired_requests(body, query):
    checked_request(body, query)
    a, b = copy.deepcopy(body), copy.deepcopy(body)
    b['plugins'][0]['max_results'] = 5
    return a, b


def decode(raw):
    obj = base.strict_load(raw)
    if obj.get('model') != base.MODEL or obj.get('provider') != base.PROVIDER:
        raise ValueError('response route mismatch')
    choices = obj.get('choices')
    if not isinstance(choices, list) or len(choices) != 1 or choices[0].get('finish_reason') != 'stop':
        raise ValueError('incomplete response')
    message = choices[0]['message']
    if message.get('refusal') is not None or message.get('tool_calls') is not None:
        raise ValueError('unexpected refusal or tool call')
    annotations = message.get('annotations', [])
    if not isinstance(annotations, list):
        raise ValueError('invalid annotations')
    leads = []
    for index, annotation in enumerate(annotations):
        if not isinstance(annotation, dict) or annotation.get('type') != 'url_citation':
            continue
        citation = annotation.get('url_citation')
        if not isinstance(citation, dict):
            raise ValueError('invalid citation')
        url = citation.get('url')
        if not isinstance(url, str):
            raise ValueError('missing citation URL')
        parsed = urlparse(url)
        safe = parsed.scheme.lower() == 'https' and bool(parsed.hostname) and parsed.username is None and parsed.password is None
        leads.append(dict(annotation_index=index, url=url, title=citation.get('title'),
                          excerpt=citation.get('content'), start_index=citation.get('start_index'),
                          end_index=citation.get('end_index'), https_header_safe=bool(safe)))
    # Preserve all native annotations without slicing, URL repair or ranking.
    return dict(native_leads=leads, native_lead_count=len(leads),
                unique_url_count=len({x['url'] for x in leads}),
                unique_safe_https_url_count=len({x['url'] for x in leads if x['https_header_safe']}),
                response_text=message.get('content'), usage=obj.get('usage'))


def freeze(discovery, criteria, destination):
    discovery, criteria, root = [Path(x).resolve() for x in (discovery, criteria, destination)]
    if root.exists():
        raise ValueError('destination exists')
    plan = base.strict_load((discovery/'plan.json').read_bytes())
    if base.digest(discovery/'plan.json') != (discovery/'plan.sha256').read_text().strip():
        raise ValueError('original plan changed')
    review = base.strict_load(criteria.read_bytes())
    if review.get('new_search_results_seen') is not False or len(plan['cases']) != 6:
        raise ValueError('prospective six-query criteria required')
    by_id = {x['id']: x for x in review['cases']}
    if len(by_id) != 6 or set(by_id) != {x['id'] for x in plan['cases']}:
        raise ValueError('query set changed')
    prepared = []; instruction = None
    for case in plan['cases']:
        cid = case['id']; query = case['query']
        if not re.fullmatch('[a-z0-9-]+', cid) or by_id[cid]['query'] != query:
            raise ValueError('identity or query drift')
        request_path = discovery/'results'/cid/'request-1.json'
        body = base.strict_load(request_path.read_bytes())
        pair = paired_requests(body, query)
        if instruction is not None and body['messages'][0]['content'] != instruction:
            raise ValueError('instruction drift between cases')
        instruction = body['messages'][0]['content']
        for count, request in zip([3, 5], pair):
            prepared.append((cid+'-exa'+str(count), cid, query, count, request, base.digest(request_path)))
    root.mkdir(parents=True); snap = root/'snapshot'; snap.mkdir()
    for name in ['discovery_breadth_experiment.py', 'test_discovery_breadth_experiment.py', 'lead_selection_experiment.py']:
        shutil.copy2(Path(__file__).with_name(name), snap/name)
    shutil.copy2(criteria, snap/'eligibility-criteria.json')
    cases = []
    for rid, cid, query, count, body, original_hash in prepared:
        name = 'snapshot/'+rid+'-request.json'; base.write(root/name, body)
        cases.append(dict(id=rid, query_id=cid, query=query, max_results=count, request=name,
                          original_request_sha256=original_hash))
    frozen = dict(version=VERSION, frozen_at=base.stamp(), planned_queries=6,
                  maximum_requests=MAXIMUM_REQUESTS, order='original six-query order; count3 then count5 within each pair',
                  retries=0, model=base.MODEL, response_provider=base.PROVIDER, endpoint=base.API_URL,
                  timeout_seconds=90, minimum_interval_seconds=15, reported_cost_stop_usd='1.50',
                  per_request_reported_cost_stop_usd='0.05', cost_stop_is_not_prepaid_hard_cap=True,
                  runtime=dict(executable=sys.executable, version=sys.version, executable_sha256=base.digest(sys.executable)),
                  private_loader_sha256=base.digest(base.LOADER), original_plan_sha256=base.digest(discovery/'plan.json'),
                  cases=cases, snapshot_hashes={str(p.relative_to(root)):base.digest(p) for p in sorted(snap.iterdir())},
                  limitations=['The unchanged discovery instruction still requests at most three sources; max_results controls retrieval breadth, not guaranteed annotation count.',
                               'Citation order is not independently verified model ranking. Native metadata cannot verify page content or nutrition.',
                               'ZDR/data_collection routing constrains inference providers; it does not establish Exa tool retention.',
                               'One fixed-order paired development observation per query/arm; no statistical or causal superiority claim.'])
    base.write(root/'plan.json', frozen); (root/'plan.sha256').write_text(base.digest(root/'plan.json')+'\n')
    return frozen


def verify(root):
    if base.digest(root/'plan.json') != (root/'plan.sha256').read_text().strip():
        raise ValueError('plan changed')
    p = base.strict_load((root/'plan.json').read_bytes())
    if p['version'] != VERSION or p['maximum_requests'] != 12 or p['retries'] != 0 or len(p['cases']) != 12:
        raise ValueError('run contract')
    if p['runtime'] != dict(executable=sys.executable, version=sys.version, executable_sha256=base.digest(sys.executable)):
        raise ValueError('runtime changed')
    for name, sha in p['snapshot_hashes'].items():
        f = (root/name).resolve()
        if not f.is_relative_to(root/'snapshot') or base.digest(f) != sha:
            raise ValueError('snapshot changed')
    if base.digest(base.LOADER) != p['private_loader_sha256']:
        raise ValueError('loader changed')
    for a, b in zip(p['cases'][::2], p['cases'][1::2]):
        x = base.strict_load((root/a['request']).read_bytes()); y = base.strict_load((root/b['request']).read_bytes())
        if a['query_id'] != b['query_id'] or (a['max_results'], b['max_results']) != (3, 5) or (x, y) != paired_requests(x, a['query']):
            raise ValueError('pair parity changed')
    return p


def run(root, send=base.transport, key_loader=base.load_key, sleeper=time.sleep):
    root = Path(root).resolve(); p = verify(root)
    if base.digest(Path(__file__)) != p['snapshot_hashes']['snapshot/discovery_breadth_experiment.py']:
        raise ValueError('use frozen runner')
    with (root/'started.json').open('x') as f:
        json.dump({'started_at': base.stamp()}, f)
    results = root/'results'; results.mkdir()
    summary = dict(version=VERSION, planned_queries=6, planned_requests=12, request_count=0,
                   reported_cost_usd='0', all_request_costs_known=True, status='running', cases=[])
    key = key_loader(); total = Decimal(0)
    for c in p['cases']:
        if summary['request_count'] >= 12:
            break
        if summary['request_count']:
            sleeper(p['minimum_interval_seconds'])
        folder = results/c['id']; folder.mkdir()
        body = base.strict_load((root/c['request']).read_bytes())
        if key in json.dumps(body, ensure_ascii=False):
            raise ValueError('credential in body')
        base.write(folder/'attempt.json', dict(started_at=base.stamp(), request_sha256=base.digest(root/c['request'])))
        summary['request_count'] += 1
        raw = None; status = None; failure = None
        try:
            status, raw = send(body, key, p['timeout_seconds'])
        except Exception:
            failure = 'transport_failed_cost_unknown'
        row = dict(id=c['id'], query_id=c['query_id'], max_results=c['max_results'], http_status=status,
                   status=failure or 'response_received', reported_cost_usd=None)
        if raw is not None:
            if key.encode() in raw:
                row['status'] = 'credential_echo_not_retained_cost_unknown'
            else:
                (folder/'response.bin').write_bytes(raw)
                row['raw_response_sha256'] = base.digest(folder/'response.bin')
                row['reported_cost_usd'] = base.reported_cost(raw)
                try:
                    if status != 200:
                        raise ValueError('HTTP error')
                    decoded = decode(raw); base.write(folder/'discovery.json', decoded)
                    row.update({k:decoded[k] for k in ['native_lead_count','unique_url_count','unique_safe_https_url_count']})
                    row['status'] = 'completed'
                except Exception:
                    row['status'] = 'invalid_response'
        known = row['reported_cost_usd'] is not None
        if known:
            total += Decimal(row['reported_cost_usd'])
        else:
            summary['all_request_costs_known'] = False
        base.write(folder/'receipt.json', row); summary['cases'].append(row); summary['reported_cost_usd'] = str(total)
        if not known:
            summary['status'] = 'stopped_unknown_cost'
        elif row['status'] != 'completed':
            summary['status'] = 'stopped_invalid_response'
        elif total >= Decimal(p['reported_cost_stop_usd']) or Decimal(row['reported_cost_usd']) >= Decimal(p['per_request_reported_cost_stop_usd']):
            summary['status'] = 'stopped_reported_cost'
        base.write(root/'summary.json', summary); print(c['id']+': '+row['status'], flush=True)
        if summary['status'] != 'running':
            break
    if summary['status'] == 'running':
        summary['status'] = 'twelve_requests_attempted'
    summary['not_attempted'] = 12-summary['request_count']; base.write(root/'summary.json', summary)
    return summary


def main():
    ap = argparse.ArgumentParser(); sub = ap.add_subparsers(dest='command', required=True)
    f = sub.add_parser('freeze'); f.add_argument('discovery'); f.add_argument('criteria'); f.add_argument('destination')
    for command in ['verify', 'run']:
        q = sub.add_parser(command); q.add_argument('directory')
        if command == 'run':
            q.add_argument('--live', action='store_true', required=True)
    a = ap.parse_args()
    if a.command == 'freeze':
        freeze(a.discovery, a.criteria, a.destination); print('Twelve requests frozen.')
    elif a.command == 'verify':
        verify(Path(a.directory).resolve()); print('Frozen plan verified.')
    else:
        run(a.directory)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        raise SystemExit('Experiment stopped; no credentials, headers or exception details displayed.')
