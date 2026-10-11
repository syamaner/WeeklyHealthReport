# UX revamp phase 1: navigation shell and Settings (architecture gate)

Status: **gate passed with changes, 11 October 2026; changes folded in below.** Issue #194; spec [ux-revamp-v1.md](ux-revamp-v1.md); wireframes `docs/designs/ux-revamp-v1/Settings.dc.html` and `Main.dc.html`.

Presentation and composition only. No contract, schema, HealthKit query, egress, provider or persisted record change. The only persisted values touched are the existing navigation destination string and existing UserDefaults preference keys, read and written with unchanged meaning. Opening or building Settings sends no network request of any kind.

## Responsibilities and file layout (app target unless stated)

Files sit flat in the existing `Views` and `FoodLedger` groups; the project uses explicit `PBXFileReference` entries, so each new file is added to `project.pbxproj` for the right target.

| File | Owns |
|---|---|
| `Views/AppRoute.swift` | `AppRoute` enum, `restoredPath(from:hasDraft:availableRoutes:)` (pure) |
| `Views/AppNavigationCoordinator.swift` | Path, protected path, restoration and destination persistence; no UIKit |
| `Views/AppShellView.swift` | Root `NavigationStack`, route-to-screen mapping, gear, lifecycle notification subscriptions, screenshot registration, medication authorisation request |
| `Views/HealthReportView.swift` | Current `reportForm`, `WeeklyReportPresentationState`, the report's medication help sheet |
| `Views/MedicationAccessHelpView.swift` | Help content; optional `done` action injected only by the report sheet |
| `Views/FoodIntakeHomeView.swift`, `Views/SavedFoodEntrySheet.swift` | Moved verbatim apart from the link changes below |
| `Views/SettingsView.swift` | `SettingsSectionID`, `SettingsSection`, `SettingsRow`, `SettingsToggle`, `AppSettings`, generic rendering |
| `Views/SettingsContributions.swift` | Export, Apple Health and About factories |
| `Views/DeveloperToolsSettingsView.swift` | Developer tools toggle and the DEBUG-only Diagnostics link |
| `FoodLedger/FoodLedgerSettings.swift` | Food search and Data factories, `FoodMarketPreference`, food market picker, `InventoryBackupView`, `InventoryBackupFile` |

`WeeklyReportView.swift` is deleted once its parts move.

## Route type and coordinator

`AppRoute: String, Codable, Hashable, CaseIterable` keeps every existing raw value (`foodLog`, `healthReport`, `dailyExport`, `genericFoodSearch`, `foodListImport`, `barcodeFoodCapture`, `inventoryReview`, `commonFoods`, `foodReresolution`, `notes`, `noteEditor`, `diagnostics`, `privacy`) and adds `settings`, `webLookupKey`, `foodMarket`, `dataBackup`, `medicationAccess`, `developerTools`. It is a rename, not a mapping, because raw values are the stored contract; an older build reading a new raw value already falls back to an empty path. `.diagnostics` stays in the enum in release builds and always restores to `[]`.

`AppNavigationCoordinator` (`@MainActor ObservableObject`, replaces `WeeklyReportNavigationController`) keeps `path`, `acceptPathChange`, `replacePath`, `append`, `protectCurrentPath` and `restoreProtectedPath` with identical semantics and owns persistence under the same key `weeklyReport.navigationDestination.v1` through an injected `UserDefaults`:

- `restoreIfNeeded(hasDraft:availableRoutes:)` runs once per coordinator; a second call is a no-op even when the stored value was unknown.
- `recordDestination()` is called by the shell's `onChange(of: path)` after restoration. It stores `path.last?.rawValue ?? ""`, so popping to root records `""` and foregrounding stays at Home.
- `willResignActive()` protects the path and stores the last route only when the path is non-empty; an empty path never overwrites the stored value.
- `didBecomeActive(hasDraft:availableRoutes:)` restores the protected path, else, if the path is empty, restores the stored destination.
- Notification subscriptions stay in `AppShellView`; the coordinator imports only Foundation and Combine.

Restoration keeps only the last route and respects availability. `availableRoutes` is every route linked from the composed Settings sections plus the fixed routes (all other cases). A Settings child that is not available (for example `medicationAccess` below iOS 26, the deployment target being iOS 17.0, or `webLookupKey`, `foodMarket`, `dataBackup` when `FoodLedgerCompositionRoot` fails) restores to `[settings]`.

| Stored value | Restored path |
|---|---|
| `foodLog`, `healthReport`, `dailyExport`, `genericFoodSearch`, `foodListImport`, `barcodeFoodCapture`, `commonFoods` | `[route]` (unchanged) |
| `notes` | `[dailyExport, notes]` (unchanged) |
| `noteEditor` | `[dailyExport, notes, noteEditor]` with draft, else `[dailyExport, notes]` (unchanged) |
| `diagnostics`, unknown, empty | `[]` |
| `privacy`, `inventoryReview`, `foodReresolution` | `[settings, route]`; the parent moves to Settings. `inventoryReview` and `foodReresolution` are fixed routes, so without a food ledger they keep today's unavailable screen |
| `settings` | `[settings]` |
| `webLookupKey`, `foodMarket`, `dataBackup`, `medicationAccess`, `developerTools` | `[settings, route]` when available, else `[settings]` |

Protected path: unchanged. The note editor's `willOpenApplicationSettings` and `willResignActive` protect the current path; `acceptPathChange` ignores SwiftUI pops until `didBecomeActive` restores it.

Screenshot eligibility: `WeeklyReportScreenshotEligibility.isEligible` keeps `navigationPath == [.healthReport] && !isTransientUIPresented`, typed as `[AppRoute]`. The shell owns `WeeklyReportPresentationState` and passes it to `HealthReportView`. `MedicationAccessHelpView` pushed from Settings has no `done` action and never touches that state.

## Settings contributions

```swift
enum SettingsSectionID: Int, Comparable, CaseIterable { case foodSearch, export, data, appleHealth, about }
struct SettingsSection: Identifiable { let id: SettingsSectionID; let title: String; let footer: String?; let rows: [SettingsRow] }
struct SettingsRow: Identifiable { enum Kind { case link(detail: @MainActor () -> String?, route: AppRoute); case toggle(SettingsToggle) }; let id: String; let title: String; let kind: Kind }
@MainActor final class SettingsToggle: ObservableObject { @Published private(set) var isOn: Bool; func set(_:); func reload() }
```

Each feature provides a factory returning `SettingsSection?`; `WeeklyHealthReportApp` (composition root) assembles them into `AppSettings` (sections plus the developer tools toggle) for the shell. `SettingsView` sorts by `id`, renders rows generically and reloads toggles and details on appear. `SettingsToggle` is the small observable that redraws after `set`, which writes through its closure and then re-reads the stored value. `SettingsSectionID` is a deliberately closed ordering: adding a section is a reviewed change to presentation order, not a plug-in.

Why this shape: the real variation is which features are composed (food ledger may fail to open, medication help is iOS 26 only, diagnostics is DEBUG only), and each section changes with its feature. Two closed row kinds cover every wireframe row (choices such as market use push-to-list), keep sections inspectable for reachability and availability, and avoid `AnyView`. A value type suffices; no section has behaviour beyond its rows.

| Section (factory) | Rows mapped to existing code |
|---|---|
| Food search (food ledger) | Toggle "Online food database" through the root's existing `FoodSearchPreferences` (`foodSearch.openFoodFacts.automatic.v1`). Link "Web lookup" to `.webLookupKey` (public `OpenRouterFoodKeyView`), detail from `hasSavedKey` and `keyIsUsable` only: "Key missing", "Revalidate key", "Key added". Settings never calls `validateAndSaveKey` or `revalidateSavedKey`. Link "Food market" to `.foodMarket`, detail the current market. Footer: existing privacy line. |
| Export (no dependency) | "Google Drive" and "Folder", both to `.dailyExport`, with no detail until #200. The factory takes no session, so building Settings cannot call `prepareForPresentation` or any network path. |
| Data (food ledger) | "Backup and restore" to `.dataBackup`; "Receipts and food inventory" to `.inventoryReview`; "Nutrition updates" to `.foodReresolution`. |
| Apple Health (iOS 26 only) | "Medication access" to `.medicationAccess`. |
| About | "Privacy policy" to `.privacy`; "Developer tools" to `.developerTools`. |

- Developer tools key: one public constant `FoodSearchDeveloperTools.storageKey` (`foodSearchDeveloperToolsEnabled`) in `FoodLedgerPresentation`. `GenericFoodSearchView` takes the `UserDefaults` store from the root (the same instance the root was built with), and the Settings toggle writes to that store.
- Food market: `FoodMarketPreference(defaults:)` is the one accessor for `food.webReview.market.v1`, used by `proposalReviewModel` and the picker. `.unspecified` removes the key, as today.
- Backup: `InventoryBackupView` reuses `LocalInventoryViewModel` from `root.inventoryModel()` as the owner of error (`message`) and busy (`pendingCommand`) state. `InventoryBackupFile.read(_:)` is the single helper for security-scoped access and the zero-size and `InventoryBackupCodec.maximumBytes` guards. Archive format and codec are unchanged.
- The gear is a `ToolbarItem` on Home labelled "Settings" (identifier `settingsButton`) calling `coordinator.openSettings()`, which appends `.settings`. Settings is pushed, so the wireframe's "Done" is the back button.

## Removals and moves

- Health report: the "Food logging" section and its CoFID/USDA caption; the DEBUG "Developer Diagnostics" link (now Settings > Developer tools).
- Home: the "Privacy policy" link. "View health report" stays until #199.
- Food Log: the "Review" section (receipts, nutrition updates).
- Inventory and common foods: the toolbar "Backup" menu.
- `GenericFoodSearchView`: the settings sheet, its toolbar gear, the Gemini section, "Debug Gemini source discovery" and the unused `webDiscovery` parameter. "Search diagnostics" move inline below results when developer tools are on. `geminiSetupMessage` stays as text without its button (unreachable in this composition).
- `FoodSearchStatusPresentation` `.credentialRejected` copy: "Search settings" becomes "Settings".

## Dependency direction

`AppRoute`, the coordinator, Settings types and all contributions live in the app target. `FoodLedgerPresentation` gains only the public key view, a public constant and a `UserDefaults` parameter; it imports nothing from the app, and `check-boundaries.sh` is unchanged.

## Invariants

1. No route appears twice within Settings; receipts and nutrition updates are linked only from Settings.
2. Existing stored raw values restore to a valid, available path; unknown values give an empty path.
3. Protected-path and screenshot eligibility behaviour are unchanged.
4. The Settings toggles and their consumers read and write the same key in the same store; changing them sends nothing.
5. No new egress, HealthKit type or persisted key; Diagnostics stays DEBUG-only.

## Risks

- `@StateObject` ownership during the split: owners stay in the shell and code moves verbatim.
- `.medicationAccessRequest` must stay on the root so first-launch authorisation still runs.
- Restoring `[settings, inventoryReview]` differs from the old `[inventoryReview]`; intentional and tested.

## Tests

- `AppNavigationTests` (new): an expected-path dictionary keyed by every `AppRoute` case, asserted equal to `Set(allCases)`, with and without draft, with and without food ledger and medication availability; unknown and empty values; persistence round trip with a suite `UserDefaults` (record, relaunch, restore once, idempotent for unknown); popping to root records `""`; resign with an empty path keeps the stored value; protected-path tests moved verbatim from `DailyNotesStoreTests`, including the ten-cycle case, plus `[settings, X]`; note-editor flow; gear yields `[.settings]`.
- `SettingsContributionTests` (new): order; every expected route linked exactly once and `availableRoutes` derived from sections; toggle value after `set` is the new value; online database toggle writes the shared key and a fresh search model reports it; developer tools write is what the search view's store returns; web lookup detail for all three key states with a recording fake provider proving zero requests; market set, removal and a new review model's `initialMarket`; Export rows have no detail; backup guard rejects zero, missing and oversized files.
- `WeeklyReportScreenshotTests`: iterate `AppRoute.allCases` and multi-route paths (`[.settings, .medicationAccess]`, `[.healthReport, .diagnostics]`, `[.foodLog, .healthReport]`) with and without transient UI; only `[.healthReport]` without transient UI is eligible; construction uses `AppShellView`.
- Package: assert the new `.credentialRejected` copy; `FoodRecoveryContractTests` pass unchanged.
- Simulator journey and device check: every Settings row, gear, restoration after relaunch, note editor round trip to system Settings.
