import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Confirm rules review v1 (docs/confirm-rules-review-v1.md, #470): the fill-only policy, the
/// one-tap packaged answer, the v6 reducer, and re-log and quick add carrying food details.
final class ConfirmRulesReviewContractTests: XCTestCase {
    typealias OFF = OpenFoodFactsEstimateContractTests

    /// An Open Food Facts product as the lookup builds it: every food detail unknown.
    static func unknownInput(_ route: OFF.Route = .barcode, expectedBasis: ResolutionBasis? = nil,
                             preparation: PreparationKind = .unknown) throws -> PopulatedFoodConfirmation {
        let base = try OFF.input(route)
        let source = base.candidates[0]
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: preparation), bone: .unknown, skin: .unknown,
            drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: source.candidate.identity.servingBasis)
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(
            sourceReleaseID: source.candidate.sourceReleaseID, recordID: source.candidate.recordID, identity: identity,
            edibleQuantity: source.candidate.edibleQuantity, nutrients: source.candidate.nutrients,
            evidenceIDs: source.candidate.evidenceIDs, matchMetadata: source.candidate.matchMetadata),
            name: source.name, brand: source.brand, variant: source.variant, barcode: source.barcode,
            itemClass: source.itemClass, packFacts: source.packFacts)
        let expected = try expectedBasis.map { try DecisiveIdentity(preparation: identity.preparation, bone: .unknown, skin: .unknown,
            drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: $0) } ?? identity
        return try PopulatedFoodConfirmation(evidence: base.evidence, sourceReleases: base.sourceReleases, candidates: [candidate],
            expectedIdentity: expected, expectedEdibleQuantity: base.expectedEdibleQuantity)
    }

    static func newState(_ input: PopulatedFoodConfirmation) -> FoodConfirmationState {
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(25, .grams))
        return state
    }

    static func sheetCorrection(_ state: FoodConfirmationState, preparation: PreparationKind = .asSold,
                                name: String? = nil, variant: String?? = nil, fortification: FortificationState = .unfortified,
                                reason: String = "typed") throws -> FoodCorrection {
        let source = state.selectedCandidate
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: preparation), bone: .notApplicable,
            skin: .notApplicable, drained: .notApplicable, packingMedium: .named(LedgerText("as sold")),
            fortification: fortification, servingBasis: source.candidate.identity.servingBasis)
        let variantText: LedgerText? = switch variant {
        case .none: source.variant
        case let .some(value): try value.map { try LedgerText($0) }
        }
        return FoodCorrection(name: try name.map { try LedgerText($0) } ?? source.name, brand: source.brand, variant: variantText,
            identity: identity, itemClass: fortification == .fortified ? .fortifiedFood : source.itemClass,
            nutrients: source.candidate.nutrients, reason: try LedgerText(reason))
    }

    // MARK: Rule 2.1, the fill-only test (tests 1 and 2)

    func testTheFillTestHoldsOnlyWhenEveryChangedDetailWasUnknown() throws {
        let state = Self.newState(try Self.unknownInput())
        XCTAssertTrue(FoodDetailsFillPolicy.isFill(try Self.sheetCorrection(state), in: state))
        XCTAssertTrue(FoodDetailsFillPolicy.isFill(try Self.sheetCorrection(state, fortification: .fortified), in: state),
                      "food to fortifiedFood with a fortified fill")
        XCTAssertFalse(FoodDetailsFillPolicy.isFill(try Self.sheetCorrection(state, name: "Another name"), in: state), "name")
        XCTAssertFalse(FoodDetailsFillPolicy.isFill(try Self.sheetCorrection(state, variant: .some(nil)), in: state), "variant")
        let source = state.selectedCandidate
        let changedValues = FoodCorrection(name: source.name, brand: source.brand, variant: source.variant,
            identity: try Self.sheetCorrection(state).identity, itemClass: source.itemClass,
            nutrients: try OFF.nutrients(fibre: OFF.exact(.fiber, 9)), reason: try LedgerText("typed"))
        XCTAssertFalse(FoodDetailsFillPolicy.isFill(changedValues, in: state), "values")

        // A source that states its details: changing one is not a fill.
        let known = Self.newState(try OFF.input(.barcode))
        XCTAssertFalse(FoodDetailsFillPolicy.isFill(try Self.sheetCorrection(known, preparation: .cooked), in: known))
    }

    func testTheEstimateRuleStaysOnTheValuePreservingLayer() throws {
        // Decision 6 of off-label-estimate-v1: changing a known food detail keeps the estimate.
        let known = Self.newState(try OFF.input(.barcode))
        let cooked = try Self.sheetCorrection(known, preparation: .cooked)
        XCTAssertFalse(FoodDetailsFillPolicy.isFill(cooked, in: known))
        XCTAssertTrue(OpenFoodFactsEstimateSource.isIdentityOnlyCorrection(cooked, of: known.selectedCandidate))
        XCTAssertFalse(OpenFoodFactsEstimateSource.isIdentityOnlyCorrection(
            try Self.sheetCorrection(known, fortification: .fortified), of: known.selectedCandidate), "fortified drops it")
    }

    func testAChangeAfterAFillIsNotAFill() throws {
        var state = Self.newState(try Self.unknownInput())
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(try PackagedAsSoldPolicy.correction(for: state, fortified: false)))
        XCTAssertFalse(FoodDetailsFillPolicy.isFill(try Self.sheetCorrection(state, preparation: .cooked), in: state),
                       "as sold, then cooked, is a change")
        XCTAssertTrue(FoodDetailsFillPolicy.isFill(try Self.sheetCorrection(state), in: state), "the same answers again")
    }

    // MARK: Rule 1, the one tap (tests 3 and 4)

    func testThePackagedAnswerIsAnOrdinaryCorrectionWithItsFixedReason() throws {
        for fortified in [false, true] {
            for harness in try LedgerFixtures.harnesses() {
                defer { harness.cleanup() }
                var state = Self.newState(try Self.unknownInput())
                XCTAssertTrue(PackagedAsSoldPolicy.offers(state), harness.name)
                XCTAssertFalse(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: .current).isEmpty)
                let correction = try PackagedAsSoldPolicy.correction(for: state, fortified: fortified)
                XCTAssertEqual(correction.reason.value, "Packaged product, eaten as sold")
                XCTAssertEqual(correction.name, state.selectedCandidate.name)
                XCTAssertEqual(correction.nutrients, state.selectedCandidate.candidate.nutrients)
                XCTAssertEqual(correction.itemClass, fortified ? .fortifiedFood : .food)
                FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(correction))
                XCTAssertFalse(PackagedAsSoldPolicy.offers(state), "offered once")
                XCTAssertFalse(state.unresolvedIdentity.contains { _ in true }, "food details known")
                XCTAssertEqual(OpenFoodFactsEstimateSource.admitsLayer(state), !fortified, "No keeps the estimate; Yes withdraws it")
                FoodConfirmationReducer.reduce(state: &state, action: .accept)
                let saved = try OFF.service(harness).save(state, operationID: LedgerFixtures.operationID(9_700 + (fortified ? 1 : 0)))
                XCTAssertEqual(saved.productVersion.identity, correction.identity, harness.name)
                XCTAssertEqual(saved.candidateDecision.outcome, .rejected, "as every corrected save")
                XCTAssertTrue(saved.assertions.contains { $0.claim.value.hasPrefix("Corrected populated confirmation") })
                XCTAssertEqual(saved.resolutionVersion.methodVersion.value, "food_confirmation_v5")
                XCTAssertFalse(try OFF.service(harness).isEstimate(saved), "an exact product with known details is not an estimate")
            }
        }
    }

    func testThePackagedAnswerIsOfferedOnlyForOpenFoodFactsProductsWithMissingDetails() throws {
        XCTAssertFalse(PackagedAsSoldPolicy.offers(Self.newState(try OFF.input(.barcode))), "details already known")
        XCTAssertTrue(PackagedAsSoldPolicy.offers(Self.newState(try Self.unknownInput(.search))), "search route")
    }

    // MARK: Rule 2.4, the v6 reducer (test 5)

    func testAFillKeepsTheGuideAndAChangeClearsIt() throws {
        var state = Self.newState(try Self.unknownInput())
        state.quantity.portionGuideCode = try LedgerText("count-portion-guide-v1:synthetic")
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(try PackagedAsSoldPolicy.correction(for: state, fortified: false)))
        XCTAssertNotNil(state.quantity.portionGuideCode, "a fill keeps it")
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(try Self.sheetCorrection(state, preparation: .cooked)))
        XCTAssertNil(state.quantity.portionGuideCode, "as sold then cooked clears it")
    }

    // MARK: Rule 3, re-log and quick add (tests 6 to 8)

    func testRelogAndQuickAddCarryAFillAndNeedOnlyAnAmount() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let context = try QuickAddContext(harness)
            var state = Self.newState(try Self.unknownInput(.search))
            FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(try PackagedAsSoldPolicy.correction(for: state, fortified: false)))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let saved = try context.confirmations.save(state, operationID: context.ids.makeID(OperationTag.self))
            XCTAssertTrue(FoodDetailsFillPolicy.isStoredFill(saved), harness.name)

            let relog = try XCTUnwrap(try context.confirmations.relogState(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(relog.correction?.identity, saved.productVersion.identity, "carried (\(harness.name))")
            XCTAssertEqual(relog.correction?.reason.value, "Food details from your last entry")
            XCTAssertNotEqual(relog.decision, .accepted, "carrying is not acceptance")
            XCTAssertFalse(FoodLogPolicy.requirements(relog, now: LedgerFixtures.date, calendar: QuickAddFixtures.london)
                .contains { if case .sourceIdentityMissing = $0 { true } else { false } })

            let favourite = try context.favourites.saveFavourite(logItemVersionID: saved.logItemVersion.logItemVersionID)
            let preparation = try context.favourites.prepare(.favourite(favourite))
            XCTAssertEqual(preparation.eligibility, .sheet, "a fill-only favourite uses quick add (\(harness.name))")
            let again = try context.log(preparation)
            XCTAssertEqual(again.productVersion.identity, saved.productVersion.identity, harness.name)
        }
    }

    func testAStatedDetailChangeOrAFortifiedFillIsNotCarried() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let context = try QuickAddContext(harness)
            // A known source corrected to cooked: a change, never carried, even with a fixed reason typed.
            var known = Self.newState(try OFF.input(.search))
            FoodConfirmationReducer.reduce(state: &known, action: .applyCorrection(
                try Self.sheetCorrection(known, preparation: .cooked, reason: "Food details from your last entry")))
            FoodConfirmationReducer.reduce(state: &known, action: .accept)
            let changed = try context.confirmations.save(known, operationID: context.ids.makeID(OperationTag.self))
            XCTAssertFalse(FoodDetailsFillPolicy.isStoredFill(changed), harness.name)
            XCTAssertNil(try context.confirmations.relogState(logItemID: changed.logItem.logItemID)?.correction, harness.name)

            var unknown = Self.newState(try Self.unknownInput(.search))
            FoodConfirmationReducer.reduce(state: &unknown, action: .applyCorrection(try PackagedAsSoldPolicy.correction(for: unknown, fortified: true)))
            FoodConfirmationReducer.reduce(state: &unknown, action: .accept)
            let fortified = try context.confirmations.save(unknown, operationID: context.ids.makeID(OperationTag.self))
            XCTAssertFalse(FoodDetailsFillPolicy.isStoredFill(fortified), "fortified fill (\(harness.name))")
            let favourite = try context.favourites.saveFavourite(logItemVersionID: fortified.logItemVersion.logItemVersionID)
            XCTAssertNotEqual(try context.favourites.prepare(.favourite(favourite)).eligibility, .sheet, harness.name)
        }
    }

    /// Test 8: a carried fill answers only a question about a detail the source left unknown and
    /// the saved entry filled in; a basis or quantity difference, or a stated detail, is still decided.
    func testACarriedFillNeverAnswersARealDifference() throws {
        let unknown = try Self.unknownInput().candidates[0].candidate.identity
        let known = try OFF.input(.barcode).candidates[0].candidate.identity
        let filled = try Self.sheetCorrection(Self.newState(try Self.unknownInput())).identity
        XCTAssertTrue(FoodDetailsFillPolicy.answersOnlyBlank(.fortification, source: unknown, saved: filled))
        XCTAssertTrue(FoodDetailsFillPolicy.answersOnlyBlank(.preparation, source: unknown, saved: filled))
        XCTAssertFalse(FoodDetailsFillPolicy.answersOnlyBlank(.preparation, source: known, saved: filled), "a stated detail")
        XCTAssertFalse(FoodDetailsFillPolicy.answersOnlyBlank(.servingBasis, source: unknown, saved: filled))
        XCTAssertFalse(FoodDetailsFillPolicy.answersOnlyBlank(.edibleQuantity, source: unknown, saved: filled))
        XCTAssertFalse(FoodDetailsFillPolicy.answersOnlyBlank(.skin, source: unknown, saved: unknown), "nothing filled")
    }

    /// Invariant review: a decided difference (here Not sure on the basis, an estimate) is never
    /// dropped by the one tap or by a reason-free sheet fill, since a correction clears decisions.
    func testTheOneTapIsNotOfferedOnceADifferenceIsPendingOrDecided() throws {
        var state = Self.newState(try Self.unknownInput(expectedBasis: .per100Millilitres))
        XCTAssertFalse(FoodLogPolicy.pendingDifferences(state).isEmpty, "a basis difference to decide")
        XCTAssertFalse(PackagedAsSoldPolicy.offers(state), "pending")
        state.answerPendingDifferences()
        XCTAssertFalse(state.decisions.isEmpty)
        XCTAssertFalse(PackagedAsSoldPolicy.offers(state), "decided")
    }

    /// Rule 3.4 and 2.4: a re-log keeps its portion guide alongside the carried details.
    func testARelogKeepsItsPortionGuideWithTheCarriedDetails() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let context = try QuickAddContext(harness)
            var state = Self.newState(try Self.unknownInput(.search))
            FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(try PackagedAsSoldPolicy.correction(for: state, fortified: false)))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let saved = try context.confirmations.save(state, operationID: context.ids.makeID(OperationTag.self))
            let relog = try XCTUnwrap(try context.confirmations.relogState(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(relog.correctionOrigin, .carried, harness.name)
            XCTAssertEqual(relog.quantity.value, 25, "the last amount (\(harness.name))")
        }
    }

    /// Local Qodo review: resetting a filled detail to unknown, then filling a different value, is
    /// not a fill, so the guide is cleared and a reason is needed.
    func testResettingAFilledDetailAndRefillingItIsNotAFill() throws {
        var state = Self.newState(try Self.unknownInput())
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(try PackagedAsSoldPolicy.correction(for: state, fortified: false)))
        let source = state.selectedCandidate
        let reset = FoodCorrection(name: source.name, brand: source.brand, variant: source.variant,
            identity: source.candidate.identity, itemClass: source.itemClass, nutrients: source.candidate.nutrients,
            reason: try LedgerText("typed"))
        XCTAssertFalse(FoodDetailsFillPolicy.isFill(reset, in: state), "back to unknown is a change")
    }

    /// Qodo review of #473: after a reasoned change to a detail the source states, filling a blank
    /// is not reason-free, so the typed reason is never replaced by the fixed one.
    func testAFillAfterAStatedDetailChangeStillNeedsItsReason() throws {
        var state = Self.newState(try Self.unknownInput(preparation: .raw))
        let source = state.selectedCandidate
        let cooked = try DecisiveIdentity(preparation: PreparationState(kind: .cooked), bone: .unknown, skin: .unknown,
            drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: source.candidate.identity.servingBasis)
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(FoodCorrection(name: source.name, brand: source.brand,
            variant: source.variant, identity: cooked, itemClass: source.itemClass, nutrients: source.candidate.nutrients,
            reason: try LedgerText("I cooked it"))))
        XCTAssertFalse(FoodDetailsFillPolicy.isFill(try Self.sheetCorrection(state, preparation: .cooked), in: state),
                       "cooked stays a change from the source's raw")
        XCTAssertTrue(FoodDetailsFillPolicy.isFill(try Self.sheetCorrection(Self.newState(try Self.unknownInput(preparation: .raw)),
            preparation: .raw), in: Self.newState(try Self.unknownInput(preparation: .raw))), "the stated raw kept, blanks filled")
    }
}
