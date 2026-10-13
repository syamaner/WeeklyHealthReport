# Composite regional source order v9

Owner decision E on issue #140 (13 October 2026). This changes only the order in
which the local composite presents rows from the [Taiwan food catalogue](taiwan-food-catalogue-v1.md).

## Rule

`composite-generic-ranking-v9` takes default sources (CoFID, then USDA) and
regional sources (Taiwan TFDA). Unless Taiwan is promoted, every TFDA row
follows every UK and US row. The order is by source: no score, rank or
preference value is compared across sources to decide it.

`regional-source-order-v1` (`RegionalSourceOrderPolicy`) promotes Taiwan when
any of these holds:

- the Settings food market is Taiwan;
- the query names Taiwan as a word ("taiwan", "taiwanese");
- the query contains Chinese (Han) characters, for example 香蕉 or 芭樂.

When promoted, all three sources interleave exactly as in v8. The character
test is script-based, not language detection: any Han character promotes
Taiwan, including Japanese kanji and simplified Chinese. Japanese kana alone,
"Thai" and other words do not.

The rule sits inside the existing tiers. Preparation-verified rows still precede
unverified ones and requested-fat matches still lead their tier, so a verified
TFDA row can precede an unverified UK row. Within a tier, UK and US rows keep
their v8 interleaving and the shared ranking policy; TFDA rows keep their own
order after them. Exact saved reuse returns first, as before.

## What does not change

Retrieval, eligibility, source identity, provenance, nutrients and the
explicit Log action are unchanged. A Taiwan row is still a Taiwan composition
estimate and still needs the user's selection. No source is hidden; only its
position moves. The Settings market is read locally at search time and is not
sent anywhere by this rule (web lookup keeps its existing use of the market).

## Versions and stored values

`composite-generic-ranking-v9` is stamped on the capture evidence of new
composite searches. Stored records keep `composite-generic-ranking-v8` (or older)
and still decode, because the version is free text in the record. No schema,
archive or export format changes.

The evidence records the composite version, not whether Taiwan was promoted
for that search. Order is presentation only: it depends on the Settings market
at search time (and on the query text, which the evidence keeps), and the
saved record is the user's explicit selection, whatever its position was.
Reproducing an old list order therefore needs the market setting of the time,
which is not stored.

## Evaluation

Until now the CI replay used a two-source composite (CoFID and USDA), so the
production position of TFDA rows was never measured. `retrieval-scenarios-v5.json`
keeps the 80 v4 cases and adds seven (r081 to r087): three default-market cases (120 g banana,
banana, guava), two Taiwan-market cases (120 g banana, guava) and two Chinese
queries (香蕉, 芭樂). The v5 replay uses the production composite and replays each
case's market. Labels for the new cases come from `build_retrieval_v5.py`: plain
fruit is grade 3 for the default market and the TFDA reference is grade 2;
for the Taiwan market and Chinese queries the grades swap. Same-author
development labels, not independent acceptance.

Results (Python 3.12 scorer):

- v3 and v4 reports are byte-identical to the ranking v7 reports.
- Replay cost: the two-source rows for the v3 and v4 labels are derived from the
  regional composite row by removing TFDA records, which is exact for scored fields when Taiwan is
  not promoted (asserted for every v3 and v4 case and by a dedicated test).
- v5, composite, v8-equivalent to v9: hit@1 0.907 to 0.987, MRR 0.953 to 0.993,
  nDCG@5 0.942 to 0.976. The rice and banana families recover hit@1 from 0.0
  to 1.0 (TFDA "White rice, cooked" and the Beijiao banana no longer lead).
  The default-market family nDCG@5 rises from 0.787 to 0.938.
- Taiwan-market and Chinese-query cases are identical before and after.
- No summary metric decreased in any source or family.

For "120 g banana" the composite now starts with "Bananas, raw" (USDA), then
"Bananas, overripe, raw", then "Bananas, flesh only" (CoFID); the Taiwan
"Banana, Beijiao average" reference is last. `v9-reproduction-manifest.json`
binds inputs, sources, replay hashes and every changed observation.
