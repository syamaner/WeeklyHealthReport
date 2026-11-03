import CryptoKit
@testable import FoodLabelTextCapture
@testable import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
@testable import UKNutritionLabelParsing
import XCTest

/// The UK freeze (`docs/pasted-nutrition-label-uk-english-v1-p3.md` section 1): parser
/// `nutrition-label-text-parser-uk-v2`, identity `pasted-label-identity-v2`, the reading policy
/// `.ukDevelopment`, the UK reader adapter and the UK harness and scorer are frozen as of the P3
/// commit, which is the reference of the P4 release check. Any later change to what one of them
/// does is a new version and needs a new fresh set.
///
/// Three pins, as reader v3 section 12.1:
/// 1. the version strings, the guard's decline codes, the two UK schemas and `.ukDevelopment`;
/// 2. a SHA-256 of a canonical listing of the UK rule tables (`UKVocabulary`, the normalisation
///    and guard constants and patterns, identity v2's markers and the scorer's equivalence
///    tables). It must **never** change while these versions exist;
/// 3. a SHA-256 of each file the UK path reads through, comments included, held here whether or
///    not the reader v3 freeze also pins it. Every file of `UKNutritionLabelParsing` and of
///    `FoodLabelTextCapture` is listed, so a new file in either module cannot slip past, and every
///    reader v3 pinned file is listed, so neither freeze can drop one silently.
///
/// Re-pin rules are reader v3's (12.1). The one change named in advance is the P5 diff (section 6),
/// recorded with pins 1 and 2 unchanged.
///
/// Re-pins after the UK freeze: none.
///
/// No label text, value or product name is here: only rule tables and source hashes.
final class UKReaderFreezeTests: XCTestCase {
    // MARK: 1. Version strings

    func testFrozenVersionStrings() {
        XCTAssertEqual(NutritionLabelTextParserUK.version, "nutrition-label-text-parser-uk-v2")
        XCTAssertEqual(UKEnglishLabelTextReader.versions.parser, NutritionLabelTextParserUK.version)
        XCTAssertEqual(UKEnglishLabelTextReader.assertedVersions.parser, NutritionLabelTextParserUK.version)
        XCTAssertEqual(PastedLabelBasisStateV2.version, "pasted-label-identity-v2")
        XCTAssertEqual(UKReadingGuard.headerBasisUnrecognised, "uk_header_basis_unrecognised")
        XCTAssertEqual(UKReadingGuard.conflictingUnits, "uk_orphan_unit")
        XCTAssertEqual(UKReadingGuard.basisStateNotSupported, "basis_state_not_supported")
        XCTAssertEqual(UKReadingGuard.basisStateNotSupported, PastedLabelIdentity.basisStateNotSupported)
        XCTAssertEqual(UKFreshSet.transcriptionSchema, "uk-english-v1-fresh-transcription-v1")
        XCTAssertEqual(UKFreshSet.runSchema, "uk-english-v1-fresh-run-v1")
        XCTAssertEqual(PastedLabelReadingPolicy.ukDevelopment.launchScope, ["taiwan_nutrition_labelling", "uk_nutrition_declaration"])
        XCTAssertEqual(PastedLabelReadingPolicy.ukDevelopment.identity, .v2)
        XCTAssertEqual(PastedLabelReadingPolicy.ukDevelopment.identity.rawValue, PastedLabelBasisStateV2.version)
    }

    // MARK: 2. Frozen rule tables

    static let frozenRuleTablesSHA256 = "6c17e3698c426dcd23133a15b4e79a3833726b2e0a3724c978d4ba8f09fa0315"

    func testFrozenRuleTablesAreUnchanged() {
        let listing = Self.ruleTableListing()
        let digest = Self.sha256(Data(listing.utf8))
        XCTAssertEqual(digest, Self.frozenRuleTablesSHA256,
                       "A frozen UK rule table changed. That is a new version and a new fresh set (UK P3 section 1). Listing:\n\(listing)")
    }

    /// One line per rule, in a fixed order, sorted where the source is a set or a dictionary.
    static func ruleTableListing() -> String {
        var lines: [String] = []
        func add(_ section: String, _ items: [String]) { lines.append("## " + section); lines.append(contentsOf: items) }
        /// The Basic Multilingual Plane characters of a character set, as scalar values.
        func members(_ set: CharacterSet) -> [String] {
            (0..<0x10000).compactMap { Unicode.Scalar($0) }.filter(set.contains).map { String(format: "U+%04X", $0.value) }
        }

        add("versions", [NutritionLabelTextParserUK.version, PastedLabelBasisStateV2.version, UKFreshSet.transcriptionSchema,
                         UKFreshSet.runSchema])
        // UKVocabulary.
        add("uk-value-pattern", [UKVocabulary.valuePattern])
        add("uk-header-phrase-pattern", [UKVocabulary.headerPhrasePattern])
        add("uk-unit-tokens", UKVocabulary.unitTokens)
        add("uk-energy-labels", UKVocabulary.energyLabels)
        add("uk-sub-row-parents", UKVocabulary.subRowParents.keys.sorted().map { "\($0)\t\(UKVocabulary.subRowParents[$0]!)" })
        add("uk-top-level-rows", UKVocabulary.topLevelRows.map { "\($0.prefix)\t\($0.row)" })
        add("uk-identity-word-markers", UKVocabulary.identityWordMarkers)
        add("uk-identity-symbol-markers", UKVocabulary.identitySymbolMarkers)
        // Normalisation N1 to N5.
        add("normalisation-patterns", [
            UKTextNormalisation.headerPhrase, UKTextNormalisation.gramSpelling, UKTextNormalisation.millilitreSpelling,
            UKTextNormalisation.value, UKTextNormalisation.dashedOfWhich, UKTextNormalisation.underscoredOfWhich,
            UKTextNormalisation.bracketedSubRow,
        ].map(\.expression.pattern))
        add("normalisation-bracketed-label-units", UKTextNormalisation.bracketedLabelUnits)
        add("normalisation-bare-label-units", UKTextNormalisation.bareLabelUnits)
        add("normalisation-separators", members(UKTextNormalisation.separators))
        add("normalisation-energy-label-units", UKTextNormalisation.energyLabelUnits)
        add("normalisation-energy-canonical", ["kJ", "kj", "KJ", "kcal", "KCAL", "cal", "Cal", "g"].map {
            "\($0)\t\(UKTextNormalisation.canonicalEnergyUnit($0) ?? "nil")"
        })
        add("normalisation-titles", UKTextNormalisation.titles)
        // Guard G1 to G3.
        add("guard-codes", [UKReadingGuard.headerBasisUnrecognised, UKReadingGuard.conflictingUnits, UKReadingGuard.basisStateNotSupported])
        add("guard-patterns", [
            UKReadingGuard.standaloneHundred, UKReadingGuard.bracketedHundredUnit, UKReadingGuard.value, UKReadingGuard.unitToken,
            UKReadingGuard.slashJoined, UKReadingGuard.gramsOrMillilitres,
        ].map(\.expression.pattern))
        // The pinned reader's header guard, which the UK adapter's fallback reads through.
        add("pasted-header-basis-guard", [PastedHeaderBasisGuard.version, PastedHeaderBasisGuard.declineCode,
                                          PastedHeaderBasisGuard.standaloneHundred.pattern,
                                          PastedHeaderBasisGuard.hundredOfGramsOrMillilitres.pattern])
        // Identity v2.
        add("identity-v2-word-markers", PastedLabelBasisStateV2.wordMarkers)
        add("identity-v2-substring-markers", PastedLabelBasisStateV2.substringMarkers)
        add("policy-uk-development", PastedLabelReadingPolicy.ukDevelopment.launchScope + [PastedLabelReadingPolicy.ukDevelopment.identity.rawValue])
        // The UK scorer (section 3).
        add("scorer-comparators", UKFreshSet.comparatorTable.keys.sorted().map { "\($0)\t\(UKFreshSet.comparatorTable[$0]!)" })
        add("scorer-units", UKFreshSet.units.keys.sorted().map { "\($0)\t\(UKFreshSet.units[$0]!)" })
        add("scorer-markers", UKFreshSet.markers)
        add("scorer-row-markers", UKFreshSet.rowMarkers)
        add("scorer-of-which", [UKFreshSet.ofWhich])
        add("scorer-bracket-characters", UKFreshSet.bracketCharacters.map(String.init).sorted())
        add("scorer-panels", UKFreshSet.panels.sorted() + [UKFreshSet.unknownPanel])
        add("scorer-nutrients", FreshSet.nutrients.sorted())
        add("scorer-bases", FreshSet.bases.sorted())
        add("scorer-ledger-nutrients", FreshSet.ledgerNutrients)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: 3. Frozen source files

    /// Paths relative to the FoodLedgerKit package root, each with its own UK hash.
    static let frozenSources: [String: String] = [
        "Sources/FoodLabelTextCapture/NutritionLabelTextReader.swift": "88208cb37f96a22e3e53c03129bb01f281ab62be7279ccf822b558a157948642",
        "Sources/FoodLabelTextCapture/PastedHeaderBasisGuard.swift": "4dd39071a6e4142d30999f6bb0a30e4240da210558fb2dc251a8d452aba7ff9b",
        "Sources/FoodLabelTextCapture/UKEnglishLabelTextReader.swift": "7479441743aab81f9f62ed0cdf769b7dd077a2935ac67ce64a7f2191a875ffa3",
        "Sources/FoodLedgerApplication/LabelReading.swift": "eae0e1ad23f06b2517e1620b2f3007213b445b5700089d99eb021b8109881af9",
        "Sources/FoodLedgerApplication/PastedLabelBasisChoice.swift": "4b36617823f0ab5236dc13587e1a0c62f73a77b4f826c891f844b85fccefc13f",
        "Sources/FoodLedgerApplication/PastedLabelBasisStateV2.swift": "12cfc96607a57411c6fc44ab2492b7e798c9b6757aa1be796fa042faf49d1d35",
        "Sources/FoodLedgerApplication/PastedLabelConfirmation.swift": "e806b82fb5c2126e3eb205ea403389b59a054119309eb20c6ff8649fb1919afb",
        "Sources/FoodLedgerApplication/PastedLabelLaunchScope.swift": "c123d10305720aa9b6fc921658cc5493df5a65e86731736ccf1bd33bbed3b892",
        "Sources/FoodLedgerApplication/PastedLabelManifest.swift": "ab2f9fd1a8d080801dc65b37f6a6ef889d147d7590914c01f846dc429e67d8ba",
        "Sources/FoodLedgerApplication/PastedLabelManifestV2.swift": "dd2e1a7e6288efac802d7545716d781a15cec89c9b55d662591cd3448b95bdf5",
        "Sources/FoodLedgerApplication/PastedLabelServingPolicy.swift": "bca53615081e45bb4f5470614de66aa2b5267caf37973663c41508e2d6e65cc1",
        "Sources/FoodLedgerApplication/PastedLabelServingSizeGrammarV3.swift": "baca78391070ff9ca61bcb1ee290f2223a4b19535a6611b571b3f6907221d259",
        "Sources/FoodLedgerApplication/PastedLabelSource.swift": "fdb22210774a02783817b2fc76d8b4238929d4863da113a248e1a3e65a36afd4",
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
        "Sources/NutritionLabelParsing/Resources/gate-v2-marker-classes-v1.txt": "65761772f268b4c7ec41d096ebd4ac9f01f10a1fe5e8bf7144898781f7855109",
        "Sources/NutritionLabelParsing/Resources/gate-v2-simplified-only-v1.txt": "a75bd032fb24c234686bc808ab1926cc502380f8421d2ba833bdceffb9dfafa5",
        "Sources/NutritionLabelParsing/TaiwanRowAliases.swift": "57d9a6ee8fc52c2f47880c3a56cc0a3dc164a15e91f9b96d1bcdbc5daec10b6d",
        "Sources/UKNutritionLabelParsing/NutritionLabelTextParserUK.swift": "20facb6846d3e774e3fa445558d316bb08c0ca690f79e9fee0653dbd327e7a6d",
        "Sources/UKNutritionLabelParsing/UKReadingGuard.swift": "b410386b2f976946778a56b71fe9aa7d061a7dd51c7d9855020792fbbaa3c210",
        "Sources/UKNutritionLabelParsing/UKTextNormalisation.swift": "5694f5f0105678266ce282d4993835eb6f8b32e084fe526837fef57141e66e46",
        "Sources/UKNutritionLabelParsing/UKVocabulary.swift": "4ea5f3c24d197f3d11f05de9fffa521e134c013024705fea8689841c6a9f17de",
        "Tests/FoodLabelTextCaptureTests/FreshSet/FreshSetProtocol.swift": "c2ad61b6ee3cc1d331d5c8d9c6fce64f520f6b52381a42c23549b5d1fe76b40a",
        "Tests/FoodLabelTextCaptureTests/FreshSet/FreshSetStepTests.swift": "42a5bf8d4c1bd2f96a3629f8a04c976ef7626027098b2f6ffef079dd2eaf4864",
        "Tests/FoodLabelTextCaptureTests/UKFreshSet/UKFreshSetProtocol.swift": "11e5a346818bdeb1fbeb58f30f0a87a421f0ca308c8b06ea42afd9d5ab19d85d",
        "Tests/FoodLabelTextCaptureTests/UKFreshSet/UKFreshSetStepTests.swift": "b14aa527624d1cb203e87f7866443d1d22c9f449f3c0782d82b6b7bef182498f",
    ]

    static let ukHarnessFiles = [
        "Tests/FoodLabelTextCaptureTests/UKFreshSet/UKFreshSetProtocol.swift",
        "Tests/FoodLabelTextCaptureTests/UKFreshSet/UKFreshSetStepTests.swift",
    ]
    static let policyFiles = [
        "Sources/FoodLedgerApplication/PastedLabelBasisStateV2.swift",
        "Sources/FoodLedgerApplication/PastedLabelLaunchScope.swift",
    ]
    static let enumeratedModules = ["Sources/UKNutritionLabelParsing/", "Sources/FoodLabelTextCapture/"]

    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testFrozenSourceFilesAreUnchanged() throws {
        let root = Self.packageRoot
        // Every file of both modules, of every type, so a new file in either cannot slip past.
        for module in Self.enumeratedModules {
            var isDirectory: ObjCBool = false
            let files = try FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent(module).path).filter {
                FileManager.default.fileExists(atPath: root.appendingPathComponent(module + $0).path, isDirectory: &isDirectory) && !isDirectory.boolValue
            }.map { module + $0 }
            XCTAssertFalse(files.isEmpty, module)
            XCTAssertEqual(Set(files), Set(Self.frozenSources.keys.filter { $0.hasPrefix(module) }), module)
        }
        for path in Self.ukHarnessFiles + Self.policyFiles { XCTAssertNotNil(Self.frozenSources[path], path) }
        for (path, expected) in Self.frozenSources.sorted(by: { $0.key < $1.key }) {
            let digest = Self.sha256(try Data(contentsOf: root.appendingPathComponent(path)))
            XCTAssertEqual(digest, expected, "\(path) changed after the UK freeze (UK P3 section 1)")
        }
    }

    /// Every file the reader v3 freeze pins is held here too, with its own UK hash: a reader v3
    /// re-pin can be right for Taiwan and still change UK reading.
    func testEveryReaderV3PinnedFileIsInTheUKFreeze() {
        let missing = Set(ReaderV3FreezeTests.frozenSources.keys).subtracting(Self.frozenSources.keys)
        XCTAssertEqual(missing, [], "add each with its own UK hash")
        XCTAssertNotNil(Self.frozenSources["Tests/FoodLabelTextCaptureTests/FreshSet/FreshSetProtocol.swift"])
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
