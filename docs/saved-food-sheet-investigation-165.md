# Saved-food sheet investigation (#165)

Scope: app saved-entry navigation and presentation only. The build-11 observation remains provisional: no private ledger contents or physical-phone access are used here. Unknown consumed calories for 200 mL against per-100-g nutrition are a separate supported unavailable calculation state, not evidence of a blank-sheet cause.

## Architecture and contract

`FoodConfirmationService.reopen` owns saved-record reconstruction; SQLite remains an infrastructure adapter. The app's `SavedFoodEntrySession` owns the selected entry identity and loading result, and `SavedFoodEntrySheet` renders it. No persistence schema, food identity, nutrition calculation, provider or quantity policy changes are required.

The former sheet used an independent Boolean and optional model, with an empty `NavigationStack` when the model was absent. The repair presents a single identifiable session through `sheet(item:)`. Every presented session has visible loading, loaded, missing-record or failure content and an unconditional Close action. Missing and failed reads offer Retry. Loading is local synchronous reconstruction started by the sheet task; no artificial asynchronous service or loading delay is added.

Regression fixtures use a temporary synthetic SQLite ledger: accept and save whole milk with 200 g and 200 mL, reconstruct the saved model, present the native sheet, dismiss, and reopen. They check quantity and source nutrition survive without edits or automatic saves. State tests distinguish missing reads from thrown failures and exercise retry. Package contracts additionally cover unavailable volume totals and both storage adapters.

## Native comparison

On the dedicated iOS 27.0 iPhone 17 Pro Max simulator, the native stored-record fixture passed four presentations with the item-driven route. A temporary comparison harness restored the former `@State` optional model plus Boolean presentation pattern: successful reconstruction and optional assignment occurred before setting the Boolean, with the model read only inside the sheet closure. The same fixture failed its populated-confirmation assertion twice (first presentation for each of gram and mL); reopening passed. The loader remained successful, separating this presentation failure from unavailable nutrient conversion. This demonstrates a stale optional-content presentation path in that pattern, without proving it caused the particular build-11 occurrence.

The temporary comparison is excluded from production and regression code. Its log is `/tmp/wh165-legacy-native.log`; the committed item-driven fixture is `FoodSearchQuantityNativeTests.testSyntheticSavedGramAndVolumeEntriesPresentDismissAndReopen`. Recovery tests check native navigation titles, states, dismissal, and retry transitions. A synthetic render was separately inspected for Close and Retry; UIKit label inspection cannot reliably introspect SwiftUI recovery-body text.

## Evidence boundary and retest

These software checks cannot establish the cause of the observed TestFlight sheet or rule out Mirroring behaviour. Keep #165 open pending an authorised device retest. Test first opening and dismissal/reopening of synthetic supported gram and unsupported volume records; ensure populated details or explicit recovery content and Close remain visible. For unsupported volume, ensure no density is inferred and consumed totals remain unavailable. Record device/build and distinguish Mirroring from direct phone interaction.

The saved-entry route permits #166's software save/reopen validation to proceed. Its measured-weight persistence semantics and physical acceptance remain #166's responsibility. No TestFlight upload, phone control, personal-data export, source adoption or HealthKit writes are included.

## Final software validation

- Complete FoodLedgerKit package run: 213 tests, one skipped, no failures (212 passed).
- Complete simulator suite on dedicated iOS 27.0 iPhone 17 Pro Max: 277 tests, no failures; includes four native quantity/sheet tests.
- Xcode static analysis: succeeded. `git diff --check`: clean.
- No physical device validation or TestFlight delivery occurred. The unsupported-volume calculation and nutrition-label projection are not changed here.

## Hosted transition-test repair

Run `36347030840` at rebased head `5a198efe` failed on the hosted iPhone 17 Pro / iOS 26.4.1 simulator. Its xcresult identified only dismissal assertions: recovery test line 98 and stored-entry test dismissal checks found a `PresentationHostingController` still present after the fixed 600 ms sleep. Content, loaded state and reconstruction assertions had passed. This evidence warrants a test-readiness repair rather than another production change.

Native tests now poll for populated navigation content with a completed presentation transition, and for `presentedViewController == nil` before reopening. Each poll yields the main actor and has an eight-second deadline; the original content, state, provenance and dismissal assertions remain. Test windows still own and restore their key-window state, preferring a foreground-active scene. This does not disable animations or alter hosted parallel settings.

Local validation uses the nearest installed runtime, iOS 26.5 with Xcode 27, on an isolated iPhone 17 Pro simulator with coverage and default parallel testing enabled. It cannot exactly reproduce the hosted Xcode 26.6 / iOS 26.4.1 environment; fresh hosted CI remains required.

A single temporary former-pattern comparison was repeated on that same iOS 26.5 simulator with the identical bounded readiness checks. First presentation for each stored-record case still lacked `Confirm food` after the eight-second deadline (four assertions: readiness plus content for each case), while reconstruction and dismissal assertions passed. This rules out the old fixed sleep as the sole explanation of that local content reproduction. The comparison is excluded from committed tests; the specific build-11 cause remains unconfirmed.

After restoring the committed harness, the final complete simulator run passed all 277 tests with coverage and default parallel testing. The focused native run also passed all four tests. No production code changed in this follow-up, so static analysis was not repeated. Expected-failure comparison diagnostic collection was stopped only after completed assertion stdout was preserved; its finalized xcresult retains the content failures. Fresh hosted validation is still required before merge.
