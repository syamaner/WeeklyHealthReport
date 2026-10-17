# Nutrition-label capture evaluation

Evaluation-only harness for issue #255, following the owner-approved plan
[`docs/nutrition-label-capture-evaluation-v1.md`](../../docs/nutrition-label-capture-evaluation-v1.md).
It compares three routes that all emit the same `label-capture-candidate-v1`:
pasted text (A), on-device Vision (B) and a multimodal model through OpenRouter (C).
Nothing here ships product behaviour, saves food or treats any output as nutrition truth.
`Tools/FoodOCREvaluation/` stays frozen; its files are read, never edited.

Phase 1 had no AI or OpenRouter call and no Vision run. Phase 2 adds route B (Vision on development images only), the phase 1 review safeguards and the untouched truth drafting (decision A). Phase 3 records the owner's verification of the untouched Taiwan drafts (round 1), downloads and drafts the refills (round 2), gives the muesli photo every consent flag, and runs route C on **development photos only** (eight models in ten arms, reasoning off and on where the endpoint allows, under the owner's evaluation-only routing decisions of 17 October 2026).

## Framework: Inspect AI

The harness is built on [Inspect AI](https://inspect.aisi.org.uk/) (`inspect_ai`, the
UK AI Security Institute's evaluation framework), pinned in `requirements.txt` to
0.3.276 (released 2 October 2026) and installed into a local venv only:

```sh
python3 -m venv Tools/NutritionLabelCaptureEvaluation/.venv
Tools/NutritionLabelCaptureEvaluation/.venv/bin/pip install --require-hashes -r Tools/NutritionLabelCaptureEvaluation/requirements-dev.lock
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
  ($0.20 per call and $60 in total since the owner's decisions of 17 October 2026, with the
  200 sealed calls reserved at $0.20, $40; at most three unknown-cost calls, not counting
  retryable errors with no generation). Inspect's own `cost_limit` is per sample and priced from
  a model-cost table, so it is not used for these stops. `LedgerBudget` keeps that state in
  one ledger outside the repository (`~/WHR-label-eval-private/spend-ledger-v1.json`), so the
  total and the 200-call sealed reservation hold across separate runs, models and the drafting;
  it refuses changed limits (they change only through `amend_limits`, recorded in
  `limits_history`) and charges any call left unrecorded at the per-call ceiling.
- `openrouter_client.py` is the one OpenRouter client for route C and the drafting: retryable
  errors (transport, timeouts, 408, 429, 5xx, provider overloaded) are retried with exponential
  backoff and full jitter, honouring `Retry-After` (seconds or HTTP-date), for at most 5 attempts
  within 180 s; content outcomes are never retried. Every attempt is a ledger entry. Inspect's own
  retry is not used for route C (its backoff ignores `Retry-After` and the OpenAI SDK below it
  retries again), so route C runs on `mockllm/model` and posts through this client.
- `openrouter_route.py` accepts a response model only when it is the requested slug or that
  slug plus one dated snapshot suffix (`-YYYYMMDD`, `-YYYY-MM-DD`, `-MM-DD`, `-MMDD`); any other
  suffix or routing variant is a mismatch. A missing `finish_reason` fails the response.
- `cases.py` refuses the untouched set unless an explicit unseal flag and the sealed
  manifest's SHA-256 are both given and the contract is frozen.

## Layout

| Path | Role |
|---|---|
| `inspect_task.py` | Inspect tasks, route solvers (A, B and C; C on development photos only), the shared scorer and metrics |
| `route_c_mapping.py` | Route C wire output to `label-capture-candidate-v1` (no conversion or inference; unread values block ready) |
| `run_route_c.py`, `qualification/` | Route C on development photos per pinned model, after two fictional qualification labels; per-stratum summary with cost and latency |
| `vision_v3.swift` | Route B recogniser: Vision revision 3, accurate, `zh-Hant` and `en-US`, lines and token geometry |
| `serialise_lines.py` | Route B serialiser: geometry to parser text, binding by column header and order within a column |
| `run_route_b.py` | Route B on development photos through Inspect, per stratum; writes `results/` summaries |
| `draft_untouched_truth.py`, `openrouter/truth-drafting-*` | Decision A drafting of untouched truth (Qwen 3.5), journal, receipts, ledger, owner review sheet |
| `score.py` | Pure scoring with the frozen v2 matching rules; called by the Inspect scorer |
| `decline_gate.py` | Phase 4 decline gate: route-independent, declines or blocks ready, never changes a value |
| `rescore_development.py`, `uk_diagnosis.py` | Offline re-score of saved development outputs with the gate, and the UK diagnosis (no API call) |
| `arithmetic.py` | Section 7 checks (general, UK fibre and Taiwan fibre energy forms; kJ / kcal; serving scaling; sub-rows) and the three frozen mutations |
| `candidate.py`, `candidate-schema-v1.json` | Shared candidate schema and an offline validator |
| `budget.py` | Route C spend stops |
| `cases.py` | Development and untouched loaders, sealed-set guard |
| `frozen-contract-v1.json`, `validate_contract.py` | Bars, adequacy minima, tolerances, stops, selection and artefact hashes |
| `acquire_off_taiwan.py` | Open Food Facts Taiwan selection, revision pinning and download (outside the repository) |
| `ingest.py` | Muesli photo: private copy, metadata strip, hash, consent stub |
| `build_cases.py`, `synthetic/` | Deterministic pasted-text development cases |
| `run_route_a.py` | Route A through Inspect; writes `results/` summaries |
| `openrouter/` | Route C instruction and wire schema; truth-drafting instructions and schema |
| `openrouter_client.py` | The one OpenRouter client (retry policy, `Retry-After`, generation lookup) for route C and the drafting |
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
- **Refills** (owner decision B): up to 27 more photos, orders 61 to 87 in hash order, each
  downloaded only when an exclusion needs it (`acquire_off_taiwan.py refill`, a reason logged per
  order, 5 MB batch stop, 10 MB stop over all untouched refills). Development replacements came first:
  orders 61 and 62 replaced the English-only development orders 4 and 17 (427,244 bytes). Untouched
  refills 63 to 77 (5,776,668 bytes) replaced the 12 owner-confirmed exclusions and three refills
  that were themselves other-language labels; see [`results/untouched-truth-drafting-v1.md`](results/untouched-truth-drafting-v1.md).
- **Ground truth:** the 22 development records (20 plus 2 replacements, 2 excluded) are a
  Claude-drafted first pass awaiting the owner's second pass, so Claude Opus route C results
  on development data carry that caveat. Untouched truth (decision A) for the 40 untouched
  Taiwan photos was drafted on 17 October 2026 by Qwen 3.5 (`qwen/qwen3.5-397b-a17b` on
  `deepinfra/fp8`; OpenRouter lists no separate Qwen 3.5 VL), which is not a route C model.
  The owner verified round 1 on 17 October 2026 (527 of 527 cells confirmed, no corrections,
  so anchoring on the draft cannot be ruled out); the verified records are committed as
  `fixtures/ground-truth-off-taiwan-untouched-v1.json`, labelled model-drafted, owner-verified
  (no owner corrections), and pinned by hash in the contract. Round 2 (order 34 and the refills)
  awaits the owner. Drafts stay outside the repository. Route C never sees untouched truth or drafts.
- **Sealing:** the 40 untouched photos were hashed on download and written read-only
  to a separate `sealed/` folder. They were opened once, for the decision A drafting only
  (their unsealing for truth purposes); no route has recognised them.
- **Taiwan FDA dataset 188:** `fixtures/fda-188-source-v1.json` records the archive
  and CSV hashes and the Open Government Data License attribution.
- **Muesli photo:** stripped master and consent record under `owner/`; the owner set all four
  flags true on 17 October 2026 (every route, including OpenRouter); `consent-redacted-v1.json`
  holds hashes, flags and the date only.

## Local checks

```sh
python3 -m unittest discover -s Tools/NutritionLabelCaptureEvaluation/tests -v
python3 Tools/NutritionLabelCaptureEvaluation/validate_contract.py Tools/NutritionLabelCaptureEvaluation/frozen-contract-v1.json
swift test --package-path Packages/FoodLedgerKit --filter NutritionLabelParsingTests
```

The route B end-to-end tests in `tests/test_phase2.py` (serialiser, then the parser CLI) are **local only**: they need the built
`NutritionLabelTextParse` (`swift build --package-path Packages/FoodLedgerKit --product NutritionLabelTextParse`) and skip
without it. CI's label-capture job runs on Linux and does not build the Swift CLI, so they do not run there.

Static checks use the pinned dev tools (`requirements-dev.txt`: pyright 1.1.414, ruff 0.16.10), with `pyrightconfig.json` and `ruff.toml` in this folder so local imports resolve. Run them from this folder:

```sh
.venv/bin/pip install --require-hashes -r requirements-dev.lock
.venv/bin/ruff check .
.venv/bin/ruff format --check .
.venv/bin/pyright
```

`requirements-dev.lock` hash-locks every package (direct and transitive) with all published file hashes, so `pip install --require-hashes` works on macOS and Linux; regenerate it after changing a pin in `requirements-dev.txt`. CI runs the unit tests and contract validation with the system Python (no network), then installs the lock from PyPI and runs ruff, pyright and the full tests, including the Inspect wiring test. No step makes a model or provider call.

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

Route B on the development photos (Taiwan development photos, the 40 v2 public development
review images, and the muesli photo only with `local_routes` consent). The Vision binary is
built outside the repository; the UK review workspace is the main checkout's ignored folder:

```sh
xcrun swiftc -O vision_v3.swift -o ~/WHR-label-eval-private/bin/vision_v3
.venv/bin/python run_route_b.py \
  --vision-binary ~/WHR-label-eval-private/bin/vision_v3 \
  --parser-binary ../../Packages/FoodLedgerKit/.build/out/Products/Debug/NutritionLabelTextParse \
  --uk-workspace <checkout>/Tools/FoodOCREvaluation/review_workspace/v2_public_development \
  --log-dir ~/WHR-label-eval-private/runs/route-b-dev/<run> \
  --summary results/route-b-development-v1.json
```

Results: [`results/route-b-development-v1.md`](results/route-b-development-v1.md).

Untouched truth drafting (decision A) for the 40 untouched Taiwan photos, then the owner's
review sheet (`--sheet-only` rebuilds it from saved responses without a call):

```sh
.venv/bin/python draft_untouched_truth.py --env-file <dotenv with OPENROUTER_API_KEY> \
  --image-root ~/WHR-label-eval-private/off-taiwan-v1 \
  --out ~/WHR-label-eval-private/drafts/untouched-taiwan-v1 \
  --ledger ~/WHR-label-eval-private/spend-ledger-v1.json \
  --unseal-for-drafting --manifest-sha256 <contract manifest_sha256> \
  --model qwen/qwen3.5-397b-a17b --endpoint deepinfra/fp8 --provider-name DeepInfra
```

Record: [`results/untouched-truth-drafting-v1.md`](results/untouched-truth-drafting-v1.md).

Phase 3 additions to the same script, none of which makes a call: `--apply-owner-answers <folder>`
merges the owner's review-page answers (`oNN.json`) into `review.csv` through `merge_owner_entries`,
and `--write-truth <file> --verified-on <date>` writes the owner-verified truth from the drafts and
the sheet (only fully checked cases become records). `--bilingual-orders 34` drafts the listed
orders with `openrouter/truth-drafting-instruction-v1.2.txt` (contract `bilingual_instruction`).

Route C on development photos, one pinned model and reasoning setting at a time: eight models in
ten arms. The order run on 17 October 2026, cheapest first, was Luna (off, on), Luna Pro (off, on),
Grok 4.7 (on), Gemini 4 Argon (on), GPT-6.1 Sol (on), GPT-6.1 Sol Pro (on), Claude Opus 5.5 (on) and
Claude Fable 5.1 (on); reasoning off is not available on the last six (reasoning mandatory).
Fictional qualification labels are rendered first with
`xcrun swift qualification/render_qualification.swift <folder outside the repository>`. Before the
first call the runner reads the key's remaining limit and the account balance (both free) and
refuses an arm whose projected cost plus a margin (and any `--reserve-usd`) is not covered, or
when either lookup fails:

```sh
.venv/bin/python run_route_c.py --label luna --reasoning off --env-file <dotenv with OPENROUTER_API_KEY> \
  --ledger ~/WHR-label-eval-private/spend-ledger-v1.json \
  --log-dir ~/WHR-label-eval-private/runs/route-c-dev/luna-off \
  --qualification-dir <rendered labels> --uk-workspace <checkout>/Tools/FoodOCREvaluation/review_workspace/v2_public_development \
  --summary ~/WHR-label-eval-private/runs/route-c-dev/luna-off-summary.json --projected-cost-usd 0.1
```

Results: [`results/route-c-development-v1.md`](results/route-c-development-v1.md).

**Phase 4 (no API call).** `decline_gate.py` is the frozen, route-independent decline gate
(`label-capture-decline-gate-v2`; v1 is recorded in the contract); `decline_gate_solver` in `inspect_task.py` runs it after every
route's extraction. It can only decline or block ready, never change a value. The saved development
outputs of routes A, B and C are re-scored offline with it, and the UK stratum is diagnosed offline,
with no provider call:

```sh
.venv/bin/python rescore_development.py --runs ~/WHR-label-eval-private/runs --out results/gate-v2-rescore-v1.json --t1-log results/t1-uk-truth-changes-v1.json
.venv/bin/python uk_diagnosis.py --runs ~/WHR-label-eval-private/runs --out results/uk-diagnosis-v1.json
```

The owner amendments of 18 October 2026 (S1 scorer, M1 to M3 route C mapping, T1 UK truth
convention; contract `amendments_2026_10_18`) are re-scored the same way, with route C re-mapped from
its saved answers. Each result file is tied to the commit that wrote it, so a file is reproduced
only at that commit: `results/decline-gate-rescore-v1.json` (gate v1, pre-amendment) at `f313578c`,
`results/amendments-rescore-v1.json` (gate v1 with the amendments) at `ac584932`; the current
version writes `--out results/gate-v2-rescore-v1.json --t1-log results/t1-uk-truth-changes-v1.json`
and refuses to overwrite the two earlier files. `results/uk-diagnosis-v1.json` is the pre-amendment
diagnosis written at `5c3d1548`; rerunning `uk_diagnosis.py` now scores with the amended scorer.

`openrouter_client.http_post` enforces a whole-call deadline (a watchdog closes the socket when the
time left of the 180 s budget runs out). Results, gate rules and the UK diagnosis:
[`results/phase-4-decline-gate-and-uk-diagnosis-v1.md`](results/phase-4-decline-gate-and-uk-diagnosis-v1.md).

**UK images.** The v1 panel images are no longer on disk and the v2 public selection (60 tuning,
40 sealed) was never acquired, so the UK route B stratum is the 40 exposed v2 development review
images and there is no UK untouched stratum. UK untouched set deferred by the owner on 17 Oct 2026;
acquire a fresh sealed UK set only if Taiwan results justify it. Until then no promotion decision
for UK label photos.
