import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import NutritionLabelParsing
import UKNutritionLabelParsing
import XCTest

/// Contract tests 6 to 9 of `docs/pasted-nutrition-label-uk-english-v1-p2.md`: routing parity,
/// unchanged English, identity v2 and its parity with guard G3, on synthetic fixtures and the
/// frozen parity cases.
final class UKEnglishLabelTextReaderTests: XCTestCase {
    private let pinned = NutritionLabelTextReader()
    private let uk = UKEnglishLabelTextReader()
    private let v3 = NutritionLabelTextParserV3()

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

    private func language(_ text: String) -> LabelLanguage { v3.parse(text, inputSHA256: "x").language }

    private func withoutParserVersion(_ reading: LabelReading) -> LabelReading {
        LabelReading(origin: reading.origin, textSHA256: reading.textSHA256, candidate: reading.candidate, format: reading.format,
                     gate: reading.gate, checks: reading.checks, conversions: reading.conversions, storedHeaderID: reading.storedHeaderID,
                     versions: .init(parser: "", gate: reading.versions.gate, arithmetic: reading.versions.arithmetic,
                                     conversion: reading.versions.conversion, formatInference: reading.versions.formatInference),
                     unheadedTable: reading.unheadedTable)
    }

    /// Test 7: every text that is not English reads exactly as the pinned reader reads it.
    func testEveryNonEnglishTextReadsThroughThePinnedReaderUnchanged() throws {
        var count = 0
        for text in try fixtureTexts() where language(text) != .english {
            for asserted in [nil, AssertedBases([.per100g]), AssertedBases([.perServing, .per100g])] {
                XCTAssertEqual(uk.read(text, textSHA256: "h", assertedBases: asserted), pinned.read(text, textSHA256: "h", assertedBases: asserted), text)
            }
            count += 1
        }
        XCTAssertGreaterThan(count, 50)
    }

    /// Test 8: an English text no rule changes and the guard passes gives the pinned reading,
    /// apart from the parser version, in ordinary, unheaded and asserted reads.
    func testUnchangedEnglishTextsGiveThePinnedReadingApartFromTheParserVersion() throws {
        var count = 0
        for text in try fixtureTexts() where language(text) == .english {
            let lines = NutritionLabelTextParserUK.lines(text)
            let folded = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
            guard lines.joined(separator: "\n") == folded else { continue }
            for asserted in [nil, AssertedBases([.per100g]), AssertedBases([.perServing, .per100g])] {
                let mine = uk.read(text, textSHA256: "h", assertedBases: asserted)
                let theirs = pinned.read(text, textSHA256: "h", assertedBases: asserted)
                if mine.candidate.declineReasons.first?.hasPrefix("uk_") == true || mine.candidate.declineReasons == ["basis_state_not_supported"]
                    && theirs.candidate.declineReasons != ["basis_state_not_supported"] { continue }
                XCTAssertEqual(withoutParserVersion(mine), withoutParserVersion(theirs), text)
                XCTAssertEqual(mine.versions.parser, NutritionLabelTextParserUK.version)
            }
            count += 1
        }
        XCTAssertGreaterThan(count, 5)
    }

    func testTheSyntheticUKDeclarationReadsWithTheUKParserVersion() {
        let reading = uk.read(SyntheticLabelTexts.ukDeclaration, textSHA256: "h", assertedBases: nil)
        XCTAssertEqual(reading.versions.parser, NutritionLabelTextParserUK.version)
        XCTAssertEqual(reading.format, LabelFormatInference.Outcome.uk.rawValue)
        XCTAssertFalse(reading.candidate.declined)
    }

    // MARK: Identity v2 (test 6)

    private func candidate(header: String) -> PastedLabelManifest.Candidate {
        PastedLabelManifest.Candidate(route: "A", inputSHA256: "x", declined: false, declineReasons: [], wouldMarkReady: false, language: "en",
                                      servingSize: nil, servingsPerPack: nil,
                                      headers: [.init(headerID: "header_1", printedText: header, basis: "per_100g", servingConversion: nil)],
                                      cells: [], warnings: [])
    }

    func testIdentityV2DeclinesEveryNewMarkerAndKeepsTheNonMarkers() {
        for header in ["Per 100g as per preparation instructions", "Per 100g reconstituted", "Per 100g (cooked)", "Per 100g when made up",
                       "Per 100g as consumed", "Per 100g with milk", "Per 30g serving with butter", "Per 100g + 125ml", "Per 100g after cooking",
                       "Per 100g brewed", "Per 100g as served", "Per 100g oven baked", "Per 100g prepared", "Per 100g drained"] {
            XCTAssertFalse(PastedLabelBasisStateV2.isAsSold(candidate(header: header)), header)
        }
        for header in ["Per 100g unprepared", "Per 100g undrained", "Per 100g uncooked", "Per 100g as sold", "Per 30g serving", "Per 100g"] {
            XCTAssertTrue(PastedLabelBasisStateV2.isAsSold(candidate(header: header)), header)
        }
    }

    func testIdentityV2EqualsV1OnEveryTaiwanFixtureHeaderAndMatchesGuardG3() throws {
        for text in try fixtureTexts() where language(text) != .english {
            let reading = pinned.read(text, textSHA256: "h", assertedBases: nil)
            XCTAssertEqual(PastedLabelBasisStateV2.isAsSold(reading.candidate), PastedLabelBasisState.isAsSold(reading.candidate), text)
        }
        XCTAssertEqual(PastedLabelBasisStateV2.wordMarkers, UKVocabulary.identityWordMarkers)
        XCTAssertEqual(Set(PastedLabelBasisStateV2.substringMarkers).subtracting(PastedLabelBasisState.substringMarkers),
                       Set(UKVocabulary.identitySymbolMarkers))
        XCTAssertEqual(UKReadingGuard.basisStateNotSupported, PastedLabelIdentity.basisStateNotSupported)
    }

    // MARK: UK reader v2 (`docs/pasted-nutrition-label-uk-english-v2-p1.md`)

    func testIdentityV3AddsOnlyCompoundCookingWordsAndMatchesGuardG3() throws {
        XCTAssertEqual(PastedLabelBasisStateV3.wordMarkers, PastedLabelBasisStateV2.wordMarkers)
        XCTAssertEqual(PastedLabelBasisStateV3.substringMarkers, PastedLabelBasisStateV2.substringMarkers)
        XCTAssertEqual(PastedLabelBasisStateV3.compoundPrefixes, UKVocabulary.identityCompoundPrefixes)
        XCTAssertEqual(PastedLabelBasisStateV3.compoundCookingWords, UKVocabulary.identityCompoundCookingWords)
        XCTAssertTrue(Set(PastedLabelBasisStateV3.compoundCookingWords).isSubset(of: PastedLabelBasisStateV2.wordMarkers))
        for header in ["Per 100g (ovenbaked)", "Per 100g airfried", "Per 100g deepfried", "Per 100g ovenmicrowaved"] {
            XCTAssertFalse(PastedLabelBasisStateV3.isAsSold(candidate(header: header)), header)
            XCTAssertTrue(PastedLabelBasisStateV2.isAsSold(candidate(header: header)), "identity v2 misses \(header)")
        }
        for header in ["Per 100g oven-baked", "Per 100g pan-fried"] {
            XCTAssertFalse(PastedLabelBasisStateV3.isAsSold(candidate(header: header)), "regression: \(header)")
        }
        for header in ["Per 100g panettone", "Per 100g airy", "Per 100g deeply", "Per 100g unbaked", "Per 100g uncooked", "Per 30g serving"] {
            XCTAssertTrue(PastedLabelBasisStateV3.isAsSold(candidate(header: header)), header)
        }
        for text in try fixtureTexts() {
            let reading = pinned.read(text, textSHA256: "h", assertedBases: nil)
            XCTAssertEqual(PastedLabelBasisStateV3.isAsSold(reading.candidate), PastedLabelBasisStateV2.isAsSold(reading.candidate), text)
        }
    }

    func testSetAsideVitaminRowsAreUnreadRowsAndNothingElseIs() {
        let heading = "Typical values\tPer 100g\tPer 30g serving"
        let body = ["Energy\t1500kJ / 360kcal\t450kJ / 108kcal", "Fat\t12.0g\t3.6g", "of which saturates\t4.0g\t1.2g",
                    "Carbohydrate\t50.0g\t15.0g", "of which sugars\t20.0g\t6.0g", "Fibre\t3.0g\t0.9g", "Protein\t8.0g\t2.4g",
                    "Salt\t0.50g\t0.15g"]
        let text = ([". Contains 3 Servings", heading] + body + ["Vitamins", "Typical values\tPer 100g\tPer 30g serving\t% NRV",
                                                                "Vitamin D\t4.0µg\t1.2µg\t24%", "*NRV = Nutrient Reference Value"])
            .joined(separator: "\n")
        let reading = uk.read(text, textSHA256: "h", assertedBases: nil)
        XCTAssertEqual(reading.unreadRows, [LabelUnreadRow(reason: UKSetAsideReport.reason, printedLabel: "Vitamin D")])
        let records = uk.setAside(text)
        XCTAssertEqual(records.map(\.rule), ["S1", "S2", "S2", "S2", "S2"])
        XCTAssertEqual(records.first, UKSetAsideRecord(rule: "S1", line: 0, cell: nil, text: ". Contains 3 Servings"))
        XCTAssertEqual(uk.setAside("營養標示\n每一份量30公克\n本包裝含4份"), [], "nothing is set aside from a text that is not English")
    }
}
