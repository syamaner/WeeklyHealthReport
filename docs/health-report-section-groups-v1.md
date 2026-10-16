# Health report section groups v1 (#216)

Version 1.1. Status: **approved by the owner, 16 October 2026; every decision in section 6 takes its recommended option. Amended by the owner, 16 October 2026: every group has a heading** (decision 3; review and QA found that without headings, standalone sections read as part of the group above them). Deferred from UX revamp phase 7 ([ux-revamp-phase-7-health-export.md](ux-revamp-phase-7-health-export.md)); wireframe `designs/ux-revamp-v1/Health.dc.html` (Activity, Body, Heart and sleep).

The Health report's sections are put under a few named groups and reordered. **No metric, value, period, row id, row label or section title changes.** The only text changes are the order of the section blocks and new group heading lines.

## 1. Today

`ReportDocument.SectionID` (`Presentation/ReportDocument.swift` lines 4 to 15), in order:

steps, weight, bodyComposition, heart, bloodPressure, cardiorespiratory, glucose, activity, sleep, medications (the last only when the medication section is included).

Copy all titles: Steps, Weight, Body Composition, Heart, Blood Pressure, Cardiorespiratory, Glucose, Activity, Sleep, Medications Taken. Full Page uses the display titles (`ReportDocument+Display.swift`), where cardiorespiratory reads "Fitness and blood oxygen".

## 2. Groups and order

| Group (heading) | Sections, in order |
|---|---|
| Daily activity | Steps, Activity |
| Food and water (only if #214 is approved) | Food and water, standalone |
| Body | Weight, Body Composition |
| Heart and sleep | Heart, Blood Pressure, Sleep |
| Fitness and blood oxygen | Cardiorespiratory, standalone |
| Glucose | Glucose, standalone |
| Medications | Medications Taken, standalone, when included |

- Every group with at least one present section has a heading, including a group with a single section (v1.1). Without it, Fitness and blood oxygen, Glucose and Medications would read as part of Heart and sleep, and Food and water as part of Daily activity. A group with no present section (Medications when that section is not included) shows nothing.
- The group is called "Daily activity", as in the README's "What it reports" table, so it never collides with the existing "Activity" section title (decision 2).
- Food and water stands alone, not inside Daily activity, so logged food energy is never shown as part of an activity group beside active energy. There is no net or balance.
- Groups are headings only. The disclosure unit stays the section (`expandedSections: Set<SectionID>` is unchanged), and tiles are unchanged.

## 3. Consistency

| Surface | Change |
|---|---|
| Health screen | Sections in the new order, with a group heading above each group, in primary-colour text distinct from section headers |
| Copy all | Section blocks in the new order. Before each group, one heading line in capitals (`DAILY ACTIVITY`, `BODY`, `HEART AND SLEEP`, `FITNESS AND BLOOD OXYGEN`, `GLUCOSE`, `MEDICATIONS`) as its own block (decision 3). Every other line is byte-identical |
| Full Page | The screen's order and headings in display wording |
| Developer tools | Unchanged order (decision 4). It reads model states, not `ReportDocument` |
| Daily JSON, stored records | No change |

Copied text changes in order and gains up to six heading lines. That is the whole change. Anyone who parses copied text by section title keeps working; anyone who relies on block order does not, which is why this needs approval.

## 4. Day rules, states and units

Unchanged. Grouping is presentation of existing sections: completed-day periods, latest-measurement lookbacks, unknown and empty states, rounding and units are exactly as now. Home's today-so-far values and the Daily JSON export are not touched. No medical interpretation is added: group names are areas, not assessments. HealthKit stays read-only; no egress change.

## 5. Architecture gate

- **Presentation** (Foundation only): `ReportDocument.Group` (id, heading, ordered `[SectionID]`) and one pure, ordered table `ReportDocument.groups`. `ReportDocument.init` keeps building sections. `ordered(sections:)` and `plainText` read the table. Every output reads this one table, so the screen, Copy all and Full Page cannot drift.
- **Views** render a heading for every group with at least one present section (v1.1), as a header-trait row distinct from the section headers.
- **Dependencies:** Views → Presentation → Models. No view model, HealthKit or formatter change.
- **Invariants:** every `SectionID` appears in exactly one group; the set of row ids and the text of every row are unchanged; the tiles' pinned ids are unchanged.
- **Contract tests (written first):** each SectionID in exactly one group (exhaustive switch); new Copy all golden text, with a test that removing heading lines and sorting blocks gives exactly the old blocks; the Full Page section order equals the Copy all order; medications absent leaves no empty group; Food and water placement behind the #214 flag; existing tile tests unchanged.

## 6. Owner decisions

1. **Group existing sections under headings, without merging or renaming them?** Recommended: yes. Merging rows into new sections would change row ids, labels and copied text much more.
2. **What is the activity group called?** Recommended: "Daily activity", the README's term, which avoids an "Activity" group containing an "Activity" section. The alternative is "Activity" with the section renamed "Energy and workouts", which changes a copied title.
3. **Copy all: add group headings or only reorder?** Recommended: add capitalised heading lines and reorder, so Copy all, Full Page and the screen share one structure. The smaller alternative is to reorder only. **Amended 16 October 2026 (v1.1):** every group gets a heading, including single-section groups (`FITNESS AND BLOOD OXYGEN`, `GLUCOSE`, `MEDICATIONS` in Copy all; "Fitness and blood oxygen", "Glucose", "Medications" on screen and in Full Page).
4. **Reorder Developer tools too?** Recommended: no. It is a diagnostic list of model states and is not part of copied output.
5. **Where does Food and water go (if #214 is approved)?** Recommended: standalone, straight after Daily activity, never inside it.
