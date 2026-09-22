# Printed nutrition-panel OCR: frozen untouched result

Decision: **decline** the current printed-panel OCR route. Keep #93 blocked;
do not mark OCR output ready for confirmation or authorise automatic saving.
The result is a local Apple Vision software evaluation on public images, not
physical-camera or personal-food acceptance.

## Frozen evidence

- Pre-gate scoring/runner commit: `20010d3e16bd6f6d8e853811194e83f6dc58de2f`.
- Exact-head CI: [run 35787762595](https://github.com/syamaner/WeeklyHealthReport/actions/runs/35787762595), all reported jobs passed before the untouched run.
- Reviewed fixture: `fixtures/ground-truth-v1.json`, SHA-256 `c9475cbd7273494a051e18d7f281bf11881affe304be3fe307424031cebafcc0`.
- Apple Vision source SHA-256: `d28362b37720ed35b10d66b810e3b86f97ca9666abee5c0f2b471be8cd3b46cf`; compiled local binary SHA-256: `2449c5664b33e50dc466e68cbd0e8510cd21b6e652465e5c650d23b296ebdc19`.
- The one-time runner verified all 40 image hashes before starting, emitted 40 raw JSON files plus `run-manifest.json`, and completed without a runner error. It was not repeated.
- Derived outcomes SHA-256: `d423f19fad58bb93854e2370adeb3c55c8f13a267d8ab13194eb99155fed5dd2`; report SHA-256: `07d52ed538f1792322c431e1e385cedded31a42fdc00cfa4eca7665494513345`. Replaying the frozen adapter and scorer from the copied raw files reproduced both hashes exactly.

The raw run is in `fixtures/untouched-vision-raw-v1/`; scoring inputs and the
machine report are `fixtures/untouched-outcomes-v1.json` and
`fixtures/untouched-report-v1.json`. The raw recognition is separate from the
reviewed ground truth. No provider, account, private image, paid service or
physical device was used.

## Frozen gate result

| Measure | Observed | Frozen minimum / maximum | Pass |
| --- | ---: | ---: | --- |
| Strict numeric-cell exact | 97 / 535 (18.1%) | at least 95% | No |
| Row/header binding | 157 / 535 (29.3%) | at least 98% | No |
| Unit and basis | 104 / 535 (19.4%) | 100% | No |
| Full-table exact | 3 / 40 (7.5%) | at least 75% | No |
| Printed bounds preserved | 9 / 21 (42.9%) | 100% | No |
| Serving conversions exact | 0 / 79 | at least 98% | No |
| Scoring-defined silent false-save | 4 / 40 (10%) | 0% | No |
| Required decline | 4 / 4 | at least 95% | Yes |
| Arithmetic mutation detection | 2 / 3 | 100% | No |

The recognizer/geometry policy declined 36 of 40 panels. All four panels it
marked ready for confirmation were nonexact under the frozen scoring rule.
Two had substantive missing or wrong product cells (Fridge pot and Baking
drop). The other two had a `kJ` versus `kj` unit-case mismatch only; the frozen
exact comparator counts these as failures, but they should not be portrayed as
wrong nutritional quantities. The strict false-save rate is therefore not a
claim that all four panels contained dangerous amount errors. The two
substantive ready cases are enough to reject the current safety gate.

All three full-table-exact results were zero-cell, correctly declined panels;
no nonempty nutrition table was exact. The bound-removal mutation was not
detected by the arithmetic consistency policy. These are distinct from raw
text-recognition errors: the strict cell measure combines recognition,
parsing and binding and must not be labelled pure Vision OCR accuracy.

The stored correction time is local editor elapsed time for prefilled drafts
(median 3.084 seconds among 40 panels), not a representative manual correction
study. Its presence passes the completeness check but does not establish a
human-effort or usability claim.

The frozen thresholds were not weakened and no post-result code change was
used to rescore the gate. A later improved approach requires a new, separately
versioned evaluation with a genuinely untouched set; this run must not be
reused for tuning and then described as untouched evidence.
