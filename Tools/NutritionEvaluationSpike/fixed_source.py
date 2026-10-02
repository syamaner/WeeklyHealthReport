"""Evaluation-only fixed-table adapter and pure scorer; no app admission or inference."""
from decimal import Decimal, InvalidOperation
from html.parser import HTMLParser
import copy
import hashlib
import json
from pathlib import Path
import re

VERSION = 'fixed-source-nutrients-v1'
LABELS = {'fat': 'fat', 'of which saturates': 'saturates', 'carbohydrate': 'carbohydrate',
          'of which sugars': 'sugars', 'fibre': 'fibre', 'protein': 'protein',
          'salt': 'salt', 'calcium': 'calcium', 'phosphorus': 'phosphorus'}
FIELDS = ['energy_kj', 'energy_kcal', *LABELS.values(), 'sodium']


class Tables(HTMLParser):
    """Small, deliberately restricted adapter. Ambiguous/merged layouts fail closed."""
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tables = []; self.table = None; self.row = None; self.cell = None; self.ignored = 0

    def handle_starttag(self, tag, attrs):
        if tag in ['script', 'style', 'template', 'noscript']:
            self.ignored += 1
        if self.ignored: return
        if tag == 'table':
            if self.table is not None: raise ValueError('nested_table')
            self.table = []
        elif self.table is not None and tag == 'tr':
            if self.row is not None: raise ValueError('nested_row')
            self.row = []
        elif self.row is not None and tag in ['td', 'th']:
            if self.cell is not None or any(k in ['colspan', 'rowspan'] and v != '1' for k, v in attrs):
                raise ValueError('unsupported_cell')
            self.cell = []
        elif self.cell is not None and tag == 'br': self.cell.append(' ')

    def handle_endtag(self, tag):
        if tag in ['script', 'style', 'template', 'noscript'] and self.ignored:
            self.ignored -= 1; return
        if self.ignored: return
        if tag in ['td', 'th'] and self.cell is not None:
            self.row.append(' '.join(''.join(self.cell).split())); self.cell = None
        elif tag == 'tr' and self.row is not None:
            if self.cell is not None: raise ValueError('unclosed_cell')
            self.table.append(self.row); self.row = None
        elif tag == 'table' and self.table is not None:
            if self.row is not None: raise ValueError('unclosed_row')
            self.tables.append(self.table); self.table = None

    def handle_data(self, text):
        if self.cell is not None and not self.ignored: self.cell.append(text)


def extract(raw, selected_table=None):
    if len(raw) > 2_000_000: raise ValueError('source_too_large')
    parser = Tables(); parser.feed(raw.decode('utf-8')); parser.close()
    if parser.table is not None: raise ValueError('unclosed_table')
    matches = [(i, t) for i, t in enumerate(parser.tables, 1) if t and t[0] and t[0][0].lower() == 'typical values']
    if selected_table is not None:
        if type(selected_table) is not int or selected_table < 1: raise ValueError('invalid_table_selection')
        matches = [(i, t) for i, t in matches if i == selected_table]
    if len(matches) != 1: raise ValueError('ambiguous_or_missing_panel')
    ti, table = matches[0]
    bases = []
    for ci, header in enumerate(table[0][1:], 2):
        m = re.fullmatch(r'Per (\d+(?:\.\d+)?)\s*(g|ml)(?: serving)?', header, re.I)
        if not m: raise ValueError('unsupported_basis')
        basis = {'amount': m[1], 'unit': m[2].lower(), 'header': header, 'table': ti, 'column': ci,
                 'nutrients': {k: {'state': 'unknown', 'value': None, 'unit': None, 'support': None} for k in FIELDS}}
        seen = set()
        for ri, row in enumerate(table[1:], 2):
            if len(row) != len(table[0]): raise ValueError('ragged_panel')
            label, value = row[0].lower(), row[ci-1]
            keys = ['energy_kj', 'energy_kcal'] if label == 'energy kj/kcal' else [LABELS[label]] if label in LABELS else []
            if not keys: raise ValueError('unsupported_nutrient_row')
            if seen.intersection(keys): raise ValueError('duplicate_nutrient')
            seen.update(keys)
            if len(keys) == 2:
                m = re.fullmatch(r'(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)', value)
                if not m: raise ValueError('unsupported_energy')
                values = [(m[1], 'kJ'), (m[2], 'kcal')]
            else:
                m = re.fullmatch(r'(\d+(?:\.\d+)?)(g|mg)(?: \(\d+(?:\.\d+)?% RI\))?', value)
                if not m: raise ValueError('unsupported_numeral')
                values = [(m[1], m[2])]
            for key, (number, unit) in zip(keys, values):
                basis['nutrients'][key] = {'state': 'declared', 'value': number, 'unit': unit,
                    'support': {'table': ti, 'row': ri, 'column': ci, 'label': row[0], 'cell': value}}
        bases.append(basis)
    if len({(b['amount'], b['unit']) for b in bases}) != len(bases): raise ValueError('duplicate_basis')
    return {'schema': VERSION, 'source_sha256': hashlib.sha256(raw).hexdigest(), 'bases': bases, 'scoop_mass_g': None}


def score(reference, proposal):
    """Exact source decimal plus state, unit, basis, source and support; no tolerances."""
    errors = []; correct = 0; numeric_correct = 0
    expected = reference['expected']
    total = sum(len(b['nutrients']) for b in expected['bases'])
    numeric_total = sum(f['state'] == 'declared' for b in expected['bases'] for f in b['nutrients'].values())
    try:
        if set(proposal) != set(expected): errors.append('proposal_schema_keys')
        if proposal['schema'] != VERSION or proposal['source_sha256'] != expected['source_sha256']: errors.append('source_or_schema')
        if proposal.get('scoop_mass_g', 'absent') is not None: errors.append('unsupported_scoop_conversion')
        if len(proposal['bases']) != len(expected['bases']): errors.append('basis_roster')
        for i, ref in enumerate(expected['bases']):
            actual = proposal['bases'][i] if i < len(proposal['bases']) else {}
            if set(actual) != set(ref): errors.append('basis_schema_keys:' + str(i))
            basis_ok = all(actual.get(k) == ref[k] for k in ['amount', 'unit', 'header', 'table', 'column'])
            if not basis_ok: errors.append('basis:' + str(i))
            nutrients = actual.get('nutrients', {})
            if set(nutrients) != set(ref['nutrients']): errors.append('field_roster:' + str(i))
            for key, field in ref['nutrients'].items():
                p = nutrients.get(key, {})
                numeric_ok = False
                if field['state'] == 'declared':
                    try:
                        numeric_ok = not isinstance(p.get('value'), bool) and Decimal(str(p.get('value'))) == Decimal(field['value'])
                    except InvalidOperation: pass
                    numeric_correct += int(numeric_ok)
                else: numeric_ok = p.get('value', 'absent') is None
                field_ok = numeric_ok and set(p) == set(field) and all(p.get(k) == field[k] for k in ['state', 'unit', 'support'])
                supported = field_ok and basis_ok and proposal['source_sha256'] == expected['source_sha256'] and proposal['schema'] == VERSION
                correct += int(supported)
                if not supported: errors.append('field:' + str(i) + ':' + key)
    except (KeyError, TypeError, ValueError): errors.append('malformed_proposal')
    return {'passed': not errors, 'errors': sorted(set(errors)), 'supported_fields': {'correct': correct, 'total': total},
            'numeric_fields': {'correct': numeric_correct, 'total': numeric_total}}


def evaluate(reference, raw):
    if reference.get('schema') != 'fixed-source-reference-v1' or reference['expected']['source_sha256'] != hashlib.sha256(raw).hexdigest():
        raise ValueError('fixed_source_reference_integrity')
    required_faults = {'wrong_basis','missing_field','unknown_as_zero','invented_scoop_mass','wrong_unit','wrong_support_column'}
    if 'planned_scorer_faults' in reference and set(reference['planned_scorer_faults']) != required_faults:
        raise ValueError('fixed_source_fault_roster')
    proposal = extract(raw, reference.get('selected_table'))
    positive = score(reference, proposal)
    # Fault injection tests the scorer only; these are not model observations or app gates.
    variants = {}
    p = copy.deepcopy(proposal); p['bases'][0]['amount'] = '1'; variants['wrong_basis'] = p
    p = copy.deepcopy(proposal); del p['bases'][0]['nutrients']['protein']; variants['missing_field'] = p
    p = copy.deepcopy(proposal); p['bases'][0]['nutrients']['sodium'].update(state='declared', value='0', unit='g'); variants['unknown_as_zero'] = p
    p = copy.deepcopy(proposal); p['scoop_mass_g'] = p['bases'][-1]['amount']; variants['invented_scoop_mass'] = p
    p = copy.deepcopy(proposal); p['bases'][0]['nutrients']['protein']['unit'] = 'mg'; variants['wrong_unit'] = p
    p = copy.deepcopy(proposal); p['bases'][0]['nutrients']['protein']['support']['column'] += 1; variants['wrong_support_column'] = p
    faults = {k: score(reference, v) for k, v in variants.items()}
    return {'schema': VERSION, 'status': 'descriptive_fixed_evidence', 'adapter': 'evaluation_only_restricted_html_table_reader',
            'reference_quality': reference['reference_quality'], 'source_cases': 1, 'model_quality': 'not_run',
            'app_admission': 'not_run', 'metrics': {'supported_fields': positive['supported_fields'], 'numeric_fields': positive['numeric_fields'],
                'whole_source_cases': {'correct': int(positive['passed']), 'total': 1},
                'scorer_faults_detected': {'correct': sum(not f['passed'] for f in faults.values()), 'total': len(faults)}},
            'positive': positive, 'scorer_faults': faults, 'proposal': proposal,
            'passed_exercised_contract': positive['passed'] and all(not f['passed'] for f in faults.values())}


def run_private(root, output):
    config_path = root / 'fixed-source-config-v1.json'
    config_bytes = config_path.read_bytes(); config = json.loads(config_bytes)
    if config.get('schema') != 'fixed-source-config-v1': raise ValueError('fixed_source_config_schema')
    def bound(name):
        path = (root / name).resolve()
        if not path.is_relative_to(root.resolve()) or any((p / '.git').exists() for p in [path, *path.parents]):
            raise ValueError('fixed_source_private_boundary')
        return path
    ref_path = bound(config['reference_path']); source_path = bound(config['source_path'])
    ref_bytes = ref_path.read_bytes(); raw = source_path.read_bytes()
    if hashlib.sha256(ref_bytes).hexdigest() != config['reference_sha256']: raise ValueError('fixed_source_reference_changed')
    report = evaluate(json.loads(ref_bytes), raw)
    if config_path.read_bytes() != config_bytes or ref_path.read_bytes() != ref_bytes or source_path.read_bytes() != raw:
        raise ValueError('fixed_source_inputs_changed')
    report['pins'] = {'config_sha256': hashlib.sha256(config_bytes).hexdigest(), 'reference_sha256': config['reference_sha256'], 'source_sha256': hashlib.sha256(raw).hexdigest()}
    (output / 'fixed-source-report.json').write_text(json.dumps(report, indent=2) + '\n')
    (output / 'fixed-source-reference.json').write_bytes(ref_bytes)
    return report
