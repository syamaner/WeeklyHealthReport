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

`corpus-feasibility-v1.json` records the current evidence boundary. A public
candidate pool of 140 distinct UK-tagged panel crops is available and the 83
tuning images have been run through the baseline. The 57-image untouched gate
has not been opened.

No available public source establishes the required exact visual transcript,
row/header relationships, conversions and correction time for 100 UK panels.
The reviewed Open Food Facts layout dataset labels nutrient entities in Google
OCR tokens; its checked flag is valuable semantic review but is not corrected
character truth. It contains only 92 checked `50…` barcode candidates before
UK country verification and only five such candidates in its test split.

Accordingly the reproducible result is **decline for insufficient ground
truth**. It does not score the baseline, weaken a threshold, consume the
untouched gate, authorize #93 or claim physical-camera validation. Completing
the gate requires an independently reviewed annotation pass and timed human
correction protocol over the hash-pinned images.
