# Printed-panel OCR v2 development slice

Status: **evaluation-only, user-selection-only prototype**. No production
capture, populated confirmation, automatic persistence or #93 promotion is
authorised by this work.

## Architecture gate

The local Vision adapter continues to emit raw text and geometry. The new
`geometry_v2.py` is pure candidate interpretation; it does not read files,
call Vision or know a UI or persistence implementation. A future application
layer could present candidates beside the original image, but it must require
explicit field-by-field selection. Image identity, exact units and bounds,
unknown conversions, provenance and non-persistence must be closed invariants
in any production contract; this prototype alone does not enforce that full
contract.
The recognizer is the credible adapter seam; candidate interpretation can be
replaced only under the same fail-closed behavioural tests. The frozen v1
contract, runner, binder, scoring inputs and reported result are unchanged.

## Repairs and limits

- Adjacent comparator/number/unit pieces in one Vision observation are joined
  only when their boxes are close. This recovers straightforward split-token
  values such as `< 0.1 g` and `701 kJ` without joining distant columns.
  A combined `kJ/167` token is split into ordered energy units and values;
  parenthesised ordinary values are parsed without treating brackets as bounds.
- A nutrient label and value in separate nearby Vision observations may be
  paired when one label and one explicit column basis are unambiguous. Distant
  or competing label matches are skipped, not guessed.
- An energy number without an explicit unit is not offered as a cell. `kJ`
  casing is preserved for a proposed energy cell.
- Missing core rows, unbound printed bound markers and per-serving headers
  without an established conversion are visible warnings. No conversion is
  manufactured from a ratio or an unlabeled package quantity.
- Every candidate remains unapproved. Even a complete-looking table has an
  unresolved image-comparison requirement and cannot be marked ready or saved.

These changes do not solve OCR recognition, all row/header binding errors,
serving conversion extraction, physical capture or the absence of a fresh
independently reviewed corpus. They should not be integrated into a production
confirmation flow until that work and a separately versioned acceptance gate
are complete.

## Development-only check

The 40 previously exposed v1 gate outputs may now be used as regression
examples, **not** as a new untouched test. On those same raw Vision outputs,
v2 proposed 235 cells; the frozen strict cell comparator credited 141/535
versus v1's 97/535. Much of that difference is the `kJ` casing correction,
not improved numeric recognition. V2 still bound only 9/21 printed bounds
and 0/79 serving conversions. It marked 0/40 tables ready, including the four
v1 false-ready cases. This is a safety-policy observation, not a measured
false-save rate for new images or a promotion result.

Run the pure tests with:

```sh
python3 -m unittest discover -s Tools/FoodOCREvaluation/tests -v
python3 Tools/FoodOCREvaluation/probe_v2.py
```

Next evidence needed: freeze a v2 policy and scoring contract before observing
a new hash-pinned, independently transcribed public-panel gate. Keep any
physical-device or personal-case validation separate and explicitly approved.
