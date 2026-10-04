# Internal TestFlight delivery: 0.1.1 (19)

WeeklyHealthReport 0.1.1 (19) was confirmed **Testing** on 4 October 2026 in the existing **Internal Testing** group with one tester and one invite. App Store Connect reported 90 days remaining; no install count was reported. The build was uploaded once; no new testers, external distribution or public App Store submission were added.

## Source and validation

- Signed source: `fcf3c8c8c3f638dd14f2dfeb88a2213020063297`, the protected merge of [PR182](https://github.com/syamaner/WeeklyHealthReport/pull/182). Its tree equals independently reviewed head `434d40e3b338c9be6956d1e549c9245ad7eb4ee8`.
- Protected-main CI [37191321170](https://github.com/syamaner/WeeklyHealthReport/actions/runs/37191321170): all 14 jobs passed.
- Local validation: 30 focused tests, 312 complete simulator tests, 97.26% domain coverage, static analysis passed, and all 82 frozen source/project/policy hashes unchanged.
- PR CI attempt 1 had 311 passing tests and one failure in the existing bounded WebView text assertion, `FoodSearchQuantityNativeTests.testGeminiSuggestionsRenderWithoutScriptsOrPersistentStorage`. The unchanged local recheck passed. One authorised failed-job retry passed on the unchanged reviewed head; both attempts were retained. The first attempt is not reported as passing.
- Archive: Xcode 27.0 (`27A266a`), Swift 6.4 (`swiftlang-6.4.0.34.1`), iOS 27.0 SDK. The signed executable links the native workout and activity heart-rate-zone APIs. They remain runtime-gated to iOS 27 and visible native Health data; older systems report unsupported.

## Package identity

Xcode's upload operation exported a separate package from the same archive. Both packages passed the same independent checks; their ZIP hashes are deliberately distinguished.

| Artifact | SHA-256 |
| --- | --- |
| Actual uploaded package, retained from Xcode's logged upload pipeline path | `ad157a9ba3286aa3d0fd1ce9dd82eafbd28649698e634b12cdb6323e42c1f89c` |
| Earlier local export | `1d12eea0d67f9c5d13005ebf455125b5480c6e0443a27d426d54a7a4f047363a` |
| Bundled privacy policy | `0b69fa94cbe9ed9ea42f450988c4b7b02b2b2dd6bf9561690ac24318b563649b` |

Verification covered the distribution signature, signing certificate/profile relationship, HealthKit entitlement, disabled debugger entitlement, internal-only export/upload settings, unchanged OAuth/privacy/encryption metadata from build18, all four public food catalogue resources, exact policy bytes and frozen source. Archive, both exported executables and retained dSYM UUIDs match. No signing configuration or credentials are included here.

The upload completed at 09:25:54 UTC. Apple processing then completed; the build was assigned only to the existing internal group. Build-specific What to Test was saved and persisted after a full reload. Its submitted text is 1,407 characters. Accessibility readback truncates the third paragraph at 500 characters; the other paragraphs, paragraph prefix, complete character count and saved state were verified. This is not a claim of a full API readback of the text.

## Privacy and acceptance boundary

The [privacy policy](https://github.com/syamaner/WeeklyHealthReport/blob/main/docs/privacy-policy.txt) was accessible publicly with exact source bytes and saved as the App Store Connect privacy-policy URL; persistence was verified after reload. The optional choices URL and public privacy questionnaire were left unchanged. Public App Store submission remains pending a complete whole-app questionnaire, as described in the [privacy checkpoint](internal-release-privacy-checkpoint.md).

The existing nutrition baseline from build18 remains included. No real Health data, Drive export, provider query or physical device action was performed for this release. TestFlight availability does not establish installation, VoiceOver/accessibility acceptance, HealthKit visibility, interval accuracy on a device or the Watch-to-Health-to-reader round trip. Issue #80 remains open for the supervised [reader acceptance procedure](workout-reader-acceptance.md), together with PacePrompt issue116.

## Prior artifact-path caveat

During initial preparation, an unuploaded candidate17 archive was created at the path recorded for prior build17. There was no pre-run existence snapshot, so replacement of a surviving archive versus recreation of an already-removed path cannot be established. The current archive at that path does not represent shipped build17. Prior build17/build18 IPAs and recorded build17 logs still match their receipts. The original build17 dSYM was not found in the known artifact paths checked; the search was not exhaustive. Build19 uses a unique task-specific archive path, and those earlier artifacts remain untouched after discovery.

Private delivery evidence retains the actual uploaded IPA, local export, source archive and matching dSYMs, receipts, selected upload-package provenance, validation logs/digests and exact bounded accounting. Independent artifact and receipt review found no blocking discrepancies. The release accounting entry is `WHR-INTERNAL-19-2026-10-04` in [DEVELOPMENT_NOTES.md](../DEVELOPMENT_NOTES.md).
