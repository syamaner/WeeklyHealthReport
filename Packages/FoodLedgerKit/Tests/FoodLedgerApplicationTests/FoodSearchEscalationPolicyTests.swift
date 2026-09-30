import FoodLedgerApplication
import XCTest

final class FoodSearchEscalationPolicyTests: XCTestCase {
    private let both = FoodSearchServiceAvailability(onlineDatabase: .ready, gemini: .ready)
    private let complete = FoodSearchCandidateCoverage(match: .strong, nutrition: .complete,
                                                       basis: .compatible, quantity: .ready)
    private let weak = FoodSearchCandidateCoverage(match: .uncertain, nutrition: .complete,
                                                   basis: .compatible, quantity: .ready)

    func testEligibilityMatrixNeverCallsDisabledOrUnavailableServices() {
        for database in FoodSearchServiceAvailability.Access.allCases {
            for gemini in FoodSearchServiceAvailability.Access.allCases {
                let access = FoodSearchServiceAvailability(onlineDatabase: database, gemini: gemini)
                let expected: FoodSearchStage? = database == .ready ? .onlineDatabase : gemini == .ready ? .gemini : nil
                XCTAssertEqual(FoodSearchEscalationPolicy.nextStage(after: .local, candidates: [], services: access), expected)
                XCTAssertEqual(FoodSearchEscalationPolicy.nextStage(after: .onlineDatabase, candidates: [], services: access),
                               gemini == .ready ? .gemini : nil)
                XCTAssertNil(FoodSearchEscalationPolicy.nextStage(after: .gemini, candidates: [], services: access))
            }
        }
    }

    func testEveryStageStopsWhenOneCandidateIsSufficient() {
        for stage in [FoodSearchStage.local, .onlineDatabase, .gemini] {
            XCTAssertNil(FoodSearchEscalationPolicy.nextStage(after: stage, candidates: [weak, complete], services: both))
        }
    }

    func testMissingQuantityAloneDoesNotCauseEnrichment() {
        let needsAmount = FoodSearchCandidateCoverage(match: .strong, nutrition: .complete,
                                                      basis: .compatible, quantity: .needsUserInput)
        XCTAssertNil(FoodSearchEscalationPolicy.nextStage(after: .local, candidates: [needsAmount], services: both))
    }

    func testStrongNameWithMissingNutritionStillEscalates() {
        for nutrition in [FoodSearchCandidateCoverage.Nutrition.incomplete, .unknown] {
            let candidate = FoodSearchCandidateCoverage(match: .strong, nutrition: nutrition,
                                                        basis: .compatible, quantity: .ready)
            XCTAssertEqual(FoodSearchEscalationPolicy.nextStage(after: .local, candidates: [candidate], services: both), .onlineDatabase)
        }
    }

    func testPreparationOrUnitBasisGapStillEscalates() {
        for basis in [FoodSearchCandidateCoverage.Basis.unknown, .incompatible] {
            let candidate = FoodSearchCandidateCoverage(match: .strong, nutrition: .complete,
                                                        basis: basis, quantity: .ready)
            XCTAssertEqual(FoodSearchEscalationPolicy.nextStage(after: .local, candidates: [candidate], services: both), .onlineDatabase)
        }
    }

    func testDifferentCandidatesCannotCombineIntoFalseSufficiency() {
        let identityOnly = FoodSearchCandidateCoverage(match: .strong, nutrition: .unknown,
                                                       basis: .compatible, quantity: .ready)
        XCTAssertEqual(FoodSearchEscalationPolicy.nextStage(after: .local, candidates: [identityOnly, weak], services: both), .onlineDatabase)
    }

    func testIncompatibleIdentityCannotBeRescuedByCompleteNutrition() {
        let wrong = FoodSearchCandidateCoverage(match: .incompatible, nutrition: .complete,
                                                basis: .compatible, quantity: .ready)
        XCTAssertEqual(FoodSearchEscalationPolicy.nextStage(after: .local, candidates: [wrong], services: both), .onlineDatabase)
    }

    func testLocalThenDatabaseThenGeminiAndNoRetry() throws {
        var session = FoodSearchSession()
        let local = session.begin(services: both)
        XCTAssertEqual(local.stage, .local)
        XCTAssertEqual(session.complete(local, candidates: [weak]), .accepted(next: session.pending))
        let database = try XCTUnwrap(session.pending)
        XCTAssertEqual(database.stage, .onlineDatabase)
        XCTAssertEqual(session.fail(database), .accepted(next: session.pending))
        let gemini = try XCTUnwrap(session.pending)
        XCTAssertEqual(gemini.stage, .gemini)
        XCTAssertEqual(session.coverage, [weak])
        XCTAssertEqual(session.fail(gemini), .accepted(next: nil))
        XCTAssertNil(session.pending)
        XCTAssertEqual(session.fail(gemini), .ignored)
        XCTAssertEqual(session.coverage, [weak])
    }

    func testDatabaseSuccessSuppressesGemini() throws {
        var session = FoodSearchSession()
        let local = session.begin(services: both)
        _ = session.complete(local, candidates: [weak])
        let database = try XCTUnwrap(session.pending)
        XCTAssertEqual(session.complete(database, candidates: [complete]), .accepted(next: nil))
        XCTAssertNil(session.pending)
        XCTAssertEqual(session.coverage, [weak, complete])
    }

    func testResubmissionRejectsOldSuccessAndFailureIncludingSameStage() {
        var session = FoodSearchSession()
        let old = session.begin(services: both)
        let current = session.begin(services: both)
        XCTAssertNotEqual(old, current)
        XCTAssertEqual(session.complete(old, candidates: [complete]), .ignored)
        XCTAssertEqual(session.fail(old), .ignored)
        XCTAssertEqual(session.pending, current)
        XCTAssertEqual(session.coverage, [])
        XCTAssertEqual(session.complete(current, candidates: [complete]), .accepted(next: nil))
    }

    func testCancelledRemoteCannotPublishEvenIfTransportIgnoresCancellation() throws {
        var session = FoodSearchSession()
        let local = session.begin(services: both)
        _ = session.complete(local, candidates: [weak])
        let remote = try XCTUnwrap(session.pending)
        session.cancel()
        XCTAssertEqual(session.complete(remote, candidates: [complete]), .ignored)
        XCTAssertEqual(session.fail(remote), .ignored)
        XCTAssertNil(session.pending)
    }

    func testDuplicateLocalCompletionCannotEndRemoteStage() throws {
        var session = FoodSearchSession()
        let local = session.begin(services: both)
        _ = session.complete(local, candidates: [weak])
        let remote = try XCTUnwrap(session.pending)
        XCTAssertEqual(session.complete(local, candidates: [complete]), .ignored)
        XCTAssertEqual(session.pending, remote)
        XCTAssertEqual(session.coverage, [weak])
    }

    func testTokenFromAnotherSessionCannotPublishIntoANewFlow() {
        var first = FoodSearchSession(sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        var second = FoodSearchSession(sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let old = first.begin(services: both)
        let current = second.begin(services: both)
        XCTAssertEqual(second.complete(old, candidates: [complete]), .ignored)
        XCTAssertEqual(second.fail(old), .ignored)
        XCTAssertEqual(second.pending, current)
        XCTAssertEqual(second.coverage, [])
    }

    func testNoEligibleServiceFinishesAfterLocalFailure() {
        var session = FoodSearchSession()
        let token = session.begin(services: .init(onlineDatabase: .disabled, gemini: .unavailable))
        XCTAssertEqual(session.fail(token), .accepted(next: nil))
        XCTAssertNil(session.pending)
    }
}
