# Internal release privacy checkpoint — 4 October 2026

Scope: prerequisite fixes for WeeklyHealthReport 0.1.1 (19), containing the merged workout interval reader from #80 and the prior build 18 nutrition baseline. This is an engineering review for the existing one-tester internal TestFlight group, not an App Review approval, public App Store submission or a legal certification. No personal Health data, Drive export, provider request or device backup was used in this review.

## Findings and resolution

The inspected App Store Connect page had no privacy-policy URL and an unstarted App Privacy questionnaire. The app had contextual disclosures but no complete in-app policy. The app's notes and food records used protected Application Support files without explicit backup exclusion. File protection does not itself prevent backup.

The release prerequisite adds one policy source, `docs/privacy-policy.txt`, bundled unchanged for offline reading from **Today → Privacy policy**, plus a link to the same public repository document. The release operator must confirm that URL is publicly reachable after protected merge and save it in App Store Connect before uploading this build. Do not guess questionnaire answers or press Publish/submit a public version as part of this release.

`LocalHealthStorageDirectory` is a Foundation infrastructure adapter. It creates the existing app-owned `Application Support/WeeklyHealthReport` directory if necessary, sets and verifies `isExcludedFromBackup`, and throws on failure. Food composition prepares it before opening any ledger; notes prepare their containing directory before reads and writes. The exclusion is an operating-system request, not an absolute guarantee about every backup/restore scenario. The directory contains existing and future notes, draft databases, food/intake history, inventory, evidence attachments and SQLite sidecars. Paths, record bytes and database schemas do not change. Existing unavailable/error presentation handles failures. This cannot remove data already present in an older backup; the policy explains that limitation and the loss/recovery trade-off of excluding local records.

Stable invariants: no HealthKit writes, no new network service, no provider payload expansion, no automatic export, no data deletion/migration, no account or permission expansion. Storage policy stays outside the pure food and reporting domains. The policy is bundled once by an Xcode file reference rather than copied into a second source.

## Data-flow review

| Flow | Code and consent | Retention/control |
| --- | --- | --- |
| HealthKit report | `HealthKitClient`, `DailyHealthExportService`, `WorkoutHealthKitProjection`; read-only permissions, selected nutrition source/medications | Local calculation and previews; schema 7 recognises HR summaries, estimated energy, intervals, native distance, independently evidenced accepted treadmill distance and optional native zones, with explicit unavailable states. No raw HR series or arbitrary metadata. |
| Drive | `DailyDriveSessionController`, `DailyDriveExportCoordinator`, `DriveExportKit`; `drive.file`, visible exact-byte preview and explicit Export | Direct Google transport; ThisDeviceOnly Keychain credential/identity storage; no background queue. Disconnect does not delete exported files. |
| Food and notes | `FoodLedgerCompositionRoot`, `DailyNotesStore`, GRDB adapters | Owned protected, backup-excluded storage; retained immutable food history; note deletion/draft discard and verified-revision cleanup. No app-wide erase command. |
| Optional food providers | `GenericFoodSearchView`, `FoodWebDiscoveryView`, OFF transports, `GeminiFoodWebDiscovery`, `HTTPSFoodSourcePageAcquirer` | Disabled by default; submitted terms/barcode only, Gemini key plus separate automatic enable/validation (manual Developer tools web search remains explicit), capped native page acquisition. No HealthKit, diary or capture-evidence attachment. Provider retention is not controlled by the app. |
| Voice and camera/import | `DailyNoteSpeechCapture`, `FoodVoiceInputView`, barcode adapter, receipt text/PDF review | Speech requires on-device support with no server fallback; no audio persistence. Barcode camera use is optional. Label-photo OCR upload is not shipped. Receipt evidence can persist locally. |
| User exports | Report copy/share, explicit inventory file exporter, reviewed Daily JSON | The user chooses recipients/destinations. Copies, provider storage and older backups require separate deletion. No automatic cloud recovery. |

No analytics, advertising, tracking SDK or app backend was found in the reviewed app data paths. Apple TestFlight/crash feedback is a separate platform data flow; the policy does not promise that Apple receives no diagnostics.

## Official policy basis and remaining public submission work

Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) apply to TestFlight (§2.2). Sections 5.1.1 and 5.1.3 require a policy accessible in the app and metadata, meaningful consent and appropriate health-data handling, including the iCloud restriction. Internal-only distribution is not a blanket privacy exemption. The two concrete missing safeguards above are release prerequisites.

Apple's [App Privacy details guidance](https://developer.apple.com/app-store/app-privacy-details/) requires the collection questionnaire when submitting a new app or update to the App Store. Its definition includes off-device retention by integrated third parties; optional features and explicit user action do not automatically qualify for the limited optional-disclosure exception. Therefore **public App Store submission remains blocked until the whole-app questionnaire is completed**, including Google Drive, optional food providers, publisher requests, account linkage, purposes and retention. Do not select “Data Not Collected” solely because HealthKit calculations are local. Saving a factual policy URL is separate from answering or publishing the questionnaire.

[Apple filesystem guidance](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively) describes backup of Application Support and backup exclusion. The synthetic tests verify the resource flag and preserved content; they do not observe a personal backup or retroactively remove one.

[Gemini terms](https://ai.google.dev/gemini-api/terms), [Google privacy](https://policies.google.com/privacy) and [Open Food Facts privacy](https://world.openfoodfacts.org/privacy) are linked in the policy. Gemini's existing consent already explains grounding retention and paid/unpaid/regional differences. No provider credentials or requests were used to verify their behaviour. The app must continue to keep health/history out of search payloads and warn against sensitive search terms.

## Release gate

Before uploading: pass focused storage/policy tests, the complete simulator suite and static analysis; independently review the final diff; merge through protected GitHub checks; verify the public policy URL and saved App Store Connect URL; archive the exact merged source with only the build-number override. Preserve signing, OAuth, Health/camera/microphone/speech purpose strings and encryption metadata. Use a fresh task-specific archive/export directory and the next build number verified against live Apple inventory, and upload once to the existing internal audience.

After uploading: verify processing, Testing and the existing group, save accurate What to Test, and retain private signature/IPA receipts. Release availability does not satisfy #116's supervised Watch → HealthKit → reader → reviewed export acceptance, physical-device accessibility, or public App Review. Those remain explicit separate evidence.

## Local verification receipt

The frozen source and bundled policy passed 30 focused notes/storage tests, then all 312 simulator tests on the dedicated iOS 26.5 simulator. Domain coverage was 97.26% (95% minimum). Xcode static analysis passed. Independent review found no P1/P2 code findings; its two policy wording corrections were applied before the full suite. All 82 source/project/policy SHA-256 inputs remained unchanged after the gates.

Private local evidence: `/private/tmp/whr-privacy-focused.log`, `/private/tmp/whr-privacy-full.log`, `/private/tmp/whr-privacy-full.xcresult`, `/private/tmp/whr-privacy-coverage.md`, `/private/tmp/whr-privacy-analyze.log`, and `/private/tmp/whr-privacy-frozen-input-sha256.json`. These are synthetic software results, not a device/backup or provider-retention experiment. App Store Connect URL publication and build 19 delivery are recorded separately after protected merge; neither has been claimed here.

The accepted-distance repair preserves the local/user-selected-Drive flow. Legacy recovery reads only an exact workout-associated distance record with strict source/sync/time validation; it does not add Health writes, a raw HR series, new permissions, providers or background transfer. Query failures block publication. The privacy policy and export preview describe the distinction between native and accepted treadmill distance. Public submission still requires the whole-app questionnaire checkpoint above.
