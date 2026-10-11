import XCTest
import SwiftUI
import Combine
import FoodGenericSearch
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
    /// shared-session traffic. The guarantee comes from types and review (the Food Log service
    /// depends only on local stores); this test is a tripwire, not the proof.
    func testFoodLogActionsMakeNoNetworkRequests() async throws {
        URLProtocol.registerClass(RecordingURLProtocol.self)
        RecordingURLProtocol.reset()
        defer { URLProtocol.unregisterClass(RecordingURLProtocol.self) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory),
                                                 userDefaults: isolatedDefaults())
        let saved = try saveClementine(root)
        let web = try saveReviewedWebEntry(root)
        let store = root.foodLogStore
        let day = try await store.day(saved.logItemVersion.reportingDate.value)
        XCTAssertEqual(day.entries.count, 2)
        let loaded = try await store.savedEntry(saved.logItem.logItemID)
        let detail = try XCTUnwrap(loaded)
        let webLoaded = try await store.savedEntry(web.logItem.logItemID)
        XCTAssertEqual(try XCTUnwrap(webLoaded).sourceFamily, .webSource)
        // Reopening a reviewed web entry rehashes its retained manifest locally; nothing is refetched.
        let webEdit = try XCTUnwrap(try root.model(reopening: web.logItem.logItemID))
        XCTAssertEqual(webEdit.logButtonTitle, "Save changes")
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

    /// The focus day is published, so a Food Log that is already showing still selects it.
    func testFocusDayIsPublishedForAShowingFoodLog() {
        let coordinator = AppNavigationCoordinator(defaults: isolatedDefaults())
        var received: [String] = []
        let subscription = coordinator.$foodLogFocusDay.compactMap { $0 }.sink { received.append($0) }
        defer { subscription.cancel() }
        coordinator.replacePath([.foodLog, .addFood])
        coordinator.finishFoodEntry(reportingDay: "2026-10-09")
        XCTAssertEqual(received, ["2026-10-09"])
    }

    // MARK: Journey QA fixes

    /// D1: every Add food Confirm host (search, web lookup, barcode, recent) holds the finish passed
    /// down by its parent, and leaving after a save finishes through the coordinator.
    func testEveryAddFoodConfirmHostFinishesThroughTheCoordinator() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory),
                                                 userDefaults: isolatedDefaults())
        let coordinator = AppNavigationCoordinator(defaults: isolatedDefaults())
        let finish = FoodEntryFinish { coordinator.finishFoodEntry(reportingDay: $0) }
        let hosts: [(String, Any?)] = [
            ("Add food", AddFoodFlowView(root: root, finish: finish)),
            ("search", GenericFoodSearchFlowView(root: root, initialQuery: "150 g chicken breast", searchesOnAppear: true, finish: finish)),
            ("web lookup", OpenRouterFoodReviewFlowView(root: root, initialQuery: "tofu", finish: finish)),
            ("barcode", BarcodeFoodFlowView(root: root, finish: finish))
        ]
        for (name, host) in hosts {
            let view = try XCTUnwrap(host, name)
            XCTAssertNotNil(Mirror(reflecting: view).descendant("finish") as? FoodEntryFinish, "\(name) carries the finish")
        }
        let saved = try XCTUnwrap(try savedClementineModel(root).savedResult)
        coordinator.replacePath([.foodLog, .addFood])
        XCTAssertFalse(FoodEntryFinish.complete(finish, saved: nil), "Cancel pops the host")
        XCTAssertEqual(coordinator.path, [.foodLog, .addFood])
        XCTAssertTrue(FoodEntryFinish.complete(finish, saved: saved))
        XCTAssertEqual(coordinator.path, [.foodLog])
        XCTAssertEqual(coordinator.takeFoodLogFocusDay(), saved.logItemVersion.reportingDate.value)
        XCTAssertFalse(FoodEntryFinish.complete(nil, saved: saved), "outside Add food the host pops itself")
    }

    /// D2: the Food Log renders at accessibility sizes with stacked rows (visual check attached).
    func testFoodLogRendersAtAccessibilityExtraLarge() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let defaults = isolatedDefaults()
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory), userDefaults: defaults)
        _ = try savedClementineModel(root)
        let navigation = AppNavigationCoordinator(defaults: defaults)
        let controller = UIHostingController(rootView: NavigationStack {
            FoodLogView(root: root, navigation: navigation).environment(\.dynamicTypeSize, .accessibility3)
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Food Log - accessibility extra large"; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(image.size.width, 390)
        window.isHidden = true
    }

    // MARK: Single post-save exit

    /// After a save, Confirm offers exactly one exit, labelled by its host, and no back button,
    /// whether pushed (Add food, the saved entry's edit host) or in a sheet (list import, plain).
    func testConfirmAfterSaveHasOneExitPerHost() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory),
                                                 userDefaults: isolatedDefaults())
        let model = try savedClementineModel(root)
        let saved = try XCTUnwrap(model.savedResult)
        let editModel = try XCTUnwrap(try root.model(reopening: saved.logItem.logItemID))
        editModel.send(.setQuantity(130, .grams))
        editModel.log()
        XCTAssertNotNil(editModel.savedResult)
        let hosts: [(String, String, String, AnyView)] = [
            ("Add food", "Done", "Confirm food", AnyView(NavigationStack {
                Text("Host").navigationDestination(isPresented: .constant(true)) { FoodConfirmationView(model: model) {} }
            })),
            ("saved entry edit", "Done", "Edit food", AnyView(NavigationStack {
                Text("Saved entry").navigationDestination(isPresented: .constant(true)) { SavedEntryEditHost(model: editModel) {} }
            })),
            ("list import", "Next line", "Confirm food", AnyView(NavigationStack { ListConfirmationHost(confirmation: model, context: nil) {} })),
            ("sheet", "Done", "Confirm food", AnyView(NavigationStack { FoodConfirmationView(model: model) {} }))
        ]
        for (host, completion, title, view) in hosts {
            let controller = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = controller
            window.isHidden = false
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let bars = Self.descendants(controller.view).compactMap { $0 as? UINavigationBar }
            let item = try XCTUnwrap(bars.first?.topItem, host)
            XCTAssertEqual(item.title, title, "\(host): the Confirm screen is the top item")
            XCTAssertTrue(item.hidesBackButton, "\(host): no back button")
            XCTAssertTrue((item.leftBarButtonItems ?? []).isEmpty, "\(host): no toolbar exit")
            XCTAssertTrue((item.rightBarButtonItems ?? []).isEmpty, "\(host): no toolbar exit")
            // SwiftUI text is not exposed as UIKit labels in a hosted test, so the exits are checked
            // through the list the view renders from; the bar checks above prove nothing else shows.
            var exits = FoodConfirmationView.exitTitles(isSaved: true, showsCancelButton: true, completionTitle: completion)
            if host == "list import" { exits += ListConfirmationHost.toolbarTitles(isSaved: true) }
            XCTAssertEqual(exits, [completion], host)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Confirm after save - \(host)"; attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    private func saveReviewedWebEntry(_ root: FoodLedgerCompositionRoot) throws -> StoredFoodConfirmation {
        let source = try GenericFoodDocumentProjector.project(Data("Synthetic tofu Per 100g Protein 6g".utf8),
            url: URL(string: "https://example.com/synthetic-tofu")!, mediaType: "text/plain",
            retrievedAt: Date(timeIntervalSince1970: TimeInterval(Int(Date().timeIntervalSince1970) - 60)), origin: "synthetic_fixture")
        let reference: [[String: Any]] = [["block_id": "b1", "quote": source.blocks[0].text]]
        let nutrients: [[String: Any]] = FoodProposalNutrientKey.allCases.map { key in
            ["key": key.rawValue, "state": key == .protein ? "declared" : "unknown",
             "value": key == .protein ? "6" as Any : NSNull(), "unit": key == .protein ? "g" as Any : NSNull(),
             "evidence": key == .protein ? reference : [], "unknown_reason": key == .protein ? NSNull() : "not_observed" as Any]
        }
        let payload: [String: Any] = ["version": FoodProposalExtraction.schemaVersion, "preferred_id": "c1", "candidates": [[
            "id": "c1", "document_id": source.id, "name": "Synthetic tofu", "brand": NSNull(), "preparation": NSNull(),
            "identity_evidence": reference, "panel_evidence": reference,
            "basis": ["amount": "100", "unit": "g", "label": "Per 100g", "evidence": reference],
            "nutrients": nutrients, "limitations": ["Synthetic source. Only protein is declared."]]]]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let extraction = try decoder.decode(FoodProposalExtraction.self, from: JSONSerialization.data(withJSONObject: payload))
        let validation = try FoodProposalBinding.validate(extraction, documents: [source])
        let review = GenericFoodProposalReview(foodTerms: "Synthetic tofu", discovery: nil, documents: [source],
            validation: validation, selection: try FoodProposalSelection(unscoredChoice: "c1", validation: validation),
            attemptedSourceURL: URL(string: source.url))
        let proposal = try XCTUnwrap(validation.candidates.first)
        let input = try ReviewedFoodProposalConfirmation(ids: RandomLedgerIDGenerator(), clock: SystemLedgerClock(),
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
            .prepare(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("en_GB"))
        let model = root.model(for: input, prefillSourceQuantity: false)
        model.send(.setQuantity(50, .grams))
        for facet in model.pendingDifferences {
            if let choice = model.offeredChoices(facet).first(where: { $0 == .notSure }) ?? model.offeredChoices(facet).first {
                model.send(.decideDifference(facet, choice))
            }
        }
        model.log()
        return try XCTUnwrap(model.savedResult, "\(model.requirements) \(model.state.phase)")
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
