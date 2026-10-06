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
import Vision

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
            try await waitForRenderHost(host, window: window)
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
    func testNutritionFirstScreenHasReferenceValuesWithoutDefaultIntakeAndHidesSourceIDs() async throws {
        let ids = NativeQuantityIDs()
        let searcher = try CoFIDGenericFoodSearch(ids: ids)
        let search = try GenericFoodSearchViewModel(searcher: searcher, locale: LedgerText("en_GB"))
        search.query = "Greek yoghurt 10% fat"; search.search()
        let input = try XCTUnwrap(search.confirmation(at: 0))
        for (name, dark, size) in [("light", false, DynamicTypeSize.large), ("dark", true, .large), ("large-text", false, .accessibility3)] {
            let model = FoodConfirmationViewModel(state: FoodConfirmationState(input: input, prefillSourceQuantity: false), searchInterpretation: search.interpretation) { _ in
                XCTFail("Rendering must not save"); throw CocoaError(.fileWriteUnknown)
            }
            let host = NativeHostingController(rootView: NavigationStack {
                FoodConfirmationView(model: model, leave: {}).environment(\.dynamicTypeSize, size)
            })
            let scene = try testScene()
            let previous = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.rootViewController = host; window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            try await waitForHostAppearance(host, window: window)
            try await Task.sleep(for: .milliseconds(250))
            host.view.layoutIfNeeded()
            XCTAssertNil(model.state.quantity.value)
            XCTAssertFalse(model.nutritionReview.isConsumed)
            XCTAssertEqual(model.nutritionReview.mainRows.count, 4)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let visible = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            XCTAssertTrue(visible.contains("Nutrition"), visible)
            if size == .large {
                for label in ["Energy", "Protein", "Carbohydrate", "Fat"] { XCTAssertTrue(visible.contains(label), visible) }
            }
            XCTAssertFalse(visible.contains(input.candidates[0].candidate.recordID.value), "Identifiers belong inside source details")
            let attachment = XCTAttachment(image: image)
            attachment.name = "Nutrition first \(name)"; attachment.lifetime = .keepAlways
            add(attachment)
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("whr-food-input-\(name).png")
            try image.pngData()?.write(to: url)
            print("FOOD_INPUT_SCREENSHOT \(url.path)")
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
        let service = FoodConfirmationService(ledger: ledger, reader: store, clock: clock, ids: ids, digester: SHA256Digester())
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

    func testEmptyOnlineSearchRendersSourceLinksOrRetryBeforeAnyScrolling() async throws {
        for unsupported in [false, true] {
            let local = try CoFIDGenericFoodSearch(ids: NativeQuantityIDs())
            let request = try GenericFoodSearchRequest(text: LedgerText("synthetic example food"),
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: LedgerText("en_GB"))
            guard case let .noResult(route) = try local.search(request) else { return XCTFail() }
            let discovery = FoodWebDiscoveryResult(leads: [.init(title: "Synthetic food source",
                url: URL(string: "https://source.example.com/food")!)], searchSuggestionsHTML: nil)
            let remote = NativeSearchRecoverySource(outcome: unsupported ? .noResult(GenericFoodNoResultRoute(
                evidence: route.evidence, sourceDiscovery: discovery, sourceReviewFailure: .unsupportedSource)) : nil)
            let model = try GenericFoodSearchViewModel(searcher: local, locale: LedgerText("en_GB"),
                gemini: remote, services: .init(onlineDatabase: .disabled, gemini: .ready))
            model.query = "synthetic example food"; model.search()
            for _ in 0..<30 where model.activeEnrichmentStage != nil { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertNil(model.activeEnrichmentStage)
            let host = NativeHostingController(rootView: NavigationStack { GenericFoodSearchView(model: model) { _ in XCTFail("No selection") } })
            let scene = try testScene()
            let previous = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host; window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            try await waitForRenderHost(host, window: window)
            try await Task.sleep(for: .milliseconds(250))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let ocr = VNRecognizeTextRequest()
            ocr.recognitionLevel = .accurate; ocr.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([ocr])
            let visible = (ocr.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            XCTAssertTrue(visible.contains(unsupported ? "Web sources" : "Search again"), visible)
            XCTAssertTrue(visible.contains(unsupported ? "not supported" : "timed out"), visible)
            XCTAssertFalse(visible.contains("Try a different food name"), visible)
            let attachment = XCTAttachment(image: image)
            attachment.name = unsupported ? "Unsupported source recovery" : "Timeout recovery"
            attachment.lifetime = .keepAlways; add(attachment)
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

    func testOpenRouterReviewRendersWithoutImplicitProviderCalls() async throws {
        for (name, size) in [("standard", DynamicTypeSize.large), ("large-text", .accessibility3)] {
            let provider = NativeWebDiscoverySpy()
            let credentials = FoodWebDiscoveryViewModel(provider: provider, keys: NativeEmptyWebKeys(),
                providerName: "OpenRouter", operatorName: "OpenRouter", keyManagementName: "OpenRouter")
            let reviewer = NativeProposalReviewSpy()
            let model = GenericFoodProposalReviewViewModel(reviewer: reviewer, credentials: credentials,
                confirmation: ReviewedFoodProposalConfirmation(ids: NativeQuantityIDs(), clock: SystemLedgerClock(),
                    encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()), locale: try LedgerText("en_GB"))
            let host = NativeHostingController(rootView: NavigationStack {
                GenericFoodProposalReviewView(model: model, credentials: credentials) { _ in XCTFail("Rendering cannot confirm") }
                    .environment(\.dynamicTypeSize, size)
            })
            let scene = try testScene(); let previous = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host; window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            try await waitForHostAppearance(host, window: window)
            model.foodTerms = "Synthetic tofu pudding"
            try await Task.sleep(for: .milliseconds(250))
            host.view.layoutIfNeeded()
            XCTAssertFalse(credentials.keyIsUsable)
            XCTAssertNil(model.result); XCTAssertFalse(model.isSearching)
            let providerCalls = await provider.calls; let reviewCalls = await reviewer.calls
            XCTAssertEqual(providerCalls, 0); XCTAssertEqual(reviewCalls, 0)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let visible = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let normalized = visible.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            XCTAssertTrue(normalized.contains("Find nutrition to review"), visible)
            if size == .large { XCTAssertTrue(visible.contains("Web nutrition review"), visible) }
            XCTAssertFalse(visible.contains("Gemini"), visible)
            let attachment = XCTAttachment(image: image); attachment.name = "OpenRouter review \(name)"
            attachment.lifetime = .keepAlways; add(attachment)
            let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("whr-openrouter-review-\(name).png")
            try image.pngData()?.write(to: path)
            print("OPENROUTER_REVIEW_SCREENSHOT \(path.path)")
        }
    }

    func testReviewedProposalShowsModelAbstentionAndBlocksConfirmation() async throws {
        let provider = NativeWebDiscoverySpy()
        let credentials = FoodWebDiscoveryViewModel(provider: provider, keys: NativeSyntheticWebKeys(), providerName: "OpenRouter")
        await credentials.revalidateSavedKey()
        XCTAssertTrue(credentials.keyIsUsable)
        let source = try GenericFoodDocumentProjector.project(Data("Synthetic tofu Per 100g Protein 6g".utf8),
            url: URL(string: "https://example.com/synthetic-tofu")!, mediaType: "text/plain",
            retrievedAt: Date(timeIntervalSince1970: 0), origin: "synthetic_fixture")
        let reference: [[String: Any]] = [["block_id": "b1", "quote": source.blocks[0].text]]
        let nutrients: [[String: Any]] = FoodProposalNutrientKey.allCases.map { key in
            ["key": key.rawValue, "state": key == .protein ? "declared" : "unknown",
             "value": key == .protein ? "6" as Any : NSNull(), "unit": key == .protein ? "g" as Any : NSNull(),
             "evidence": key == .protein ? reference : [], "unknown_reason": key == .protein ? NSNull() : "not_observed" as Any]
        }
        let payload: [String: Any] = ["version": FoodProposalExtraction.schemaVersion, "preferred_id": "none", "candidates": [[
            "id": "c1", "document_id": source.id, "name": "Synthetic tofu", "brand": NSNull(), "preparation": NSNull(),
            "identity_evidence": reference, "panel_evidence": reference,
            "basis": ["amount": "100", "unit": "g", "label": "Per 100g", "evidence": reference],
            "nutrients": nutrients, "limitations": ["Synthetic fixture: source applicability is declined."]]]]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let extraction = try decoder.decode(FoodProposalExtraction.self, from: JSONSerialization.data(withJSONObject: payload))
        let validation = try FoodProposalBinding.validate(extraction, documents: [source])
        let review = GenericFoodProposalReview(foodTerms: "Synthetic tofu", discovery: nil, documents: [source],
            validation: validation, selection: nil, attemptedSourceURL: URL(string: source.url))
        let model = GenericFoodProposalReviewViewModel(reviewer: NativeCompletedProposalReview(result: review), credentials: credentials,
            confirmation: ReviewedFoodProposalConfirmation(ids: NativeQuantityIDs(), clock: SystemLedgerClock(),
                encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()), locale: try LedgerText("en_GB"))
        model.foodTerms = review.foodTerms
        await model.search()
        let proposal = try XCTUnwrap(model.result?.validation.candidates.first)
        XCTAssertTrue(proposal.selectionEligible)
        XCTAssertThrowsError(try model.prepare(proposal, querySnapshot: review.foodTerms, scope: .representativeEstimate,
            acknowledgement: .init(identityAndScopeReviewed: true, basisReviewed: true, nutrientsAndUnknownsReviewed: true)))
        let host = NativeHostingController(rootView: NavigationStack {
            GenericFoodProposalReviewView(model: model, credentials: credentials) { _ in XCTFail("No confirmation") }
        })
        let scene = try testScene(); let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await waitForHostAppearance(host, window: window)
        var found = false
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(150)); host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let visible = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            if visible.contains("No suitable candidate suggested") {
                found = true
                let attachment = XCTAttachment(image: image); attachment.name = "Declined proposal remains inspectable"
                attachment.lifetime = .keepAlways; add(attachment)
                let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("whr-openrouter-declined-proposal.png")
                try image.pngData()?.write(to: path)
                print("OPENROUTER_DECLINED_SCREENSHOT \(path.path)")
                break
            }
            if let scroll = descendants(host.view).compactMap({ $0 as? UIScrollView }).first {
                scroll.setContentOffset(CGPoint(x: 0, y: min(scroll.contentOffset.y + 180,
                    max(0, scroll.contentSize.height - scroll.bounds.height))), animated: false)
            }
        }
        XCTAssertTrue(found, "Native result must display the extractor's abstention even without Jev")
        let calls = await provider.calls
        XCTAssertEqual(calls, 1, "Only synthetic key validation; no live requests")
    }

    /// Opt-in native interaction harness. A human or UI automation operates the
    /// actual review/confirmation controls; only synthetic data enters a temporary ledger.
    func testInteractiveReviewedPartialProposalSavesOnlyAfterExplicitReview() async throws {
        guard ProcessInfo.processInfo.environment["NUTRITION_NATIVE_REVIEW_INTERACTION"] == "1" else {
            throw XCTSkip("Explicit native interaction session only; no live provider or personal ledger")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("review-interaction-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Fixed whole-second clock keeps exact persistence equality deterministic.
        let ids = NativeQuantityIDs(); let clock = NativeReviewClock()
        let store = try FoodLedgerGRDBStore(databaseURL: directory.appendingPathComponent("ledger.sqlite"),
            attachmentsRoot: directory.appendingPathComponent("attachments"))
        let ledger = FoodLedgerService(actorID: try ids.makeID(ActorTag.self), committer: store, clock: clock,
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let service = FoodConfirmationService(ledger: ledger, reader: store, clock: clock, ids: ids, digester: SHA256Digester())
        let provider = NativeWebDiscoverySpy()
        let credentials = FoodWebDiscoveryViewModel(provider: provider, keys: NativeSyntheticWebKeys(), providerName: "OpenRouter")
        await credentials.revalidateSavedKey()
        let source = try GenericFoodDocumentProjector.project(Data("Synthetic tofu Per 100g Protein 6g".utf8),
            url: URL(string: "https://example.com/synthetic-tofu")!, mediaType: "text/plain",
            retrievedAt: Date(timeIntervalSince1970: 0), origin: "synthetic_fixture")
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
            "nutrients": nutrients, "limitations": ["Synthetic source. Only protein is declared; all other target nutrients are unknown."]]]]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let extraction = try decoder.decode(FoodProposalExtraction.self, from: JSONSerialization.data(withJSONObject: payload))
        let review = GenericFoodProposalReview(foodTerms: "Synthetic tofu", discovery: nil, documents: [source],
            validation: try FoodProposalBinding.validate(extraction, documents: [source]),
            selection: try FoodProposalSelection(unscoredChoice: "c1", validation: FoodProposalBinding.validate(extraction, documents: [source])),
            attemptedSourceURL: URL(string: source.url))
        let model = GenericFoodProposalReviewViewModel(reviewer: NativeCompletedProposalReview(result: review), credentials: credentials,
            confirmation: ReviewedFoodProposalConfirmation(ids: ids, clock: clock,
                encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()), locale: try LedgerText("en_GB"))
        model.foodTerms = review.foodTerms; await model.search()
        let driver = NativeReviewedSaveDriver { input in
            let state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
            XCTAssertNil(state.quantity.value, "Review must not invent an amount eaten")
            XCTAssertEqual(state.decision, .undecided)
            XCTAssertEqual(try store.counts().operations, 0)
            let operationID = try ids.makeID(OperationTag.self)
            return FoodConfirmationViewModel(state: state) { state in
                try service.save(state, operationID: operationID)
            }
        }
        let host = NativeHostingController(rootView: NativeReviewedSaveHarness(model: model, credentials: credentials, driver: driver))
        let scene = try testScene(); let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await waitForHostAppearance(host, window: window)
        print("NATIVE_REVIEW_INTERACTION_READY synthetic-only temporary ledger")
        let deadline = ContinuousClock.now.advanced(by: .seconds(300))
        while driver.confirmation?.savedResult == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }
        let confirmation = try XCTUnwrap(driver.confirmation, "Operate the proposal's native review controls")
        let saved = try XCTUnwrap(confirmation.savedResult, "Complete the native confirmation with 50 g and save")
        XCTAssertEqual(try store.counts().operations, 1)
        XCTAssertEqual(saved.logItemVersion.edibleQuantity, try PositiveQuantity(value: 50, unit: .grams))
        let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
        XCTAssertTrue(reopened.isGenericEstimate)
        XCTAssertEqual(reopened.input.evidence, confirmation.state.input.evidence)
        XCTAssertEqual(reopened.selectedCandidate.candidate.nutrients, confirmation.state.selectedCandidate.candidate.nutrients)
        let totals = FoodIntakeSummary(contributions: [.init(quantity: try reopened.calculatedEdibleQuantity(),
            basis: reopened.selectedCandidate.candidate.identity.servingBasis, nutrients: reopened.selectedCandidate.candidate.nutrients)])
        XCTAssertEqual(totals.totals.first { $0.key == .protein }?.knownAmount, 3)
        XCTAssertNil(totals.totals.first { $0.key == .energyConsumed }?.knownAmount)
        XCTAssertNil(totals.totals.first { $0.key == .sodium }?.knownAmount)
        XCTAssertTrue(totals.totals.first { $0.key == .protein }?.includesEstimates == true)
        let providerCalls = await provider.calls
        XCTAssertEqual(providerCalls, 1, "Only synthetic credential validation")
        try await Task.sleep(for: .milliseconds(300)); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "Native reviewed partial proposal saved"
        attachment.lifetime = .keepAlways; add(attachment)
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("whr-reviewed-partial-native-saved.png")
        try image.pngData()?.write(to: path)
        print("NATIVE_REVIEW_SAVED_SCREENSHOT \(path.path)")
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
        try await waitForRenderHost(host, window: window)
        let webView = try XCTUnwrap(descendants(host.view).compactMap { $0 as? WKWebView }.first)
        XCTAssertFalse(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        var text = ""
        var readyState = "unknown"
        var lastJavaScriptError: String?
        repeat {
            do {
                readyState = try await webView.evaluateJavaScript("document.readyState") as? String ?? "unknown"
                text = try await webView.evaluateJavaScript("document.body.innerText") as? String ?? ""
            } catch {
                lastJavaScriptError = String(describing: error)
            }
            if readyState == "complete" && text.contains("Synthetic Google suggestions") { break }
            try await Task.sleep(for: .milliseconds(100))
        } while clock.now < deadline
        XCTAssertEqual(readyState, "complete", "loading=\(webView.isLoading); URL=\(String(describing: webView.url)); lastJSerror=\(lastJavaScriptError ?? "none")")
        XCTAssertTrue(text.contains("Synthetic Google suggestions"), "DOM=\(text); loading=\(webView.isLoading); URL=\(String(describing: webView.url)); lastJSerror=\(lastJavaScriptError ?? "none")")
        let ran = try await webView.evaluateJavaScript("document.body.dataset.executed || 'no'") as? String
        XCTAssertEqual(ran, "no")
    }

    private func testScene() throws -> UIWindowScene {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return try XCTUnwrap(scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)
    }

    /// Static rendering asserts the real content below; UIKit's viewDidAppear callback
    /// is a separate requirement for tests that present or reopen a controller.
    private func waitForRenderHost<Content: View>(_ host: NativeHostingController<Content>, window: UIWindow) async throws {
        try await waitForNativeState("Render host should own a visible, laid-out active window",
            diagnostics: { "\(self.nativeSnapshot(host, window: window, driver: nil)); hostAppeared=\(host.hasAppeared); bounds=\(host.view.bounds)" }) {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            return window.rootViewController === host && host.view.window === window
                && !window.isHidden && window.isKeyWindow && !host.view.isHidden
                && !host.view.bounds.isEmpty && window.windowScene?.activationState == .foregroundActive
                && !host.isBeingPresented && !host.isBeingDismissed && host.presentedViewController == nil
        }
    }

    private func waitForHostAppearance<Content: View>(
        _ host: NativeHostingController<Content>, window: UIWindow, driver: SavedSheetDriver? = nil
    ) async throws {
        try await waitForNativeState("Host should appear in its owned active window before presentation",
            diagnostics: { "\(self.nativeSnapshot(host, window: window, driver: driver)); hostAppeared=\(host.hasAppeared)" }) {
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
private actor NativeProposalReviewSpy: GenericFoodProposalReviewing {
    private(set) var calls = 0
    func review(foodTerms: String, sourceURL: URL?, key: String) async throws -> GenericFoodProposalReview {
        calls += 1
        throw GenericFoodProposalReviewError.noSourceLinks
    }
}
private struct NativeEmptyWebKeys: FoodWebKeyStoring {
    func load() throws -> String? { nil }
    func save(_ key: String) throws {}
    func delete() throws {}
}

private struct NativeSyntheticWebKeys: FoodWebKeyStoring {
    func load() throws -> String? { "synthetic-native-review-key-not-real" }
    func save(_ key: String) throws {}
    func delete() throws {}
}

private struct NativeCompletedProposalReview: GenericFoodProposalReviewing {
    let result: GenericFoodProposalReview
    func review(foodTerms: String, sourceURL: URL?, key: String) async throws -> GenericFoodProposalReview { result }
}

private struct NativeSearchRecoverySource: FoodSearchEnriching {
    let outcome: GenericFoodSearchOutcome?
    func enrich(_ query: FoodSearchRemoteQuery) async throws -> GenericFoodSearchOutcome {
        guard let outcome else { throw FoodSearchEnrichmentError.timedOut }
        return outcome
    }
}


@MainActor
private final class NativeReviewedSaveDriver: ObservableObject {
    @Published var confirmation: FoodConfirmationViewModel?
    @Published var showsConfirmation = false
    private let make: (PopulatedFoodConfirmation) throws -> FoodConfirmationViewModel
    init(make: @escaping (PopulatedFoodConfirmation) throws -> FoodConfirmationViewModel) { self.make = make }
    func open(_ input: PopulatedFoodConfirmation) {
        do { confirmation = try make(input); showsConfirmation = true }
        catch { XCTFail("Synthetic confirmation could not be prepared: \(error)") }
    }
}

private struct NativeReviewedSaveHarness: View {
    let model: GenericFoodProposalReviewViewModel
    let credentials: FoodWebDiscoveryViewModel
    @ObservedObject var driver: NativeReviewedSaveDriver
    var body: some View {
        NavigationStack {
            GenericFoodProposalReviewView(model: model, credentials: credentials) { driver.open($0) }
                .navigationDestination(isPresented: $driver.showsConfirmation) {
                    if let confirmation = driver.confirmation {
                        FoodConfirmationView(model: confirmation) { driver.showsConfirmation = false }
                    }
                }
        }
    }
}

private struct NativeReviewClock: LedgerClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_791_122_400) }
}
