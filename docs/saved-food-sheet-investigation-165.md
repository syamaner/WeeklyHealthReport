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
