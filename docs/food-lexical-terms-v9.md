# Food lexical terms v9: rule-based plurals

Approved by the owner on 13 October 2026 as part of the UX revamp programme (#140). Based on search ranking v7 / composite v9 / query parser v8 (PR #232), which was still open when this work started.

## Problem

Food search requires every meaningful query term to occur in a source name. Before v9 the shared lexical policy (`food-lexical-terms-v8`) only knew a closed list of about forty plural and singular pairs, so a plural that was not on the list never met its singular, and the other way round. "almonds" is the reported case: the query parser already hands retrieval "almond", while CoFID spells "Almonds, whole kernels" and USDA "Nuts, almonds", so neither catalogue found its plain almonds. "guava" missed USDA "Guavas, common, raw", "sheep milk" missed CoFID "Milk, sheeps, raw", and "cashews" and "pistachios" found nothing in USDA, which spells them "cashew nuts" and "pistachio nuts".

v9 folds plural forms to a singular with a small set of deterministic rules and a closed exception list. The same function runs on query terms and on source-name terms, so a folded form only has to be consistent, not dictionary-correct.

## Architecture gate

- **Responsibilities.** `FoodLexicalPlurals` (application layer, pure Swift, no Foundation) owns the rules, the exception list and the version. `GenericFoodRankingPolicy.terms` applies it to every retrieval term before the existing v8 equivalents; `literalTerms` keeps the v8 terms. Catalogue adapters (CoFID, USDA, TFDA) and the shared ranking preference use the folded terms. Original text, evidence, source names, identity and nutrients are never rewritten.
- **Dependency direction.** Unchanged. The new type depends on nothing; infrastructure adapters call the application policy as before. No framework, model, network or persisted format is added.
- **Invariants.** Unknown is never zero; full meaningful-term coverage is still required; preparation is still a hard constraint; nothing is selected or saved automatically; the explicit Log action is unchanged. Folding changes which names count as covering a query, never what a record is.
- **Extension axes.** New exceptions or rules need a new lexical version. Other adapters adopt folded terms only with their own version bump.
- **Contract tests.** `FoodLexicalPluralsTests` (rules, exceptions, look-alike words, non-ASCII and numeric terms, idempotence, symmetric query and source terms, the same-number preference); `LexicalPluralRetrievalTests` (actual bundled adapters, the list-import route and the exception words); the ranked retrieval replay against frozen expected reports.

Apple's NaturalLanguage framework, or any other operating-system model, is not used at run time. It was used once, offline, as a second opinion in the audit below.

## Rules

`FoodLexicalPlurals.singular(_:)` takes one lowercase term after diacritic folding. In order:

1. A term in the exception list returns its listed value.
2. A term that is not plain ASCII letters (numbers, mixed tokens, Chinese) or is shorter than four letters is unchanged.
3. A term ending in `-ss` (glass, cress, bass, grass, swiss) or `-us` (hummus, couscous, asparagus, citrus) is unchanged.
4. `-ies` becomes `-y` when the term has at least five letters: berries to berry, anchovies to anchovy. "pies" is too short for this rule and loses only its s.
5. `-oes` becomes `-o` when the term has at least five letters: tomatoes, potatoes, mangoes.
6. `-sses`, `-xes`, `-ches`, `-shes` and `-zzes` lose `-es`: glasses, mixes, peaches, sandwiches, radishes.
7. Any other final `-s` is removed: almonds, walnuts, lentils, olives, cheeses, kiwis, pistachios.

`-ves` is never folded to `-f` or `-fe` by rule, only through the exception list. Rule 6 narrows the approved "-es after s and z" to doubled `ss` and `zz`, because the audit showed that most food words ending in `-ses` or `-zes` are a singular `-se` or `-ze` plus s (cheeses, rinses, glazes). The folding is idempotent and every exception value is a fixed point; both are tested.

Folding runs before the closed v8 equivalents, so "roasts" and "roast" both become "roasted", "slices" becomes "sliced" and "garbanzos" becomes "chickpea" exactly as before.

## Exception list

| Group | Entries |
|---|---|
| Irregular `-ves` | leaves to leaf, loaves to loaf, halves to half, calves to calf (knives is not food and is not listed) |
| Singular ends in `-ie` or `-i` | cookies, brownies, smoothies, veggies, calories, crunchies (Crunchie), chillies to chilli, chilies to chili |
| Singular ends in `-che` or `-sse` | quiches, brioches, ganaches, mousses |
| Singular ends in `-oe` | sloes, roes, aloes |
| Only look plural (names, places, dishes, Latin and French terms) | molasses, haggis, basis, christmas, texas, thomas, madras, pancreas, gras, haas, gris, frais, physalis, tennis, diabetes, testes, trans, eccles, atkins, mars, always, kudos, horlicks, salmis, oikos, species |
| Plural noun whose singular is a different everyday adjective | greens, sweets, crisps |

The owner's list is covered by these entries and by rule 3: hummus, couscous, asparagus, citrus, swiss, bass, grass and cress are protected by the `-ss` and `-us` rule; molasses and haggis are listed; lentils to lentil is an ordinary fold. "brussels" is folded to "brussel" on both sides, which also lets the common spelling "brussel sprouts" match. The last group stops a search for spring greens, sweets or crisps widening to every record that contains the adjective green, sweet or crisp.

## Same-number preference (ranking v8)

Folding lets a plural query reach names that use the singular only as a modifier: "walnuts" now also retrieves "Oil, walnut", and USDA's own walnuts are named "Nuts, walnuts, ...", so neither name is the primary food. Without a tiebreak the shorter oil name ranked first. `generic-representation-ranking-v8` adds one lexical preference directly after the primary-name check: a name that spells a query term in the same number as the original query text precedes a name that matches it only after folding. "walnuts" therefore lists "Nuts, walnuts, english" before "Oil, walnut", and "almonds" lists "Nuts, almonds" before almond milk and almond butter. The original request text decides the number, because the query parser may already have turned "almonds" into "almond". A primary-name match keeps precedence, so "Guavas, common, raw" still leads a search for "guava". This orders the list the user chooses from; it never establishes identity.

## Scope

- **Changed:** CoFID, USDA and TFDA catalogue retrieval and ranking, the shared ranking preference (and therefore the order of composite rows), typo suggestions built from catalogue vocabulary, and the part-word comparison (a named "giblet" now matches a "giblets" part).
- **Unchanged:** the query parser (`food-query-parser-v8` keeps its own bounded singular list), the list grammar (`food-list-lexical-v5`), and every live source: Open Food Facts search and transport, the Oatly, Arla and Alpro admissions, manufacturer page identity and the Auntie Emily recipe admission. These call `literalTokens`, the v8 terms, so their matching and page-identity checks are byte-for-byte as before. Folding them needs their own version bumps and is not part of this change.

## Audit

Method, run once on 13 October 2026 with `Tools/FoodSearchQuality/lexical-v9-audit/`:

1. `vocabulary.py` collected every lowercase ASCII word in the bundled CoFID, USDA and TFDA names (TFDA aliases included) and in the queries of `retrieval-scenarios-v6.json` and `synthetic-v7.json`: 3,507 words.
2. `main.swift`, compiled offline with `FoodLexicalPlurals.swift`, compared each rule output with the NaturalLanguage lemma of the word in a carrier sentence ("I bought some ... today."), and listed every pair of distinct vocabulary words that fold to the same term. The tool is never linked into the app or the package.
3. Every disagreement and every merge was reviewed by hand. Output: `lexical-v9-audit/audit-output.txt`.

Results with the final rules: the rules change 541 words. The lemmatiser agrees on 447. For 80 it gives no lemma (brands, compounds and non-English words such as allsorts, beansprouts, krispies, pepitas and tamarillos); each was read and folds consistently. The first round found these rule faults, now fixed by exceptions: chilies (rule gave "chily"), crunchies (an `-ie` singular, like the pre-seeded cookies, brownies and calories, which the audit confirmed), species, the look-alike words in the table above (basis, christmas, madras, pancreas, physalis and others) and the three adjective nouns. The remaining disagreements are accepted because both sides fold identically and no other food word collides: brussels, chapatis (lemma "chapatti", a spelling variant), chitterlings, crosscuts, entrees, frijoles, giblets, lychees (lemma "litchi", a synonym), nopales, oops, pasties (lemma "pastie"; "pasty" is the British singular), popeyes, spareribs and wieners. All 324 remaining merges pair a word with its own plural. The review excluded greens, sweets and crisps, where the plural noun and the singular adjective name different things often enough to widen a search. Others where the meanings differ a little (tenders, thins, browns, grands, kids) were kept: they occur in brand or cut names where the singular is the same food, and full term coverage plus the primary-name preference keep them behind the requested food. Fries with fry, chips with chip and halves with half are intended.

## Versions and stored values

- `food-lexical-terms-v9` (`FoodLexicalPlurals.version`) and `generic-representation-ranking-v8` are code constants and are not persisted.
- The adapter matcher versions advance to `cofid-generic-ranking-v14`, `usda-generic-ranking-v15` and `tfda-reviewed-ranking-v2`. They are stamped on new capture evidence and candidate match metadata only. Stored records, evidence and archives keep the v13, v14 and v1 values they were saved with and still decode, because the version is free text in the record. TFDA rows did not change in any replayed scenario, but TFDA aliases such as "mushrooms" and "noodles" now meet singular queries, so its result sets can change.
- `composite-generic-ranking-v9` is unchanged: the composite's source order and interleaving rules are the same, and its rows change only through the adapters and the shared preference, as in ranking v7.
- `food-query-parser-v8` and `food-list-lexical-v5` are unchanged.

## Evaluation

Frozen sets are not edited. `Tools/FoodSearchQuality/retrieval-scenarios-v6.json` keeps the 87 v5 cases and adds 18 (`build_retrieval_v6.py`): plural nuts (almonds, walnuts, cashews, hazelnuts, pistachios, peanuts), pulses (lentils, chickpeas), produce (tomatoes, potatoes, berries, blueberries), quantities (30 g almonds, 100g walnuts) and the look-alike words (hummus, couscous, asparagus, molasses). "a handful of almonds" reaches search as "almonds" through `food-list-lexical-v5`; `LexicalPluralRetrievalTests` checks that route end to end ("Almonds, whole kernels" first in the composite, "Nuts, almonds" present). New labels come from the name rules in `build_retrieval_v6.py`, applied to every record either lexical version retrieved. For five earlier cases (oats, 100g oats and the two default and Taiwan-market guava cases) v9 retrieves records that no frozen label covered; only those records are graded, by the rule that labelled the case, and recorded under `labelExtension`. Every existing grade is kept. These are same-author development labels, not independent acceptance.

`Tools/FoodQueryEvaluation/synthetic-v7.json` keeps the 523 v6 cases and adds 19 plural cases (`build_v7.py`) that pin the food text the unchanged parser hands to retrieval. First and final run: routing 542/542, quantity 542/542, search cases with every field correct 372/372, no unexpected prefills. The one field difference is the tentative food on the clarify case "a handful of walnuts", which is not scored by the gate. The v6 gate still passes with predictions byte-identical to `predictions/v6-final.json.gz`.

Retrieval results, v8 to v9, scored with Python 3.12:

| Scenario set and labels | Source | hit@1 | hit@5 | MRR | nDCG@5 |
|---|---|---|---|---|---|
| v3 (72 cases), frozen | CoFID | 0.976 to 1.000 | 0.976 to 1.000 | 0.976 to 1.000 | 0.929 to 0.952 |
| | USDA | 0.933 unchanged | 1.000 | 0.967 | 0.976 unchanged |
| | Composite | 1.000 | 1.000 | 1.000 | 0.984 to 0.990 |
| v4 (80 cases), frozen | CoFID | 0.980 to 1.000 | 0.980 to 1.000 | 0.980 to 1.000 | 0.937 to 0.956 |
| | USDA | 0.924 unchanged | 1.000 | 0.962 | 0.970 unchanged |
| | Composite | 0.985 unchanged | 1.000 | 0.993 | 0.977 to 0.983 |
| v5 (87 cases), frozen | CoFID | 0.981 to 1.000 | 0.981 to 1.000 | 0.981 to 1.000 | 0.942 to 0.960 |
| | USDA | 0.928 unchanged | 1.000 | 0.964 | 0.972 to 0.956 |
| | Composite | 0.987 unchanged | 1.000 | 0.993 | 0.976 to 0.979 |
| v6 (105 cases), extended | CoFID | 0.941 to 1.000 | 0.941 to 1.000 | 0.941 to 1.000 | 0.905 to 0.975 |
| | USDA | 0.872 to 0.930 | 0.930 to 1.000 | 0.901 to 0.963 | 0.909 to 0.960 |
| | Composite | 0.944 to 0.989 | 0.956 to 1.000 | 0.950 to 0.994 | 0.913 to 0.958 |

The CoFID gain in v3 to v5 is "sheep milk" now finding "Milk, sheeps, raw". The only decrease is USDA nDCG@5 on the frozen v5 labels, and it is a labelling gap rather than a ranking loss: v9 finds "Guavas, common, raw" and "Guavas, strawberry, raw" for "guava", the frozen v5 labels never saw them, and the scorer counts an unlabelled record as 0. With those two records graded by the v5 rule (v6 labels), USDA "guava" rises from nDCG@5 0.23 to 1.0 and hit@1 from 0 to 1. On the v6 labels no case in any source loses hit@1, hit@5 or nDCG@5. The plural families, v8 to v9: nuts hit@1 CoFID 0.60 to 1.00, USDA 0.50 to 0.83, composite 0.50 to 1.00; quantities 0.50 to 1.00 in every source; pulses and the look-alike words unchanged; produce nDCG@5 up in USDA and the composite ("berries" finds more mixed-berry products, all graded as mentions). The remaining USDA nuts miss at rank 1 is "cashews", where "Nuts, cashew butter, plain" outranks "Nuts, cashew nuts, raw" through the existing plain-representation bonus; before v9 USDA found nothing for "cashews". Pistachios still find nothing in CoFID, which has no pistachio record.

CI now verifies the v3, v4 and v5 rows against `retrieval-metrics-final-lexical-v9.json`, `retrieval-metrics-v4-final-lexical-v9.json` and `retrieval-metrics-v5-final-lexical-v9.json`, and the v6 rows against `retrieval-metrics-v6-final-lexical-v9.json`; `retrieval-metrics-v6-baseline-lexical-v8.json` scores the v6 labels on the v8 replay. The previous expected reports stay in the repository and still reproduce from the v8 code. `lexical-v9-reproduction-manifest.json` binds the inputs, source and replay hashes. The replay test now covers 105 cases.

## Limitations

The rules are English and lexical. They do not know that "fries" in "French fries" and "fry" in "stir fry" are different foods, or that strawberry guava is a different species; full term coverage, the ranking preference and the user's explicit choice remain the safeguards. Irregular plurals outside the exception list (for example "geese") fold wrongly but consistently on both sides. The audit covers the bundled catalogues and the evaluation queries, not every word a user may type. Live sources keep v8 terms until they are versioned. No device, HealthKit or live-provider check is claimed.
