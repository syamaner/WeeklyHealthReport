# UX revamp phase 7: Health summary and simplified Export (architecture gate)

Status: **draft for gate review, 11 October 2026.** Issue #200 (carries #146's acceptance); spec [ux-revamp-v1.md](ux-revamp-v1.md); wireframes `docs/designs/ux-revamp-v1/Health.dc.html` and `Export.dc.html`.

Presentation only. No contract, schema, HealthKit query, aggregation, egress, Drive transport or Daily JSON byte change. The three day rules stay distinct: the Health report uses completed days; the Daily JSON export keeps its selected-day rule (today up to the frozen refresh cutoff, or one of the previous seven local days) under [daily-export-contract.md](daily-export-contract.md); Home's today-so-far projection (#199) is untouched. Refresh, review and export stay manual.

## Wireframe items deferred because they would need a contract change

| Wireframe item | Why it is out of this phase | Phase 7 instead |
|---|---|---|
| Period picker "28 days" and "Custom" | `ReportPeriodSelection` has `currentWeek`, `previousWeek`, `lastSevenCompletedDays`; new periods change query windows, equivalent-period comparisons, "Weekly Total" wording and README semantics | Segmented picker over the existing three selections with the visible range; new periods become a follow-up issue |
| "Logged energy" tile and "Food and water" section | Food-log data is not in `ReportDocument`; adding it changes Copy all, Full Page and Diagnostics parity | Omitted; Home (#199) owns food |
| "↑ 6% vs previous" on steps | The report computes no steps trend or percentages | Steps tile shows average and coverage only |
| Wireframe group names (Activity, Body, Heart and sleep) | Regrouping rows changes the copied text and Full Page structure | Keep `ReportDocument` sections, order and titles |
| Export "14 metrics · 2 workouts" and "Last export of this day" | Needs new envelope counting and a per-day identity read | Existing `DailyExportPreviewSummary` fields and `lastVerifiedLabel` |

## Health screen

| Element | Existing code | Restyled or new |
|---|---|---|
| Period picker with visible range | `HealthReportView` `Picker` over `ReportPeriodSelection`, `periodText` | Restyled (segmented, range beneath, "completed days") |
| Summary tiles | None | New: `Presentation/HealthSummaryTiles.swift` plus a tile view |
| Grouped sections | `ReportDocumentSectionView`, `BloodPressureReportSection`, `MedicationReportSection` | Restyled: each section a disclosure group with one shared expansion policy |
| Copy all (toolbar and button) | Inline `Copy Report` button calling `plainText(generatedAt:)` | Restyled and renamed; one `copyAll()` used by both |
| Full Page | `WeeklyReportScreenshotService`, `WeeklyReportPDFView`, `AppShellView.configureScreenshotProvider` | Unchanged renderer; provider passes details expanded |
| Export entry | "Export" section at the top of the form | Restyled to a trailing row linking `AppRoute.dailyExport` |

**Tile projection.** `enum HealthSummaryTiles { static func make(from: ReportDocument) -> [HealthSummaryTile] }` is pure Foundation: no SwiftUI, HealthKit, clock or locale beyond the strings already formatted in the document. It selects rows by their stable ids (`steps-average` with `steps-coverage`, `sleep-average`, `resting-heart-rate-average` with `resting-heart-rate-trend`, `weight-average` with `weight-trend`, `blood-pressure-morning-average` with its coverage) and copies `value` verbatim. A trend appears only when the document already contains that trend row with `.standard` style. When the row is absent or its section reports no data, loading or failure, the tile shows "No data", "Loading" or "Failed" and the section keeps the full sentence. No new HealthKit query, threshold, colour coding or interpretation. Tiles duplicate section values, so they add no metric and are not added to copied text.

**Expansion.** `WeeklyReportPresentationState` gains `expandedSections: Set<ReportDocument.SectionID>` (default all expanded) beside the existing morning/evening blood-pressure flags. Copy all and Full Page ignore expansion: both build the document with `showsMorningBloodPressureDetails` and `showsEveningBloodPressureDetails` set to `true`. This changes Full Page from mirroring the on-screen detail state to always expanded, so README's Full Page paragraph and validation step 14 are updated in the same PR.

**Full Page eligibility** is unchanged: `navigationPath == [.healthReport]`, no transient UI, and `screenshotSnapshot` still returns `nil` during a refresh or period mismatch. Other screens keep the ordinary screenshot.

## Export screen

| Element | Existing code | Restyled or new |
|---|---|---|
| Day picker | `DailyExportView` "Report date" over `session.availableReportDays` and `selectReportDay` | Restyled: "Today, up to <cutoff>" from `previewSummary.dataAsOf`, weekday names for the previous seven days; same binding and `busy` gate |
| Included preview | "Prepared daily snapshot" section and `DailyExportPreviewSummary` | Restyled: Health data (as of cutoff), Nutrition (selected source name), Notes (`savedNoteCount`, link to `AppRoute.notes`), Exact file (`Review exact JSON` sheet); a fixed line that food-log entries are not exported (#97) |
| One Export action | `Export prepared snapshot`, `Refresh`, `Cancel active export` | Restyled: one primary Export; Refresh and Cancel remain, secondary, with today's enablement |
| Prepared, attempted, verified | `presentationState`, `exporting`, `status`, `lastVerifiedLabel`, last outcome (`.verified`, `.unchangedVerified`) | New pure `DailyExportPhase` projection over those values; the state machine is not edited |
| Nutrition source choice | "Apple Health nutrition source" section | Kept on Export, shown only when the state's actions include it |
| Needs attention | `attentionSection`, trashed-destination and file-replacement confirmations | Kept on Export; they depend on the prepared snapshot |
| Drive account and folder | `googleConnectionSection`, `accountContextSection` | Moved to Settings > Export |

`DailyExportPhase` (`notSetUp`, `preparing`, `prepared`, `exporting`, `verified`, `failed`, `needsAttention`) is a display mapping in the app's `GoogleDrive` group with no Drive or HealthKit import. "Verified" is shown only from a verified outcome for the current preview identity; an HTTP response alone stays "attempted". Snapshot invalidation (saved-note change, date change, background) keeps clearing the preview and disabling Export exactly as now. `onAppear` and scene-phase `prepareForPresentation()` calls are unchanged.

## Settings > Export contribution

`ExportSettingsContribution.section()` keeps taking no session, so building Settings still sends no request. Its row points at a new `AppRoute.exportDestination` (a fixed route; restores to `[settings, exportDestination]`) whose `DriveDestinationSettingsView` hosts the moved connect, sign-out, revoke, choose existing folder and create folder controls, calling existing `DailyDriveSessionController` methods. It must not call `prepareForPresentation()`, so opening it never prepares a Health snapshot. Export's "Not set up" state links to this route. Phase 3 (PR #207) adds `.addFood`; `.exportDestination` is appended after it on rebase, and the restoration table gains one row.

## Responsibilities and dependency direction

Views depend on `Presentation` (`ReportDocument`, `HealthSummaryTiles`) and on `DailyExportPhase`; those depend only on Models and Foundation. `WeeklyReportViewModel`, `HealthKitClient`, `ReportDocument` row ids and `plainText` output are not edited. `DailyDriveSessionController` gains no new state; any helper needed by the Settings view is an additive read of existing published values. The shell remains the composition root and sole owner of `WeeklyReportPresentationState`.

## Risks

- **Export guarantees:** moving controls could bypass `busy` or `canExport` gates. Mitigation: the moved buttons keep their exact enablement expressions; the phase projection is read-only.
- **Settings causing work:** a Drive view that calls `prepareForPresentation()` would query HealthKit from Settings. Mitigation: a test asserts no preparation on appear.
- **Metric consistency:** tiles drifting from sections, or a renamed row id silently blanking a tile. Mitigation: tile values are copied from rows, and a test pins every id the projection reads.
- **Full Page change:** always-expanded output differs from today; README and the device checklist must say so.
- **Route conflict with #207:** both edit `AppRoute`; resolve by rebase, not reordering raw values.

## Tests

1. `HealthSummaryTiles`: synthetic documents for available, no data, loading, failed and no completed days; trend only when the trend row exists; values equal row values byte for byte.
2. Copy all equals `ReportDocument(details expanded).plainText` regardless of `expandedSections` and blood-pressure flags; toolbar and button share one path.
3. Full Page: eligibility table unchanged; provider returns the expanded document; `nil` during refresh.
4. `DailyExportPhase`: every `DailyExportPresentationState` plus `exporting` and outcome combination; verified never derived from attempted alone.
5. Export state machine unchanged: existing `DailyDriveSessionController` and orchestration tests pass untouched; day picker offers today plus seven days; invalidation on note change and date change.
6. Settings: `ExportSettingsContribution` links `.exportDestination`; restoration `[settings, exportDestination]`; the destination view never prepares a snapshot.
7. Native render tests for Health and Export at default and accessibility sizes, light and dark.
8. Simulator suite, Xcode static analysis, `git diff --check`, and a device check comparing Health, Copy all, Full Page and Diagnostics.
