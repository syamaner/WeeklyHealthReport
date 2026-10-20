import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// `pasted-label-serving-v2` (contract sections 2.3 and 6.3; owner, in session, 19 October 2026):
/// servings and whole pack on a stored per 100 g (per 100 ml) column with an exact serving size in
/// the same unit, printed or corrected or entered on Confirm. Both stores, save and reopen.
/// `pasted-label-serving-v1` is pinned unchanged by `PastedLabelReviewFixTests`. Synthetic only.
final class PastedLabelServingV2ContractTests: XCTestCase {
    private typealias F = PastedLabelFixtures

    private static let printed30g = PastedLabelManifest.Candidate.ServingSize(printedText: "每一份量30公克", decimalText: "30",
                                                                               unit: "公克", canonicalUnit: "g")
    private static let printed250ml = PastedLabelManifest.Candidate.ServingSize(printedText: "每一份量250毫升", decimalText: "250",
                                                                                 unit: "毫升", canonicalUnit: "ml")
    private static let exactPack = PastedLabelManifest.Candidate.ServingsPerPack(printedText: "本包裝含10份", decimalText: "10", approximate: false)

    private func state(_ input: PopulatedFoodConfirmation, _ amount: Double, _ unit: QuantityUnit) -> FoodConfirmationState {
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(amount, unit))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return state
    }

    private func energy(_ saved: StoredFoodConfirmation) -> Double? {
        FoodIntakeSummary(contributions: [FoodIntakeContribution(quantity: saved.logItemVersion.edibleQuantity,
            basis: saved.productVersion.identity.servingBasis, nutrients: saved.resolutionVersion.nutrients)])
            .totals.first { $0.key == .energyConsumed }?.knownAmount
    }

    private func sizeCorrection(_ kind: PastedLabelManifest.Correction.Kind, _ decimal: String, _ unit: String = "g",
                                recognised: PastedLabelManifest.Candidate.ServingSize? = printed30g) -> PastedLabelManifest.Correction {
        PastedLabelManifest.Correction(kind: kind, nutrient: "serving_size", rowID: nil, headerID: "h2",
            recognised: kind == .corrected ? recognised.map { .init(printedText: $0.printedText, decimalText: $0.decimalText ?? "",
                                                                    unit: $0.unit ?? "", comparator: "=") } : nil,
            corrected: .init(decimalText: decimal, unit: unit, comparator: "="), at: Date(timeIntervalSince1970: 1_700_000_900))
    }

    // MARK: Versions

    func testMethodVersionsAreAppendOnlyAndChosenByTheStoredColumn() throws {
        XCTAssertEqual(PastedLabelServingPolicy.version, "pasted-label-serving-v1", "v1 is unchanged")
        XCTAssertEqual(PastedLabelServingPolicy.per100Version, "pasted-label-serving-v2")
        XCTAssertEqual(PastedLabelServingPolicy.admittedVersions, ["pasted-label-serving-v1", "pasted-label-serving-v2"])

        let per100 = try F.input(F.per100Manifest(servingSize: Self.printed30g))
        XCTAssertEqual(PastedLabelServingPolicy.method(per100, candidate: per100.candidates[0]), "pasted-label-serving-v2")
        XCTAssertEqual(PastedLabelServingPolicy.serving(per100, candidate: per100.candidates[0]), try PositiveQuantity(value: 30, unit: .grams))
        XCTAssertFalse(PastedLabelServingPolicy.servingsOnly(per100, candidate: per100.candidates[0]))
        let perServing = try F.input(F.perServingManifest(readableServingSize: true))
        XCTAssertEqual(PastedLabelServingPolicy.method(perServing, candidate: perServing.candidates[0]), "pasted-label-serving-v1")
        let ml = try F.input(F.per100Manifest(servingSize: Self.printed250ml, basis: "per_100ml"))
        XCTAssertEqual(PastedLabelServingPolicy.serving(ml, candidate: ml.candidates[0]), try PositiveQuantity(value: 250, unit: .millilitres))
        XCTAssertEqual(FoodConfirmationState(input: per100).quantity, FoodQuantityDraft(value: 100, unit: .grams),
                       "A per 100 g label still opens on grams")
    }

    func testNoServingsWithoutAnExactServingSizeInTheBasisUnit() throws {
        let cases: [(String, PastedLabelManifest)] = [
            ("no serving size", try F.per100Manifest(servingSize: nil)),
            ("unreadable serving size", try F.per100Manifest(servingSize: .init(printedText: "每一份量一片", decimalText: nil, unit: nil, canonicalUnit: nil))),
            ("about (Chinese)", try F.per100Manifest(servingSize: .init(printedText: "每一份量約30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"))),
            ("about (English)", try F.per100Manifest(servingSize: .init(printedText: "Serving size about 30g", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("约 (simplified)", try F.per100Manifest(servingSize: .init(printedText: "每一份量约30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"))),
            ("〜 (wave dash)", try F.per100Manifest(servingSize: .init(printedText: "每一份量〜30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"))),
            ("≒", try F.per100Manifest(servingSize: .init(printedText: "每一份量≒30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"))),
            ("±", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g ± 2g", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("± before", try F.per100Manifest(servingSize: .init(printedText: "Serving size ±30g", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("hyphen range", try F.per100Manifest(servingSize: .init(printedText: "Serving size 25-30g", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("en-dash range", try F.per100Manifest(servingSize: .init(printedText: "Serving size 25–30 g", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("至 range", try F.per100Manifest(servingSize: .init(printedText: "每一份量25至30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"))),
            ("～ range", try F.per100Manifest(servingSize: .init(printedText: "每一份量25～30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"))),
            ("range after the unit", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g-35g", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("至 range with units", try F.per100Manifest(servingSize: .init(printedText: "每一份量30公克至35公克", decimalText: "30", unit: "公克", canonicalUnit: "g"))),
            ("quantity in brackets after a count (review reproduction)", try F.per100Manifest(servingSize: .init(printedText: "Serving size 3 gummies (approx. 3g)", decimalText: "3", unit: "g", canonicalUnit: "g"))),
            ("approx. after the quantity", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g approx.", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("(approx.) after the quantity", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g (approx.)", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("approximately after the quantity", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30 g approximately", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("約 after the quantity", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g 約", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("約 and a weight inside the bracket", try F.per100Manifest(servingSize: .init(printedText: "每一份量 30 公克（約30公克）", decimalText: "30", unit: "公克", canonicalUnit: "g"))),
            ("approx. and a weight inside the bracket", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g (approx. 28g)", decimalText: "28", unit: "g", canonicalUnit: "g"))),
            ("approx. and a weight word inside the bracket", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g (approx. 28 grams)", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("約 and a bare number inside the bracket", try F.per100Manifest(servingSize: .init(printedText: "每一份量 30 公克（約2）", decimalText: "30", unit: "公克", canonicalUnit: "g"))),
            ("tolerance with the same unit", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30 g ± 2 g", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("tolerance ending the value", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g±2", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("± with a percentage", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g ± 2%", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("± with another weight word", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30 g ± 2 grams", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("± alone", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30 g ±", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("range to a listed weight word", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g-35 grams", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("spaced range", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30 g - 35 g", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("comma then approx.", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g, approx.", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("full-width comma then 約", try F.per100Manifest(servingSize: .init(printedText: "每一份量30公克，約", decimalText: "30", unit: "公克", canonicalUnit: "g"))),
            ("word after a bracket group", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g (2 biscuits) approx.", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("about and ounce in the bracket", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g (about 1 ounce)", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("approx. and gm in the bracket", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g (approx. 28 gm)", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("about and fl oz in the bracket", try F.per100Manifest(servingSize: .init(printedText: "Serving size 30g (about 2 fl oz)", decimalText: "30", unit: "g", canonicalUnit: "g"))),
            ("quantity not found", try F.per100Manifest(servingSize: .init(printedText: "每一份量三十公克", decimalText: "30", unit: "公克", canonicalUnit: "g"))),
            ("ml against per 100 g", try F.per100Manifest(servingSize: Self.printed250ml)),
            ("g against per 100 ml", try F.per100Manifest(servingSize: Self.printed30g, basis: "per_100ml"))
        ]
        for (name, manifest) in cases {
            let input = try F.input(F.per100Manifest(servingSize: manifest.candidate.servingSize, servingsPerPack: Self.exactPack,
                                                     basis: manifest.candidate.headers[1].basis))
            XCTAssertNil(PastedLabelServingPolicy.serving(input, candidate: input.candidates[0]), name)
            XCTAssertNil(PastedLabelServingPolicy.wholePack(input, candidate: input.candidates[0]), name)
            var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(2, .count))
            XCTAssertTrue(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: QuickAddFixtures.london)
                .contains(.countNeedsMeasuredAmount), "Ordinary counts still need a measured amount (\(name))")
        }
        // English markers match whole words only: "surrounded" is not "around".
        let word = try F.input(F.per100Manifest(servingSize: .init(printedText: "Serving size 30g (surrounded)", decimalText: "30",
                                                                   unit: "g", canonicalUnit: "g")))
        XCTAssertEqual(PastedLabelServingPolicy.serving(word, candidate: word.candidates[0]), try PositiveQuantity(value: 30, unit: .grams))
    }

    /// Only the serving-size segment is scanned: an approximation elsewhere on the line (the pack
    /// count) or a range to another unit after the quantity keeps an exact serving size, and each
    /// saves under v2 and reopens on both stores.
    func testExactServingSizesSaveAndReopenUnderV2() throws {
        let exact: [(String, String, String)] = [
            ("每一份量30公克", "30", "公克"),
            ("每一份量30公克，本包裝含約10份", "30", "公克"),
            ("Serving size 30g – 2 biscuits", "30", "g"),
            ("每一份量 30 公克（約2片）", "30", "公克"),
            ("每一份量30公克(约2片)", "30", "公克"),
            ("Serving size 30g (about 2 biscuits)", "30", "g"),
            ("Serving size 30g (approx. 3 pieces)", "30", "g"),
            ("Serving size 30g ~ 2 pieces", "30", "g"),
            ("Serving size 1 bar (30g)", "30", "g"),
            ("Serving size 30g (surrounded)", "30", "g")
        ]
        XCTAssertEqual(PastedLabelServingPolicy.servingSegment(.init(printedText: "每一份量30公克，本包裝含約10份", decimalText: "30",
                                                                     unit: "公克", canonicalUnit: "g")), "30公克")
        XCTAssertEqual(PastedLabelServingPolicy.servingSegment(.init(printedText: "Serving size 30g ± 2g", decimalText: "30",
                                                                     unit: "g", canonicalUnit: "g")), "30g ±", "± always joins the quantity")
        XCTAssertEqual(PastedLabelServingPolicy.servingSegment(.init(printedText: "Serving size 3 gummies (approx. 3g)", decimalText: "3",
                                                                     unit: "g", canonicalUnit: "g")), "3 gummies (approx. 3g",
                       "the bracketed quantity, as the parser binds it")
        XCTAssertEqual(PastedLabelServingPolicy.servingSegment(.init(printedText: "Serving size 30g ~ 2 pieces", decimalText: "30",
                                                                     unit: "g", canonicalUnit: "g")), "30g", "a range to another unit is not a tolerance")
        XCTAssertNil(PastedLabelServingPolicy.servingSegment(.init(printedText: "Serving size 3 gummies (approx. 3g)", decimalText: "30",
                                                                   unit: "g", canonicalUnit: "g")), "not the recorded quantity")
        XCTAssertEqual(PastedLabelServingPolicy.approximateMarks, ["約", "约", "~", "～", "〜", "≈", "≒", "±", "+/-", "+-", "左右", "上下"], "fixed for v2")
        XCTAssertEqual(PastedLabelServingPolicy.approximateWords, ["about", "approx", "approximate", "approximately", "around", "ca", "circa", "roughly"])
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            for (index, (printed, decimal, unit)) in exact.enumerated() {
                let input = try F.input(F.per100Manifest(servingSize: .init(printedText: printed, decimalText: decimal, unit: unit,
                                                                           canonicalUnit: "g")), evidence: 9_600 + index)
                XCTAssertEqual(PastedLabelServingPolicy.serving(input, candidate: input.candidates[0]),
                               try PositiveQuantity(value: 30, unit: .grams), printed)
                let saved = try service.save(state(input, 2, .count), operationID: LedgerFixtures.operationID(9_600 + index))
                XCTAssertEqual(saved.quantityConversion?.methodVersion.value, "pasted-label-serving-v2", printed)
                let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), "\(harness.name) \(printed)")
                XCTAssertEqual(reopened.quantity.value, 2, printed)
                XCTAssertEqual(reopened.quantity.unit, .count, printed)
            }
        }
    }

    // MARK: Save and reopen on both stores

    func testServingsLogAsAV2QuantityConversionAgainstThePer100BasisOnBothStores() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let input = try F.input(F.per100Manifest(servingSize: Self.printed30g))
            let service = try F.service(harness)
            let servings = try service.save(state(input, 2, .count), operationID: LedgerFixtures.operationID(9_400))
            XCTAssertEqual(servings.logItemVersion.edibleQuantity, try PositiveQuantity(value: 60, unit: .grams), harness.name)
            XCTAssertEqual(servings.productVersion.identity.servingBasis, .per100Grams, "The basis stays per 100 g")
            let conversion = try XCTUnwrap(servings.quantityConversion, harness.name)
            XCTAssertEqual(conversion.methodVersion.value, "pasted-label-serving-v2", harness.name)
            XCTAssertEqual(conversion.sourceQuantity, try PositiveQuantity(value: 2, unit: .count))
            XCTAssertEqual(conversion.convertedQuantity, try PositiveQuantity(value: 60, unit: .grams))
            XCTAssertEqual(conversion.sourceReleaseID, input.sourceReleases[0].sourceReleaseID, "Cites the pasted release")
            XCTAssertEqual(conversion.evidenceID, input.evidence[0].evidenceID, "Cites the manifest evidence")
            XCTAssertEqual(servings.assertions, [], harness.name)
            XCTAssertEqual(try XCTUnwrap(energy(servings)), 222.3, accuracy: 0.000_001, "370.5 kcal per 100 g × 60 g (\(harness.name))")

            // Reopen and re-save: the v2 conversion is recomputed from the count.
            var reopened = try XCTUnwrap(service.reopen(logItemID: servings.logItem.logItemID), harness.name)
            XCTAssertEqual(reopened.quantity.unit, .count)
            XCTAssertEqual(reopened.quantity.value, 2)
            FoodConfirmationReducer.reduce(state: &reopened, action: .setQuantity(3, .count))
            let edited = try service.save(reopened, operationID: LedgerFixtures.operationID(9_401))
            XCTAssertEqual(edited.logItemVersion.edibleQuantity, try PositiveQuantity(value: 90, unit: .grams), harness.name)
            XCTAssertEqual(edited.quantityConversion?.methodVersion.value, "pasted-label-serving-v2")

            // Grams are still accepted as for any per 100 g basis, with no conversion.
            let grams = try service.save(state(input, 45, .grams), operationID: LedgerFixtures.operationID(9_402))
            XCTAssertEqual(grams.logItemVersion.edibleQuantity, try PositiveQuantity(value: 45, unit: .grams), harness.name)
            XCTAssertNil(grams.quantityConversion, harness.name)
        }
    }

    func testPer100MillilitreServingsLogInMillilitres() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let input = try F.input(F.per100Manifest(servingSize: Self.printed250ml, basis: "per_100ml"))
            let saved = try F.service(harness).save(state(input, 1.5, .count), operationID: LedgerFixtures.operationID(9_410))
            XCTAssertEqual(saved.logItemVersion.edibleQuantity, try PositiveQuantity(value: 375, unit: .millilitres), harness.name)
            XCTAssertEqual(saved.quantityConversion?.methodVersion.value, "pasted-label-serving-v2", harness.name)
        }
    }

    func testWholePackOnAPer100ColumnFromAPrintedOrEnteredExactCount() throws {
        let printed = try F.input(F.per100Manifest(servingSize: Self.printed30g, servingsPerPack: Self.exactPack))
        XCTAssertEqual(PastedLabelServingPolicy.wholePack(printed, candidate: printed.candidates[0]), PastedLabelWholePack(servings: 10, origin: .printed))
        let about = try F.input(F.per100Manifest(servingSize: Self.printed30g,
            servingsPerPack: .init(printedText: "本包裝含約10份", decimalText: "10", approximate: true)))
        XCTAssertNil(PastedLabelServingPolicy.wholePack(about, candidate: about.candidates[0]), "About is never a whole pack")
        let enteredPack = PastedLabelManifest.Correction(kind: .entered, nutrient: "servings_per_pack", rowID: nil, headerID: "h2",
            recognised: nil, corrected: .init(decimalText: "4", unit: "count", comparator: "="), at: Date(timeIntervalSince1970: 1_700_000_800))
        let entered = try F.input(F.per100Manifest(servingSize: Self.printed30g, corrections: [enteredPack]))
        XCTAssertEqual(PastedLabelServingPolicy.wholePack(entered, candidate: entered.candidates[0]),
                       PastedLabelWholePack(servings: 4, origin: .enteredByYou(correctionIndex: 0)))

        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let saved = try service.save(state(printed, 10, .count), operationID: LedgerFixtures.operationID(9_420))
            XCTAssertEqual(saved.logItemVersion.edibleQuantity, try PositiveQuantity(value: 300, unit: .grams), harness.name)
            XCTAssertEqual(saved.quantityConversion?.methodVersion.value, "pasted-label-serving-v2", harness.name)
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(PastedLabelServingPolicy.wholePack(reopened.input, candidate: reopened.input.candidates[0]),
                           PastedLabelWholePack(servings: 10, origin: .printed), harness.name)
        }
    }

    // MARK: Corrected or entered serving size

    func testACorrectedOrEnteredServingSizeFeedsV2AndIsVerified() throws {
        let corrected = try F.input(F.per100Manifest(servingSize: Self.printed30g, corrections: [sizeCorrection(.corrected, "35")]))
        XCTAssertEqual(PastedLabelServingPolicy.serving(corrected, candidate: corrected.candidates[0]), try PositiveQuantity(value: 35, unit: .grams))
        XCTAssertEqual(corrected.candidates[0].candidate.identity.servingBasis, .per100Grams, "A serving size never changes a per 100 g basis")
        // A user's exact value replaces an "about" printed serving size.
        let aboutPrinted = PastedLabelManifest.Candidate.ServingSize(printedText: "每一份量約30公克", decimalText: "30", unit: "公克", canonicalUnit: "g")
        let overAbout = try F.input(F.per100Manifest(servingSize: aboutPrinted, corrections: [sizeCorrection(.corrected, "32", recognised: aboutPrinted)]))
        XCTAssertEqual(PastedLabelServingPolicy.serving(overAbout, candidate: overAbout.candidates[0]), try PositiveQuantity(value: 32, unit: .grams))
        let entered = try F.input(F.per100Manifest(servingSize: nil, corrections: [sizeCorrection(.entered, "40")]))
        XCTAssertEqual(PastedLabelServingPolicy.serving(entered, candidate: entered.candidates[0]), try PositiveQuantity(value: 40, unit: .grams))
        let enteredMl = try F.input(F.per100Manifest(servingSize: nil, corrections: [sizeCorrection(.entered, "40", "ml")]))
        XCTAssertNil(PastedLabelServingPolicy.serving(enteredMl, candidate: enteredMl.candidates[0]), "No unit mismatch")

        // Inconsistent serving-size records fail verification on a per 100 g column too.
        let invalid: [(String, PastedLabelManifest.Correction, PastedLabelManifest.Candidate.ServingSize?)] = [
            ("entered over a readable printed size", sizeCorrection(.entered, "40"), Self.printed30g),
            ("corrected naming another printed size", sizeCorrection(.corrected, "35", recognised: .init(printedText: "每一份量31公克",
                decimalText: "31", unit: "公克", canonicalUnit: "g")), Self.printed30g),
            ("zero", sizeCorrection(.entered, "0"), nil),
            ("count", sizeCorrection(.entered, "2", "count"), nil)
        ]
        for (name, correction, printed) in invalid {
            let manifest = try F.per100Manifest(servingSize: printed, corrections: [correction])
            XCTAssertThrowsError(try PastedLabelSource.storedBasis(manifest), name)
            XCTAssertThrowsError(try F.input(manifest), name)
        }
        let twice = try F.per100Manifest(servingSize: nil, corrections: [sizeCorrection(.entered, "40"), sizeCorrection(.entered, "41")])
        XCTAssertThrowsError(try F.input(twice), "At most one serving-size record")

        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let saved = try service.save(state(corrected, 2, .count), operationID: LedgerFixtures.operationID(9_430))
            XCTAssertEqual(saved.logItemVersion.edibleQuantity, try PositiveQuantity(value: 70, unit: .grams), harness.name)
            XCTAssertNotNil(try service.reopen(logItemID: saved.logItem.logItemID), harness.name)
        }
    }

    // MARK: Inconsistent records

    func testAConversionNamingTheOtherMethodIsRefusedAtSave() throws {
        let per100 = try F.input(F.per100Manifest(servingSize: Self.printed30g))
        let perServing = try F.input(F.perServingManifest(readableServingSize: true))
        let ordinary = try F.input(F.per100Manifest(servingSize: nil))
        for (name, input, method) in [("v1 on per 100 g", per100, PastedLabelServingPolicy.version),
                                      ("v2 on per serving", perServing, PastedLabelServingPolicy.per100Version),
                                      ("v2 without a serving size", ordinary, PastedLabelServingPolicy.per100Version)] {
            var state = state(input, 2, .count)
            FoodConfirmationReducer.reduce(state: &state, action: .setConversion(QuantityConversionDraft(
                convertedQuantity: try PositiveQuantity(value: 60, unit: .grams), methodVersion: try LedgerText(method),
                sourceReleaseID: input.sourceReleases[0].sourceReleaseID, evidenceID: input.evidence[0].evidenceID)))
            XCTAssertTrue(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: QuickAddFixtures.london)
                .contains(.sourceServingsRequired), name)
            for harness in try LedgerFixtures.harnesses() {
                defer { harness.cleanup() }
                XCTAssertThrowsError(try F.service(harness).save(state, operationID: LedgerFixtures.operationID(9_440)), "\(name) \(harness.name)")
            }
        }
    }

    func testReopenRejectsAServingsConversionThatDoesNotMatchItsLabel() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let v2 = try service.save(state(try F.input(F.per100Manifest(servingSize: Self.printed30g)), 2, .count),
                                      operationID: LedgerFixtures.operationID(9_450))
            let v1 = try service.save(state(try F.input(F.perServingManifest(readableServingSize: true), evidence: 9_101), 2, .count),
                                      operationID: LedgerFixtures.operationID(9_451))
            let tampered = [
                ("v2 relabelled v1", try relabel(v2, from: "pasted-label-serving-v2", to: "pasted-label-serving-v1")),
                ("v1 relabelled v2", try relabel(v1, from: "pasted-label-serving-v1", to: "pasted-label-serving-v2")),
                ("v2 with another source quantity", try relabel(v2, from: #""sourceQuantity":{"unit":"count","value":2}"#,
                                                                 to: #""sourceQuantity":{"unit":"count","value":3}"#))
            ]
            for (name, saved) in tampered {
                let reader = ServingV2StoredReader(saved: saved)
                let reopening = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: reader,
                    clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester,
                    pastedLabelConversions: GoldenPastedLabelConversions())
                XCTAssertThrowsError(try reopening.reopen(logItemID: saved.logItem.logItemID), "\(harness.name) \(name)") {
                    guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\(name): \($0)") }
                }
            }
            // The untampered records reopen through the same path.
            for saved in [v1, v2] {
                let reopening = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer),
                    reader: ServingV2StoredReader(saved: saved), clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(),
                    digester: LedgerFixtures.digester, pastedLabelConversions: GoldenPastedLabelConversions())
                XCTAssertNotNil(try reopening.reopen(logItemID: saved.logItem.logItemID), harness.name)
            }
        }
    }

    /// Re-encodes a stored confirmation with one JSON fragment replaced (it must occur).
    private func relabel(_ saved: StoredFoodConfirmation, from: String, to: String) throws -> StoredFoodConfirmation {
        var json = String(decoding: try LedgerFixtures.encoder.encode(saved), as: UTF8.self)
        XCTAssertTrue(json.contains(from), from)
        json = json.replacingOccurrences(of: from, with: to)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(StoredFoodConfirmation.self, from: Data(json.utf8))
    }
}

private struct ServingV2StoredReader: FoodConfirmationReading {
    let saved: StoredFoodConfirmation
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { saved.sourceReleases.first { $0.sourceReleaseID == id } }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { logItemID == saved.logItem.logItemID ? saved : nil }
    func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? {
        logItemVersionID == saved.logItemVersion.logItemVersionID ? saved : nil
    }
    func evidence(id: EvidenceID) throws -> CaptureEvidence? { saved.evidence.first { $0.evidenceID == id } }
}
