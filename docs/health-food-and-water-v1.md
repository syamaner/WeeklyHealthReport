# Health food and water section v1 (#214)

Status: **approved by the owner, 16 October 2026; every decision in section 9 takes its recommended option.** Policy identifier: `health_food_log_period_v1`. Deferred from UX revamp phase 7 ([ux-revamp-phase-7-health-export.md](ux-revamp-phase-7-health-export.md)); wireframe `designs/ux-revamp-v1/Health.dc.html` ("Logged energy" tile, "Food and water" section).

**Proposal:** yes, the Health report shows what was **logged in this app's food log** for the selected completed days: average logged energy per complete day and average plain water per day it was logged, with logged-day coverage. Both are food-log facts, labelled "logged", not measured intake. HealthKit dietary data stays export-only, as README already says.

## 1. Day rules

- **Health report (this section):** the selected period's completed local days. Each completed day maps to one food-log reporting date (`yyyy-MM-dd` in the report's captured calendar and time zone). Entries are matched by their stored reporting date (the day chosen when logging or backdating), not by the time they were saved. Today is excluded.
- **Home and Food Log** keep their own today-so-far and selected-day views ([intake-home-projection-v1.md](intake-home-projection-v1.md)).
- **Daily JSON export:** unchanged. Food-log entries are not exported (the Drive coordinator still rejects them; #97 owns that). The Export screen line "Food-log entries are not exported yet." stays.

## 2. Per-day facts (existing read side, unchanged)

`FoodLogDayContent` for one reporting date (`FoodLedgerApplication/FoodLogDayContent.swift`) already gives:

- `totals`, which is nil when the day has no current entries. The energy total is `FoodIntakeTotal(key: .energyConsumed)` with `knownAmount`, `incompleteContributions` and `includesEstimates` (summary policy `food-intake-summary-v2`).
- `plainWater`, which is nil when no plain water was logged. It is a known minimum when `incompleteContributions > 0` (`PlainWaterDayTotal`).

Day classification:

| Day | Rule |
|---|---|
| Not logged | No current entries (`totals == nil`). Not zero, and not in any average |
| Logged, energy complete | `knownAmount != nil` and `incompleteContributions == 0` |
| Logged, energy incomplete | Otherwise. The known subtotal is a minimum and is left out of the average (decision 3) |
| Water day | `plainWater != nil` with `incompleteContributions == 0` |
| Water incomplete | `plainWater` with `incompleteContributions > 0`. Left out of the average and counted |

Superseded and removed versions never contribute. Competing current heads make that day a read failure, as on Home.

## 3. Values and rounding

- **Logged energy:** the arithmetic mean of complete days' energy totals, with each day weighted equally. kcal, rounded to a whole number with grouping, only in presentation.
- **Plain water:** the mean over complete water days. mL, rounded to a whole number. It is plain water entries only (the Home and Food Log figure), never water contained in foods. The label says "Plain water".
- **Coverage:** "6 / 7 days logged" (the existing `dayCoverage` style), plus incomplete counts when not zero.
- If any day in an average includes estimates, the value carries the existing "includes estimates" wording.

## 4. Rows and states

Section id `foodLog`, title "Food and water" in Copy all and on screen. Row ids: `food-days-logged`, `food-energy-average`, `food-energy-incomplete`, `food-plain-water-average`, plus the usual `-loading`, `-no-data`, `-failed` and `-no-completed-days` state rows.

```text
Food and water
Days Logged: 6 / 7 days
Logged Energy: 2,010 kcal per day (5 complete days)
Incomplete Energy Days: 1
Plain Water: 1,750 mL per day (4 days)
Logged in this app; not a measure of everything eaten or drunk.
```

| State | Section shows |
|---|---|
| Loading | "Reading the food log…" |
| No completed days | Same as Steps: "There are no completed days in this period yet." |
| Nothing logged in the period | "No food logged in this period." Never 0 kcal |
| Logged but no complete energy day | `Logged Energy: Insufficient history` plus the counts |
| No plain water logged | `Plain Water: No data` |
| Read failed | "Could not read the food log." The technical message appears only in Developer tools. This is distinct from the Apple Health wording |

The incomplete-days row is left out when the count is 0. The footer line is fixed copy.

## 5. Consistency

| Surface | Change |
|---|---|
| Health screen | New section (placement owned by #216, see [health-report-section-groups-v1.md](health-report-section-groups-v1.md)). New "Logged energy" tile pinned to `food-energy-average` with `food-days-logged` (decision 4) |
| Copy all | Adds the section block above. Tiles are not copied |
| Full Page | The same section in display wording |
| Developer tools | New "Food log (Health report)" section: each reporting date, entry count, unrounded energy known amount, incomplete contributions, estimate flag, plain water and its flags, and each day's classification |
| Daily JSON, stored records | No change. Read-only use of existing records; no schema, ledger or archive change |

No net, balance or deficit with active energy (today-so-far D9 applies here as well). No target, protein, macro or interpretation (protein and macros stay with #145).

## 6. Architecture gate

- **Domain** (`Models/`, Foundation only): `FoodLogPeriodSummary.make(days: [FoodLogDayFacts], reportingDates: [String]) -> FoodLogPeriodSummary`. `FoodLogDayFacts` is a plain app value (date, entry count, energy known amount, energy incomplete count, includes estimates, water known amount, water incomplete count). No FoodLedgerKit, GRDB or SwiftUI types appear in it.
- **Application:** a consumer-owned port `FoodLogPeriodReading { func dayFacts(for reportingDates: [String]) async throws -> [FoodLogDayFacts] }`, declared beside the report view model. `WeeklyReportViewModel` reads it under the same refresh generation and publishes `MetricState<FoodLogPeriodSummary>` in the report snapshot. A food-log failure never affects the HealthKit states.
- **Infrastructure:** an adapter at the composition root (`FoodLedgerCompositionRoot`) maps `FoodLogReadingService.day(_:)` (`totals`, `plainWater`) to `FoodLogDayFacts`, one date at a time. There is no new store query and no range API.
- **Presentation:** `ReportDocument` builds the section, `HealthReportFormatter` formats it, and `HealthSummaryTiles` pins the new rows.
- **Dependencies:** Models ← application ← adapters wired at the composition root. `Tools/check-app-boundaries.sh` still passes, and Presentation imports only Foundation.
- **Invariants:** an empty day is not zero; incomplete totals never enter an average; plain water never includes food water; HealthKit dietary data is never read for this section; existing sections are byte-identical.
- **Contract tests (written first):** classification of each day type; mean weighting days equally; rounding; estimate flag propagation; competing heads give a failed state; superseded and removed entries excluded; backdated entries counted on their stored date; a DST week maps to 7 reporting dates; existing Copy all golden text unchanged except the new block; Daily JSON golden snapshots unchanged; a fake port and the real adapter pass the same tests on synthetic ledgers.

HealthKit stays read-only and is not touched. No new egress: the section leaves the device only through Copy all or Full Page, which privacy-and-egress.md already lists. That file's food-log bullet gains "and the Health report's Copy all and Full Page", so this is a documentation update, not a new destination.

## 7. Relation to coverage

"Days logged" measures use of the log, not completeness of eating. The fixed footer says so, and no value is called "intake" or "calories eaten".

## 8. Not in scope

Protein and other nutrients (#145), trends (#147), the HealthKit dietary energy comparison, and food in the Daily JSON export (#97).

## 9. Owner decisions

1. **Should Health show logged food energy and plain water for completed days?** Recommended: yes, as a "Food and water" section from the local food log, labelled "logged", with logged-day coverage.
2. **Which water counts?** Recommended: plain water entries only (the Home figure), labelled "Plain water". The alternative is total water including water in foods, which is usually unknown.
3. **How are days with an unknown energy contribution treated?** Recommended: leave them out of the average and show "Incomplete Energy Days: n". The alternative is to include their known subtotals and label the average "at least".
4. **Add the "Logged energy" summary tile?** Recommended: yes, pinned to the energy average and days-logged rows, not copied.
5. **Show the section when nothing has ever been logged?** Recommended: yes, with "No food logged in this period.", so every surface has the same sections.
6. **Include protein, as the wireframe shows?** Recommended: no; leave it to #145.
