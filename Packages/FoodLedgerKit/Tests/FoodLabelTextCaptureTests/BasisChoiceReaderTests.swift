import Foundation
@testable import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
@testable import NutritionLabelParsing
import XCTest

/// Reader v3 section 8.4 (PR 4) end to end through the adapter: `AssertedBases` at the port, the
/// versions of each read, the same outcome across options, mixed tables, the options from the
/// unheaded table and from each asserted candidate, servings under a chosen basis, decision 24,
/// and decision 25's byte-for-byte reproduction. Contract tests 10, 11, 12, 14, 19 and 21 of
/// 8.4.15. Every text is synthetic (`UnheadedTableFixtures`).
final class BasisChoiceReaderTests: XCTestCase {
    private typealias U = UnheadedTableFixtures
    private struct Clock: LedgerClock { let date: Date; func now() -> Date { date } }
    private let adapter = NutritionLabelTextReader()
    private let reader = PastedLabelReader(reader: NutritionLabelTextReader(), digester: SHA256Digester())
    /// A clock with a sub-millisecond part: the choice is truncated to whole milliseconds.
    private static let chosenAt = Date(timeIntervalSince1970: 1_700_000_000.123_9)

    private func builder(_ date: Date = chosenAt) -> PastedLabelConfirmation {
        PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: Clock(date: date), encoder: FoundationCanonicalJSONEncoder(),
                                digester: SHA256Digester(), conversions: NutritionLabelConversionChecker())
    }

    private func request(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> PastedLabelBasisChoiceRequest {
        let outcome = reader.read(text)
        guard case let .needsBasisChoice(request) = outcome else {
            XCTFail("Expected the basis sheet, got \(outcome.declineCodes)", file: file, line: line)
            throw NSError(domain: "basis", code: 1)
        }
        return request
    }

    private func arrangement(_ identifier: String) -> PastedLabelBasisOptions.Arrangement {
        PastedLabelBasisOptions.Arrangement(identifier: identifier)!
    }

    private func confirmation(_ review: PastedLabelReview) throws -> PopulatedFoodConfirmation {
        try builder().confirmation(review, details: .init(name: "Synthetic biscuits", fortification: .no), corrections: [],
                                   locale: LedgerText("zh_TW"))
    }

    private func verifies(_ input: PopulatedFoodConfirmation) -> Bool {
        PastedLabelSource.verify(input, candidate: input.candidates[0], encoder: FoundationCanonicalJSONEncoder(),
                                 digester: SHA256Digester(), conversions: NutritionLabelConversionChecker())
    }

    private func manifest(_ input: PopulatedFoodConfirmation) throws -> PastedLabelEvidenceManifest {
        try XCTUnwrap(PastedLabelValueOrigins.manifest(input, candidate: input.candidates[0]))
    }

    // MARK: 10. AssertedBases at the adapter, and the versions of each read

    func test10TheAdapterAppliesAssertedBasesAndReportsChecksV2() throws {
        let hash = String(repeating: "a", count: 64)
        let plain = adapter.read(U.inline1, textSHA256: hash, assertedBases: nil)
        XCTAssertEqual(plain.candidate.declineReasons, ["no_basis_header"])
        XCTAssertEqual(plain.versions.arithmetic, "label-arithmetic-checks-v1")
        let table = try XCTUnwrap(plain.unheadedTable)
        XCTAssertEqual(table.amountColumnCount, 1)
        XCTAssertEqual(table.amountHeaderIDs, ["header_1"])
        XCTAssertEqual(table.servingSize?.decimalText, "30")
        XCTAssertEqual(table.servingsPerPack?.decimalText, "8")
        XCTAssertFalse(table.referenceColumnPrinted)
        let asserted = adapter.read(U.inline1, textSHA256: hash, assertedBases: AssertedBases([.per100g]))
        XCTAssertFalse(asserted.candidate.declined)
        XCTAssertNil(asserted.unheadedTable)
        XCTAssertEqual(asserted.versions.arithmetic, "label-arithmetic-checks-v2")
        XCTAssertEqual(asserted.pipeline, PastedLabelSource.admittedPipelines["pasted-nutrition-label-v2"]?.first)
        XCTAssertEqual(asserted.candidate.headers.map(\.basis), ["per_100g"])
        XCTAssertEqual(asserted.candidate.headers.map(\.printedText), [""])
        XCTAssertTrue(asserted.checks.contains { $0.name == "basis_plausibility" && $0.basis == "per_100g" })
        XCTAssertFalse(plain.checks.contains { $0.name == "basis_plausibility" })
        // An ordinary read with printed headers stays checks v1 with the v1 pipeline.
        let printed = adapter.read(U.serving + "每100公克\n" + U.rows1.joined(separator: "\n"), textSHA256: hash, assertedBases: nil)
        XCTAssertEqual(printed.pipeline, PastedLabelSource.admittedPipelines["pasted-nutrition-label-v1"]?.last)
        // The adapter declines bases that do not fit.
        for (text, bases) in [(U.inline1, [AssertedBases.Basis.perServing, .per100g]), (U.inline2, [.per100g]),
                              (U.mixedInline, [.perServing, .per100g])] {
            XCTAssertEqual(adapter.read(text, textSHA256: hash, assertedBases: AssertedBases(bases)).candidate.declineReasons,
                           ["asserted_bases_mismatch"])
        }
        XCTAssertEqual(PastedLabelCodes.classify("asserted_bases_mismatch").copy, .unreadableTable)
    }

    /// Decision 25: reading the stored text with the bases from `basis_choices` reproduces the
    /// stored candidate byte for byte.
    func test10TheStoredCandidateIsReproducedFromBasisChoices() throws {
        let encoder = FoundationCanonicalJSONEncoder()
        for fixture in U.inScope {
            let request = try request(fixture.text)
            for option in request.options {
                let review = try builder().choose(option.arrangement, in: request)
                let stored = try manifest(confirmation(review))
                guard case let .v2(v2) = stored else { return XCTFail("\(fixture.name): manifest v2") }
                let bases = v2.basisChoices.compactMap { AssertedBases.Basis(rawValue: $0.basis) }
                let again = adapter.read(v2.pastedText, textSHA256: v2.pastedTextSHA256, assertedBases: AssertedBases(bases))
                XCTAssertEqual(try encoder.encode(again.candidate), try encoder.encode(v2.candidate),
                               "\(fixture.name) \(option.arrangement.identifier)")
            }
        }
    }

    // MARK: Every in-scope layout reaches a verified manifest v2

    func testEveryOptionOfEveryInScopeFixtureBuildsAVerifiedManifestV2() throws {
        for fixture in U.inScope {
            let request = try request(fixture.text)
            XCTAssertEqual(request.unheaded.amountColumnCount, fixture.columns, fixture.name)
            for option in request.options {
                let name = "\(fixture.name) \(option.arrangement.identifier)"
                let review = try builder().choose(option.arrangement, in: request)
                XCTAssertEqual(review.basisChoice?.at, 1_700_000_000_123, "\(name): truncated to whole milliseconds")
                XCTAssertEqual(review.basisChoice?.offered, request.offered, name)
                let input = try confirmation(review)
                XCTAssertTrue(verifies(input), name)
                XCTAssertEqual(input.evidence[0].captureMethodVersion.value, "pasted-nutrition-label-v2", name)
                XCTAssertEqual(input.sourceReleases[0].schemaVersion.value, "pasted-nutrition-label-v2:taiwan_nutrition_labelling", name)
                XCTAssertEqual(input.sourceReleases[0].pipelineVersion.value, PastedLabelSource.admittedPipelines["pasted-nutrition-label-v2"]?.first)
                let stored = try manifest(input)
                XCTAssertEqual(stored.basisChoices.map(\.basis), option.arrangement.bases.map(\.rawValue), name)
                XCTAssertEqual(stored.basisChoices.map(\.headerID), request.unheaded.amountHeaderIDs, name)
                XCTAssertEqual(stored.basisOrigin.isChosen, true, name)
                // Chosen-basis values keep user_verified_panel provenance: their numbers are printed.
                let panel = input.candidates[0].candidate.nutrients.entries.flatMap { $0.value.provenance }
                XCTAssertTrue(panel.contains { $0.sourceKind == .userVerifiedPanel }, name)
            }
        }
    }

    // MARK: 21. One serving-unit mapping: options from the table equal options from each asserted candidate

    func test21OptionsFromTheUnheadedTableEqualOptionsFromEachAssertedCandidate() throws {
        let approximate = U.inline1.replacingOccurrences(of: "每一份量 30公克", with: "每一份量 約30公克")
        let range = U.inline1.replacingOccurrences(of: "每一份量 30公克", with: "每一份量 25-30公克")
        for (name, text) in U.inScope.map({ ($0.name, $0.text) }) + [("approximate", approximate), ("range", range)] {
            let request = try request(text)
            let fromTable = PastedLabelBasisOptions.options(for: request.unheaded)?.map(\.identifier)
            XCTAssertEqual(fromTable, request.offered, name)
            for option in request.options {
                XCTAssertEqual(PastedLabelBasisOptions.options(for: option.review.reading.candidate)?.map(\.identifier), request.offered,
                               "\(name) \(option.arrangement.identifier)")
            }
        }
        // Approximate and range serving sizes map to their unit, so Per serving is offered.
        XCTAssertEqual(try request(approximate).offered, ["per_serving", "per_100g", "per_100ml"])
        XCTAssertEqual(try request(range).offered.first, "per_serving")
    }

    // MARK: 11. The same outcome across options; 12. mixed tables

    func test11AnyDecliningOptionMeansNoSheet() throws {
        XCTAssertEqual(reader.read(U.tooLittle).declineCodes, ["too_little_read"], "every option reads too little")
        XCTAssertEqual(reader.read(U.twoColumnsNoServing).declineCodes, ["unheaded_columns_without_serving_size"], "two columns, no serving size")
        XCTAssertEqual(PastedLabelCodes.classify("unheaded_columns_without_serving_size"), .init(kind: .hardDecline, copy: .noHeadingsNoServingSize))
        // A serving size printed, but not in grams or millilitres: its own copy says so.
        let packOnly = "營養標示\n每一份量 1包\n" + U.rows2.joined(separator: "\n") + "\n"
        XCTAssertEqual(reader.read(packOnly).declineCodes, ["unheaded_columns_serving_size_not_in_g_or_ml"])
        XCTAssertEqual(PastedLabelCodes.classify("unheaded_columns_serving_size_not_in_g_or_ml").copy, .noHeadingsServingSizeNotInGramsOrMillilitres)
        // An unheaded English table reads, but the launch scope declines every option.
        let english = "Energy 120kcal\nFat 3g\nSaturates 1g\nCarbohydrate 20g\nSugars 5g\nProtein 3g\nSalt 0.1g\n"
        XCTAssertEqual(reader.read(english).declineCodes, ["layout_not_supported"])
    }

    func test12MixedTablesInEveryLayoutDeclineWithoutASheet() {
        for fixture in U.mixed {
            let outcome = reader.read(fixture.text)
            guard case .declined = outcome else { return XCTFail("\(fixture.name): no sheet for a mixed table") }
            XCTAssertNil(outcome.declineCodes.first { $0 == "asserted_bases_mismatch" }, fixture.name)
        }
        XCTAssertFalse(reader.read(U.referenceNotLast).declineCodes.isEmpty, "a percentage before an amount: no sheet")
    }

    // MARK: 8.4.4: plausibility per option; only the chosen option's warning is recorded

    func testOnlyTheChosenOptionsPlausibilityWarningIsShownAndRecorded() throws {
        let request = try request(U.heavyServing)
        let warnings = Dictionary(uniqueKeysWithValues: request.options.map { ($0.arrangement.identifier, $0.plausibilityWarnings) })
        XCTAssertEqual(warnings["per_serving"], [])
        XCTAssertEqual(warnings["per_100g"], ["basis_plausibility:per_100g:macronutrients", "basis_plausibility:per_100g:energy"])
        let per100 = try builder().choose(arrangement("per_100g"), in: request)
        XCTAssertEqual(try manifest(confirmation(per100)).warningsShown.filter { $0.hasPrefix("basis_plausibility") },
                       ["basis_plausibility:per_100g:macronutrients", "basis_plausibility:per_100g:energy"])
        let perServing = try builder().choose(arrangement("per_serving"), in: request)
        XCTAssertFalse(try manifest(confirmation(perServing)).warningsShown.contains { $0.hasPrefix("basis_plausibility") })
    }

    // MARK: 19. Decision 24

    func test19TheHintIsRecordedOnlyWhenItDiffersFromTheChosenArrangement() throws {
        let request = try request(U.energyLine)
        XCTAssertEqual(request.offered, ["per_100g", "per_100ml"], "the hint never reorders")
        let differs = try builder().choose(arrangement("per_100g"), in: request)
        XCTAssertEqual(differs.warningCodes.last, "basis_hint:energy_line")
        XCTAssertEqual(differs.basisOrigin, .chosenByYou(hint: "(每100毫升)"))
        let stored = try manifest(confirmation(differs))
        XCTAssertEqual(stored.warningsShown.last, "basis_hint:energy_line")
        XCTAssertEqual(stored.candidate.warnings.last, "basis_hint: energy_line: (每100毫升)")
        let agrees = try builder().choose(arrangement("per_100ml"), in: request)
        XCTAssertFalse(agrees.warningCodes.contains("basis_hint:energy_line"))
        XCTAssertEqual(agrees.basisOrigin, .chosenByYou(hint: nil))
        XCTAssertEqual(try manifest(confirmation(agrees)).candidate.warnings.last, "basis_hint: energy_line: (每100毫升)",
                       "the candidate keeps the hint either way")
        // With a serving size in millilitres: the order follows the serving unit, never the hint.
        let serving = try self.request(U.energyLineServing)
        XCTAssertEqual(serving.offered, ["per_serving", "per_100ml", "per_100g"])
        XCTAssertTrue(try builder().choose(arrangement("per_serving"), in: serving).warningCodes.contains("basis_hint:energy_line"))
        XCTAssertFalse(try builder().choose(arrangement("per_100ml"), in: serving).warningCodes.contains("basis_hint:energy_line"))
    }

    /// Review low 9: if the clock moved backwards between the choice and a rebuild of the source,
    /// `at` is re-stamped to the capture, so the source still builds and verifies; it is never
    /// refused silently.
    func test20AChoiceIsReStampedWhenTheClockMovedBackwards() throws {
        let request = try request(U.inline1)
        let review = try builder(Date(timeIntervalSince1970: 1_700_000_100)).choose(arrangement("per_100g"), in: request)
        XCTAssertEqual(review.basisChoice?.at, 1_700_000_100_000)
        let earlier = builder(Date(timeIntervalSince1970: 1_700_000_050.5))
        let input = try earlier.confirmation(review, details: .init(name: "Synthetic biscuits", fortification: .no), corrections: [],
                                             locale: LedgerText("zh_TW"))
        XCTAssertTrue(verifies(input))
        XCTAssertEqual(try manifest(input).basisChoices.map(\.at), [1_700_000_050_500])
    }

    // MARK: 14. Servings under a chosen basis: the 5.6 method table unchanged

    func test14TheServingMethodTableAppliesToTheAssertedBasis() throws {
        let exact = try request(U.inline1)
        let perServing = try confirmation(try builder().choose(arrangement("per_serving"), in: exact))
        XCTAssertEqual(PastedLabelServingPolicy.method(perServing, candidate: perServing.candidates[0]), "pasted-label-serving-v1")
        XCTAssertEqual(try PastedLabelSource.storedBasis(manifest(perServing)), .perServing(try PositiveQuantity(value: 30, unit: .grams)))
        let per100g = try confirmation(try builder().choose(arrangement("per_100g"), in: exact))
        XCTAssertEqual(PastedLabelServingPolicy.method(per100g, candidate: per100g.candidates[0]), "pasted-label-serving-v3")
        XCTAssertEqual(PastedLabelServingPolicy.serving(per100g, candidate: per100g.candidates[0]), try PositiveQuantity(value: 30, unit: .grams))
        let per100ml = try confirmation(try builder().choose(arrangement("per_100ml"), in: exact))
        XCTAssertNil(PastedLabelServingPolicy.serving(per100ml, candidate: per100ml.candidates[0]), "a serving in grams against per 100 ml")
        // An approximate serving size: per serving uses its basis quantity (v1); per 100 g offers none.
        let approximate = try request(U.inline1.replacingOccurrences(of: "每一份量 30公克", with: "每一份量 約30公克"))
        let approxServing = try confirmation(try builder().choose(arrangement("per_serving"), in: approximate))
        XCTAssertEqual(PastedLabelServingPolicy.method(approxServing, candidate: approxServing.candidates[0]), "pasted-label-serving-v1")
        XCTAssertEqual(PastedLabelServingPolicy.serving(approxServing, candidate: approxServing.candidates[0]),
                       try PositiveQuantity(value: 30, unit: .grams))
        let approx100 = try confirmation(try builder().choose(arrangement("per_100g"), in: approximate))
        XCTAssertNil(PastedLabelServingPolicy.serving(approx100, candidate: approx100.candidates[0]))
    }
}
