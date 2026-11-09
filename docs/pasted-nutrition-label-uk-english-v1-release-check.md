# Pasted nutrition label, UK English v1: release check results (#371, P4)

Results of the harness step of the UK release check, phase P4 of [the UK English plan](pasted-nutrition-label-uk-english-v1.md), run under the protocol of the [P3 spec](pasted-nutrition-label-uk-english-v1-p3.md) section 4 (adapted from reader v3 section 12.2). As in the [Taiwan release check](pasted-nutrition-label-reader-v3-release-check.md), this file holds counts only: no label text, product name, page address, transcription, per-label result or hash. Everything else stays in the private run folder outside the repository.

The device step (the `#if DEBUG` switch and a Debug build on the owner's iPhone, plan decision 9) was not run: the owner decided not to ship v1 (see the end of this file).

## Protocol record

| Item | Value |
| --- | --- |
| Freeze | `UKReaderFreezeTests` and `ReaderV3FreezeTests`, added by [PR388](https://github.com/syamaner/WeeklyHealthReport/pull/388); both passed at the run commit |
| Run commit | `ec93271`, `main` on 5 November 2026, from a clean checkout |
| Amendments before the text seal | Amendment 1 (collectors fixed per site, agent copy method), in [PR388](https://github.com/syamaner/WeeklyHealthReport/pull/388); Amendment 2 (scripted selection for web pages, after the agent's copy did not reach the system clipboard), [PR394](https://github.com/syamaner/WeeklyHealthReport/pull/394). Both were committed before any label page was opened |
| `other` skips | 6, all listed to the owner and confirmed before the text seal |
| Text seal | 5 November 2026, 24 texts |
| Seal 1 (blind transcription) | 5 November 2026, before the run, 24 files |
| Seal 2 (owner-verified transcription) | 5 November 2026, before the run, covering 24 labels |
| Owner verification | Complete for 24 labels, with 0 transcription corrections |
| Run | 5 November 2026, one attempt, no reruns |

## Collection

| Count | Value |
| --- | ---: |
| Labels collected | 24 |
| Retailer pages | 23 |
| Manufacturer pages | 0 |
| PDFs | 1 |
| Results opened, or judged from their result line | 536 |

Labels by category: biscuits and crisps 3, soft drinks 3, cereal 3, ready meals 3, milk and yoghurt 2, sauces 2, frozen 2, confectionery 2, bread 2, instant noodles 1, nuts and dried fruit 1.

Skips by reason (517 in all, a few logged per site rather than per result): `no_nutrition_table` 259, `not_source_kind` 213, `development_set` 15, `non_uk` 12, `wrong_category` 10, `other` 6, `blocked` 1, `duplicate` 1.

Collectors and copy method:

- **Collectors.** The agent collected from every retailer and from Google until Google showed it a traffic-verification page at slot 22. Under Amendment 1, Google then moved to the owner in a Safari private window for slots 21 to 24. No retailer blocked the agent.
- **Copy method.** 23 texts are scripted selections in the built-in browser (Amendment 2 item 1). 1 is a Preview system copy of a PDF. A scripted selection is the text a selection gives, not a paste from Safari or the iPhone, so line breaks and tab placement can differ from a real paste. Every rate below carries that caveat.

Fallbacks used:

- **`kind_fallback` for 8 slots.** The 5 manufacturer slots (16 to 20) had no eligible page on a brand owner's own site. Of the 4 PDF slots, slots 21 to 23 had no eligible PDF in their first 30 results: most results were restaurant menus, US sources, research or health guidance. These slots were filled by the retailer procedure. Slot 24 took a UK retailer's product sheet.
- **Fallback 3 (re-walk)** and **fallback 4** were not needed.

## Results

**The bar passes: zero wrong values in every table that reached Confirm.**

| Measure | Value |
| --- | ---: |
| Labels | 24 |
| Panels, by title | 24 UK declarations; 0 US Nutrition Facts; 0 other English |
| Reached Confirm | 4 |
| Declined | 20 |
| Basis choices needed | 0 |
| Values checked | 58 |
| Wrong values | 0 |
| Tables with a wrong value | 0 |
| Calculated vs printed discrepancies | 0 |
| Rows "Printed but not read" | 0 |
| Correction burden, median | 0 |
| Correction burden, mean | 0.250 |
| Share of tables needing any correction | 0.250 |

Declines by reason: `multiple_panels` 7, `count_mismatch` 4, `duplicate_basis` 2, `no_basis_header` 2, `basis_state_not_supported` 2, `multiple_complete_panels` 1, `too_little_read` 1, `uk_orphan_unit` 1.

No flags or warnings were shown on the 4 labels that reached Confirm.

| Also reported | Value |
| --- | --- |
| Residual errors after the owner's check | 0 (no wrong value in accepted tables) |
| Disputes raised after the run | None |
| Device-build outcome compared with the harness | Not run: v1 is not shipped |

**Statistical limit (rule of three).** With 58 values checked and none wrong, the per-value wrong-value rate is below 3/58 = 0.052 with 95% confidence. With only 4 tables reaching Confirm, the per-table rate is below 3/4 = 0.75. The table-level limit is weak: the zero rests on very few accepted tables. Neither figure is a claim of a zero rate.

### Goals that do not gate release

| Goal | Result | Status |
| --- | --- | --- |
| Decline rate at most 25% | 83% (20 of 24) | Missed |
| Median correction burden at most 1 | 0 | Met |

Missing the decline goal does not block release when the bar passes. It does mean that, as read today, about four in five real UK pastes would be declined. How much of that comes from the scripted selection rather than from the labels cannot be told from these counts. These texts have now been read by the reader, so any rule shaped by their declines turns them into development data; a later reader version needs a new fresh set.

## Deviations from the protocol

- **Downloads of approved PDFs.** The built-in browser saved a PDF as a download rather than showing it, and the protocol does not let the collector fetch files any other way. With the owner's approval of each file, the coordinator downloaded the 4 approved files with a plain HTTP download into the private folder, without opening them, and recorded size and hash; the collector then judged each one in Preview. The coordinator is not independent of the reader, but a plain download involves no choice.
- **Google results read from the owner's pastes.** For slots 21 to 24, the owner pasted Google's results pages from Safari. The coordinator numbered the organic results in order without judging them, and the collector judged each one. Where Google's order had changed since the first load, the first load's order stood (reader v3 section 12.2.3). The owner opened one result in Safari and pasted its text, and the collector judged that result from the paste.
- **One refused run attempt.** The run step refused to start in a checkout with an untracked folder, before reading any text and without writing the run log. The run then went ahead from a clean checkout at the same commit.

## Owner decision (5 November 2026)

Do not ship v1. The decline rate is too high for UK support to be useful, so the reader is improved first and measured again on a new fresh set. The device step and P5 are not run for v1. The follow-up is the [UK English v2 plan](pasted-nutrition-label-uk-english-v2.md). The fresh set was probed after the run to find the decline causes, so it is now development data.

Only counts and rules were added from the real-text set; no text, value, product name or hash.
