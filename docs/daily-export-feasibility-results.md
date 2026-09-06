# Synthetic Files → Drive feasibility, 6 September 2026

Status: **copy-export route rejected: same-name duplicates observed in Drive web**.
Directory route unavailable: operator reported Drive greyed out in the picker.
Existing-file route not accepted: limited operator-confirmed success ended in an
unresolved provider-local bedtime / Drive-web evening mismatch. User approved a
secure consent/Drive API approach; implementation is planned separately.
Copy-export testing stopped at the uniqueness failure. No personal HealthKit data was used.
The existing daily-export contract remains unchanged.

Authority: the user's subsequent **“proceed”** authorises the explicitly proposed
local signing and installation of Synthetic Files Test on SiPhone, and creation
and replacement of the invented JSON only in `WHR-Synthetic-2026-09-06` on Drive.
The user operates Files and the separate Drive client. No personal-data export
or broader Drive mutation is authorised by this experiment.

## Setup observed

- Xcode 26.6 (17F113).
- Read-only CoreDevice discovery: SiPhone, iPhone 17 Pro Max, paired/connected,
  iOS 26.6.1 (23G83), Developer Mode enabled.
- User confirmed they can operate the iPhone and a separate Drive client.
- User reported successfully accessing Google Drive in Files. A corrected query
  including non-development apps confirms Drive version **4.2635.41602**. The
  initial inventory used the default developer-only filter and was inconclusive.
- No simulator was booted during preflight. Generic simulator compilation is not
  a simulator UI run or a Drive-provider test.

## Harness and local validation

`Tools/SyntheticDriveExport/` contains a separate Xcode app, fixed synthetic JSON
generator, local admission policy, executable pure checks and the device protocol.
It uses a copy-export document picker and one fixed filename for three revisions.
There is no HealthKit access, production app change, Google OAuth or app networking.

- Pure checks passed: only one active attempt, rejection of older revisions,
  equal-revision retries, restored watermark semantics and deterministic JSON.
- Generic iOS simulator build passed; Xcode static analysis passed.
- Generic unsigned iPhone build passed. Subsequent authorised signing passed
  after Xcode obtained a development provisioning profile for the separate app.
- Installation was attempted and rejected by iOS: CoreDevice error 3002,
  underlying MIInstallerErrorDomain error 13, explicitly reporting the maximum
  number of installed apps using a free developer profile. The listed apps were
  WeeklyHealthReport, PacePrompt and PacePromptEvaluation. No existing app was
  removed or replaced at that point. The harness had not yet been installed or
  launched, and no synthetic Drive write had run.
- The user subsequently explicitly authorised removal of PacePromptEvaluation.
  CoreDevice confirmed its uninstallation, followed by successful installation
  and launch of Synthetic Files Test. WeeklyHealthReport and PacePrompt were not
  removed or replaced. Subsequent saves and independent-client observations are
  recorded below.
- Simulator-service sandbox diagnostics appeared during compilation; no simulator
  runtime behaviour is inferred from these builds.
- The injected pre-write failure button performs no destination operation; it
  cannot establish preservation following an actual provider write failure.
- A persisted local watermark cannot establish remote ordering after reconnection.

## Acceptance observations

The following table records the original **copy-export route** only. Later
existing-file observations are recorded after the build-3 notes below.

| Requirement | Result | Evidence still required |
| --- | --- | --- |
| Morning → evening → bedtime leaves one latest file | **FAIL at evening save** | Operator reported two files; Drive web screenshot shows two identical filenames. Bedtime not attempted |
| Identical bedtime save creates no duplicate | Untested | Independent count and identical downloaded content |
| Cancellation preserves previous valid file | **PASS, operator-reported** | One file in Drive web screenshot; operator confirmed revision 1 / morning after cancellation |
| Failed provider write preserves previous valid file | Untested | Real safe provider failure and independent read; injected local failure is insufficient |
| Relaunch | Local policy check only | Force-quit/relaunch and device persistence behaviour |
| Offline/reconnect | Untested | Queue/failure observations and independent content during/after sync |
| Older attempt cannot overwrite newer content | Local admission check only | Device rejection plus queued-provider ordering evidence |
| Final content visible from separate Drive client | Untested | Client/version, file count and downloaded revision 3 |

### Observed sequence and limits

1. Operator supplied morning JSON: revision 1, marker `morning`, invented_steps
   1234, data_as_of `2026-09-06T08:00:00+01:00`.
2. Initial destination screenshot showed `Health Coach / Daily health`. The
   operator was asked to move only the synthetic file into the dedicated test
   folder and confirmed doing so. A later Drive web screenshot showed one
   `health-daily-2026-09-06.json` in the synthetic folder.
3. Operator cancelled the evening picker as instructed and confirmed the remaining
   file still contained morning revision 1. The later repeated morning JSON was
   still from this cancellation step, **not an attempted evening replacement**;
   the operator explicitly corrected this sequencing misunderstanding.
4. After actually saving evening, the operator reported “Now I saved and got 2
   files”. Attached screenshot `codex-clipboard-3a5e69d6-c555-4f8d-8bb5-4080d5b65e3c.png`
   shows Drive web with two rows named `health-daily-2026-09-06.json`, both 235 bytes,
   displayed modified times 14:46 and 14:42. Screenshot times are reproduced as
   displayed, without inferring a time zone. Each duplicate's downloaded content,
   the exact Files prompts and harness callbacks were not supplied.
5. Operator later reported a third file after another copy save and inability to
   select an existing file. No third-file screenshot was supplied. No further
   copy-export actions are requested.

The screenshot directly establishes duplicate names in the separate Drive web
client; the operator supplies the action sequence. This is sufficient to reject
`UIDocumentPickerViewController(forExporting:asCopy: true)` as used by this harness
for the mandatory one-file-per-day contract. It does not establish that every
possible Files storage route fails. Preserve both duplicates as evidence; do not
continue bedtime/repeat/offline writes on this failed route. Morning visibility
was independently observed; final bedtime content remains untested. Remaining
acceptance checks are untested or local-only as indicated above.

## Next bounded work

Following explicit approval, build 2 replaces the copy-export UI with a `.folder`
open picker (`asCopy: false`) and coordinated directory writes. A fresh folder
`WHR-Directory-2026-09-06` is required; the original duplicate folder is preserved.
The harness validates existing bytes as known synthetic fixtures, rejects extra
entries and stale revisions, and skips identical writes. It uses security-scoped
access and `NSFileCoordinator` off the UI thread, followed by local count/readback.
No bookmark is saved: the same folder must be reselected after relaunch. A separate
persisted directory-route watermark avoids reusing the copy-route revision state.

Local filesystem integration checks passed for creation/replacement, identical
no-op, stale rejection, injected pre-write failure preservation and refusal of
unexpected contents. A sandboxed macOS coordination attempt failed (Cocoa 512);
the same checks passed with access to the coordination service. Generic simulator
build and Xcode static analysis passed. Signed device build passed. No production
app code changed; no production simulator suite was rerun for this isolated probe.
CoreDevice confirmed installation of build 2. Automatic launch failed because
SiPhone was locked (CoreDevice 10002, underlying FBSOpenApplicationErrorDomain 7).
The operator was asked to unlock/open the harness and test folder selection only.
No directory-route provider write has run.
The operator initially answered that selection worked, then corrected this:
Google Drive was **greyed out** in the directory picker. The initial answer is
superseded; no successful Drive directory selection is recorded.

### Existing-file probe (build 3)

User authorised the next test. Build 3 opens `.json` with `asCopy: false`, declares
support for opening documents in place, and replaces the directory UI with
**Choose existing JSON**. The selected known synthetic file is coordinated for
replacement and written atomically; no parent enumeration, destination creation,
delete-first or truncate fallback is used. Local admission/log keys are separate
from prior builds. The operator must seed one morning file in a fresh
`WHR-ExistingFile-2026-09-06` folder, preserving the old three duplicates.

Local existing-file checks passed: replacement/readback, identical no-op, stale
rejection, injected failure preservation and unknown-content refusal. Signed
device build passed. Provider access and updates are not yet established. Even
success here would leave initial daily canonical-file creation unresolved.
Build 3 installed and launched successfully. The first simulator build stalled
in SDK stat-cache generation; a fresh derived-data build with the cache disabled
passed compilation and analysis, and the stalled task processes were stopped.
The operator was asked to test selection only before any existing-file update.

### Subsequent build-3 observations (operator evidence)

- Initial selection was one of three duplicates; an evening payload from that
  selection did not establish a new update. The operator then copied a fixture to
  the fresh folder and confirmed a single file, selection and an evening payload.
  These exchanges support limited single-file update observations, but no paired
  Drive IDs or complete before/after downloads were captured.
- Operator confirmed repeat evening retained one evening file, stale morning was
  rejected after relaunch, and injected pre-write failure preserved evening.
  Exact events for these confirmations were not supplied.
- Offline bedtime attempt returned: `2026-09-06T14:28:02Z Revision 3: Identical
  selected payload; no write. Remote upload UNVERIFIED`. This established that
  the provider-local file was already bedtime, not an offline write or upload.
  The action that first produced that local content remains uncertain.
- User elected to skip further offline testing and ensure connectivity manually.
  Offline/reconnect ordering therefore remains untested, not passed.
- Subsequent Drive-web payload supplied by the operator was still evening revision
  2. After instruction to reconnect/relaunch/reselect/retry, the operator reported
  the same local no-write result. File identity was not independently correlated;
  provider caching/sync versus selecting different documents remains unresolved.
  This mismatch is sufficient to withhold acceptance, not to diagnose its cause.
- No actual provider-failure preservation or initial canonical creation guarantee
  was established. Production health-data export has not run.

## Revised direction

User approved secure Google Drive consent/API integration and create/select folder
without broad Drive access. See `google-drive-export-plan.md` and the revised daily
contract. No more Files probes are planned. Initial creation, ID-based replacement,
remote verification and retry/recovery semantics are the next synthetic scope.
The original no-OAuth rule is superseded narrowly; one-file-per-day is unchanged.
These checks do not establish Drive folder support, file identity or remote sync.

## Slice A local implementation evidence, 6 September 2026

Build 4 replaces the rejected Files UI with a separate synthetic Google consent
and destination harness. It pins AppAuth-iOS 2.1.0 and requests exactly
`drive.file`. The two flows are **Create WeeklyHealthReport Exports** and
**Choose existing folder** through Google's special system-browser Picker flow.
There is no hosted page, backend, HealthKit query or daily JSON transport.

The app validates the returned grant, account identity, one returned folder ID,
folder MIME type, app authorisation, trashed/Shared Drive state and
`canAddChildren`. AppAuth state and account-partitioned destination bindings use
this-device-only Keychain storage. Local sign-out and remote revocation are
separate; neither deletes exports. A disposable unrelated-file denial check is
available without retaining or logging its ID.

Local policy checks passed for exact-scope rejection, single-ID Picker admission,
folder/account/write validation, account partitioning and revocation transitions,
alongside the preserved historical Files policy checks. Mocked HTTP checks passed
for account/folder decoding, authenticated folder create/get requests, unrelated
file denial and revocation request construction. The unsigned generic iOS Simulator
build and Xcode static analysis passed with AppAuth resolved at 2.1.0.

This is not Google or device acceptance. No Google Cloud configuration was found
locally (`gcloud` is not installed), no OAuth client values exist in the repository,
and no Google grant or folder mutation ran. SiPhone was visible as connected, but
installation was intentionally not attempted without the configuration and fresh
device/external-write authority. Consent cancellation/restoration, sign-out versus
revocation, expiry/denial, account switching, both destination flows and unrelated
file denial all remain real-device/manual checks. Slice A is therefore incomplete.

## Slice A external and SiPhone evidence, 6 September 2026

Evidence is separated by source so a local assertion is not mistaken for a Google
or device result.

### Local evidence

- Build 4 signed for and installed on the authorised SiPhone with bundle ID
  `com.syamaner.WHRSyntheticDriveExport`. AppAuth resolved at 2.1.0.
- Mocked Drive checks passed for account/folder decoding, authenticated create/get,
  the unrelated-file denial response and revocation request construction.
- The OAuth client ID and reversed scheme exist only in the ignored local
  `Config/OAuth.local.xcconfig`. No client secret was requested, downloaded or
  stored. Account identifiers, client values and signing identity remain private.
- No HealthKit query, daily JSON creation, slice-B work, commit or push ran.

### Google evidence

- The intended user-owned Cloud project was verified privately. Only the Google
  Drive API and Google Picker API were enabled for this work.
- Google Auth Platform is External/Testing. The iOS client uses the exact synthetic
  bundle ID and the configured data-access scope is exactly `drive.file`; no broader,
  sensitive or restricted scope was added.
- The app-created `WeeklyHealthReport Exports` folder persisted after revocation.
  The operator's Drive-web observation was "no files inside"; this is recorded only
  as that direct observation, not as proof of emptiness and not as an inference from
  limited `drive.file` visibility.
- A separate empty existing-folder fixture and one unrelated disposable synthetic
  Google document were created. The unrelated document was not moved into either
  destination and its private ID was not published. The app's denial probe rejected
  access to it under the granted `drive.file` scope.

### SiPhone/operator evidence

- Exact `drive.file` consent and **Create WeeklyHealthReport Exports** succeeded.
  The app reported the expected account and destination only after its account,
  folder-metadata and write-capability validation.
- Relaunch restored and revalidated the secure state. Local sign-out then left
  Google access and exports intact; after relaunch the app showed `Not connected`
  and `No destination`.
- Cancelling consent and cancelling the existing-folder flow both reported that the
  operation was cancelled and preserved prior credentials/destination state.
- Reconnection selected the expected account/destination. In-app remote revocation
  then cleared the selection without deleting the Drive folder.
- **Choose existing folder passed after an operator-discovered workaround.** The
  Picker initially made an empty folder appear unselectable. Changing its filter to
  **Folder** exposed folder selection, and the app accepted and validated the exact
  dedicated existing folder. No hosted page, browser key or broader scope was
  required. Picker scrolling remained unreliable: taps made while trying to scroll
  could select the item under the finger, so the operator needed several attempts.
- After access was removed in Google Account settings while build 4 retained its
  local state, relaunch failed closed: `Operation cancelled or failed. No export
  file was written.`, `Not connected`, `No destination`. The security outcome
  passed, although the message does not distinguish remote denial/revocation from
  cancellation or another failure.
- The unrelated disposable synthetic file was denied, as required.
- One proposed institutional address was ineligible for test-user designation, but
  the operator subsequently added an eligible second Google account. Build 4 created
  and validated that account's separate synthetic destination. After local sign-out,
  reconnecting the original account restored only its original destination; signing
  out and reconnecting the second account restored only the second destination.
  No cross-account folder binding was observed.

Slice A is **complete**. Both destination flows and every required security check,
including two-account switching, passed. The Picker's unreliable scroll/tap
interaction and the generic revoked-access error remain recorded limitations, not
grounds for broader Drive permission or hosting.

## Slice B local implementation evidence, 6 September 2026

Evidence remains separated by source. No personal data or production daily JSON was
created, and no HealthKit code was read or changed for this implementation.

### Local evidence

- Build 5 adds pre-generated Drive ID reservation, persisted-before-create identity,
  same-ID uncertain-create retry, stored-ID multipart updates and remote metadata/
  byte readback to the separate synthetic harness.
- Minimal identity and operation state is account/folder/date partitioned in this-
  device-only Keychain items. A separate installation marker makes missing state
  fail closed. Explicit selected-file recovery validates app metadata and exact
  content without listing a folder or searching by filename.
- One actor serialises token refresh, submission, one bounded same-byte retry and
  reconciliation. Unresolved submissions block newer generations. Cancellation is
  distinguished before and after submission. No reachability trigger or automatic
  offline queue exists.
- Only the fixed invented morning/evening/bedtime bytes are admitted. Tests cover
  revoked/expired/denied credentials, account/destination isolation, relaunch,
  missing-state recovery, rejected-write preservation, moved/trashed files, remote
  byte mismatch and stale-completion rejection while retaining the last verified
  record.
- Deterministic coordinator checks pass. Mocked HTTP checks pass for `generateIds`,
  multipart create/update, metadata/content get, structured errors and the retained
  slice-A requests. Static analysis and the unsigned generic iOS Simulator build
  succeed with AppAuth still pinned at 2.1.0. The production simulator suite ran once
  after implementation: all 54 tests passed with no failures, skips or expected
  failures.

### Device evidence

- Under separately granted action-by-action authority, build 5 was signed, installed
  over build 4 and launched on SiPhone (iPhone 17 Pro Max). The existing ignored
  OAuth configuration and bundle identifier were reused; no new credential, scope,
  key, secret, hosted component or backend was added.
- Launch restored and revalidated the existing session, account and destination and
  explicitly reported that no Drive write ran. After the online fixture sequence,
  the app was terminated/relaunched and restored the same binding again.
- A post-relaunch repeat of bedtime reported that unchanged revision 3 was remotely
  reverified and no write ran. This establishes device Keychain persistence for the
  exercised identity, not the unrun missing/corrupt-state recovery cases.
- No HealthKit permission or query ran. Temporary Mirroring screenshots used only to
  read the visible status were deleted because they contained the account label.

### Google evidence

- The operator temporarily approved the existing dedicated slice-A folder as the
  bounded slice-B synthetic destination. The app did not enumerate it or infer that
  limited `drive.file` visibility meant it was empty.
- Under fresh authority for each mutation, build 5 created the fixed morning fixture,
  then updated it to evening and bedtime. After each accepted step the app reported
  remote metadata/content verification. Repeating bedtime reported a read-only
  reverify with no write.
- Independent Drive-web checks found exactly one canonical JSON file. The privately
  compared Drive file link/ID was identical across evening and bedtime, and remained
  so after relaunch/no-op. Downloaded files semantically matched the fixed invented
  revision 1/2/3 fixtures (1234/2468/3702 steps). Chat paste formatting means those
  independent copies are semantic evidence; the app's downloaded comparison is the
  byte-for-byte evidence.
- No delete, folder listing, broader permission, recovery selection, credential
  revocation, account switch or connectivity change ran in build 5. Controlled
  uncertain-create, cancellation, denied/expired/revoked credentials, missing-state
  recovery, stale completion and offline/unresolved behaviour remain deterministic
  local evidence, not Google/device evidence.

At the build-5 boundary, slice B was **locally implemented with its bounded canonical
online Drive path accepted**, while the adverse-provider/device protocol remained
explicitly unaccepted. The build-6 section below supersedes that interim status. No
metric queries or production export UI were implemented. One-file-per-day remains
mandatory. No commits, pushes or remote issues had been created at that boundary.

## Slice-B build-6 adverse-control preparation, 6 September 2026

Build 6 adds a second fixed invented reporting date and a test-only transport
interposer for the still-unrun adverse protocol. It can discard a committed create
response and verify its conflict retry retains the reserved ID, cancel at deterministic pre/post-submission
boundaries, leave an update unresolved after two bounded pre-commit losses, and
discard a successful response before readback reconciliation. It also exposes forced
token refresh, device-only expired/denied/revoked credential failures and local
identity loss that preserves the installation marker. None changes request bytes,
IDs, scope or destination; no folder listing or automatic queue was added.

Focused coordinator, mocked-HTTP and policy checks pass, including the new ordered
adverse sequence. The unsigned generic simulator build and static analysis pass.
These remain local results only.

### Build-6 device/app evidence

- Under separately bounded authority, build 6 was signed with the existing local
  development identity/profile, installed over build 5 and launched on SiPhone. The
  restored account and existing destination were reused. No new credential, scope,
  key, secret, hosted component, backend, Picker flow or HealthKit access was added.
- A debug-only exact launch argument selected the fixed `2026-09-07` adverse fixture
  and invoked only the morning uncertain-create probe. The app reported that invented
  revision 1 was remotely verified byte-for-byte, that it discarded the committed
  create response, and that the conflict retry used the same reserved Drive file ID.
- A separately authorised evening probe then injected cancellation after account
  validation and before file submission. The app reported that cancellation occurred
  before file submission and that remote file state was preserved.
- After independent confirmation that state was unchanged, a separately authorised
  unresolved-evening probe suppressed both bounded submissions before commit. The app
  reported that the submitted request remained unresolved, newer writes were blocked,
  no retry was queued and both submissions retained the stored file ID.
- After the operator independently confirmed that the unresolved probe left the
  morning file unchanged, an authorised inert terminate/relaunch restored and
  revalidated the session, account and destination and explicitly reported that no
  Drive write ran. The unresolved request did not retry automatically after relaunch.
- A separately authorised retry then resumed the persisted evening operation, updated
  by its stored file ID and deliberately discarded the successful submission response.
  The app accepted the outcome only after Drive metadata and exact-byte readback
  verified invented revision 2.
- After independent one-file/evening-content confirmation, a separately authorised
  bedtime update committed by the same stored ID and then injected cancellation. The
  app reported only after reconciliation verified invented revision 3, explicitly
  distinguishing post-submission cancellation from rollback.
- After independent one-file/bedtime-content confirmation, a separately authorised
  AppAuth forced-refresh pass reverified unchanged invented revision 3 by the stored
  file ID and explicitly reported that no Drive write ran.
- After the operator confirmed the forced-refresh pass left Drive unchanged, three
  authorised device-only runs injected expired, denied and revoked failures at the
  coordinator token-provider boundary. Each was rejected with its distinct reason.
  Session restoration was bypassed for these exact debug arguments, so they acquired
  no token, made no Google request and did not alter the real AppAuth credential.
- After the operator confirmed Drive remained unchanged, an authorised local identity-
  loss probe captured the adverse-date binding, removed only the canonical registry,
  preserved the installation marker and attempted bedtime export. It failed closed as
  ambiguous before token acquisition. Explicit Picker recovery was then required.
- Under fresh authority, the existing account/destination were restored and Google's
  consent UI showed only the per-file `drive.file` grant. The operator selected one
  JSON in the explicit Picker; the harness accepted it only after account, parent,
  app-ownership, report-date, installation-marker, generation, hash, metadata and
  downloaded-byte checks passed, then restored invented revision 3 locally. No Drive
  write ran.
- After independent confirmation that recovery left Drive unchanged, the rebuilt app
  was installed over the existing copy and relaunched. It loaded the recovered
  persisted identity, reverified unchanged invented revision 3 by its stored file ID
  and explicitly reported that no Drive write ran.
- The app did not enumerate the destination or touch the accepted `2026-09-06`
  canonical identity. Temporary Mirroring screenshots used to read the visible result
  were deleted because they contained the account label.

### Build-6 Google evidence

After the morning probe, the operator independently confirmed exactly one
`2026-09-07` file, its fixed invented morning content and preservation of the
accepted `2026-09-06` file. The file ID/link itself was not supplied, so identity
continuity beyond the no-duplicate observation remains unconfirmed independently.
The operator independently confirmed that both the pre-submission cancellation and
unresolved-evening probe left the single adverse-date morning file unchanged. After
the lost-response retry, the operator independently confirmed one adverse-date file
with the exact invented evening fields and preservation of the accepted-date file;
the adverse file ID/link itself was not supplied. Independent confirmation of the
post-submission-cancellation state found exactly one adverse-date file with the
expected bedtime content and preservation of the accepted-date file. Independent
confirmation found the subsequent forced-refresh reverify left this unchanged. The
expired/denied/revoked injections were deliberately local-only and are not Google
credential-state evidence. The device/app results above must not be substituted for
provider-independent checks. The identity-loss probe made no Google request; explicit
recovery subsequently passed the strict readback checks above. Independent confirmation
found that recovery left the one-file bedtime state and accepted-date file unchanged.
Final independent confirmation after the persisted-identity reverify again found the
same one-file bedtime state and accepted-date file unchanged.

Slice B is therefore **accepted within its synthetic-only boundary**. Device/API plus
independent Drive evidence covers pre-generated same-ID creation, updates, bounded
uncertain outcomes, both cancellation boundaries, unresolved/no-queue behavior,
forced refresh, explicit recovery and persistence. Expired/denied/revoked handling is
device-local injection; actual revocation and two-account isolation remain the prior
slice-A evidence. Account/destination change rejection, stale-completion rejection and
last-verified preservation remain deterministic local evidence, not new Google facts.
No HealthKit query, personal data, production JSON, folder enumeration, broader scope,
hosting, backend, API key or client secret was introduced.
