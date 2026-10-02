"""Pure synthetic journey scorer and production Swift runner composition."""
import math
import hashlib
import json
from pathlib import Path

SCHEMA = 'synthetic-save-daily-journeys-v1'
HERE = Path(__file__).resolve().parent


def same(observed, expected):
    if type(expected) in [int, float]:
        return type(observed) in [int, float] and math.isfinite(observed) and abs(observed - expected) <= max(1e-9, 1e-9 * abs(expected))
    if isinstance(expected, dict):
        return isinstance(observed, dict) and observed.keys() == expected.keys() and all(same(observed[k], v) for k, v in expected.items())
    if isinstance(expected, list):
        return isinstance(observed, list) and len(observed) == len(expected) and all(same(a, b) for a, b in zip(observed, expected))
    return type(observed) == type(expected) and observed == expected


def score(reference, observations):
    if reference.get('schema') != SCHEMA or not isinstance(observations, list):
        raise ValueError('journey_schema')
    expected = {r['case_id']: r for r in reference['cases']}
    if not expected: raise ValueError('empty_journey_reference')
    actual = {r['case_id']: r for r in observations}
    if len(expected) != len(reference['cases']) or len(actual) != len(observations) or actual.keys() != expected.keys():
        raise ValueError('journey_roster')
    details = []
    for cid, ref in expected.items():
        observation = actual[cid]
        failures = []
        for key, value in ref['expected'].items():
            # Strict JSON types: bool cannot stand in for integer counts or numeric values.
            observed = observation.get(key, 'missing')
            equal = same(observed, value)
            if not equal: failures.append(key)
        details.append({'case_id': cid, 'kind': ref['kind'], 'passed': not failures, 'failures': failures})
    def metric(rows):
        return {'correct': sum(r['passed'] for r in rows), 'total': len(rows)}
    return {'schema': SCHEMA, 'status': 'descriptive_synthetic_production_journeys',
        'reference_quality': 'synthetic_frozen_before_execution', 'independent_acceptance': 'not_run',
        'persistence': 'in_memory', 'entry_boundary': 'populated_confirmation',
        'metrics': {'all_journeys': metric(details), 'saved_outcomes': metric([r for r in details if r['kind'] == 'save']),
                    'blocked_outcomes': metric([r for r in details if r['kind'] == 'block'])},
        'details': details, 'passed_exercised_contract': all(r['passed'] for r in details)}


def run(output, execute):
    reference_path = HERE / 'journey-reference-v3.json'
    reference_bytes = reference_path.read_bytes()
    reference = json.loads(reference_bytes)
    manifest = json.loads((HERE / 'journey-freeze-v3.json').read_text())
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    if sha(reference_path) != manifest['reference_sha256']:
        raise ValueError('journey_reference_hash')
    sources = HERE.parents[1] / 'Packages/FoodLedgerKit/Sources'
    paths = [HERE / 'journey.swift', HERE / 'journey.py', reference_path, HERE / 'journey-freeze-v3.json']
    for module in ['FoodLedgerDomain', 'FoodLedgerApplication', 'FoodLedgerTestSupport']:
        paths.extend(sorted((sources / module).glob('*.swift')))
    before = {str(p): sha(p) for p in paths}
    (output / 'journey-input-pins.json').write_text(json.dumps(before, indent=2) + '\n')
    (output / 'journey-reference.json').write_bytes(reference_bytes)
    build = output / 'journey-build'; build.mkdir(mode=0o700)
    execution = []
    common = ['swiftc', '-module-cache-path', build / 'module-cache']
    def invoke(args):
        result = execute(args, output, output / ('journey-command-' + str(len(execution)) + '.log'))
        execution.append(result)
        if result['exit_code'] != 0: raise ValueError('journey_execution_failure')
    for module in ['FoodLedgerDomain', 'FoodLedgerApplication', 'FoodLedgerTestSupport']:
        dependencies = [] if module == 'FoodLedgerDomain' else ['-I', build, '-L', build, '-lFoodLedgerDomain']
        if module == 'FoodLedgerTestSupport': dependencies += ['-lFoodLedgerApplication']
        invoke(common + ['-emit-library', '-emit-module', '-module-name', module,
            '-emit-module-path', build / (module + '.swiftmodule'), '-o', build / ('lib' + module + '.dylib')]
            + dependencies + sorted((sources / module).glob('*.swift')))
    invoke(common + [HERE / 'journey.swift', '-parse-as-library', '-I', build, '-L', build,
        '-lFoodLedgerDomain', '-lFoodLedgerApplication', '-lFoodLedgerTestSupport',
        '-Xlinker', '-rpath', '-Xlinker', build, '-o', build / 'journey-runner'])
    invoke([build / 'journey-runner', output / 'journey-observations.json'])
    if any(sha(Path(p)) != digest for p, digest in before.items()):
        raise ValueError('journey_inputs_changed')
    report = score(reference, json.loads((output / 'journey-observations.json').read_text()))
    report['input_sha256'] = before
    report['execution'] = execution
    (output / 'journey-report.json').write_text(json.dumps(report, indent=2) + '\n')
    (output / 'journey-reference.json').write_bytes(reference_bytes)
    return report
