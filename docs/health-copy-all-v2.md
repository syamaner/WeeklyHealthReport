# Health Copy all text, version 2: the screen's wording

Version 2. Status: **decided under the owner's autonomous delivery approval for #308 (24 October 2026)**; the owner can revert it on the PR. It supersedes the "every other line is byte-identical" rule of [health-report-section-groups-v1.md](health-report-section-groups-v1.md) (v1.1, table row "Copy all") for section titles, row labels and footers only. Group order and group headings are unchanged.

## Why

The UX review of main 53450fb7 (#308) found Copy all naming metrics differently from the Health screen it copies: "Resting HR Average" against "Resting heart rate average", "Watch Data Coverage" against "Days with Apple Watch data", "Cardiorespiratory" against "Fitness and blood oxygen". Someone comparing the pasted text with the screen (README validation step 14) had to translate. Copy all text is not read back by the app, the export or any parser; it is a human-readable clipboard copy, so the wording can follow the screen.

## Rule

Copy all is the display document (`ReportDocument.forDisplay()`, `ReportDocument+Display.swift`) rendered as text:

- Preamble lines (title, selection, period, "Generated:") are unchanged.
- One capitalised heading line per group, as in v1.1.
- Each section block: the display section title, then `label: value` (or the value alone) for every row of the fully expanded document, then the display footer. The weight section therefore also carries the screen's note that the average uses the last 7 completed days.
- Values, row order and states are unchanged. A failed Apple Health read is "Could not read Apple Health." and a failed food log read "Could not read the food log.", as before; no technical message is copied.
- Names that come from Apple Health (workouts, medications) are never reworded, as on screen.

One table (`displaySectionTitles`, `displayRowLabels`) now feeds the screen, Full Page and Copy all, so they cannot drift.

## Unchanged

The Daily JSON export, its schema and bytes; Developer tools; the summary tiles (still never copied); every value, unit, rounding and day rule.

## Tests

`WeeklyReportScreenshotTests`: golden Copy all text with failed reads in v2 wording; Copy all equals the display document rendered line for line, with and without failures; no "Resting HR Average", "Watch Data Coverage" or "Query failed" in the copied text.
