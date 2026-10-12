import XCTest
import FoodLedgerApplication
import FoodLedgerPresentation
@testable import WeeklyHealthReport

@MainActor
final class SettingsContributionTests: XCTestCase {
    func testSectionsAreOrderedAndEveryRouteIsLinkedOnce() throws {
        let (root, defaults) = try makeFoodLedger()
        let settings = WeeklyHealthReportApp.makeSettings(foodLedger: root, defaults: defaults, medicationAccessAvailable: true)

        XCTAssertEqual(settings.sections.map(\.id), [.foodSearch, .export, .data, .appleHealth, .about])
        XCTAssertEqual(settings.linkedRoutes, [
            .webLookupKey, .foodMarket, .exportDestination, .dataBackup, .inventoryReview,
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
    }

    func testBuildingAndReadingFoodSearchSettingsSendsNoRequests() throws {
        for savedKey in [nil, "synthetic-key"] as [String?] {
            let provider = RecordingWebProvider()
            let lookup = FoodWebDiscoveryViewModel(provider: provider, keys: FixedKeyStore(key: savedKey))
            let preferences = FoodSearchUserDefaultsPreferencesFake()
            let section = FoodSearchSettingsContribution.section(
                preferences: preferences, onlineDatabaseAvailable: true,
                webLookup: lookup, market: FoodMarketPreference(defaults: isolatedDefaults())
            )
            var details: [String?] = []
            for row in section.rows {
                switch row.kind {
                case let .link(detail, _): details.append(detail())
                case let .toggle(toggle): toggle.set(true); toggle.set(false)
                }
            }
            XCTAssertEqual(details, [savedKey == nil ? "Key missing" : "Revalidate key", "Unspecified"])
            XCTAssertEqual(provider.requestCount, 0)
            XCTAssertEqual(section.footerLink?.title, "Open Food Facts terms and data licences")
            XCTAssertEqual(section.footerLink?.url, URL(string: "https://world.openfoodfacts.org/terms-of-use"))
            guard case let .toggle(toggle) = section.rows.first?.kind else { return XCTFail("Expected the database toggle") }
            XCTAssertTrue(toggle.caption?.contains("Community product data can be incomplete.") == true)
        }
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
        let section = ExportSettingsContribution.section()
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

    private func makeFoodLedger() throws -> (FoodLedgerCompositionRoot, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let defaults = isolatedDefaults()
        let root = try FoodLedgerCompositionRoot(
            fileManager: IntakeRenderFileManager(directory: directory), userDefaults: defaults
        )
        return (root, defaults)
    }
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

@MainActor
private final class FoodSearchUserDefaultsPreferencesFake: FoodSearchPreferences {
    var onlineDatabaseEnabled = false
    var geminiEnabled = false
}
