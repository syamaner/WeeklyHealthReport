# Personal food database import v1: phase 1 plan and P1a gate

Status: **draft, 11 November 2026, programme #424, base contract #419.** It plans the app side of
[import v1](personal-food-catalogue-import-v1.md) (revision 5, accepted 7 November 2026), which is
step 1 of the order of work in the [estimates contract](personal-food-catalogue-estimates-v1.md)
(section 6). E3 is final (plan revision 7, decision 11) and both contracts are accepted, so the
block on importer code is lifted. This document changes no rule of either contract; where it
refines one, it says so and the contract wins.

## 1. Why phase 1 is split

Import v1 is one contract but four kinds of change: a pure codec, a protected store with a
Settings lifecycle, a search adapter with a nutrient merge, and the confirmation, save and export
path. One PR for all of it would be too large to review against the closed rules. Phase 1 is
therefore three PRs, each with its own ledger row, in this order:

| PR | Scope | Contract sections |
|---|---|---|
| **P1a** | Pure domain codec for `personal-food-catalogue-v1`: strict JSON reading, typed model, every rejection rule with the shared rule codes, release identity as a pure function of the digest. No store, no UI, not wired. | 3 (domain), 4, 4.1, 4.2, 9 (fixtures, release identity) |
| **P1b** | `FoodLedgerPersonalDatabase` store target (protected dataset layout, one active release), `PersonalFoodDatabaseImporting` (validate, digest, atomic replace, release immutability), Settings row "Your food database" (import, replace, remove, locked), boundary rule with a failing fixture. | 3, 7 (lifecycle, locked), 8, 9 (lifecycle, immutability, boundaries) |
| **P1c** | `GenericRecordResolving` for CoFID, USDA and TFDA, `PersonalFoodDatabaseFoodSearch`, the composite's `databaseSource`, the "Your food database" family, amendment A1 merge, Confirm notice, save, release records and export, the amendment rows, and the simulator journey. No ranking change: rows take their v11 place. | 5 (except v12), 6, 7, 9 |

Then, as the estimates contract orders: phase 2 (estimates decoder, provenance kind, capture
manifest, presentation, export amendment) and phase 3 (ranking v12).

## 2. P1a architecture gate

**Responsibilities.**

- `PersonalFoodDatabaseJSON` (`FoodLedgerDomain`): a strict, byte-level reader that turns the file
  into a small value tree (object as ordered key and value pairs, array, string, number as its
  exact source text plus a finite `Double`, boolean, null). It refuses a byte-order mark, UTF-16 or
  any non-UTF-8 byte, `NaN`, `Infinity` and every other non-JSON token, a repeated key in one object,
  nesting deeper than a fixed limit and trailing bytes. Foundation's `JSONSerialization` and
  `JSONDecoder` are not used for this file: neither reports repeated keys, and both lose the exact
  number text the "too large to be a nutrient value" rule needs.
- `PersonalFoodDatabaseCodec` (`FoodLedgerDomain`): `decode(_ bytes: Data) -> Result<PersonalFoodDatabaseFile, PersonalFoodDatabaseRejection>`.
  It enforces the size and count limits, then every rule of section 4.2 on the value tree, and
  collects every failing rule code rather than stopping at the first, as the skill's `check_bytes`
  does. The rejection carries the set of rule codes and a short visible reason; it never carries an
  entry ID, title or value, so a later Settings message cannot leak file content.
- Typed model (`FoodLedgerDomain`): `PersonalFoodDatabaseFile`, `PersonalFoodDatabaseEntry`,
  `PersonalFoodDatabaseLabelValue`, `PersonalFoodDatabaseGenericReference`,
  `PersonalFoodDatabaseDeclaredSource`, and closed enums for category, product type, state, basis,
  source kind and match pair, generic source, reference match and role. Values use the existing
  `NutrientKey` and canonical units; transforms use one table built from the app's existing pairs
  (`NutrientDerivation.calculatedTransforms` and the `mass-g-to-mg` conversion), each limited to its
  nutrient, source unit and source kind, with the 0.5 per cent recompute check.
- Release identity (`FoodLedgerDomain`): `PersonalFoodDatabaseRelease.sourceRelease(fileSHA256:generated:)`
  builds the database `SourceRelease` exactly as section 4 defines it, as a pure function of the
  digest and the `generated` date. The digest itself is computed by the caller through the
  existing `Digesting` port (P1b); the domain never hashes.

**Dependency direction.** Domain only: Foundation and existing `FoodLedgerDomain` types. Nothing
imports the new types yet except tests. No application, infrastructure or presentation change, no
persisted format or schema change, no migration.

**Invariants.** A rejected file yields no model. Every unexpected type is a rejection, never a
crash or a trap. Unknown stays unknown: there is no null, trace or bounded value, and zero is only
a declared zero. Entry IDs are opaque (never recomputed). The rule codes are the skill's codes, so
the two checkers cannot silently disagree.

**Extension axes.** None. The format is closed; a new field, source, transform or vocabulary value
is a new schema version. The estimates decoder of phase 2 sits beside this codec and shares its
validation functions, so P1a exposes them as internal functions of the module rather than private
helpers of one type.

**Contract tests (synthetic fixtures only).**

- Every file in `docs/fixtures/personal-food-database-v1/manifest.json`: `golden.json` decodes; each
  `reject-*.json` is rejected with its listed rule code among the codes; none crashes. The two
  generated cases (size and count) are built at test time. The test reads the manifest, so a new
  fixture added for the Python checker is picked up by Swift with no code change.
- The golden file decodes to the expected typed values (ASCII, accented and Chinese titles; a
  transform value; a `merge` and a `candidate` reference).
- Release identity: for `golden.json`, the release ID from SHA-256 of its bytes equals the one the
  skill's `export_v1` computes (pinned in the test as a constant derived from the fixture); one
  changed byte gives a different release; the `SourceRelease` fields match section 4 exactly.
- The strict reader in isolation: repeated keys at depth, BOM, UTF-16, non-finite tokens, deep
  nesting, trailing bytes, huge integers, escaped and non-BMP strings.

**Validation.** `swift test --package-path Packages/FoodLedgerKit`, `check-boundaries.sh` and
`git diff --check`. P1a touches no app target, so the Xcode gates run but are expected unchanged.

### 2.1 Changes from the architecture-gate review (11 November 2026)

Verdict PASS WITH CHANGES. Each change below binds P1a and overrides any looser wording above.

1. **Numbers.** A number node keeps its exact text and a `Double` that may be infinite. The codec
   rejects as `value` anything non-finite, negative or at least 1e15 (`export_v1._num`), so the
   400-digit fixture gives `value`, as the manifest expects. Python refuses an integer of more than
   4,300 digits as `json`; Swift does the same by counting digits before conversion, and a shared
   fixture pins it.
2. **Lone surrogates** (`"\ud800"`) cannot be held in a Swift `String`. Both checkers reject them as
   `json`; the Python checker gains the rule and a shared fixture.
3. **Unicode comparison.** Keys, IDs and vocabulary are compared by Unicode scalars, never by Swift
   `String` equality (which uses canonical equivalence), so two keys differing only as NFC and NFD
   are distinct, as in Python. Every digit, hex, date and GTIN rule checks ASCII bytes;
   `Character.isHexDigit` and other Unicode-aware predicates are not used, and unvalidated text never
   reaches `SHA256Digest`.
4. **Stage order,** as in `check_bytes`: size, then BOM, then whole-file UTF-8 (`encoding`), then
   parse (`json`), then the rules. The reader checks depth before recursing, with Python's
   effective limit stated in code, and overflow is `json`.
5. **No throwing primitives on file content.** No `try!`; brand and titles are kept as raw strings
   (an empty brand string is valid). The `title` rule uses one whitespace set equal to Python's
   `str.strip()` (which includes U+001C to U+001F), with a shared fixture.
6. **Declared sources.** `PersonalFoodDatabaseDeclaredSource.sourceRelease()` moves into P1a, so
   P1b's immutability check has its mapping. The Open Food Facts parity test (contract section 9)
   is owned by P1c.
7. **Rule codes.** A closed Swift enum whose raw values are the Python codes, with a test that the
   two sets are equal. The Python checker emits `corpus` instead of `malformed` for a non-string
   corpus source. New shared fixtures cover `sources`, `item-keys`, `label-nutrients`,
   `value-shape` and that corpus case.
8. **Transforms.** A separate allow-list for this schema, sodium-only for `mass-g-to-mg`;
   `NutrientDerivation.calculatedTransforms` is not changed. The check copies Python's formula and
   order exactly: rejected when `abs(f(sv) - v) > 0.005 * abs(f(sv)) + 1e-9`.
9. **Release date.** `sourceRelease` takes the validated typed date and computes 00:00:00Z with a
   fixed UTC Gregorian calendar, never the process calendar or time zone.
10. **Golden bytes.** The fixture folder is marked `-text` in `.gitattributes`; the test pins the
    SHA-256 `shasum` gives for the committed `golden.json` and uses a test-local CryptoKit digest.
11. **Accept set.** The manifest gains an `accept` list checked by both sides: `-0`, `4e2`, an
    integer value, a transform exactly at the tolerance, an empty brand, empty `label_nutrients` and
    `titles`, and an `off-product-projection-v5` release.

Added contract tests: the rule-code set equality; stage order; lone surrogates, depth limit plus
one, an integer over 4,300 digits, `1e400`, `1e15` and a U+001C title; NFC and NFD keys distinct;
full-width digits rejected in GTIN, hex and dates; the tolerance boundary both ways; declared Open
Food Facts and owner sources mapping to `SourceRelease`; `releasedAt` unchanged under a non-UTC
process time zone; a seeded fuzz of truncations and type swaps of the golden file with no trap;
and the accept set on both checkers.

Python changes stay inside the skill script and its tests; no frozen tool, seal or freeze record
changes. They make the checker stricter only for inputs no build has produced (lone surrogates) or
change one rejection's code (`malformed` to `corpus`).

## 3. Open points (none blocks P1a)

- P1b: whether the database file lives under the existing dataset root or a sibling folder;
  decided in the P1b gate against `food-library-storage-and-backup-decision.md`.
- P1c: the composite's dedupe and the shared `sameSourceRecord` move are specified in section 5 of
  the contract; P1c's gate restates them with the resolver contract suite.
