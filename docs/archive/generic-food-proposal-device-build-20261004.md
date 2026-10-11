# Local iPhone nutrition acceptance build — 4 October 2026

**Ready:** development-signed WeeklyHealthReport **0.1.1 (19.1)**, bundle `com.otherweather.WeeklyHealthReport`, built from base `79efe83526668e47608e33cbf00655638c2d4826` plus the retained uncommitted nutrition implementation. Source hashes were frozen before building and rechecked afterwards. Deep/strict signature verification passed both before and after retaining the app. Existing signing team, HealthKit entitlement, OAuth client/redirect and current bundled privacy text were verified.

The paired iPhone 17 Pro Max was available, booted, on iOS 27.0.1 with Developer Mode enabled. Its identifier is covered by the development profile. The existing profile expires **5 October 2026 at 15:19:46 Europe/London (14:19:46 UTC)**. This local build is distinct from TestFlight build 19 and has not been uploaded.

## Installation status

**Not installed.** Automatic approval review rejected the install command before execution. Its reason: an in-place installation can replace the existing app and affect nontrivial local state; the user's “do it” was interpreted as approving build preparation, not this specific installation. Explicit approval for the in-place install is required. No attempt was made to bypass the rejection, uninstall the existing app, read its data container or launch it.

The retained app is at `/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/repair-20261004-v2/device-acceptance-v1/WeeklyHealthReport.app`. The adjacent source manifest, signed-app manifest (30 files), receipt, build log and signing records identify this exact artifact. The private provisioning record remains outside the repository.

## Physical acceptance checklist

Record observations against this exact build after installation approval. Every row is currently **not run**; simulator results do not fill these rows.

| Check | Expected observation | Result |
| --- | --- | --- |
| Installed identity | 0.1.1 (19.1), correct canonical bundle; no uninstall or data reset | Not run |
| Entry and privacy | Opening web nutrition review does not submit a query; disclosure identifies OpenRouter and its providers | Not run |
| Explicit public-source request | A deliberate request progresses through acquisition, extraction and applicability checking; retain URL, time and any failure | Not run |
| Evidence and unknowns | Original source can be inspected; missing nutrients appear unknown, never zero; identity/basis/values require acknowledgement | Not run |
| Confirmation | Quantity starts empty; no save until quantity and explicit match acceptance; no inferred density/serving weight | Not run |
| Save/reopen | Only an explicitly approved test entry is saved; reopened entry retains estimate status, source and missing values | Not run |
| Refusal/error | None/clarify or failed checking prevents confirmation; cancel leaves without saving; do not claim a branch passed if it did not occur | Not run |
| Large text and VoiceOver | Food/source names, unknowns, evidence, switches, focus order, quantity and disabled Save are understandable and operable | Not run |

Do not authorise or inspect personal HealthKit data for this nutrition check. No export or Drive sign-in is needed. Do not weaken credentials or manipulate a live account to manufacture an error. Live provider probes remain separately bounded and costed; the retained synthetic simulator fixture already covers save/reopen without personal ledger data.

The independent 12-source worksheet remains pending review by someone who has not seen model answers. Installation, successful launch and software checks do not establish nutrition accuracy or physical acceptance.

This phase incurred **zero provider calls**. No commit, push, TestFlight/App Store upload or external policy publication occurred.
