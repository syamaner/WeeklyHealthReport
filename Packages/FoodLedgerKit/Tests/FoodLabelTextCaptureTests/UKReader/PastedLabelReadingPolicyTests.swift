import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import NutritionLabelParsing
import XCTest

/// Contract tests 2 to 4 of `docs/pasted-nutrition-label-uk-english-v1-p2b.md`: the closed
/// reading policy, the UK policy's exact effect on every fixture, and no UK manifest before P5.
/// Test 1 (default equality) ran against the pre-seam development copy before it was removed.
final class PastedLabelReadingPolicyTests: XCTestCase {
    private let product = PastedLabelReader(reader: NutritionLabelTextReader(), digester: SHA256Digester())
    private let uk = PastedLabelReader(reader: NutritionLabelTextReader(), digester: SHA256Digester(), policy: .ukDevelopment)
    private let ukReader = PastedLabelReader(reader: UKEnglishLabelTextReader(), digester: SHA256Digester(), policy: .ukDevelopment)

    private func fixtureTexts() throws -> [String] {
        [SyntheticLabelTexts.base, SyntheticLabelTexts.kilojoulesOnly, SyntheticLabelTexts.asPrepared, SyntheticLabelTexts.drained,
         SyntheticLabelTexts.sodiumMissing, SyntheticLabelTexts.packMissing, SyntheticLabelTexts.perServingOnly,
         SyntheticLabelTexts.perServingNoSize, SyntheticLabelTexts.supplement, SyntheticLabelTexts.fullwidthDigits,
         SyntheticLabelTexts.energyMismatch, SyntheticLabelTexts.usNutritionFacts, SyntheticLabelTexts.ukDeclaration,
         SyntheticLabelTexts.japanese, UnheadedTableFixtures.inline1, UnheadedTableFixtures.inline2, UnheadedTableFixtures.inline1Ml,
         UnheadedTableFixtures.stacked1, UnheadedTableFixtures.stacked2, UnheadedTableFixtures.flattened1,
         UnheadedTableFixtures.flattened2, UnheadedTableFixtures.energyLine, UnheadedTableFixtures.energyLineServing,
         UnheadedTableFixtures.mixedInline] + TaiwanHeaderProbeTests.texts() + (try FrozenParityCases.textCases().map(\.text))
    }

    // MARK: Test 3, closure

    func testThePolicyIsClosedAndAUKScopeAlwaysReadsWithIdentityV3() {
        XCTAssertEqual(PastedLabelReadingPolicy.product.launchScope, ["taiwan_nutrition_labelling"])
        XCTAssertEqual(PastedLabelReadingPolicy.product.launchScope, PastedLabelLaunchScope.enabledFormats)
        XCTAssertEqual(PastedLabelReadingPolicy.product.identity, .v1)
        XCTAssertEqual(PastedLabelReadingPolicy.Identity.v1.rawValue, PastedLabelIdentity.version)
        XCTAssertEqual(PastedLabelReadingPolicy.Identity.v2.rawValue, PastedLabelBasisStateV2.version)
        XCTAssertEqual(PastedLabelReadingPolicy.Identity.v3.rawValue, PastedLabelBasisStateV3.version)
        XCTAssertEqual(PastedLabelReadingPolicy.ukDevelopment.launchScope.last, LabelFormatInference.Outcome.uk.rawValue)
        for policy in PastedLabelReadingPolicy.all where policy.admits(LabelFormatInference.Outcome.uk.rawValue) {
            XCTAssertEqual(policy.identity, .v3)
        }
    }

    // MARK: Test 2, the UK policy's exact effect

    private func reading(_ outcome: PastedLabelReadOutcome) -> LabelReading? {
        switch outcome {
        case let .declined(_, reading): reading
        case let .usable(review): review.reading
        case let .needsBasisChoice(request): request.declinedReading
        }
    }

    func testTheUKPolicyOnlyRemovesTheScopeDeclineFromUKTablesAndAppliesIdentityV3() throws {
        var admitted = 0
        for text in try fixtureTexts() {
            let mine = uk.read(text), theirs = product.read(text)
            if case .usable = theirs {
                XCTAssertEqual(mine, theirs, "a usable product reading changed: \(text)")
                continue
            }
            if case .needsBasisChoice = theirs { XCTAssertEqual(mine, theirs, text); continue }
            guard let candidate = reading(theirs)?.candidate else { XCTAssertEqual(mine, theirs, text); continue }
            var expected = theirs.declineCodes
            if reading(theirs)?.format == LabelFormatInference.Outcome.uk.rawValue {
                expected.removeAll { $0 == PastedLabelCodes.layoutNotSupported }
            }
            if !PastedLabelBasisStateV3.isAsSold(candidate), PastedLabelBasisState.isAsSold(candidate),
               !expected.contains(PastedLabelIdentity.basisStateNotSupported) {
                let noTable = expected.firstIndex(of: PastedLabelCodes.noTable) ?? expected.endIndex
                expected.insert(PastedLabelIdentity.basisStateNotSupported, at: noTable)
            }
            if expected.isEmpty {
                guard case .usable = mine else { XCTFail("a scope-only decline still declines: \(text)"); continue }
                admitted += 1
            } else {
                XCTAssertEqual(mine.declineCodes, expected, text)
            }
        }
        XCTAssertGreaterThan(admitted, 0)
    }

    func testTheSyntheticUKDeclarationReachesConfirmOnlyUnderTheUKPolicy() {
        guard case let .usable(review) = ukReader.read(SyntheticLabelTexts.ukDeclaration) else {
            return XCTFail("the synthetic UK declaration should be usable under .ukDevelopment")
        }
        XCTAssertEqual(review.reading.format, LabelFormatInference.Outcome.uk.rawValue)
        XCTAssertEqual(product.read(SyntheticLabelTexts.ukDeclaration).declineCodes, [PastedLabelCodes.layoutNotSupported])
    }

    func testTheUSPanelStillDeclinesForTheProductsReasonUnderTheUKPolicy() {
        let outcome = ukReader.read(SyntheticLabelTexts.usNutritionFacts)
        XCTAssertFalse(outcome.declineCodes.isEmpty)
        XCTAssertEqual(outcome.declineCodes,
                       product.read(SyntheticLabelTexts.usNutritionFacts).declineCodes.filter { $0 != PastedLabelCodes.layoutNotSupported })
    }

    // MARK: Test 4, no UK manifest before P5

    private struct Clock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) } }

    func testTheConfirmationRefusesTheUKPolicyAndBuildsNoManifest() throws {
        guard case let .usable(review) = ukReader.read(SyntheticLabelTexts.ukDeclaration) else { return XCTFail("no UK review") }
        let confirmation = PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: Clock(), encoder: FoundationCanonicalJSONEncoder(),
                                                   digester: SHA256Digester(), conversions: NutritionLabelConversionChecker(),
                                                   policy: .ukDevelopment)
        XCTAssertThrowsError(try confirmation.manifest(review, details: .init(name: "Synthetic oat bar"), corrections: [])) { error in
            XCTAssertEqual(error as? PastedLabelConfirmationError, .identityNotRecordable(PastedLabelBasisStateV3.version))
        }
        // The UK pipeline is not admitted either, so even under `.product` no UK manifest is built.
        let productConfirmation = PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: Clock(),
                                                          encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester(),
                                                          conversions: NutritionLabelConversionChecker())
        XCTAssertThrowsError(try productConfirmation.manifest(review, details: .init(name: "Synthetic oat bar"), corrections: []))
    }
}
