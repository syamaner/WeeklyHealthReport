# Route A on development pasted text (phase 1)

Run on 17 October 2026 through Inspect AI 0.3.276 (`label_capture_route_a_development`,
nominal model `mockllm/model`, no model or provider call). Rerun in phase 2 with parser
`nutrition-label-text-parser-v2` (Swift target `NutritionLabelParsing`): every metric below is
unchanged against v1, and the number of tables the route would mark ready after the
arithmetic policy is 173 of 191 usable tables under both versions (an intermediate phase 2
build had dropped it to 146, mostly one-value-per-line pastes, which a zero false-ready
count did not show; the count is now reported in the summary). Dataset
`synthetic/development-cases-v1.jsonl`, SHA-256
`894a406d6e1a720b0712517beb59da3387171d7c3e6cedd46b2b7a7813175da8`. Full numbers are in
[`route-a-development-v1.json`](route-a-development-v1.json); the `.eval` log is kept
outside the repository.

**This is a development result, not evidence for promotion.** The parser and the
renderer were developed together on these cases, which is what development cases are
for. No untouched case was generated, opened or run.

Scoring now compares the printed unit text as well as the canonical unit, for strict cells
and for unit and basis (review fix 1).

## Cases

| Corpus | Cases | Source |
|---|---:|---|
| `v1` | 80 | Rendered from the reviewed v1 ground truth (all 100 panels were already exposed; 20 excluded, below) |
| `v2dev` | 22 | Rendered from the frozen 40-panel v2 public development review (its 22 usable tables) |
| `muesli_typed` | 1 | The owner's muesli label typed in Traditional Chinese (not synthetic) |
| `fda188` | 76 | 60 Taiwan FDA dataset 188 rows rendered in 營養標示 layout, plus 16 decline variants (Simplified Chinese, or energy without a unit) |
| `zh_template` | 28 | Seeded closed-template Taiwan tables for the tags FDA 188 lacks: 3 with bounds, 7 with 每日參考值百分比, 8 with 每100毫升, 7 single column, 3 with 本包裝含2.5份 |
| **Total** | **207** | 191 usable tables, 16 required declines |

**FDA 188.** 9,129 of the 10,771 rows with structured per-serving values passed the
internal-consistency check: 1,629 failed it and 13 were unstructured. The first 120 by hash
were taken, and the hash split gave 60 development and 60 untouched. Only the 60
development rows were rendered.

**Template.** 60 candidates were generated (12 per variant). The hash split gave 28
development and 32 untouched, and only the 28 development candidates were rendered.
Untouched generated cases are rendered only after the generators are frozen.

**English exclusions** (38, never repaired):

- 33 panels whose image ground truth requires a decline;
- 2 with two same-basis columns whose printed headers were not recorded;
- 2 with a blank amount cell;
- 1 whose header mixes bases.

## Result against the pass bars

| Metric | Result | Bar | Verdict |
|---|---:|---:|---|
| Strict numeric cell exact | 2,467 / 2,467 | at least 95% | pass |
| Row / header binding | 2,585 / 2,585 | at least 98% | pass |
| Unit and basis (printed and canonical) | 2,467 / 2,467 | 100% | pass |
| Full-table exact | 191 / 191 | at least 75% | pass |
| Serving conversions exact | 832 / 832 | at least 98% | pass |
| Servings per pack exact | 89 / 89 | at least 98% | pass |
| Printed bounds preserved | 70 / 70 | 100% | pass |
| Correct decline | 16 / 16 | at least 95% | pass |
| False-ready (silent false-save) | 0 of 207 | 0 | pass |
| Would mark ready after arithmetic (reported, not gated) | 173 of 207 cases (191 usable) | n/a | n/a |
| Automatic persistence | 0 | 0 | pass |
| Arithmetic mutation detection | 133 / 145 (91.7%) | 100% | **fail** |

The energy cross-check informs only and never gates: 181 pass, 26 not checkable, 0 fail.

**Mutation detection by mutation:**

| Mutation | Detected |
|---|---:|
| Tenfold serving | 108 / 111 |
| Basis transposition | 20 / 22 |
| Bound replaced by exact value | 5 / 12 |

**Effect of decision Q1** (for a Taiwan label that prints a fibre row, use only the Taiwan
energy form). On the same 163 tables as the earlier run, detection is unchanged at 103 / 115.
The rise to 133 / 145 comes only from the 28 template tables.

The arithmetic policy still cannot see a printed bound replaced by an exact value unless
another column in the same row still prints a bound. A few tenfold or transposed values also
stay within printed rounding or the energy tolerance. This measures the arithmetic policy,
not the parser. It fails its 100% bar on development truth, and the failure is reported, not
weakened.

## Chinese coverage tags (plan section 3.1)

The Chinese pasted-text development cases (105) now cover:

- `zh_hant`
- `two_column_serving_and_100`
- `single_column`
- `reference_intake_column`
- `per_100ml`
- `bound`
- `sodium`
- `serving_line`
- `servings_per_pack` (including 2.5)
- `nested_rows`
- `decline_expected`
- `synthetic`

Not covered:

- `salt`: Taiwan labels print 鈉, not salt.
- `en_uk`: English, by definition.
- `column_offset`, `glossy`, `curved_or_crumpled`, `small_font`: these describe photos and
  cannot apply to pasted text.

Bounds remain thin, at 3 template cases.

## Limits (repeat in every report)

- All English, FDA and template cases are synthetic, rendered in four known paste shapes
  per language. They show that the parser handles those shapes, not that real copied text
  arrives in them. Real pasted Taiwan text from web pages is unmeasured.
- The renderer writes every value as comparator, number and unit, so it never tests a unit
  that is printed only in a header.
- Two renderer conventions were fixed on development data:
  - a reference-intake cell takes the parent of its printed row, because the v1 and v2
    reviews recorded RI rows without a parent;
  - an energy %RI is keyed to kcal when kcal is printed.
- FDA 188 has no fibre column. The Taiwan fibre energy form is exercised by the muesli case
  and by the template tables that print fibre.
- US English is not covered. A real US panel declines on `Calories 230` because no energy
  unit is printed, as section 6 of the plan requires.
- Route A never sees a photo. The first-pass Taiwan photo ground truth is for routes B and C
  in later phases.
