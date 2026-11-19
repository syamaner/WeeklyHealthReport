# Personal food database: other brands on composite dishes and composition-table addresses (G7, G8)

Status: **proposed for the owner's approval in #532.** The owner decided both questions of section 5
on 19 November 2026; this text becomes binding when the owner approves the PR, and no value it
admits is written before then. It follows amendments G1 to G5 and keeps their numbering. G6 (a
recorded density conversion between per 100 g and per 100 ml) was planned in #532 and deferred by the
owner on 19 November 2026; nothing here admits a density conversion.

It is a delta on [labelled estimates on catalogue v2](personal-food-catalogue-estimates-v2-proposal.md)
("estimates v2"), [import v1](personal-food-catalogue-import-v1.md), the
[label photo estimates](personal-food-catalogue-off-estimates-v1-proposal.md) ("label photo") and
[G5](personal-food-catalogue-composite-web-amendment-v1.md), and repeats none of them. Each amended
document gains a dated note pointing here.

## 1. Why

The owner's goal for the private catalogue is coverage ("all I care is %", 19 November 2026), with
honest labels. Counts only, from the owner's catalogue on 19 November 2026 (836 entries, 807 with
energy, protein, fat and fibre all known): 17 of the 29 entries still missing one of them are packaged
composite dishes whose only sources are other brands' labels, and about 8 single-ingredient entries
(dry tea leaves, beetroot juice) have a national composition table value only on a record page whose
address needs a query string.

## 2. Amendment G7: another brand's label on a composite dish (owner, 19 November 2026)

Amends import v1 decision 4 (as amended by G1), G5b and G5 section 3 (third bullet), the label photo
contract's rule for composite foods (same brand and named product only), and the skill's owner
ruling 6.

- **Pages.** A `manufacturer_page` estimate carried from a similar food (`carried_from_similar_food`)
  on a `packaged_composite` entry, another brand's product page, is admitted on G5a's terms: quality
  `low` and an assumption containing the fixed sentence "A generic recipe, not this product's.";
  otherwise the builder withholds it as `composite`. The same holds for an `aggregator` page relaying
  another brand's label. The codec ceiling of G5d (a similar-food web page on a composite entry is at
  most `low`) already bounds both; it is unchanged.
- **Label photos.** A `product_dataset_photo` estimate of another product on a composite entry carries
  the fixed sentence and is at most `low`; the builder withholds such a photo above `low`. A photo of
  the same named product (another pack, market or revision) keeps the label photo rules and its
  `medium` cap, without the sentence. Which product a photo shows is the owner's declaration on the
  review sheet, as G5c says for pages; the codec does not cap photos by method, because the owner's
  file holds 27 same-product photo estimates at `medium` on composite entries.
- **Counts.** `composite_other_product_page` (manufacturer pages carried from a similar food on a
  composite entry) becomes a reported count, no longer a must-be-zero count. `composite_above_low`
  also counts a composite photo that carries the fixed sentence.
- **Unchanged.** A label value always wins; the fixed sentence; national records on composite entries
  (G1); pages about this product (G5c).

## 3. Amendment G8: composition-table record addresses with a query (owner, 19 November 2026)

Amends estimates v2's page address rule (`source-reference`: no query string, no fragment). A page
address may carry a query string only when it is one of these record addresses, exactly:

| Host | Address | Query |
|---|---|---|
| `fooddb.mext.go.jp` (Japanese Standard Tables of Food Composition) | `https://fooddb.mext.go.jp/details/details.pl` | `ITEM_NO=` then 1 or 2 digits, `_`, 5 digits, `_`, 1 or 2 digits, and nothing else |
| `www.nutritionvalue.org` (USDA FoodData Central values) | `https://www.nutritionvalue.org/<name>_nutritional_value.html` (one path segment) | exactly `size=100+g` |

Any other query, a second parameter, a fragment or any other host with a query stays
`source-reference`. Both checkers implement the grammar by hand, byte for byte
(`PersonalFoodDatabaseEstimateChecker.tableQueryBase`, `estimates_v2.table_query_base`).

**Exports and egress.** The food daily export already drops the query string and fragment of a page
address (privacy and egress), and keeps doing so, so an exported MEXT address names the table's
record page but not the record. The full address stays on the device, in the stored evidence and in
Developer tools. Reading these pages is covered by the existing web search rule; G8 adds no
destination and no egress.

## 4. Compatibility and rollback

No token, field, schema version, store, food contract or egress changes.
- *An older build reading a G7 or G8 file:* a G7 row is a valid `low` row for it, and is read the same
  way; a file holding a G8 address is rejected whole with `source-reference`, never read differently.
- *A G7/G8 build reading an older file:* every older file stays valid: G7 loosens only builder rules,
  and G8 only admits addresses an older file could not hold.
- *Rollback:* rebuild the file without the G7 and G8 rows.

## 5. Architecture gate

Blind `architecture-gate` review of the G6 to G8 plan before code, 19 November 2026: CONCERNS. Its
G6 findings (ledger source basis, stored manifest, density as a closed domain rule, national rows,
photos) are why the owner deferred G6. For G7 it asked not to cap photos by method in the codec (the
27 `medium` rows), to keep "another product" an owner declaration, and to amend the named passages;
for G8 a closed per-host grammar mirrored byte for byte, and to state that exports keep dropping the
query. All are taken here.

- **Responsibilities.** G8: the codec's page address check (domain, `PersonalFoodDatabaseEstimates.swift`;
  skill mirror `estimates_v2.py`). G7: builder rules and counts only (`estimates_input.reason`,
  `estimate_counts`).
- **Dependency direction.** Unchanged; no new protocol or target.
- **Contract tests.** Shared fixtures in `docs/fixtures/personal-food-database-estimates-v2/`:
  `accept-page-url-mext-item`, `accept-page-url-nutritionvalue-100-g`,
  `reject-page-url-mext-extra-parameter`, `reject-page-url-nutritionvalue-other-size`
  (`source-reference`); `reject-page-url-with-query` and every other fixture keep their bytes and
  codes. Skill tests: the address grammar, a manufacturer page about another product admitted at `low`
  with the sentence and withheld otherwise, the reported count, and a composite photo with the sentence
  withheld above `low`.

## 6. Decisions

| # | Question | Decision |
|---|---|---|
| G7 | May another brand's label fill a composite dish? | Yes, as a `low` similar-food estimate with the fixed sentence. **Owner, 19 November 2026** ("approved", after "leave composite ones to last"). |
| G8 | May a composition-table record address carry its query string? | Yes, for the closed list of section 3 only. **Owner, 19 November 2026** ("approved"). |
| G6 | Density conversion | Deferred. **Owner, 19 November 2026** ("G7 and G8 now, G6 later"). |
