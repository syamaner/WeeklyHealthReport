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
The fixture passes the closed corpus and family-coverage checks. This is a
ground-truth freeze, not an OCR accuracy result. The one-time untouched Apple
Vision gate remains unopened; #93 and automatic saving remain unauthorised.

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
Only the resulting frozen fixture hash may unlock the one-time untouched Apple
Vision run.

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
Its replacement draft is an assistant candidate, not verified ground truth.
Finalization must use v2 only after a reviewer has checked and saved index 3
against the image. No untouched Apple Vision run or promotion is authorised by
the existing 99 annotations alone.
