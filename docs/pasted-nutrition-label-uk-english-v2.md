# Pasted nutrition label, UK English v2 (plan draft, #371)

Status: **draft, 5 November 2026. Direction approved by the owner (decision 1); decisions 2 to 5 open; no architecture gate yet.** It follows the owner's decision of 5 November 2026 to hold UK English off release after the v1 release check, and to work on the reader first.

## 1. Where v1 stands

The v1 release check ([results](pasted-nutrition-label-uk-english-v1-release-check.md)) passed the bar, with zero wrong values in the 4 tables that reached Confirm. But 20 of 24 fresh labels declined (83%, against a goal of at most 25%), and the per-table limit rests on only 4 accepted tables. **Owner decision, 5 November 2026: do not ship v1; improve the reader, then run a new release check.** The P4 device step and P5 are not run for v1.

## 2. Development data

After the v1 run, the fresh set was probed to find the decline causes. That makes it development data, like the P1 set. v2 develops against both sets, 48 labels in all, kept in the private folders as before, and reports counts only. Neither set can measure v2. A new fresh set, collected and sealed under the same protocol, does that.

## 3. Decline causes found

Causes from a leave-one-line-out probe of each declined v1 fresh text, run on scratch copies, plus a reading of its structure and screenshot. A synthetic example shows each shape; none is real label text.

| # | Shape (synthetic example) | Fresh labels | Today's decline |
|---|---|---:|---|
| C1 | A pack-count line between the title and the heading: `Nutrition` / `. Contains 3 Servings` / `Typical values  Per 100g  Per 1/2 pot` | 3 | `multiple_panels` |
| C2 | A reference-value column (`RI*`, `your RI*`) printing `8400kJ / 2000kcal`, `70g` beside `%RI`, often with kJ and kcal in one cell | 4 | `count_mismatch` |
| C3 | A second table after the nutrition table: `Vitamins and Minerals` | 2 | `multiple_panels` |
| C4 | A one-cell-per-line layout: `Typical values` / `Per 100ml` / `Energy kJ` / `180` / `Energy kcal` / `43` ... | 3 | `duplicate_basis` 2, `too_little_read` 1 |
| C5 | A heading without the word "per": `Typical Values  100 ml  250 ml`, or a pack-count cell in place of `Typical values` | 2 | `no_basis_header` |
| C6 | A pack-count line after the table with trailing tabs: `Approximately 12 servings per pack` | 1 | `multiple_panels` |
| C7 | Two stacked complete tables with the same values, `Per 100g:` then `Per Serving:`, under a repeated title | 1 | `multiple_complete_panels` |
| C8 | A PDF whose two-column layout Preview copies with an unrelated block in between | 1 | `multiple_panels` |
| C9 | A header naming a prepared state: `Per 100ml as consumed`, `Per 100g microwaved`, `Per 4 pieces cooked` | 3 | `basis_state_not_supported` 2, `uk_orphan_unit` 1 |

Some labels need more than one fix: removing one cause can expose the next (two C1 labels and the C6 label move to `count_mismatch` when their line goes). The P1 set's 8 remaining declines are `basis_state_not_supported` 2, `count_mismatch` 2, `uk_orphan_unit` 2, `energy_without_unit` 1 and `value_without_unit` 1; v2 maps them to these causes during P1 below.

**C9 declines are correct today.** The identity rule (P2b) keeps a value for the food as prepared from being stored as the food as sold. v2 does not change that without a versioned identity contract (decision 3).

**C4 and C8 may depend on how the text was copied.** C4 came from scripted selections of grid layouts, and C8 from Preview's text order. Whether a Safari or iPhone paste of the same pages gives the same shape is not known. Decision 4 asks how to find out.

## 4. Proposed changes, in order of value

1. **C1 and C6, pack-count lines.** A line that only states a pack or serving count, before the heading or after the last row, binds as the pack count (or nothing) and never starts a panel.
2. **C2, reference-value columns.** A column whose heading names the reference intake itself (`RI*`, `your RI*`, `Reference Intake`) binds to `reference_intake` and never to an amount, and its cells never count toward the amount columns. The kJ/kcal-in-one-cell form is covered in the same step.
3. **C3, a following vitamins and minerals table.** A titled table naming vitamins and minerals, after a complete nutrition table, ends the reading; its rows are not read.
4. **C5, headings without "per".** `100 ml` or `100g` as a whole heading cell reads as per 100; a weight or volume with a serving word reads as per serving; a pack-count cell in the label column is ignored.
5. **C7, stacked duplicate tables.** Two complete tables with identical values for every row, one per 100 and one per serving, read as the first table; any difference still declines.
6. **C4, one cell per line.** Only if decision 4 shows real pastes keep this shape.

Each change is a parser or normaliser rule with positive and negative synthetic tests, under the same invariants as v1: no number, unit or comparator is ever invented, unknown is never zero, a misbinding always declines, and Taiwan readings stay byte-identical.

If every change works as planned, up to 17 of the 24 v1 fresh labels might reach Confirm (20 with change 6), against 4 today; the C8 label and the 3 C9 labels would still decline. That is an upper bound on development data, not a prediction: only the new fresh set measures v2.

## 5. Phases

1. **P1, specification and gate.** Map the P1 set's declines to the causes, write the v2 rule spec, and pass the architecture gate.
2. **P2, rules.** Implement changes 1 to 5 (and 6 if decision 4 says so), with synthetic tests. Re-run both development sets, reporting counts only.
3. **P3, freeze.** Freeze UK reader v2 and commit the fresh-set protocol, with the copy method settled by decision 4.
4. **P4, release check.** Collect, transcribe, verify and seal a new fresh set of 24, then do one run and the device step.
5. **P5, enable UK.** Only after P4 passes and the owner decides to ship, including the v1 P3 spec section 6 question.

## 6. Owner decisions

1. **Approve this plan's direction?** *Recommendation: yes.* **Decided (owner, in session, 5 November 2026): approved.**
2. **Keep the release bar and goals as v1** (zero wrong values gates; decline at most 25% and median burden at most 1 are goals)? *Recommendation: yes.*
3. **Leave prepared-state headers (C9) declined in v2?** *Recommendation: yes. Supporting them needs its own identity contract, with the food recorded as prepared.*
4. **How to settle the copy question (C4, C8)?** *Recommendation: before P3, the owner pastes 3 of the C4 pages from Safari on the iPhone into a note, without running the reader. The shapes are then compared, counts only. If a real paste gives tabs, C4 is a copy artefact and change 6 is dropped.*
5. **Collector for the v2 fresh set:** the v1 Amendment 2 scripted copy, or a real Safari copy by the owner? *Recommendation: decide after decision 4. If scripted selections differ from real pastes, the owner copies.*
