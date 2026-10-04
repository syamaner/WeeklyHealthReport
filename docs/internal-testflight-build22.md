# Internal TestFlight 0.1.1 (22)

Build22 was uploaded once on 4 October 2026 and verified **Testing**, expiring in 90 days, for the existing **Internal Testing** group with one tester/invite. No new testers or external distribution were added. The reviewed four-paragraph What to Test text was saved and read back in full after an explicit reload (1,517 characters; 2,483 remaining). This establishes internal availability, not installation or personal Health validation. Issue #80 remains open.

## Released source and compatibility

The signed source is protected main `6b5f279b95cbadb21b7a2e081ff3f3d4b1df28f3`, tree `0d82ec0cc5a043aefb1cda2b70356c795250e2fa`. [Reader PR185](https://github.com/syamaner/WeeklyHealthReport/pull/185) and [compatibility PR187](https://github.com/syamaner/WeeklyHealthReport/pull/187) merged through normal protections. All 14 jobs of [exact-source main CI37235752509](https://github.com/syamaner/WeeklyHealthReport/actions/runs/37235752509) succeeded. This receipt is later documentation; its own CI is separate from signed-source evidence. After build22 was released, nutrition PR186 advanced protected main to `5082236361cda80220427396e2bb736b5c16deb1`. Those later nutrition changes are not in build22. This receipt is rebased onto that newer main without changing or redistributing the signed package.

The reader supports native numeric metadata, Health interchange1/2/3 and Daily schema7 with a separately labelled accepted treadmill distance. Native distance retains its existing meaning. Legacy recovery requires a single exactly bound trusted associated sample; new accepted aggregates preserve canonical producer decimal precision. No saved Health record is rewritten. Unsafe pause-spanning native samples are omitted by the compatible producer, so Apple Health/Fitness may have no native distance even when accepted distance is available here.

The exact already-shipped build21 nutrition runtime/package/test/resource inputs are preserved, including OpenRouter source/applicability review. See [the integration provenance](build21-reader-compatibility.md). This does not establish independent live-provider or nutrition acceptance. Install this reader before the forthcoming PacePrompt Health3 update; this receipt makes no claim that the producer update is already distributed.

## Package verification

| Artifact | SHA-256 |
| --- | --- |
| Actual uploaded IPA, selected from Xcode's upload pipeline and retained | `b5c31fe2a25ebec5461da5ef655d7ee6b983ebff019103f0289af43c8da9b1ed` |
| Separately verified local export | `59932955a8db99b55d35e5ae2439d0ad39fbecf32aeb1487e999e52b7280bef2` |
| Reviewed public/bundled privacy policy | `59da55343bdb634f135f87619006a55c9aa8480db66f7fc845f61accb6575031` |

Archive, exported app and matching dSYM share UUID `CCEB3C20-4194-314A-9F90-77F2CBD8F6AD`. Xcode27.0 (27A266a), Swift6.4 and the iOS27 SDK produced the archive; both native workout/activity zone adapters are compiled into it. The actual uploaded package passed an independent provenance, host-trust signature, distribution-profile, entitlement, UUID and metadata review. All 336 pinned source inputs and 12 catalogue/prompt/schema/licence resources matched; resources and OAuth/permission/encryption metadata were also compared with the actual uploaded build21 package. All 47 Mach-O sections match the archive. Local and uploaded executables differ only in their signing region.

Xcode changed the archive's outer `Info.plist` during upload. Separate pre/post manifests retain that exact change; application and dSYM bytes stayed unchanged. Whole-archive byte immutability is therefore not claimed. Existing approved configuration was reused with only the build number changed; automatic version management was disabled and export/upload were internal-only.

The [existing App Store Connect privacy URL](https://github.com/syamaner/WeeklyHealthReport/blob/main/docs/privacy-policy.txt) was read back, and anonymous public policy bytes matched the reviewed bundled policy. This was an internal release; the unsubmitted App Store privacy questionnaire remains a prerequisite for a future public App Store submission.

## Validation and boundaries

- Combined simulator suite: 337 total, 336 passed, one explicit interactive opt-in skip, zero failures; domain coverage96.93%; static analysis succeeded.
- FoodLedger package: 695 total, 689 passed, six explicit offline/opt-in skips. Closed dependency guards passed, including eight negative controls.
- Actual synthetic paired Watch/phone HealthKit pipeline: 13 cases, 728 independently expected fields per transport, two named test methods passed, and all 13 direct-query/archive JSON pairs equal. The final integrated source binding and 986 retained evidence hashes were independently verified. This executes actual producer persistence, paired-phone visibility, reader query/recovery, projection, Daily7 encoding and strict identity admission.
- The bounded eight natural safe attempts did not isolate a final-only submillisecond pause overlap with valid start bounds. Deterministic policy tests, measured old native clipping and native mid-workout pause suppression are separate evidence. No stronger native boundary claim is made.
- Populated physiological statistics, physical-device behavior, VoiceOver, user re-export and optional personal Drive delivery remain separate acceptance steps. Raw timestamped heart-rate sample series are not exported. No live provider call or personal export formed part of these gates.

Initial failures, interrupted runs and policy-negative native cases remain retained; they were not relabelled as passes. Superseded build20 was never uploaded. The earlier build17 archive-path incident remains unresolved: no pre-existence snapshot proves whether that path was overwritten or newly created, and original shipped17 dSYMs were not found in the non-exhaustive inspected locations. Earlier IPAs/logs were preserved; the later candidate at that path is not evidence of shipped17 symbols.

Private archive, both IPAs, matching symbols, exact source inputs, upload provenance/logs, native and software gate references, Apple readbacks and hash-verified retention evidence are kept outside Git. Local signing configuration and credentials are excluded from the retained deliverable. Re-export the same previously saved workout in build22 and inspect native versus accepted distance and interval metadata before sharing any personal export.
