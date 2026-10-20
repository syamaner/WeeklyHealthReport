import CryptoKit
@testable import FoodLedgerApplication
import Foundation
@testable import NutritionLabelParsing
import XCTest

/// The reader v3 freeze (`docs/pasted-nutrition-label-reader-v3.md` section 12, decisions 14 and
/// 15): `nutrition-label-text-parser-v3`, `label-arithmetic-checks-v2`, `pasted-label-serving-v3`,
/// `taiwan-row-aliases-v1` and manifest `pasted-nutrition-label-v2` are frozen as of the freeze
/// commit, which is also the reference of the fresh-set release check (7.4). Any later change to
/// what they do is a new version (parser v4, checks v3, serving v4, aliases v2, manifest v3) and
/// needs a new fresh set.
///
/// Three pins, from the strictest to the most specific:
/// 1. the version strings;
/// 2. a SHA-256 of a canonical listing of the frozen rule tables (aliases, layout precedence, row
///    markers, approximation lists, the serving grammar copy, the serving method table, the
///    admitted pipelines, the options table, the checks v2 constants and a set of parser v3
///    patterns). Every list is filtered to the frozen versions, so adding a version (a new
///    parser, pipeline, serving method or manifest) is additive and leaves this hash unchanged.
///    It must **never** change while these versions exist;
/// 3. a SHA-256 of each file that implements the frozen behaviour or that the fresh-set harness
///    uses to read and bind values. A change to one of these files fails here, comments included.
///    Rules for a re-pin (section 12.1): a new version added beside the frozen one in the same
///    file, or a new file in `NutritionLabelParsing` holding only a new version (a new key here),
///    with pins 1 and 2 unchanged and the reason recorded in section 12.1; a comment-only change
///    waits until after the release check, and then needs a recorded re-pin with a diff showing
///    comments only, reviewed. A change that alters what a frozen version does is never re-pinned:
///    it is a new version.
///
/// No label text, value or product name is here: only rule tables and source hashes.
final class ReaderV3FreezeTests: XCTestCase {
    // MARK: 1. Version strings

    func testFrozenVersionStrings() {
        XCTAssertEqual(NutritionLabelTextParserV3.version, "nutrition-label-text-parser-v3")
        XCTAssertEqual(NutritionLabelTextParserV3.aliasVersion, "taiwan-row-aliases-v1")
        XCTAssertEqual(TaiwanRowAliases.version, "taiwan-row-aliases-v1")
        XCTAssertEqual(LabelArithmeticChecksV2.version, "label-arithmetic-checks-v2")
        XCTAssertEqual(PastedLabelServingPolicy.per100VersionV3, "pasted-label-serving-v3")
        XCTAssertEqual(PastedLabelManifestV2.version, "pasted-nutrition-label-v2")
        XCTAssertEqual(PastedLabelSource.parserVersion, "nutrition-label-text-parser-v3", "new readings are written with the frozen parser")
        XCTAssertEqual(PastedLabelSource.parserVersionV3, NutritionLabelTextParserV3.version)
        XCTAssertEqual(PastedLabelSource.arithmeticVersionV2, LabelArithmeticChecksV2.version)
        XCTAssertEqual(PastedLabelSource.gateVersion, "label-capture-decline-gate-v2")
        XCTAssertEqual(PastedLabelSource.conversionVersion, "pasted-label-conversions-v1")
    }

    // MARK: 2. Frozen rule tables

    static let frozenRuleTablesSHA256 = "58c7068d802ae6f8709cf66882d3997169c4f93f50a91cc891f9a81d276365e4"

    func testFrozenRuleTablesAreUnchanged() {
        let listing = Self.ruleTableListing()
        let digest = Self.sha256(Data(listing.utf8))
        XCTAssertEqual(digest, Self.frozenRuleTablesSHA256,
                       "A frozen rule table changed. That is a new version and a new fresh set (reader v3 section 12). Listing:\n\(listing)")
    }

    static let frozenParsers = ["nutrition-label-text-parser-v2", "nutrition-label-text-parser-v3"]
    static let frozenServingVersions = ["pasted-label-serving-v1", "pasted-label-serving-v2", "pasted-label-serving-v3"]
    static let frozenManifests = ["pasted-nutrition-label-v1", "pasted-nutrition-label-v2"]
    static let frozenPipelines: [(String, String)] = [
        ("pasted-nutrition-label-v1", "nutrition-label-text-parser-v2:label-capture-decline-gate-v2:label-arithmetic-checks-v1:pasted-label-conversions-v1"),
        ("pasted-nutrition-label-v1", "nutrition-label-text-parser-v3:label-capture-decline-gate-v2:label-arithmetic-checks-v1:pasted-label-conversions-v1"),
        ("pasted-nutrition-label-v2", "nutrition-label-text-parser-v3:label-capture-decline-gate-v2:label-arithmetic-checks-v2:pasted-label-conversions-v1"),
    ]

    /// One line per rule, in a fixed order, sorted where the source is a set or a dictionary.
    static func ruleTableListing() -> String {
        var lines: [String] = []
        func add(_ section: String, _ items: [String]) { lines.append("## " + section); lines.append(contentsOf: items) }

        add("versions", [NutritionLabelTextParserV3.version, TaiwanRowAliases.version, LabelArithmeticChecksV2.version,
                         PastedLabelServingPolicy.per100VersionV3, PastedLabelManifestV2.version])
        add("taiwan-row-aliases-v1", TaiwanRowAliases.table.keys.sorted().map { key in
            let entry = TaiwanRowAliases.table[key]!
            return "\(key)\t\(entry.row)\t\(entry.parent ?? "-")\t\(entry.templateUnit ?? "-")"
        })
        add("recognised-not-stored", TaiwanRowAliases.recognisedNotStored)
        add("voluntary-bracket", [TaiwanRowAliases.voluntaryBracket.expression.pattern])
        add("layout-precedence", LabelLayout.precedence.map(\.rawValue))
        add("row-markers", PatternsV3.rowMarkers + PatternsV3.hanMarkers.map(String.init))
        add("parser-approximation-words", PatternsV3.approximateWords.sorted())
        add("parser-approximation-marks", PatternsV3.approximateMarks)
        add("parser-patterns", [
            PatternsV3.servingSize, PatternsV3.servingLabelAlone, PatternsV3.servingQuantityAlone, PatternsV3.packPhrase,
            PatternsV3.packLabelAlone, PatternsV3.packQuantityAlone, PatternsV3.chinesePackPhrase, PatternsV3.servingQuantity,
            PatternsV3.per100Phrase, PatternsV3.chineseTitle, PatternsV3.ruleLine, PatternsV3.greaterThan, PatternsV3.value,
            PatternsV3.noteLine, PatternsV3.unitPair, PatternsV3.referenceSuffix,
        ].map(\.expression.pattern))
        add("bound-vocabulary", [BoundVocabulary.english.expression.pattern, BoundVocabulary.marks.expression.pattern]
            + BoundVocabulary.less.sorted())
        add("serving-v3-grammar-copy", [PastedLabelServingSizeGrammarV3.labelPattern, PastedLabelServingSizeGrammarV3.parenthesisedPattern,
                                        PastedLabelServingSizeGrammarV3.quantityPattern, PastedLabelServingSizeGrammarV3.packPhrasePattern])
        add("serving-lists", PastedLabelServingPolicy.approximateWords.sorted() + PastedLabelServingPolicy.approximateMarks
            + [PastedLabelServingPolicy.rangeMarks, PastedLabelServingPolicy.separators, PastedLabelServingPolicy.marker,
               PastedLabelServingPolicy.weightOrVolumeUnits])
        // Filtered to the frozen versions: a later version adds entries without changing these lines.
        add("serving-method-table", Self.frozenParsers.map { parser in
            let methods = PastedLabelServingPolicy.methods(parserVersion: parser)
            return "\(parser)\t\(methods?.perServing ?? "none")\t\(methods?.per100 ?? "none")"
        } + Self.frozenServingVersions.map { "\($0)\tadmitted=\(PastedLabelServingPolicy.admittedVersions.contains($0))" })
        add("admitted-pipelines", Self.frozenPipelines.map { manifest, pipeline in
            "\(manifest)\t\(pipeline)\tadmitted=\(PastedLabelSource.admittedPipelines[manifest]?.contains(pipeline) == true)"
        })
        add("manifest-versions", Self.frozenManifests.map { "\($0)\tadmitted=\(PastedLabelEvidenceManifest.versions.contains($0))" })
        add("basis-options", [1, 2].flatMap { columns in
            [PastedLabelBasisOptions.ServingUnit.none, .grams, .millilitres].map { unit in
                let options = PastedLabelBasisOptions.options(amountColumnCount: columns, servingUnit: unit)
                return "\(columns)\t\(unit.rawValue)\t" + (options.map { $0.map(\.identifier).joined(separator: " | ") } ?? "nil")
            }
        })
        add("checks-v2", [LabelArithmeticChecksV2.checkName] + LabelArithmeticChecksV2.macronutrientRows
            + ["\(LabelArithmeticChecksV2.kjPerKcal)", "\(LabelArithmeticChecksV2.relativeTolerance)",
               "\(LabelArithmeticChecksV2.gramFloor)", "\(LabelArithmeticChecksV2.kcalFloor)"])
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: 3. Frozen source files

    /// Paths relative to the FoodLedgerKit package root: the frozen versions' own files, the files
    /// the fresh-set harness uses to read and bind values (`LabelReading`, `PastedLabelSource`,
    /// `PastedLabelConfirmation`, the adapter) and the committed harness and scorer.
    static let frozenSources: [String: String] = [
        "Sources/NutritionLabelParsing/FlattenedLine.swift": "2671cb5d9f3b216c9190303e16207495be5dfccd242423542efdcf0b11d8cead",
        "Sources/NutritionLabelParsing/LabelArithmeticChecks.swift": "8f361669e8dba5bb935e8af3af0b5effa2c9a06ef8632388738adb9d9def600d",
        "Sources/NutritionLabelParsing/LabelArithmeticChecksV2.swift": "41f98bbdf7ca21781960c2ddf0ce38fb807cf4e032f1679cbdc8f14eb7620f6f",
        "Sources/NutritionLabelParsing/LabelCaptureCandidate.swift": "65722296a95944d0c6d32505beb35f469c0906cd7782fed769aa0c6a5576c76f",
        "Sources/NutritionLabelParsing/LabelDeclineGate.swift": "d2c1eab81eb12f9e1ff214c2c95bc3e59256ac96405b86e898e39d0f1c0c9641",
        "Sources/NutritionLabelParsing/LabelGateTables.swift": "8c5edded49fa704191b1c5a0a3bb1314300d5ffbac6897a8fe3a0d33c88a9d0a",
        "Sources/NutritionLabelParsing/LabelLayout.swift": "ae4b89d642c1a488eb19f84d0e4be47f023d0c0c1093120e3fab694fe92f06c8",
        "Sources/NutritionLabelParsing/LabelVocabulary.swift": "0792d7c351f58f967e21ba0c34cc551c245d9421dd9455a6b371035e8409260d",
        "Sources/NutritionLabelParsing/NutritionLabelTextParser.swift": "128334fc1a7fa862cdecfdf42e12fc97253aaa9ee8d454dfb450cc3fbaa37e02",
        "Sources/NutritionLabelParsing/NutritionLabelTextParserV3.swift": "346a10f5fd56be2071394014cdf514892dac8b1e92a129e152dc430af4a5fcf4",
        "Sources/NutritionLabelParsing/PastedLabelConversions.swift": "2c66ea89ce968d339151d2a21bcb9202c1a487f0921d9efd13f88fe3a724de9d",
        "Sources/NutritionLabelParsing/TaiwanRowAliases.swift": "57d9a6ee8fc52c2f47880c3a56cc0a3dc164a15e91f9b96d1bcdbc5daec10b6d",
        "Sources/NutritionLabelParsing/Resources/gate-v2-marker-classes-v1.txt": "65761772f268b4c7ec41d096ebd4ac9f01f10a1fe5e8bf7144898781f7855109",
        "Sources/NutritionLabelParsing/Resources/gate-v2-simplified-only-v1.txt": "a75bd032fb24c234686bc808ab1926cc502380f8421d2ba833bdceffb9dfafa5",
        "Sources/FoodLedgerApplication/PastedLabelManifest.swift": "ab2f9fd1a8d080801dc65b37f6a6ef889d147d7590914c01f846dc429e67d8ba",
        "Sources/FoodLedgerApplication/LabelReading.swift":"b082f9c0a26b31c4a463ba3123cc748bc2b224110b6d7b1c406793b83db2ebb7",
        "Sources/FoodLedgerApplication/PastedLabelSource.swift": "fdb22210774a02783817b2fc76d8b4238929d4863da113a248e1a3e65a36afd4",
        "Sources/FoodLedgerApplication/PastedLabelConfirmation.swift": "4f62b0b53b8a3f2e3856375e9eab2828239838b0a178317dd25f00c820d8a677",
        "Sources/FoodLabelTextCapture/NutritionLabelTextReader.swift": "d442eef620f913c51434777f5a7db54f4caaf9e7c3a52f9c705a1c22aea471b6",
        "Tests/FoodLabelTextCaptureTests/FreshSet/FreshSetProtocol.swift": "bc11c69d9e0dc15cb2cc102a9d9c200b0b82428317a8b736bd390a9d7a27fd99",
        "Tests/FoodLabelTextCaptureTests/FreshSet/FreshSetStepTests.swift": "42a5bf8d4c1bd2f96a3629f8a04c976ef7626027098b2f6ffef079dd2eaf4864",
        "Sources/FoodLedgerApplication/PastedLabelBasisChoice.swift": "4b36617823f0ab5236dc13587e1a0c62f73a77b4f826c891f844b85fccefc13f",
        "Sources/FoodLedgerApplication/PastedLabelManifestV2.swift": "dd2e1a7e6288efac802d7545716d781a15cec89c9b55d662591cd3448b95bdf5",
        "Sources/FoodLedgerApplication/PastedLabelServingPolicy.swift": "bca53615081e45bb4f5470614de66aa2b5267caf37973663c41508e2d6e65cc1",
        "Sources/FoodLedgerApplication/PastedLabelServingSizeGrammarV3.swift": "baca78391070ff9ca61bcb1ee290f2223a4b19535a6611b571b3f6907221d259",
    ]

    func testFrozenSourceFilesAreUnchanged() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // Every file of the parser module is listed, so a new file there cannot slip past the freeze.
        let parserFiles = try FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent("Sources/NutritionLabelParsing").path)
            .filter { $0.hasSuffix(".swift") || $0.hasSuffix(".txt") }
            .map { "Sources/NutritionLabelParsing/" + $0 }
        XCTAssertEqual(Set(parserFiles), Set(Self.frozenSources.keys.filter { $0.hasPrefix("Sources/NutritionLabelParsing/") }))
        for (path, expected) in Self.frozenSources.sorted(by: { $0.key < $1.key }) {
            let digest = Self.sha256(try Data(contentsOf: root.appendingPathComponent(path)))
            XCTAssertEqual(digest, expected, "\(path) changed after the reader v3 freeze (section 12)")
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
