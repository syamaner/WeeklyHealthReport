# UX revamp phase 7: Health summary and simplified Export (architecture gate)

Status: **gate passed with changes, 11 October 2026; changes folded in below. Implemented 12 October 2026 (see "Implementation notes").** Issue #200 (carries #146's acceptance); spec [ux-revamp-v1.md](ux-revamp-v1.md); wireframes `docs/designs/ux-revamp-v1/Health.dc.html` and `Export.dc.html`.

Presentation only. No contract, schema, HealthKit query, aggregation, egress, Drive transport or Daily JSON byte change. The three day rules stay distinct: the Health report uses completed days; the Daily JSON export keeps its selected-day rule (today up to the frozen refresh cutoff, or one of the previous seven local days) under [daily-export-contract.md](daily-export-contract.md); Home's today-so-far projection (#199) is untouched. Refresh, review and export stay manual.

## Deferred wireframe items (each becomes a follow-up issue to file)

| Wireframe item | Why it is deferred | Phase 7 instead |
|---|---|---|
| Period "28 days" and "Custom" | **Needs a semantics change:** new query windows, equivalent-period comparisons, "Weekly Total" wording and README period rules. #200's scope line must be amended | Segmented picker over the existing three `ReportPeriodSelection` cases with the visible range |
| "Logged energy" tile, "Food and water" section | **Needs a contract change:** food-log data is not in `ReportDocument`; adding it changes Copy all, Full Page and Diagnostics parity | Omitted; Home (#199) owns food |
| "↑ 6% vs previous" on steps | **Needs a semantics change:** the report computes no steps trend or percentages | Steps tile shows average and coverage |
| Regrouping (Activity, Body, Heart and sleep) | Outside presentation-only scope: it changes copied text and Full Page structure | Keep `ReportDocument` sections, order and titles |
| "14 metrics · 2 workouts", "Last export of this day" | Outside presentation-only scope: new envelope counting and a per-day identity read | Existing `DailyExportPreviewSummary` fields and `lastVerifiedLabel` |

## Health screen

| Element | Existing code | Restyled or new |
|---|---|---|
| Period picker with visible range | `HealthReportView` picker, `periodText` | Restyled (segmented, range beneath, "completed days") |
| Summary tiles | None | New: `Presentation/HealthSummaryTiles.swift` plus a tile view |
| Grouped sections | `ReportDocumentSectionView`, `BloodPressureReportSection`, `MedicationReportSection` | Restyled: one disclosure style and one expansion policy for every section |
| Copy all (toolbar and button) | Inline `Copy Report` button | Restyled and renamed; one `copyAll()` and one enablement expression (`!viewModel.isRefreshing`) shared by both |
| Full Page | `WeeklyReportScreenshotService`, `WeeklyReportPDFView`, `AppShellView.configureScreenshotProvider` | Renderer unchanged; provider passes details expanded |
| Export entry | "Export" section at the top of the form | Restyled to a trailing row linking `AppRoute.dailyExport` |

**Expanded document.** One helper builds `ReportDocument` with both blood-pressure detail flags `true`. Copy all, Full Page and the tiles all use it, never the on-screen document, so tiles and copied text cannot depend on expansion (for example `blood-pressure-morning-coverage` exists only when morning details are shown). `WeeklyReportPresentationState` gains `expandedSections: Set<ReportDocument.SectionID>` (default all expanded) for the screen only. Full Page changes from mirroring on-screen detail state to always expanded.

**Tile projection.** `enum HealthSummaryTiles { static func make(from: ReportDocument) -> [HealthSummaryTile] }` imports Foundation only and reads no clock or locale. It selects rows by pinned ids (`steps-average` with `steps-coverage`, `sleep-average`, `resting-heart-rate-average` with `resting-heart-rate-trend`, `weight-average` with `weight-trend`, `blood-pressure-morning-average` with `blood-pressure-morning-coverage`) and copies each row's `label`, `value` and `style` verbatim, so windows such as "7-day Average" stay visible. A trend appears only when the document contains that trend row. When a section reports a state instead of values, the tile copies that row's value and style; steps state rows map to the shared `MetricRowVocabulary` terms (made internal rather than private), keeping "Unavailable" and "No completed days" distinct. No new query, threshold, colour coding or interpretation. Tiles repeat section values, add no metric and never appear in plain text.

**Full Page eligibility** is unchanged: `navigationPath == [.healthReport]`, no transient UI, and `screenshotSnapshot` returns `nil` during a refresh or period mismatch.

## Export screen

| Element | Existing code | Restyled or new |
|---|---|---|
| Day picker | "Report date" over `session.availableReportDays`, `selectReportDay`, `busy` gate | Restyled: "Today, up to <cutoff>" only from `previewSummary.dataAsOf`; with no preview just "Today" (the clock is never read for the label); weekday names for the previous seven days |
| Included preview | "Prepared daily snapshot", `DailyExportPreviewSummary` | Restyled: Health data (as of cutoff), Nutrition (selected source), Notes (`savedNoteCount`, link to `AppRoute.notes`), Exact file (`Review exact JSON`); a fixed line that food-log entries are not exported (#97) |
| One Export action | `Export prepared snapshot`, `Refresh`, `Cancel active export` | One primary Export; Refresh and Cancel secondary with today's enablement |
| Export result | `exporting`, `status`, `lastVerifiedLabel` strings | New additive `lastExportOutcome` plus pure `DailyExportPhase` |
| Nutrition source, Needs attention | Existing sections and confirmations | Kept on Export; they depend on the prepared snapshot and state actions |
| Drive account and folder | `googleConnectionSection`, `accountContextSection` | Moved to Settings > Export |

**Outcome.** The controller publishes no typed outcome today, and `applyExportOutcome` sets `preview = nil` after success. Add one published `lastExportOutcome: DailyExportOutcomeRecord?` (plain app type: `reportDate`, `dataAsOf`, `kind`), set only in `applyExportOutcome`, mapping all four `DailyDriveExportResult` cases (`verified`, `unchangedVerified`, `cancelledBeforeSubmission`, `cancelledAfterSubmissionVerified`) and failure. It is cleared on day change, saved-note invalidation, sign-out, revoke and `prepareForPresentation()`. Label strings are never parsed.

**Phase.** `DailyExportPhase` lives in `WeeklyHealthReport/Presentation/` and takes plain inputs (a presentation-state summary, `exporting`, `hasPreview`, `lastExportOutcome`). Cases: `notSetUp`, `preparing`, `prepared`, `attempting` (submission in flight), `verified` (both verified results and `cancelledAfterSubmissionVerified`), `cancelledBeforeSending`, `attemptedNotVerified` (failure), `needsAttention`. Verified comes only from the recorded outcome and survives `preview == nil`. The state machine, invalidation rules and `onAppear` and scene-phase preparation are not edited.

## Settings > Export contribution

`ExportSettingsContribution.section()` keeps taking no session, so building Settings sends no request. Its row links a new `AppRoute.exportDestination`, appended after `.addFood` (#207), a fixed route with an explicit `restoredPath` case `[.settings, .exportDestination]`; stored `dailyExport` still restores to `[dailyExport]`. `DriveDestinationSettingsView` hosts connect, sign-out, revoke, choose existing folder and create folder, calling the existing controller methods. Opening it makes zero HealthKit, OAuth or Drive calls and never calls `prepareForPresentation()`. Tapping connect, create or choose still runs `prepareAfterGoogleConnection` and `refreshPreviewWithoutAuthorization` (HealthKit read, snapshot build, network destination validation); this is user-initiated and unchanged from today, and accepted. Export's "Not set up" state links to this route.

## Responsibilities, dependency direction and boundaries

Views depend on `Presentation` (`ReportDocument`, `HealthSummaryTiles`, `DailyExportPhase`), which depends only on Models and Foundation. `WeeklyReportViewModel`, `HealthKitClient`, row ids and `plainText` output are not edited. The controller gains only `lastExportOutcome`. A new app-level boundary step (beside `Packages/FoodLedgerKit/Scripts/check-boundaries.sh`) fails if any `WeeklyHealthReport/Presentation/*.swift` imports anything but Foundation. The shell stays the composition root and sole owner of `WeeklyReportPresentationState`.

## Risks

- **Export guarantees:** moved controls keep their exact `busy`, `canExport` and `isConfigured` expressions; "verified" never appears without a verified result.
- **Settings causing work:** a spy test proves opening Settings > Export calls nothing.
- **Metric consistency:** tiles copy rows from the expanded document; pinned ids catch renames.
- **Full Page change:** always expanded output; README and the device checklist record it.
- **Route conflict with #207:** resolved by rebase and append, never by reordering raw values.

## README updates in the implementation PR

Line 36 ("one main screen", "Copy Report" becomes Copy all and the current shell); the Full Page paragraph (always expanded, tiles excluded); validation step 14 (Copy all).

## Open questions (answered: the recommended answers were taken)

1. Ship 28 days and Custom now? No; file a follow-up with a semantics and README amendment and amend #200's scope. **Taken.**
2. Accept Full Page always expanded? Yes; #200's acceptance requires it. **Taken.**
3. Tiles in Copy all? No; plain text stays as the expanded document. **Taken.**
4. Nutrition source picker location? Export, shown only when the state's actions include it. **Taken.**
5. Per-day "Last export of this day"? Defer; it is an additional identity read in the controller. **Taken.**
6. Keep Refresh and Cancel beside Export? Yes, secondary, with today's enablement. **Taken.**

## Implementation notes

- **Remote trashed or missing file.** These two export failures used to be rethrown before `applyExportOutcome`. They now pass through `applyExportOutcome(.failure(...))`, which rethrows the same error, so the status, presentation state and replacement candidate are unchanged and the failure is still recorded in `lastExportOutcome`. `lastExportOutcome` is still set nowhere else.
- **Clearing on preparation.** `prepareForPresentation()` clears the outcome whenever it is not refused as busy, including when the build has no OAuth configuration.
- **Further clearing (review fix).** The outcome is also cleared whenever a new preview is installed (so Refresh after an export reads "Ready to export", not a stale verified or failed result) and on an authorisation error.
- **Phase precedence.** `preparing`, then `attempting`, then a failed outcome (`attemptedNotVerified`), then `notSetUp` or `needsAttention` from the setup summary, then a verified or cancelled outcome, then `prepared`. A later problem is therefore never hidden behind an earlier verified export, and `verified` still survives `preview == nil`. `needsNutritionSource` reads as needs attention, because the source is chosen on Export.
- **Settings folder actions.** "Choose existing folder" appears once the session has validated an account in this run (the screen never restores it by itself); "Create new export folder" appears only when the state's actions include it, as before. "Recover existing canonical JSON" stays on Export beside the action buttons, with its previous enablement.
- **Export screen.** The "Included" list replaces "Prepared daily snapshot" and the notes section; the completed-day window rows are no longer shown on screen (the exact file still contains them). The fixed line reads "Food-log entries are not exported yet."
- **App boundary check.** `Tools/check-app-boundaries.sh`, run in CI beside the FoodLedgerKit boundary step.
- **README.** Besides the three listed passages, the export workflow and privacy paragraphs were updated for the renamed **Export** action and Drive setup in Settings. The README screenshot of the old export screen is unchanged and needs a fresh synthetic capture.

## Tests

1. Tiles: per state (available, no data, unavailable, no completed days, loading, failed) byte for byte against rows; independent of on-screen expansion; pinned row ids.
2. Copy all equals the expanded document's `plainText` for every flag and `expandedSections` combination; toolbar and button share one path and gate; tiles never in plain text.
3. Full Page: provider returns the expanded document; eligibility table unchanged; `nil` during refresh.
4. `DailyExportPhase`: exhaustive mapping including all four results and failure; clearing on each trigger; verified after `preview == nil`.
5. Existing controller and orchestration tests pass unmodified; day picker offers today plus seven days and honours `busy`; `exactJSONConstructionCount` stays 0 until review.
6. Settings: spies record zero calls on open; connect, create and choose follow unchanged paths.
7. Navigation: restoration table row for `exportDestination` in `AppNavigationTests`; `dailyExport` unchanged; app boundary check.
8. Native renders of Health and Export at default and accessibility sizes, light and dark; simulator suite, static analysis, device check.
- **Review and tap-through fixes (12 October 2026).**
  - The controller gains one more read-only member, `hasValidatedAccount` (`account != nil`, no request), so Settings shows "Choose existing folder" only after this run validated an account, including in needs-attention states.
  - Settings > Export buttons go through `DriveDestinationAction` and a small `DriveDestinationControlling` protocol, so a spy test proves each button reaches the matching controller method.
  - A day change while Drive is not set up keeps the not-set-up state (or the no-configuration state) instead of moving to needs attention; otherwise the status now names the "Retry preparation" button that is shown. This is the only edit to the state transitions.
  - Export hides the "Needs attention" section when it has no visible action; the verified result shows a readable day and cutoff; "Exact file" and a separate, visibly disabled "Review exact JSON" button replace the hint-only row.
  - Settings uses the Export status wording for a build without OAuth configuration.
  - Tiles show the short "Query failed" term for any failure row; the full message stays in the section row, Copy all and Full Page. Tiles are otherwise verbatim.
  - The in-form Copy all button is a full-width, centred title and icon in its own section; Health uses compact section spacing to reduce the gap under collapsed sections.
  - The period choice resets to "Last 7 days" on relaunch on main as well (it was never persisted); unchanged here.
  - `Tools/check-app-boundaries.sh` now scans subfolders and allows `@preconcurrency import Foundation` and trailing comments.
  - README period names follow the picker titles; the README export screenshot still shows the pre-#200 screen (alt text updated). A synthetic recapture is a follow-up.
