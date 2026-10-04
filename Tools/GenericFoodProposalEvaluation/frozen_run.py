"""Freeze and run bounded development evaluations through the actual Swift adapter.

Credentials are consumed only by the pre-existing private loader. No environment
file is enumerated, opened, copied, hashed or printed by this module.
"""
import argparse
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PRIVATE_ROOT = Path('/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1')
LOADER = PRIVATE_ROOT / 'evaluation-v4/run_private_env.py'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


GOLD_VALIDATION_VERSION = 'source-review-gold-v2'


def decimal_value(value, *, positive=False):
    if isinstance(value, bool) or not isinstance(value, (str, int, float, Decimal)):
        raise ValueError('invalid reference number')
    try:
        number = Decimal(str(value))
    except InvalidOperation as error:
        raise ValueError('invalid reference number') from error
    if not number.is_finite() or number < 0 or (positive and number == 0):
        raise ValueError('invalid reference number')
    return number


def nonempty_distinct_strings(values):
    return (isinstance(values, list) and bool(values)
            and all(isinstance(value, str) and bool(value.strip()) for value in values)
            and len(set(values)) == len(values))


def validate_gold(gold):
    if not isinstance(gold, dict):
        raise ValueError('invalid gold')
    if gold.get('outcome') == 'selected':
        nutrients = gold.get('nutrients')
        if (not isinstance(nutrients, dict)
                or set(nutrients) != {'energy', 'protein', 'carbohydrate', 'fat', 'fibre', 'sodium'}
                or not nonempty_distinct_strings(gold.get('allowed_names'))):
            raise ValueError('incomplete gold')
        for value in nutrients.values():
            if value is not None:
                decimal_value(value)
        if 'allowed_document_ids' in gold and not nonempty_distinct_strings(gold['allowed_document_ids']):
            raise ValueError('invalid source document identities')
        equivalents = gold.get('allowed_equivalent_bases', [])
        if not isinstance(equivalents, list):
            raise ValueError('invalid equivalent bases')
        for basis in [gold.get('basis')] + equivalents:
            if not isinstance(basis, dict) or basis.get('unit') not in ['g', 'ml', 'serving']:
                raise ValueError('invalid basis')
            decimal_value(basis.get('amount'), positive=True)
    elif (gold.get('outcome') != 'abstain'
          or not nonempty_distinct_strings(gold.get('allowed_choices'))
          or not set(gold['allowed_choices']) <= {'none', 'clarify'}):
        raise ValueError('invalid expected outcome')


def validate_cases(cases):
    if not cases or len(cases) > 40 or len({c['id'] for c in cases}) != len(cases):
        raise ValueError('invalid roster')
    for case in cases:
        if not case['id'] or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in case['id']):
            raise ValueError('invalid identifier')
        if case['task'] not in ['provided_document', 'discovery']:
            raise ValueError('invalid task')
        for key in ['query', 'family', 'layout', 'domain', 'slice', 'reference_status']:
            if not isinstance(case[key], str) or not case[key]:
                raise ValueError('missing case metadata')
        if not 1 <= len(case['query']) <= 300:
            raise ValueError('query size')
        if case['task'] == 'provided_document':
            if case.get('extractor', 'luna') not in ['luna', 'sol', 'qwen', 'grok', 'opus']:
                raise ValueError('invalid extractor')
            if not isinstance(case.get('selection', True), bool):
                raise ValueError('invalid selection setting')
            if case.get('selector', 'jev') not in ['jev', 'applicability']:
                raise ValueError('invalid selector')
            if case.get('selection', True) and case.get('selector', 'jev') == 'jev' and case.get('extractor', 'luna') != 'luna':
                raise ValueError('paired selector comparison uses baseline route')
            validate_gold(case.get('gold'))


def freeze(roster_path, executable, destination, holdout_against=None):
    roster_path, executable, root = map(lambda p: Path(p).resolve(), [roster_path, executable, destination])
    roster = json.loads(roster_path.read_text())
    validate_cases(roster['cases'])
    holdout = None
    if holdout_against is not None:
        from holdout_audit import audit
        holdout = audit(roster_path, holdout_against)
        if not holdout['eligible_for_prospective_run']:
            raise ValueError('prospective holdout overlaps supplied development runs')
    interval = roster.get('minimum_interval_seconds', 0)
    if isinstance(interval, bool) or not isinstance(interval, (int, float)) or not 0 <= interval <= 60:
        raise ValueError('invalid request interval')
    if root.exists():
        raise ValueError('run already exists')
    bundle = executable.parent / 'FoodLedgerKit_FoodGenericSearch.bundle'
    if not executable.is_file() or not bundle.is_dir():
        raise ValueError('runtime or resource bundle missing')
    for case in roster['cases']:
        if case['task'] != 'provided_document':
            continue
        inputs = [case['document'], *case.get('evidence_files', [])]
        if case.get('raw_source'):
            inputs.append(case['raw_source'])
        for name in inputs:
            path = (roster_path.parent / name).resolve()
            if path.name == '.env' or path.name.startswith('.env.'):
                raise ValueError('credential files are not evaluation inputs')
            if not path.is_file():
                raise ValueError('evaluation input missing')
    root.mkdir(parents=True)
    snapshot = root / 'snapshot'
    (snapshot / 'runtime').mkdir(parents=True)
    if holdout is not None:
        write(snapshot / 'holdout-audit.json', holdout)
    shutil.copy2(executable, snapshot / 'runtime/FoodProposalProbe')
    shutil.copytree(bundle, snapshot / 'runtime' / bundle.name)
    package = REPO / 'Packages/FoodLedgerKit'
    source_files = sorted((package / 'Sources').rglob('*.swift')) + sorted((package / 'Tools').rglob('*.swift'))
    source_files += [package / 'Package.swift', package / 'Package.resolved']
    source_files += sorted((package / 'Sources/FoodGenericSearch/Resources/OpenRouter').glob('*'))
    source_files += sorted(HERE.glob('*.py'))
    for source in source_files:
        if source.is_file():
            target = snapshot / 'source' / source.relative_to(REPO)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    cases = []
    for original in roster['cases']:
        case = dict(original)
        if case['task'] == 'provided_document':
            source = (roster_path.parent / case['document']).resolve()
            target = snapshot / 'documents' / (case['id'] + '.json')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            case['document'] = str(target.relative_to(root))
            if case.get('raw_source'):
                raw = (roster_path.parent / case['raw_source']).resolve()
                raw_target = snapshot / 'raw' / (case['id'] + raw.suffix)
                raw_target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(raw, raw_target)
                case['raw_source'] = str(raw_target.relative_to(root))
            evidence = []
            for index, name in enumerate(case.get('evidence_files', [])):
                original_evidence = (roster_path.parent / name).resolve()
                evidence_target = snapshot / 'evidence' / case['id'] / (str(index) + '-' + original_evidence.name)
                evidence_target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(original_evidence, evidence_target)
                evidence.append(str(evidence_target.relative_to(root)))
            if evidence:
                case['evidence_files'] = evidence
        cases.append(case)
    plan = dict(version='swift-frozen-evaluation-v1', status='development_not_independent_acceptance',
                gold_validation_version=GOLD_VALIDATION_VERSION,
                holdout_audit='snapshot/holdout-audit.json' if holdout is not None else None,
                frozen_at=datetime.now(timezone.utc).isoformat(), cases=cases,
                minimum_interval_seconds=interval,
                output_hashes_required=True,
                roster_metadata={k: v for k, v in roster.items() if k != 'cases'},
                executable='snapshot/runtime/FoodProposalProbe',
                maximum_requests=sum(1 if c['task'] == 'discovery' or not c.get('selection', True) else 2 for c in cases),
                reported_cost_stop_usd='1.50', per_case_reported_cost_stop_usd='0.05',
                cost_stop_is_not_prepaid_hard_cap=True, automatic_retries=0,
                private_loader_sha256=digest(LOADER),
                snapshot_hashes={str(p.relative_to(root)): digest(p) for p in sorted(snapshot.rglob('*')) if p.is_file()})
    write(root / 'plan.json', plan)
    (root / 'plan.sha256').write_text(digest(root / 'plan.json') + '\n')
    print(f'Frozen {len(cases)} development cases with executable, resource bundle, sources and gold.')


def verify(root):
    if digest(root / 'plan.json') != (root / 'plan.sha256').read_text().strip():
        raise ValueError('plan changed')
    plan = json.loads((root / 'plan.json').read_text())
    if plan['version'] != 'swift-frozen-evaluation-v1' or plan['status'] != 'development_not_independent_acceptance':
        raise ValueError('wrong plan')
    validate_cases(plan['cases'])
    for name, expected in plan['snapshot_hashes'].items():
        path = (root / name).resolve()
        if not path.is_relative_to(root / 'snapshot') or digest(path) != expected:
            raise ValueError('snapshot changed')
    if digest(LOADER) != plan['private_loader_sha256']:
        raise ValueError('private loader changed')
    return plan


def cost_state(root):
    requests = []
    unverified_attempts = []
    for folder in sorted((root / 'results').iterdir()):
        if not folder.is_dir():
            continue
        status_path = folder / 'run-status.json'
        receipt = folder / 'receipt.json'
        if status_path.exists():
            status = json.loads(status_path.read_text())
            verify_output_hashes(folder, status)
        else:
            unverified_attempts.append(folder.name)
        if receipt.exists():
            rows = json.loads(receipt.read_text())['requests']
            if not rows and folder.name not in unverified_attempts:
                unverified_attempts.append(folder.name)
            requests.extend(rows)
        elif folder.name not in unverified_attempts:
            unverified_attempts.append(folder.name)
    known = []
    for row in requests:
        value = row.get('reported_cost_usd')
        if value is None:
            continue
        if isinstance(value, bool):
            raise ValueError('invalid reported cost')
        value = Decimal(str(value))
        if not value.is_finite() or value < 0:
            raise ValueError('invalid reported cost')
        known.append(value)
    return dict(request_count=len(requests), known_cost_requests=len(known),
                unknown_cost_requests=len(requests) - len(known),
                known_reported_cost_usd=str(sum(known, Decimal(0))),
                unverified_cost_attempts=unverified_attempts,
                all_request_costs_known=not unverified_attempts and len(known) == len(requests))


def totals(root):
    state = cost_state(root)
    return state['request_count'], Decimal(state['known_reported_cost_usd']), state['all_request_costs_known']


def output_hashes(directory):
    allowed = re.compile(r'(?:extraction|result|discovery|receipt|request-[0-9]+|response-[0-9]+)\.json')
    return {p.name: digest(p) for p in sorted(directory.iterdir()) if p.is_file() and allowed.fullmatch(p.name)}


def verify_output_hashes(directory, status):
    if status.get('output_hashes') != output_hashes(directory):
        raise ValueError('run outputs changed after receipt')


def run(directory):
    root = Path(directory).resolve()
    plan = verify(root)
    if digest(Path(__file__)) != plan['snapshot_hashes']['snapshot/source/Tools/GenericFoodProposalEvaluation/frozen_run.py']:
        raise ValueError('use the frozen runner')
    results = root / 'results'
    results.mkdir(exist_ok=True)
    # Only this established loader consumes the private environment file.
    sys.path.insert(0, str(LOADER.parent))
    from run_private_env import load_credentials
    load_credentials(PRIVATE_ROOT / 'evaluation-v2')
    summary = dict(started_at=datetime.now(timezone.utc).isoformat(), cases=[], status='running')
    previous_started = None
    for case in plan['cases']:
        count, cost, covered = totals(root)
        if not covered or count >= plan['maximum_requests'] or cost >= Decimal(plan['reported_cost_stop_usd']):
            summary['status'] = 'stopped_budget_or_unknown_cost'
            break
        output = results / case['id']
        if output.exists():
            # A continuation never retries a case, including a failed one.
            summary['cases'].append(dict(id=case['id'], status='already_attempted'))
            continue
        args = [str(root / plan['executable'])]
        if case['task'] == 'discovery':
            args += ['discover', case['query'], str(output)]
        elif not case.get('selection', True):
            args += ['extract-only', case.get('extractor', 'luna'), str(root / case['document']), case['query'], str(output)]
        elif case.get('selector') == 'applicability':
            args += ['extract-and-check', case.get('extractor', 'luna'), str(root / case['document']), case['query'], str(output)]
        else:
            args += ['extract-and-select', str(root / case['document']), case['query'], str(output)]
        if previous_started is not None:
            time.sleep(max(0, plan.get('minimum_interval_seconds', 0) - (time.monotonic() - previous_started)))
        previous_started = time.monotonic()
        try:
            child = subprocess.run(args, capture_output=True, timeout=210, env=os.environ.copy(), check=False)
            status = 'completed' if child.returncode == 0 else 'failed'
        except subprocess.TimeoutExpired:
            status = 'timed_out'
        output.mkdir(exist_ok=True)
        write(output / 'run-status.json', dict(status=status, finished_at=datetime.now(timezone.utc).isoformat(),
                                             output_hashes=output_hashes(output)))
        summary['cases'].append(dict(id=case['id'], status=status))
        write(root / 'run-summary.json', summary)
        # Fixed identifiers/outcomes only; never arbitrary subprocess output.
        print(case['id'] + ': ' + status, flush=True)
        if status == 'timed_out':
            summary['status'] = 'stopped_timeout_cost_may_be_unknown'
            break
    else:
        summary['status'] = 'roster_attempted'
    count, cost, covered = totals(root)
    summary.update(cost_state(root), reported_cost_usd=str(cost))
    write(root / 'run-summary.json', summary)


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest='command', required=True)
    create = commands.add_parser('freeze')
    create.add_argument('roster'); create.add_argument('executable'); create.add_argument('destination')
    create.add_argument('--holdout-against', action='append', help='Frozen development run; repeat for every exposed run')
    for action in ['run', 'verify']:
        commands.add_parser(action).add_argument('directory')
    args = parser.parse_args()
    if args.command == 'freeze':
        freeze(args.roster, args.executable, args.destination, args.holdout_against)
    elif args.command == 'verify':
        verify(Path(args.directory).resolve()); print('Frozen inputs verified.')
    else:
        run(args.directory)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        raise SystemExit('Evaluation stopped; no configuration or exception contents displayed.')
