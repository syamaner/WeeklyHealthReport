# Label photo estimates v1: phase gate

Status: **phase gate, 18 November 2026, after two blind reviews (section 8); implemented on the
phase branch, with one change recorded in section 9.** Implements the accepted contract
[label photo estimates v1](personal-food-catalogue-off-estimates-v1-proposal.md) (PR 516) as one
phase. Issue: #518. Programme #424.

Everything in the contract stands. This file fixes the names, numbers, rule codes and code sites the
contract left to the gate, and the test list. It repeats no rule of the contract.

## 1. Numbers and names allocated here

| Item | Value | Why |
|---|---|---|
| Catalogue schema | `personal-food-catalogue-estimates-v3` | Contract section 2.1. |
| Private input | `pfc-accepted-estimates-v2` | Contract section 2.1. Input v1 keeps refusing the token. |
| Source-type token | `product_dataset_photo` | Contract section 2.1. |
| Capture manifest | `pfd-estimate-capture-v1`, unchanged; the token is allowed only from food contract 11 | The per-stored-contract token list (contract section 2.1), as built: see section 9. |
| Food contract | **11** | The store's GRDB migrations run in order, so the next number is the only safe one. [Assistant-pasted estimates v1](assistant-pasted-estimates-v1-proposal.md) section 7 claimed 11, but says its phase "takes the next free one" when 11 is taken; it is not built, so it moves to 12 (dated note added there). |
| Store | `FoodLedgerGRDBStore.schemaVersion` 11, migration `v11_label_photo_estimate`, metadata `food-ledger-v11` | Metadata only, as `v10_approved_estimate`. |
| Daily food export | **`food_daily_schema_version` 5** | Contract section 4: the next number no contract claims (4 is claimed by assistant-pasted estimates and not built). Version 5 is version 3's shape plus the token, nothing else. **Whichever phase later needs both shapes allocates a new number (6) for the union; a shipped version is never widened.** The v4 union fixture is deferred to that phase. |
| Output file | `out/personal-food-catalogue-estimates-v3.json` when a photo estimate is admitted; otherwise `…-estimates-v2.json`, byte-identical to today | The writer retires whichever name the run does not write. |

## 2. The photo record (contract sections 2.1 to 2.4, made mechanical)

### 2.1 Address and barcode

- `source_reference` must start with the exact bytes `https://images.openfoodfacts.org/images/products/`
  (lower case, no port, no user information, no query or fragment), followed by one or more
  all-digit path segments and then one final file-name segment. The barcode is the digit segments
  joined. Anything else is `photo-fields`.
- The Open Food Facts host rejection (`open-food-facts-host`) stays for `manufacturer_page` and
  `aggregator`; a photo row is never judged by it.

### 2.2 Other fields

`composition_source` null; `page_access` `direct_read`; `source_digest` a 64-hex value (required);
`retrieved_on` a real date (required); `state_basis` `source_states_it` or `stated_assumption`;
`method` `direct` or `carried_from_similar_food`; `derivation` null. A failure of any of these is one
`photo-fields` code for that record. Quality ceiling `medium` (`estimate-quality`).

### 2.3 Relation (contract section 2.3, codec rule)

`direct` (same food) is accepted only when the photo's barcode equals, leading zeros removed, the
digits of an `off:gtin:` record ID that the same entry cites in `label_nutrients`. Otherwise the row
must be `carried_from_similar_food`. A `direct` photo of another barcode raises `photo-relation`.

### 2.4 State (builder rule with a must-be-zero count)

A photo row's `source_state` is one of these exact byte strings (no case or spacing
normalisation): `as sold`, `as sold, cooked`, `as prepared`, `raw`, `cooked`, `dried`, `frozen`,
`canned`, `drained`, `smoked`. Anything else refuses the input row.

| Entry state | Compatible `source_state` |
|---|---|
| `unknown` | `as sold`, `raw` |
| `raw` | `raw`, `as sold` |
| `cooked` | `cooked`, `as sold, cooked`, `as prepared` |
| `canned` | `canned`, `drained`, and `as sold` with `source_states_it` only |
| `dried`, `frozen`, `smoked` | the same word, `as sold` |

A row outside the table is withheld as `state_contradiction` and counted (must be zero in the file).

### 2.5 Ready to eat (owner decision F3)

Input v2 photo rows carry `ready_to_eat` (`true` or `false`), set by the owner on the review
sheet. `stated_assumption` is accepted only with `ready_to_eat: true` and `source_state` `as sold`
or `as sold, cooked`; anything else refuses the input row. The evaluator also counts
`stated_assumption` photo estimates on `raw`, `frozen` and `dried` entries, shown to the owner.

## 3. Refusal matching for photo rows (contract section 2.5)

- Classes `open_food_facts`, `per_entry_exclusion`, `value_fault`, `unresolved_a1`: a refusal row
  matches a photo estimate when the entry is the same and the row has no `nutrient` (every
  nutrient of the entry) or the same nutrient, whatever the row's `source_type`.
- Barcode: from a refusal row whose `source_reference` is `off:gtin:<digits>` or an address whose
  path holds `/product/<digits>`, compared with the photo's barcode (section 2.1), leading zeros
  removed. A match refuses that photo for every entry.
- A match is withheld as `refused_source`. The token is never re-admissible: refusal rows,
  re-admission list rows and sheet rows keep the estimates v2 token set, so a row naming
  `product_dataset_photo` there is refused.

## 4. Rule codes and their order (Python and Swift identical)

- New codes: `photo-fields`, `photo-relation`, `photo-missing`.
- In `check_record`: after the `token` check, a photo record runs its section 2.1 and 2.2 rules and
  raises at most one `photo-fields`, in the position the page-type checks hold today; the
  `digest`, `free-text` and derivation checks after it are unchanged.
- In the table of contract section 3.1: `estimate-own-*`, then `estimate-quality`, then
  `estimate-basis`, then `photo-relation`.
- After every record and item: `photo-missing` once, for a v3 file with no photo estimate.
- A v2 file carrying the token gets `token`. `photo-*` codes join `estimatesOnly`.

## 5. Responsibilities and sites

| Layer | Site | Change |
|---|---|---|
| Domain | `PersonalFoodDatabaseEstimateSourceType` | Gains `productDatasetPhoto`; `estimatesV2List` and `allowed(catalogue:)` replace the codec's `allCases` use; the export keeps its own list per schema (`FoodDailyExportShape.estimateSourceTypes(schema:)`); stored records are gated by contract 11 (section 9). |
| Domain | `PersonalFoodDatabaseSchema`, `PersonalFoodDatabaseCodec.swift:291` | `estimatesV3`, treated as an estimates schema for top-level and item keys. |
| Domain | `PersonalFoodDatabaseEstimateChecker.check`, `checkRecord`, `tableCodes`, `ceiling` | Take the schema; sections 2.1 to 2.3 and 4. |
| Domain | `ApprovedEstimateEvidence` | `typed` enforces sections 2.1 and 2.2 on a photo record (`PersonalFoodDatabasePhotoAddress.recordIsValid`), so an altered stored record gives nil. |
| Application | `CanonicalFoodProjection` | `foodContractVersion` 11; floor 11 for a capture manifest whose evidence names the token (read structurally, never from free text), before the contract 10 rule; decoding an archive labelled below 11 that holds one fails. |
| Application | `PersonalFoodDatabaseEstimateAdmission`, `ApprovedEstimateEligibility` | Unchanged: the national-only checks stay national-only (intentional). |
| Application | `FoodDailyExport.swift:587-590, 762, 836`, `FoodDailyExportShape.swift:46-50, 83, 127` | Version 5 written only when a kept value is a photo estimate; key 5 with its own branch; schema 3 rejects the token; schema 5 requires one and, on photo provenance, the section 2.1 host and a 64-hex `content_hash`. The page branch treating the token as a page is intentional. |
| GRDB | `FoodLedgerMigrations`, `FoodLedgerGRDBStore` | Migration 11 and open check. |
| Store | `FilePersonalFoodDatabaseStore.swift:305` | Accepts v3; an unknown schema still fails closed. |
| Presentation | `ApprovedEstimatePresentation.sourceType` | "Product database label photo". |
| Skill | `estimates_v2.py`, `export_v1.py` | v3 constant, per-schema token sets, sections 2.1 to 2.3 and 4. |
| Skill | `estimates_input.py` | Input v2 (v1 still read and still refuses the token), `ready_to_eat`, photo rows exempt from `open_food_facts_source` only for this token, section 2.4, v3 written only with a photo estimate admitted. |
| Skill | `estimate_counts.py` | Section 3; refusal, list and sheet rows keep the v2 token set; the counts of contract section 2.5 plus the section 2.5 count here. |
| Skill | `apply_estimates.py` | Output name by schema, retiring the other. |
| Docs | Daily export v2 contract | Dated note for version 5, including that a build with version 5 only rejects assistant fields (fails closed). |
| Docs | `assistant-pasted-estimates-v1-proposal.md` | Dated note: food contract 12, migration `v12_assistant_estimate`, daily export version 4 unchanged, union at 6. |
| Docs | `privacy-and-egress.md` | Contract section 5's statements: the barcode in an exported photo address (app, factual), and the photo fetch and the agent's photo read (developer tooling), the last two approved by the owner on 18 November 2026 (F6). |

Dependency direction is unchanged: domain and application stay free of frameworks; the skill is
outside the app; no new network path in the app.

## 6. Contract tests (Python and Swift alike, synthetic fixtures)

Fixtures: `docs/fixtures/personal-food-database-estimates-v3/`. The export cases of test 11 are built through the writer from that golden (`PhotoEstimateExportContractTests`) rather than from a separate `food-daily-v5` fixture.

1. A valid v3 file with one photo estimate decodes; the bytes re-encode unchanged; an installed v3
   catalogue reopens.
2. `photo-fields` for: another host, upper-case host, a port, query, fragment, a path without digit
   segments, missing digest, missing date, `indexed_copy`, `unknown` state basis, `derived` method,
   a derivation present, `carried_from_same_food`. `estimate-quality` for `high`.
3. `photo-relation`: `direct` with another barcode; `direct` with the entry's own `off:gtin:`
   passes.
4. `token` for the token in a v2 file (the new binary's v2 checker); `photo-missing` for a v3 file
   without one; Python and Swift give the same codes in the same order for every fixture.
5. A page type on an Open Food Facts host is still `open-food-facts-host` in v2 and v3.
6. Input: v1 refuses the token; v2 accepts it; `underlying_source` other than `not_applicable`
   refused; a `source_state` outside section 2.4, or `As sold`, refused; `stated_assumption` without
   `ready_to_eat: true`, or with `as prepared`, refused; a derivation refused.
7. Admission: a refusal row of another source type with no nutrient refuses every nutrient of the
   entry; a nutrient row refuses that nutrient only; the barcode rule refuses another entry; an
   `as sold` panel on a `cooked` entry, an `as prepared` panel on an `unknown` entry and `as sold`
   with `stated_assumption` on a `canned` entry are withheld and counted; refusal, list and sheet
   rows naming the token are refused.
8. Writer: with no photo estimate admitted, the estimates v2 bytes are unchanged and v3 is not
   written; with one, v3 is written and the v2 name retired.
9. Store: migration 10 to 11; a contract 11 archive with a photo manifest round-trips; a contract
   10 archive holding one is rejected by the new binary; encoding refuses contract 10 for it; a
   national manifest stays at contract 10 and decodes.
10. Manifest: a stored photo record with a null digest, another host, a `high` tier or
    `carried_from_same_food` gives `typed` nil.
11. Export: version 5 only with a kept photo estimate; a day whose photo estimate was left out or
    withheld exports as 3 or 2, byte-identical; a photo plus a national estimate exports as 5;
    validators 3 and 5 reject each other's case; `content_hash` equals the manifest digest (writer
    test).
12. Presentation shows "Product database label photo".

## 7. Not in this phase

The private fibre pass, any photo fetch (waits for the F6 wording approval), any rebuild of the
private catalogue, and any change to the no-repeat rule (waits for the owner's count).

## 8. Review record

- **18 November 2026, blind `architecture-gate` and `invariant-reviewer` reviews of the first draft:
  both pass with notes, nothing blocking.** Applied:
  - the codec site and the schema passed into the checker, so v2 is not widened;
  - refusal, list and sheet rows keep the v2 token set;
  - a v2 capture manifest as the per-stored-contract list, with every site named;
  - the barcode relation rule (`photo-relation`);
  - a new number for any later union, never widening a shipped version;
  - manifest and v5 validator photo rules;
  - named codes and their order;
  - the assistant-pasted renumbering note and the third egress statement;
  - `unknown` entries limited to `as sold` and `raw`;
  - `ready_to_eat` for `stated_assumption`;
  - `drained`, and `canned` with `as sold` only when stated;
  - an exact host and path shape that fails closed;
  - exact-byte state matching;
  - the added tests.
- **18 November 2026, blind `invariant-reviewer` review of the implementation at 1f7d0ce4: pass with
  notes, nothing blocking.** Applied:
  - writer tests for daily export version 5 (kept photo, left-out photo, photo beside a composition
    estimate, and the v2 catalogue staying at 3);
  - a store test that an installed v3 catalogue reopens;
  - two Python hardenings (a non-string evidence ID in a tampered file, and non-ASCII digits in a
    refusal row);
  - the site table and the F6 wording aligned with what was built.

## 9. Change made during implementation

The gate first chose a new manifest version (`pfd-estimate-capture-v2`) as the per-stored-contract
list. While building it, the manifest's method version turned out to be part of every saved
estimate's provenance check (`ApprovedEstimateProvenance.manifestReference`), so a second version
would have changed how every existing estimate value is validated. The same safety holds without
it: a record citing the token needs food contract 11, so every older binary declines the store
(schema 11) and the archive (contract 11); the new binary rejects an archive labelled below 11 that
holds one; and a stored photo record keeps its photo rules. The manifest stays
`pfd-estimate-capture-v1` and test 9 checks the rule.
