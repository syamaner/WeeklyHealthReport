import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerGRDB
@testable import WeeklyHealthReport
import FoodLedgerDomain
import FoodLedgerPresentation
import SwiftUI
import UIKit
import XCTest
import WebKit

@MainActor
final class FoodSearchQuantityNativeTests: XCTestCase {
    func testSelectedCandidateRendersEditableParsedQuantityWithoutAutomaticSave() async throws {
        let ids = NativeQuantityIDs()
        let searcher = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: ids),USDAGenericFoodSearch(ids: ids)],ids:ids)
        for (query,amount,unit) in [("200g Greek yoghurt 10% fat",200.0,QuantityUnit.grams),
            ("0.25kg rice",250.0,.grams),("200ml milk",200.0,.millilitres),("2 eggs",2.0,.count)] {
            let search = try GenericFoodSearchViewModel(searcher:searcher,locale:LedgerText("en_GB"))
            search.query=query;search.search()
            let input = try XCTUnwrap(search.confirmation(at:1),query)
            var saves=0
            let model=FoodConfirmationViewModel(state:FoodConfirmationState(input:input,queryQuantity:search.parsedQuery?.quantity)) { _ in
                saves += 1;throw CocoaError(.fileWriteUnknown)
            }
            let host=NativeHostingController(rootView:NavigationStack { FoodConfirmationView(model:model,leave:{}) })
            let scene = try testScene()
            let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
            let window=UIWindow(windowScene:scene);window.frame=CGRect(x:0,y:0,width:430,height:932);window.rootViewController=host
            window.makeKeyAndVisible()
            defer { window.isHidden=true; previousKeyWindow?.makeKey() }
            try await waitForHostAppearance(host, window: window)
            host.view.layoutIfNeeded()
            var field:UITextField?
            for _ in 0..<24 {
                try await Task.sleep(for:.milliseconds(100))
                host.view.layoutIfNeeded()
                field=descendants(host.view).compactMap { $0 as? UITextField }.first { $0.text == String(amount) }
                if field != nil { break }
                if let scroll=descendants(host.view).compactMap({ $0 as? UIScrollView }).first {
                    scroll.setContentOffset(CGPoint(x:0,y:min(scroll.contentOffset.y+400,max(0,scroll.contentSize.height-scroll.bounds.height))),animated:false)
                }
            }
            let diagnostics = descendants(host.view).compactMap { view -> String? in
                if let text = view as? UITextField { return "field: \(text.text ?? "nil") / \(text.accessibilityLabel ?? "nil")" }
                if let scroll = view as? UIScrollView { return "scroll: \(scroll.contentOffset) size \(scroll.contentSize)" }
                return nil
            }.joined(separator:"; ")
            let quantityField=try XCTUnwrap(field,"Quantity should render \(amount) for \(query). \(diagnostics)")
            XCTAssertEqual(model.state.quantity.unit,unit)
            quantityField.text=String(amount+5);quantityField.sendActions(for:.editingChanged)
            try await Task.sleep(for:.milliseconds(100))
            XCTAssertEqual(model.state.quantity.value,amount+5,query)
            XCTAssertEqual(model.state.quantity.unit,unit)
            XCTAssertEqual(saves,0);XCTAssertEqual(model.state.decision,.undecided)
        }
    }
    func testSavedEntrySessionMissingFailureAndRetry() throws {
        let id = try NativeQuantityIDs().makeID(LogItemTag.self)
        var attempts = 0
        let session = SavedFoodEntrySession(id: id) {
            attempts += 1
            if attempts == 1 { throw CocoaError(.fileReadUnknown) }
            return nil
        }
        guard case .loading = session.phase else { return XCTFail("Initial loading state") }
        session.load()
        guard case .failed = session.phase else { return XCTFail("Visible failure state") }
        session.load()
        guard case .missing = session.phase else { return XCTFail("Missing record is distinct from failure") }
        XCTAssertEqual(attempts, 2)
    }

    func testMissingAndFailedSavedEntriesRenderRecoveryAndDismiss() async throws {
        let scene = try testScene()
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let driver = SavedSheetDriver()
        let host = NativeHostingController(rootView: SavedSheetHarness(driver: driver))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932); window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKey() }
        for missing in [true, false] {
            try await waitForHostAppearance(host, window: window, driver: driver)
            driver.session = SavedFoodEntrySession(id: try NativeQuantityIDs().makeID(LogItemTag.self)) {
                if missing { return nil }
                throw CocoaError(.fileReadUnknown)
            }
            let title = missing ? "Saved entry unavailable" : "Could not open saved food"
            try await waitForPresentation(host, title: title, window: window, driver: driver)
            let presented = try XCTUnwrap(host.presentedViewController)
            XCTAssertTrue(nativeText(presented.view).contains(title))
            if missing {
                guard case .missing = driver.session?.phase else { return XCTFail("Expected missing state") }
            } else {
                guard case .failed = driver.session?.phase else { return XCTFail("Expected failure state") }
            }
            driver.session = nil
            try await waitForDismissal(host, window: window, driver: driver)
            XCTAssertNil(host.presentedViewController)
        }
    }

    func testSyntheticSavedGramAndVolumeEntriesPresentDismissAndReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await exerciseStoredSavedEntries(directory: directory)
    }

    private func exerciseStoredSavedEntries(directory: URL) async throws {
        let ids = NativeQuantityIDs()
        let store = try FoodLedgerGRDBStore(databaseURL: directory.appendingPathComponent("ledger.sqlite"),
                                           attachmentsRoot: directory.appendingPathComponent("attachments"))
        let clock = SystemLedgerClock()
        let ledger = FoodLedgerService(actorID: try ids.makeID(ActorTag.self), committer: store,
                                       clock: clock, encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let service = FoodConfirmationService(ledger: ledger, reader: store, clock: clock, ids: ids)
        let searcher = try CoFIDGenericFoodSearch(ids: ids)
        for query in ["200g whole milk", "200ml whole milk"] {
            let search = try GenericFoodSearchViewModel(searcher: searcher, locale: LedgerText("en_GB"))
            search.query = query; search.search()
            let input = try XCTUnwrap(search.confirmation(at: 0))
            var state = FoodConfirmationState(input: input, queryQuantity: search.parsedQuery?.quantity)
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let saved = try service.save(state, operationID: ids.makeID(OperationTag.self))
            let scene = try testScene()
            let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
            let driver = SavedSheetDriver()
            let host = NativeHostingController(rootView: SavedSheetHarness(driver: driver))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 430, height: 932); window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; previousKeyWindow?.makeKey() }
            for _ in 0..<2 {
                try await waitForHostAppearance(host, window: window, driver: driver)
                driver.session = SavedFoodEntrySession(id: saved.logItem.logItemID) {
                    guard let reopened = try service.reopen(logItemID: saved.logItem.logItemID) else { return nil }
                    XCTAssertEqual(reopened.quantity.value, 200)
                    XCTAssertEqual(reopened.quantity.unit, state.quantity.unit)
                    XCTAssertEqual(reopened.selectedCandidate.candidate.nutrients, state.selectedCandidate.candidate.nutrients)
                    return FoodConfirmationViewModel(state: reopened) { _ in throw CocoaError(.fileWriteUnknown) }
                }
                try await waitForPresentation(host, title: "Confirm food", window: window, driver: driver)
                let presented = try XCTUnwrap(host.presentedViewController, query)
                let labels = nativeText(presented.view)
                XCTAssertTrue(labels.contains("Confirm food"), "Native sheet must contain confirmation: \(labels)")
                guard case .loaded = driver.session?.phase else { return XCTFail("Saved record did not load") }
                driver.session = nil
                try await waitForDismissal(host, window: window, driver: driver)
                XCTAssertNil(host.presentedViewController)
            }
        }
    }

    func testGeminiSetupRendersSecureEntryAndDoesNotCallProvider() async throws {
        let provider = NativeWebDiscoverySpy()
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: NativeEmptyWebKeys())
        let host = NativeHostingController(rootView: NavigationStack { FoodWebDiscoveryView(model: model) })
        let scene = try testScene()
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await waitForHostAppearance(host, window: window)
        var field: UITextField?
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            host.view.layoutIfNeeded()
            field = descendants(host.view).compactMap { $0 as? UITextField }.first { $0.isSecureTextEntry }
            if field != nil { break }
            if let scroll = descendants(host.view).compactMap({ $0 as? UIScrollView }).first {
                scroll.setContentOffset(CGPoint(x: 0, y: min(scroll.contentOffset.y + 250,
                    max(0, scroll.contentSize.height - scroll.bounds.height))), animated: false)
            }
        }
        XCTAssertNotNil(field, "API key entry must be a native secure field")
        XCTAssertFalse(model.canSearch)
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
    }

    func testGeminiSuggestionsRenderWithoutScriptsOrPersistentStorage() async throws {
        let html = "<div id='suggestions'>Synthetic Google suggestions</div><script>document.body.dataset.executed='yes'</script>"
        let host = NativeHostingController(rootView: FoodWebSearchSuggestions(html: html))
        let scene = try testScene()
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 600)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await waitForHostAppearance(host, window: window)
        let webView = try XCTUnwrap(descendants(host.view).compactMap { $0 as? WKWebView }.first)
        XCTAssertFalse(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        var text = ""
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            text = (try? await webView.evaluateJavaScript("document.body.innerText")) as? String ?? ""
            if text.contains("Synthetic Google suggestions") { break }
        }
        XCTAssertTrue(text.contains("Synthetic Google suggestions"))
        let ran = try await webView.evaluateJavaScript("document.body.dataset.executed || 'no'") as? String
        XCTAssertEqual(ran, "no")
    }

    private func testScene() throws -> UIWindowScene {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return try XCTUnwrap(scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)
    }

    private func waitForHostAppearance<Content: View>(
        _ host: NativeHostingController<Content>, window: UIWindow, driver: SavedSheetDriver? = nil
    ) async throws {
        try await waitForNativeState("Host should appear in its owned active window before presentation",
            diagnostics: { self.nativeSnapshot(host, window: window, driver: driver) }) {
            host.view.layoutIfNeeded()
            return host.hasAppeared && host.view.window === window && !window.isHidden && window.isKeyWindow
                && window.windowScene?.activationState == .foregroundActive
                && !host.isBeingPresented && !host.isBeingDismissed && host.presentedViewController == nil
        }
    }

    private func waitForPresentation(_ host: UIViewController, title: String,
                                     window: UIWindow, driver: SavedSheetDriver) async throws {
        try await waitForNativeState("Sheet should render \(title)",
            diagnostics: { self.nativeSnapshot(host, window: window, driver: driver) }) {
            host.view.layoutIfNeeded()
            guard let presented = host.presentedViewController,
                  !presented.isBeingPresented, !presented.isBeingDismissed else { return false }
            presented.view.layoutIfNeeded()
            return self.nativeText(presented.view).contains(title)
        }
    }

    private func waitForDismissal(_ host: UIViewController,
                                  window: UIWindow, driver: SavedSheetDriver) async throws {
        try await waitForNativeState("Sheet should finish dismissal before reopening",
            diagnostics: { self.nativeSnapshot(host, window: window, driver: driver) }) {
            host.presentedViewController == nil
        }
    }

    private func waitForNativeState(_ message: String, diagnostics: () -> String,
                                    condition: () -> Bool) async throws {
        // Let the main actor process UIKit transitions; slow hosted simulators need
        // readiness checks rather than an assumed animation duration.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        while !condition() && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let ready = condition()
        XCTAssertTrue(ready, ready ? message : "\(message). Timeout snapshot: \(diagnostics())")
    }

    private func nativeSnapshot(_ host: UIViewController, window: UIWindow,
                                driver: SavedSheetDriver?) -> String {
        let phase: String
        switch driver?.session?.phase {
        case .none: phase = "no session"
        case .some(.loading): phase = "loading"
        case .some(.loaded): phase = "loaded"
        case .some(.missing): phase = "missing"
        case .some(.failed): phase = "failed"
        }
        let presented = host.presentedViewController
        let hostTitles = host.isViewLoaded ? nativeText(host.view) : []
        let sheetTitles = presented?.isViewLoaded == true ? nativeText(presented!.view) : []
        return "phase=\(phase); hostTitles=\(hostTitles); sheetTitles=\(sheetTitles); "
            + "hostPresenting=\(host.isBeingPresented); hostDismissing=\(host.isBeingDismissed); "
            + "sheetPresenting=\(presented?.isBeingPresented.description ?? "nil"); "
            + "sheetDismissing=\(presented?.isBeingDismissed.description ?? "nil"); "
            + "ownedWindow=\(host.isViewLoaded && host.view.window === window); "
            + "windowHidden=\(window.isHidden); windowKey=\(window.isKeyWindow); "
            + "sceneState=\(window.windowScene?.activationState.rawValue.description ?? "nil")"
    }

    private func nativeText(_ view: UIView) -> [String] {
        descendants(view).compactMap { ($0 as? UILabel)?.text }
    }
    private func descendants(_ view:UIView)->[UIView] { [view]+view.subviews.flatMap(descendants) }
}
private final class NativeQuantityIDs:LedgerIDGenerating,@unchecked Sendable {
    private var value=1
    func makeID<Tag>(_ tag:Tag.Type)throws->LedgerID<Tag> {
        defer { value += 1 };return try LedgerID(String(format:"00000000-0000-0000-0000-%012x",value))
    }
}

@MainActor
private final class SavedSheetDriver: ObservableObject {
    @Published var session: SavedFoodEntrySession?
}
private struct SavedSheetHarness: View {
    @ObservedObject var driver: SavedSheetDriver
    var body: some View {
        Text("Synthetic food log")
            .sheet(item: $driver.session) { session in
                SavedFoodEntrySheet(session: session) { driver.session = nil }
            }
    }
}

@MainActor
private final class NativeHostingController<Content: View>: UIHostingController<Content> {
    private(set) var hasAppeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
}

private actor NativeWebDiscoverySpy: FoodWebDiscovering {
    private(set) var calls = 0
    func validate(key: String) async throws { calls += 1 }
    func discover(foodTerms: String, key: String) async throws -> FoodWebDiscoveryResult {
        calls += 1
        return FoodWebDiscoveryResult(leads: [], searchSuggestionsHTML: nil)
    }
}
private struct NativeEmptyWebKeys: FoodWebKeyStoring {
    func load() throws -> String? { nil }
    func save(_ key: String) throws {}
    func delete() throws {}
}
