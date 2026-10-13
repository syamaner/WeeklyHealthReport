# Generic food ranking v7: unrequested part words

Owner decision E on issue #140 (13 October 2026). This extends the shared
presentation policy in [generic retrieval policy v5](generic-food-retrieval-policy-v5.md);
everything that document keeps closed stays closed.

## Rule

`generic-representation-ranking-v7` adds one comparison to the shared lexical
preference. After the unrequested specialisation count and before the
unrequested form count, a candidate that presents an unrequested part word
ranks below one that does not. The part words are a closed list:

| Word | Why it is on the list |
|---|---|
| skin | Poultry and fish skin is sold and recorded separately and is much higher in fat than the meat it covers ("Chicken, skin, roasted/grilled"). |
| fat | Separable fat and "lean and fat" cuts differ materially from lean meat ("Pork, leg joint, roasted, lean and fat"). |
| giblets | Offal records share the animal's name but are a different food ("Giblets, chicken, boiled"). |
| liver | As giblets; the most common offal record in CoFID and USDA ("Chicken, liver, all classes, raw"). |

Other offal and parts (heart, kidney, bone, gizzard) were left out: they are
rare in these catalogues, their records already rank below the meat through
the primary-food rule, or they are a weighing basis ("weighed with bone")
rather than an eaten part. Widening the list needs a new version.

A part word counts only when the source name presents the part as present:

- a part the user typed anywhere in the original text is not penalised
  ("chicken liver", "roast chicken with skin");
- a part directly after `without`, `no` or `weighed` is not a part
  ("without skin", "weighed with skin");
- `fat` after a fat-content qualifier (`low`, `lower`, `reduced`, `less`,
  `non`, `zero`, `half`, `full`) or a number, or before `free`, is a fat
  content, not a part ("low fat", "2% fat", "trimmed to 0" fat", "fat free").

The count is the number of distinct part words, so "meat and skin" counts once.

## What does not change

Primary-food, parenthetical and specialisation comparisons keep precedence.
Lexical eligibility, full meaningful-token coverage, preparation as a hard
constraint, source identity, evidence, nutrients and the explicit Log action are
unchanged. The policy still never selects or saves a candidate; it orders the
list the user chooses from. A record cooked with its skin and eaten as meat only
("grilled with skin, meat only") still counts the part; this is a known
conservative imprecision, recorded rather than special-cased.

## Versions and stored values

`generic-representation-ranking-v7` is a code constant and is not persisted.
Because the shared policy changes adapter order, the adapter matcher versions
advance to `cofid-generic-ranking-v13` and `usda-generic-ranking-v14`. These
are stamped on new capture evidence and candidate match metadata only; stored
records keep the v12 and v13 values they were saved with and still decode,
because the version is free text in the record. TFDA ranking and the composite
are unchanged by this rule.

## Evaluation

`Tools/FoodSearchQuality/retrieval-scenarios-v4.json` keeps the 72 frozen v3
cases byte-for-byte in content and adds six: four unrequested-part cases
(150 g grilled chicken, grilled chicken, 200g roast chicken, 150g roast pork)
and two requested-part cases (roast chicken with skin, chicken liver). Labels
for the new cases come from the name rules in `build_retrieval_v4.py`, applied
to every record either ranking version retrieved. They are same-author
development labels, not independent acceptance.

Results (CoFID, USDA and the two-source composite, scored with Python 3.12):

- v3 labels: every summary metric equals the v6 report. Only the tails of four
  raw-ribeye observations change (a "lean and fat" record leaves rank 8).
  `retrieval-metrics-final-v7.json` is the new exact expected report.
- v4 unrequested-part family, ranking v6 to v7: composite hit@1 0.25 to 0.75,
  MRR 0.625 to 0.875, nDCG@5 0.540 to 0.820; CoFID hit@1 0.5 to 1.0; USDA
  nDCG@5 0.804 to 0.927. Incorrect part records at rank 1 fall from 2 to 0.
- v4 requested-part family: identical before and after (hit@1 1.0 in every source).
- No summary metric in any source or family decreased.

`v7-reproduction-manifest.json` binds the inputs, source hashes, replay hashes
and the changed observations. The target query "150 g grilled chicken" now
starts with "Chicken, breast, grilled without skin, meat only" in CoFID and the
composite, ahead of "Chicken, skin, roasted/grilled, moist".
