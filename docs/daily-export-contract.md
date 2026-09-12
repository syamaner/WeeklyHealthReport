# Daily Health JSON export: design and delivery slices

Status: revised contract, 6 September 2026. Synthetic Files probes ran; no Files
route was accepted. User approved moving to secure Google Drive consent/API
integration. The merged synthetic harness includes accepted slice A. Slice B is now
accepted within its synthetic-only boundary through local checks and bounded build-5/
build-6 device and Drive evidence. Slice C's product policies are ratified and its
daily query/model/JSON path is accepted locally through invented fixtures, the complete
62-test simulator suite and static analysis. The additive nutrition contract introduced
schema version 2, a selected visible HealthKit source and fixed seven-completed-day
windows. Schema version 3 adds ordered, date-bound user notes while retaining every
schema-v2 health and nutrition field.
Slice D now has a locally integrated, automatically restored foreground preparation
flow and fail-closed manual transport path, but no production OAuth client,
personal-data export, real-device HealthKit validation or new Google mutation exists.
See `daily-export-feasibility-results.md`
for evidence and `google-drive-export-plan.md` for implementation gates.

## Agreed outcome

Claude Cowork consumes a daily JSON report for the following morning's 06:00 exercise plan and produces weekly reporting separately. The user exports throughout the day and finally before bed. Each successful export replaces the same reporting day's earlier version. There must be one canonical daily file, not a history of export copies.

Include useful daily breakdowns and the app's existing deterministic HealthKit-derived summaries and trends. Weight has one value and recording time for the day, not a list or daily average in the daily detail. Existing weight trend calculations retain their daily-first aggregation internally.

Use manual, user-initiated Google Drive API export after consent. A newly connected or restored account with definitively no prior binding must explicitly choose an existing folder by Drive ID or create and bind one dedicated “WeeklyHealthReport Exports” folder. Folder names are never searched or treated as identity. Revalidate and reuse a stored account-specific destination, but never replace a missing, inaccessible or trashed binding automatically. Keep `drive.file` access and an application-enforced destination restriction; do not request whole-Drive scopes. This supersedes the original Files-only/no-OAuth transport restriction. Evening automation and treadmill intervals remain deferred. Google configuration, real-device acceptance, canonical transport and personal-data export remain separate gated work.

Foreground preparation is serial and idempotent: restore and revalidate the secure
Google session, validate the account destination or require an explicit choose/create
decision, silently
resolve the exact saved nutrition-source bundle identifier, then refresh one new
in-memory preview. Silent resolution and preview queries never request HealthKit
authorisation. First-time nutrition authorisation/source discovery remains an explicit
action. Explicit folder creation reserves and securely persists one Drive ID before
submission, so an uncertain response is reconciled or retried only under that same ID.
Repeated appearances cannot overlap preparation, refresh or export, and no
preparation step uploads bytes, opens Google consent or Picker UI, performs canonical
recovery, or queues later work.

## Daily identity and time

- Proposed name: `health-daily-YYYY-MM-DD.json` in one user-selected destination folder. Filename is a convention, not proof of uniqueness on Drive.
- Identity is the reporting date in the configured reporting time zone; export timestamps never change that identity.
- Capture one time zone, local date and refresh cutoff at refresh start. Query today's data from local midnight through that cutoff. Use explicit inclusive-start/exclusive-end bounds where applicable and document metric-specific exceptions.
- A bedtime export for 6 September supplies the 7 September morning plan. It is not delayed until another completed-day reporting cycle.
- Record actual data cutoff and export time. Do not claim all devices have finished syncing or label the report medically complete.
- Freeze the snapshot before upload or destination selection. Crossing midnight while consent or a picker is open must not rename yesterday's snapshot as today.
- A later automation retry must retain its original reporting date. Backfill/date selection and time-zone changes during travel need an explicit policy before automation.

## JSON envelope

Top-level fields: `schema_version`, `report_date`, `time_zone`, `data_as_of`, `exported_at`, `day_window`, `today`, `app_context`. The current envelope is schema version 3. Schema versions 1 and 2 remain valid only for verifying and safely replacing an existing canonical same-date Drive file.

Schema v3 always includes `today.notes: [String]`. No saved notes is `[]`, never
`null` or an availability wrapper. Strings retain intentional embedded line breaks
and deterministic creation order. Local note IDs, timestamps and revisions are not
exported; unfinished drafts never serialize.

### User-authored note lifecycle

- Notes are keyed by the captured local reporting date and time-zone identity. A
  draft crossing into another identity remains recoverable under its original date
  until the person explicitly copies it into today or discards it.
- The app retains at most 20 saved notes per reporting day, 2,000 Unicode characters
  per note and 20,000 characters across the day. It trims leading and trailing
  whitespace only when saving and never silently truncates input.
- Notes and the one unfinished draft use an atomically replaced Codable document in
  Application Support with complete iOS file protection. Note text is not stored in
  UserDefaults, Keychain, logs, analytics, notifications or Google identity metadata.
- The editor's dedicated microphone uses `SFSpeechRecognizer` with a live
  `SFSpeechAudioBufferRecognitionRequest` only after a user tap. It requires
  `supportsOnDeviceRecognition`, sets `requiresOnDeviceRecognition` on every request
  and fails closed rather than using server recognition. Partial text remains outside
  the draft. Complete final text is appended once; a reset partial or empty or
  incomplete final instead assembles the ordered recognised fragments once, appends
  the complete candidate atomically to the editable draft and visibly asks the user to
  check it there. If one character or daily-limit check rejects the complete candidate,
  the draft remains unchanged and the untruncated candidate stays separately editable.
  That limit-recovery state remains in memory across backgrounding and prevents
  accidental editor dismissal until explicit acceptance or discard. Capture stops on
  backgrounding or editor dismissal. Audio is never persisted, logged, exported or
  uploaded, and this guarantee does not extend to system-keyboard Dictation.
- Refresh captures the saved-note strings and monotonically changing revision before
  asynchronous HealthKit work. A changed revision blocks a late result; a mutation
  after publication invalidates the preview and disables export.
- A remotely verified export records the exact note revision and payload hash. The
  unchanged saved notes become cleanup-eligible only from a later local reporting
  date. Cleanup is lazy, never background work, and never removes an unfinished draft.
- Failed, cancelled-before-submission, uncertain or stale exports cannot authorize
  cleanup. A post-export note change is a new unsent revision and must be retained.

`today` contains daily metric summaries and agreed detail. `app_context` contains existing app-derived summaries/trends with their own windows, coverage, calculation policy identifier and availability. Do not add a blanket previous-seven-days raw-data bundle or ask Cowork to reconstruct established app calculations.

Use JSON numbers rather than formatted display strings, explicit units and ISO 8601 timestamps with offsets. Date-only identifiers use ISO calendar dates. Record actual window boundaries, including DST changes. Arrays have deterministic chronological ordering. Never emit NaN or infinity.

Metric state is explicit through an `availability` field: `available`, `no_data_or_access`, `unsupported`, or `insufficient_data` for derived calculations. `available` requires a `data` object; other states omit `data`. Null is not zero. Loading and query failures are export-blocking states in the first version. Unsupported medication APIs and legitimate empty reads must not block an otherwise valid export. Avoid exporting raw error messages or identifiers unrelated to interpreting the data.

## Metric contract

| Metric | Today | Existing app context to retain |
| --- | --- | --- |
| Weight | One value in kg and recording time; missing if no measurement today | Current and previous seven-completed-day averages, signed kg trend, sampled-day counts and exact windows |
| Body fat | Timestamped measurements in percentage points and daily summary | Latest may include today; seven-day and current/previous 28-day averages use completed local-calendar days and retain sampled-day coverage |
| Waist | Timestamped measurements in cm | Latest-known measurement and existing four-week comparison, including comparison measurement/date or insufficient history |
| Blood pressure | All intact systolic/diastolic pairs in mmHg, timestamp, morning/evening/outside-slot assignment; batch means and counts | Existing period morning/evening daily-first averages, coverage and latest batches with their dates; no invented BP trend |
| Glucose | Daily average/minimum/maximum in mmol/L; proposed hourly statistics with explicit start/end and missing-hour states | Existing completed-period daily-first mean, observed range and coverage |
| Resting HR / HRV | Today's HealthKit daily averages in bpm/ms | Existing equivalent-period averages, trends, coverage and windows |
| Blood oxygen | Timestamped readings in percent and today's median | Existing latest measurement, median-of-daily-medians, daily-median range and coverage |
| VO₂ max | Timestamped estimates in mL/kg/min | Latest estimate and four-week/three-month/six-month daily-first averages and counts, ending at refresh as implemented |
| Sleep | Merged asleep intervals and duration for today's wake-date bucket | Existing completed-period average and sampled-night coverage |
| Activity | HealthKit-resolved steps, active kcal and exercise minutes | Step average over visible daily totals with sampled/reporting-day coverage; existing completed-period energy and exercise summaries |
| Workouts | Individual type, start time and duration; stable record identity for matching | Existing period count and duration summary |
| Watch coverage | Presence of qualifying Watch heart-rate data today, not wear duration | Existing sampled-day coverage |
| Medications | Visible taken events with medication, logged quantity/unit and timestamp | Existing period event summaries, explicitly tied to their reporting window |
| Nutrition | One source-filtered cumulative total per catalogue nutrient from local midnight through the captured cutoff | Exactly seven completed-day states, sampled-day current and previous averages, exact windows and a signed trend only when both windows have 7/7 visible days |

Latest-known context must never be labelled as a measurement taken today. Record retained context measurements' actual dates.

Ratified multiple-weight fallback: if HealthKit unexpectedly exposes multiple weights today, select the latest end timestamp deterministically; when timestamps tie, select the lexicographically smallest HealthKit object UUID. The UUID is an internal, value-neutral tie-break and is not exported. Do not silently average multiple weights into today's single weight.

Glucose hourly bins require query work: current code obtains daily statistics. Derive hourly values using HealthKit statistics, not manual summation/merging of overlapping sensor sources. Keep daily statistics independently queried: averaging hourly means would change the existing daily semantics. Clip the last bin to the refresh cutoff and identify repeated/skipped local hours by timestamp offsets.

Preserve BP pairs, including readings outside the morning/evening slots. Do not join independent systolic and diastolic samples. Preserve existing slot boundaries and equal-day weighting in context summaries.

Nutrition uses one ordered catalogue of all 39 current HealthKit dietary quantity identifiers. The catalogue owns each stable JSON key, display label, category and export unit and is reused for read-only authorisation, source discovery, daily statistics queries and serialization. The person selects a visible HealthKit source by bundle identifier; its name is display-only. Source discovery publishes one complete in-memory snapshot only after all catalogue queries succeed; concurrent reads see either the previous or next complete snapshot, and failure or cancellation preserves the previous snapshot. Every nutrition query combines the selected source predicate with the exact date predicate and uses `cumulativeSum`. There is no provider-specific identifier and no unfiltered fallback. A missing statistic is `no_data_or_access`; it is not zero or proof of denied access.

The nutrition context policy is `nutrition_last_7_completed_days_v1`. It reuses the export's fixed Last 7 Completed Days period and its immediately preceding equivalent period, independent of the weekly screen selection. Each nutrient query spans those 14 completed local-calendar days plus today through the cutoff, normally as one daily statistics collection. Available daily totals alone enter sampled-day averages, whose payload records both sampled and reporting days. Trend is the signed current average minus previous average only when both periods expose all seven daily totals; otherwise it is `insufficient_data`. No foods, meals, targets, percentage changes, tolerances, scores or interpretation are exported.

Sleep remains the existing noon-to-noon bucket ending on the waking date, clipped to available data at refresh. A Sunday bedtime export cannot contain Sunday-night sleep ending Monday; Cowork must use another source or later refresh if that is required.

## Context window decision

Weight, body fat, waist and VO₂ max already have metric-specific windows. RHR, HRV and other period summaries depend on the screen's selected period. Ratified export policy: fix period-dependent context to Last 7 Completed Days, independent of the UI selection, and use existing pure calculations. This makes repeated daily exports comparable. The export never quietly inherits whichever screen selection happens to be active.

Body-fat seven-day and current/previous 28-day summaries use start-inclusive,
end-exclusive completed-day windows ending at local midnight today; the independent
latest body-fat measurement may include today. VO₂ max retains its distinct windows
ending at the captured refresh time.

## Replacement and failure contract

- Requery and build a full daily snapshot on every export; replace rather than append. This permits later HealthKit corrections/deletions to appear.
- One export operation at a time; an older attempt cannot overwrite a newer snapshot.
- Repeating a save of the same snapshot must leave one canonical daily artifact.
- A newer schema-v2 snapshot for the same reporting date replaces a verified schema-v1 canonical file under the same persisted Drive file ID. Version evolution does not relax stale-cutoff rejection, exact-byte readback or one-file-per-day identity.
- A schema-v3 snapshot likewise replaces a verified schema-v1 or schema-v2 canonical file under the same persisted Drive file ID. It never patches notes into already reviewed bytes.
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
pass. Initial-create retry, lost response, cancellation, credential rejection,
account/destination isolation, restart, recovery and stale-attempt behavior are
covered by the separated local/device/Google evidence. No background offline queue.

### 2. Daily model, query and JSON

The two policies above and the consumer field shape are confirmed. Add a distinct daily query window rather than mislabelling today as a completed day. Reuse pure app calculations for context, preserve explicit states in the export snapshot and add glucose hourly queries. Keep calculations in models, HealthKit access in the client and serialization outside the SwiftUI view.

Acceptance: synthetic fixtures cover morning/evening/bedtime replacement snapshots, one daily weight, BP pairing/slots, glucose missing hours, DST, midnight capture, today-versus-context dates, source-resolved cumulative values, insufficient history, unsupported APIs and failed refreshes. JSON preserves the same deterministic values as existing model calculations.

### 3. Manual export UI and proven storage route

Refresh daily data, preview the report date/cutoff and content, then save/replace using the proven mechanism. Preserve weekly UI behaviour. Update privacy documentation and repository scope to describe user-directed JSON file export and any narrowly required temporary storage or secure Google credentials and minimal destination/file identity metadata.

Acceptance: focused tests during development, complete simulator suite once stable, static analysis, diff review, then real-device Apple Health comparisons and Drive replacement checks. Synthetic/simulator success is not personal HealthKit or remote-sync validation.

Local integration provides one serial foreground preparation flow and contextual
Connect, source selection, folder change, account management and Recovery actions.
Opening the export screen may revalidate an existing secure Google session and its
stored destination and may refresh an in-memory HealthKit snapshot without presenting
consent; it performs no automatic export or queued write. The existing weekly-report
refresh remains unchanged. The checked-in OAuth values are non-working placeholders and a distinct
product iOS client remains an external acceptance gate.

### Deferred work

- Treadmill intervals: duration/speed/incline, recording-source investigation and planned-versus-observed semantics. Do not infer these from existing workout type/duration.
- Evening automation around 23:00: scheduling feasibility, unattended provider access, retries, retained reporting date and stale-write protection. No guarantee of exact execution time yet.
- No new weekly report generator, medical interpretation, backend, telemetry or background Google uploads in the manual-export scope.

## Sources and current evidence

- Apple export API: https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller
- Apple directory access: https://developer.apple.com/documentation/uikit/providing-access-to-directories
- Google file resource: https://developers.google.com/workspace/drive/api/reference/rest/v3/files — filenames are not necessarily unique within a folder.
- Apple statistics: https://developer.apple.com/documentation/healthkit/hkstatisticsquery
- HealthKit object identity: https://developer.apple.com/documentation/healthkit/hkobject/uuid
- Existing README, HealthDataProviding, HealthKitClient and pure metric models inspected during planning. Synthetic device evidence is recorded separately; no personal HealthKit export has run.
- Google API/OAuth sources and retry/permission constraints: see `google-drive-export-plan.md`.

## Paste-ready next-task prompt

Validate the locally integrated slice-D product flow with a distinct production iOS
OAuth client. Preserve ignored configuration, synthetic evidence and frozen
accounting rows. Obtain fresh authority for every physical-device HealthKit or Google
action. Compare a reviewed product snapshot with Apple Health and independently
confirm same-ID Drive replacement. Do not broaden `drive.file`, add hosting, a
backend, API keys or client secrets, start automation, or close issue #6 until those
separate device and Google gates pass.
