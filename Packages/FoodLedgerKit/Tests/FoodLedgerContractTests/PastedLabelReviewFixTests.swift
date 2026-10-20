import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Invariant review fixes on PR #267: `pasted-label-serving-v1`, canonical manifest bytes, the
/// admitted pipelines pin, and a correction over a calculated value. Synthetic fixtures only.
final class PastedLabelReviewFixTests: XCTestCase {
    private typealias F = PastedLabelFixtures

    private func energy(_ saved: StoredFoodConfirmation) -> FoodIntakeTotal? {
        FoodIntakeSummary(contributions: [FoodIntakeContribution(quantity: saved.logItemVersion.edibleQuantity,
            basis: saved.productVersion.identity.servingBasis, nutrients: saved.resolutionVersion.nutrients)])
            .totals.first { $0.key == .energyConsumed }
    }

    private func state(_ input: PopulatedFoodConfirmation, _ amount: Double, _ unit: QuantityUnit) -> FoodConfirmationState {
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(amount, unit))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return state
    }

    // MARK: pasted-label-serving-v1

    func testServingPolicyVersionAndApplicability() throws {
        XCTAssertEqual(PastedLabelServingPolicy.version, "pasted-label-serving-v1")
        // Per 100 g with no serving size: no serving rule (v2 needs a serving size; see PastedLabelServingV2ContractTests).
        let per100 = try F.input(F.per100Manifest(servingSize: nil))
        XCTAssertFalse(PastedLabelServingPolicy.applies(per100, candidate: per100.candidates[0]), "No serving size, no servings")
        let case2 = try F.input(F.perServingManifest(readableServingSize: true))
        let case3 = try F.input(F.perServingManifest(readableServingSize: false))
        XCTAssertTrue(PastedLabelServingPolicy.applies(case2, candidate: case2.candidates[0]))
        XCTAssertFalse(PastedLabelServingPolicy.servingsOnly(case2, candidate: case2.candidates[0]))
        XCTAssertTrue(PastedLabelServingPolicy.servingsOnly(case3, candidate: case3.candidates[0]))
        XCTAssertEqual(FoodConfirmationState(input: case3).quantity.unit, .count, "Case 3 offers servings")
    }

    func testCaseThreeTwoServingsSavesAndScalesByTwo() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let input = try F.input(F.perServingManifest(readableServingSize: false))
            XCTAssertEqual(input.candidates[0].candidate.identity.servingBasis, .perServing(try PositiveQuantity(value: 1, unit: .count)))
            let service = try F.service(harness)
            let saved = try service.save(state(input, 2, .count), operationID: LedgerFixtures.operationID(9_950))
            XCTAssertEqual(saved.logItemVersion.edibleQuantity, try PositiveQuantity(value: 2, unit: .count), harness.name)
            XCTAssertNil(saved.quantityConversion, "Case 3 servings carry no weight (\(harness.name))")
            XCTAssertEqual(saved.assertions, [], harness.name)
            XCTAssertEqual(energy(saved)?.knownAmount, 222, "111 kcal per serving × 2 (\(harness.name))")
            XCTAssertNotNil(try service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            // Servings only: a weight is refused, never given to the serving.
            XCTAssertThrowsError(try service.save(state(input, 60, .grams), operationID: LedgerFixtures.operationID(9_951))) {
                guard case let .unmetRequirements(unmet) = $0 as? FoodConfirmationSaveError else { return XCTFail("\($0)") }
                XCTAssertTrue(unmet.contains(.sourceServingsRequired), harness.name)
            }
        }
    }

    func testCaseTwoLogsByServingsThroughThePrintedServingSizeAndByGrams() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let input = try F.input(F.perServingManifest(readableServingSize: true))
            let service = try F.service(harness)
            let servings = try service.save(state(input, 2, .count), operationID: LedgerFixtures.operationID(9_960))
            XCTAssertEqual(servings.logItemVersion.edibleQuantity, try PositiveQuantity(value: 60, unit: .grams), harness.name)
            let conversion = try XCTUnwrap(servings.quantityConversion, harness.name)
            XCTAssertEqual(conversion.methodVersion.value, "pasted-label-serving-v1", "The policy version is recorded (\(harness.name))")
            XCTAssertEqual(conversion.sourceQuantity, try PositiveQuantity(value: 2, unit: .count))
            XCTAssertEqual(conversion.convertedQuantity, try PositiveQuantity(value: 60, unit: .grams))
            XCTAssertEqual(conversion.sourceReleaseID, input.sourceReleases[0].sourceReleaseID)
            XCTAssertEqual(conversion.evidenceID, input.evidence[0].evidenceID)
            XCTAssertEqual(servings.assertions, [], harness.name)
            XCTAssertEqual(energy(servings)?.knownAmount, 222, harness.name)

            // Reopen and re-save unchanged: the policy conversion is reused, not duplicated.
            var reopened = try XCTUnwrap(service.reopen(logItemID: servings.logItem.logItemID))
            XCTAssertEqual(reopened.quantity.unit, .count)
            FoodConfirmationReducer.reduce(state: &reopened, action: .setQuantity(3, .count))
            let edited = try service.save(reopened, operationID: LedgerFixtures.operationID(9_961))
            XCTAssertEqual(edited.logItemVersion.edibleQuantity, try PositiveQuantity(value: 90, unit: .grams), harness.name)
            XCTAssertEqual(edited.quantityConversion?.methodVersion.value, "pasted-label-serving-v1")

            let grams = try service.save(state(input, 45, .grams), operationID: LedgerFixtures.operationID(9_962))
            XCTAssertEqual(grams.logItemVersion.edibleQuantity, try PositiveQuantity(value: 45, unit: .grams), harness.name)
            XCTAssertNil(grams.quantityConversion, harness.name)
            XCTAssertEqual(energy(grams)?.knownAmount, 166.5, harness.name)
        }
    }

    func testOrdinaryCountsStillNeedAMeasuredAmount() throws {
        // The policy is closed: a pasted label per 100 g without a serving size gains no serving rule.
        let input = try F.input(F.per100Manifest(servingSize: nil))
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(2, .count))
        XCTAssertTrue(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: QuickAddFixtures.london)
            .contains(.countNeedsMeasuredAmount))
    }

    // MARK: Canonical manifest bytes

    func testNonCanonicalManifestBytesFailAtSaveAndReopen() throws {
        let input = try F.input(F.manifest())
        guard case let .text(payload) = input.evidence[0].originalPayload else { return XCTFail() }
        let text = payload.value
        XCTAssertTrue(PastedLabelSource.isCanonical(Data(text.utf8), encoder: LedgerFixtures.encoder))
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let saved = try F.service(harness).save(F.state(input), operationID: LedgerFixtures.operationID(9_970))
            for (index, (name, variant)) in F.nonCanonicalVariants(text).enumerated() {
                XCTAssertNotEqual(variant, text, name)
                XCTAssertEqual(PastedLabelManifest.decode(Data(variant.utf8)), PastedLabelManifest.decode(Data(text.utf8)),
                               "\(name) decodes to the same manifest")
                XCTAssertFalse(PastedLabelSource.isCanonical(Data(variant.utf8), encoder: LedgerFixtures.encoder), name)
                let forged = try F.rebinding(input, manifestText: text, with: variant)
                XCTAssertThrowsError(try F.service(harness).save(F.state(forged), operationID: LedgerFixtures.operationID(9_971 + index)), name) {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource, "\(harness.name) \(name)")
                }
                let rewritten = try F.rebinding(saved, manifestText: text, with: variant)
                let service = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer),
                    reader: SingleStoredReader(saved: rewritten), clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(),
                    digester: LedgerFixtures.digester, pastedLabelConversions: GoldenPastedLabelConversions())
                XCTAssertThrowsError(try service.reopen(logItemID: saved.logItem.logItemID), "\(harness.name) \(name)") {
                    guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\($0)") }
                }
            }
        }
    }

    // MARK: Admitted pipelines

    func testAdmittedPipelinesGolden() {
        XCTAssertEqual(PastedLabelSource.admittedPipelines, [
            "pasted-nutrition-label-v1": [
                "nutrition-label-text-parser-v2:label-capture-decline-gate-v2:label-arithmetic-checks-v1:pasted-label-conversions-v1"
            ]
        ])
    }

    // MARK: Correction over a calculated value

    func testACorrectionOverACalculatedValueKeepsItsConversionVerified() throws {
        let corrected = PastedLabelManifest.Correction(kind: .corrected, nutrient: "energy_kcal", rowID: "熱量", headerID: "h2",
            recognised: .init(printedText: "1550 kJ", decimalText: "1550", unit: "kJ", comparator: "="),
            corrected: .init(decimalText: "380", unit: "kcal", comparator: "="), at: LedgerFixtures.date)
        let input = try F.input(F.manifest(corrections: [corrected]))
        guard case let .measured(energy) = input.candidates[0].candidate.nutrients.entries.first(where: { $0.key == .energyConsumed })?.value else {
            return XCTFail("energy")
        }
        XCTAssertEqual(energy.amount, 380, "The correction supplies the stored value")
        XCTAssertEqual(energy.provenance.map(\.sourceKind), [.manualDeclaration])
        XCTAssertFalse(NutrientDerivation.isCalculated(.measured(energy)), "A corrected value is not calculated")
        // The conversion record stays as evidence and is still verified.
        let badConversion = PastedLabelManifest.Conversion(nutrient: "energy_kcal", rule: "kj_to_kcal_v1", ruleVersion: "pasted-label-conversions-v1",
            sourceHeaderID: "h2", sourceRowID: "熱量", operandText: "1550", operandUnit: "kJ", factorText: "4.184",
            intermediateText: "370.458891", storedText: "370.4")
        XCTAssertThrowsError(try F.input(F.manifest(conversions: [badConversion, F.sodium], corrections: [corrected])))
        // Recognising the kJ cell needs a verified conversion of that cell; without one it is not a correction.
        XCTAssertThrowsError(try F.input(F.manifest(conversions: [F.sodium], corrections: [corrected])))
        // An entry over a calculated value is a correction, not an entry.
        let entered = PastedLabelManifest.Correction(kind: .entered, nutrient: "energy_kcal", rowID: nil, headerID: "h2", recognised: nil,
            corrected: .init(decimalText: "380", unit: "kcal", comparator: "="), at: LedgerFixtures.date)
        XCTAssertThrowsError(try F.input(F.manifest(corrections: [entered])))
    }
}

private struct SingleStoredReader: FoodConfirmationReading {
    let saved: StoredFoodConfirmation
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { saved.sourceReleases.first { $0.sourceReleaseID == id } }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { logItemID == saved.logItem.logItemID ? saved : nil }
    func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? {
        logItemVersionID == saved.logItemVersion.logItemVersionID ? saved : nil
    }
    func evidence(id: EvidenceID) throws -> CaptureEvidence? { saved.evidence.first { $0.evidenceID == id } }
}
