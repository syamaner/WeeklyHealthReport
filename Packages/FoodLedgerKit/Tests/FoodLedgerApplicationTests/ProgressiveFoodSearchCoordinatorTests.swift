import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

@MainActor
final class ProgressiveFoodSearchCoordinatorTests: XCTestCase {
    private let enabled = FoodSearchServiceAvailability(onlineDatabase: .ready, gemini: .ready)

    func testNamedDishSearchKeepsOriginalOutboundContextAndRequiresQuantityInput() async throws {
        let started = expectation(description: "remote"); let finished = expectation(description: "finished")
        let provider = SuspendedSearch(started: started)
        let empty = try GenericFoodSearchOutcome.noResult(GenericFoodNoResultRoute(evidence: SearchFixture.evidence()))
        let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(empty), database: provider, services: enabled)
        coordinator.onUpdate = { if $0.pending == nil { finished.fulfill() } }
        let text = "200g cooked porridge made with water"
        let request = try SearchFixture.request(text)
        coordinator.search(request)
        await fulfillment(of: [started], timeout: 2)
        let terms = await provider.queries.map(\.foodTerms)
        XCTAssertEqual(terms, [text])
        let candidate = try SearchFixture.outcome(name: "Porridge, made with water")
        let coverage = ConservativeFoodSearchCoverageAssessment().assess(candidate, for: request)
        XCTAssertEqual(coverage.first?.quantity, .needsUserInput)
        await provider.release(.success(candidate))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertTrue(coordinator.snapshot.failures.isEmpty)
    }

    func testMethodQueryRejectsRawRemoteAndRetainsOriginalOutboundTerms() async throws {
        let started = expectation(description: "remote")
        let finished = expectation(description: "finished")
        let provider = SuspendedSearch(started: started)
        let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(try SearchFixture.outcome()), database: provider, services: enabled)
        coordinator.onUpdate = { if $0.pending == nil { finished.fulfill() } }
        coordinator.search(try SearchFixture.request("250g grilled sirloin"))
        await fulfillment(of: [started], timeout: 2)
        let terms = await provider.queries.map(\.foodTerms)
        XCTAssertEqual(terms, ["250g grilled sirloin"])
        await provider.release(.success(try SearchFixture.outcome(record: "raw", preparation: .raw)))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(SearchFixture.records(coordinator.snapshot.outcome), ["local"])
        XCTAssertEqual(coordinator.snapshot.failures.map(\.reason), [.invalidResponse])
        let local = CountingFoodSearch(try SearchFixture.outcome())
        let conflicting = ProgressiveFoodSearchCoordinator(local: local)
        conflicting.search(try SearchFixture.request("250g boiled sirloin", preparation: .raw))
        XCTAssertEqual(local.calls, 0)
        XCTAssertEqual(conflicting.snapshot.failures.map(\.reason), [.invalidQuery])
    }

    func testLocalPublishedBeforeRemoteAndRowsAppendWithoutMoving() async throws {
        let local = try SearchFixture.outcome(record: "local")
        let remote = try SearchFixture.outcome(record: "online")
        let started = expectation(description: "online called")
        let finished = expectation(description: "finished")
        let provider = SuspendedSearch(started: started)
        let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(local), database: provider, services: enabled)
        var updates: [ProgressiveFoodSearchSnapshot] = []
        coordinator.onUpdate = { value in updates.append(value); if value.pending == nil { finished.fulfill() } }
        coordinator.search(try SearchFixture.request())
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(SearchFixture.records(updates[0].outcome), ["local"])
        XCTAssertEqual(updates[0].pending, .onlineDatabase)
        await fulfillment(of: [started], timeout: 2)
        await provider.release(.success(remote))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(SearchFixture.records(coordinator.snapshot.outcome), ["local", "online"])
    }

    func testOnlineFailureKeepsLocalAndFallsThroughToGeminiOnce() async throws {
        let databaseStarted = expectation(description: "database")
        let geminiStarted = expectation(description: "gemini")
        let finished = expectation(description: "finished")
        let database = SuspendedSearch(started: databaseStarted)
        let gemini = SuspendedSearch(started: geminiStarted)
        let local = try SearchFixture.outcome(record: "local")
        let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(local), database: database, gemini: gemini, services: enabled)
        coordinator.onUpdate = { if $0.pending == nil { finished.fulfill() } }
        coordinator.search(try SearchFixture.request())
        await fulfillment(of: [databaseStarted], timeout: 2)
        await database.release(.failure(FoodSearchEnrichmentError.quotaExceeded))
        await fulfillment(of: [geminiStarted], timeout: 2)
        XCTAssertEqual(SearchFixture.records(coordinator.snapshot.outcome), ["local"])
        await gemini.release(.success(try SearchFixture.outcome(record: "grounded")))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(SearchFixture.records(coordinator.snapshot.outcome), ["local", "grounded"])
        XCTAssertEqual(coordinator.snapshot.failures.map(\.reason), [.quotaExceeded])
        let counts = await [database.calls, gemini.calls]
        XCTAssertEqual(counts, [1, 1])
    }

    func testSufficientDatabaseResultSuppressesGemini() async throws {
        let started = expectation(description: "database")
        let finished = expectation(description: "finished")
        let database = SuspendedSearch(started: started)
        let gemini = ImmediateSearch(try SearchFixture.outcome(record: "unused"))
        let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(try SearchFixture.outcome(record: "local")),
            database: database, gemini: gemini, services: enabled, assessment: SufficientOnlineAssessment())
        coordinator.onUpdate = { if $0.pending == nil { finished.fulfill() } }
        coordinator.search(try SearchFixture.request())
        await fulfillment(of: [started], timeout: 2)
        await database.release(.success(try SearchFixture.outcome(record: "online")))
        await fulfillment(of: [finished], timeout: 2)
        let calls = await gemini.calls
        XCTAssertEqual(calls, 0)
    }

    func testDisabledUnavailableAndMissingAdaptersMakeNoCalls() async throws {
        for access in [FoodSearchServiceAvailability.Access.disabled, .unavailable] {
            let provider = ImmediateSearch(try SearchFixture.outcome(record: "unused"))
            let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(try SearchFixture.outcome()),
                database: provider, gemini: provider, services: .init(onlineDatabase: access, gemini: access))
            coordinator.search(try SearchFixture.request())
            XCTAssertNil(coordinator.snapshot.pending)
            let calls = await provider.calls
            XCTAssertEqual(calls, 0)
        }
        let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(try SearchFixture.outcome()), services: enabled)
        coordinator.search(try SearchFixture.request())
        XCTAssertNil(coordinator.snapshot.pending)
        XCTAssertTrue(coordinator.snapshot.failures.isEmpty)
    }

    func testOnlyDisplayedTermsAndPreparationCrossRemoteBoundary() async throws {
        let started = expectation(description: "remote")
        let finished = expectation(description: "finished")
        let provider = SuspendedSearch(started: started)
        let evidence = try SearchFixture.evidence(payload: "private inventory evidence")
        let request = try GenericFoodSearchRequest(text: LedgerText("250g sirloin"),
            identity: GenericFoodIdentityQuery(preparation: PreparationState(kind: .cooked)),
            capturedAt: SearchFixture.date, locale: LedgerText("en_GB"), additionalEvidence: [evidence])
        let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(try SearchFixture.outcome()), database: provider, services: enabled)
        coordinator.onUpdate = { if $0.pending == nil { finished.fulfill() } }
        coordinator.search(request)
        await fulfillment(of: [started], timeout: 2)
        let queries = await provider.queries
        XCTAssertEqual(queries, [try FoodSearchRemoteQuery(foodTerms: "250g sirloin cooked")])
        XCTAssertEqual(Mirror(reflecting: queries[0]).children.compactMap(\.label), ["foodTerms"])
        await provider.release(.failure(FoodSearchEnrichmentError.unavailable))
        await fulfillment(of: [finished], timeout: 2)
    }

    func testCancellationAndServiceDisableIgnoreUncooperativeProvider() async throws {
        for disable in [false, true] {
            let started = expectation(description: "started")
            let returned = expectation(description: "provider returned")
            let provider = SuspendedSearch(started: started, returned: returned)
            let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(try SearchFixture.outcome(record: "local")), database: provider, services: enabled)
            coordinator.search(try SearchFixture.request())
            await fulfillment(of: [started], timeout: 2)
            if disable { coordinator.setServices(.init(onlineDatabase: .disabled, gemini: .disabled)) }
            else { coordinator.cancel() }
            var updates = 0
            coordinator.onUpdate = { _ in updates += 1 }
            await provider.release(.success(try SearchFixture.outcome(record: "late")))
            await fulfillment(of: [returned], timeout: 2)
            // Drain the same executor used to deliver the response without timing sleeps.
            await Task.yield()
            XCTAssertNil(coordinator.snapshot.pending)
            XCTAssertEqual(SearchFixture.records(coordinator.snapshot.outcome), ["local"])
            XCTAssertEqual(updates, 0)
        }
    }

    func testSelectionDuringLocalPublicationPreventsAnyRemoteLaunch() async throws {
        let provider = ImmediateSearch(try SearchFixture.outcome(record: "unused"))
        let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(try SearchFixture.outcome()), database: provider, services: enabled)
        coordinator.onUpdate = { [weak coordinator] _ in coordinator?.cancel() }
        coordinator.search(try SearchFixture.request())
        XCTAssertNil(coordinator.snapshot.pending)
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
    }

    func testRejectedCredentialsDisableNextRunWithoutRetry() async throws {
        let started = expectation(description: "first")
        let finished = expectation(description: "finished")
        let provider = SuspendedSearch(started: started)
        let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(try SearchFixture.outcome()), gemini: provider, services: enabled)
        coordinator.onUpdate = { if $0.pending == nil { finished.fulfill() } }
        coordinator.search(try SearchFixture.request())
        await fulfillment(of: [started], timeout: 2)
        await provider.release(.failure(FoodSearchEnrichmentError.credentialRejected))
        await fulfillment(of: [finished], timeout: 2)
        coordinator.onUpdate = nil
        coordinator.search(try SearchFixture.request())
        XCTAssertNil(coordinator.snapshot.pending)
        let calls = await provider.calls
        XCTAssertEqual(calls, 1)
    }

    func testConflictRejectsWholeBatchAndKeepsLocalResult() async throws {
        let started = expectation(description: "started")
        let finished = expectation(description: "finished")
        let provider = SuspendedSearch(started: started)
        let local = try SearchFixture.outcome(record: "same", name: "original")
        let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(local), database: provider, services: enabled)
        coordinator.onUpdate = { if $0.pending == nil { finished.fulfill() } }
        coordinator.search(try SearchFixture.request())
        await fulfillment(of: [started], timeout: 2)
        let conflict = try SearchFixture.outcome(record: "same", name: "different")
        let batch = try FoodSearchResultMerger.merge(SearchFixture.outcome(record: "new"), conflict)
        await provider.release(.success(batch))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(coordinator.snapshot.outcome, local)
        XCTAssertEqual(coordinator.snapshot.failures.map(\.reason), [.invalidResponse])
    }

    func testInvalidQueryNeverReachesLocalOrRemoteAndRemoteLengthIsBounded() throws {
        let local = CountingFoodSearch(try SearchFixture.outcome())
        let coordinator = ProgressiveFoodSearchCoordinator(local: local)
        coordinator.search(try SearchFixture.request("<100g rice"))
        XCTAssertEqual(local.calls, 0)
        XCTAssertEqual(coordinator.snapshot.failures.map(\.reason), [.invalidQuery])
        XCTAssertThrowsError(try FoodSearchRemoteQuery(foodTerms: "   "))
        XCTAssertThrowsError(try FoodSearchRemoteQuery(foodTerms: String(repeating: "a", count: 301)))
        XCTAssertEqual(try FoodSearchRemoteQuery(foodTerms: " milk ").foodTerms, "milk")
    }

    func testLocalFailureRetainsOriginalQueryAndPrivateEvidenceWithoutSendingIt() async throws {
        let started = expectation(description: "remote")
        let finished = expectation(description: "finished")
        let provider = SuspendedSearch(started: started)
        let inventory = try SearchFixture.evidence(id: 9, payload: "private inventory")
        let request = try GenericFoodSearchRequest(text: LedgerText("250g sirloin"), capturedAt: SearchFixture.date,
            locale: LedgerText("en_GB"), additionalEvidence: [inventory])
        let coordinator = ProgressiveFoodSearchCoordinator(local: FailingLocalSearch(), database: provider, services: enabled)
        coordinator.onUpdate = { if $0.pending == nil { finished.fulfill() } }
        coordinator.search(request)
        await fulfillment(of: [started], timeout: 2)
        await provider.release(.success(try SearchFixture.outcome(record: "online")))
        await fulfillment(of: [finished], timeout: 2)
        guard case let .confirmation(route) = coordinator.snapshot.outcome else { return XCTFail() }
        XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(request.text))
        XCTAssertTrue(route.confirmation.evidence.contains(inventory))
        let queries = await provider.queries
        XCTAssertEqual(queries.map(\.foodTerms), ["250g sirloin"])
    }

    func testEvidenceCreationFailureStopsBeforeAnyProviderAndConflictingPreparationStopsBeforeLocal() async throws {
        let provider = ImmediateSearch(try SearchFixture.outcome())
        let local = CountingFoodSearch(try SearchFixture.outcome())
        let coordinator = ProgressiveFoodSearchCoordinator(local: local, database: provider, services: enabled, ids: FailingSearchIDs())
        coordinator.search(try SearchFixture.request())
        XCTAssertNil(coordinator.snapshot.pending)
        XCTAssertEqual(local.calls, 0)
        let remoteCalls = await provider.calls
        XCTAssertEqual(remoteCalls, 0)
        let other = ProgressiveFoodSearchCoordinator(local: local)
        other.search(try SearchFixture.request("raw sirloin", preparation: .cooked))
        XCTAssertEqual(local.calls, 0)
        XCTAssertEqual(other.snapshot.failures.map(\.reason), [.invalidQuery])
    }

    func testKnownWrongPreparationIsRejectedEvenWithOptimisticAssessment() async throws {
        let finished = expectation(description: "finished")
        let raw = try SearchFixture.outcome(record: "raw", preparation: .raw)
        let provider = ImmediateSearch(raw)
        let coordinator = ProgressiveFoodSearchCoordinator(local: FixedFoodSearch(try SearchFixture.outcome()), database: provider,
            services: enabled, assessment: SufficientOnlineAssessment())
        coordinator.onUpdate = { if $0.pending == nil { finished.fulfill() } }
        coordinator.search(try SearchFixture.request("250g cooked sirloin"))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(SearchFixture.records(coordinator.snapshot.outcome), ["local"])
        XCTAssertEqual(coordinator.snapshot.failures.map(\.reason), [.invalidResponse])
    }
}

final class FoodSearchResultMergerTests: XCTestCase {
    func testIdenticalRecordsDeduplicateButDifferentReleasesRemainSeparate() throws {
        let original = try SearchFixture.outcome(record: "a")
        let duplicate = try FoodSearchResultMerger.merge(original, original)
        XCTAssertEqual(duplicate, original)
        let differentRelease = try SearchFixture.outcome(record: "a", release: "release-two")
        let merged = try FoodSearchResultMerger.merge(duplicate, differentRelease)
        guard case let .confirmation(route) = merged else { return XCTFail() }
        XCTAssertEqual(route.matches.count, 2)
        XCTAssertNotEqual(route.matches[0].searchID, route.matches[1].searchID)
        XCTAssertEqual(route.confirmation.sourceReleases.count, 2)
    }

    func testDuplicateOccurrenceRetainsEvidenceWithoutDuplicatingOrReplacingTheRow() throws {
        let original = try SearchFixture.outcome()
        let repeated = try SearchFixture.outcome(evidenceID: 2)
        let result = try FoodSearchResultMerger.merge(original, repeated)
        guard case let .confirmation(route) = result,
              case let .confirmation(first) = original else { return XCTFail() }
        XCTAssertEqual(route.matches, first.matches)
        XCTAssertEqual(route.confirmation.evidence.count, 2)
        XCTAssertEqual(route.confirmation.candidates[0], first.confirmation.candidates[0])
    }

    func testEvidenceReleaseAndRouteCollisionsAreRejected() throws {
        let original = try SearchFixture.outcome()
        XCTAssertThrowsError(try FoodSearchResultMerger.merge(original, SearchFixture.outcome(attribution: "changed")))
        XCTAssertThrowsError(try FoodSearchResultMerger.merge(original, SearchFixture.outcome(payload: "different query")))
        guard case let .confirmation(route) = original,
              case let .confirmation(other) = try SearchFixture.outcome(record: "other") else { return XCTFail() }
        let misaligned = GenericFoodSearchOutcome.confirmation(.init(confirmation: route.confirmation, matches: other.matches))
        XCTAssertThrowsError(try FoodSearchResultMerger.merge(nil, misaligned))
    }

    func testNoResultEvidenceSurvivesLaterCandidateAndMissCannotEraseCandidates() throws {
        let evidence = try SearchFixture.evidence(id: 2, payload: "original typed query")
        let miss = GenericFoodSearchOutcome.noResult(.init(evidence: evidence))
        let result = try FoodSearchResultMerger.merge(miss, SearchFixture.outcome())
        guard case let .confirmation(route) = result else { return XCTFail() }
        XCTAssertEqual(route.confirmation.evidence.first, evidence)
        XCTAssertEqual(try FoodSearchResultMerger.merge(result, miss), result)
    }

    func testCoverageSeparatesNutritionQuantityAndPreparationWithoutInventingConfidence() throws {
        let policy = ConservativeFoodSearchCoverageAssessment()
        let complete = try SearchFixture.outcome(complete: true)
        let base = try policy.assess(complete, for: SearchFixture.request("sirloin"))[0]
        XCTAssertEqual(base.match, .uncertain) // Exact name is deliberately insufficient.
        XCTAssertEqual(base.nutrition, .complete)
        XCTAssertEqual(base.quantity, .needsUserInput)
        XCTAssertEqual(base.basis, .compatible)
        let missing = try policy.assess(SearchFixture.outcome(), for: SearchFixture.request())[0]
        XCTAssertEqual(missing.nutrition, .incomplete)
        let volume = try policy.assess(complete, for: SearchFixture.request("250ml sirloin"))[0]
        XCTAssertEqual(volume.basis, .incompatible)
        let unknownPrep = try policy.assess(SearchFixture.outcome(preparation: .unknown),
            for: SearchFixture.request("250g cooked sirloin", preparation: .cooked))[0]
        XCTAssertEqual(unknownPrep.basis, .unknown)
    }
}

private struct SufficientOnlineAssessment: FoodSearchCoverageAssessing {
    func assess(_ outcome: GenericFoodSearchOutcome, for request: GenericFoodSearchRequest) -> [FoodSearchCandidateCoverage] {
        SearchFixture.records(outcome).map { .init(match: $0 == "online" ? .strong : .uncertain,
            nutrition: .complete, basis: .compatible, quantity: .ready) }
    }
}
private struct FailingLocalSearch: GenericFoodSearching {
    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome { throw FoodSearchEnrichmentError.unavailable }
}
private struct FailingSearchIDs: LedgerIDGenerating {
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> { throw FoodLedgerValidationError.invalidIdentifier("synthetic failure") }
}
private struct FixedFoodSearch: GenericFoodSearching {
    let outcome: GenericFoodSearchOutcome
    init(_ outcome: GenericFoodSearchOutcome) { self.outcome = outcome }
    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome { outcome }
}
private final class CountingFoodSearch: GenericFoodSearching, @unchecked Sendable {
    let outcome: GenericFoodSearchOutcome
    private(set) var calls = 0
    init(_ outcome: GenericFoodSearchOutcome) { self.outcome = outcome }
    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome { calls += 1; return outcome }
}
private actor ImmediateSearch: FoodSearchEnriching {
    let outcome: GenericFoodSearchOutcome
    private(set) var calls = 0
    init(_ outcome: GenericFoodSearchOutcome) { self.outcome = outcome }
    func enrich(_ query: FoodSearchRemoteQuery) async throws -> GenericFoodSearchOutcome { calls += 1; return outcome }
}
private actor SuspendedSearch: FoodSearchEnriching {
    let started: XCTestExpectation
    let returned: XCTestExpectation?
    private var continuation: CheckedContinuation<GenericFoodSearchOutcome, Error>?
    private(set) var queries: [FoodSearchRemoteQuery] = []
    var calls: Int { queries.count }
    init(started: XCTestExpectation, returned: XCTestExpectation? = nil) { self.started = started; self.returned = returned }
    func enrich(_ query: FoodSearchRemoteQuery) async throws -> GenericFoodSearchOutcome {
        queries.append(query)
        defer { returned?.fulfill() }
        return try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
    }
    func release(_ result: Result<GenericFoodSearchOutcome, Error>) { continuation?.resume(with: result); continuation = nil }
}

private enum SearchFixture {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    static func request(_ text: String = "250g sirloin", preparation: PreparationKind? = nil) throws -> GenericFoodSearchRequest {
        try GenericFoodSearchRequest(text: LedgerText(text),
            identity: GenericFoodIdentityQuery(preparation: preparation.map { try PreparationState(kind: $0) }),
            capturedAt: date, locale: LedgerText("en_GB"))
    }
    static func evidence(id: Int = 1, payload: String = "250g sirloin") throws -> CaptureEvidence {
        try CaptureEvidence(evidenceID: LedgerID(String(format: "00000000-0000-0000-0000-%012x", id)), kind: .genericSearch,
            capturedAt: date, locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"),
            captureMethodVersion: LedgerText("fixture-v1"), originalPayload: .text(LedgerText(payload)))
    }
    static func outcome(record: String = "local", name: String = "Sirloin", release: String = "fixture-v1",
                        preparation: PreparationKind = .cooked, complete: Bool = false,
                        attribution: String = "Synthetic", payload: String = "250g sirloin", evidenceID: Int = 1) throws -> GenericFoodSearchOutcome {
        let sourceID = try ExternalIdentifier("fixture")
        let releaseID = try ExternalIdentifier(release)
        let recordID = try ExternalIdentifier(record)
        let evidence = try evidence(id: evidenceID, payload: payload)
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: preparation), bone: .boneless,
            skin: .notApplicable, drained: .notApplicable, packingMedium: .named(LedgerText("none")),
            fortification: .unfortified, servingBasis: .per100Grams)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard complete, ConservativeFoodSearchCoverageAssessment.requiredNutrients.contains(key) else {
                return try NutrientEntry(key: key, value: .unknown(.notDeclared))
            }
            return try NutrientEntry(key: key, value: .augmented(ExactNutrientValue(amount: 1, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: 1, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [NutrientProvenance(sourceKind: .genericCompositionDataset, sourceID: sourceID,
                    sourceReleaseID: releaseID, recordID: recordID)])))
        })
        let release = try SourceRelease(sourceReleaseID: releaseID, sourceID: sourceID, releasedAt: date,
            artifactHash: SHA256Digest(String(repeating: "a", count: 64)), schemaVersion: LedgerText("fixture-v1"),
            pipelineVersion: LedgerText("fixture-v1"), licence: LedgerText("synthetic"), attribution: LedgerText(attribution),
            manifestHash: SHA256Digest(String(repeating: "b", count: 64)))
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: releaseID, recordID: recordID,
            identity: identity, edibleQuantity: .unknown, nutrients: nutrients, evidenceIDs: [evidence.evidenceID]),
            name: LedgerText(name), itemClass: .food)
        return .confirmation(GenericFoodConfirmationRoute(confirmation: try PopulatedFoodConfirmation(evidence: [evidence],
            sourceReleases: [release], candidates: [candidate], expectedIdentity: identity, expectedEdibleQuantity: .unknown),
            matches: [.init(candidate: candidate, isExactName: true)]))
    }
    static func records(_ outcome: GenericFoodSearchOutcome?) -> [String] {
        guard case let .confirmation(route) = outcome else { return [] }
        return route.matches.map { $0.candidate.candidate.recordID.value }
    }
}
