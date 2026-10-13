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

A part word counts only in closed animal-part positions, and only when the
user did not type it anywhere in the original text ("chicken liver", "roast
chicken with skin" are never penalised). The name is read one comma field at a
time:

- the whole primary name is a part ("Liver, chicken", "Giblets, chicken");
- the second field starts with a part ("Chicken, skin, roasted/grilled",
  "Chicken, skin (drumsticks and thighs), cooked", "Pork, fat, cooked");
- a field contains one of the part phrases "meat and skin", "lean and fat",
  "separable fat", "skin only" or "fat only".

A field never counts when it contains a weighing basis, a removal, a negation
or a fat-content word: `weighed`, `removed`, `excluding`, `without`, `no`,
`trimmed`, `free`, `reduced`, `content`, `low`, `lower`, `medium`, `high`,
`higher`, `extra`, `less`, `non`, `zero`, `half`, `full`, or a number. So
"fillets weighed with bones and skin", "skin and breading removed", "excluding
skin", "medium fat", "fat trimmed", "2% fat" and "trimmed to 0" fat" are not
parts.

Produce skin is part of the eaten food, not an animal part. "Apples, raw, with
skin", "flesh and skin" (potatoes, apples) and "includes skin" (plums,
cherries, apricots, courgette) are in none of the positions above and never
count. A poultry record cooked with its skin and eaten as meat only
("Chicken, breast, grilled with skin, meat only") does not count either.

The count is the number of distinct part words, so "meat and skin" counts once.

## What does not change

Primary-food, parenthetical and specialisation comparisons keep precedence.
Lexical eligibility, full meaningful-token coverage, preparation as a hard
constraint, source identity, evidence, nutrients and the explicit Log action are
unchanged. The policy still never selects or saves a candidate; it orders the
list the user chooses from. The positions are lexical: a part named in another
position (for example a third field that is only "skin") is not counted, which
keeps the rule narrow rather than complete.

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
cases byte-for-byte in content and adds eight: four unrequested-part cases
(150 g grilled chicken, grilled chicken, 200g roast chicken, 150g roast pork),
two requested-part cases (roast chicken with skin, chicken liver) and two
produce-skin cases (eating apple, 200g baked potato) where the skin-on record
is preferred. Labels
for the new cases come from the name rules in `build_retrieval_v4.py`, applied
to every record either ranking version retrieved. They are same-author
development labels, not independent acceptance.

Results (CoFID, USDA and the two-source composite, scored with Python 3.12):

- v3 labels: every summary metric equals the v6 report. Only the tails of four
  raw-ribeye observations change (a "lean and fat" record leaves rank 8).
  `retrieval-metrics-final-v7.json` is the new exact expected report.
- v4 unrequested-part family, ranking v6 to v7: composite hit@1 0.25 to 0.75,
  MRR 0.625 to 0.875, nDCG@5 0.540 to 0.869; CoFID hit@1 0.5 to 1.0, nDCG@5
  0.665 to 0.976; USDA nDCG@5 0.804 to 0.927. Incorrect part records at rank 1
  fall from 2 to 0.
- v4 requested-part and produce-skin families: identical before and after
  (produce-skin nDCG@5 1.0; "Potatoes, old, baked, flesh and skin" stays first).
- No summary metric in any source or family decreased.

`v7-reproduction-manifest.json` binds the inputs, source hashes, replay hashes
and the changed observations. The target query "150 g grilled chicken" now
starts with "Chicken, breast, grilled with skin, meat only", then "Chicken,
breast, grilled without skin, meat only" and the two USDA skinless breast
records in the composite; "Chicken, skin, roasted/grilled, moist" falls from
rank 1 to rank 5.

An earlier draft of this version counted any skin or fat word not preceded by a
short qualifier list. Invariant review found that it demoted produce skin and
missed several fat-content and removal wordings, so the closed positions above
replaced it before merge.
