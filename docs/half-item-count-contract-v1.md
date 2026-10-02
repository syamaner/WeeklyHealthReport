# Half-item count contract v1

A positive exact fraction of a recognised discrete item is an item count.
Capturing half an item does not establish a gram weight, edible fraction,
density, source serving or nutrient amount. Search may proceed and confirmation
may prefill the count; candidate selection and intake saving remain separate.

Food query parser v6 adds a bounded pepper-count grammar to the existing count
families. Optional size and colour/bell qualifiers are retained. Half, one-half
notation and decimal fractions are accepted; soup, sauce, household measures,
multiple foods, approximations and competing count/mass amounts remain
unresolved. Nonpositive or nonfinite counts are rejected. List lexical parser
v3 adds the standalone half glyph to its existing positive count/fraction syntax.
Mixed-number glyph syntax is not added to list parsing in this revision.

The architecture gate extends the pure parsers and uses existing application
orchestration. No provider, storage, conversion service or new domain type is
introduced. FoodConfirmationState retains 0.5 count without a conversion. The
existing FoodConfirmationService rejects count intake without an explicit
conversion; per-100g catalogue composition is not a consumed portion. Synthetic
regressions exercise real adapter handoff and a failed in-memory save, proving
that no intake row is created. No default portion weight is added.

Versions: food-query-parser-v6, food-list-lexical-v3,
cofid-generic-ranking-v10 and usda-generic-ranking-v11. Catalogue records,
source hashes, identity and quantity-conversion schemas remain unchanged.
The v4 cooking-method retrieval and typed preparation safeguards remain in force.

## Local evaluation run book

Run parser, confirmation, real-source and presentation contracts, then the full
package suite. Run the existing frozen 511-case synthetic parser gate against
parser v6; do not relabel old expectations to improve a score. New half-item
syntax is separately covered by synthetic unit contracts, not represented as
independent acceptance. Run the complete simulator suite and Xcode static
analysis once after production code stabilises; inspect `git diff --check` and
the final diff.

Private examples, labels and reports remain outside Git. Retain the paired
baseline, rerun all private suites under network denial with frozen labels and
source hashes unchanged, and report parsing, retrieval and count-confirmation
behaviour separately. An available candidate and a preserved fraction do not
prove edible grams or nutrition correctness. Personal saved-food reuse,
physical-device acceptance and independent user-labelled acceptance remain
separate evaluations.
