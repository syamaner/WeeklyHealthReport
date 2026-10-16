# Nutrition-label capture evaluation

Evaluation-only harness for issue #255, following the owner-approved plan
[`docs/nutrition-label-capture-evaluation-v1.md`](../../docs/nutrition-label-capture-evaluation-v1.md).
It compares three routes that all emit the same `label-capture-candidate-v1`:
pasted text (A), on-device Vision (B) and a multimodal model through OpenRouter (C).
Nothing here ships product behaviour, saves food or treats any output as nutrition truth.
`Tools/FoodOCREvaluation/` stays frozen; its files are read, never edited.

Phase 1 (this folder as first committed) has **no AI or OpenRouter call and no Vision run**.

## Framework: Inspect AI

The harness is built on [Inspect AI](https://inspect.aisi.org.uk/) (`inspect_ai`, the
UK AI Security Institute's evaluation framework), pinned in `requirements.txt` to
0.3.276 (released 2 October 2026) and installed into a local venv only:

```sh
python3 -m venv Tools/NutritionLabelCaptureEvaluation/.venv
Tools/NutritionLabelCaptureEvaluation/.venv/bin/pip install -r Tools/NutritionLabelCaptureEvaluation/requirements.txt
```

Why Inspect: it gives datasets of `Sample`s with targets and metadata, pluggable
solvers (one per route), custom scorers and metrics shared by every route, epochs
for the stability probe, provider-agnostic model calls (including `openrouter/...`
with a provider block), per-sample limits with token and cost accounting, and a
log viewer (`inspect view`) for side-by-side comparison of runs.

The considered alternative was promptfoo. It was not chosen because its assertions
are oriented to per-output pass or fail, which makes the plan's micro-averaged,
multi-denominator metrics (cells, bindings, bounds, conversions, declines,
false-ready) awkward to express, and because it has no natural place for a sealed
untouched set that refuses to load without a hash-bound unseal.

Where Inspect does not enforce a plan rule natively, a small wrapper does:

- `budget.py` enforces the route C stops on the cost OpenRouter reports per response
  ($0.05 per call, $25 in total including the reserved sealed-run budget, at most
  three unknown-cost calls). Inspect's own `cost_limit` is per sample and priced from
  a model-cost table, so it is not used for these stops.
- `cases.py` refuses the untouched set unless an explicit unseal flag and the sealed
  manifest's SHA-256 are both given and the contract is frozen.

## Layout

| Path | Role |
|---|---|
| `inspect_task.py` | Inspect tasks, route solvers (A live, B reserved slot, C defined but disabled), the shared scorer and metrics |
| `score.py` | Pure scoring with the frozen v2 matching rules; called by the Inspect scorer |
| `arithmetic.py` | Section 7 checks (general, UK fibre and Taiwan fibre energy forms; kJ / kcal; serving scaling; sub-rows) and the three frozen mutations |
| `candidate.py`, `candidate-schema-v1.json` | Shared candidate schema and an offline validator |
| `budget.py` | Route C spend stops |
| `cases.py` | Development and untouched loaders, sealed-set guard |
| `frozen-contract-v1.json`, `validate_contract.py` | Bars, adequacy minima, tolerances, stops, selection and artefact hashes |
| `acquire_off_taiwan.py` | Open Food Facts Taiwan selection, revision pinning and download (outside the repository) |
| `ingest.py` | Muesli photo: private copy, metadata strip, hash, consent stub |
| `build_cases.py`, `synthetic/` | Deterministic pasted-text development cases |
| `run_route_a.py` | Route A through Inspect; writes `results/` summaries |
| `openrouter/` | Route C instruction and wire schema, drafts, never sent in phase 1 |
| `fixtures/` | Taiwan photo manifest, FDA 188 source record, first-pass Taiwan development truth |

The parser under evaluation is the Swift target `NutritionLabelParsing` in
`Packages/FoodLedgerKit` (Foundation only, enforced by `check-boundaries.sh`), so the
evaluated code is the code that would ship. `NutritionLabelTextParse` is its
evaluation CLI (stdin JSON to stdout JSON; it adds the input hash with CryptoKit so
the parser itself stays pure).

## Data and privacy

Nothing personal or downloaded is committed: only hashes, manifests, hand-checked
values and synthetic text. Image bytes, the FDA archive, Inspect `.eval` logs and the
muesli master live under `~/WHR-label-eval-private/` (outside any checkout).

- **Open Food Facts Taiwan photos** (owner-approved, 17 October 2026): 60
  `nutrition_zh` photos, 28,851,427 bytes, re-derived from Search-a-licious
  `countries_tags:"en:taiwan"` ordered by SHA-256 of the 13-digit barcode; it matched
  the candidate list exactly. Orders 1 to 20 are development, 21 to 60 untouched.
  Each photo is CC BY-SA 3.0; `fixtures/off-taiwan-manifest-v1.json` records the
  barcode, pinned revision, URL, SHA-256, uploader and attribution.
- **Sealing:** the 40 untouched photos were hashed on download, written read-only
  to a separate `sealed/` folder and have not been opened, viewed or recognised.
- **Taiwan FDA dataset 188:** `fixtures/fda-188-source-v1.json` records the archive
  and CSV hashes and the Open Government Data License attribution.
- **Muesli photo:** stripped master and consent stub (all four flags `false`) under
  `owner/`; `consent-redacted-v1.json` holds hashes and flags only.

## Local checks

```sh
python3 -m unittest discover -s Tools/NutritionLabelCaptureEvaluation/tests -v
python3 Tools/NutritionLabelCaptureEvaluation/validate_contract.py Tools/NutritionLabelCaptureEvaluation/frozen-contract-v1.json
swift test --package-path Packages/FoodLedgerKit --filter NutritionLabelParsingTests
```

The contract pins artefact hashes. After a deliberate development change, re-pin with
`--pin` (refused once the contract is `frozen_for_untouched_run`).

Route A on the development cases:

```sh
swift build --package-path Packages/FoodLedgerKit --product NutritionLabelTextParse
cd Tools/NutritionLabelCaptureEvaluation
.venv/bin/python run_route_a.py \
  --parser-binary ../../Packages/FoodLedgerKit/.build/out/Products/Debug/NutritionLabelTextParse \
  --log-dir ~/WHR-label-eval-private/runs/inspect-route-a \
  --summary results/route-a-development-v1.json
```

Results and their limits are in [`results/route-a-development-v1.md`](results/route-a-development-v1.md).
