import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import XCTest

@MainActor
final class GenericFoodProposalReviewPresentationTests: XCTestCase {
    func testAbstentionOrClarificationCannotPrepareALiterallyBoundCandidate() async throws {
        for choice in ["none", "clarify"] {
            for selector in [false, true] {
                let reviewer = ControlledProposalReview(); let model = make(reviewer)
                model.foodTerms = "milk"
                let task = Task { await model.search() }; await reviewer.waitForRequest()
                let result = try ProposalPresentationFixture.result(preferred: selector ? "c1" : choice, selection: selector ? choice : nil)
                await reviewer.complete(result); await task.value
                let proposal = try XCTUnwrap(model.result?.validation.candidates.first)
                XCTAssertTrue(proposal.selectionEligible, "This test requires an otherwise bound proposal")
                XCTAssertEqual(result.suggestedChoice, choice)
                XCTAssertFalse(result.permitsConfirmation(of: proposal))
                XCTAssertThrowsError(try model.prepare(proposal, querySnapshot: "milk", scope: .representativeEstimate,
                    acknowledgement: .init(identityAndScopeReviewed: true, basisReviewed: true, nutrientsAndUnknownsReviewed: true)))
            }
        }
    }

    func testMissingOrFailedApplicabilityCannotFallBackToExtractorPreference() throws {
        for failed in [false, true] {
            let original = try ProposalPresentationFixture.result(selection: nil)
            let review = GenericFoodProposalReview(foodTerms: original.foodTerms, discovery: nil, documents: original.documents,
                validation: original.validation, selection: nil, rankingUnavailable: failed)
            XCTAssertEqual(review.suggestedChoice, "clarify")
            XCTAssertFalse(review.permitsConfirmation(of: try XCTUnwrap(review.validation.candidates.first)))
        }
    }

    func testExplicitBasisMismatchOverridesEvenSuccessfulApplicability() throws {
        let original = try ProposalPresentationFixture.result()
        for query in ["milk per 100ml", "milk per 50g", "牛奶 每100毫升"] {
            let review = GenericFoodProposalReview(foodTerms: query, discovery: nil, documents: original.documents,
                validation: original.validation, selection: original.selection)
            XCTAssertEqual(review.suggestedChoice, "clarify")
            XCTAssertFalse(review.permitsConfirmation(of: try XCTUnwrap(review.validation.candidates.first)))
        }
        let basis = try XCTUnwrap(original.validation.candidates.first).candidate.basis
        XCTAssertFalse(FoodProposalQueryPolicy.hasBasisConflict(query: "milk per 100 grams", basis: basis))
        XCTAssertFalse(FoodProposalQueryPolicy.hasBasisConflict(query: "200g milk", basis: basis), "Consumed quantity is not a source denominator")
    }

    func testTypingDoesNotRequestReviewAndExplicitSearchPublishes() async throws {
        let reviewer = ControlledProposalReview()
        let model = make(reviewer)
        model.foodTerms = "milk"
        let initial = await reviewer.callCount; XCTAssertEqual(initial, 0)
        let task = Task { await model.search() }
        await reviewer.waitForRequest()
        XCTAssertTrue(model.isSearching)
        await reviewer.complete(try ProposalPresentationFixture.result())
        await task.value
        XCTAssertEqual(model.result?.validation.candidates.first?.candidate.name, "Milk")
        XCTAssertFalse(model.isSearching)
        let count = await reviewer.callCount; XCTAssertEqual(count, 1)
    }

    func testChangedQueryDiscardsLateSuccess() async throws {
        let reviewer = ControlledProposalReview(); let model = make(reviewer)
        model.foodTerms = "milk"
        let task = Task { await model.search() }; await reviewer.waitForRequest()
        model.foodTerms = "yoghurt"
        await reviewer.complete(try ProposalPresentationFixture.result())
        await task.value
        XCTAssertNil(model.result); XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.message)
    }

    func testChangedSourceDiscardsLateSuccessAndClearsReview() async throws {
        let reviewer = ControlledProposalReview(); let model = make(reviewer)
        model.foodTerms = "milk"
        let task = Task { await model.search() }; await reviewer.waitForRequest()
        model.sourceAddress = "https://different.example/food"
        await reviewer.complete(try ProposalPresentationFixture.result()); await task.value
        XCTAssertNil(model.result)
    }

    func testCredentialReplacementDuringRequestCannotPublishOrDeleteReplacement() async throws {
        let keys = ProposalCredentials(); let reviewer = ControlledProposalReview(); let model = make(reviewer, keys: keys)
        model.foodTerms = "milk"
        let task = Task { await model.search() }; await reviewer.waitForRequest()
        keys.version += 1
        await reviewer.complete(try ProposalPresentationFixture.result()); await task.value
        XCTAssertNil(model.result); XCTAssertFalse(model.isSearching)
        XCTAssertTrue(model.message?.contains("key changed") == true)
        XCTAssertEqual(keys.rejections, 0)
    }

    func testInvalidKeyFailureInvalidatesOnlyCurrentGrant() async {
        let keys = ProposalCredentials(); let reviewer = ControlledProposalReview(); let model = make(reviewer, keys: keys)
        model.foodTerms = "milk"
        let task = Task { await model.search() }; await reviewer.waitForRequest()
        await reviewer.fail(FoodWebDiscoveryError.credentialRejected); await task.value
        XCTAssertEqual(keys.rejections, 1); XCTAssertNil(model.result)
        XCTAssertTrue(model.message?.contains("rejected this key") == true)
    }

    func testCredentialChangeAfterResultsPreventsDetailScreenConfirmation() async throws {
        for replacement in [true, false] {
            let keys = ProposalCredentials(); let reviewer = ControlledProposalReview(); let model = make(reviewer, keys: keys)
            model.foodTerms = "milk"
            let task = Task { await model.search() }; await reviewer.waitForRequest()
            await reviewer.complete(try ProposalPresentationFixture.result()); await task.value
            let proposal = try XCTUnwrap(model.result?.validation.candidates.first)
            // Navigating into detail preserves a completed result and its grant.
            model.cancel(clearResult: false)
            if replacement { keys.version += 1 } else { keys.usable = false }
            XCTAssertThrowsError(try model.prepare(proposal, querySnapshot: "milk", scope: .representativeEstimate,
                acknowledgement: .init(identityAndScopeReviewed: true, basisReviewed: true, nutrientsAndUnknownsReviewed: true)))
            XCTAssertNil(model.result)
            XCTAssertEqual(keys.rejections, 0)
            let count = await reviewer.callCount; XCTAssertEqual(count, 1)
        }
    }

    func test400RequestFailureLeavesValidatedCredentialAvailable() async {
        let keys = ProposalCredentials(); let reviewer = ControlledProposalReview(); let model = make(reviewer, keys: keys)
        model.foodTerms = "milk"
        let task = Task { await model.search() }; await reviewer.waitForRequest()
        await reviewer.fail(FoodWebDiscoveryError.requestRejected); await task.value
        XCTAssertEqual(keys.rejections, 0); XCTAssertTrue(keys.usable)
        XCTAssertTrue(model.message?.contains("not been marked invalid") == true)
    }

    func testOldDetailScreenCannotConfirmReusedCandidateIDFromSamePage() async throws {
        let reviewer = ControlledProposalReview(); let model = make(reviewer)
        model.foodTerms = "milk"
        let first = try ProposalPresentationFixture.result(name: "Milk")
        let firstTask = Task { await model.search() }; await reviewer.waitForRequest()
        await reviewer.complete(first); await firstTask.value
        let original = try XCTUnwrap(model.result?.validation.candidates.first)
        let nextTask = Task { await model.search() }; await reviewer.waitForRequest()
        await reviewer.complete(try ProposalPresentationFixture.result(name: "Yoghurt")); await nextTask.value
        XCTAssertEqual(model.result?.validation.candidates.first?.id, original.id)
        XCTAssertEqual(model.result?.validation.candidates.first?.document.rawSha256, original.document.rawSha256)
        XCTAssertThrowsError(try model.prepare(original, querySnapshot: "milk", scope: .representativeEstimate,
            acknowledgement: .init(identityAndScopeReviewed: true, basisReviewed: true, nutrientsAndUnknownsReviewed: true)))
    }

    func testReviewedSnapshotPreparesConfirmationWithoutAcceptingOrSupplyingIntake() async throws {
        let reviewer = ControlledProposalReview(); let model = make(reviewer)
        model.foodTerms = "milk"
        let task = Task { await model.search() }; await reviewer.waitForRequest()
        await reviewer.complete(try ProposalPresentationFixture.result()); await task.value
        let proposal = try XCTUnwrap(model.result?.validation.candidates.first)
        model.cancel(clearResult: false)
        let input = try model.prepare(proposal, querySnapshot: "milk", scope: .representativeEstimate,
            acknowledgement: .init(identityAndScopeReviewed: true, basisReviewed: true, nutrientsAndUnknownsReviewed: true))
        let state = FoodConfirmationState(input: input)
        XCTAssertEqual(state.decision, .undecided); XCTAssertNil(state.quantity.value)
        model.cancel()
        XCTAssertThrowsError(try model.prepare(proposal, querySnapshot: "milk", scope: .representativeEstimate,
            acknowledgement: .init(identityAndScopeReviewed: true, basisReviewed: true, nutrientsAndUnknownsReviewed: true)))
    }

    func testInsecureSourceIsRejectedWithoutReadingCredentialOrCallingProvider() async {
        let reviewer = ControlledProposalReview(); let keys = ProposalCredentials(); let model = make(reviewer, keys: keys)
        model.foodTerms = "milk"; model.sourceAddress = "http://example.com/milk"
        await model.search()
        XCTAssertEqual(keys.reads, 0)
        let count = await reviewer.callCount; XCTAssertEqual(count, 0)
        XCTAssertTrue(model.message?.contains("public HTTPS") == true)
    }

    func testOtherDiscoveredSourcesRemainAvailableAfterSuccessAndExplicitAlternativeFailure() async throws {
        let reviewer = ControlledProposalReview(); let model = make(reviewer)
        model.foodTerms = "milk"
        let original = try ProposalPresentationFixture.result()
        let leads = [FoodWebLead(title: "First", url: URL(string: "https://example.com/food")!),
                     FoodWebLead(title: "Second", url: URL(string: "https://other.example/food")!),
                     FoodWebLead(title: "Third", url: URL(string: "https://third.example/food")!)]
        let result = GenericFoodProposalReview(foodTerms: original.foodTerms,
            discovery: .init(leads: leads, searchSuggestionsHTML: nil), documents: original.documents,
            validation: original.validation, selection: nil, attemptedSourceURL: leads[0].url)
        let first = Task { await model.search() }; await reviewer.waitForRequest()
        await reviewer.complete(result); await first.value
        XCTAssertEqual(model.alternativeSources, Array(leads.dropFirst()))
        model.sourceAddress = leads[1].url.absoluteString
        let second = Task { await model.search() }; await reviewer.waitForRequest()
        await reviewer.fail(GenericFoodProposalPartialFailure(discovery: nil, reason: .acquisition(.unsupportedContent)))
        await second.value
        XCTAssertEqual(model.alternativeSources, [leads[0], leads[2]])
        model.foodTerms = "rice"
        XCTAssertTrue(model.alternativeSources.isEmpty)
    }

    func testOldCredentialFailureCannotPublishSourceLinksAfterKeyReplacement() async {
        let reviewer = ControlledProposalReview(); let keys = ProposalCredentials(); let model = make(reviewer, keys: keys)
        model.foodTerms = "milk"
        let task = Task { await model.search() }; await reviewer.waitForRequest()
        keys.version += 1
        let discovered = FoodWebDiscoveryResult(leads: [.init(title: "Old", url: URL(string: "https://old.example/food")!)], searchSuggestionsHTML: nil)
        await reviewer.fail(GenericFoodProposalPartialFailure(discovery: discovered, reason: .provider(.requestRejected)))
        await task.value
        XCTAssertTrue(model.alternativeSources.isEmpty)
        XCTAssertTrue(model.message?.contains("key changed") == true)
        XCTAssertEqual(keys.rejections, 0)
    }

    func testSourceAbstentionPreservesAllLeadsRatherThanHidingFirst() async {
        let reviewer = ControlledProposalReview(); let model = make(reviewer)
        model.foodTerms = "milk"
        let leads = [FoodWebLead(title: "First", url: URL(string: "https://first.example/food")!),
                     FoodWebLead(title: "Second", url: URL(string: "https://second.example/food")!)]
        let task = Task { await model.search() }; await reviewer.waitForRequest()
        await reviewer.fail(GenericFoodProposalPartialFailure(discovery: .init(leads: leads, searchSuggestionsHTML: nil),
            reason: .sourceNotSuggested))
        await task.value
        XCTAssertNil(model.result)
        XCTAssertEqual(model.alternativeSources, leads)
        XCTAssertTrue(model.message?.contains("None of the returned sources") == true)
    }

    func testSourceMarketConflictExplainsRegionAndKeepsAlternativeLeads() async {
        let reviewer = ControlledProposalReview(); let keys = ProposalCredentials(); let model = make(reviewer, keys: keys)
        model.foodTerms = "UK milk"
        let leads = [FoodWebLead(title: "Irish milk", url: URL(string: "https://publisher.ie/milk")!),
                     FoodWebLead(title: "UK milk", url: URL(string: "https://publisher.co.uk/milk")!)]
        let task = Task { await model.search() }; await reviewer.waitForRequest()
        await reviewer.fail(GenericFoodProposalPartialFailure(discovery: .init(leads: leads, searchSuggestionsHTML: nil),
            reason: .sourceMarketConflict))
        await task.value
        XCTAssertNil(model.result)
        XCTAssertEqual(model.alternativeSources, leads)
        XCTAssertTrue(model.message?.contains("different country") == true)
        XCTAssertEqual(keys.rejections, 0)
    }

    private func make(_ reviewer: any GenericFoodProposalReviewing, keys: ProposalCredentials = ProposalCredentials()) -> GenericFoodProposalReviewViewModel {
        GenericFoodProposalReviewViewModel(reviewer: reviewer, credentials: keys,
            confirmation: ReviewedFoodProposalConfirmation(ids: RandomLedgerIDGenerator(), clock: SystemLedgerClock(),
                encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()), locale: try! LedgerText("en_GB"))
    }
}

@MainActor
private final class ProposalCredentials: FoodWebCredentialAuthorizing {
    var version = 0; var rejections = 0; var reads = 0; var usable = true
    func credentialForRequest() throws -> FoodWebRequestCredential {
        reads += 1
        guard usable else { throw FoodSearchEnrichmentError.unavailable }
        return .init(key: "synthetic-proposal-key-contract-only", generation: version)
    }
    func isCurrent(_ credential: FoodWebRequestCredential) -> Bool { usable && credential.generation == version }
    func reject(_ credential: FoodWebRequestCredential) { if isCurrent(credential) { rejections += 1; usable = false } }
}

private actor ControlledProposalReview: GenericFoodProposalReviewing {
    var callCount = 0
    private var pending: CheckedContinuation<GenericFoodProposalReview, Error>?
    private var started: CheckedContinuation<Void, Never>?
    func review(foodTerms: String, sourceURL: URL?, key: String) async throws -> GenericFoodProposalReview {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation; started?.resume(); started = nil
        }
    }
    func waitForRequest() async { if pending != nil { return }; await withCheckedContinuation { started = $0 } }
    func complete(_ result: GenericFoodProposalReview) { let value = pending; pending = nil; value?.resume(returning: result) }
    func fail(_ error: any Error) { let value = pending; pending = nil; value?.resume(throwing: error) }
}

private enum ProposalPresentationFixture {
    static func result(name: String = "Milk", preferred: String = "c1", selection: String? = "c1") throws -> GenericFoodProposalReview {
        let text = "Milk Yoghurt Per 100g Energy 100kcal"
        let document = try GenericFoodDocumentProjector.project(Data(text.utf8), url: URL(string: "https://example.com/food")!,
            mediaType: "text/plain", retrievedAt: Date(timeIntervalSince1970: 0), origin: "synthetic_fixture")
        let ref: [[String: Any]] = [["block_id": "b1", "quote": text]]
        let nutrients: [[String: Any]] = FoodProposalNutrientKey.allCases.map { key in
            ["key": key.rawValue, "state": key == .energy ? "declared" : "unknown", "value": key == .energy ? "100" as Any : NSNull(),
             "unit": key == .energy ? "kcal" as Any : NSNull(), "evidence": key == .energy ? ref : [],
             "unknown_reason": key == .energy ? NSNull() : "not_observed" as Any]
        }
        let candidate: [String: Any] = ["id": "c1", "document_id": document.id, "name": name, "brand": NSNull(), "preparation": NSNull(),
            "identity_evidence": ref, "panel_evidence": ref,
            "basis": ["amount": "100", "unit": "g", "label": "Per 100g", "evidence": ref], "nutrients": nutrients, "limitations": []]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let extraction = try decoder.decode(FoodProposalExtraction.self, from: JSONSerialization.data(withJSONObject:
            ["version": FoodProposalExtraction.schemaVersion, "candidates": [candidate], "preferred_id": preferred]))
        let validation = try FoodProposalBinding.validate(extraction, documents: [document])
        let suggestion = try selection.map { try FoodProposalSelection(choice: $0,
            probabilities: ["c1": $0 == "c1" ? 1 : 0, "none": $0 == "none" ? 1 : 0, "clarify": $0 == "clarify" ? 1 : 0],
            rawConfidence: 1, validation: validation) }
        return GenericFoodProposalReview(foodTerms: "milk", discovery: nil, documents: [document],
            validation: validation, selection: suggestion)
    }
}
