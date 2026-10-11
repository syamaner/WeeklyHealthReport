import XCTest
@testable import WeeklyHealthReport

@MainActor
final class AppNavigationTests: XCTestCase {
    private let allAvailable = Set(AppRoute.allCases)
    private let withoutComposedSettings = AppRoute.fixedRoutes.union([.developerTools])

    // MARK: Restoration contract

    /// Every case must have an explicit decision; adding a route fails here until it does.
    func testEveryRouteRestoresToItsExpectedPath() {
        let expected: [AppRoute: (draft: [AppRoute], noDraft: [AppRoute])] = [
            .foodLog: ([.foodLog], [.foodLog]),
            .healthReport: ([.healthReport], [.healthReport]),
            .dailyExport: ([.dailyExport], [.dailyExport]),
            .genericFoodSearch: ([.genericFoodSearch], [.genericFoodSearch]),
            .foodListImport: ([.foodListImport], [.foodListImport]),
            .barcodeFoodCapture: ([.barcodeFoodCapture], [.barcodeFoodCapture]),
            .commonFoods: ([.commonFoods], [.commonFoods]),
            .inventoryReview: ([.settings, .inventoryReview], [.settings, .inventoryReview]),
            .foodReresolution: ([.settings, .foodReresolution], [.settings, .foodReresolution]),
            .notes: ([.dailyExport, .notes], [.dailyExport, .notes]),
            .noteEditor: ([.dailyExport, .notes, .noteEditor], [.dailyExport, .notes]),
            .diagnostics: ([], []),
            .privacy: ([.settings, .privacy], [.settings, .privacy]),
            .settings: ([.settings], [.settings]),
            .webLookupKey: ([.settings, .webLookupKey], [.settings, .webLookupKey]),
            .foodMarket: ([.settings, .foodMarket], [.settings, .foodMarket]),
            .dataBackup: ([.settings, .dataBackup], [.settings, .dataBackup]),
            .medicationAccess: ([.settings, .medicationAccess], [.settings, .medicationAccess]),
            .developerTools: ([.settings, .developerTools], [.settings, .developerTools]),
            .addFood: ([.addFood], [.addFood])
        ]
        XCTAssertEqual(Set(expected.keys), Set(AppRoute.allCases))
        for (route, paths) in expected {
            XCTAssertEqual(AppRoute.restoredPath(from: route.rawValue, hasDraft: true, availableRoutes: allAvailable), paths.draft, "\(route)")
            XCTAssertEqual(AppRoute.restoredPath(from: route.rawValue, hasDraft: false, availableRoutes: allAvailable), paths.noDraft, "\(route)")
        }
    }

    func testLegacyRawValuesAreUnchanged() {
        let legacy = ["foodLog", "healthReport", "dailyExport", "genericFoodSearch", "foodListImport",
                      "barcodeFoodCapture", "inventoryReview", "commonFoods", "foodReresolution",
                      "notes", "noteEditor", "diagnostics", "privacy"]
        for value in legacy { XCTAssertNotNil(AppRoute(rawValue: value), value) }
    }

    func testUnknownAndEmptyValuesRestoreHome() {
        for value in ["", "removedRoute", "Settings", "weeklyReport"] {
            XCTAssertEqual(AppRoute.restoredPath(from: value, hasDraft: true, availableRoutes: allAvailable), [])
        }
    }

    func testUnavailableSettingsChildrenRestoreSettings() {
        for route in [AppRoute.webLookupKey, .foodMarket, .dataBackup, .medicationAccess] {
            XCTAssertEqual(
                AppRoute.restoredPath(from: route.rawValue, hasDraft: false, availableRoutes: withoutComposedSettings),
                [.settings], "\(route)"
            )
        }
        // Fixed routes keep their existing unavailable-screen behaviour.
        XCTAssertEqual(AppRoute.restoredPath(from: "inventoryReview", hasDraft: false, availableRoutes: withoutComposedSettings), [.settings, .inventoryReview])
        XCTAssertEqual(AppRoute.restoredPath(from: "foodReresolution", hasDraft: false, availableRoutes: withoutComposedSettings), [.settings, .foodReresolution])
    }

    func testComposedAvailabilityFollowsFoodLedgerAndMedicationAccess() {
        let bare = WeeklyHealthReportApp.makeSettings(foodLedger: nil, defaults: isolatedDefaults(), medicationAccessAvailable: false)
        XCTAssertEqual(AppRoute.restoredPath(from: "medicationAccess", hasDraft: false, availableRoutes: bare.availableRoutes), [.settings])
        XCTAssertEqual(AppRoute.restoredPath(from: "webLookupKey", hasDraft: false, availableRoutes: bare.availableRoutes), [.settings])
        XCTAssertEqual(AppRoute.restoredPath(from: "developerTools", hasDraft: false, availableRoutes: bare.availableRoutes), [.settings, .developerTools])

        let withMedication = WeeklyHealthReportApp.makeSettings(foodLedger: nil, defaults: isolatedDefaults(), medicationAccessAvailable: true)
        XCTAssertEqual(AppRoute.restoredPath(from: "medicationAccess", hasDraft: false, availableRoutes: withMedication.availableRoutes), [.settings, .medicationAccess])
    }

    func testComposedAvailabilityWithFoodLedger() throws {
        let (root, defaults) = try makeFoodLedger()
        let settings = WeeklyHealthReportApp.makeSettings(foodLedger: root, defaults: defaults, medicationAccessAvailable: false)
        for route in [AppRoute.webLookupKey, .foodMarket, .dataBackup] {
            XCTAssertEqual(AppRoute.restoredPath(from: route.rawValue, hasDraft: false, availableRoutes: settings.availableRoutes), [.settings, route])
        }
    }

    // MARK: Persistence

    func testDestinationPersistsAcrossRelaunchAndRestoresOnce() {
        let defaults = isolatedDefaults()
        let first = AppNavigationCoordinator(defaults: defaults)
        first.restoreIfNeeded(hasDraft: false, availableRoutes: allAvailable)
        XCTAssertEqual(first.path, [])
        first.append(.settings); first.recordDestination()
        first.append(.foodMarket); first.recordDestination()
        XCTAssertEqual(defaults.string(forKey: AppNavigationCoordinator.destinationKey), "foodMarket")

        let relaunched = AppNavigationCoordinator(defaults: defaults)
        relaunched.restoreIfNeeded(hasDraft: false, availableRoutes: allAvailable)
        XCTAssertEqual(relaunched.path, [.settings, .foodMarket])
        relaunched.acceptPathChange([])
        relaunched.restoreIfNeeded(hasDraft: false, availableRoutes: allAvailable)
        XCTAssertEqual(relaunched.path, [])
    }

    func testRestoreIsIdempotentForUnknownValues() {
        let defaults = isolatedDefaults()
        defaults.set("removedRoute", forKey: AppNavigationCoordinator.destinationKey)
        let coordinator = AppNavigationCoordinator(defaults: defaults)
        coordinator.restoreIfNeeded(hasDraft: false, availableRoutes: allAvailable)
        XCTAssertEqual(coordinator.path, [])
        coordinator.append(.foodLog)
        coordinator.restoreIfNeeded(hasDraft: false, availableRoutes: allAvailable)
        XCTAssertEqual(coordinator.path, [.foodLog])
    }

    func testRecordingBeforeRestorationDoesNotOverwriteStoredValue() {
        let defaults = isolatedDefaults()
        defaults.set("privacy", forKey: AppNavigationCoordinator.destinationKey)
        let coordinator = AppNavigationCoordinator(defaults: defaults)
        coordinator.recordDestination()
        XCTAssertEqual(coordinator.storedDestination, "privacy")
    }

    func testPoppingToHomeRecordsEmptyAndForegroundingStaysHome() {
        let defaults = isolatedDefaults()
        let coordinator = AppNavigationCoordinator(defaults: defaults)
        coordinator.restoreIfNeeded(hasDraft: false, availableRoutes: allAvailable)
        coordinator.append(.healthReport); coordinator.recordDestination()
        coordinator.acceptPathChange([]); coordinator.recordDestination()
        XCTAssertEqual(coordinator.storedDestination, "")

        coordinator.willResignActive()
        coordinator.didBecomeActive(hasDraft: false, availableRoutes: allAvailable)
        XCTAssertEqual(coordinator.path, [])
    }

    func testResignWithEmptyPathKeepsStoredValue() {
        let defaults = isolatedDefaults()
        defaults.set("dailyExport", forKey: AppNavigationCoordinator.destinationKey)
        let coordinator = AppNavigationCoordinator(defaults: defaults)
        coordinator.willResignActive()
        XCTAssertEqual(coordinator.storedDestination, "dailyExport")
    }

    func testActivationWithEmptyPathRestoresStoredDestination() {
        let defaults = isolatedDefaults()
        defaults.set("notes", forKey: AppNavigationCoordinator.destinationKey)
        let coordinator = AppNavigationCoordinator(defaults: defaults)
        coordinator.didBecomeActive(hasDraft: false, availableRoutes: allAvailable)
        XCTAssertEqual(coordinator.path, [.dailyExport, .notes])
    }

    // MARK: Protected path (moved from DailyNotesStoreTests)

    func testNavigationRejectsLifecyclePopsUntilActivationCompletes() {
        let navigation = AppNavigationCoordinator(defaults: isolatedDefaults())
        let editorPath: [AppRoute] = [.dailyExport, .notes, .noteEditor]
        navigation.replacePath(editorPath)

        navigation.protectCurrentPath()
        navigation.acceptPathChange([.dailyExport, .notes])
        navigation.acceptPathChange([])

        XCTAssertEqual(navigation.path, editorPath)

        navigation.restoreProtectedPath()
        navigation.acceptPathChange([.dailyExport, .notes])

        XCTAssertEqual(navigation.path, [.dailyExport, .notes])

        navigation.acceptPathChange([])

        XCTAssertTrue(navigation.path.isEmpty)
    }

    func testNavigationProtectionSupportsRepeatedLifecycleCycles() {
        let navigation = AppNavigationCoordinator(defaults: isolatedDefaults())
        let notesPath: [AppRoute] = [.dailyExport, .notes]
        navigation.replacePath(notesPath)

        for _ in 0..<10 {
            navigation.protectCurrentPath()
            navigation.acceptPathChange([])
            navigation.restoreProtectedPath()
            XCTAssertEqual(navigation.path, notesPath)
        }
    }

    func testProtectionKeepsSettingsChildAcrossLifecycle() {
        for child in [AppRoute.webLookupKey, .foodMarket, .dataBackup, .medicationAccess, .developerTools, .privacy] {
            let navigation = AppNavigationCoordinator(defaults: isolatedDefaults())
            navigation.replacePath([.settings, child])
            navigation.willResignActive()
            navigation.acceptPathChange([.settings])
            navigation.acceptPathChange([])
            navigation.didBecomeActive(hasDraft: false, availableRoutes: allAvailable)
            XCTAssertEqual(navigation.path, [.settings, child])
        }
    }

    func testNoteEditorRoundTripToSystemSettings() {
        let defaults = isolatedDefaults()
        let navigation = AppNavigationCoordinator(defaults: defaults)
        navigation.restoreIfNeeded(hasDraft: false, availableRoutes: allAvailable)
        navigation.append(.dailyExport); navigation.append(.notes); navigation.append(.noteEditor)
        navigation.recordDestination()

        // The editor's willOpenApplicationSettings callback, then the app resigns.
        navigation.protectCurrentPath()
        navigation.willResignActive()
        navigation.acceptPathChange([])
        navigation.didBecomeActive(hasDraft: true, availableRoutes: allAvailable)
        XCTAssertEqual(navigation.path, [.dailyExport, .notes, .noteEditor])

        // A relaunch with the draft still present restores the editor.
        let relaunched = AppNavigationCoordinator(defaults: defaults)
        relaunched.restoreIfNeeded(hasDraft: true, availableRoutes: allAvailable)
        XCTAssertEqual(relaunched.path, [.dailyExport, .notes, .noteEditor])
    }

    // MARK: Gear

    func testGearOpensSettingsFromHome() {
        let navigation = AppNavigationCoordinator(defaults: isolatedDefaults())
        navigation.openSettings()
        XCTAssertEqual(navigation.path, [.settings])
    }

    // MARK: Helpers

    private func isolatedDefaults() -> UserDefaults {
        let name = "app-navigation-" + UUID().uuidString
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
