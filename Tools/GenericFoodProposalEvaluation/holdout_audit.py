"""Offline overlap preflight against explicitly supplied frozen development runs.

Absence of metadata overlap is not proof of semantic independence or source truth.
All planned development cases count as exposed, including unattempted predictions.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import unicodedata
from urllib.parse import urlsplit, urlunsplit

VERSION = 'food-evaluation-holdout-preflight-v2'


def read_bytes(path):
    path = Path(path).resolve()
    if path.name == '.env' or path.name.startswith('.env.'):
        raise ValueError('credential files are not evaluation inputs')
    return path.read_bytes()


def digest_bytes(value):
    return hashlib.sha256(value).hexdigest()


def normalise(value):
    if not isinstance(value, str) or not value.strip():
        raise ValueError('missing split metadata')
    return ' '.join(unicodedata.normalize('NFKC', value).casefold().split())


def domain(value):
    value = normalise(value).rstrip('.')
    if any(c in value for c in '/:@?# ') or '.' not in value:
        raise ValueError('domain must be a declared source host or reviewed domain group')
    return value.encode('idna').decode('ascii')


def related_domains(left, right):
    return left == right or left.endswith('.' + right) or right.endswith('.' + left)


def fingerprints(case, base, hashes=None):
    raw_hashes = set()
    urls = set()
    source_domains = set()
    if case['task'] == 'provided_document':
        path = (base / case['document']).resolve()
        if hashes is not None:
            if not path.is_relative_to((base / 'snapshot').resolve()):
                raise ValueError('development document escapes snapshot')
            relative = str(path.relative_to(base))
            if relative not in hashes:
                raise ValueError('development document is not frozen')
        data = read_bytes(path)
        if hashes is not None and digest_bytes(data) != hashes[relative]:
            raise ValueError('development document changed')
        documents = json.loads(data)
        if isinstance(documents, dict):
            documents = [documents]
        if not isinstance(documents, list) or not documents:
            raise ValueError('missing source documents')
        for document in documents:
            raw = document.get('raw_sha256')
            if not isinstance(raw, str) or not re.fullmatch('[0-9a-f]{64}', raw):
                raise ValueError('invalid source hash')
            raw_hashes.add(raw)
            source = document.get('url')
            if source:
                parts = urlsplit(source)
                if parts.scheme != 'https' or not parts.hostname or parts.username or parts.password:
                    raise ValueError('invalid source URL')
                urls.add(urlunsplit((parts.scheme, parts.netloc.lower(), parts.path, parts.query, '')))
                source_domains.add(domain(parts.hostname))
    # Historical discovery plans precede source selection and explicitly lack a host.
    # Keep their query/family exposure without inventing a domain or dropping the case.
    unknown_domain = (case['task'] == 'discovery' and case['domain'] in
                      {'unobserved', 'not_known_before_discovery'})
    domains = source_domains | (set() if unknown_domain else {domain(case['domain'])})
    if 'domain_group' in case:
        domains.add(domain(case['domain_group']))
    return dict(id=case['id'], comparison_case=case.get('comparison_case', case['id']),
                family=normalise(case['family']), domains=sorted(domains),
                source_domain_unknown=unknown_domain,
                query=normalise(case['query']), raw_sha256=sorted(raw_hashes), source_urls=sorted(urls))


def audit(roster_path, development_runs):
    # Import lazily so the freeze entry point can use this preflight without a cycle.
    from frozen_run import validate_cases
    roster_path = Path(roster_path).resolve()
    data = read_bytes(roster_path)
    roster = json.loads(data)
    validate_cases(roster['cases'])
    roots = [Path(p).resolve() for p in development_runs]
    if not roots or len(set(roots)) != len(roots):
        raise ValueError('explicit distinct development runs required')
    candidates = [fingerprints(case, roster_path.parent) for case in roster['cases']]
    development = []
    plans = []
    for root in roots:
        plan_data = read_bytes(root / 'plan.json')
        plan_hash = digest_bytes(plan_data)
        if plan_hash != read_bytes(root / 'plan.sha256').decode().strip():
            raise ValueError('development plan changed')
        plan = json.loads(plan_data)
        if plan.get('version') != 'swift-frozen-evaluation-v1':
            raise ValueError('unsupported development plan')
        validate_cases(plan['cases'])
        plans.append(dict(path=str(root), sha256=plan_hash, planned_cases=len(plan['cases'])))
        for case in plan['cases']:
            value = fingerprints(case, root, plan['snapshot_hashes'])
            value['plan_sha256'] = plan_hash
            development.append(value)
    overlaps = []
    for candidate in candidates:
        matches = []
        for exposed in development:
            reasons = []
            if candidate['comparison_case'] == exposed['comparison_case']:
                reasons.append('comparison_case')
            if candidate['family'] == exposed['family']:
                reasons.append('declared_food_family')
            if any(related_domains(a, b) for a in candidate['domains'] for b in exposed['domains']):
                reasons.append('declared_source_domain')
            if candidate['query'] == exposed['query']:
                reasons.append('normalised_query')
            if set(candidate['raw_sha256']) & set(exposed['raw_sha256']):
                reasons.append('raw_source_bytes')
            if set(candidate['source_urls']) & set(exposed['source_urls']):
                reasons.append('source_url')
            if reasons:
                matches.append(dict(development_case=exposed['id'], plan_sha256=exposed['plan_sha256'], reasons=reasons))
        if matches:
            overlaps.append(dict(candidate_case=candidate['id'], matches=matches))
    return dict(version=VERSION, candidate_roster_sha256=digest_bytes(data),
                candidate_cases=candidates, development_plans=plans, development_cases=development,
                development_cases_without_source_domain=sum(c['source_domain_unknown'] for c in development),
                overlapping_candidate_count=len(overlaps), overlaps=overlaps,
                eligible_for_prospective_run=not overlaps,
                independent_acceptance=False, confidence_calibrated=False,
                qualification='Mechanical overlap check against the explicitly supplied plans only. All planned cases count as exposed. Declared family/domain groups need source review; semantic aliases, shared brands across country domains and unseen development history can still overlap. No prediction quality or source truth is certified.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('roster')
    parser.add_argument('output')
    parser.add_argument('--development-run', action='append', required=True)
    args = parser.parse_args()
    output = Path(args.output)
    if output.exists():
        raise ValueError('audit output already exists')
    result = audit(args.roster, args.development_run)
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: result[k] for k in ['overlapping_candidate_count', 'eligible_for_prospective_run', 'independent_acceptance']}))


if __name__ == '__main__':
    main()
