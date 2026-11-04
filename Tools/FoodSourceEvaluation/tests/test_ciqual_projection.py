"""ciqual-projection-v1 and ciqual-group-scope-v1 on synthetic XML fixtures (never the real files)."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import json
import unittest

spec = importlib.util.spec_from_file_location('project_ciqual', Path(__file__).parents[1] / 'project_ciqual.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
audit_spec = importlib.util.spec_from_file_location('audit_ciqual', Path(__file__).parents[1] / 'audit_ciqual.py')
audit = importlib.util.module_from_spec(audit_spec); audit_spec.loader.exec_module(audit)

BOM = '﻿'
NAMES = {'const': 'const_2025_11_03.xml', 'sources': 'sources_2025_11_03.xml', 'compo': 'compo_2025_11_03.xml',
         'alim_grp': 'alim_grp_2025_11_03.xml', 'alim': 'alim_2025_11_03.xml'}
IDS = {'const': 666246, 'sources': 666248, 'compo': 666249, 'alim_grp': 666250, 'alim': 666252}


def element(tag, value):
    if value is None: return '      <%s missing=" " />' % tag
    return '      <%s> %s </%s>' % (tag, value.replace('&', '&amp;').replace('<', '&lt;'), tag)


def table(row_tag, rows, prolog=''):
    lines = [BOM + '<?xml version="1.0" encoding="utf-8" ?>' + prolog, '<TABLE>']
    for row in rows:
        lines.append('   <%s>' % row_tag)
        lines += [element(k, v) for k, v in row]
        lines.append('   </%s>' % row_tag)
    lines.append('</TABLE>')
    return '\r\n'.join(lines).encode()


class Fixture:
    """A small synthetic Ciqual release: two chocolate foods (0702) and one food outside the scope."""

    def __init__(self):
        units = {code: unit for code, unit in filter(None, m.MAPPING.values())}
        units.update({'333': 'kcal', '10004': 'g', '327': 'g'})
        self.const = [[('const_code', c), ('const_nom_fr', 'Constituant %s %s' % (c, m.FRENCH_UNIT[u])),
                       ('const_nom_eng', 'Constituent %s' % c), ('code_INFOODS', 'X')] for c, u in sorted(units.items())]
        self.foods = [self.food('31074', 'Dark chocolate, 70% cocoa, bar', 'Chocolat noir 70 % de cacao environ, tablette', '0702'),
                      self.food('31005', 'Dark chocolate, 50% cocoa, bar', 'Chocolat noir 50 %, tablette', '0702'),
                      self.food('1000', 'Pastis (anise-flavoured spirit)', 'Pastis', '0603')]
        self.groups = [[('alim_grp_code', '07'), ('alim_grp_nom_fr', 'produits sucrés'), ('alim_grp_nom_eng', 'sugar and confectionery'),
                        ('alim_ssgrp_code', '0702'), ('alim_ssgrp_nom_fr', 'chocolats'), ('alim_ssgrp_nom_eng', 'chocolate and chocolate products'),
                        ('alim_ssssgrp_code', '000000'), ('alim_ssssgrp_nom_fr', '-'), ('alim_ssssgrp_nom_eng', '-')]]
        self.compo = {}
        for food in ('31074', '31005', '1000'):
            for code in sorted(units, key=int):
                self.compo[(food, code)] = dict(teneur='1,5', min=None, max=None, code_confiance='A', source_code='1')
        self.extra = []
        self.prolog = {}

    @staticmethod
    def food(code, eng, fr, subgroup):
        return [('alim_code', code), ('alim_nom_fr', fr), ('alim_nom_eng', eng), ('alim_nom_sci', None),
                ('alim_grp_code', subgroup[:2]), ('alim_ssgrp_code', subgroup), ('alim_ssssgrp_code', '000000'),
                ('facteur_Jones', '6.25')]

    def set(self, food, const, teneur, confidence='A', **extra):
        self.compo[(food, const)] = dict(dict(min=None, max=None, source_code=None if teneur == '-' else '1'),
                                         teneur=teneur, code_confiance=confidence, **extra)

    def write(self, folder):
        compo_rows = [[('alim_code', f), ('const_code', c), ('teneur', r['teneur']), ('min', r['min']), ('max', r['max']),
                       ('code_confiance', r['code_confiance']), ('source_code', r['source_code'])]
                      for (f, c), r in self.compo.items()] + self.extra
        data = {'const': table('CONST', self.const, self.prolog.get('const', '')),
                'sources': table('SOURCES', [[('source_code', '1'), ('ref_citation', 'Synthetic')]]),
                'compo': table('COMPO', compo_rows, self.prolog.get('compo', '')),
                'alim_grp': table('ALIM_GRP', self.groups), 'alim': table('ALIM', self.foods, self.prolog.get('alim', ''))}
        files = []
        for kind, raw in data.items():
            (folder / NAMES[kind]).write_bytes(raw)
            files.append((IDS[kind], NAMES[kind], len(raw), hashlib.md5(raw).hexdigest(), hashlib.sha256(raw).hexdigest()))
        return tuple(sorted(files))


class CiqualProjectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.folder = Path(self.tmp.name)
        self.fixture = Fixture()

    def tearDown(self): self.tmp.cleanup()

    def build(self, exceptions=frozenset()):
        files = self.fixture.write(self.folder)
        return m.build(self.folder, files=files, nonpositive_exceptions=exceptions)

    def nutrients(self, corpus, code='31074'):
        return next(r for r in corpus['records'] if r['alimCode'] == code)['nutrients']

    def rejects(self, message=None, exceptions=frozenset()):
        with self.assertRaises(ValueError) as caught: self.build(exceptions)
        if message: self.assertIn(message, str(caught.exception))

    def testScopeIdentityAndReleaseFields(self):
        corpus = self.build()
        self.assertEqual([r['alimCode'] for r in corpus['records']], ['31005', '31074'])
        manifest_sha = hashlib.sha256(m.manifest_bytes(corpus['sourceManifest'])).hexdigest()
        self.assertEqual(corpus['sourceManifestSHA256'], manifest_sha)
        self.assertEqual([f['id'] for f in corpus['sourceManifest']['files']], sorted(IDS.values()))
        self.assertEqual(corpus['sourceReleaseID'], 'ciqual:2025-11-19:sha256:' + manifest_sha)
        record = corpus['records'][1]
        self.assertEqual(record['recordID'], corpus['sourceReleaseID'] + ':alim:31074')
        self.assertEqual(record['name'], 'Dark chocolate, 70% cocoa, bar')
        self.assertEqual(record['frenchName'], 'Chocolat noir 70 % de cacao environ, tablette')
        self.assertEqual(record['preparation'], 'unknown')
        self.assertEqual((corpus['sourceID'], corpus['releasedAt'], corpus['schema'], corpus['projectionVersion'], corpus['groupScope']),
                         ('ciqual', '2025-11-19T00:00:00Z', 'ciqual-generic-v1', 'ciqual-projection-v1', 'ciqual-group-scope-v1'))
        self.assertEqual(corpus['variant'], 'Ciqual · French composition estimate · per 100 g')
        self.assertNotRegex(corpus['variant'], r'\d+\s*%')
        self.assertTrue(corpus['attribution'].startswith('Anses. 2025. Table de composition nutritionnelle des aliments Ciqual 2025. https://doi.org/10.57745/RDMHWY.'))
        self.assertIn('Etalab Open Licence 2.0', corpus['licence'])
        self.assertEqual(corpus['compoSHA256'], hashlib.sha256((self.folder / NAMES['compo']).read_bytes()).hexdigest())
        self.assertEqual(len(self.nutrients(corpus)), 39)

    def testValueFormsBomPaddingAndMissingAttribute(self):
        f = self.fixture
        f.set('31074', '10260', '11', min='9,5', max='12')
        f.set('31074', '10120', '0,33', confidence='C')
        f.set('31074', '10340', '< 20')
        f.set('31074', '10300', '< 0,01', confidence='B')
        f.set('31074', '10290', 'traces')
        f.set('31074', '10251', '-', confidence=None)
        f.set('31074', '56600', '0', confidence='D')
        n = self.nutrients(self.build())
        self.assertEqual(n['iron'], dict(state='exact', value='11', unit='mg', constCode='10260', literal='11',
                                         confidence='A', sourceCode='1', min='9,5', max='12'))
        self.assertEqual((n['magnesium']['value'], n['magnesium']['literal'], n['magnesium']['confidence']), ('0.33', '0,33', 'C'))
        self.assertEqual({k: n['selenium'][k] for k in ('state', 'upper', 'upperClosed', 'unit')},
                         dict(state='bounded', upper='20', upperClosed=False, unit='mcg'))
        self.assertNotIn('value', n['selenium']); self.assertNotIn('lower', n['selenium'])
        self.assertEqual((n['zinc']['state'], n['zinc']['upper'], n['zinc']['literal']), ('bounded', '0.01', '< 0,01'))
        self.assertEqual((n['copper']['state'], n['copper']['reason'], n['copper']['literal']), ('unknown', 'no_compatible_source', 'traces'))
        self.assertEqual((n['manganese']['state'], n['manganese']['reason']), ('unknown', 'not_declared'))
        self.assertNotIn('confidence', n['manganese']); self.assertNotIn('sourceCode', n['manganese'])
        self.assertEqual((n['vitamin_b12']['state'], n['vitamin_b12']['value']), ('exact', '0'))

    def testUnknownKeysWaterVitaminAAndMissingPairs(self):
        del self.fixture.compo[('31074', '10200')]
        n = self.nutrients(self.build())
        for key in ('biotin_b7', 'chromium', 'molybdenum', 'caffeine', 'calcium'):
            self.assertEqual(n[key], dict(state='unknown', reason='not_declared'), key)
        self.assertEqual((n['water']['state'], n['water']['reason'], n['water']['literal'], n['water']['unit']),
                         ('unknown', 'missing_conversion', '1,5', 'g'))
        self.assertEqual((n['vitamin_a']['state'], n['vitamin_a']['reason']), ('unknown', 'no_compatible_source'))
        self.assertFalse(any(v['state'] != 'unknown' for k, v in n.items() if k in ('water', 'vitamin_a')))

    def testOneConstituentPerKeyEnergySodiumAndSalt(self):
        f = self.fixture
        f.set('31074', '328', '591', confidence='D'); f.set('31074', '333', '600', confidence='D')
        f.set('31074', '327', '2470', confidence='D')
        f.set('31074', '10110', '-', confidence=None); f.set('31074', '10004', '0,02')
        n = self.nutrients(self.build())
        self.assertEqual((n['energy_consumed']['value'], n['energy_consumed']['constCode'], n['energy_consumed']['unit']), ('591', '328', 'kcal'))
        self.assertEqual(n['sodium']['state'], 'unknown')
        self.assertEqual(n['sodium']['constCode'], '10110')
        self.assertEqual({v.get('constCode') for v in n.values()} & {'333', '327', '10004'}, set())
        self.assertEqual(n['protein']['constCode'], '25000'); self.assertEqual(n['folate_b9']['constCode'], '56700')
        self.assertEqual(n['vitamin_e']['constCode'], '71010'); self.assertEqual(n['vitamin_k']['constCode'], '54101')
        self.assertEqual(n['vitamin_d']['constCode'], '52100')

    def testFormsOutsideTheFiveAreRejectedAcrossTheWholeTable(self):
        for food in ('31074', '1000'):
            for literal in ('1.5', '1 000', 'NaN', 'n.d.', '', '<', '< x', '1,5,0', '-1', 'Traces', '<20', '<  20', '<\u00a020', '007', '00,5', '< 007'):
                with self.subTest(food=food, literal=literal):
                    self.fixture = Fixture(); self.fixture.set(food, '10260', literal)
                    self.rejects()

    def testNonPositiveUpperBoundsAreRejected(self):
        for literal in ('< 0', '< -1', '< 0,0'):
            for food in ('31074', '1000'):
                with self.subTest(literal=literal, food=food):
                    self.fixture = Fixture(); self.fixture.set(food, '10260', literal)
                    self.rejects('n <= 0')

    def testPinnedOutOfScopeZeroBoundsOnly(self):
        self.fixture.set('1000', '10260', '< 0')
        self.assertEqual(len(self.build({('1000', '10260')})['records']), 2)
        self.rejects('n <= 0', exceptions={('1000', '10530')})
        self.fixture = Fixture(); self.fixture.set('31074', '10260', '< 0')
        self.rejects('n <= 0', exceptions={('31074', '10260')})
        self.fixture = Fixture()
        self.rejects('pinned', exceptions={('1000', '10260')})

    def testConfidenceCodeRules(self):
        for food in ('31074', '1000'):
            for literal in ('11', '< 20', 'traces', '0'):
                with self.subTest(food=food, literal=literal, confidence=None):
                    self.fixture = Fixture(); self.fixture.set(food, '10260', literal, confidence=None)
                    self.rejects('no confidence code')
            with self.subTest(food=food, confidence='E'):
                self.fixture = Fixture(); self.fixture.set(food, '10260', '11', confidence='E')
                self.rejects('no confidence code')
            with self.subTest(food=food, literal='-', confidence='D'):
                self.fixture = Fixture(); self.fixture.set(food, '10260', '-', confidence='D')
                self.rejects('carries a confidence code')

    def testDuplicatesAndUnitDriftAreRejected(self):
        self.fixture.foods.append(Fixture.food('1000', 'Copy', 'Copie', '0603'))
        self.rejects('duplicate alim_code')
        self.fixture = Fixture()
        self.fixture.extra.append([('alim_code', '1000'), ('const_code', '400'), ('teneur', '1'), ('min', None), ('max', None),
                                   ('code_confiance', 'A'), ('source_code', '1')])
        self.rejects('duplicate food and constituent pair')
        self.fixture = Fixture()
        self.fixture.const = [row if row[0][1] != '10260' else [row[0], ('const_nom_fr', 'Fer (µg/100 g)')] + row[2:]
                              for row in self.fixture.const]
        self.rejects('unit drift')

    def testChangedByteInEachPinnedFileIsRejected(self):
        for kind, name in NAMES.items():
            with self.subTest(kind=kind):
                files = self.fixture.write(self.folder)
                path = self.folder / name
                raw = bytearray(path.read_bytes()); raw[-3] ^= 0x01; path.write_bytes(bytes(raw))
                with self.assertRaises(ValueError) as caught: m.build(self.folder, files=files, nonpositive_exceptions=frozenset())
                self.assertIn('pinned file changed', str(caught.exception))

    def testDoctypeAndEntitiesAreRefused(self):
        for kind, prolog in (('compo', '\r\n<!DOCTYPE TABLE [<!ENTITY x "1">]>'), ('alim', '\r\n<!DOCTYPE TABLE SYSTEM "x.dtd">'),
                             ('const', '\r\n<!DOCTYPE TABLE>')):
            with self.subTest(kind=kind):
                self.fixture = Fixture(); self.fixture.prolog[kind] = prolog
                self.rejects('refused')
        with self.assertRaises(Exception): m.parse_rows(b'<TABLE><ALIM><alim_code>&x;</alim_code></ALIM></TABLE>', 'alim')

    def testProjectionIsDeterministic(self):
        first = m.corpus_bytes(self.build())
        second = m.corpus_bytes(self.build())
        self.assertEqual(first, second)
        self.assertTrue(first.endswith(b'\n'))

    def testAuditTracesEveryValueAndCatchesATamperedCorpus(self):
        self.fixture.set('31074', '10340', '< 20'); self.fixture.set('31074', '10290', 'traces')
        files = self.fixture.write(self.folder)
        corpus = m.build(self.folder, files=files, nonpositive_exceptions=frozenset())
        path = self.folder / 'corpus.json'; path.write_bytes(m.corpus_bytes(corpus))
        result = audit.audit(self.folder, path, files=files)
        self.assertEqual(result['valueCorrespondence'], dict(passed=78, denominator=78))
        self.assertEqual(result['identityFailures'], 0)
        iron = next(v for v in result['values'] if v['alimCode'] == '31074' and v['key'] == 'iron')
        self.assertEqual((iron['literal'], iron['value'], iron['constCode']), ('1,5', '1.5', '10260'))
        self.assertIsInstance(iron['compoLine'], int)
        corpus['records'][1]['nutrients']['iron']['value'] = '15'
        path.write_bytes(m.corpus_bytes(corpus))
        self.assertEqual(audit.audit(self.folder, path, files=files)['valueCorrespondence']['passed'], 77)
        corpus['records'][1]['nutrients']['iron']['value'] = '1.5'
        for field, tampered in (('groupCode', '99'), ('subSubgroupCode', '999999')):
            with self.subTest(field=field):
                changed = json.loads(m.corpus_bytes(corpus)); changed['records'][1][field] = tampered
                path.write_bytes(m.corpus_bytes(changed))
                self.assertEqual(audit.audit(self.folder, path, files=files)['identityFailures'], 1)
        emptied = json.loads(m.corpus_bytes(corpus)); emptied['records'][1]['nutrients'] = {}
        path.write_bytes(m.corpus_bytes(emptied))
        self.assertGreater(audit.audit(self.folder, path, files=files)['identityFailures'], 0, 'an emptied record fails')
        corpus['records'] = corpus['records'][1:]
        path.write_bytes(m.corpus_bytes(corpus))
        with self.assertRaisesRegex(ValueError, 'scope binding'):
            audit.audit(self.folder, path, files=files)


if __name__ == '__main__': unittest.main()
