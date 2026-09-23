# Printed nutrition OCR v2: pre-gate evidence plan

Status: **development preparation only**. This is not a frozen v2 acceptance
contract, a ground-truth review, a gate result, or authority to ship OCR.

## Evidence boundary

The 100 image identities in `review-selection-v2.json` and
`ground-truth-v1.json` are excluded from a fresh v2 acceptance set. Their
images, Vision outputs, annotations and v1 outcomes have already been exposed
to development. `pregate_v2.py` audits by both panel ID and image SHA-256 and
rejects duplicate, unpinned or unsupported images. It does not run OCR or
assign a new split.

The pinned candidate manifest contains **40 other images**: 23 labelled
`tuning` and 17 labelled `untouched_gate` by the old v1 split. Those old split
labels are descriptive only. They do not make any image a v2 gate case. A new
gate needs a separately versioned, predetermined selection rule, adequate
coverage, verified image bytes and independent visual ground truth before
the v2 recognizer runs. If 40 of these are selected for review, there is no
remaining reserve for exclusions or unreadable images; acquire additional
public, immutable, no-login images before claiming a robust gate.

## Contract to freeze before seeing new outcomes

- Define the candidate output schema: image identity, exact printed value,
  comparator, unit, nutrient/parent, column basis, explicit serving quantity
  when actually printed, and a distinct `unknown` state. Preserve a bound as
  a bound; never derive a product amount from a reference-intake constant.
- Define matching and denominators separately for numeric cells, bounds,
  units/bases, row/header relationships, serving conversions, complete tables
  and decline decisions. An unknown conversion is not an exact match and is
  not silently removed from the denominator.
- Define safety gates before testing: no automatic save; candidates require
  field-by-field user selection against the source image; incomplete or
  ambiguous tables cannot be marked ready. Score false-ready proposals
  separately from automatic persistence. A zero false-ready observation on a
  finite set is not proof of a zero real-world rate.
- Freeze thresholds, family coverage, source licences, panel exclusions,
  hash-pinned split and one-time gate procedure in a versioned contract.
  Run implementation tuning only on designated development panels.
- Record reviewer identity/time and image hash with each exact visual
  transcription. The draft OCR and contributor metadata are hints, not
  evidence of printed characters. Reviewers must inspect the image itself.
- Keep an untouched personal/device validation gate explicitly deferred.
  Public-image success would not establish physical-camera or personal-case
  performance, and no production promotion follows automatically.

## Next bounded action

Acquire more public revision-pinned image candidates, verify downloaded bytes
against their recorded hashes, and prepare a blinded visual-review pack with
no v2 Vision outputs. A human review must correct and sign off each panel's
ground truth before freezing and running a separate v2 gate. Until then,
`geometry_v2.py` remains evaluation-only and user-selection-only.

Inventory command (prints identities only; does not download or run OCR):

```sh
python3 Tools/FoodOCREvaluation/pregate_v2.py \
  --candidate Tools/FoodOCREvaluation/fixtures/candidate-manifest-v1.json \
  --prior-selection Tools/FoodOCREvaluation/fixtures/review-selection-v2.json \
  --prior-truth Tools/FoodOCREvaluation/fixtures/ground-truth-v1.json
```
