import XCTest
import SwiftUI
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
@testable import WeeklyHealthReport

/// Phase 4 (#197) at app level: the Add food finish route, restoration and no egress.
@MainActor
final class FoodLogAppTests: XCTestCase {
    // MARK: Focus day (F4)

    func testDoneAfterLogFromTheFoodLogReturnsThereWithTheEntrysDay() {
        let coordinator = AppNavigationCoordinator(defaults: isolatedDefaults())
        coordinator.replacePath([.foodLog, .addFood])
        coordinator.finishFoodEntry(reportingDay: "2026-10-10")
        XCTAssertEqual(coordinator.path, [.foodLog])
        XCTAssertEqual(coordinator.takeFoodLogFocusDay(), "2026-10-10")
        XCTAssertNil(coordinator.takeFoodLogFocusDay(), "the focus day is used once")
    }

    func testDoneAfterLogFromARestoredOrHomeAddFoodReturnsHome() {
        for path in [[AppRoute.addFood], [.settings, .addFood]] {
            let coordinator = AppNavigationCoordinator(defaults: isolatedDefaults())
            coordinator.replacePath(path)
            coordinator.finishFoodEntry(reportingDay: "2026-10-10")
            XCTAssertEqual(coordinator.path, [], "\(path)")
            XCTAssertNil(coordinator.takeFoodLogFocusDay())
        }
    }

    func testFocusDayIsNeverPersisted() {
        let defaults = isolatedDefaults()
        let coordinator = AppNavigationCoordinator(defaults: defaults)
        coordinator.restoreIfNeeded(hasDraft: false, availableRoutes: Set(AppRoute.allCases))
        coordinator.replacePath([.foodLog, .addFood])
        coordinator.finishFoodEntry(reportingDay: "2026-10-10")
        coordinator.recordDestination()
        XCTAssertEqual(coordinator.storedDestination, "foodLog")
        let relaunched = AppNavigationCoordinator(defaults: defaults)
        XCTAssertNil(relaunched.takeFoodLogFocusDay())
        XCTAssertEqual(AppRoute.restoredPath(from: "foodLog", hasDraft: false, availableRoutes: Set(AppRoute.allCases)), [.foodLog])
    }

    /// A saved entry is presentation state of the Food Log, not a route value (#197).
    func testNoRouteWasAddedForTheSavedEntry() {
        XCTAssertEqual(AppRoute.allCases.count, 20)
        XCTAssertEqual(AppRoute.allCases.last, .addFood)
    }

    // MARK: No egress

    /// Food Log load, saved-entry open, edit, remove and restore run through the composition
    /// root without any network request. The root has no transport seam, so the recorder sees
    /// shared-session traffic; the service's dependencies are local by type.
    func testFoodLogActionsMakeNoNetworkRequests() async throws {
        URLProtocol.registerClass(RecordingURLProtocol.self)
        RecordingURLProtocol.reset()
        defer { URLProtocol.unregisterClass(RecordingURLProtocol.self) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory),
                                                 userDefaults: isolatedDefaults())
        let saved = try saveClementine(root)
        let store = root.foodLogStore
        let day = try await store.day(saved.logItemVersion.reportingDate.value)
        XCTAssertEqual(day.entries.count, 1)
        let loaded = try await store.savedEntry(saved.logItem.logItemID)
        let detail = try XCTUnwrap(loaded)
        let edit = try XCTUnwrap(try root.model(reopening: saved.logItem.logItemID))
        XCTAssertEqual(edit.logButtonTitle, "Save changes")
        edit.send(.setQuantity(120, .grams))
        edit.log()
        let edited = try XCTUnwrap(edit.savedResult)
        let outcome = await store.remove(detail.logItemID, expected: edited.logItemVersion.logItemVersionID)
        XCTAssertEqual(outcome, .applied)
        let afterRemoval = try await store.day(saved.logItemVersion.reportingDate.value)
        let removed = try XCTUnwrap(afterRemoval.removed.first)
        let restored = await store.restore(removed.logItemID, expected: removed.logItemVersionID)
        XCTAssertEqual(restored, .applied)
        XCTAssertEqual(RecordingURLProtocol.requestCount, 0)
    }

    // MARK: - Helpers

    // MARK: Single post-save exit (MEDIUM 7)

    /// After a save, Confirm offers exactly one exit, labelled by its host, and no back button,
    /// whether pushed (Add food, edit) or in a sheet (list import, saved entry).
    func testConfirmAfterSaveHasOneExitPerHost() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory),
                                                 userDefaults: isolatedDefaults())
        let model = try savedClementineModel(root)
        for (host, title, pushed) in [("Add food", "Done", true), ("edit", "Done", true), ("list import", "Next line", false), ("sheet", "Done", false)] {
            let confirm = FoodConfirmationView(model: model, completionTitle: title) {}
            let view: AnyView = pushed
                ? AnyView(NavigationStack { Text("Host").navigationDestination(isPresented: .constant(true)) { confirm } })
                : AnyView(NavigationStack { confirm })
            let controller = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = controller
            window.isHidden = false
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let bars = Self.descendants(controller.view).compactMap { $0 as? UINavigationBar }
            let item = try XCTUnwrap(bars.first?.topItem, host)
            XCTAssertTrue(item.hidesBackButton || item.backBarButtonItem == nil && bars.first?.backItem == nil, "\(host): no back button")
            XCTAssertTrue((item.leftBarButtonItems ?? []).isEmpty, "\(host): no toolbar exit")
            XCTAssertTrue((item.rightBarButtonItems ?? []).isEmpty, "\(host): no toolbar exit")
            XCTAssertNotNil(model.savedResult)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Confirm after save - \(host)"; attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    private static func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }

    private func savedClementineModel(_ root: FoodLedgerCompositionRoot) throws -> FoodConfirmationViewModel {
        let search = try root.genericFoodSearchModel(locale: Locale(identifier: "en_GB"))
        search.query = "clementine"
        search.search()
        guard case let .results(route) = search.phase else { throw XCTSkip("Expected offline fruit candidates") }
        let candidate = try XCTUnwrap(route.confirmation.candidates.first)
        let input = try PopulatedFoodConfirmation(evidence: route.confirmation.evidence, sourceReleases: route.confirmation.sourceReleases,
            candidates: [candidate], expectedIdentity: candidate.candidate.identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity)
        let confirmation = root.model(for: input)
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: .notApplicable, skin: .skinless,
            drained: .notApplicable, packingMedium: .named(LedgerText("none — synthetic fixture")), fortification: .unfortified,
            servingBasis: candidate.candidate.identity.servingBasis)
        confirmation.send(.applyCorrection(FoodCorrection(name: try LedgerText("Synthetic clementine flesh"), brand: nil, variant: nil,
            identity: identity, nutrients: candidate.candidate.nutrients,
            reason: try LedgerText("Explicit identity assertions for an isolated fixture"))))
        confirmation.send(.setQuantity(100, .grams))
        confirmation.save()
        XCTAssertNotNil(confirmation.savedResult, "\(confirmation.state.phase)")
        return confirmation
    }

    private func saveClementine(_ root: FoodLedgerCompositionRoot) throws -> StoredFoodConfirmation {
        try XCTUnwrap(try savedClementineModel(root).savedResult)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "food-log-app-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}

private final class RecordingURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var count = 0
    private static let lock = NSLock()
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset() { lock.lock(); count = 0; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock(); count += 1; lock.unlock()
        return false
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
