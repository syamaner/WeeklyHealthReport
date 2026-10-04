#!/usr/bin/env python3
"""Independent synthetic expected values. Native receipts supply identities/times, never expected quantities."""
import argparse
import datetime
import json
from pathlib import Path
import shutil
import zoneinfo

P = 'today.workouts.data.0.enrichment'
SPECS = {
    'v2-paused': (2, '2405', 100, 2),
    'v3-paused': (3, '2500', 100, 2),
    'v3-zero': (3, '2501', 0, 1),
    'v3-incomplete': (3, '2502', None, 1),
    'v3-rich': (3, '2511', 30.625, 2),
}
for index in range(8):
    SPECS[f'v3-safe-{index}'] = (3, str(2503 + index), 10, 1)

def local(text):
    return datetime.datetime.fromisoformat(text.replace('Z', '+00:00')).astimezone(zoneinfo.ZoneInfo('Europe/London')).isoformat(timespec='milliseconds')

def scenario(case, directory, destination, decision):
    version, suffix, aggregate, count = SPECS[case]
    wire = json.loads((directory / (case + '.manifest.json')).read_text())
    receipt = json.loads((directory / (case + '.receipt.json')).read_text())
    summary = '00000000-0000-4000-8000-00000000' + suffix
    assert wire['schemaVersion'] == version and wire['summaryID'] == summary and wire['revision'] == 1
    assert len(wire['intervals']) == count
    incomplete, rich, paused = case == 'v3-incomplete', case == 'v3-rich', case.endswith('paused')
    if version == 3:
        assert receipt['nativeSampleIncluded'] == (decision == 'included')
        assert receipt.get('nativeSampleReason') == (None if decision == 'included' else decision)
    expected = {'schema_version': 7, P + '.enrichment_version': 2, P + '.interchange_schema_version': version,
                P + '.summary_id': summary, P + '.ownership': 'watchPrimary', P + '.manifest_revision': 1,
                P + '.expected_interval_count': count, P + '.recognition': 'supportedIncomplete' if incomplete else 'supportedComplete',
                P + '.started_at': local(wire['workoutStart']),
                P + '.distance_state': 'available' if version == 2 or decision == 'included' else 'noDataOrAccess',
                P + '.distance_provenance': 'fr30zCumulativeDistanceDelta' if version == 2 or decision == 'included' else 'unavailable',
                P + '.accepted_distance.schema_version': 1, P + '.accepted_distance.state': 'unavailable' if incomplete else 'accepted',
                P + '.accepted_distance.metres': aggregate, P + '.accepted_distance.reason': 'notAccepted' if incomplete else None,
                P + '.accepted_distance.provenance': None if incomplete else 'fr30zCumulativeDistanceDelta',
                P + '.accepted_distance.evidence': None if incomplete else 'producerMetadataV3' if version == 3 else 'recoveredLegacyAssociatedSample'}
    if wire.get('workoutEnd'):
        expected[P + '.ended_at'] = local(wire['workoutEnd'])
    if version == 3:
        expected.update({P + '.native_distance_sample.schema_version': 1,
                         P + '.native_distance_sample.state': 'included' if decision == 'included' else 'suppressed',
                         P + '.native_distance_sample.reason': None if decision == 'included' else decision,
                         P + '.distance_metres': aggregate if decision == 'included' else None})
    else:
        expected[P + '.native_distance_sample'] = None
    for index, interval in enumerate(wire['intervals']):
        item = f'{P}.activities.{index}'
        q, d = item + '.pace_prompt', item + '.pace_prompt.interval_distance'
        prescribed = [(3.125, 1.25), (5.125, 3.25)][index] if rich else (3, 0)
        effective = [(3.5, 2.75), (4.875, 3)][index] if rich else (3, 0)
        source = 'manualOverride' if rich else 'planned'
        end = ['targetChanged', 'completed'][index] if rich else 'paused' if paused and index == 0 else 'completed'
        assert interval['prescribed'] == {'speedKilometresPerHour': prescribed[0], 'inclinationPercent': prescribed[1], 'kind': 'interval'}
        assert interval['effectiveSpeed'] == {'kilometresPerHour': effective[0], 'source': source}
        assert interval['effectiveInclination'] == {'percent': effective[1], 'source': source}
        assert interval['settledObservation']['speedKilometresPerHour'] == effective[0] and interval['settledObservation']['inclinationPercent'] == effective[1]
        assert interval['segmentIndex'] == 0 and interval['intervalIndex'] == index and interval['endReason'] == end
        expected.update({item + '.activity': 'walking', item + '.location': 'indoor', item + '.started_at': local(interval['startedAt']), item + '.ended_at': local(interval['endedAt']),
                         q + '.segment_index': 0, q + '.interval_index': index, q + '.prescribed_segment_kind': 'interval',
                         q + '.prescribed_speed_kilometres_per_hour': prescribed[0], q + '.prescribed_inclination_percent': prescribed[1],
                         q + '.effective_target_speed_kilometres_per_hour': effective[0], q + '.effective_target_inclination_percent': effective[1],
                         q + '.observed_speed_kilometres_per_hour': effective[0], q + '.observed_inclination_percent': effective[1],
                         q + '.speed_target_source': source, q + '.inclination_target_source': source,
                         q + '.observation_provenance': 'fr30zTreadmillDataCurrentEpoch', q + '.observed_at': local(interval['settledObservation']['observedAt']),
                         q + '.interval_end_reason': end, d + '.schema_version': 1})
        if rich and index == 1:
            assert interval['intervalDistance']['state'] == 'unavailable' and interval['intervalDistance']['reason'] == 'missingBoundary'
            expected.update({d + '.state': 'unavailable', d + '.reason': 'missingBoundary'})
            for field in ['metres', 'start_cumulative_metres', 'end_cumulative_metres', 'coverage', 'start_observed_at', 'end_observed_at', 'provenance']:
                expected[d + '.' + field] = None
        else:
            values = (100.125, 112.5, 12.375) if rich else [(100, 130, 30), (130, 200, 70)][index] if paused else (100, 100, 0) if case == 'v3-zero' else (100, 110, 10)
            assert [interval['intervalDistance'][key] for key in ['startCumulativeMetres', 'endCumulativeMetres', 'metres']] == list(values)
            expected.update({d + '.state': 'observed', d + '.metres': values[2], d + '.start_cumulative_metres': values[0], d + '.end_cumulative_metres': values[1],
                             d + '.provenance': 'fr30zCumulativeDistanceDelta', d + '.coverage': 'partialObservationWindow' if rich else 'completeInterval',
                             d + '.start_observed_at': local(interval['intervalDistance']['startObservedAt']), d + '.end_observed_at': local(interval['intervalDistance']['endObservedAt'])})
    expected[f'{P}.activities.{count}'] = None
    archive = case + '.archive'
    shutil.copyfile(directory / (case + '.hkworkout'), destination / archive)
    return {'name': 'native-' + case, 'archive': archive, 'nativeWorkoutUUID': receipt['nativeWorkoutUUID'],
            'expectedAssociatedDistanceMetres': aggregate if version == 2 or decision == 'included' else None,
            'expectedJSONPaths': expected}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--producer-output', type=Path, required=True)
    parser.add_argument('--legacy-output', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--decision', action='append', default=[], help='Independently reviewed case=included|pauseOverlap|uncertainTemporalCoverage; never copy the writer decision without checking native bounds/events')
    parser.add_argument('cases', nargs='+', choices=sorted(SPECS))
    args = parser.parse_args()
    if args.output.exists() or len(set(args.cases)) != len(args.cases):
        parser.error('Output must be absent and cases unique')
    decisions = dict(item.split('=', 1) for item in args.decision)
    decisions.update({'v3-paused': 'pauseOverlap', 'v3-zero': 'zeroAggregate', 'v3-incomplete': 'notAccepted'})
    for case in args.cases:
        if case.startswith('v3-safe') or case == 'v3-rich':
            if decisions.get(case) not in ['included', 'pauseOverlap', 'uncertainTemporalCoverage']:
                parser.error('Naturally timed cases require an independently reviewed --decision')
    args.output.mkdir(parents=True, mode=0o700)
    cases = [scenario(case, args.legacy_output if case == 'v2-paused' else args.producer_output, args.output, decisions.get(case)) for case in args.cases]
    (args.output / 'scenarios.json').write_text(json.dumps(cases, indent=2) + '\n')

if __name__ == '__main__':
    main()
