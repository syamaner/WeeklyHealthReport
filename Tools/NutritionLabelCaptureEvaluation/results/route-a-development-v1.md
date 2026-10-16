# Route A on development pasted text (phase 1)

Run on 17 October 2026 through Inspect AI 0.3.276 (`label_capture_route_a_development`,
nominal model `mockllm/model`, no model or network call). Parser
`nutrition-label-text-parser-v1` (Swift target `NutritionLabelParsing`). Dataset
`synthetic/development-cases-v1.jsonl`, SHA-256
`3247b8292f07a7c106265a94a9067c470cbcbaad2b8461522a6a412f0a31eb17`. Full numbers are in
[`route-a-development-v1.json`](route-a-development-v1.json); the `.eval` log is kept
outside the repository.

**This is a development result. It is not evidence for promotion.** The parser and the
renderer were developed together on these cases, and tuning on development cases is
what they are for. No untouched case was generated, opened or run.

## Cases

| Corpus | Cases | Source |
|---|---:|---|
| `v1` | 80 | Rendered from the reviewed v1 ground truth (all 100 panels exposed; 20 excluded, below) |
| `v2dev` | 22 | Rendered from the frozen 40-panel v2 public development review (its 22 usable tables) |
| `muesli_typed` | 1 | The owner's muesli label typed in Traditional Chinese (not synthetic) |
| `fda188` | 76 | 60 Taiwan FDA dataset 188 rows rendered in 營養標示 layout, plus 16 decline variants (Simplified Chinese or energy without a unit) |
| **Total** | **179** | 163 usable tables, 16 required declines |

FDA 188: 9,129 of 10,771 rows with structured per-serving values passed the
internal-consistency check (1,629 failed it, 13 were unstructured). The first 120 by
hash were taken; the hash split gave 60 development and 60 untouched. Only the 60
development rows were rendered; the untouched 60 are rendered only after the generator
is frozen.

English exclusions (38, never repaired): 33 panels whose image ground truth requires
a decline, 2 with two same-basis columns whose printed headers were not recorded,
2 with a blank amount cell and 1 whose header mixes bases.

## Result against the pass bars

| Metric | Result | Bar | Verdict |
|---|---:|---:|---|
| Strict numeric cell exact | 2,115 / 2,115 | at least 95% | pass |
| Row / header binding | 2,191 / 2,191 | at least 98% | pass |
| Unit and basis | 2,115 / 2,115 | 100% | pass |
| Full-table exact | 163 / 163 | at least 75% | pass |
| Serving conversions exact | 656 / 656 | at least 98% | pass |
| Servings per pack exact | 61 / 61 | at least 98% | pass |
| Printed bounds preserved | 58 / 58 | 100% | pass |
| Correct decline | 16 / 16 | at least 95% | pass |
| False-ready (silent false-save) | 0 of 179 | 0 | pass |
| Automatic persistence | 0 | 0 | pass |
| Arithmetic mutation detection | 103 / 115 (89.6%) | 100% | **fail** |

Energy cross-check (informing only): 153 pass, 26 not checkable, 0 fail.

Mutation detection by mutation: tenfold serving 87 / 90, basis transposition 14 / 16,
bound replaced by exact 2 / 9. As in the v1 gate, the arithmetic policy cannot see a
printed bound replaced by an exact value unless another column of the same row still
prints a bound, and a few tenfold or transposed values stay within printed rounding or
energy tolerance. This measures the arithmetic policy, not the parser, and it fails its
100% bar on development truth; it is reported, not weakened.

## Limits (repeat in every report)

- All English and FDA cases are synthetic, rendered in four known paste shapes each.
  They show the parser handles those shapes, not that real copied text arrives in them.
  Real pasted Taiwan text from web pages is unmeasured.
- The renderer writes every value as comparator, number and unit, so it never tests a
  unit printed only in a header.
- Renderer conventions, fixed on development data: a reference-intake cell takes the
  parent of its printed row (the v1 and v2 reviews recorded RI rows without a parent),
  and an energy %RI is keyed to kcal when kcal is printed.
- FDA 188 has no fibre column, so the Taiwan fibre energy form is exercised only by the
  muesli case.
- US English is not covered. A real US panel declines on `Calories 230` (no printed
  energy unit), as section 6 of the plan requires.
- Route A never sees a photo; the first-pass Taiwan photo ground truth is for routes B
  and C in later phases.
