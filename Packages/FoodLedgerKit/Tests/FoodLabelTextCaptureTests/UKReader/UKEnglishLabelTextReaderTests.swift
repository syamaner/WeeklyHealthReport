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
}
