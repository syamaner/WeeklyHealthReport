# Daily Health JSON export: design and delivery slices

Status: revised contract, 6 September 2026. Synthetic Files probes ran; no Files
route was accepted. User approved moving to secure Google Drive consent/API
integration. An uncommitted synthetic slice-A harness now exists, but no production
export or accepted Google integration exists. See `daily-export-feasibility-results.md`
for evidence and `google-drive-export-plan.md` for implementation gates.

## Agreed outcome

Claude Cowork consumes a daily JSON report for the following morning's 06:00 exercise plan and produces weekly reporting separately. The user exports throughout the day and finally before bed. Each successful export replaces the same reporting day's earlier version. There must be one canonical daily file, not a history of export copies.

Include useful daily breakdowns and the app's existing deterministic HealthKit-derived summaries and trends. Weight has one value and recording time for the day, not a list or daily average in the daily detail. Existing weight trend calculations retain their daily-first aggregation internally.

Use manual, user-initiated Google Drive API export after consent. Offer Create “WeeklyHealthReport Exports” or Choose existing folder, with `drive.file` access and an application-enforced destination restriction; do not request whole-Drive scopes. This supersedes the original Files-only/no-OAuth transport restriction. Evening automation and treadmill intervals remain deferred. Google configuration, real-device acceptance, canonical transport and personal-data export remain separate gated work.

## Daily identity and time

- Proposed name: `health-daily-YYYY-MM-DD.json` in one user-selected destination folder. Filename is a convention, not proof of uniqueness on Drive.
- Identity is the reporting date in the configured reporting time zone; export timestamps never change that identity.
- Capture one time zone, local date and refresh cutoff at refresh start. Query today's data from local midnight through that cutoff. Use explicit inclusive-start/exclusive-end bounds where applicable and document metric-specific exceptions.
- A bedtime export for 6 September supplies the 7 September morning plan. It is not delayed until another completed-day reporting cycle.
- Record actual data cutoff and export time. Do not claim all devices have finished syncing or label the report medically complete.
- Freeze the snapshot before upload or destination selection. Crossing midnight while consent or a picker is open must not rename yesterday's snapshot as today.
- A later automation retry must retain its original reporting date. Backfill/date selection and time-zone changes during travel need an explicit policy before automation.

## Proposed JSON envelope

Top-level fields: `schema_version`, `report_date`, `time_zone`, `data_as_of`, `exported_at`, `day_window`, `today`, `app_context`.

`today` contains daily metric summaries and agreed detail. `app_context` contains existing app-derived summaries/trends with their own windows, coverage, calculation policy identifier and availability. Do not add a blanket previous-seven-days raw-data bundle or ask Cowork to reconstruct established app calculations.

Use JSON numbers rather than formatted display strings, explicit units and ISO 8601 timestamps with offsets. Date-only identifiers use ISO calendar dates. Record actual window boundaries, including DST changes. Arrays have deterministic chronological ordering. Never emit NaN or infinity.

Metric state is explicit: `available`, `no_data_or_access`, `unsupported`, or `insufficient_data` for derived calculations. Null is not zero. Loading and query failures are export-blocking states in the proposed first version. Unsupported medication APIs and legitimate empty reads must not block an otherwise valid export. Avoid exporting raw error messages or identifiers unrelated to interpreting the data.

## Metric contract

| Metric | Today | Existing app context to retain |
| --- | --- | --- |
| Weight | One value in kg and recording time; missing if no measurement today | Current and previous seven-completed-day averages, signed kg trend, sampled-day counts and exact windows |
| Body fat | Timestamped measurements in percentage points and daily summary | Existing seven-day and current/previous 28-day averages and percentage-point trend; current implementation can include today |
| Waist | Timestamped measurements in cm | Latest-known measurement and existing four-week comparison, including comparison measurement/date or insufficient history |
| Blood pressure | All intact systolic/diastolic pairs in mmHg, timestamp, morning/evening/outside-slot assignment; batch means and counts | Existing period morning/evening daily-first averages, coverage and latest batches with their dates; no invented BP trend |
| Glucose | Daily average/minimum/maximum in mmol/L; proposed hourly statistics with explicit start/end and missing-hour states | Existing completed-period daily-first mean, observed range and coverage |
| Resting HR / HRV | Today's HealthKit daily averages in bpm/ms | Existing equivalent-period averages, trends, coverage and windows |
| Blood oxygen | Timestamped readings in percent and today's median | Existing latest measurement, median-of-daily-medians, daily-median range and coverage |
| VO₂ max | Timestamped estimates in mL/kg/min | Latest estimate and four-week/three-month/six-month daily-first averages and counts, ending at refresh as implemented |
| Sleep | Merged asleep intervals and duration for today's wake-date bucket | Existing completed-period average and sampled-night coverage |
| Activity | HealthKit-resolved steps, active kcal and exercise minutes | Existing completed-period summaries with their dates |
| Workouts | Individual type, start time and duration; stable record identity for matching | Existing period count and duration summary |
| Watch coverage | Presence of qualifying Watch heart-rate data today, not wear duration | Existing sampled-day coverage |
| Medications | Visible taken events with medication, logged quantity/unit and timestamp | Existing period event summaries, explicitly tied to their reporting window |

Latest-known context must never be labelled as a measurement taken today. Record retained context measurements' actual dates.

Proposed multiple-weight fallback: if HealthKit unexpectedly exposes multiple weights today, select the latest timestamp deterministically; do not silently average them into today's single weight. This fallback is a design choice to confirm before implementation.

Glucose hourly bins require query work: current code obtains daily statistics. Derive hourly values using HealthKit statistics, not manual summation/merging of overlapping sensor sources. Keep daily statistics independently queried: averaging hourly means would change the existing daily semantics. Clip the last bin to the refresh cutoff and identify repeated/skipped local hours by timestamp offsets.

Preserve BP pairs, including readings outside the morning/evening slots. Do not join independent systolic and diastolic samples. Preserve existing slot boundaries and equal-day weighting in context summaries.

Sleep remains the existing noon-to-noon bucket ending on the waking date, clipped to available data at refresh. A Sunday bedtime export cannot contain Sunday-night sleep ending Monday; Cowork must use another source or later refresh if that is required.

## Context window decision before coding

Weight, body fat, waist and VO₂ max already have metric-specific windows. RHR, HRV and other period summaries depend on the screen's selected period. Proposed export policy: fix period-dependent context to Last 7 Completed Days, independent of the UI selection, and use existing pure calculations. This makes repeated daily exports comparable. Confirm this choice before implementation; do not quietly inherit whichever screen selection happens to be active.

The earlier conversation's blanket claim that all trends use completed-day windows was incorrect. Preserve actual per-metric behaviour; do not change body-fat or VO₂ max calculations as part of export.

## Replacement and failure contract

- Requery and build a full daily snapshot on every export; replace rather than append. This permits later HealthKit corrections/deletions to appear.
- One export operation at a time; an older attempt cannot overwrite a newer snapshot.
- Repeating a save of the same snapshot must leave one canonical daily artifact.
- A failed refresh, cancellation or failed write must preserve the prior good file. Never delete the prior file first to simulate replacement.
- Validate the complete JSON before handing it to storage. Keep temporary data only as long as needed and clean it up after completion/cancellation where possible.
- Treat HTTP upload response separately from verified remote content. Verify the expected account/folder/file ID and JSON bytes through the Drive API before reporting verified upload. Independent Drive web verification remains an acceptance check; this does not prove Cowork fetched the file.
- Same-name duplicates, ambiguous destinations, corrupt replacement, or stale content winning after reconnection fail the storage acceptance test.

## Delivery slices

### 1. Secure synthetic Google Drive feasibility

Files evidence: copy-export produced same-name duplicates; Drive was greyed out
for directory selection; existing-file updates produced limited operator-confirmed
success but ended in an unresolved local bedtime / remote evening mismatch. Do not
reuse local provider readback as cloud evidence. Offline testing was curtailed at
the user's request; user connectivity is a workflow precondition, not evidence of
sync or protection against a mid-request network loss.

Implement only the synthetic API slices in `google-drive-export-plan.md`: iOS
consent and narrow scope, create/select destination, safe initial creation, updates
by persisted file ID, and remote readback. Do not wire HealthKit until those gates
pass. Initial-create retry, lost response, cancellation, revocation, account switch,
restart and stale-attempt tests remain required. No background offline queue.

### 2. Daily model, query and JSON

Confirm the two proposed policies above and consumer field shape. Add a distinct daily query window rather than mislabelling today as a completed day. Reuse pure app calculations for context, preserve explicit states in the export snapshot and add glucose hourly queries. Keep calculations in models, HealthKit access in the client and serialization outside the SwiftUI view.

Acceptance: synthetic fixtures cover morning/evening/bedtime replacement snapshots, one daily weight, BP pairing/slots, glucose missing hours, DST, midnight capture, today-versus-context dates, source-resolved cumulative values, insufficient history, unsupported APIs and failed refreshes. JSON preserves the same deterministic values as existing model calculations.

### 3. Manual export UI and proven storage route

Refresh daily data, preview the report date/cutoff and content, then save/replace using the proven mechanism. Preserve weekly UI behaviour. Update privacy documentation and repository scope to describe user-directed JSON file export and any narrowly required temporary storage or secure Google credentials and minimal destination/file identity metadata.

Acceptance: focused tests during development, complete simulator suite once stable, static analysis, diff review, then real-device Apple Health comparisons and Drive replacement checks. Synthetic/simulator success is not personal HealthKit or remote-sync validation.

### Deferred work

- Treadmill intervals: duration/speed/incline, recording-source investigation and planned-versus-observed semantics. Do not infer these from existing workout type/duration.
- Evening automation around 23:00: scheduling feasibility, unattended provider access, retries, retained reporting date and stale-write protection. No guarantee of exact execution time yet.
- No new weekly report generator, medical interpretation, backend, telemetry or background Google uploads in the manual-export scope.

## Sources and current evidence

- Apple export API: https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller
- Apple directory access: https://developer.apple.com/documentation/uikit/providing-access-to-directories
- Google file resource: https://developers.google.com/workspace/drive/api/reference/rest/v3/files — filenames are not necessarily unique within a folder.
- Apple statistics: https://developer.apple.com/documentation/healthkit/hkstatisticsquery
- Existing README, HealthDataProviding, HealthKitClient and pure metric models inspected during planning. Synthetic device evidence is recorded separately; no personal HealthKit export has run.
- Google API/OAuth sources and retry/permission constraints: see `google-drive-export-plan.md`.

## Paste-ready next-task prompt

Implement only slice A (secure consent and destination selection) of docs/google-drive-export-plan.md, using the revised daily-export-contract.md. Preserve all uncommitted work and frozen accounting rows. First establish the user-owned Google Cloud project, iOS client/redirect configuration, dependency version and compatible narrow-scope Picker flow. Use invented data only; no production HealthKit integration. Request only drive.file for Drive access, keep credentials in secure SDK/Keychain storage, and never put tokens in logs or hosted picker URLs. Prove create-folder and choose-existing-folder without broad scopes; validate account, MIME type and write capability. If iOS Picker compatibility requires a new hosted component, stop that part with concrete evidence rather than broadening permissions. Record checks and unresolved boundaries. Do not commit/push or export personal data.
