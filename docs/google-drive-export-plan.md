# Secure Google Drive daily export implementation plan

Product authority: `daily-export-contract.md`. Evidence:
`daily-export-feasibility-results.md`. Slice A's synthetic harness, private Google
configuration and real-device/provider acceptance are complete. Slice B now has a
local synthetic implementation, deterministic checks and a bounded build-5 online
Drive pass plus build-6 adverse device/provider evidence. Slice B is accepted within
its synthetic-only boundary, with evidence-source limits recorded below. The
privacy-safe reproduction and tester-onboarding procedure is in
[`google-drive-cloud-setup.md`](google-drive-cloud-setup.md).
Slice C is locally accepted. Slice D's manual product integration is implemented and
locally testable with fail-closed OAuth placeholders; distinct-product-client,
physical-device HealthKit and Google acceptance remain outstanding. Product setup is
documented separately in
[`google-drive-product-setup.md`](google-drive-product-setup.md).

GitHub tracking: [issue #6 — secure daily JSON export](https://github.com/syamaner/WeeklyHealthReport/issues/6).

## Agreed scope

Manual same-day JSON for the following morning's 06:00 Cowork plan. One canonical
file per local reporting date; refreshed snapshots replace that file by Drive ID.
Cowork handles weekly reports. Retain existing app summaries with their actual
windows. No treadmill intervals, background scheduling or medical interpretation.

User approved a narrow exception to the previous no-account/no-network/no-persistence
rules: explicit Google consent, direct user-initiated Drive export, secure credential
storage and minimal export-identity metadata. HealthKit remains read-only. No backend,
analytics, credential collection, personal payload logging or unrelated transport.
Synthetic API feasibility must pass before production HealthKit wiring.

## Permission and destination design

- Drive permission: `https://www.googleapis.com/auth/drive.file` only. No broad
  `drive`, `drive.readonly` or metadata-wide scope. Review any basic identity scopes
  required by the chosen SDK separately; never silently widen Drive access.
- UI: **Create WeeklyHealthReport Exports** (default) or **Choose existing folder**.
  Persist Google account identity and folder ID, not folder name as identity.
- `drive.file` is per-file/app-created access, not a Google-enforced folder sandbox.
  Selecting a folder must not be described as granting all its pre-existing children.
  Restrict app operations to the selected destination and app-owned daily file IDs.
- Validate returned selection server-side via API metadata: folder MIME type, expected
  account, not trashed, and current write capability. Reject shortcuts and Shared
  Drives in the initial implementation unless their semantics are explicitly added.
- Prefer an app-created fresh folder. With an existing folder, limited-scope listing
  may not reveal every unrelated file. Do not claim an empty visible listing proves
  no collisions. Require a dedicated user-confirmed empty destination for first use;
  define recovery/adoption before reusing a previously populated export folder.
- Changing account/folder must not silently create a second canonical export for a
  date already exported elsewhere. Block that date until an explicit migration or
  destination policy is agreed. Never silently re-create a missing/inaccessible file.

## A. Consent and destination feasibility — first implementation slice

Keep this in the synthetic harness. Establish the user-owned Cloud project, enabled
Drive/Picker APIs, consent audience/test-user status, iOS client and bundle ID,
redirect registration, pinned SDK version and configuration handling. No secrets
in Git; a client ID identifies the app and is not a client secret.

Use a supported system-browser native OAuth flow with validated redirect/state and
PKCE where applicable; do not implement credential entry or embed OAuth login in a
webview. Prefer maintained SDK support and its Keychain storage. No tokens in
UserDefaults, logs, analytics, URLs to an app-hosted page, or plain configuration.
Validate granted scopes and account consistency; reject callback tampering, cancelled
consent, mismatched state and missing grants. Sign-out clears local credentials;
revocation/disconnect is a distinct operation and must report failures honestly.
Disconnect never deletes Drive exports. Account switching partitions all metadata.

**Picker compatibility gate:** Google's browser Picker guide documents
`allow_folder_selection=true`, but the special consent/Picker flow permits only
`drive.file` and cannot combine it with other scopes. Do not assume the Google
Sign-In SDK's identity scopes or Android samples compose directly with an iOS flow.
Prove a supported iOS return/code-exchange mechanism and scope combination before
committing to an SDK design. If a hosted Picker page is necessary, propose its
origin restrictions, credential boundary and hosting scope first; no automatic
backend/hosting expansion. App-created folder flow may be tested independently,
but Choose existing folder remains required and unaccepted until demonstrated.

Acceptance: consent/cancel, restore, sign-out versus revoke, expired/denied grant,
account switch, folder creation and explicit existing-folder selection; unrelated
Drive-file access is denied. No full-Drive permission prompt. Record actual grants
and destination ID privately, without publishing account identifiers or tokens.

### Compatibility resolution implemented locally, 6 September 2026

The synthetic harness pins AppAuth-iOS 2.1.0 rather than Google Sign-In. Google
Sign-In adds basic identity scopes, which cannot be combined with the Picker
flow's exact `drive.file`-only scope. AppAuth is the supported native lower-level
installed-app client: it uses the system authentication session and validates
redirect/state with PKCE. The same code-only client flow supplies Google's
documented `trigger_onepick=true` and `allow_folder_selection=true` parameters.
The returned `picked_file_ids` value is admitted only when it contains one ID.

No hosted page/backend is added. Account identity is obtained from Drive
`about.get`, then the returned/created folder is checked by ID for folder MIME
type, app authorisation, non-trashed state, no Shared Drive ID and
`capabilities.canAddChildren`. Credentials and destination partitions are stored
in this-device-only Keychain items. The implementation remains unaccepted until
the user-owned Cloud project/client and real-device test matrix are complete.

### Real-device compatibility result, 6 September 2026

The special installed-app consent/Picker flow passed the required existing-folder
path after the operator changed the Picker filter to **Folder**. Build 4 then
received, checked and retained the exact dedicated folder ID. No hosted page,
browser developer key, web OAuth client or broader Drive scope was required.

The Picker UI is operationally unreliable on SiPhone: attempts to scroll can select
the item under the finger, so the operator needed several attempts. Treat this as a
usability limitation and do not infer that the unfiltered empty-folder view proves
folder selection is unsupported. The unrelated-file denial and remotely revoked
credential fail-closed checks also passed. After one proposed institutional address
was rejected as ineligible, the operator added an eligible second Google account.
Each account created or restored its own validated destination across local sign-out
and reconnection, with no observed cross-account binding. **Slice A is complete.**

## B. Synthetic canonical transport

Keep transport independent of HealthKit. Proposed small boundaries: authentication
adapter, Drive API client, export-identity store, and one serial export coordinator.
Use Foundation URLSession or a justified supported client; avoid a universal storage
framework. Existing `HealthDataProviding` and `WeeklyReportViewModel` remain untouched.

Persist minimal identity metadata, using atomic local storage and iOS data protection:
account + folder ID + report date + reserved Drive file ID + snapshot generation/hash
+ operation state. Do not persist health JSON for offline delivery. Freeze payload
bytes in memory for the foreground operation; discard after it resolves. If app
termination loses those bytes, reconcile the remote ID/state before a fresh snapshot.
A hash is integrity metadata, not encryption or anonymisation; exclude it from logs.

1. Resolve existing identity; reserve a Drive ID with `files.generateIds` before
   the first create, and persist that reservation before the request.
2. Create JSON at that ID with the chosen parent; on uncertain response reuse the
   same ID. A retry conflict requires readback reconciliation, not a new ID.
3. Update existing files via `files.update(fileId)`. Never delete first and never
   create another file merely because a filename search or permission read failed.
4. Serialise operations across token refresh, retries and app lifecycle. A timed-out
   request may still commit remotely: block newer updates while that write remains
   unresolved. Validate API concurrency/precondition support before relying on it.
   Generation tags in JSON or metadata alone cannot prevent a delayed stale write.
5. Read remote metadata and content back by the same ID; validate account binding,
   parent/date, byte equality and JSON. Only then show **Upload verified**, with time.
   A cached local match does not skip remote verification. Mismatch is **Unverified**.
6. Bounded retry for transient failures; refresh auth appropriately for 401; surface
   denied/revoked permission, quota, rate limit, missing/trashed/moved file and 409
   distinctly. No reachability check is treated as a delivery guarantee.
7. Cancel before transmission preserves remote state. Cancellation after submission
   cannot promise rollback: reconcile and report whether it completed or is unknown.

Recovery policy is a release gate: pre-generated IDs prevent duplicate retries of
one recorded create, not duplicates after metadata loss, reinstalls or independent
writers. Define and test recovery from app-owned remote metadata/explicit selection,
and fail closed on ambiguity. Proposed first release supports one active exporting
installation; multi-device conflict protection is deferred, not assumed. Confirm
that product limit before release. Never weaken one-file-per-day within its scope.

Acceptance uses invented morning/evening/bedtime bytes and independent Drive web
count/content/file-ID checks. Cover initial create and lost-response retry, replacement,
identical snapshot plus remote verification, cancellation, rejected write preservation,
relaunch/reconciliation, account changes, token expiry/revocation and stale completion.
The user skipped prolonged Files offline testing: keep no automatic offline queue,
but test timeouts/network loss mid-request deterministically and with a bounded real
API test. Untested failures are not passes. Preserve the last good file on failure.

### Local slice-B implementation, 6 September 2026

Build 5 adds a Foundation Drive transport and one actor-isolated export coordinator
to the synthetic harness. It reserves one Drive ID, persists that ID before create,
uses multipart create/update by ID, stores only minimal account/folder/date/file/
installation/generation/hash/operation metadata in this-device-only Keychain state,
and remotely reads metadata plus bytes before reporting verified. Keychain updates
no longer delete the old item before replacement.

The coordinator admits only the fixed invented morning/evening/bedtime fixtures.
It serialises token refresh, submission, bounded same-byte retry and reconciliation;
an unresolved submission blocks newer content and creates no offline queue. Pre-
submission cancellation runs no create/update. Post-submission cancellation reports
only verified reconciliation or remains unresolved. Account/destination changes,
missing identity with an existing installation marker, moved/trashed files, metadata
mismatch and stale completions fail closed while retaining the last verified record.
Explicit recovery requires selecting the exact app-owned JSON and validating its
metadata and downloaded bytes; no folder listing or filename search is used.

Deterministic fake-server checks and mocked HTTP request checks pass locally, and the
unsigned generic simulator build compiles. Separately authorised build-5 device and
Google evidence now covers one pre-generated create, same-ID evening/bedtime updates,
app metadata/content readback, independent one-file and file-ID/content checks,
relaunch persistence and an unchanged read-only reverify. It does not establish the
unrun real fault-injection, cancellation, credential, ambiguity or offline cases;
those remain local deterministic evidence and must not be promoted to provider fact.

Build 6 adds a test-only transport interposer and a second fixed invented report date
to exercise the remaining protocol without racing the UI or overwriting the accepted
date. Its bounded modes suppress requests before Drive, discard a successful response,
or inject cancellation immediately before or after submission. They do not change
request bytes, IDs, scope or destination, and they add no queue. A local identity-loss
control preserves the installation marker and therefore forces explicit recovery.
Focused coordinator/API/policy checks and a generic simulator compile/static analysis
pass locally. Under separately bounded authority, build 6 was then installed on the
existing device and its morning uncertain-create probe reported exact metadata/byte
verification after a same-reserved-ID conflict retry. That is device/app evidence;
the operator independently confirmed one new adverse-date file with the invented
morning content and preservation of the accepted-date file, but did not supply its
file ID/link. A separately authorised pre-submission cancellation then reported that
no file submission ran and remote state was preserved; independent Drive-web
confirmation found the single adverse-date morning file unchanged. A subsequent
separately authorised unresolved-evening probe reported that both bounded submissions
were suppressed before commit, newer writes were blocked and no retry was queued.
Independent Drive-web confirmation found the adverse-date morning file unchanged.
An inert terminate/relaunch then restored and revalidated the binding and reported no
Drive write, establishing that no automatic retry ran after relaunch. A separately
authorised retry resumed the persisted evening operation by stored ID, discarded the
successful response and reported exact metadata/byte verification after readback.
Independent Drive-web confirmation found one adverse-date file with the exact
invented evening fields and preservation of the accepted-date file, although its
file ID/link was not supplied. A separately authorised same-ID bedtime update then
injected cancellation after submission and reported exact reconciliation of invented
revision 3. Independent confirmation found one adverse-date file with the expected
bedtime content and preservation of the accepted-date file. A separately authorised
AppAuth forced-refresh pass then reverified that unchanged bedtime file by stored ID
and explicitly reported no Drive write; independent confirmation found the file state
unchanged. Three subsequent device-only expired/denied/revoked injections failed at
the token-provider boundary before any Google request and did not change the real
credential. Those are device/app evidence, not Google credential-state evidence. A
subsequent local identity-loss probe removed the registry, preserved the installation
marker and failed closed as ambiguous before token acquisition. Explicit Picker
recovery then ran under fresh authority: Google showed only its per-file `drive.file`
grant, the operator selected one JSON, and the harness restored invented revision 3
only after strict metadata/content and identity validation. No Drive write ran.
Independent confirmation found remote state unchanged. A subsequent reinstall/relaunch
loaded the recovered persisted identity, reverified unchanged invented revision 3 by
stored ID and explicitly reported no Drive write. Final independent confirmation found
the one adverse-date bedtime file and accepted-date file unchanged.

This closes slice B's bounded synthetic acceptance. The same-ID create/update,
uncertain-response reconciliation, cancellation, unresolved/no-queue, forced-refresh
and explicit-recovery paths have device/API evidence with independent Drive checks at
the recorded boundaries. Expired/denied/revoked injection is device-local; actual
revocation and two-account isolation were established in slice A. Account/destination
change rejection, stale-completion rejection and last-verified preservation remain
deterministic local evidence and are not promoted to new provider facts. No HealthKit
query, personal data or production JSON was involved.

## C. Daily query/model/JSON slice — locally accepted after transport acceptance

The user ratified the multiple-weight rule (latest end timestamp, then
lexicographically smallest HealthKit object UUID), fixed Last 7 Completed Days
period-dependent context, and the envelope/availability shape before implementation.
The UUID tie-break remains internal and is not exported.

Add a separate today window through a frozen cutoff, without changing `ReportPeriod`'s
completed-day meaning. Add a narrowly scoped daily provider boundary for daily/hourly
queries; reuse pure per-metric models. Keep JSON serialization outside `HealthReportFormatter`'s
human display formatting and outside SwiftUI. Keep a separate export orchestration
path so changing the screen period cannot affect export context unexpectedly.

Preserve paired BP, HealthKit-resolved cumulative statistics, glucose daily statistics
independent of hourly means, daily-first trends, actual body-fat/VO2 windows, sleep
wake-date buckets and explicit missing/unsupported states. Query failures block export.
Use synthetic fixtures for DST, midnight, empty reads, partial-day cutoffs, corrections,
weight ties, pair integrity and all retained summary values. No storage/provider code
inside HealthKit queries.

### Local slice-C implementation, 6 September 2026

The app now has a separate, currently unconnected daily refresh service. It freezes
the local calendar, time zone, report date and cutoff before any query; queries a
partial today window without changing `ReportPeriod`'s completed-day meaning; fixes
period-dependent context to Last 7 Completed Days; and preserves the existing
metric-specific body-composition and cardiorespiratory windows. The HealthKit adapter
uses statistics for cumulative totals, daily/hourly glucose and daily heart metrics,
keeps blood-pressure correlations paired, and never writes HealthKit data.

The pure export builder emits schema version 1 with exact offset timestamps,
deterministic chronological arrays, stable workout identities, explicit units and
the ratified availability wrapper. Non-available states omit `data`; query failures
produce no envelope or bytes; JSON encoding rejects non-finite values and sorts keys.
No file is written or uploaded, and the service is not connected to SwiftUI or Drive.

Invented focused checks pass outside the occupied simulator, and all app and test
sources type-check against the iOS SDK. Focused simulator tests passed on a separate
authorised iPhone 17e destination, then the complete simulator suite ran once with
all 62 tests passing and Xcode static analysis succeeded. Those checks cover morning/evening/bedtime
snapshots, equal-timestamp weight selection, fixed context, BP slots, missing glucose
hours, DST, midnight, later corrections, existing-summary value reuse, unsupported
medication APIs and query failure. This is local synthetic evidence only: simulator,
type-checking and synthetic bytes do not prove representative personal HealthKit
behaviour, real-device correctness or any Google/Drive result.

## D. Manual product integration and validation

Connect → choose/create destination → refresh/preview date and cutoff → Export →
verify remote content. Show account/destination and last verified export; clearly
separate refresh failure, upload failure and unknown remote outcome. No claim that
Cowork consumed the file. Disconnect and destination recovery are explicit actions.

Update README privacy claims when networking actually ships, identifying Google's
receipt of user-selected health JSON and the user's Cowork workflow. Maintain read-only
HealthKit `toShare: []`. Run focused tests then the full simulator suite once stable,
static analysis and diff review. Device Health comparisons and separate-client Drive
checks are required before declaring production completion. No personal export during
synthetic slices; it needs explicit device/user authority when reached.

### Local slice-D integration, 6 September 2026

The production app now exposes a separate manual flow for Connect/Restore,
create/select destination, fresh HealthKit preview, exact JSON review, Export,
Cancel, explicit file recovery, local sign-out and remote revocation. Opening the
export screen does not automatically restore its session, refresh its daily snapshot
or contact Drive; the existing weekly report's HealthKit refresh remains unchanged.
The first release supports one
active exporting installation, partitions destination state by account, persists
canonical Drive file IDs before create, updates by stored ID, verifies metadata and
bytes, serialises writes, refreshes rejected tokens once, reconciles uncertain
submissions and never queues offline work.

AppAuth-iOS remains pinned at 2.1.0. Product OAuth values are deliberately invalid in
source and may be supplied only through an ignored local file for a distinct native
iOS client. No client ID, redirect, token, account or Drive ID is published. No
client secret, API key, hosted page, backend, broad Drive scope or folder enumeration
was added.

Invented mock coverage exercises same-ID creation/update, uncertain-create retry,
lost-response reconciliation, cancellation on both sides of submission, relaunch,
explicit recovery, expired/denied/revoked credentials, account/destination isolation,
stale completion, remote mismatch/move/trash and no background queue. These remain
local/simulator facts. Product OAuth consent, representative physical-device
HealthKit comparison and independent Google replacement evidence are still required
before production completion.

## Sources checked 6 September 2026

- [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Create folders and parent files](https://developers.google.com/workspace/drive/api/guides/folder)
- [Browser/mobile Picker parameters and scope restriction](https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker)
- [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios/sign-in)
- [Sign-out and revoke APIs](https://developers.google.com/identity/sign-in/ios/reference/Classes/GIDSignIn)
- [Pre-generated IDs and safe create retries](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
- [Update by file ID](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/update)
