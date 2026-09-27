# Expectation revisions before integration

Cases nlp-252 through nlp-256 now retain unresolved words and search without guessing a correction or brand. Explicit mass is preserved for review; retrieval may miss. No correction from break to bread, why to whey, or haas to Hass is inferred. This is a corrected specification, not a parser success on the original labels. The original v1 fixture is unchanged. Mixed vegetable proportions and ambiguous count/mass remain clarification cases.

Unknown words do not in themselves make a clearly stated amount unsafe: selection and confirmation remain mandatory. The original reported unsafe-prefill count was overbroad for these cases. Reports pin fixture hashes so revisions cannot be mistaken for performance gains on fixed labels.

Corrected an erroneous generated 1g expectation for “1 pretzel”: this is one count. Canonical sesame names now consistently use singular seed across all scenarios.

## v5 correction

`nlp-444` (three boiled eggs) omitted the explicit boiled preparation in v4.
Only v5 corrects this annotation; v4 and its first-run/repaired reports remain
retained. This improves strict attribute scoring, not routing or quantity.
