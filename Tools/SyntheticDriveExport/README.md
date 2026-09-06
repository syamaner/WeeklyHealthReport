# Secure Google consent and destination harness — build 4

This separate app implements only slice A of `docs/google-drive-export-plan.md`.
It uses invented labels only and does not query HealthKit or upload a daily JSON
file. The rejected Files experiments below are retained as historical evidence;
do not resume them.

## Compatibility decision

The existing-folder path uses Google's special browser/mobile Picker OAuth flow.
That flow permits only `https://www.googleapis.com/auth/drive.file` and cannot be
combined with other scopes. Google Sign-In for iOS always adds basic identity
scopes, so it is deliberately not used here. The harness pins OpenID Foundation
AppAuth-iOS **2.1.0**. AppAuth presents `ASWebAuthenticationSession`, validates the
OAuth redirect and state, and supplies PKCE for the installed-app code flow.
Google Drive `about.get` supplies the account binding under `drive.file`; no
`openid`, `email`, `profile`, broad Drive or metadata-wide scope is requested.

No hosted Picker page or backend is required by this implementation. The Picker
returns the selected folder ID to the registered iOS custom-scheme callback. The
app exchanges the code directly, then validates the folder through Drive API
metadata. Build 4 passed this path on the authorised real device after the operator
changed the Picker filter to **Folder**. Picker scrolling was unreliable and could
select the item under a scrolling finger; this is a recorded usability limitation,
not permission to broaden scope or add hosting.

## Private configuration required before device testing

Follow the privacy-safe, click-by-click setup and tester onboarding runbook in
[`../../docs/google-drive-cloud-setup.md`](../../docs/google-drive-cloud-setup.md).
The summary below is retained as the harness-local checklist.

1. In a user-owned Google Cloud project, configure the OAuth audience as External
   / Testing and add the intended Google account(s) as test users. A second test
   account is required to complete the account-switch test.
2. Enable **Google Drive API** and **Google Picker API** in that project.
3. Create an **iOS OAuth client** for the exact synthetic-harness bundle identifier.
   The proposed local identifier is `com.syamaner.WHRSyntheticDriveExport`; the
   final value must match both the Xcode configuration and Cloud client.
4. Use the client ID's reversed scheme and the redirect
   `REVERSED_CLIENT_ID:/oauth2redirect`. Do not create, download or add a client
   secret: an installed iOS app cannot keep one.
5. Copy `Config/OAuth.local.xcconfig.example` to the ignored
   `Config/OAuth.local.xcconfig` and set the client ID, reversed scheme and bundle
   identifier. Never paste tokens or a client secret there.

The checked-in defaults are deliberately non-working. `OAuth.local.xcconfig` is
ignored. AppAuth credentials and account-partitioned folder IDs are archived only
in this app's non-synchronising, when-unlocked, this-device-only Keychain items.
Tokens are not placed in `UserDefaults`, logs, URLs to an app-hosted page or source.

## Authorised real-device protocol

Installation, Google consent and folder creation are external state changes. Run
these only after the operator confirms the device, configured project/client and
test accounts, and explicitly authorises the named mutations.

1. Launch with no stored state. Start **Create WeeklyHealthReport Exports**, then
   cancel in the system browser. Confirm no folder is created and the app remains
   disconnected. Repeat cancellation from **Choose existing folder**.
2. Run **Create WeeklyHealthReport Exports**, inspect the Google prompt, and record
   privately that the returned grant is exactly `drive.file`. Confirm one new
   folder is created, is not in a Shared Drive, and the app reports it writable.
   No child JSON should exist.
3. Relaunch and use **Restore secure session**. Confirm the same account and
   destination return. Use **Sign out locally**, relaunch, and confirm restoration
   does not occur. Reconnect and confirm the folder still exists.
4. Use **Revoke Google access**. Confirm revocation succeeds, local credentials are
   cleared, the folder remains, and a later action requires consent again. A failed
   revocation must leave credentials present and report failure.
5. In Drive web, create a fresh dedicated empty folder outside this app. Run
   **Choose existing folder**, choose it in Google's system-browser Picker, and
   confirm its returned ID/type/account/write capability. Do not infer access to
   its children or that a limited listing proves it empty.
6. Sign out, select the second test account in a destination flow, and verify its
   destination is separate. Switch back and confirm the first account's binding is
   restored rather than reused cross-account.
7. Create a disposable unrelated synthetic file in Drive web, outside either
   selected folder and never select it in Picker. Paste only its file ID into the
   least-privilege check. Confirm access is denied; the harness clears the ID and
   never logs or persists it.

Stop on any identity/scope mismatch, embedded-webview behaviour, callback error,
unrequested permission, Shared Drive selection, non-folder result, inability to
add children or unrelated-file access. Keep account identifiers, folder/file IDs,
screenshots containing them and tokens private.

## Local validation

```sh
xcrun swiftc -module-cache-path /tmp/whr-consent-swift-module-cache \
  Tools/SyntheticDriveExport/ExportPolicy.swift \
  Tools/SyntheticDriveExport/ConsentPolicy.swift \
  Tools/SyntheticDriveExport/PolicyChecks.swift \
  -o /tmp/whr-consent-policy-checks
/tmp/whr-consent-policy-checks

xcrun swiftc -module-cache-path /tmp/whr-consent-swift-module-cache \
  Tools/SyntheticDriveExport/ConsentPolicy.swift \
  Tools/SyntheticDriveExport/DriveAPI.swift \
  Tools/SyntheticDriveExport/DriveAPIChecks.swift \
  -o /tmp/whr-drive-api-checks
/tmp/whr-drive-api-checks

xcodebuild -project Tools/SyntheticDriveExport/SyntheticDriveExport.xcodeproj \
  -scheme SyntheticDriveExport -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/whr-drive-consent-derived \
  CODE_SIGNING_ALLOWED=NO build analyze
```

The checks exercise exact-scope admission, one-folder Picker response handling,
folder/account/write validation, account partitioning and sign-out/revocation
state policy. They do not prove Google consent, Keychain restoration, remote
revocation, either destination flow or least-privilege denial.

The separately recorded real-device run proved those external behaviours, including
both destination flows, unrelated-file denial and two-account isolation. See
`docs/daily-export-feasibility-results.md`. This harness remains synthetic-only;
slice B transport and all HealthKit work are outside build 4.

---

# Historical existing-file probe — build 3, rejected route

Drive was greyed out in the directory picker, according to the operator. Build 3
replaces that picker with `.json` / `asCopy: false`, and declares support for opening
documents in place. The current screen is **Existing File Test**.

1. Preserve the original folder containing three duplicates. In Drive web, copy
   one **morning revision 1** fixture into a fresh `WHR-ExistingFile-2026-09-06`
   folder, keeping `health-daily-2026-09-06.json` as the filename. Confirm exactly
   one file there. This is a manual test seed, not a proven daily creation route.
2. Tap **Choose existing JSON**. Navigate to Drive and select that file. Selection
   itself writes nothing. Report whether Drive/file selection is enabled before
   pressing any write button. Stop if unavailable; do not revert to copy-export.
3. Once selected, tap **Write evening (2)** once. Refresh Drive web and download
   the file to confirm revision 2 / evening / 2468 and exactly one file. Record
   the Drive web file ID/link before and after to assess identity preservation.
4. If replacement passes, repeat evening (expected no-op), cancel the file picker,
   relaunch/reselect and test stale rejection, then proceed to the previously
   documented bedtime/offline/failed-write checks. No provider claim follows from
   local readback alone.

Only the selected security-scoped file is accessed. No parent folder enumeration
or destination creation occurs. A coordinator announces replacement and the write
uses `.atomic`; no unsafe truncate/delete fallback is allowed. Unknown contents,
symlinks and stale revisions are rejected; identical bytes skip writing. Local
watermark/events use new keys, leaving earlier probe state intact. Reselect the
same file after relaunch; no bookmark is stored. The operator must choose only the
new synthetic seed; provider URL paths may not expose the user-visible folder.

Local checks cover existing-file replacement, no-op repeat, stale refusal,
injected failure preservation and unknown-content refusal. These do not establish
Drive compatibility, identity, file count or remote failure atomicity. Initial
daily creation remains unresolved even if this update probe succeeds.

---

# Historical directory probe — unavailable in tested Drive picker

# Directory replacement probe — current harness

The copy-export route failed: two identically named files appeared in Drive web
following the evening save, and the operator subsequently reported a third.
The current app removes that route. Preserve those files as evidence.

## Current device protocol

1. In Drive/Files create a new empty folder **WHR-Directory-2026-09-06**.
2. In **Directory Files Test**, tap **Choose test folder**. Navigate to Drive and
   select that folder. Do not try to select an existing JSON file. Folder selection
   alone does not write anything. If Drive is unavailable/disabled or the folder
   cannot be selected, report the exact UI; stop this route without more saves.
3. If the app reports “Test folder selected”, tap **Write morning (1)** once.
   Record the local event. Independently refresh Drive web and download/read the
   JSON: exactly one canonical filename, revision 1 / morning / 1234 steps.
4. Tap **Write evening (2)** once. There is no second save picker. Independently
   verify exactly one canonical file now contains revision 2 / evening / 2468 steps.
5. Only after replacement passes, repeat evening. Expected local event is identical
   payload/no write. Verify the independent count and contents again.
6. Cancel **Choose test folder** and confirm the previous file remains unchanged.
   Relaunch the app, reselect the same folder, then try morning: older revision must
   be rejected. Folder permission is deliberately reacquired, not bookmarked.
7. Test a controlled offline evening/bedtime sequence and reconnection, preserving
   independent observations of ordering. Do not infer remote success from readback.
8. The **Fail before writing bedtime** probe raises a deterministic error before
   the write; it retains the highest-submitted watermark. Retry bedtime afterwards.
   This does not substitute for an actual provider-failure preservation check.

Stop on duplicates, corruption, stale rollback or unsupported directory access.
The older detailed failure/ordering criteria below still apply, but its old UI
button instructions are historical and must not be followed on this build.

## Implementation and limits

The picker opens `.folder` with `asCopy: false`. Each operation starts/stops access
to the security-scoped URL, coordinates writing the directory off the main thread,
checks its children and atomically writes the named child without deleting first.
An existing file must contain exactly one of our synthetic fixture byte sequences;
unknown files, extra entries and older revisions are refused. Equal bytes skip
writing. Local enumeration/readback is only provider-local evidence. Atomic local
replacement does not establish preserved remote identity or cloud atomicity.

The folder name is restricted to the new test name. This does not authenticate its
provider: the operator must choose Google Drive. No directory bookmark is persisted;
reselect after relaunch. The directory-route watermark and event log use separate
UserDefaults keys, preserving the old copy-route state. No reset button is offered.
The watermark is conservative and cannot order provider queues or other clients.
No HealthKit, OAuth, network client or production app code is involved.

Run the build commands below. `PolicyChecks.swift` now additionally exercises local
coordinated creation/replacement, identical no-op, stale rejection, injected failure
preservation and unexpected-content refusal. macOS file-coordination services may
require running the check outside the sandbox. These are local filesystem checks,
not simulator or Drive-provider acceptance. Xcode build/analyse validates compilation.

Apple authority: [directory access](https://developer.apple.com/documentation/uikit/providing-access-to-directories)
and [external document coordination](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller).

---

# Historical copy-export probe — rejected, UI removed


Separate disposable iOS app; does not link HealthKit or change WeeklyHealthReport.
Only invented data is exported. This is a storage experiment, not production export code.

Open `SyntheticDriveExport.xcodeproj`. The app is **Synthetic Files Test**.
Before device installation, obtain explicit authority for the named device and
test-folder writes. Set a separate, locally signed bundle identifier in Xcode;
do not reuse WeeklyHealthReport's app identifier or commit signing details.

Destination: one new, empty Drive folder named `WHR-Synthetic-2026-09-06`.
All revisions use `health-daily-2026-09-06.json`; do not rename it in Files.
The date is deliberately fixed synthetic data, not the device's current date.
Revision markers are `morning` (1), `evening` (2), `bedtime` (3).
`invented_steps` is respectively 1234, 2468, 3702. Repeating a revision yields
identical bytes. These fields do not ratify the production health JSON schema.

The harness presents `UIDocumentPickerViewController(forExporting:asCopy:)`.
It logs returned URLs only as a count, never as remote-upload proof. Provider
errors may remain within Files without a delegate error callback; record the
actual visible prompt. It never deletes a destination file.

One picker can be active at a time. A local persisted highest-submitted revision
rejects older attempts after a later one, even when the later attempt is cancelled.
Equal revisions remain retryable. This conservative guard is for this fixed-date,
single-installation probe only. It cannot prevent a provider replaying old queued
writes, or protect against another installation/client. Do not reinstall/reset the
app during relaunch tests. There is no watermark-reset button.

Three bounded synthetic source files may remain in the app's temporary directory
so picker callbacks do not trigger premature deletion. Their revision directories
are distinct, preventing newer payloads from changing an earlier source path.
Local event history is limited to 60 entries in UserDefaults. Uninstalling the
separate harness removes its local state. Production retention is still undecided.

## Build and local checks

From the repository root:

```sh
xcrun swiftc -module-cache-path /tmp/whr-swift-module-cache Tools/SyntheticDriveExport/ExportPolicy.swift Tools/SyntheticDriveExport/PolicyChecks.swift -o /tmp/whr-export-policy-checks
/tmp/whr-export-policy-checks
xcodebuild -project Tools/SyntheticDriveExport/SyntheticDriveExport.xcodeproj -scheme SyntheticDriveExport -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/whr-synthetic-derived CODE_SIGNING_ALLOWED=NO build analyze
```

The pure checks exercise serial admission, stale rejection, retries, restored
watermark and deterministic JSON. They do not exercise Files or Google Drive.

## Device protocol

Record iOS and Drive versions, Drive availability in Files, and separate-client
identity (for example Drive web in Chrome). Keep account identifiers private.
Record visible prompts verbatim, folder file count including same-name duplicates,
and downloaded JSON revision after each successful save. A preview may be cached:
refresh the separate client and download/open the actual file. Keep screenshots
free of unrelated personal filenames. Do not empty Trash or delete valid files.

1. Save morning online into the empty test folder. Confirm exactly one file and
   revision 1 from the separate client.
2. Start evening, then cancel the picker. Confirm one unchanged revision-1 file.
3. Tap the simulated pre-write failure. Confirm revision 1 remains. This is only
   a local no-write probe, **not evidence of provider failure preservation**.
4. Save evening online, choosing replacement if offered. Record prompts. Confirm
   one file, revision 2. If a second file appears, stop: the route fails uniqueness.
5. Force-quit and relaunch the harness. Tap morning: expect local rejection and
   no picker. Confirm Drive remains revision 2.
6. Disconnect the iPhone's Wi-Fi and cellular data manually. Attempt evening
   again (identical payload). Record whether Files errors, queues or completes.
   If it queues/completes, attempt bedtime while still offline. If an active
   picker blocks the second operation, record that fact instead of bypassing it.
   Reconnect. Observe final remote content and count until provider sync settles;
   record elapsed time. If bedtime was not submitted, save it after reconnection.
   A single final read cannot exclude a transient rollback; retain intermediate
   observations and do not call an unobservable ordering test a pass.
7. Confirm exactly one revision-3 file in the separate client. Repeat bedtime
   online, confirm exactly one file with identical JSON again.
8. Relaunch again; tap evening and expect rejection. Confirm revision 3 remains.
9. Test an actual provider write failure only through a safe, operator-controlled
   condition affecting this test destination. Offline behaviour counts as failure
   only if Files actually reports failure; a queued save is not a failed write.
   Do not revoke account-wide access, fill storage, or delete the prior valid file
   to manufacture failure. If no safe failure is available, mark it untested.

For every step record: action, local event/prompt, independent file count/content,
connection state, outcome (pass/fail/untested), and evidence source (operator or
direct observation). Stop on duplicates, corrupt replacement or stale rollback.
Finite device runs establish observed compatibility, not a universal provider
guarantee. An untested acceptance condition keeps the storage slice incomplete.

## If the picker fails

The next smallest candidate is a user-selected directory, locating and updating
the existing file under coordinated access rather than re-exporting a new copy.
Directory availability, replacement atomicity and offline ordering must be tested
on Drive before accepting it. It is not implemented here. If Drive does not support
that route, a subsequent scope decision is needed for an identity-preserving
transport that updates one existing Drive file ID with appropriate concurrency
control. Google OAuth/API work remains excluded from this slice. Never accept
same-name duplicates or deletion-before-save as a workaround.

References: [Apple document picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller),
[Apple directory access](https://developer.apple.com/documentation/uikit/providing-access-to-directories).
