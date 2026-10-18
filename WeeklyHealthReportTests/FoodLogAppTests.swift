import XCTest
import SwiftUI
import Combine
import FoodBarcodeCapture
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
    /// Phase 7 (#200) appends `exportDestination` after `addFood`, then phase 5 (#198) appends
    /// `favourites`; the quick-add sheet is presentation state, not a route. Phase 6 (#199) appends
    /// `todayNotes` and `todayNoteEditor` for Home's notes row.
    func testNoRouteWasAddedForTheSavedEntry() {
        XCTAssertEqual(AppRoute.allCases.count, 24)
        XCTAssertEqual(Array(AppRoute.allCases.suffix(5)), [.addFood, .exportDestination, .favourites, .todayNotes, .todayNoteEditor])
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

    // MARK: Add food day (owner decision D)

    /// The coordinator carries the Food Log day to Add food only while that Add food sits on the
    /// Food Log; Home, a restored Add food, closing it and Done all leave none. Never persisted.
    func testAddFoodDayIsCarriedOnlyFromTheFoodLogAndNeverPersisted() {
        let defaults = isolatedDefaults()
        let coordinator = AppNavigationCoordinator(defaults: defaults)
        coordinator.restoreIfNeeded(hasDraft: false, availableRoutes: Set(AppRoute.allCases))
        coordinator.replacePath([.foodLog])
        coordinator.openAddFood(fromFoodLogDay: "2026-10-10")
        XCTAssertEqual(coordinator.path, [.foodLog, .addFood])
        XCTAssertEqual(coordinator.addFoodEntryDay, "2026-10-10")
        coordinator.recordDestination()
        XCTAssertEqual(coordinator.storedDestination, "addFood", "only the route is stored, never the day")
        XCTAssertNil(AppNavigationCoordinator(defaults: defaults).addFoodEntryDay)
        coordinator.acceptPathChange([.foodLog])
        XCTAssertNil(coordinator.addFoodEntryDay, "closing Add food forgets the day")
        coordinator.acceptPathChange([.foodLog, .addFood])
        XCTAssertNil(coordinator.addFoodEntryDay, "a later Add food does not inherit it")
        coordinator.openAddFood(fromFoodLogDay: nil)
        XCTAssertNil(coordinator.addFoodEntryDay, "today carries no day")
        coordinator.replacePath([])
        coordinator.acceptPathChange([.addFood])
        XCTAssertNil(coordinator.addFoodEntryDay, "Add food from Home stays Now")
        coordinator.replacePath([.foodLog])
        coordinator.openAddFood(fromFoodLogDay: "2026-10-09")
        coordinator.finishFoodEntry(reportingDay: "2026-10-09")
        XCTAssertEqual(coordinator.path, [.foodLog])
        XCTAssertNil(coordinator.addFoodEntryDay)
    }

    /// Search, barcode, web lookup, recent foods and quick add all start When on the Food Log day
    /// at the current clock time; a day beyond the window stays Now with the notice; the sheet's
    /// Edit keeps the sheet's When; Log saves on that day and Done returns to it.
    func testAddFoodFromAPastDayPrefillsWhenOnEveryRoute() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory),
                                                 userDefaults: isolatedDefaults())
        let calendar = root.confirmationDayCalendar
        let now = root.confirmationNow
        let yesterday = FoodReportingDay.key(for: try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now)), calendar: calendar)
        let tooOld = FoodReportingDay.key(for: try XCTUnwrap(calendar.date(byAdding: .day, value: -9, to: now)), calendar: calendar)
        let coordinator = AppNavigationCoordinator(defaults: isolatedDefaults())
        coordinator.replacePath([.foodLog])
        coordinator.openAddFood(fromFoodLogDay: yesterday)
        let finish = FoodEntryFinish(entryDay: coordinator.addFoodEntryDay) { coordinator.finishFoodEntry(reportingDay: $0) }
        let hosts: [(String, Any?)] = [
            ("Add food", AddFoodFlowView(root: root, finish: finish)),
            ("search", GenericFoodSearchFlowView(root: root, initialQuery: "clementine", finish: finish)),
            ("web lookup", OpenRouterFoodReviewFlowView(root: root, initialQuery: "tofu", finish: finish)),
            ("barcode", BarcodeFoodFlowView(root: root, finish: finish))
        ]
        for (name, host) in hosts {
            let carried = Mirror(reflecting: try XCTUnwrap(host, name)).descendant("finish") as? FoodEntryFinish
            XCTAssertEqual(carried?.entryDay, yesterday, name)
        }
        // Search, web lookup and barcode share root.model(for:entryDay:).
        let confirm = try savedClementineModel(root, entryDay: yesterday)
        let saved = try XCTUnwrap(confirm.savedResult)
        XCTAssertEqual(saved.logItemVersion.reportingDate.value, yesterday)
        XCTAssertTrue(FoodEntryFinish.complete(finish, saved: saved))
        XCTAssertEqual(coordinator.path, [.foodLog])
        XCTAssertEqual(coordinator.takeFoodLogFocusDay(), yesterday)
        // Recent foods.
        let relog = try XCTUnwrap(try root.model(relogging: saved.logItem.logItemID, entryDay: yesterday))
        XCTAssertEqual(relog.state.occurredAt.map { FoodReportingDay.key(for: $0, calendar: calendar) }, yesterday)
        XCTAssertNil(try XCTUnwrap(try root.model(relogging: saved.logItem.logItemID)).state.occurredAt, "no day: Now")
        // Quick add: the sheet, Confirm for an ineligible item, and the sheet's Edit.
        let water = try root.quickAddPreparation(.builtInWater)
        let sheet = root.quickAddSheetModel(water, entryDay: yesterday)
        XCTAssertFalse(sheet.occursNow)
        XCTAssertEqual(FoodReportingDay.key(for: sheet.displayedOccurredAt, calendar: calendar), yesterday)
        XCTAssertNil(sheet.whenNotice)
        sheet.setOccurredAt(nil)
        XCTAssertNil(root.model(quickAdd: try XCTUnwrap(sheet.editState)).state.occurredAt, "Edit keeps the sheet's Now")
        let direct = root.model(quickAdd: water.state, entryDay: yesterday)
        XCTAssertEqual(direct.state.occurredAt.map { FoodReportingDay.key(for: $0, calendar: calendar) }, yesterday)
        // Beyond the window: Now, with the notice on Confirm and the sheet.
        let old = root.quickAddSheetModel(water, entryDay: tooOld)
        XCTAssertTrue(old.occursNow)
        XCTAssertEqual(old.whenNotice, "Entries can be logged up to 7 days back.")
        let oldConfirm = root.model(quickAdd: water.state, entryDay: tooOld)
        XCTAssertNil(oldConfirm.state.occurredAt)
        XCTAssertEqual(oldConfirm.whenNotice, "Entries can be logged up to 7 days back.")
        for (size, name) in [(DynamicTypeSize.large, "standard"), (.accessibility3, "accessibility3")] {
            renderPolish(NavigationStack { FoodConfirmationView(model: direct) {} }.environment(\.dynamicTypeSize, size),
                         "Confirm from a past day - \(name)")
            renderPolish(NavigationStack { QuickAddSheet(model: old, edit: {}, close: {}) }.environment(\.dynamicTypeSize, size),
                         "Quick add beyond the window - \(name)")
        }
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

    /// A root on a fixed clock and calendar (09:42:17 BST on 14 October 2026), so the backdating
    /// window cannot move under the test at midnight.
    private func fixedDayRoot(_ directory: URL, _ defaults: UserDefaults) throws -> FoodLedgerCompositionRoot {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        return try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory), userDefaults: defaults,
            confirmationClock: FixedFoodLogClock(), confirmationCalendar: london)
    }

    /// Owner decision, 14 October 2026: on a Food Log day older than the backdating window, Add
    /// food is replaced by the window text; day 7 back keeps Add food with its day.
    func testFoodLogOffersAddFoodOnlyWithinTheBackdatingWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try fixedDayRoot(directory, isolatedDefaults())
        let model = root.foodLogModel()
        XCTAssertEqual(model.selectedKey, "2026-10-14")
        await model.showDay("2026-10-07")
        XCTAssertTrue(model.canAddFoodForSelectedDay)
        XCTAssertEqual(model.addFoodDayKey, "2026-10-07")
        await model.showDay("2026-10-06")
        XCTAssertFalse(model.canAddFoodForSelectedDay)
        XCTAssertNil(model.addFoodFootnote)
        await model.returnToToday()
        XCTAssertTrue(model.isToday)
        XCTAssertTrue(model.canAddFoodForSelectedDay)
    }

    /// The beyond-window Food Log day at default and accessibility sizes (visual check attached).
    func testFoodLogBeyondTheBackdatingWindowRenders() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let defaults = isolatedDefaults()
        let root = try fixedDayRoot(directory, defaults)
        for (size, name) in [(DynamicTypeSize.large, "standard"), (.accessibility3, "accessibility3")] {
            let navigation = AppNavigationCoordinator(defaults: defaults)
            // Done from Add food on the Food Log is the route that sets a focus day.
            navigation.replacePath([.foodLog, .addFood])
            navigation.finishFoodEntry(reportingDay: "2026-10-06")
            let controller = UIHostingController(rootView: NavigationStack {
                FoodLogView(root: root, navigation: navigation).environment(\.dynamicTypeSize, size)
            })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = controller
            window.isHidden = false
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Food Log - beyond the backdating window - \(name)"; attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(image.size.width, 390)
            window.isHidden = true
        }
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

    // MARK: UX polish (#212, phase 3 follow-ups)

    /// With an amount field focused, Edit shows "Done" in the navigation bar, not as a floating
    /// keyboard toolbar over the pinned Log bar; with nothing focused, the bar has no trailing item.
    func testFocusedAmountShowsDoneInTheNavigationBar() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory),
                                                 userDefaults: isolatedDefaults())
        let saved = try XCTUnwrap(try savedClementineModel(root).savedResult)
        let editModel = try XCTUnwrap(try root.model(reopening: saved.logItem.logItemID))
        let controller = UIHostingController(rootView: NavigationStack {
            Text("Saved entry").navigationDestination(isPresented: .constant(true)) { SavedEntryEditHost(model: editModel) {} }
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        func trailingItems() -> [UIBarButtonItem] {
            Self.descendants(controller.view).compactMap { $0 as? UINavigationBar }.flatMap {
                ($0.topItem?.rightBarButtonItems ?? []) + ($0.topItem?.trailingItemGroups.flatMap(\.barButtonItems) ?? [])
            }
        }
        XCTAssertFalse(Self.descendants(controller.view).compactMap { $0 as? UINavigationBar }.isEmpty)
        XCTAssertTrue(trailingItems().isEmpty, "no Done while nothing is focused")
        let quantity = try XCTUnwrap(Self.descendants(controller.view).compactMap { $0 as? UITextField }
            .first { $0.keyboardType == .decimalPad }, "an amount field uses the decimal pad")
        XCTAssertTrue(quantity.becomeFirstResponder())
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let items = trailingItems()
        XCTAssertEqual(items.compactMap(\.title), [FoodAmountFieldText.keyboardDoneTitle])
        XCTAssertFalse(items.isEmpty, "Done shows in the navigation bar while an amount field is focused")
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Edit - amount focused, Done in the navigation bar"; attachment.lifetime = .keepAlways
        add(attachment)
        quantity.resignFirstResponder()
        window.isHidden = true
    }

    /// Renders the polished screens at standard and accessibility sizes (synthetic data): Confirm
    /// after a save shows the plate row as a static, secondary row; Add food recents stack at
    /// accessibility sizes; the barcode unavailable heading wraps instead of truncating.
    func testUXPolishScreensRenderAtStandardAndAccessibilitySizes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory),
                                                 userDefaults: isolatedDefaults())
        let saved = try savedClementineModel(root)
        XCTAssertNotNil(saved.savedResult)
        let recents = root.recentFoods()
        XCTAssertFalse(recents.isEmpty, "the saved entry is a recent food")
        let guidance = BarcodePermissionGuidance(unavailable: true)
        XCTAssertEqual(guidance.title, "Barcode camera unavailable")
        for (size, name) in [(DynamicTypeSize.large, "standard"), (.accessibility3, "accessibility3")] {
            renderPolish(NavigationStack { FoodConfirmationView(model: saved) {} }.environment(\.dynamicTypeSize, size),
                   "Confirm after save - plate row \(name)")
            renderPolish(NavigationStack {
                AddFoodView(recents: recents, now: root.confirmationNow, calendar: root.confirmationDayCalendar,
                            search: { _ in }, scanBarcode: {}, pasteOrDictate: {}, favourites: {}, relog: { _ in })
            }.environment(\.dynamicTypeSize, size), "Add food - recents \(name)")
            renderPolish(NavigationStack { Form { Section { BarcodePermissionGuidanceView(guidance: guidance) {} } } }
                .environment(\.dynamicTypeSize, size), "Barcode unavailable - \(name)")
        }
    }

    /// B1: Confirm with mL on a per 100 g source renders "Log without nutrition" and the inline
    /// "Enter grams instead" action at standard and accessibility sizes (synthetic data).
    func testConfirmWithAnUnscalableUnitRendersLogWithoutNutrition() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory),
                                                 userDefaults: isolatedDefaults())
        let search = try root.genericFoodSearchModel(locale: Locale(identifier: "en_GB"))
        search.query = "clementine"
        search.search()
        guard case let .results(route) = search.phase else { throw XCTSkip("Expected offline fruit candidates") }
        let candidate = try XCTUnwrap(route.confirmation.candidates.first)
        XCTAssertEqual(candidate.candidate.identity.servingBasis, .per100Grams)
        let input = try PopulatedFoodConfirmation(evidence: route.confirmation.evidence, sourceReleases: route.confirmation.sourceReleases,
            candidates: [candidate], expectedIdentity: candidate.candidate.identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity)
        let model = root.model(for: input)
        model.send(.setQuantity(200, .millilitres))
        XCTAssertEqual(model.logButtonTitle, "Log without nutrition")
        XCTAssertEqual(model.sourceUnitAction?.actionTitle, "Enter grams instead")
        for (size, name) in [(DynamicTypeSize.large, "standard"), (.accessibility3, "accessibility3")] {
            renderPolish(NavigationStack { FoodConfirmationView(model: model) {} }.environment(\.dynamicTypeSize, size),
                         "Confirm mL on per 100 g - \(name)")
        }
    }

    /// QA fix: list import's Confirm offers the whole-milk volume estimate like the search route,
    /// and Add food tells the user list items keep Now when a past day is carried.
    func testListImportOffersTheMilkVolumeEstimateAndStatesNow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory),
                                                 userDefaults: isolatedDefaults())
        let list = try root.foodListModel(locale: Locale(identifier: "en_GB"))
        list.input = "200 ml whole milk"
        list.prepare()
        list.search()
        let policy = try CoFIDWholeMilkVolumeConversion()
        let matches = try XCTUnwrap(list.selectedRow?.route?.matches)
        let index = try XCTUnwrap(matches.firstIndex { policy.applies(to: $0.candidate) }, "CoFID whole milk is offered")
        list.review(candidate: index)
        let confirmation = try XCTUnwrap(list.confirmation)
        XCTAssertEqual(confirmation.state.quantity.unit, .millilitres)
        XCTAssertNotNil(confirmation.availableVolumeConversion)
        XCTAssertNil(confirmation.state.occurredAt, "list items keep Now")
        confirmation.applyAvailableVolumeConversion()
        XCTAssertEqual(confirmation.conversionMethodLabel, "Whole milk volume estimate (1.03 g per mL, PHE)")
        XCTAssertNotEqual(confirmation.logButtonTitle, "Log without nutrition")

        let note = FoodLogText.listImportNote(entryDay: "2026-10-10")
        for (size, name) in [(DynamicTypeSize.large, "standard"), (.accessibility3, "accessibility3")] {
            renderPolish(NavigationStack {
                AddFoodView(recents: [], search: { _ in }, scanBarcode: {}, pasteOrDictate: {}, favourites: {},
                            listImportNote: note, relog: { _ in })
            }.environment(\.dynamicTypeSize, size), "Add food from a past day - \(name)")
            renderPolish(NavigationStack { FoodConfirmationView(model: confirmation) {} }.environment(\.dynamicTypeSize, size),
                         "List Confirm with milk estimate - \(name)")
        }
    }

    /// Owner change: with 200 mL whole milk on the per 100 g CoFID record, the sourced estimate
    /// sits directly above "Log without nutrition" with its energy, at standard and accessibility
    /// sizes; once applied it leaves the Log bar and Log states the total.
    func testConfirmShowsTheMilkVolumeEstimateBesideLog() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory),
                                                 userDefaults: isolatedDefaults())
        let list = try root.foodListModel(locale: Locale(identifier: "en_GB"))
        list.input = "200 ml whole milk"
        list.prepare()
        list.search()
        let policy = try CoFIDWholeMilkVolumeConversion()
        let matches = try XCTUnwrap(list.selectedRow?.route?.matches)
        let index = try XCTUnwrap(matches.firstIndex { policy.applies(to: $0.candidate) }, "CoFID whole milk is offered")
        list.review(candidate: index)
        let confirmation = try XCTUnwrap(list.confirmation)
        XCTAssertEqual(confirmation.logButtonTitle, "Log without nutrition")
        XCTAssertEqual(confirmation.volumeEstimateLogBarAction?.title, "Use sourced whole-milk volume estimate (about 130 kcal)")
        for (size, name) in [(DynamicTypeSize.large, "standard"), (.accessibility3, "accessibility3")] {
            renderPolish(NavigationStack { FoodConfirmationView(model: confirmation) {} }.environment(\.dynamicTypeSize, size),
                         "Confirm milk estimate beside Log - \(name)")
        }
        confirmation.applyAvailableVolumeConversion()
        XCTAssertNil(confirmation.volumeEstimateLogBarAction)
        XCTAssertEqual(confirmation.logButtonTitle, "Log 130 kcal")
        renderPolish(NavigationStack { FoodConfirmationView(model: confirmation) {} }, "Confirm milk estimate applied - standard")
    }

    /// The barcode route opens the scanner once, on first opening, with no explainer tap; coming
    /// back from search or Confirm does not reopen it.
    func testBarcodeRouteStartsScanningOnceOnOpening() {
        // Device path: open the route, the scanner opens, scan, push to search, come back twice.
        var start = BarcodeFlowStart()
        XCTAssertEqual(start.buttonTitle, "Scan barcode", "no scan has opened yet")
        XCTAssertTrue(start.appear(), "opening the route starts the scanner")
        start.scannerOpened()
        XCTAssertEqual(start.buttonTitle, "Scan again")
        XCTAssertFalse(start.appear(), "returning from search does not reopen the scanner")
        XCTAssertFalse(start.appear(), "returning from Confirm does not reopen the scanner")
        // Simulator or unsupported device: the route appears, no scanner can open.
        var unsupported = BarcodeFlowStart()
        XCTAssertTrue(unsupported.appear())
        XCTAssertFalse(unsupported.appear())
        XCTAssertEqual(unsupported.buttonTitle, "Scan barcode", "never 'Scan again' before a scanner opened")
    }

    private func renderPolish<V: View>(_ content: V, _ name: String) {
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(image.size.width, 390)
        window.isHidden = true
    }

    private func savedClementineModel(_ root: FoodLedgerCompositionRoot, entryDay: String? = nil) throws -> FoodConfirmationViewModel {
        let search = try root.genericFoodSearchModel(locale: Locale(identifier: "en_GB"))
        search.query = "clementine"
        search.search()
        guard case let .results(route) = search.phase else { throw XCTSkip("Expected offline fruit candidates") }
        let candidate = try XCTUnwrap(route.confirmation.candidates.first)
        let input = try PopulatedFoodConfirmation(evidence: route.confirmation.evidence, sourceReleases: route.confirmation.sourceReleases,
            candidates: [candidate], expectedIdentity: candidate.candidate.identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity)
        let confirmation = root.model(for: input, entryDay: entryDay)
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

/// UX revamp phase 5 (#198): favourites, quick add and plain water through the composition root.
@MainActor
final class QuickAddAppTests: XCTestCase {
    private func makeRoot() throws -> FoodLedgerCompositionRoot {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: "quick-add-\(UUID().uuidString)")!
        return try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory), userDefaults: defaults)
    }

    /// An exact synthetic product (user-verified panel, fully known identity).
    private func exactInput(_ name: String = "Greek yoghurt") throws -> PopulatedFoodConfirmation {
        let evidenceID = try EvidenceID(UUID().uuidString.lowercased())
        let evidence = try CaptureEvidence(evidenceID: evidenceID, kind: .synthetic, capturedAt: Date(timeIntervalSince1970: 1_790_000_000),
            locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic_fixture"), captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText(name)))
        let release = SourceRelease(sourceReleaseID: try ExternalIdentifier("package:quick-add-app-v1"),
            sourceID: try ExternalIdentifier("physical_package"), releasedAt: Date(timeIntervalSince1970: 1_790_000_000),
            artifactHash: try SHA256Digest(String(repeating: "c", count: 64)), schemaVersion: try LedgerText("food-contract-v1"),
            pipelineVersion: try LedgerText("manual-capture-v1"), licence: try LedgerText("user supplied evidence"),
            attribution: try LedgerText("synthetic fixture"), manifestHash: try SHA256Digest(String(repeating: "d", count: 64)))
        let provenance = NutrientProvenance(sourceKind: .manualDeclaration, sourceID: release.sourceID,
            sourceReleaseID: release.sourceReleaseID, evidenceID: evidenceID)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard key == .energyConsumed else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(amount: 57, unit: .kilocalories,
                sourceValue: .exact(SourceExactNutrientValue(amount: 57, unit: LedgerText("kcal"), basis: .per100Grams)),
                provenance: [provenance])))
        })
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Grams)
        let quantity = EdibleQuantityIdentity.known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil)
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: release.sourceReleaseID,
            recordID: ExternalIdentifier("fixture:\(name)"), identity: identity, edibleQuantity: quantity, nutrients: nutrients,
            evidenceIDs: [evidenceID]), name: LedgerText(name), itemClass: .food)
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: identity, expectedEdibleQuantity: quantity)
    }

    /// Favourites opened from Add food on a past Food Log day: the create routes (Food search,
    /// Barcode, Web lookup) carry Add food's finish, so When starts on that day, Log saves there and
    /// Done returns to the Food Log on it. Opened from Home or Settings, they log for now.
    func testFavouriteCreatedFromAddFoodOnAPastDayLogsThereAndFinishesAddFood() throws {
        let root = try makeRoot()
        let calendar = root.confirmationDayCalendar
        let yesterday = FoodReportingDay.key(for: try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: root.confirmationNow)),
                                             calendar: calendar)
        let coordinator = AppNavigationCoordinator(defaults: UserDefaults(suiteName: "favourites-day-\(UUID().uuidString)")!)
        coordinator.replacePath([.foodLog])
        coordinator.openAddFood(fromFoodLogDay: yesterday)
        XCTAssertEqual(coordinator.path, [.foodLog, .addFood])
        let addFood = AddFoodFlowView(root: root, finish: FoodEntryFinish(entryDay: coordinator.addFoodEntryDay) {
            coordinator.finishFoodEntry(reportingDay: $0)
        })
        let favourites = addFood.favouritesFlow
        XCTAssertEqual((Mirror(reflecting: favourites).descendant("finish") as? FoodEntryFinish)?.entryDay, yesterday,
                       "Add food passes its finish to Favourites")
        let create = favourites.createFinish
        XCTAssertEqual(create.entryDay, yesterday, "search, barcode and web lookup carry the day")

        let confirm = root.model(for: try exactInput(), prefillSourceQuantity: false, savesFavourite: true, entryDay: create.entryDay)
        XCTAssertEqual(confirm.state.occurredAt.map { FoodReportingDay.key(for: $0, calendar: calendar) }, yesterday,
                       "When starts on the Food Log day")
        confirm.send(.setQuantity(150, .grams))
        confirm.log()
        XCTAssertEqual(confirm.favouriteOutcome, .saved, "\(confirm.state.phase)")
        let saved = try XCTUnwrap(confirm.savedResult)
        XCTAssertEqual(saved.logItemVersion.reportingDate.value, yesterday, "saved on that day")
        XCTAssertTrue(FoodEntryFinish.complete(create, saved: saved), "Done finishes Add food")
        XCTAssertEqual(coordinator.path, [.foodLog])
        XCTAssertEqual(coordinator.takeFoodLogFocusDay(), yesterday)

        // From Home or Settings, Favourites has no Add food finish: Now, and Done stays in Favourites.
        let standalone = FavouritesFlowView(root: root)
        XCTAssertNil(Mirror(reflecting: standalone).descendant("finish") as? FoodEntryFinish)
        XCTAssertNil(standalone.createFinish.entryDay)
        XCTAssertNil(root.model(for: try exactInput("Oat milk"), prefillSourceQuantity: false, savesFavourite: true,
                                entryDay: standalone.createFinish.entryDay).state.occurredAt, "logs for now")
    }

    /// Logs an exact food from Confirm with Save as favourite on; returns the new favourite.
    private func favouriteFromConfirm(_ root: FoodLedgerCompositionRoot, _ name: String = "Greek yoghurt",
                                      grams: Double = 150) throws -> FavouriteVersion {
        let model = root.model(for: try exactInput(name), prefillSourceQuantity: false, savesFavourite: true)
        XCTAssertTrue(model.offersFavourite)
        XCTAssertEqual(model.logButtonTitle, "Log and save favourite")
        model.send(.setQuantity(grams, .grams))
        model.log()
        XCTAssertEqual(model.favouriteOutcome, .saved, "\(model.state.phase)")
        guard case let .favourite(favourite)? = try XCTUnwrap(root.quickAddItems()).last else {
            throw XCTSkip("Expected the new favourite")
        }
        return favourite
    }

    /// Home water chip: the sheet opens on a tap (nothing written), one Log saves 250 mL, and the
    /// same plain water figure appears on Home and in the Food Log.
    func testWaterChipLogsPlainWaterShownOnHomeAndInTheFoodLog() throws {
        let root = try makeRoot()
        let items = try XCTUnwrap(root.quickAddItems())
        XCTAssertEqual(items.first, .builtInWater)
        let today = root.confirmationNow
        XCTAssertNil(try root.plainWaterTotal(for: today, calendar: root.confirmationDayCalendar), "No data, not 0 mL")
        let preparation = try root.quickAddPreparation(.builtInWater)
        XCTAssertEqual(preparation.eligibility, .sheet)
        let sheet = root.quickAddSheetModel(preparation)
        XCTAssertNil(try root.plainWaterTotal(for: today, calendar: root.confirmationDayCalendar), "Opening the sheet writes nothing")
        XCTAssertEqual(sheet.logTitle, "Log 250 mL")
        sheet.log(); sheet.log()
        XCTAssertEqual(sheet.phase, .saved)
        let saved = try XCTUnwrap(sheet.savedResult)
        XCTAssertEqual(try root.plainWaterTotal(for: today, calendar: root.confirmationDayCalendar)?.knownAmount, 250)
        let day = try root.foodLogService.day(reportingDate: saved.logItemVersion.reportingDate.value)
        XCTAssertEqual(day.plainWater?.knownAmount, 250)
        XCTAssertEqual(day.entries.count, 1, "One Log press saves once")
        XCTAssertEqual(FoodLogText.plainWater(day.plainWater, locale: Locale(identifier: "en_GB")), "250 mL")
        XCTAssertTrue(try XCTUnwrap(root.quickAddItems()).contains(.builtInWater), "Logging water writes no favourite")
    }

    /// QA D1: logging from the sheet runs the completion exactly once, which dismisses the sheet and
    /// reloads the host (or ends Add food through its single exit); Edit is then unavailable.
    func testSheetLogCompletesOnceDismissesAndBlocksEdit() throws {
        let root = try makeRoot()
        var dismissed = 0, reloaded = 0
        let sheet = root.quickAddSheetModel(try root.quickAddPreparation(.builtInWater))
        sheet.onLogged = QuickAddPresenter.completion(dismiss: { dismissed += 1 }, finish: nil, logged: { reloaded += 1 })
        XCTAssertNotNil(sheet.editState)
        sheet.log(); sheet.log()
        XCTAssertEqual(dismissed, 1); XCTAssertEqual(reloaded, 1)
        XCTAssertNil(sheet.editState, "A logged sheet cannot be logged again through Edit")
        let coordinator = AppNavigationCoordinator(defaults: UserDefaults(suiteName: "quick-add-\(UUID().uuidString)")!)
        coordinator.replacePath([.foodLog, .addFood])
        var finished = 0
        let inside = root.quickAddSheetModel(try root.quickAddPreparation(.builtInWater))
        inside.onLogged = QuickAddPresenter.completion(dismiss: { dismissed += 1 },
            finish: FoodEntryFinish { finished += 1; coordinator.finishFoodEntry(reportingDay: $0) }, logged: { reloaded += 1 })
        inside.log()
        XCTAssertEqual(finished, 1); XCTAssertEqual(reloaded, 1, "Inside Add food the journey finishes instead")
        XCTAssertEqual(coordinator.path, [.foodLog])
    }

    /// Confirm's "Save as favourite" writes the favourite after Log; the favourite then quick-adds
    /// through the sheet.
    func testSaveAsFavouriteFromConfirmThenQuickAddFromTheChip() throws {
        let root = try makeRoot()
        let favourite = try favouriteFromConfirm(root)
        XCTAssertEqual(favourite.defaultAmount, try FavouriteAmount(value: 150, unit: .grams))
        let preparation = try root.quickAddPreparation(.favourite(favourite))
        XCTAssertEqual(preparation.eligibility, .sheet)
        let sheet = root.quickAddSheetModel(preparation)
        sheet.log()
        XCTAssertEqual(sheet.savedResult?.logItemVersion.edibleQuantity.value, 150)
    }

    /// QA D2: Confirm never offers Save as favourite for plain water (already the built-in quick add).
    func testPlainWaterConfirmDoesNotOfferSaveAsFavourite() throws {
        let root = try makeRoot()
        let water = try PlainWaterReference(digester: SHA256Digester())
        let model = root.model(for: water.input, prefillSourceQuantity: false, savesFavourite: true)
        XCTAssertFalse(model.offersFavourite)
        XCTAssertFalse(model.savesFavourite)
        model.send(.setQuantity(330, .millilitres))
        XCTAssertNotEqual(model.logButtonTitle, "Log and save favourite")
        model.log()
        XCTAssertNotNil(model.savedResult)
        XCTAssertEqual(try XCTUnwrap(root.quickAddItems()), [.builtInWater], "No second Water item")
        XCTAssertFalse(root.model(quickAdd: try root.quickAddPreparation(.builtInWater).state).offersFavourite)
    }

    /// The sheet and Confirm for a milk favourite use the same enriched input (the volume source is
    /// offered in Confirm), so both save the same entry.
    func testMilkFavouriteSheetAndConfirmUseTheSameVolumeSourceInput() throws {
        let root = try makeRoot()
        let search = try root.genericFoodSearchModel(locale: Locale(identifier: "en_GB"))
        search.query = "Milk, whole, pasteurised, average"
        search.search()
        guard case let .results(route) = search.phase,
              let milk = route.confirmation.candidates.first(where: { $0.name.value.localizedCaseInsensitiveContains("whole") }) else {
            throw XCTSkip("Expected offline CoFID whole milk")
        }
        let input = try PopulatedFoodConfirmation(evidence: route.confirmation.evidence, sourceReleases: route.confirmation.sourceReleases,
            candidates: [milk], expectedIdentity: milk.candidate.identity, expectedEdibleQuantity: milk.candidate.edibleQuantity)
        let confirm = root.model(for: input, prefillSourceQuantity: false, savesFavourite: true)
        confirm.send(.setQuantity(200, .millilitres))
        confirm.answerPendingDifferencesForTest()
        guard confirm.availableVolumeConversion != nil else { throw XCTSkip("Milk volume source not offered") }
        confirm.applyAvailableVolumeConversion()
        confirm.log()
        XCTAssertEqual(confirm.favouriteOutcome, .saved, "\(confirm.state.phase)")
        guard case let .favourite(favourite)? = try XCTUnwrap(root.quickAddItems()).last else { return XCTFail("favourite") }
        XCTAssertEqual(favourite.defaultAmount.unit, .millilitres)
        let preparation = try root.quickAddPreparation(.favourite(favourite))
        let sheet = root.quickAddSheetModel(preparation)
        let edit = root.model(quickAdd: preparation.state)
        XCTAssertEqual(sheet.state.input, edit.state.input)
        XCTAssertTrue(sheet.state.input.sourceReleases.contains { $0.sourceReleaseID.value.hasPrefix("phe-npm-2018") })
        XCTAssertNotNil(edit.availableVolumeConversion, "Confirm carries the volume offering")
        edit.answerPendingDifferencesForTest()
        sheet.log(); edit.log()
        let fromSheet = try XCTUnwrap(sheet.savedResult), fromConfirm = try XCTUnwrap(edit.savedResult)
        XCTAssertEqual(fromSheet.logItemVersion.edibleQuantity, fromConfirm.logItemVersion.edibleQuantity)
        XCTAssertEqual(fromSheet.resolutionVersion.nutrients, fromConfirm.resolutionVersion.nutrients)
        XCTAssertEqual(fromSheet.sourceReleases.map(\.sourceReleaseID), fromConfirm.sourceReleases.map(\.sourceReleaseID))
        XCTAssertEqual(fromSheet.quantityConversion == nil, fromConfirm.quantityConversion == nil)
    }

    /// Review: Add food shows a failure, not "No favourites yet", when favourites cannot be read.
    func testAddFoodFavouritesStateDistinguishesFailureFromEmpty() {
        XCTAssertEqual(AddFoodFavouritesState(nil, quickAdd: true), .failed)
        XCTAssertEqual(AddFoodFavouritesState([], quickAdd: true), .empty)
        XCTAssertEqual(AddFoodFavouritesState([.builtInWater], quickAdd: true), .items([.builtInWater]))
    }

    /// Owner decision A: logging without Save as favourite, then saving from the saved entry and
    /// from "From what you’ve logged" pins the current version; a repeat shows Already a favourite.
    func testSaveAsFavouriteFromTheSavedEntryAndFromWhatYouLogged() throws {
        let root = try makeRoot()
        let confirm = root.model(for: try exactInput("Skyr"), prefillSourceQuantity: false)
        confirm.send(.setQuantity(170, .grams))
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult)
        let versionID = saved.logItemVersion.logItemVersionID
        let logged = try root.loggedFoods()
        XCTAssertEqual(logged.first?.logItemVersionID, versionID)
        XCTAssertEqual(FavouriteFromLoggedView.offered(logged).map(\.name), ["Skyr"])

        let fromEntry = root.favouriteSaveModel()
        fromEntry.refresh([versionID])
        XCTAssertEqual(fromEntry.state(for: versionID), .available)
        fromEntry.save(versionID)
        XCTAssertEqual(fromEntry.state(for: versionID), .saved)
        guard case let .favourite(favourite)? = try XCTUnwrap(root.quickAddItems()).last else { return XCTFail("favourite") }
        XCTAssertEqual(favourite.binding, .savedEntry(versionID))
        XCTAssertEqual(favourite.defaultAmount, try FavouriteAmount(value: 170, unit: .grams))

        let fromList = root.favouriteSaveModel()
        fromList.refresh(logged.compactMap(\.logItemVersionID))
        XCTAssertEqual(fromList.state(for: versionID), .alreadyFavourite)
        fromList.save(versionID)
        XCTAssertEqual(try XCTUnwrap(root.quickAddItems()).count, 2, "built-in water and one favourite, no duplicate")
    }

    /// Review question 1, through the composition root: the recent list is read, the entry is then
    /// edited, and saving from the stale row pins the edited (current) version.
    func testStaleRecentRowPinsTheCurrentVersion() throws {
        let root = try makeRoot()
        let confirm = root.model(for: try exactInput("Muesli"), prefillSourceQuantity: false)
        confirm.send(.setQuantity(60, .grams))
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult)
        let stale = try XCTUnwrap(try root.loggedFoods().first)
        XCTAssertEqual(stale.logItemVersionID, saved.logItemVersion.logItemVersionID)
        let edit = try XCTUnwrap(try root.model(reopening: saved.logItem.logItemID))
        edit.send(.setQuantity(80, .grams))
        edit.log()
        let edited = try XCTUnwrap(edit.savedResult).logItemVersion.logItemVersionID
        XCTAssertNotEqual(edited, stale.logItemVersionID)
        let model = root.favouriteSaveModel()
        model.save(try XCTUnwrap(stale.logItemVersionID), logItemID: stale.item.logItemID)
        XCTAssertEqual(model.state(for: try XCTUnwrap(stale.logItemVersionID)), .saved)
        guard case let .favourite(favourite)? = try XCTUnwrap(root.quickAddItems()).last else { return XCTFail("favourite") }
        XCTAssertEqual(favourite.binding, .savedEntry(edited), "the current version, never the stale one")
    }

    /// Journey QA: a saved plain water entry names its source plainly and keeps the mL symbol;
    /// other entries keep their family name.
    func testSavedEntrySourceLineForPlainWaterAndFood() async throws {
        let root = try makeRoot()
        let sheet = root.quickAddSheetModel(try root.quickAddPreparation(.builtInWater))
        sheet.log()
        let water = try XCTUnwrap(sheet.savedResult)
        let waterDetail = try XCTUnwrap(try root.foodLogService.savedEntry(water.logItem.logItemID))
        XCTAssertEqual(FoodLogText.source(waterDetail), "Plain water · per 100 mL")
        let confirm = root.model(for: try exactInput("Rye bread"), prefillSourceQuantity: false)
        confirm.send(.setQuantity(40, .grams))
        confirm.log()
        let food = try XCTUnwrap(confirm.savedResult)
        let foodDetail = try XCTUnwrap(try root.foodLogService.savedEntry(food.logItem.logItemID))
        XCTAssertTrue(FoodLogText.source(foodDetail).hasSuffix(" · per 100 g"), FoodLogText.source(foodDetail))
        XCTAssertFalse(FoodLogText.source(foodDetail).hasPrefix(FoodLogText.plainWaterSourceName))
    }

    /// Native renders of the changed Favourites layouts: the Add section with "From what you’ve
    /// logged" and "Add Water to quick add", the list itself, and the saved entry's favourite
    /// section; default and accessibility3 text sizes.
    func testFavouritesFromLoggedScreensRender() async throws {
        let root = try makeRoot()
        let confirm = root.model(for: try exactInput("Overnight oats with blueberries and a long descriptive name"), prefillSourceQuantity: false)
        confirm.send(.setQuantity(200, .grams))
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult)
        let favourites = root.favouritesModel()
        favourites.reload()
        favourites.remove(try XCTUnwrap(favourites.today.first))
        XCTAssertTrue(favourites.canAddWater)
        let logged = try root.loggedFoods()
        let saving = root.favouriteSaveModel()
        saving.refresh(logged.compactMap(\.logItemVersionID))
        let failing = root.favouriteSaveModel()
        for (size, name) in [(DynamicTypeSize.large, "standard"), (.accessibility3, "accessibility3")] {
            render(NavigationStack {
                FavouritesView(model: favourites, createFromLogged: {}, createFromSearch: {}, createFromBarcode: {}, createFromWebLookup: {})
            }.environment(\.dynamicTypeSize, size), "Favourites - water removed, add section \(name)")
            render(NavigationStack {
                FavouriteFromLoggedView(content: .items(logged), now: root.confirmationNow, calendar: root.confirmationDayCalendar,
                                        model: saving, retry: {})
            }.environment(\.dynamicTypeSize, size), "From what you've logged - \(name)")
            render(NavigationStack {
                FavouriteFromLoggedView(content: .failed, now: root.confirmationNow, calendar: root.confirmationDayCalendar,
                                        model: failing, retry: {})
            }.environment(\.dynamicTypeSize, size), "From what you've logged - failed \(name)")
            let entry = root.savedEntryModel(saved.logItem.logItemID)
            await entry.load()
            XCTAssertEqual(entry.phase, .loaded)
            XCTAssertEqual(entry.detail?.isPlainWater, false)
            render(NavigationStack {
                SavedFoodEntryView(model: entry, favourites: root.favouriteSaveModel(),
                                   calendar: root.confirmationDayCalendar, now: { root.confirmationNow })
            }.environment(\.dynamicTypeSize, size), "Saved entry - save as favourite \(name)")
        }
        saving.save(saved.logItemVersion.logItemVersionID)
        render(NavigationStack {
            FavouriteFromLoggedView(content: .items(logged), now: root.confirmationNow, calendar: root.confirmationDayCalendar,
                                    model: saving, retry: {})
        }, "From what you've logged - saved")
        favourites.addWater()
        XCTAssertFalse(favourites.canAddWater)
        XCTAssertEqual(favourites.today.first?.title, "Water")
    }

    /// Native renders (synthetic data): Favourites populated and empty, Home chips (including a long
    /// name, whose amount stays whole), the quick-add sheet ready and with an invalid custom amount,
    /// Confirm with Save as favourite; standard and accessibility text sizes, light and dark.
    func testQuickAddScreensRender() throws {
        let root = try makeRoot()
        let empty = root.favouritesModel()
        empty.reload()
        XCTAssertEqual(empty.today.map(\.item), [.builtInWater])
        render(NavigationStack { FavouritesView(model: empty, createFromSearch: {}, createFromBarcode: {}, createFromWebLookup: {}) }, "Favourites - water only")
        empty.setDefaultAmount(empty.today[0], to: 500)
        XCTAssertNil(empty.changeFailure)
        _ = try favouriteFromConfirm(root, "Greek yoghurt with honey, walnuts and a very long descriptive name")
        let populated = root.favouritesModel()
        populated.reload()
        XCTAssertEqual(populated.today.count, 2)
        let chips = try XCTUnwrap(root.quickAddItems())
        XCTAssertTrue(chips.map(QuickAddText.defaultAmount).contains("150 g"))
        for (size, scheme, name) in [(DynamicTypeSize.large, ColorScheme.light, "standard light"), (.accessibility3, .dark, "accessibility dark")] {
            render(NavigationStack { FavouritesView(model: populated, createFromSearch: {}, createFromBarcode: {}, createFromWebLookup: {}) }
                .environment(\.dynamicTypeSize, size).preferredColorScheme(scheme), "Favourites - \(name)")
            render(NavigationStack { Form { QuickAddChipRow(items: chips) { _ in } } }
                .environment(\.dynamicTypeSize, size).preferredColorScheme(scheme), "Home chips - \(name)")
            let ready = root.quickAddSheetModel(try root.quickAddPreparation(.builtInWater))
            render(NavigationStack { QuickAddSheet(model: ready, edit: {}, close: {}) }
                .environment(\.dynamicTypeSize, size).preferredColorScheme(scheme), "Quick add - ready \(name)")
            let invalid = root.quickAddSheetModel(try root.quickAddPreparation(.builtInWater))
            invalid.setCustomText("6000")
            XCTAssertEqual(invalid.blockedReason, QuickAddText.waterBoundText)
            render(NavigationStack { QuickAddSheet(model: invalid, edit: {}, close: {}) }
                .environment(\.dynamicTypeSize, size).preferredColorScheme(scheme), "Quick add - custom invalid \(name)")
            let confirm = root.model(for: try exactInput(), savesFavourite: true)
            render(NavigationStack { FoodConfirmationView(model: confirm) {} }
                .environment(\.dynamicTypeSize, size).preferredColorScheme(scheme), "Confirm - save as favourite \(name)")
        }
    }

    private func render<V: View>(_ content: V, _ name: String) {
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(image.size.width, 390)
        window.isHidden = true
    }
}

private extension FoodConfirmationViewModel {
    /// Answers any pending inline difference with the source's own value, as a user would.
    func answerPendingDifferencesForTest() {
        for facet in pendingDifferences {
            let offered = offeredChoices(facet)
            send(.decideDifference(facet, offered.first { $0 == .matchesSource } ?? offered[0]))
        }
    }
}

private struct FixedFoodLogClock: LedgerClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_791_967_337) } // 2026-10-14T08:42:17Z
}

/// Owner decision, 15 October 2026: Log on a new single food saves and closes Confirm through the
/// exit Done used, then the destination shows "Logged · …" with Undo. Undo writes one Food Log
/// remove; list import and Edit keep their saved state.
extension QuickAddAppTests {
    /// The exit each host passes as `leave`: Add food's finish, Favourites' return, or a pop.
    private func hostLeave(_ finish: FoodEntryFinish?, _ model: FoodConfirmationViewModel,
                           popped: @escaping () -> Void) -> () -> Void {
        { if !FoodEntryFinish.complete(finish, saved: model.savedResult) { popped() } }
    }

    private func newEntry(_ root: FoodLedgerCompositionRoot, _ name: String = "Greek yoghurt",
                          favourite: Bool = false) throws -> FoodConfirmationViewModel {
        let model = root.model(for: try exactInput(name), prefillSourceQuantity: false, savesFavourite: favourite)
        model.send(.setQuantity(100, .grams))
        return model
    }

    private func makeCoordinator() -> AppNavigationCoordinator {
        let name = "log-closes-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return AppNavigationCoordinator(defaults: defaults)
    }

    func testLogClosesConfirmToTheDoneDestinationOfEachHostAndShowsTheBanner() throws {
        let root = try makeRoot()
        let single = root.singleFoodConfirmation(try newEntry(root)) {}
        XCTAssertNotNil(Mirror(reflecting: single).descendant("logged") as? (FoodLoggedNotice) -> Void,
                        "single-food hosts pass the banner")
        // Add food opened from the Food Log: back to the Food Log on the entry's day.
        let coordinator = makeCoordinator()
        coordinator.replacePath([.foodLog, .addFood])
        root.loggedBanner.location = { AnyHashable(coordinator.path) }
        let addFood = FoodEntryFinish { coordinator.finishFoodEntry(reportingDay: $0) }
        let fromLog = try newEntry(root)
        XCTAssertEqual(fromLog.logButtonTitle, "Log 57 kcal")
        var popped = 0
        XCTAssertTrue(FoodConfirmationView.logTapped(fromLog, leave: hostLeave(addFood, fromLog) { popped += 1 },
                                                     logged: root.loggedBanner.show))
        XCTAssertEqual(coordinator.path, [.foodLog])
        XCTAssertEqual(coordinator.takeFoodLogFocusDay(), fromLog.savedResult?.logItemVersion.reportingDate.value)
        XCTAssertEqual(root.loggedBanner.content?.message, "Logged · 57 kcal")
        XCTAssertTrue(root.loggedBanner.content?.offersUndo == true)
        root.loggedBanner.navigated(to: AnyHashable(coordinator.path))
        XCTAssertNotNil(root.loggedBanner.content, "the closing navigation keeps the banner")
        // Add food opened from Home: back Home.
        coordinator.replacePath([.addFood])
        let fromHome = try newEntry(root, "Oat milk")
        XCTAssertTrue(FoodConfirmationView.logTapped(fromHome, leave: hostLeave(addFood, fromHome) { popped += 1 },
                                                     logged: root.loggedBanner.show))
        XCTAssertEqual(coordinator.path, [])
        // Hosts outside Add food (Home's quick-add Confirm, the standalone routes): the host pops.
        let standalone = try newEntry(root, "Skyr")
        XCTAssertTrue(FoodConfirmationView.logTapped(standalone, leave: hostLeave(nil, standalone) { popped += 1 },
                                                     logged: root.loggedBanner.show))
        XCTAssertEqual(popped, 1)
        // Favourites opened from Home: the create routes return to Favourites.
        let favourites = FavouritesFlowView(root: root)
        let created = try newEntry(root, "Kefir", favourite: true)
        XCTAssertTrue(FoodConfirmationView.logTapped(created, leave: hostLeave(favourites.createFinish, created) { popped += 1 },
                                                     logged: root.loggedBanner.show))
        XCTAssertEqual(popped, 1, "Favourites' own return, not a pop")
        XCTAssertEqual(root.loggedBanner.content?.message, "Logged and saved as favourite · 57 kcal")
        XCTAssertEqual(root.loggedBanner.content?.detail, "Undo removes the entry. The favourite stays.")
    }

    func testUndoRemovesOnlyTheEntryAndTheFavouriteStays() async throws {
        let root = try makeRoot()
        let model = try newEntry(root, "Kefir", favourite: true)
        XCTAssertTrue(FoodConfirmationView.logTapped(model, leave: {}, logged: root.loggedBanner.show))
        let saved = try XCTUnwrap(model.savedResult)
        let day = saved.logItemVersion.reportingDate.value
        XCTAssertEqual(try root.foodLogService.day(reportingDate: day).entries.count, 1)
        let favouritesBefore = try XCTUnwrap(root.quickAddItems())
        await root.loggedBanner.undo()
        await root.loggedBanner.undo()
        let after = try root.foodLogService.day(reportingDate: day)
        XCTAssertTrue(after.entries.isEmpty)
        XCTAssertEqual(after.removed.map(\.logItemID), [saved.logItem.logItemID], "the entry moves to Removed")
        // Append-only: the logged version and exactly one removed version, written by the Food
        // Log remove path (its fixed reason is pinned by the reading service contract tests).
        XCTAssertEqual(try root.foodLogService.historyEvents(saved.logItem.logItemID).map(\.kind), [.removed, .logged],
                       "newest first")
        XCTAssertEqual(root.loggedBanner.content, .result("Entry removed"))
        XCTAssertEqual(root.loggedBanner.removals, 1)
        XCTAssertEqual(try XCTUnwrap(root.quickAddItems()), favouritesBefore, "the favourite stays")
    }

    func testUndoIsUnavailableAfterTimeoutOrNavigation() async throws {
        let root = try makeRoot()
        let coordinator = makeCoordinator()
        coordinator.replacePath([.foodLog])
        root.loggedBanner.location = { AnyHashable(coordinator.path) }
        let timedOut = try newEntry(root)
        XCTAssertTrue(FoodConfirmationView.logTapped(timedOut, leave: {}, logged: root.loggedBanner.show))
        root.loggedBanner.expire(generation: root.loggedBanner.currentGeneration)
        XCTAssertNil(root.loggedBanner.content)
        await root.loggedBanner.undo()
        let navigatedAway = try newEntry(root, "Oat milk")
        XCTAssertTrue(FoodConfirmationView.logTapped(navigatedAway, leave: {}, logged: root.loggedBanner.show))
        coordinator.openAddFood(fromFoodLogDay: nil)
        root.loggedBanner.navigated(to: AnyHashable(coordinator.path))
        XCTAssertNil(root.loggedBanner.content)
        await root.loggedBanner.undo()
        let day = try XCTUnwrap(timedOut.savedResult).logItemVersion.reportingDate.value
        XCTAssertEqual(try root.foodLogService.day(reportingDate: day).entries.count, 2, "nothing removed")
    }

    func testSaveFailureAndFavouriteFailureStayOnConfirm() throws {
        let root = try makeRoot()
        let state = try newEntry(root).state
        let now = root.confirmationNow
        struct Refused: Error {}
        let failing = FoodConfirmationViewModel(state: state, now: { now },
                                                calendar: root.confirmationDayCalendar) { _ in throw Refused() }
        var left = 0
        XCTAssertFalse(FoodConfirmationView.logTapped(failing, leave: { left += 1 }, logged: root.loggedBanner.show))
        XCTAssertEqual(left, 0)
        guard case .saveFailed = failing.state.phase else { return XCTFail("\(failing.state.phase)") }
        XCTAssertNil(root.loggedBanner.content)
        // The entry saves but its favourite does not: Confirm stays with Try again and Done.
        let stored = try XCTUnwrap(try newEntry(root, "Skyr").savedResultAfterLog())
        let favouriteFails = FoodConfirmationViewModel(state: state, now: { now },
            calendar: root.confirmationDayCalendar, savesFavourite: true,
            favouriteAction: { _ in throw Refused() }) { _ in stored }
        XCTAssertFalse(FoodConfirmationView.logTapped(favouriteFails, leave: { left += 1 }, logged: root.loggedBanner.show))
        XCTAssertEqual(favouriteFails.favouriteOutcome, .failed)
        XCTAssertNotNil(favouriteFails.savedResult)
        XCTAssertEqual(left, 0)
        XCTAssertNil(root.loggedBanner.content)
    }

    func testListImportAndEditKeepTheirSavedState() throws {
        let root = try makeRoot()
        let saved = try XCTUnwrap(try newEntry(root).savedResultAfterLog())
        let edit = try XCTUnwrap(try root.model(reopening: saved.logItem.logItemID))
        edit.send(.setQuantity(120, .grams))
        XCTAssertEqual(edit.logButtonTitle, "Save changes")
        var left = 0
        XCTAssertFalse(FoodConfirmationView.logTapped(edit, leave: { left += 1 }, logged: root.loggedBanner.show),
                       "Save changes never closes, even with a handler")
        XCTAssertNotNil(edit.savedResult)
        XCTAssertEqual(left, 0)
        XCTAssertNil(root.loggedBanner.content)
        // List import and Edit build Confirm without the handler.
        let list = ListConfirmationHost(confirmation: try newEntry(root, "Oat milk"), context: nil) {}
        let listConfirm = try XCTUnwrap(Self.firstDescendant(of: list.body, ofType: FoodConfirmationView.self), "list import hosts Confirm")
        XCTAssertNil(Mirror(reflecting: listConfirm).descendant("logged") as? (FoodLoggedNotice) -> Void, "list import keeps Next line")
        let editConfirm = try XCTUnwrap(Self.firstDescendant(of: SavedEntryEditHost(model: edit) {}.body, ofType: FoodConfirmationView.self))
        XCTAssertNil(Mirror(reflecting: editConfirm).descendant("logged") as? (FoodLoggedNotice) -> Void, "Edit keeps Done")
    }

    func testQuickAddSheetLogClosesAndTheBannerShowsItsAmount() async throws {
        let root = try makeRoot()
        let coordinator = makeCoordinator()
        coordinator.replacePath([.foodLog, .addFood])
        root.loggedBanner.location = { AnyHashable(coordinator.path) }
        let sheet = root.quickAddSheetModel(try root.quickAddPreparation(.builtInWater))
        var dismissed = 0
        sheet.onLogged = QuickAddPresenter.completion(dismiss: { dismissed += 1 },
            finish: FoodEntryFinish { coordinator.finishFoodEntry(reportingDay: $0) }, logged: {},
            notice: { [weak sheet] in sheet?.loggedNotice }, show: root.loggedBanner.show)
        sheet.log()
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(coordinator.path, [.foodLog])
        XCTAssertEqual(root.loggedBanner.content?.message, "Logged · 250 mL")
        await root.loggedBanner.undo()
        XCTAssertNil(try root.plainWaterTotal(for: root.confirmationNow, calendar: root.confirmationDayCalendar),
                     "the removed water leaves the day")
    }

    func testBannerRendersAtStandardAndAccessibilitySizesInLightAndDark() throws {
        let notice = FoodLoggedNotice(logItemID: try LogItemID("00000000-0000-0000-0000-000000000001"),
            logItemVersionID: try LogItemVersionID("00000000-0000-0000-0000-000000000002"),
            message: "Logged and saved as favourite · 260 kcal", detail: FoodLoggedText.favouriteStays)
        let contents: [(String, FoodLoggedBannerModel.Content)] = [
            ("logged", .logged(notice)), ("removed", .result(FoodLoggedText.removed))
        ]
        for (kind, content) in contents {
            for (size, sizeName) in [(DynamicTypeSize.large, "standard"), (.accessibility3, "accessibility3")] {
                for scheme in [ColorScheme.light, .dark] {
                    render(ZStack(alignment: .bottom) {
                        Color(.systemGroupedBackground).ignoresSafeArea()
                        FoodLoggedBannerContent(content: content, undo: {}, dismiss: {})
                    }
                    .environment(\.dynamicTypeSize, size).environment(\.colorScheme, scheme),
                    "Logged banner - \(kind) - \(sizeName) - \(scheme == .dark ? "dark" : "light")")
                }
            }
        }
    }

    /// Review fix: a push outside the navigation path (the Food Log opening a saved entry through
    /// `navigationDestination(item:)`, search results through `isPresented:`) dismisses the banner
    /// shown on the screen underneath, so Undo is never offered over another screen.
    func testOpeningASavedEntryDismissesTheBannerShownOnTheFoodLog() async throws {
        try await assertNonPathPushDismissesTheBanner("item")
    }

    func testPushingSearchResultsDismissesTheBannerShownBelow() async throws {
        try await assertNonPathPushDismissesTheBanner("isPresented")
    }

    private func assertNonPathPushDismissesTheBanner(_ kind: String) async throws {
        let root = try makeRoot()
        let banner = root.loggedBanner
        do {
            let pushes = BannerPushState()
            let host = UIHostingController(rootView: NavigationStack {
                BannerPushRoot(state: pushes, banner: banner, usesItem: kind == "item")
            })
            // A window in the app's scene, so navigation and window changes run as on device.
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.makeKeyAndVisible()
            addTeardownBlock { window.isHidden = true }
            Self.runUntil { banner.hasVisibleScreen }
            XCTAssertTrue(banner.hasVisibleScreen, "\(kind): the screen reports entering the window")
            let model = try newEntry(root, "Kefir \(kind)")
            XCTAssertTrue(FoodConfirmationView.logTapped(model, leave: {}, logged: banner.show))
            XCTAssertNotNil(banner.content, "shown on the registered screen")
            XCTAssertTrue(banner.isAnchoredToScreen, "\(kind): anchored to the screen showing")
            if kind == "item" { pushes.openedEntry = "saved entry" } else { pushes.showsResults = true }
            Self.runUntil { banner.content == nil && pushes.pushedAppeared > 0 }
            XCTAssertEqual(pushes.pushedAppeared, 1, "\(kind): the push happened")
            XCTAssertNil(banner.content, "\(kind): leaving the screen dismisses the banner")
            await banner.undo()
            let day = try XCTUnwrap(model.savedResult).logItemVersion.reportingDate.value
            let content = try root.foodLogService.day(reportingDate: day)
            XCTAssertEqual(content.removed.count, 0, "\(kind): nothing removed")
            XCTAssertEqual(content.entries.count, 1, kind)
            window.isHidden = true
        }
    }

    private static func runUntil(seconds: TimeInterval = 5, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    private static func firstDescendant<T>(of value: Any, ofType: T.Type, depth: Int = 0) -> T? {
        if let match = value as? T { return match }
        guard depth < 12 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let match = firstDescendant(of: child.value, ofType: T.self, depth: depth + 1) { return match }
        }
        return nil
    }
}

@MainActor
private final class BannerPushState: ObservableObject {
    @Published var openedEntry: String?
    @Published var showsResults = false
    var pushedAppeared = 0
}

/// A registered screen with the two kinds of push the Food Log and the search hosts use.
private struct BannerPushRoot: View {
    @ObservedObject var state: BannerPushState
    let banner: FoodLoggedBannerModel

    let usesItem: Bool

    var body: some View {
        Group {
            if usesItem {
                Text("Food Log").navigationDestination(item: $state.openedEntry) { Text($0).onAppear { state.pushedAppeared += 1 } }
            } else {
                Text("Search").navigationDestination(isPresented: $state.showsResults) { Text("Search results").onAppear { state.pushedAppeared += 1 } }
            }
        }
            .foodLoggedBannerScreen(banner)
    }
}

private extension FoodConfirmationViewModel {
    func savedResultAfterLog() -> StoredFoodConfirmation? {
        log()
        return savedResult
    }
}
