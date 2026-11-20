# Personal food database: generic web page estimates for composite dishes (G5)

Status: **accepted.** The owner decided the question of section 5 on 19 November 2026 and approved
#529, which merged on 19 November 2026. It follows the [gap estimates amendments G1 to G3](personal-food-catalogue-gap-estimates-v1-amendment.md)
and the [own merge amendment G4](personal-food-catalogue-own-merge-amendment-v1.md), and keeps their
numbering.

It is a delta on [labelled estimates on catalogue v2](personal-food-catalogue-estimates-v2-proposal.md)
("estimates v2") and on G1, and repeats neither. Everything estimates v2, import v1 and G1 to G4 say
that this document does not name stays as written. Estimates v2, import v1 and the G1 to G3 document
gain dated notes pointing here.

**Amendment, 19 November 2026 ([amendments G7 and G8](personal-food-catalogue-tables-composites-amendment-v1.md), proposed in #532).** G5b and section 3's third bullet are amended: another brand's product page may fill a composite dish at `low` with the fixed sentence (G7).

## 1. Why

G1 lets a national table's generic dish record fill a `packaged_composite` entry as a rough estimate.
Where no national table has a record for the dish, the entry stays empty, because import v1 decision 4
and the skill's owner ruling 6 keep every other recipe out of a composite dish. A nutrition database
page for the same kind of dish (an `aggregator` page) is the same kind of evidence as a national dish
record: a generic recipe, not this product's.

Counts only, from the owner's private catalogue on 19 November 2026 (836 entries): 31 of the 57
entries still missing energy, protein, fat or fibre are packaged composite dishes or unknown dishes
with no national dish record of their kind. On composite entries the file holds 778 national
estimates at `low`, 27 label photo estimates carried from a similar product at `medium` and one
manufacturer page estimate about the product itself at `medium`; it holds no `aggregator` estimate.

## 2. Amendment G5 (owner, 19 November 2026)

Amends import v1 decision 4, estimates v2 section 3.3 (one ceiling) and section 4 (the composite
sentence), and G1's builder rule. The rule is closed; changing it is a new dated amendment.

**G5a. A generic web page may fill a composite dish on G1's terms.** An `aggregator` estimate on a
`packaged_composite` entry with method `carried_from_similar_food` (relation `similar_food`) is
admitted only when its quality is `low` and its assumption contains the fixed sentence "A generic
recipe, not this product's."; otherwise the builder withholds it as `composite`, as G1 does for a
national record.

**G5b. Another product's page never fills a composite dish.** A `manufacturer_page` estimate on a
`packaged_composite` entry with method `carried_from_similar_food` is another brand's label (import
v1 decision 4 as amended by G1) and the builder withholds it as `composite`. The evaluator count
`composite_other_product_page` (such estimates in the file) must be zero.

**G5c. A page about this product is unchanged.** An `aggregator` or `manufacturer_page` estimate on a
composite entry with method `direct`, `carried_from_same_food` or `derived` describes this product
(a `derived` value is a transform of this product's printed value) and keeps every existing rule and
ceiling. The method is the owner's declaration on the review sheet, not proof, so "about this product"
stays an owner check.

**G5d. Codec ceiling.** Estimates v2 section 3.3 gains one ceiling: an `aggregator` or
`manufacturer_page` estimate with method `carried_from_similar_food` on a `packaged_composite` entry
is at most `low` (`estimate-quality`), beside G1's ceiling for a national record (any method). Label
photo estimates (`product_dataset_photo`) are outside G5: their composite rule (same brand and named
product only) and their `medium` cap are unchanged.

**Owner checks shown on the review sheet.** The codec and builder cannot read a page, so two
conditions stay with the owner, row by row: the page describes a generic dish of the same kind (a
generic dish record, not a branded product's entry), and the state the page describes is compatible
with the entry's. A page value still reaches the file only after the owner accepts its row
(estimates v2 section 4: `page_unconfirmed` values never reach a file).

**Searches.** Web searches for G5 are generic dish names with no brand, which
[privacy and egress](privacy-and-egress.md) already allows when the owner has asked for web search in
the session. G5 changes no egress. Tier advice from the OpenRouter classifier is not part of G5; any
G5 description sent there would need its own approved list.

**Compatibility and rollback.** No token, field, schema version, store, food contract or egress
changes.
- *An older build reading a G5 file:* a `low` aggregator estimate on a composite entry was already
  valid there, so it reads the file the same way.
- *A G5 build reading an older file:* a file holding an `aggregator` or `manufacturer_page` estimate
  with method `carried_from_similar_food` above `low` on a composite entry is now rejected whole with
  `estimate-quality`. The owner's file holds none (section 1), and no shared fixture does: the golden
  file's aggregator estimate on its composite entry is `derived`, about the product itself, and keeps
  `medium`. If such a file were already installed, the app re-reads it with the codec on every load,
  so Your food database would show no rows after the upgrade until a rebuilt file is imported; it
  fails closed and never reads a value differently. The remedy for any such file is to rebuild it.
- *Rollback:* rebuild the file without the G5 rows.

## 3. What does not change

- Unknown is never zero; no conversion of any kind is applied.
- A label value always wins; estimates are augmented, never measured, and can be left out on Confirm.
- Another brand's label (a manufacturer page or label photo of another product) never fills a
  composite dish.
- G1's national dish records, G2's per 100 ml rules, G3's photo re-admission and G4's own merge rule.
- Every estimate is accepted by the owner, row by row, with its tier shown.

## 4. Architecture gate

Blind `architecture-gate` review of the plan before code, 19 November 2026: BLOCK on one point (a cap
on every aggregator method would have changed the golden file and 15 accept fixtures), fixed by
scoping the cap to `carried_from_similar_food`; the other eight findings are addressed here.

- **Responsibilities.** The codec ceiling (`PersonalFoodDatabaseEstimates.ceiling`, domain) gains a
  `webSimilar` flag computed in `tableCodes` from the source type and method. The builder rule and
  counts live in the skill: `estimates_input.reason` (reason `composite`, no new reason),
  `estimate_counts` (`composite_above_low` and `composite_without_sentence` now cover national
  records and similar-food web pages; new must-be-zero `composite_other_product_page`). The Python
  codec mirror is `estimates_v2.ceiling` with `web_similar`.
- **Dependency direction.** Unchanged; the domain file imports Foundation only. No application,
  infrastructure or presentation change, and no new protocol.
- **Invariants.** Labels first; no another brand's label on a composite dish; no egress change; a
  file is rejected whole, never read differently.
- **Extension axes.** None added.
- **Contract tests.** Shared fixtures in `docs/fixtures/personal-food-database-estimates-v2/`:
  codec fixtures `reject-quality-composite-aggregator-similar-medium` and
  `reject-quality-composite-manufacturer-similar-medium` (`estimate-quality`), the accept fixture
  `accept-composite-aggregator-similar-at-low`; golden and every other fixture keep their bytes and
  codes (only `manifest.json` changes). App tests: the ceiling matrix (national any method `low`,
  similar web page `low`, a page about this product `high` or `medium` as before, a photo `medium`).
  Skill tests (`test_gap_amendments.py`): admitted at `low` with the sentence; withheld at `medium` or
  without it; a manufacturer page about another product withheld; pages about this product admitted
  with their ceilings; the codec rejection and count above `low`; a label value still wins; the
  ceiling and the new count.

## 5. Decisions

| # | Question | Decision |
|---|---|---|
| G5 | May a web page value fill a composite dish? | Yes, a generic dish page, on G1's terms (`low`, similar food, the fixed sentence); never another product's page. **Owner, 19 November 2026**: the web rule is relaxed for this case (the ready-meal rule). |
