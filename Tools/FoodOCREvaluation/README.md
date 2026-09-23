# Printed nutrition-panel OCR evaluation

This directory is the reproducible, evaluation-only artefact for issue #88. It
does not ship product behaviour, authorize production OCR, save nutrition data,
contact a cloud OCR provider or establish physical-camera acceptance.

`frozen-contract-v1.json` fixes the population, split, metrics and promotion
thresholds before the untouched gate is observed. The corpus contains real UK
nutrition-panel crops selected from Open Food Facts. Open Food Facts product
fields and OCR sidecars are discovery aids only: a reviewer must transcribe and
visually verify every scored character and relationship against the source
crop.

## Architecture gate

- `acquire.py` is an infrastructure adapter. It discovers public candidates,
  records source attribution and hashes downloaded bytes. It cannot create
  ground truth.
- `vision.swift` is a recognizer adapter. It emits raw candidates, confidence
  and normalized geometry without deciding which nutrition cells are true.
  The frozen language is `en-US`, the English locale advertised by the current
  Vision revision; this is recorded rather than represented as British-English
  model support.
- `parser.py` is pure domain logic for labels, numbers, units, bounds, bases and
  deterministic arithmetic evidence. It never authorizes persistence.
- `evaluate.py` is application orchestration and scoring. It verifies fixture
  hashes and the frozen split before producing a recommendation.

Correctness, provenance, split assignment, units, bases, bounds, arithmetic
rules and the no-save policy are closed versioned invariants. Recognizer and
parser implementations are replaceable only if they emit the same raw/result
contracts and pass the same tests.

## Frozen workflow

1. Run candidate discovery and download only public selected nutrition images.
2. Reject non-UK, illegible, duplicate or non-panel images without looking at
   recognizer outcomes.
3. Record image SHA-256 and layout families. Split assignment is derived from
   the image hash and panel ID; it cannot be hand-picked.
4. Independently transcribe and verify ground truth. Candidate OCR or product
   fields may accelerate entry but are never truth.
5. Tune only on `tuning`. Freeze implementation hashes, then run
   `untouched_gate` once.
6. Report recognition, binding, unit, basis, bounds, conversion, arithmetic,
   decline, false-save and correction-time results separately.

The image source is licensed separately by Open Food Facts. The manifest must
retain image attribution and the source licence URL; downstream users must
review the applicable CC BY-SA and database terms before redistribution.

`ground-truth-schema-v1.json` requires the exact visible table transcript plus
every numeric cell's row, parent row, header, basis, printed text, comparator,
decimal text, unit and serving conversion. Verification is tied to the image
SHA-256 so a later image revision cannot inherit an earlier annotation.

## Local checks

```sh
python3 -m unittest discover -s Tools/FoodOCREvaluation/tests -v
python3 Tools/FoodOCREvaluation/validate_contract.py \
  Tools/FoodOCREvaluation/frozen-contract-v1.json
```

The evaluation intentionally fails closed until at least 100 independently
verified panels, including at least 40 untouched-gate panels and every required
family, are present.

## Current result

`corpus-feasibility-v1.json` preserves the earlier pre-review assessment. The
140-image public candidate pool supplied a hash-pinned 100-panel review set.
After the user-approved review and versioned language replacement,
`fixtures/ground-truth-v1.json` contains 100 image-bound reviewed annotations:
60 tuning and 40 untouched-gate panels, 1,389 structured cells and 15 recorded
declines. Its SHA-256 is
`c9475cbd7273494a051e18d7f281bf11881affe304be3fe307424031cebafcc0`.
The fixture passes the closed corpus and family-coverage checks. The one-time
untouched Apple Vision run has now completed. Its exact-head evidence,
threshold results, limitations and **decline** recommendation are in
[`untouched-gate-result-v1.md`](untouched-gate-result-v1.md). This does not
authorise #93 or automatic saving.

An isolated, evaluation-only v2 candidate prototype and its development-only
regressions are described in [`v2-development-notes.md`](v2-development-notes.md).
It does not change the frozen v1 result or establish a new acceptance gate.
The separate [v2 pre-gate plan](v2-pregate-plan.md) and `pregate_v2.py` audit
the unreviewed public-image inventory without running recognition or assigning
new gate status.

### V2 public-panel development review

`prepare_v2_review.py` creates a separate, image-first local review pack from
the 40 unused, hash-pinned public images. It excludes all selected/reviewed v1
images by ID and SHA-256, downloads only revision-pinned Open Food Facts image
URLs, checks every byte hash, and drafts text with local Tesseract only. It
does **not** run Apple Vision, assign a v2 gate split, or create verified truth.
The pack builder refuses to overwrite an existing review workspace.

From the repository root, prepare the ignored local workspace and start the
localhost-only reviewer:

```sh
python3 Tools/FoodOCREvaluation/prepare_v2_review.py \
  --candidate Tools/FoodOCREvaluation/fixtures/candidate-manifest-v1.json \
  --prior-selection Tools/FoodOCREvaluation/fixtures/review-selection-v2.json \
  --prior-truth Tools/FoodOCREvaluation/fixtures/ground-truth-v1.json \
  --workspace Tools/FoodOCREvaluation/review_workspace/v2_public_development
python3 Tools/FoodOCREvaluation/review_server.py \
  --workspace Tools/FoodOCREvaluation/review_workspace/v2_public_development \
  --port 8793
```

Open `http://127.0.0.1:8793/` in a browser on this machine. Port 8788 may
still host the older #88 review; do not mix the two workspaces. Review the image
itself, correct every draft character and structured cell, then check the
visual-verification assertion and save. Saves are local JSON files under
`annotations/`; reloading the page preserves them. If an image is unreadable
or the table is incomplete, mark a decline with a reason rather than inventing
values. These annotations are review inputs, not an accepted v2 evaluation:
the separate scoring contract and gate still need to be frozen before any
new gate run. The untouched personal/device case remains deferred.

## Human review pack

`prepare_review.py` deterministically selects 60 tuning and 40 untouched-gate
panels, then randomises their presentation order so the reviewer is blinded to
the split. It creates draft transcripts from three local Tesseract layouts.
Tuning cases may also use already-observed Apple Vision output; untouched cases
must not. `augment_review_with_off_ocr.py` may improve untouched drafts using
the public precomputed Open Food Facts OCR sidecar, which is independent of the
Apple Vision system under test.

The generated images, draft manifest and reviewer annotations live under the
ignored `review_workspace/`; they are not committed or uploaded. Start the
localhost-only editor with:

```sh
python3 Tools/FoodOCREvaluation/review_server.py \
  --workspace Tools/FoodOCREvaluation/review_workspace \
  --port 8788
```

The reviewer corrects the transcript and structured cells against each image,
tags visible layout families, records necessary declines and checks the visual
verification assertion. Saves are atomic and correction time is accumulated
per panel. The UI does not expose split or recognizer provenance.

After all 100 panels are reviewed, freeze the result before running any gate
recognition:

```sh
python3 Tools/FoodOCREvaluation/finalize_review.py \
  --selection Tools/FoodOCREvaluation/fixtures/review-selection-v2.json \
  --candidate-manifest Tools/FoodOCREvaluation/fixtures/candidate-manifest-v1.json \
  --workspace Tools/FoodOCREvaluation/review_workspace \
  --output Tools/FoodOCREvaluation/fixtures/ground-truth-v1.json
```

The finalizer fails closed for incomplete reviews, identity/hash/provenance
mismatches, split drift or any missing required family. It carries the
candidate's pinned public source and UK country tag into the scored fixture.
Only the resulting frozen fixture hash unlocked the one-time untouched Apple
Vision run; the recorded raw directory must not be reused as a fresh gate.

Before that run, `run_vision.py` verifies all 40 local image hashes, requires
the exact fixture SHA-256 and refuses a nonempty output directory. It writes a
run manifest before invoking Vision, so a partial run cannot silently be
repeated. `build_gate_outcomes.py` accepts only the matching raw run and the
frozen recognizer configuration. Pure scoring matches nutrient, parent row and
column basis; independently generated editor/recognizer header IDs do not
carry semantic identity. Repeated columns with the same row and basis are
ambiguous and receive no automatic credit.

The frozen arithmetic probes mutate three real untouched labels using the
contract seed. Their result measures the deterministic consistency policy,
not OCR recognition. The current policy detects the tenfold serving value and
swapped basis, but not removal of a printed bound. That miss remains visible
and cannot be counted as a pass or used to weaken the frozen 100% threshold.

### Source-language replacement before the gate

The reviewer excluded the bilingual KA Sparkling Fruit Punch image at review
index 3. `review-selection-v1.json` and its source image remain preserved. The
versioned `review-selection-v2.json` replaces only that untouched-gate slot
with the next hash-ranked, unused English-language candidate in the same split:
revision-pinned public Strawberry Milk image
`off:5000128605717:nutrition_en.10`. Its downloaded bytes match the candidate
manifest SHA-256. The replacement rule, reason and superseded selection hash
are recorded in v2; other review indices and their annotations are unchanged.

`replace_review_panel.py` reproduces this pre-gate replacement using the pinned
candidate manifest, v1 selection, local review workspace and downloaded image.
Its replacement draft was an assistant candidate, not ground truth. The
reviewer checked and saved index 3 against the image before finalization. The
versioned v2 selection and reviewed fixture, not the earlier 99 annotations
alone, were used for the one-time gate.
