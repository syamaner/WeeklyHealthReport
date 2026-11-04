#!/usr/bin/env python3
"""Project the Ciqual 2025 chocolate subgroup from pinned local XML files. No network or private inputs.

Implements ciqual-group-scope-v1 and ciqual-projection-v1 (docs/ciqual-2025-admission-v1.md).
The XML files are untrusted data: they are parsed with expat directly, and any DTD, entity
declaration or external entity reference is refused.
"""
import argparse
from decimal import Decimal
import hashlib
import importlib.util
import json
from pathlib import Path
import re
from xml.parsers import expat

SCHEMA = 'ciqual-generic-v1'
PROJECTION = 'ciqual-projection-v1'
GROUP_SCOPE = 'ciqual-group-scope-v1'
SUBGROUPS = ('0702',)
SOURCE_ID = 'ciqual'
DOI = '10.57745/RDMHWY'
DATASET_VERSION = '1.0'
RELEASE_TIME = '2025-11-19T16:29:04Z'
RELEASED_AT = '2025-11-19T00:00:00Z'
LICENCE = 'Etalab Open Licence 2.0 · https://www.etalab.gouv.fr/licence-ouverte-open-licence/'
ATTRIBUTION = ('Anses. 2025. Table de composition nutritionnelle des aliments Ciqual 2025. '
               'https://doi.org/10.57745/RDMHWY. Reviewed projection of the chocolate group; '
               'English names as published by Anses; no Anses endorsement.')
VARIANT = 'Ciqual · French composition estimate · per 100 g'

# (file ID, name, bytes, MD5, SHA-256), sorted by file ID (spec 1.1).
FILES = (
    (666246, 'const_2025_11_03.xml', 17955, 'd8f2f25fdacb887bc993a6eeaf80f203',
     '3a231ea3e9836e4ac0b6ff94511e010210b2523d1b8b486c6b29e211066ba3f3'),
    (666248, 'sources_2025_11_03.xml', 871783, '5469598d6b4811672b65e1644dfc6485',
     '73e6a0c573f88c23f23b4670a016c616edea806b3d92340942cdbdb9b4323137'),
    (666249, 'compo_2025_11_03.xml', 69243149, '2da725585946434df320d8041631998b',
     '8c46a9032ece4eab4ffccc9dfcb0c490ec2f416aa664cc1ee013b241c6bdd4af'),
    (666250, 'alim_grp_2025_11_03.xml', 80421, 'c31aeea90349c3aab86f98ef5f4f10da',
     'e216928be1001aed15ba1b120405b70a98145da2a1a76026d6e33542bd5e39dc'),
    (666252, 'alim_2025_11_03.xml', 1581031, '8e1171d63cee4b6010cfce25dd29243d',
     'e0b1de25b3039028205e9d54a96892e403e1b313c2efeb41180fabe132627478'),
)

# NutrientKey -> (Ciqual constituent code, catalogue unit), or None when Ciqual has no constituent.
# Exactly one constituent per key; never summed or substituted (spec 3.1).
MAPPING = {
    'energy_consumed': ('328', 'kcal'), 'carbohydrates': ('31000', 'g'), 'protein': ('25000', 'g'),
    'fat_total': ('40000', 'g'), 'fat_saturated': ('40302', 'g'), 'fat_monounsaturated': ('40303', 'g'),
    'fat_polyunsaturated': ('40304', 'g'), 'fiber': ('34100', 'g'), 'sugar': ('32000', 'g'),
    'cholesterol': ('75100', 'mg'), 'vitamin_a': ('51104', 'mcg'), 'thiamin_b1': ('56100', 'mg'),
    'riboflavin_b2': ('56200', 'mg'), 'niacin_b3': ('56310', 'mg'), 'pantothenic_acid_b5': ('56400', 'mg'),
    'vitamin_b6': ('56500', 'mg'), 'biotin_b7': None, 'folate_b9': ('56700', 'mcg'),
    'vitamin_b12': ('56600', 'mcg'), 'vitamin_c': ('55100', 'mg'), 'vitamin_d': ('52100', 'mcg'),
    'vitamin_e': ('71010', 'mg'), 'vitamin_k': ('54101', 'mcg'), 'calcium': ('10200', 'mg'),
    'chloride': ('10170', 'mg'), 'iron': ('10260', 'mg'), 'magnesium': ('10120', 'mg'),
    'phosphorus': ('10150', 'mg'), 'potassium': ('10190', 'mg'), 'sodium': ('10110', 'mg'),
    'zinc': ('10300', 'mg'), 'chromium': None, 'copper': ('10290', 'mg'), 'iodine': ('10530', 'mcg'),
    'manganese': ('10251', 'mg'), 'molybdenum': None, 'selenium': ('10340', 'mcg'),
    'water': ('400', 'g'), 'caffeine': None,
}
# Keys read for details but never projected as a value, with their unknown reason.
# water: no density conversion from g to the catalogue's mL (as CoFID water).
# vitamin_a: decision A3; 51104 uses the IOM 2001 convention (beta-carotene / 12, retinol
# activity equivalents), not the retinol-equivalent convention CoFID fills this key with.
UNPROJECTED = {'water': 'missing_conversion', 'vitamin_a': 'no_compatible_source'}
# The French unit in each mapped constituent's name must match the catalogue unit
# (the English label of 51104 is misprinted "µg/100mg").
FRENCH_UNIT = {'g': '(g/100 g)', 'mg': '(mg/100 g)', 'mcg': '(µg/100 g)', 'kcal': '(kcal/100 g)'}

# "< 0" rows outside the admitted scope, pinned on 4 November 2026 (spec 3.2, amended in C1).
# Each is a (alim_code, const_code) pair. Any other "< n" with n <= 0, or any of these inside the
# admitted scope, fails the build, and so does a pinned pair that is no longer present.
PINNED_NONPOSITIVE_BOUNDS = frozenset([
    ('13211', '32410'), ('13996', '51200'), ('13996', '52300'), ('17001', '32210'), ('17001', '32250'),
    ('17001', '32410'), ('17001', '32430'), ('17001', '32480'), ('18029', '52200'), ('18044', '10530'),
    ('18045', '10530'), ('18046', '10530'), ('18048', '40303'), ('18048', '40304'), ('18048', '40400'),
    ('18048', '40600'), ('18048', '40800'), ('18048', '41000'), ('18048', '41200'), ('18048', '41400'),
    ('18048', '41600'), ('18048', '41800'), ('18048', '42053'), ('18048', '42263'), ('18048', '52100'),
    ('18048', '52200'), ('18048', '56100'), ('18048', '56200'), ('18048', '56310'), ('18048', '56500'),
    ('18048', '56600'), ('18048', '56700'), ('18902', '40400'), ('20354', '42053'), ('20354', '42263'),
    ('20700', '75100'), ('20929', '52300'), ('23399', '52200'), ('23399', '55100'), ('25616', '51200'),
])

# Fixed forms, as published: no leading zeros and exactly one ASCII space after '<'.
NUMBER = re.compile(r'(?:0|[1-9][0-9]*)(?:,[0-9]+)?')
BOUND = re.compile(r'< (-?(?:0|[1-9][0-9]*)(?:,[0-9]+)?)')
CONFIDENCE = frozenset('ABCD')
BOM = b'\xef\xbb\xbf'

ROWS = {
    'alim': ('ALIM', {'alim_code', 'alim_nom_fr', 'alim_nom_eng', 'alim_nom_sci', 'alim_grp_code',
                      'alim_ssgrp_code', 'alim_ssssgrp_code', 'facteur_Jones'}),
    'alim_grp': ('ALIM_GRP', {'alim_grp_code', 'alim_grp_nom_fr', 'alim_grp_nom_eng', 'alim_ssgrp_code',
                              'alim_ssgrp_nom_fr', 'alim_ssgrp_nom_eng', 'alim_ssssgrp_code',
                              'alim_ssssgrp_nom_fr', 'alim_ssssgrp_nom_eng'}),
    'const': ('CONST', {'const_code', 'const_nom_fr', 'const_nom_eng', 'code_INFOODS'}),
    'compo': ('COMPO', {'alim_code', 'const_code', 'teneur', 'min', 'max', 'code_confiance', 'source_code'}),
}


def _preparation():
    path = Path(__file__).resolve().parent / 'project_usda.py'
    spec = importlib.util.spec_from_file_location('project_usda_preparation', path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module.PREPARATION_POLICY, module.preparation_from_description


PREPARATION_POLICY, preparation_from_description = _preparation()


def _refuse(*_):
    raise ValueError('DTD, entity or external reference refused')


def parse_rows(data, kind):
    """Parse one Ciqual XML table into a list of {field: stripped text or None}, with line numbers."""
    row_tag, fields = ROWS[kind]
    if data.startswith(BOM): data = data[len(BOM):]
    if b'<!DOCTYPE' in data or b'<!ENTITY' in data: _refuse()
    parser = expat.ParserCreate('UTF-8')
    parser.SetParamEntityParsing(expat.XML_PARAM_ENTITY_PARSING_NEVER)
    parser.StartDoctypeDeclHandler = _refuse
    parser.EntityDeclHandler = _refuse
    parser.UnparsedEntityDeclHandler = _refuse
    parser.ExternalEntityRefHandler = _refuse
    parser.SkippedEntityHandler = _refuse
    rows, stack, state = [], [], {}

    def start(tag, attrs):
        depth = len(stack)
        if depth == 0 and tag != 'TABLE': raise ValueError('unexpected root: ' + tag)
        if depth == 1:
            if tag != row_tag: raise ValueError('unexpected row: ' + tag)
            state['row'], state['line'] = {}, parser.CurrentLineNumber
            state['lines'] = {}
        if depth == 2:
            if tag not in fields or tag in state['row']: raise ValueError('unexpected or duplicate field: ' + tag)
            if set(attrs) - {'missing'}: raise ValueError('unexpected attribute')
            state['field'], state['text'], state['missing'] = tag, [], 'missing' in attrs
            state['lines'][tag] = parser.CurrentLineNumber
        if depth >= 3: raise ValueError('unexpected nesting')
        stack.append(tag)

    def end(tag):
        stack.pop()
        if len(stack) == 2:
            text = ''.join(state['text']).strip()
            if state['missing']:
                if text: raise ValueError('missing field carries text')
                state['row'][tag] = None
            else:
                state['row'][tag] = text
        elif len(stack) == 1:
            row = state['row']
            if set(row) != fields: raise ValueError('incomplete row')
            row['_line'] = state['line']; row['_lines'] = state['lines']
            rows.append(row)

    def chars(text):
        if len(stack) == 3: state['text'].append(text)
        elif text.strip(): raise ValueError('unexpected text')

    parser.StartElementHandler, parser.EndElementHandler, parser.CharacterDataHandler = start, end, chars
    parser.Parse(data, True)
    return rows


def classify(literal):
    """Return (form, decimal string or None). Fixed rule; never a locale."""
    if literal is None: raise ValueError('absent teneur')
    if literal == '-': return 'missing', None
    if literal == 'traces': return 'traces', None
    if NUMBER.fullmatch(literal): return 'number', literal.replace(',', '.')
    bound = BOUND.fullmatch(literal)
    if bound: return 'bound', bound.group(1).replace(',', '.')
    raise ValueError('unknown value form: ' + literal)


def manifest_bytes(manifest):
    return json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()


def verify(folder, files):
    """Check every pinned file and return (manifest, {name: bytes})."""
    contents, entries = {}, []
    for file_id, name, size, md5, sha256 in sorted(files):
        raw = (folder / name).read_bytes()
        if len(raw) != size or hashlib.md5(raw).hexdigest() != md5 or hashlib.sha256(raw).hexdigest() != sha256:
            raise ValueError('pinned file changed: ' + name)
        contents[name] = raw
        entries.append(dict(id=file_id, name=name, bytes=size, md5=md5, sha256=sha256))
    manifest = dict(doi=DOI, datasetVersion=DATASET_VERSION, releaseTime=RELEASE_TIME, files=entries)
    return manifest, contents


def value_entry(key, row, constituent, unit):
    literal = row['teneur']
    form, decimal = classify(literal)
    confidence = row['code_confiance']
    entry = dict(constCode=constituent, unit=unit, literal=literal)
    if confidence is not None: entry['confidence'] = confidence
    if row['source_code'] is not None: entry['sourceCode'] = row['source_code']
    # A7: min and max are the range observed across Ciqual's source data, kept for details only.
    if row['min'] is not None: entry['min'] = row['min']
    if row['max'] is not None: entry['max'] = row['max']
    if form == 'missing': entry.update(state='unknown', reason='not_declared')
    elif form == 'traces': entry.update(state='unknown', reason='no_compatible_source')
    elif key in UNPROJECTED: entry.update(state='unknown', reason=UNPROJECTED[key])
    elif form == 'number': entry.update(state='exact', value=decimal)
    else: entry.update(state='bounded', upper=decimal, upperClosed=False)
    return entry


def project(tables, subgroups=SUBGROUPS, nonpositive_exceptions=PINNED_NONPOSITIVE_BOUNDS):
    foods, groups, constituents, compo = (tables[k] for k in ('alim', 'alim_grp', 'const', 'compo'))
    codes = [f['alim_code'] for f in foods]
    if len(set(codes)) != len(codes): raise ValueError('duplicate alim_code')
    scoped = {f['alim_code']: f for f in foods if f['alim_ssgrp_code'] in subgroups}
    const_by_code = {c['const_code']: c for c in constituents}
    if len(const_by_code) != len(constituents): raise ValueError('duplicate const_code')
    for mapped in filter(None, MAPPING.values()):
        code, unit = mapped
        if code not in const_by_code: raise ValueError('mapped constituent missing: ' + code)
        if not const_by_code[code]['const_nom_fr'].endswith(FRENCH_UNIT[unit]): raise ValueError('unit drift: ' + code)
    names = {}
    for g in groups:
        if g['alim_ssgrp_code'] in subgroups:
            names.setdefault(g['alim_ssgrp_code'], (g['alim_grp_code'], g['alim_ssgrp_nom_eng']))
    if set(names) != set(subgroups): raise ValueError('admitted subgroup not published')

    pairs, values, nonpositive = set(), {}, set()
    for row in compo:
        pair = (row['alim_code'], row['const_code'])
        if pair in pairs: raise ValueError('duplicate food and constituent pair')
        pairs.add(pair)
        form, decimal = classify(row['teneur'])
        confidence = row['code_confiance']
        if form == 'missing':
            if confidence is not None: raise ValueError('a "-" carries a confidence code')
        elif confidence not in CONFIDENCE:
            raise ValueError('a value has no confidence code')
        if form == 'bound' and Decimal(decimal) <= 0:
            if pair[0] in scoped or pair not in nonpositive_exceptions: raise ValueError('"< n" with n <= 0')
            nonpositive.add(pair)
        if pair[0] in scoped: values[pair] = row
    if nonpositive != set(nonpositive_exceptions): raise ValueError('pinned "< 0" rows changed')

    records = []
    for code in sorted(scoped, key=int):
        food = scoped[code]
        nutrients = {}
        for key, mapped in MAPPING.items():
            if mapped is None or (code, mapped[0]) not in values:
                nutrients[key] = dict(state='unknown', reason='not_declared')
                continue
            nutrients[key] = value_entry(key, values[(code, mapped[0])], *mapped)
        records.append(dict(alimCode=code, name=food['alim_nom_eng'], frenchName=food['alim_nom_fr'],
            groupCode=food['alim_grp_code'], subgroupCode=food['alim_ssgrp_code'],
            subSubgroupCode=food['alim_ssssgrp_code'], preparation=preparation_from_description(food['alim_nom_eng']),
            nutrients=nutrients))
    return records, dict(sourceFoods=len(foods), sourceCompositionRows=len(compo),
                         subgroups=[dict(code=c, groupCode=names[c][0], name=names[c][1]) for c in subgroups])


def build(folder, files=FILES, subgroups=SUBGROUPS, nonpositive_exceptions=PINNED_NONPOSITIVE_BOUNDS):
    manifest, contents = verify(folder, files)
    tables = {kind: parse_rows(contents[_name(contents, kind)], kind) for kind in ROWS}
    records, counts = project(tables, subgroups, nonpositive_exceptions)
    manifest_sha = hashlib.sha256(manifest_bytes(manifest)).hexdigest()
    release_id = '%s:2025-11-19:sha256:%s' % (SOURCE_ID, manifest_sha)
    for record in records: record['recordID'] = release_id + ':alim:' + record['alimCode']
    return dict(schema=SCHEMA, projectionVersion=PROJECTION, groupScope=GROUP_SCOPE, sourceID=SOURCE_ID,
        doi=DOI, datasetVersion=DATASET_VERSION, releaseTime=RELEASE_TIME, releasedAt=RELEASED_AT,
        sourceManifest=manifest, sourceManifestSHA256=manifest_sha, sourceReleaseID=release_id,
        compoSHA256=hashlib.sha256(contents[_name(contents, 'compo')]).hexdigest(),
        licence=LICENCE, attribution=ATTRIBUTION, variant=VARIANT, basis='per100Grams',
        preparationPolicy=PREPARATION_POLICY, records=records, **counts)


def _name(contents, kind):
    found = [n for n in contents if n.startswith(kind + '_2')]
    if len(found) != 1: raise ValueError('missing pinned file for ' + kind)
    return found[0]


def corpus_bytes(corpus):
    return (json.dumps(corpus, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('downloads', type=Path, help='folder holding the five pinned Ciqual 2025 XML files')
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = build(args.downloads)
    data = corpus_bytes(result)
    args.output.write_bytes(data)
    print(json.dumps(dict(records=len(result['records']), sourceFoods=result['sourceFoods'], bytes=len(data),
        sourceManifestSHA256=result['sourceManifestSHA256'], sha256=hashlib.sha256(data).hexdigest())))
