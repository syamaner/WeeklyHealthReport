import Combine
import XCTest
import FoodLedgerApplication
import FoodLedgerPresentation
@testable import WeeklyHealthReport

@MainActor
final class SettingsContributionTests: XCTestCase {
    func testSectionsAreOrderedAndEveryRouteIsLinkedOnce() throws {
        let (root, defaults) = try makeFoodLedger()
        let settings = WeeklyHealthReportApp.makeSettings(foodLedger: root, defaults: defaults, medicationAccessAvailable: true)

        XCTAssertEqual(settings.sections.map(\.id), [.foodSearch, .openRouter, .export, .data, .appleHealth, .about])
        XCTAssertEqual(settings.linkedRoutes, [
            .foodMarket, .webLookupKey, .openRouterPrivacy, .exportDestination, .dataBackup, .personalFoodDatabase, .inventoryReview,
            .commonFoods, .foodReresolution, .medicationAccess, .privacy, .developerTools
        ])
        XCTAssertEqual(Set(settings.linkedRoutes).count, settings.linkedRoutes.count)
        XCTAssertEqual(settings.availableRoutes, Set(AppRoute.allCases))
    }

    func testSectionsWithoutFoodLedgerOrMedicationAccess() {
        let settings = WeeklyHealthReportApp.makeSettings(foodLedger: nil, defaults: isolatedDefaults(), medicationAccessAvailable: false)
        XCTAssertEqual(settings.sections.map(\.id), [.export, .about])
        XCTAssertEqual(settings.linkedRoutes, [.exportDestination, .privacy, .developerTools])
        XCTAssertFalse(settings.availableRoutes.contains(.medicationAccess))
        XCTAssertFalse(settings.availableRoutes.contains(.dataBackup))
    }

    func testToggleShowsTheStoredValueAfterSet() {
        var stored = false
        let toggle = SettingsToggle(title: "Synthetic", read: { stored }, write: { stored = $0 })
        XCTAssertFalse(toggle.isOn)
        toggle.set(true)
        XCTAssertTrue(toggle.isOn)
        toggle.set(false)
        XCTAssertFalse(toggle.isOn)

        let refusing = SettingsToggle(title: "Refusing", read: { false }, write: { _ in })
        refusing.set(true)
        XCTAssertFalse(refusing.isOn)
    }

    func testOnlineDatabaseToggleWritesTheSearchPreference() throws {
        let (root, defaults) = try makeFoodLedger()
        let toggle = try XCTUnwrap(root.settingsSections().first?.rows.compactMap { row -> SettingsToggle? in
            if case let .toggle(toggle) = row.kind { return toggle }
            return nil
        }.first)
        XCTAssertFalse(toggle.isOn)
        XCTAssertFalse(try root.genericFoodSearchModel().onlineDatabaseEnabled)

        toggle.set(true)
        XCTAssertTrue(toggle.isOn)
        XCTAssertTrue(defaults.bool(forKey: "foodSearch.openFoodFacts.automatic.v1"))
        XCTAssertTrue(try root.genericFoodSearchModel().onlineDatabaseEnabled)

        toggle.set(false)
        XCTAssertFalse(try root.genericFoodSearchModel().onlineDatabaseEnabled)
    }

    func testDeveloperToolsToggleWritesTheSearchScreenStore() throws {
        let (root, _) = try makeFoodLedger()
        let unrelated = isolatedDefaults()
        let settings = WeeklyHealthReportApp.makeSettings(foodLedger: root, defaults: unrelated, medicationAccessAvailable: false)

        settings.developerTools.set(true)
        XCTAssertTrue(settings.developerTools.isOn)
        // GenericFoodSearchFlowView passes root.userDefaults to the search view.
        XCTAssertTrue(root.userDefaults.bool(forKey: FoodSearchDeveloperTools.storageKey))
        XCTAssertNil(unrelated.object(forKey: FoodSearchDeveloperTools.storageKey))

        settings.developerTools.set(false)
        XCTAssertFalse(root.userDefaults.bool(forKey: FoodSearchDeveloperTools.storageKey))
    }

    func testWebLookupDetailStates() {
        XCTAssertEqual(FoodSearchSettingsContribution.webLookupDetail(hasSavedKey: false, keyIsUsable: false), "Key missing")
        XCTAssertEqual(FoodSearchSettingsContribution.webLookupDetail(hasSavedKey: true, keyIsUsable: false), "Revalidate key")
        XCTAssertEqual(FoodSearchSettingsContribution.webLookupDetail(hasSavedKey: true, keyIsUsable: true), "Key added")
        XCTAssertEqual(FoodSearchSettingsContribution.webLookupDetail(hasSavedKey: false, keyIsUsable: false, keyLoadFailed: true),
                       "Key not read yet", "a key the Keychain could not return is not shown as missing (#493)")
    }

    func testBuildingAndReadingFoodSearchSettingsSendsNoRequests() throws {
        let preferences = FoodSearchUserDefaultsPreferencesFake()
        let section = FoodSearchSettingsContribution.section(
            preferences: preferences, onlineDatabaseAvailable: true, market: FoodMarketPreference(defaults: isolatedDefaults()))
        var details: [String?] = []
        for row in section.rows {
            switch row.kind {
            case let .link(detail, _): details.append(detail())
            case let .toggle(toggle): toggle.set(true); toggle.set(false)
            case .text, .value, .action: XCTFail("Food search has no plain text, value or action rows")
            }
        }
        XCTAssertEqual(details, ["Unspecified"])
        XCTAssertEqual(section.footerLink?.title, "Open Food Facts terms and data licences")
        XCTAssertEqual(section.footerLink?.url, URL(string: "https://world.openfoodfacts.org/terms-of-use"))
        guard case let .toggle(toggle) = section.rows.first?.kind else { return XCTFail("Expected the database toggle") }
        XCTAssertTrue(toggle.caption?.contains("Community product data can be incomplete.") == true)
    }

    /// O1.6 test 9: Food search keeps only Online food database and Food market, with the Open Food
    /// Facts footer, word for word; the Web lookup row and the photo toggle are gone.
    func testFoodSearchHasNoOpenRouterRowsAndItsFooterIsVerbatim() {
        let section = FoodSearchSettingsContribution.section(
            preferences: FoodSearchUserDefaultsPreferencesFake(), onlineDatabaseAvailable: true,
            market: FoodMarketPreference(defaults: isolatedDefaults()))
        XCTAssertEqual(section.rows.map(\.id), ["toggle.onlineFoodDatabase", "route.foodMarket"])
        XCTAssertEqual(section.footer, "Open Food Facts receives only the food terms you search for or a barcode you look up. Your Health data and food log stay on this device unless you export them to Google Drive.")
    }

    /// O1.6 test 9 with CE1 section 8: Settings › OpenRouter has the exact rows, copy and order of O1.1,
    /// with the Confirm suggestions rows after the consent switch; the switch is off by default and
    /// writes only its versioned key; building and toggling it, and showing the label reads row, sends
    /// no request and creates no read session.
    func testTheOpenRouterSectionRowsCopyAndOrder() throws {
        let (root, defaults) = try makeFoodLedger()
        let sessions = LabelPhotoSessions.count
        let section = root.openRouterSettingsSection()
        XCTAssertEqual(section.id, .openRouter)
        XCTAssertEqual(section.title, "OpenRouter")
        XCTAssertEqual(section.rows.map(\.id), ["toggle.openRouterConsent", "toggle.confirmEnrichment", "value.confirmSuggestionsToday",
                                                "action.clearSuggestionsCache", "route.webLookupKey", "value.labelPhotoReadsToday",
                                                "route.openRouterPrivacy"])
        XCTAssertEqual(section.rows.map(\.title), ["Use OpenRouter for food lookups, label reading and Confirm suggestions",
                                                   "Suggest missing food details and values on Confirm", "Confirm suggestions today",
                                                   "Clear suggestions cache", "API key", "Label photo reads today", "How the app uses OpenRouter"])
        XCTAssertNil(section.footer)
        XCTAssertEqual(section.footerLink?.title, "Manage OpenRouter keys and limits")
        XCTAssertEqual(section.footerLink?.url, URL(string: "https://openrouter.ai/settings/keys"))
        guard case let .toggle(toggle) = section.rows[0].kind else { return XCTFail("Expected the consent switch") }
        XCTAssertEqual(toggle.caption, "Off by default. While it is off, the app sends nothing to OpenRouter. Uses your own key and credit.")
        XCTAssertFalse(toggle.isOn, "off by default")
        guard case let .link(keyDetail, _) = section.rows[4].kind, case let .value(reads) = section.rows[5].kind else {
            return XCTFail("Expected the key link and the reads row")
        }
        XCTAssertEqual(keyDetail(), FoodSearchSettingsContribution.webLookupDetail(hasSavedKey: root.webDiscovery.hasSavedKey,
            keyIsUsable: root.webDiscovery.keyIsUsable, keyLoadFailed: root.webDiscovery.keyLoadFailed))
        XCTAssertNil(reads(), "hidden while the switch is off")
        toggle.set(true)
        XCTAssertTrue(toggle.isOn)
        if root.webDiscovery.hasSavedKey { XCTAssertEqual(reads(), "0 of 30") } else { XCTAssertNil(reads(), "hidden while no key is saved") }
        toggle.set(false)
        XCTAssertNil(defaults.persistentDomain(forName: consentDomains[ObjectIdentifier(defaults)] ?? "")?[OpenRouterConsentPreference.key])
        XCTAssertEqual(LabelPhotoSessions.count, sessions, "the section builds no read flow")
    }

    /// CE1 sections 8 and 9: the enrichment switch is off by default, reads and writes only
    /// `confirmEnrichment.enabled.v1` in the persistent domain, and is removed when off; the day row
    /// follows the label reads row's visibility and reads `<n> of 100`; Clear suggestions cache deletes
    /// the live cache file. Building, toggling, reading and clearing write no day record and no cache,
    /// and so send nothing (a request reserves in the day record before it is sent).
    func testTheConfirmSuggestionsRowsAreOffByDefaultAndSendNothing() throws {
        let (root, defaults) = try makeFoodLedger()
        let domain = consentDomains[ObjectIdentifier(defaults)] ?? ""
        let section = root.openRouterSettingsSection()
        guard case let .toggle(consent) = section.rows[0].kind, case let .toggle(enrichment) = section.rows[1].kind,
              case let .value(today) = section.rows[2].kind, case let .action(hint, clear) = section.rows[3].kind else {
            return XCTFail("Expected the consent switch, the enrichment switch, the day row and the clear action")
        }
        XCTAssertEqual(enrichment.caption, "Off by default. Sends a description of the food you are logging and its known values; never the amount, time, notes or Health data.")
        XCTAssertEqual(hint, "Removes the saved suggestions from this iPhone. Nothing is sent.")
        XCTAssertFalse(enrichment.isOn, "off by default")
        XCTAssertNil(today(), "hidden while OpenRouter is off")
        enrichment.set(true)
        XCTAssertTrue(enrichment.isOn)
        XCTAssertEqual(defaults.persistentDomain(forName: domain)?[ConfirmEnrichmentPreference.key] as? Bool, true)
        XCTAssertTrue(root.confirmEnrichmentPreference.isOn)
        consent.set(true)
        if root.webDiscovery.hasSavedKey { XCTAssertEqual(today(), "0 of 100") } else { XCTAssertNil(today(), "hidden while no key is saved") }

        let folder = root.healthDirectory.appendingPathComponent("FoodLedger/v1", isDirectory: true)
        let cacheFile = folder.appendingPathComponent("confirm-enrichment-cache-v1.json")
        let dayFile = folder.appendingPathComponent("confirm-enrichment-day-v1.json")
        XCTAssertEqual(root.confirmEnrichment?.mode, .live)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dayFile.path), "nothing reserved, so nothing sent")
        try Data("{}".utf8).write(to: cacheFile)
        clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path), "the live cache file is deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dayFile.path))
        XCTAssertEqual(root.confirmEnrichment?.ledger.read(), .absent)

        enrichment.set(false)
        consent.set(false)
        XCTAssertNil(defaults.persistentDomain(forName: domain)?[ConfirmEnrichmentPreference.key], "off removes the value")
    }

    func testTheConfirmSuggestionsDetail() {
        XCTAssertEqual(OpenRouterSettingsContribution.suggestionsDetail(.absent, today: "2026-11-22"), "0 of 100")
        XCTAssertEqual(OpenRouterSettingsContribution.suggestionsDetail(.unreadable, today: "2026-11-22"), "Not available")
        let day = ConfirmEnrichmentSpendPolicy.Day(localDay: "2026-11-22", requests: 7)
        XCTAssertEqual(OpenRouterSettingsContribution.suggestionsDetail(.day(day), today: "2026-11-22"), "7 of 100")
        XCTAssertEqual(OpenRouterSettingsContribution.suggestionsDetail(.day(day), today: "2026-11-23"), "0 of 100", "a new day starts at 0")
    }

    func testTheLabelReadsDetail() {
        XCTAssertEqual(OpenRouterSettingsContribution.readsDetail(.absent, today: "2026-11-20"), "0 of 30")
        XCTAssertEqual(OpenRouterSettingsContribution.readsDetail(.unreadable, today: "2026-11-20"), "Not available")
    }

    func testFoodMarketPreferenceSetRemoveAndReviewModel() throws {
        let (root, defaults) = try makeFoodLedger()
        XCTAssertEqual(root.foodMarket.market, .unspecified)

        root.foodMarket.market = .taiwan
        XCTAssertEqual(defaults.string(forKey: FoodMarketPreference.key), "Taiwan")
        XCTAssertEqual(try root.proposalReviewModel(initialQuery: "synthetic").market, .taiwan)

        root.foodMarket.market = .unspecified
        XCTAssertNil(defaults.object(forKey: FoodMarketPreference.key))
        XCTAssertEqual(try root.proposalReviewModel(initialQuery: "synthetic").market, .unspecified)

        // A choice made on the review screen is what Settings shows.
        let review = try root.proposalReviewModel(initialQuery: "synthetic")
        review.market = .unitedKingdom
        XCTAssertEqual(root.foodMarket.market, .unitedKingdom)
    }

    func testExportRowsHaveNoDetail() {
        let section = ExportSettingsContribution.section(driveExportAvailable: true)
        XCTAssertEqual(section.rows.map(\.route), [.exportDestination])
        for row in section.rows {
            guard case let .link(detail, _) = row.kind else { return XCTFail("Expected a link") }
            XCTAssertNil(detail())
        }
    }

    func testInventoryBackupGuardRejectsEmptyMissingAndOversizedFiles() throws {
        XCTAssertThrowsError(try InventoryBackupFile.validate(size: nil))
        XCTAssertThrowsError(try InventoryBackupFile.validate(size: 0))
        XCTAssertThrowsError(try InventoryBackupFile.validate(size: InventoryBackupCodec.maximumBytes + 1))
        XCTAssertNoThrow(try InventoryBackupFile.validate(size: 1))
        XCTAssertNoThrow(try InventoryBackupFile.validate(size: InventoryBackupCodec.maximumBytes))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let empty = directory.appendingPathComponent("empty.json")
        try Data().write(to: empty)
        XCTAssertThrowsError(try InventoryBackupFile.read(empty)) {
            XCTAssertEqual($0 as? InventoryStoreError, .corruptStore)
        }
        let small = directory.appendingPathComponent("small.json")
        try Data("{}".utf8).write(to: small)
        XCTAssertEqual(try InventoryBackupFile.read(small), Data("{}".utf8))
    }

    // MARK: Helpers

    private func isolatedDefaults() -> UserDefaults {
        let name = "settings-contribution-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// #424 P1b: the Settings row and screen model import, replace and remove a synthetic file in
    /// the simulator; the folder sits under the backup-excluded root and its files are protected.
    func testYourFoodDatabaseImportAndRemoveThroughTheRoot() async throws {
        let (root, _) = try makeFoodLedger()
        let model = root.personalFoodDatabase
        let row = try XCTUnwrap(WeeklyHealthReportApp.makeSettings(foodLedger: root, defaults: isolatedDefaults(), medicationAccessAvailable: true)
            .sections.flatMap(\.rows).first { $0.route == .personalFoodDatabase })
        XCTAssertEqual(row.title, "Your food database")
        await model.load()
        XCTAssertEqual(model.rowDetail, "Not added")

        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/fixtures/personal-food-database-v1")
        await model.importFile(try Data(contentsOf: fixtures.appendingPathComponent("golden.json")))
        XCTAssertEqual(model.message, "Your food database was added.")
        XCTAssertEqual(model.rowDetail, "3 foods")
        if case let .link(detail, _) = row.kind { XCTAssertEqual(detail(), "3 foods") } else { XCTFail("link row") }

        let folder = root.healthDirectory.appendingPathComponent("FoodLedger/v1/Datasets/personal-food-database", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("active.json").path))
        XCTAssertEqual(try root.healthDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertNotNil(try FileManager.default.contentsOfDirectory(atPath: folder.path).first { $0.hasPrefix("pfc-sha256-") })
        // The simulator has no data protection (it reports no protection attribute), so complete
        // protection is checked by the package's applier test and on the device, not here.

        await model.importFile(try Data(contentsOf: fixtures.appendingPathComponent("reject-unknown-schema.json")))
        XCTAssertEqual(model.message, "This file is not a food database file from your Mac. Your food database was not changed.")
        XCTAssertEqual(model.rowDetail, "3 foods")

        await model.remove()
        XCTAssertEqual(model.rowDetail, "Not added")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    /// The Settings detail publisher is built once and emits nothing on subscription, so the view's
    /// `onReceive` cannot re-render itself in a loop; a real state change emits once.
    func testSettingsDetailChangesAreQuietUntilAStateChange() async throws {
        let (root, defaults) = try makeFoodLedger()
        let settings = WeeklyHealthReportApp.makeSettings(foodLedger: root, defaults: defaults, medicationAccessAvailable: true)
        await root.personalFoodDatabase.load()
        var count = 0
        let subscription = settings.detailChanges.sink { count += 1 }
        defer { subscription.cancel() }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(count, 0, "no emission on subscription")
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/fixtures/personal-food-database-v1")
        await root.personalFoodDatabase.importFile(try Data(contentsOf: fixtures.appendingPathComponent("golden.json")))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(count, 1)
    }

    private func makeFoodLedger() throws -> (FoodLedgerCompositionRoot, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let name = "settings-contribution-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        consentDomains[ObjectIdentifier(defaults)] = name
        let root = try FoodLedgerCompositionRoot(
            fileManager: IntakeRenderFileManager(directory: directory), userDefaults: defaults, openRouterConsentDomain: name
        )
        return (root, defaults)
    }
    private var consentDomains: [ObjectIdentifier: String] = [:]
}

private final class RecordingWebProvider: FoodWebDiscovering, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var requestCount: Int { lock.withLock { count } }

    func validate(key: String) async throws {
        lock.withLock { count += 1 }
    }

    func discover(foodTerms: String, key: String) async throws -> FoodWebDiscoveryResult {
        lock.withLock { count += 1 }
        throw CancellationError()
    }
}

private struct FixedKeyStore: FoodWebKeyStoring {
    let key: String?
    func load() throws -> String? { key }
    func save(_ key: String) throws {}
    func delete() throws {}
}

/// The protected-data rules behind Your food database's "Locked" row: a pending lock clears on
/// "did become available", or on becoming active when that notification was missed while suspended.
final class ProtectedDataLockStateTests: XCTestCase {
    func testAPendingLockReadsUnavailableWhileTheLiveValueIsStillTrue() {
        var state = ProtectedDataLockState()
        state.observe(true)
        XCTAssertTrue(state.isReadable)
        state.willBecomeUnavailable(live: true)
        XCTAssertFalse(state.isReadable)
        state.observe(true)
        XCTAssertFalse(state.isReadable, "a live read never clears a pending lock")
    }

    func testDidBecomeAvailableClearsAPendingLock() {
        var state = ProtectedDataLockState()
        state.willBecomeUnavailable(live: true)
        state.didBecomeAvailable(live: true)
        XCTAssertTrue(state.isReadable)
    }

    func testBecomingActiveClearsALockWhoseUnlockNotificationWasMissed() {
        var state = ProtectedDataLockState()
        state.observe(true)
        state.willBecomeUnavailable(live: true)
        // Suspended: the phone locks and unlocks, and "did become available" never arrives.
        state.becameActive(live: true)
        XCTAssertTrue(state.isReadable)
    }

    func testBecomingActiveWhileStillUnreadableKeepsTheLock() {
        var state = ProtectedDataLockState()
        state.willBecomeUnavailable(live: false)
        state.becameActive(live: false)
        XCTAssertFalse(state.isReadable)
        state.becameActive(live: true)
        XCTAssertTrue(state.isReadable)
    }

    func testAnUnseededStateIsUnreadable() {
        XCTAssertFalse(ProtectedDataLockState().isReadable)
    }
}

@MainActor
private final class FoodSearchUserDefaultsPreferencesFake: FoodSearchPreferences {
    var onlineDatabaseEnabled = false
    var geminiEnabled = false
}
