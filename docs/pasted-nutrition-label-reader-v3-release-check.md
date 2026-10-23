# Pasted nutrition label reader v3: release check results (#93)

Results of the release check on a fresh set of Taiwan labels, step 5b of [`pasted-nutrition-label-reader-v3.md`](pasted-nutrition-label-reader-v3.md) (sections 7.4 and 12.2), which is the release gate of [`pasted-nutrition-label-v1.md`](pasted-nutrition-label-v1.md) section 9 for Taiwan. Under section 12.3 this file holds counts only: no label text, product name, page address, transcription, per-label result or hash. Everything else stays in the private run folder outside the repository.

## Protocol record

| Item | Value |
| --- | --- |
| Freeze reference | `bbb833f3`, the merge commit of [PR286](https://github.com/syamaner/WeeklyHealthReport/pull/286) on `main` |
| Rule amendments before the text seal or seal 2 | Amendments 1 to 3 to the selection and scoring rules: [PR290](https://github.com/syamaner/WeeklyHealthReport/pull/290), [PR291](https://github.com/syamaner/WeeklyHealthReport/pull/291) and [PR297](https://github.com/syamaner/WeeklyHealthReport/pull/297) (scorer Amendment 3, merged before seal 2) |
| Text seal | Recorded before the run, 22 October 2026 |
| Seal 1 (blind transcription) | Recorded before the run, 22 October 2026 |
| Seal 2 (owner-verified transcription) | Recorded before the run, 24 October 2026 (local), covering 24 labels |
| Owner verification | Complete for 24 labels and 396 transcribed items, with 3 transcription corrections |
| Run | 24 October 2026, one run, no reruns |

## Collection

| Count | Value |
| --- | ---: |
| Labels collected | 24 |
| Retailer pages | 23 |
| Manufacturer pages | 1 |
| PDFs | 0 |
| Results opened | 2,181 |

Labels by category: snacks 4, drinks 4, cereal 3, sauces and condiments 3, dairy 2, instant noodles 2, confectionery 2, nuts 2, bread 1, frozen 1.

Skips by reason (2,157 in all): `no_nutrition_table` 1,139, `wrong_category` 699, `not_source_kind` 213, `development_set` 47, `table_image` 27, `supplement` 20, `other` 10, `duplicate` 1, `non_taiwan` 1.

## Results (section 12.2.8)

**The bar passes: zero wrong values in every table that reached Confirm.**

| Measure | Value |
| --- | ---: |
| Labels | 24 |
| Reached Confirm | 11 |
| Declined | 13 |
| Basis choices needed | 4 |
| Values checked | 136 |
| Wrong values | 0 |
| Tables with a wrong value | 0 |
| Calculated vs printed discrepancies | 0 |
| Rows "Printed but not read" | 0 |
| Correction burden, median | 0 |
| Correction burden, mean | 0.364 |
| Share of tables needing any correction | 0.182 |

Declines by reason: `multiple_panels` 5, `count_mismatch` 2, `no_basis_header` 2, `basis_not_sure` 2, `flattened_table_ambiguous` 1, `multiple_complete_panels` 1.

**Statistical limit (rule of three).** With 136 values checked and none wrong, the per-value wrong-value rate is below 3/136 = 0.022 with 95% confidence; with 11 tables reaching Confirm and none wrong, the per-table rate is below 3/11 = 0.273. Neither is a claim of a zero rate.

### Goals that do not gate release

| Goal | Result | Status |
| --- | --- | --- |
| Decline rate at most 25% (decision 16) | 54% (13 of 24) | Missed |
| Median correction burden at most 1 | 0 | Met |

Missing the decline goal does not block release when the bar passes (section 12.2.8); it informs the next reader version.

## Deviation from the protocol

Section 12.2.6 describes the owner review page as a local file that is never published. At the owner's request, the page was additionally published as a private claude.ai artifact visible only to the owner, and deleted after seal 2. The owner completed the check on the local page.

## Owner decision (24 October 2026)

Ship reader v3 now. The declines are followed up in reader v4, [#301](https://github.com/syamaner/WeeklyHealthReport/issues/301).

Only counts and rules were added from the real-text sets; no text, value, product name or hash.
