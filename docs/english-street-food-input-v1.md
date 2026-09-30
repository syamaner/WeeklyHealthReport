# English street-food input discovery v1

This slice extends the build-14 local-first search flow for English dish descriptions, including the user's Taiwan examples. It does not supply Taiwanese recipe nutrition, infer restaurant formulation, translate names or decompose a meal into confirmed ingredients.

## Architecture and contracts

`food-query-discovery-v3` adds bounded dish-with-ingredient descriptions to the existing discovery exception: pancake, dan bing, omelette, fried rice, beef noodle soup, dumplings, toast, sandwich, steak, bubble tea, milk tea and fried chicken, followed by a reviewed lexical ingredient list. Taiwanese/breakfast prefixes and the observed `scallion n pancake` wording are retained in retrieval, not silently corrected. These are search descriptions, not equivalence assertions. Existing lentil/tomato soup and porridge rules are preserved.

The parser's original text, tentative food/attributes, clarification route and nil quantity are unchanged. Multiple amounts, portions/counts, conflicting preparation, approximations, unsupported instructions, arbitrary extra meal items and unknown percentage scope gain no named-dish exception. Existing literal-percentage discovery remains separate; `50% sugar` is not reinterpreted as 50% fat or a confirmed sugar reduction. No default cup, egg count, cheese weight, oil or finished-dish yield is supplied.

The existing application coordinator sends the original displayed food description through enabled OFF then valid-BYOK Gemini ports. Services, privacy, cancellation, source-page budgets, source-admission and persistence contracts are unchanged. A provider that finds no match leaves the dish unresolved. No current source adapter is added for Taiwanese restaurants or street-food recipes.

`generic-representation-ranking-v4` and `food-lexical-terms-v6` normalise pancake/pancakes and syrup/syrups for retrieval. Meaningful non-ASCII letters survive tokenisation: mixed Chinese/English descriptions cannot match merely by dropping the Chinese food identity. This is conservative token preservation, not Chinese segmentation or translation.

The shared lexical food-form guard excludes unrequested syrup, mix and batter records from pancake retrieval. Explicit queries for those forms remain eligible. CoFID matcher v10, USDA matcher v11 and OFF capture method `off-search-candidates-v6` record the changed matching behaviour. OFF's nutrition projection/schema remains v5 because no nutrient or identity-field projection changes. Corpus bytes, source-release IDs, nutrient amounts and provenance are unchanged.

## Evaluation and limitations

The frozen 63-case development panel lives in the primary checkout under `Tools/LocalHybridSearchEvaluation/diagnostics/taiwan-input-v1/`. It includes the user's exact description and added examples, constructed English/dictation contrasts, ambiguous quantities and mixed-script controls. Initial outputs are retained. This is not an independent acceptance set, live-provider result or device test.

Synthetic ports prove original terms reach enabled layers without inventing a result. Actual OFF adapter fixtures separately check ingredient coverage, unknown preparation, explicit selection and rejection of incomplete food identities/product forms. The coordinator assumes an adapter has fulfilled its semantic admission contract; its shared contradiction check concerns structured identity metadata, not free-text name equivalence.

Local catalogue gaps remain for scallion pancake, bubble tea, oyster omelette, Fat Daddy fried chicken and steak with noodles and fried egg. `beef noodle soup` can find source-labelled canned soup alternatives; that does not establish a Taiwanese restaurant recipe. Standard pancake records are not established scallion-pancake equivalents. Larger bubble-tea sizes, half-sugar wording, custom exclusions, menu aliases and recipe/portion clarification remain follow-up work. Live grounded retrieval and new nutrition sources require separately bounded evidence; this slice does not claim them.

## Device checks after a later release

Search the complete breakfast description, `steak with noodles and fried egg`, and `bubble tea with tapioca pearls`. They should reach lookup instead of “search one food at a time”. With services disabled, an honest local miss is expected for these exact descriptions. With enabled services, source discovery can run; citation-only outcomes remain possible.

Search `pancake` and `pancakes`: the choices should agree and exclude syrup/mix/batter. `pancake syrup` must still find syrup. Search `蛋餅 cheese`: plain cheese must not appear through dropped characters. Neither these checks nor this implementation establish meal nutrition without explicit source/quantity review.
