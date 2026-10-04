# Internal TestFlight build 21 — preparation history

> Superseded: the user explicitly authorised upload, which succeeded. Build 21 is now Testing in the existing internal group. See [completed delivery](internal-testflight-build21.md). The blocked state below is historical.

Date: 4 October 2026. The user requested delivery of the new nutrition build through TestFlight. A fresh distribution archive and internal-only IPA are ready. **Nothing was uploaded, assigned or distributed.**

Automatic approval review rejected the upload command before execution because it treated the earlier no-release/no-distribution restriction as still active. Upload attempts remain zero. The blocked command would have uploaded 0.1.1 (21) for the existing Internal Testing group, currently one tester. Explicit confirmation of that exact upload is required; do not retry through another tool or upload route to bypass the decision.

## Verified package

* Version **0.1.1 (21)**; App Store Connect app 6812893951; distribution bundle `com.otherweather.ReportWeeklyHealth`.
* Base `22df0958244d790ca8021b734e056f4c1140afd5` plus frozen uncommitted nutrition changes. Main PR #184 was fast-forwarded into the isolated worktree; four upstream paths did not overlap local work, and all 28 modified tracked files retained their hashes. The shared checkout is untouched.
* Build 20 belongs to the separate workout release worker and was not overwritten, uploaded or otherwise changed. Safari showed build 19 as the latest uploaded version during preparation.
* 340 source/project/resource inputs are retained with hashes. The archive used the prior release configuration with only build number 20 → 21. This is distinct from the earlier local development build 19.1 and its different development signing configuration.
* Combined app: **317 simulator tests passed**, one expected opt-in skip; static analysis passed. Archive and export succeeded.
* IPA SHA-256: `78c8d53dc2361f35c5650a34fedc9ed973af64956ab715ca93bf6dd768fef1af`.
* Archive/export/dSYM UUID: `3E974254-53EF-328D-BE35-450476418BEF`.
* Deep/strict signature verified; distribution team/profile match, debugger entitlement disabled, HealthKit entitlement retained, no device-specific profile. Internal-only export is enabled, and automatic build renumbering is disabled.
* Existing OAuth, privacy-purpose and encryption metadata match the previous distribution package. Current bundled policy matches nutrition source. Four food catalogues and extraction prompt v11/schema v5 match the frozen code. Public policy publication was not performed.

## Delivery after approval

Use the retained archive and internal-only upload settings. Upload once, retain Apple's actual uploaded package identity separately if Xcode repackages the local export, and verify processing in Safari. Add the retained 1,099-character What to Test text, assign only the existing Internal Testing group, and reload to verify status. Do not add testers, external testing or submit for public App Store review.

The internal group uses manual distribution for Xcode builds. Its existing one tester showed build 19 installed. Build 21 has not been installed or tested physically. Nutrition independent accuracy and calibrated confidence remain unestablished; the notes retain these limits.

## Retained artifacts

Private evidence root: `/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-testflight-21-20261004`.

The root contains `WeeklyHealthReport.xcarchive`, `export/WeeklyHealthReport.ipa`, `verified-package/`, `source-snapshot/`, `source-manifest.json`, `receipt.json`, `combined-test-analysis.log`, `archive.log`, `export.log`, `verify-package.py`, `what-to-test.txt` and inherited release/export/upload configuration. No signing credentials are copied into the repository.

Provider spend during preparation: zero. No commit, git push, physical-device installation, HealthKit export, public-policy update or external distribution occurred. Source remains uncommitted and reproducible from its frozen snapshot.
