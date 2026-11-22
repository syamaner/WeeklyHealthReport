import FoodLedgerApplication
import FoodLedgerTestSupport
import Foundation
import XCTest

/// docs/openrouter-single-consent-v1-amendment.md O1.2 and O1.6 tests 1, 2 and 4, for the label
/// photo read session and the application's pure consent rules. Synthetic data only.
final class OpenRouterConsentSessionTests: XCTestCase {
    typealias S = LabelPhotoReadSessionTests

    private var image: PreparedLabelImage { S().image }

    func testTheBlockedReasonFollowsTheTableOrder() {
        XCTAssertEqual(OpenRouterAccess.blockedReason(consentOn: false, keyState: .valid), .switchOff)
        XCTAssertEqual(OpenRouterAccess.blockedReason(consentOn: false, keyState: .missing), .switchOff, "the switch comes first")
        XCTAssertEqual(OpenRouterAccess.blockedReason(consentOn: true, keyState: .missing), .noKey)
        XCTAssertEqual(OpenRouterAccess.blockedReason(consentOn: true, keyState: .notValidated), .keyNotValidated)
        XCTAssertNil(OpenRouterAccess.blockedReason(consentOn: true, keyState: .valid))
        XCTAssertEqual(OpenRouterAccess.keyState(hasSavedKey: false, keyIsUsable: false), .missing)
        XCTAssertEqual(OpenRouterAccess.keyState(hasSavedKey: true, keyIsUsable: false), .notValidated)
        XCTAssertEqual(OpenRouterAccess.keyState(hasSavedKey: true, keyIsUsable: true), .valid)
    }

    /// Section 6: the closed list and its explicit mapping to the policy and the egress table.
    func testTheUseListIsClosedAndMapsOnlyUsesInForce() {
        XCTAssertEqual(OpenRouterUse.allCases.filter(\.isInForce), [
            .keyValidation, .webLookup, .labelPhotoRead, .labelPhotoCatalogueCheck,
            .confirmEnrichmentDetails, .confirmEnrichmentNutrients,
            .confirmEnrichmentDetailsCatalogueCheck, .confirmEnrichmentNutrientsCatalogueCheck
        ])
        for use in OpenRouterUse.allCases {
            XCTAssertEqual(use.policyEntry != nil, use.isInForce, "\(use)")
            XCTAssertEqual(use.egressRow != nil, use.isInForce, "\(use)")
        }
        XCTAssertEqual(OpenRouterUse.keyValidation.egressRow, OpenRouterUse.webLookup.egressRow)
        XCTAssertEqual(OpenRouterUse.labelPhotoRead.policyEntry, OpenRouterUse.labelPhotoCatalogueCheck.policyEntry)
        // Confirm enrichment (phase gate section 6, PR 5): one policy entry, one row per part.
        let enrichment: [OpenRouterUse] = [.confirmEnrichmentDetails, .confirmEnrichmentNutrients,
                                           .confirmEnrichmentDetailsCatalogueCheck, .confirmEnrichmentNutrientsCatalogueCheck]
        XCTAssertEqual(Set(enrichment.map(\.policyEntry)), ["Confirm suggestions."])
        XCTAssertEqual(OpenRouterUse.confirmEnrichmentDetails.egressRow, "confirm-enrichment-openrouter-v1.md#OpenRouter System One")
        XCTAssertEqual(OpenRouterUse.confirmEnrichmentDetailsCatalogueCheck.egressRow, OpenRouterUse.confirmEnrichmentDetails.egressRow)
        XCTAssertEqual(OpenRouterUse.confirmEnrichmentNutrients.egressRow,
                       "confirm-enrichment-openrouter-v1.md#OpenRouter and its one allow-listed model endpoint for nutrient estimates")
        XCTAssertEqual(OpenRouterUse.confirmEnrichmentNutrientsCatalogueCheck.egressRow, OpenRouterUse.confirmEnrichmentNutrients.egressRow)
    }

    /// Section 6: the exhaustive switches name the new case; unreachable where the throw precedes them.
    func testTheSelectionFailureMappingOfARefusalIsPinned() {
        XCTAssertEqual(FoodProposalSelectionFailure(FoodWebDiscoveryError.notPermitted), .requestRejected)
    }

    func testARefusalBeforeTheCatalogueCheckSendsNothingAndKeepsTheRouteAvailable() async {
        let gate = RecordingOpenRouterEgress(permits: false)
        let (session, attempter, checker, ledger, _) = S().makeSession([S.answer], egress: gate)
        let outcome = await session.read(image)
        XCTAssertEqual(outcome, .failed(.notPermitted))
        XCTAssertEqual(checker.calls, 0)
        XCTAssertTrue(attempter.timeouts.isEmpty)
        XCTAssertEqual(ledger.writes, 0, "nothing is reserved or counted")
        XCTAssertEqual(gate.uses, [.labelPhotoCatalogueCheck])
        let status = await session.status()
        XCTAssertFalse(status.routeUnavailable)
        // Switched on again: a read the same day succeeds.
        gate.set(true)
        guard case .answered = await session.read(image) else { return XCTFail("the route stays available the same day") }
    }

    func testACheckerRefusalIsNotADayFailure() async {
        let checker = S.Checker(.failure(LabelPhotoRouteCheckFailure.notPermitted))
        let (session, attempter, _, ledger, _) = S().makeSession([S.answer], checker: checker)
        let outcome = await session.read(image)
        XCTAssertEqual(outcome, .failed(.notPermitted))
        XCTAssertTrue(attempter.timeouts.isEmpty)
        XCTAssertEqual(ledger.writes, 0)
        let status = await session.status()
        XCTAssertFalse(status.routeUnavailable, "routeUnavailableOn stays unset")
        checker.result = .success(S.good)
        guard case .answered = await session.read(image) else { return XCTFail() }
    }

    func testARefusalBeforeTheReservationReservesNothing() async {
        // The catalogue check is allowed, the reservation's ask is refused.
        let gate = RecordingOpenRouterEgress(permits: true, then: [false])
        let (session, attempter, checker, ledger, _) = S().makeSession([S.answer], egress: gate)
        let outcome = await session.read(image)
        XCTAssertEqual(outcome, .failed(.notPermitted))
        XCTAssertEqual(checker.calls, 1)
        XCTAssertTrue(attempter.timeouts.isEmpty)
        XCTAssertEqual(ledger.writes, 0, "the ledger is unchanged")
        XCTAssertEqual(gate.uses, [.labelPhotoCatalogueCheck, .labelPhotoRead])
    }

    func testAFirstAttemptRefusalReleasesTheReservation() async {
        let (session, _, _, ledger, _) = S().makeSession([.notSent(.notPermitted)])
        let outcome = await session.read(image)
        XCTAssertEqual(outcome, .failed(.notPermitted))
        XCTAssertEqual(ledger.day?.reads, 0, "the tap is released, not counted")
        XCTAssertTrue(ledger.day?.openTaps.isEmpty ?? true)
    }

    func testARetryRefusalSettlesOnTheSentAttemptAndSaysItMayHaveBeenSent() async {
        let (session, attempter, _, ledger, sleeper) = S().makeSession([S.failed(.httpStatus(503, retryAfter: nil), cost: 0.004),
                                                                         .notSent(.notPermitted)])
        let outcome = await session.read(image)
        XCTAssertEqual(outcome, .failed(.notPermittedAfterSending))
        XCTAssertEqual(attempter.timeouts.count, 2, "the refused retry is asked once and sends nothing")
        XCTAssertEqual(sleeper.sleeps.count, 1, "exactly one backoff wait")
        XCTAssertEqual(ledger.day?.reads, 1, "the tap is reconciled on the attempt already sent")
    }
}
