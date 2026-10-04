# Internal TestFlight0.1.1(23)

Build23 was uploaded once on4October2026 and verified **Testing**, expiring in90days, for the existing **Internal Testing** group with one tester/invite. All five approved What to Test paragraphs persisted across an explicit reload (1,813characters;2,187remaining). No new tester or external distribution was added. Build22 remains available. This proves internal availability, not installation or personal Health acceptance.

The user requested another exporter build after the newer nutrition review merged. Build23 includes protected source `5082236361cda80220427396e2bb736b5c16deb1` ([PR186](https://github.com/syamaner/WeeklyHealthReport/pull/186)); all14 jobs of [exact-source main CI37237659880](https://github.com/syamaner/WeeklyHealthReport/actions/runs/37237659880) succeeded. The later build22 receipt merge `d7c5344127c4a565fdf8d1ca9fbb862724e2ee74` is documentation only and is not in this signed package. This receipt's own CI is separate from signed-source evidence.

Build22 already provides the compatible workout reader. Build23 preserves that repair and adds the newer explicit food-market preference, representative-source review and bounded fallback behaviour. Only four runtime Swift files changed from22; Health/Drive access, schemas, native reader, credentials, dependencies, bundled resources and privacy policy are unchanged. No independent nutrition or live-provider acceptance is inferred from this release.

## Verified package and provenance

| Artifact | SHA-256 |
| --- | --- |
| Actual uploaded IPA retained from Xcode's upload pipeline | `aa944915f52121d6497b7e3211c0709cfac86ef75fc9c50dd9dc1c995d696372` |
| Separately verified local export | `bf8501d15294bb31ab9ed20a2b7f6ca81125617f2df66c411c6e8c8b410a21bd` |
| Public/bundled privacy policy | `59da55343bdb634f135f87619006a55c9aa8480db66f7fc845f61accb6575031` |

Archive, package and matching dSYM UUID: `2B43CFCB-A04D-36F6-A5FA-404900EE9334`. Xcode27/Swift6.4/iOS27 SDK built the archive; native workout/activity zone adapters are compiled in. Independent local and actual-uploaded package reviews verified provenance, host-trust signatures, profile/certificate, entitlements, OAuth/permissions/encryption metadata, all336 source/gate inputs,12 resources and all47 Mach-O sections. Local/uploaded executables differ only in their signing region. The actual uploaded build22 package remained unchanged and supplied the comparison baseline.

Xcode changed only the archive's outer `Info.plist` during upload; separate pre/post manifests retain this bookkeeping change, and app/dSYM bytes are unchanged. Approved same-repository configuration was reused with only build22→23; automatic renumbering was disabled and both export/upload were internal-only. The existing [privacy-policy URL](https://github.com/syamaner/WeeklyHealthReport/blob/main/docs/privacy-policy.txt) was read back in App Store Connect; anonymous public bytes equal the reviewed bundled policy. No public App Store submission or questionnaire change was performed.

## Current-source validation

- Full simulator:337 total,336 passed,one explicit interactive opt-in skip,zero failures; static analysis succeeded; domain coverage96.93%.
- FoodLedger package:710 total,704 passed,six explicit offline/opt-in skips,zero failures.114 offline evaluation tests and the dependency boundary gate passed. No provider request occurred.
- Actual source508 native read-only rerun:13 existing synthetic cases,728 independent fields per transport,two named test methods passed,all13 direct-query/archive JSON pairs equal. All1,103 frozen evidence files were independently hash-verified. The run exercises real query/recovery/projection/Daily7 serialization/strict identity using the already-authorised synthetic simulator store; no new workouts or grants were created.

Private retention preserves exact source inputs, archive/matching symbols, both IPAs, upload logs/provenance, Apple readbacks and software/native evidence with copy hashes and restricted permissions. Credentials and local signing configuration are excluded from the retained deliverable; originals remain intact.

## Remaining acceptance

The same saved workout should be re-exported on the user's device and inspected before any personal sharing. Native distance remains separately labelled from accepted treadmill distance. Legacy recovery never rewrites Health records; new unsafe pause-spanning native samples can be absent from Apple Health/Fitness while accepted distance remains available. Zero and unavailable stay distinct. Raw timestamped heart-rate series are not included.

The bounded natural simulator attempts did not isolate a final-only submillisecond pause overlap with valid start bounds; deterministic policy tests and other measured native boundaries remain distinct evidence. Populated physiological values, physical-device behaviour, VoiceOver and personal Drive delivery remain separate acceptance. Issue #80 remains open.

All earlier artifacts remain preserved. Build20 was never uploaded. The historical build17 archive-path uncertainty and non-exhaustive original-symbol search remain as documented in the [build22 receipt](internal-testflight-build22.md); this release makes no new claim about those missing historical symbols. Future public App Store submission still requires completing the whole-app privacy questionnaire.
