# Integrated nutrition retrieval replay v6

This replay uses the unchanged 72-case v3 reference across CoFID, USDA and composite
(216 observations), on the current-main integration candidate. All aggregate metrics,
per-case outcomes, hit-at-1, hit-at-5, reciprocal rank, nDCG and top-five grade sequences
are identical to build 16's v5 baseline. Twelve full grade arrays differ beyond the
first five: eight ribeye source/case observations change tail ordering or membership;
four banana source/case observations omit an unrequested derivative. The reproduction
manifest records each before/after array. Neither judgement labels nor scorer changes.

The earlier comparison in the old checkout used v4 and showed a small banana nDCG
change. That is not the relevant build-16 comparison: current main includes a later
retrieval baseline. Both historical baselines remain unchanged.

The new v6 expected report is an exact reproducibility gate for the integrated
ranking versions, not a new independent quality threshold. The compressed raw replay,
input/source hashes and expected report are retained for reproducibility. CI runs the
actual adapters and compares its freshly scored result to v6. This does not validate
private examples, provider inference, source acquisition or real-user acceptance.
