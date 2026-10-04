import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

@MainActor
final class GenericFoodProposalReviewerTests: XCTestCase {
    private let key = "synthetic-provider-key-123456789"
    private let url = URL(string: "https://publisher.example/tofu")!

    func testSelectedWrongMarketStopsBeforeCaptureAndPreservesEveryLead() async throws {
        for useSelector in [true, false] {
            let urls = [URL(string: "https://ie.fage/yoghurts/fage-total-0")!, URL(string: "https://publisher.co.uk/yoghurt")!]
            let ports = ReviewPorts(leadURLs: urls)
            let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports,
                sourceSelection: useSelector ? ports : nil)
            do { _ = try await service.review(foodTerms: "FAGE plain yoghurt UK", key: key); XCTFail("Expected market conflict") }
            catch let failure as GenericFoodProposalPartialFailure {
                guard case .sourceMarketConflict = failure.reason else { return XCTFail("Wrong failure reason") }
                XCTAssertEqual(failure.discovery?.leads.map(\.url), urls)
                XCTAssertNil(failure.attemptedSourceURL)
            }
            let calls = await ports.calls
            XCTAssertEqual(calls, useSelector ? ["discover", "chooseSource"] : ["discover"])
        }
    }

    func testSuppliedWrongMarketHasNoDiscoveryCaptureOrProviderCall() async throws {
        let ports = ReviewPorts()
        let service = reviewer(ports)
        do {
            _ = try await service.review(foodTerms: "UK yoghurt", sourceURL: URL(string: "https://ie.fage/yoghurt")!, key: key)
            XCTFail("Expected market conflict")
        } catch let failure as GenericFoodProposalPartialFailure {
            guard case .sourceMarketConflict = failure.reason else { return XCTFail("Wrong failure reason") }
            XCTAssertNil(failure.discovery); XCTAssertNil(failure.attemptedSourceURL)
        }
        let calls = await ports.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testRedirectedWrongMarketStopsBeforeExtractionAndRetainsAttemptedURL() async throws {
        let ports = ReviewPorts(capturedURL: URL(string: "https://ie.fage/yoghurt")!)
        let service = reviewer(ports)
        do {
            _ = try await service.review(foodTerms: "UK yoghurt", sourceURL: url, key: key)
            XCTFail("Expected redirected market conflict")
        } catch let failure as GenericFoodProposalPartialFailure {
            guard case .sourceMarketConflict = failure.reason else { return XCTFail("Wrong failure reason") }
            XCTAssertEqual(failure.attemptedSourceURL, url)
        }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["capture"])
    }

    func testSourceSelectionChoosesOnlyAnOfferedLeadBeforeCapture() async throws {
        let ports = ReviewPorts(sourceChoice: .selected(index: 1, reason: "Exact source"))
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
        let result = try await service.review(foodTerms: "tofu", key: key)
        XCTAssertEqual(result.attemptedSourceURL?.host, "other.example")
        XCTAssertEqual(result.documents.first?.url, "https://other.example/tofu")
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "chooseSource", "capture", "extract"])
    }

    func testSourceAbstentionInvalidIndexAndFailurePreserveLeadsWithoutCapture() async throws {
        for ports in [ReviewPorts(sourceChoice: .abstain(reason: "Wrong market")),
                      ReviewPorts(sourceChoice: .selected(index: 2, reason: "Invented choice")),
                      ReviewPorts(sourceChoice: .selected(index: -1, reason: "Invalid choice")),
                      ReviewPorts(sourceError: .quotaExceeded)] {
            let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
            do { _ = try await service.review(foodTerms: "tofu", key: key); XCTFail("Expected closed source choice") }
            catch let failure as GenericFoodProposalPartialFailure {
                XCTAssertEqual(failure.discovery?.leads.count, 2)
                XCTAssertNil(failure.attemptedSourceURL)
            }
            let calls = await ports.calls
            XCTAssertEqual(calls, ["discover", "chooseSource"])
        }
    }

    func testSuppliedURLSkipsSourceSelectionAndRejectedKeyRemainsDistinct() async throws {
        let ports = ReviewPorts(sourceError: .credentialRejected)
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
        do { _ = try await service.review(foodTerms: "tofu", key: key); XCTFail("Expected key rejection") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .credentialRejected) }
        let result = try await service.review(foodTerms: "tofu", sourceURL: url, key: key)
        XCTAssertNil(result.discovery)
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "chooseSource", "capture", "extract"])
    }

    func testDeadlineDuringSourceChoicePreventsCapture() async throws {
        let ports = ReviewPorts(suspendSourceChoice: true)
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports,
            sourceSelection: ports, timeout: .milliseconds(30))
        do { _ = try await service.review(foodTerms: "tofu", key: key); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .timedOut) }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "chooseSource"])
    }

    func testDiscoveryCaptureExtractionAndRankingEachRunOnce() async throws {
        let ports = ReviewPorts()
        let result = try await reviewer(ports).review(foodTerms: "  tofu  ", key: key)
        XCTAssertEqual(result.foodTerms, "tofu")
        XCTAssertEqual(result.discovery?.leads.count, 2)
        XCTAssertEqual(result.selection?.choice, "c1")
        XCTAssertFalse(result.rankingUnavailable)
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture", "extract", "select"])
    }

    func testSuppliedURLSkipsDiscoveryAndOptionalSelectorCanBeOmitted() async throws {
        let ports = ReviewPorts()
        let result = try await reviewer(ports, ranking: false).review(foodTerms: "tofu", sourceURL: url, key: key)
        XCTAssertNil(result.discovery); XCTAssertNil(result.selection)
        let calls = await ports.calls
        XCTAssertEqual(calls, ["capture", "extract"])
    }

    func testNoCandidateSkipsRankingRatherThanSelectingAnInventedCandidate() async throws {
        let ports = ReviewPorts(empty: true)
        let result = try await reviewer(ports).review(foodTerms: "tofu", key: key)
        XCTAssertTrue(result.validation.candidates.isEmpty)
        XCTAssertNil(result.selection); XCTAssertFalse(result.rankingUnavailable)
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture", "extract"])
    }

    func testCaptureFailureRetainsEveryDiscoveredLinkAndDoesNotRetry() async throws {
        let ports = ReviewPorts(captureError: .unsupportedContent)
        do { _ = try await reviewer(ports).review(foodTerms: "tofu", key: key); XCTFail("Expected failure") }
        catch let failure as GenericFoodProposalPartialFailure {
            XCTAssertEqual(failure.discovery?.leads.count, 2)
            guard case .acquisition(.unsupportedContent) = failure.reason else { return XCTFail("Wrong stage") }
        }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture"])
    }

    func testExtractionQuotaFailureRetainsLinksAndNeverCallsSelector() async throws {
        let ports = ReviewPorts(extractionError: .quotaExceeded)
        do { _ = try await reviewer(ports).review(foodTerms: "tofu", key: key); XCTFail("Expected failure") }
        catch let failure as GenericFoodProposalPartialFailure {
            XCTAssertEqual(failure.discovery?.leads.count, 2)
            guard case .provider(.quotaExceeded) = failure.reason else { return XCTFail("Wrong stage") }
        }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture", "extract"])
    }

    func testApplicabilityFailurePreservesInspectableProposalButBlocksConfirmation() async throws {
        let ports = ReviewPorts(selectionError: .serviceUnavailable)
        let result = try await reviewer(ports).review(foodTerms: "tofu", key: key)
        XCTAssertEqual(result.validation.candidates.filter(\.selectionEligible).count, 1)
        XCTAssertNil(result.selection); XCTAssertTrue(result.rankingUnavailable)
        XCTAssertEqual(result.suggestedChoice, "clarify")
        XCTAssertFalse(result.permitsConfirmation(of: try XCTUnwrap(result.validation.candidates.first)))
    }

    func testCredentialRejectionRemainsDistinctAtExtractionAndSelection() async throws {
        for ports in [ReviewPorts(extractionError: .credentialRejected), ReviewPorts(selectionError: .credentialRejected)] {
            do { _ = try await reviewer(ports).review(foodTerms: "tofu", key: key); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .credentialRejected) }
        }
    }

    func testConcurrentReviewIsRejectedAndCancellationPreventsLaterProviderCalls() async throws {
        let ports = ReviewPorts(suspendCapture: true)
        let service = reviewer(ports)
        let pending = Task { try await service.review(foodTerms: "tofu", key: key) }
        try await waitForCapture(ports)
        do { _ = try await service.review(foodTerms: "rice", key: key); XCTFail("Expected concurrency guard") }
        catch { XCTAssertEqual(error as? GenericFoodProposalReviewError, .alreadyRunning) }
        pending.cancel()
        do { _ = try await pending.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture"])
        // A cancelled attempt releases the concurrency guard for a later explicit tap.
        await ports.resumeCapture()
        _ = try await service.review(foodTerms: "tofu", key: key)
    }

    func testOverallDeadlineCancelsAcquisitionBeforeProviderCalls() async throws {
        let ports = ReviewPorts(suspendCapture: true)
        do {
            _ = try await reviewer(ports, timeout: .milliseconds(30)).review(foodTerms: "tofu", key: key)
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .timedOut) }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture"])
    }

    func testKeyEchoAndInvalidSourceAreRejectedBeforeAnyPortCall() async throws {
        let ports = ReviewPorts()
        let service = reviewer(ports)
        for (terms, source) in [(key, url), ("tofu", URL(string: "http://publisher.example/tofu")!)] {
            do { _ = try await service.review(foodTerms: terms, sourceURL: source, key: key); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .invalidQuery) }
        }
        let calls = await ports.calls
        XCTAssertTrue(calls.isEmpty)
    }

    private func reviewer(_ ports: ReviewPorts, ranking: Bool = true, timeout: Duration = .seconds(2)) -> GenericFoodProposalReviewer {
        GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports,
                                    selection: ranking ? ports : nil, timeout: timeout)
    }

    private func waitForCapture(_ ports: ReviewPorts) async throws {
        for _ in 0..<1000 {
            if await ports.calls.contains("capture") { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Capture did not begin")
    }
}

private actor ReviewPorts: FoodWebDiscovering, FoodDocumentCapturing, FoodProposalExtracting, FoodProposalSelecting, FoodSourceLeadSelecting {
    var calls: [String] = []
    let empty: Bool
    let captureError: FoodSourceAcquisitionError?
    let extractionError: FoodWebDiscoveryError?
    let selectionError: FoodWebDiscoveryError?
    var suspendCapture: Bool
    let sourceChoice: FoodSourceLeadDecision
    let sourceError: FoodWebDiscoveryError?
    let suspendSourceChoice: Bool
    let leadURLs: [URL]
    let capturedURL: URL?
    init(empty: Bool = false, captureError: FoodSourceAcquisitionError? = nil,
         extractionError: FoodWebDiscoveryError? = nil, selectionError: FoodWebDiscoveryError? = nil,
         suspendCapture: Bool = false, sourceChoice: FoodSourceLeadDecision = .selected(index: 0, reason: "Source"),
         sourceError: FoodWebDiscoveryError? = nil, suspendSourceChoice: Bool = false,
         leadURLs: [URL] = [URL(string: "https://publisher.example/tofu")!, URL(string: "https://other.example/tofu")!],
         capturedURL: URL? = nil) {
        self.empty = empty; self.captureError = captureError; self.extractionError = extractionError
        self.selectionError = selectionError; self.suspendCapture = suspendCapture
        self.sourceChoice = sourceChoice; self.sourceError = sourceError; self.suspendSourceChoice = suspendSourceChoice
        self.leadURLs = leadURLs; self.capturedURL = capturedURL
    }
    func chooseSource(foodTerms: String, leads: [FoodWebLead], key: String) async throws -> FoodSourceLeadDecision {
        calls.append("chooseSource")
        if suspendSourceChoice { try await Task.sleep(for: .seconds(30)) }
        if let sourceError { throw sourceError }
        return sourceChoice
    }
    func resumeCapture() { suspendCapture = false }
    func validate(key: String) async throws { XCTFail("Review must not add a validation request") }
    func discover(foodTerms: String, key: String) async throws -> FoodWebDiscoveryResult {
        calls.append("discover")
        return .init(leads: leadURLs.map { .init(title: "Tofu source", url: $0) }, searchSuggestionsHTML: nil)
    }
    func capture(_ url: URL) async throws -> CapturedFoodDocument {
        calls.append("capture")
        if suspendCapture { try await Task.sleep(for: .seconds(30)) }
        if let captureError { throw captureError }
        return try CapturedFoodDocument(id: "d1", url: (capturedURL ?? url).absoluteString, rawSha256: String(repeating: "a", count: 64),
            captureOrigin: "synthetic_fixture", retrievedAt: "2026-10-04T00:00:00Z",
            blocks: [.init(id: "b1", kind: "text", text: "Tofu Per 100 g Protein 6 g", locator: "line1")])
    }
    func extract(foodTerms: String, documents: [CapturedFoodDocument], key: String) async throws -> FoodProposalExtraction {
        calls.append("extract")
        if let extractionError { throw extractionError }
        if empty { return .init(version: FoodProposalExtraction.schemaVersion, candidates: [], preferredId: "none") }
        let reference: [[String: Any]] = [["block_id": "b1", "quote": "Tofu Per 100 g Protein 6 g"]]
        let nutrients: [[String: Any]] = FoodProposalNutrientKey.allCases.map { nutrient in
            let known = nutrient == .protein
            return ["key": nutrient.rawValue, "state": known ? "declared" : "unknown", "value": known ? "6" as Any : NSNull(),
                    "unit": known ? "g" as Any : NSNull(), "evidence": known ? reference : [],
                    "unknown_reason": known ? NSNull() : "not_observed" as Any]
        }
        let candidate: [String: Any] = ["id": "c1", "document_id": "d1", "name": "Tofu", "brand": NSNull(), "preparation": NSNull(),
            "identity_evidence": reference, "panel_evidence": reference,
            "basis": ["amount": "100", "unit": "g", "label": "Per 100 g", "evidence": reference],
            "nutrients": nutrients, "limitations": []]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FoodProposalExtraction.self, from: JSONSerialization.data(withJSONObject:
            ["version": FoodProposalExtraction.schemaVersion, "candidates": [candidate], "preferred_id": "c1"]))
    }
    func select(foodTerms: String, documents: [CapturedFoodDocument], validation: FoodProposalValidation, key: String) async throws -> FoodProposalSelection {
        calls.append("select")
        if let selectionError { throw selectionError }
        return try .init(choice: "c1", probabilities: ["c1": 0.8, "none": 0.1, "clarify": 0.1], rawConfidence: 0.8, validation: validation)
    }
}
