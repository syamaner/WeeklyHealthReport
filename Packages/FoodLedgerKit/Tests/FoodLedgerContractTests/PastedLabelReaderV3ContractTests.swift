import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Reader v3 PR 1 (`docs/pasted-nutrition-label-reader-v3.md` sections 5.2, 5.4 and 5.6): the
/// admitted pipelines (test 11), golden parser-v2 and parser-v3 manifests under v1, and
/// `pasted-label-serving-v3` with its closed parser-version method table (test 5). Every fixture
/// is synthetic. Serving v2 stays pinned, unchanged, by `PastedLabelServingV2ContractTests`.
final class PastedLabelReaderV3ContractTests: XCTestCase {
    private typealias F = PastedLabelFixtures
    private typealias P = PastedLabelServingPolicy
    private static let v2 = PastedLabelSource.parserVersionV2
    private static let v3 = PastedLabelSource.parserVersionV3

    private static func size(_ printed: String, _ decimal: String = "30", _ unit: String = "公克") -> PastedLabelManifest.Candidate.ServingSize {
        .init(printedText: printed, decimalText: decimal, unit: unit, canonicalUnit: ["毫升", "ml", "mL"].contains(unit) ? "ml" : "g")
    }

    private func state(_ input: PopulatedFoodConfirmation, _ amount: Double, _ unit: QuantityUnit) -> FoodConfirmationState {
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(amount, unit))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return state
    }

    // MARK: 11. Admitted pipelines (5.2)

    func test11AdmittedPipelinesAreExactlyTheListedStrings() throws {
        XCTAssertEqual(PastedLabelSource.admittedPipelines, [
            "pasted-nutrition-label-v1": [
                "nutrition-label-text-parser-v2:label-capture-decline-gate-v2:label-arithmetic-checks-v1:pasted-label-conversions-v1",
                "nutrition-label-text-parser-v3:label-capture-decline-gate-v2:label-arithmetic-checks-v1:pasted-label-conversions-v1"
            ]
        ], "append-only: the parser-v2 entry is kept; manifest v2's entry arrives with PR 4")
        XCTAssertEqual(PastedLabelSource.parserVersion, "nutrition-label-text-parser-v3", "a new reading writes the newest pipeline")
        XCTAssertNoThrow(try F.input(F.manifest(parserVersion: Self.v2)))
        XCTAssertNoThrow(try F.input(F.manifest(parserVersion: Self.v3)))
        XCTAssertThrowsError(try F.input(F.manifest(parserVersion: "nutrition-label-text-parser-v4")))
    }

    // MARK: 5.4. Golden manifests under v1

    func testParserV2AndParserV3ManifestsRoundTripByteForByte() throws {
        for (parser, golden) in [(Self.v2, PastedLabelContractTests.manifestGoldenSHA256), (Self.v3, Self.parserV3ManifestGoldenSHA256)] {
            let bytes = try F.data(F.manifest(parserVersion: parser))
            XCTAssertEqual(try LedgerFixtures.digester.sha256(bytes).value, golden, parser)
            let decoded = try XCTUnwrap(PastedLabelManifest.decode(bytes), parser)
            XCTAssertEqual(decoded.parserVersion, parser)
            XCTAssertEqual(try F.data(decoded), bytes, parser)
            XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains(#""version":"pasted-nutrition-label-v1""#), parser)
            XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("basis_choices"), parser)
            // Both verify and reopen through the same v1 path on both stores.
            let input = try F.input(F.manifest(parserVersion: parser))
            for harness in try LedgerFixtures.harnesses() {
                defer { harness.cleanup() }
                let service = try F.service(harness)
                let saved = try service.save(state(input, 40, .grams), operationID: LedgerFixtures.operationID(9_700))
                XCTAssertEqual(saved.sourceReleases.first?.pipelineVersion.value.hasPrefix(parser + ":"), true, "\(harness.name) \(parser)")
                XCTAssertNotNil(try service.reopen(logItemID: saved.logItem.logItemID), "\(harness.name) \(parser)")
            }
        }
    }

    static let parserV3ManifestGoldenSHA256 = "8ae35354bb9c81ceee26de57be3ceb5462661475c797cfaca92be21cb6df6f2c"

    // MARK: 5. Serving v3: the method table

    func test5TheMethodIsChosenByParserVersionFromAClosedTable() throws {
        XCTAssertEqual(P.per100VersionV3, "pasted-label-serving-v3")
        XCTAssertEqual(P.admittedVersions, ["pasted-label-serving-v1", "pasted-label-serving-v2", "pasted-label-serving-v3"])
        XCTAssertEqual(P.methods(parserVersion: Self.v2)?.perServing, "pasted-label-serving-v1")
        XCTAssertEqual(P.methods(parserVersion: Self.v2)?.per100, "pasted-label-serving-v2")
        XCTAssertEqual(P.methods(parserVersion: Self.v3)?.perServing, "pasted-label-serving-v1")
        XCTAssertEqual(P.methods(parserVersion: Self.v3)?.per100, "pasted-label-serving-v3")
        for other in ["nutrition-label-text-parser-v1", "nutrition-label-text-parser-v4", "", "NUTRITION-LABEL-TEXT-PARSER-V3"] {
            XCTAssertNil(P.methods(parserVersion: other), other)
            XCTAssertEqual(P.exactness(Self.size("每一份量30公克"), parserVersion: other), .unmatched, "no servings: \(other)")
        }
        let printed = Self.size("每一份量30公克")
        for (parser, per100) in [(Self.v2, "pasted-label-serving-v2"), (Self.v3, "pasted-label-serving-v3")] {
            let input = try F.input(F.per100Manifest(servingSize: printed, parserVersion: parser))
            XCTAssertEqual(P.method(input, candidate: input.candidates[0]), per100, parser)
            XCTAssertEqual(P.serving(input, candidate: input.candidates[0]), try PositiveQuantity(value: 30, unit: .grams), parser)
            let perServing = try F.input(F.perServingManifest(readableServingSize: true, parserVersion: parser))
            XCTAssertEqual(P.method(perServing, candidate: perServing.candidates[0]), "pasted-label-serving-v1", parser)
        }
        // An unknown parser version never verifies, so it can never save; its servings are refused.
        XCTAssertThrowsError(try F.input(F.per100Manifest(servingSize: printed, parserVersion: "nutrition-label-text-parser-v9")))
    }

    func test5ServingsSaveAndReopenUnderV3OnBothStores() throws {
        let input = try F.input(F.per100Manifest(servingSize: Self.size("每1份量30公克，本包裝含約8份"),
            servingsPerPack: .init(printedText: "每1份量30公克，本包裝含約8份", decimalText: "8", approximate: true), parserVersion: Self.v3))
        XCTAssertNil(P.wholePack(input, candidate: input.candidates[0]), "about is never a whole pack")
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let saved = try service.save(state(input, 2, .count), operationID: LedgerFixtures.operationID(9_710))
            XCTAssertEqual(saved.logItemVersion.edibleQuantity, try PositiveQuantity(value: 60, unit: .grams), harness.name)
            XCTAssertEqual(saved.productVersion.identity.servingBasis, .per100Grams)
            let conversion = try XCTUnwrap(saved.quantityConversion, harness.name)
            XCTAssertEqual(conversion.methodVersion.value, "pasted-label-serving-v3", harness.name)
            XCTAssertEqual(conversion.sourceReleaseID, input.sourceReleases[0].sourceReleaseID)
            XCTAssertEqual(conversion.evidenceID, input.evidence[0].evidenceID)
            var reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(reopened.quantity.value, 2)
            FoodConfirmationReducer.reduce(state: &reopened, action: .setQuantity(3, .count))
            let edited = try service.save(reopened, operationID: LedgerFixtures.operationID(9_711))
            XCTAssertEqual(edited.quantityConversion?.methodVersion.value, "pasted-label-serving-v3", harness.name)
            XCTAssertEqual(edited.logItemVersion.edibleQuantity, try PositiveQuantity(value: 90, unit: .grams))
        }
    }

    func test5AZeroPackCountIsNeverAWholePack() throws {
        let zero = try F.input(F.per100Manifest(servingSize: Self.size("每一份量30公克"),
            servingsPerPack: .init(printedText: "本包裝含0份", decimalText: "0", approximate: false), parserVersion: Self.v3))
        XCTAssertEqual(P.serving(zero, candidate: zero.candidates[0]), try PositiveQuantity(value: 30, unit: .grams))
        XCTAssertNil(P.wholePack(zero, candidate: zero.candidates[0]), "printed 0 is read as printed, never a whole pack")
    }

    // MARK: 5. Serving v3: the cut, the joined line, bilingual scanning and the review inputs

    func test5TheValueIsCutAtThePackPhraseAndAJoinedLineIsReadAsStored() {
        let exact = ["每一份量30公克，本包裝含約8份", "每1份量30公克 本包裝含約8份", "每一份量 30公克", "每1份量30公克／本包裝包含8份",
                     "每一份量30公克、本包裝 8 份", "每一份量30公克", "每一份量： 30 公克"]
        for line in exact {
            XCTAssertEqual(P.exactness(Self.size(line), parserVersion: Self.v3), .exact, line)
        }
        XCTAssertEqual(P.valueV3("每一份量30公克，本包裝含約8份"), "30公克")
        XCTAssertEqual(P.valueV3("每一份量30公克 / servings per container 8"), "30公克")
        XCTAssertEqual(P.valueV3("每份量30公克"), "30公克")
        // 約 in the serving value (not only in the pack phrase) is approximate.
        XCTAssertEqual(P.exactness(Self.size("每一份量約30公克，本包裝含8份"), parserVersion: Self.v3), .approximate)
        // Parser v2's grammar does not know 每1份量, so v2 cannot match it; v3 can.
        XCTAssertEqual(P.exactness(Self.size("每1份量30公克")), .unmatched)
        XCTAssertEqual(P.exactness(Self.size("每1份量30公克"), parserVersion: Self.v3), .exact)
        // A pack number is never the serving quantity.
        XCTAssertEqual(P.exactness(Self.size("每一份量1片，本包裝含8份(240公克)", "240"), parserVersion: Self.v3), .unmatched)
    }

    func test5ABilingualLineIsScannedForApproximationOutsideTheSegment() {
        XCTAssertEqual(P.exactness(Self.size("每一份量30公克 (Serving Size 30g)"), parserVersion: Self.v3), .unmatched,
                       "the bracketed quantity binds first, so a recorded 30 公克 does not match")
        XCTAssertEqual(P.exactness(Self.size("每一份量30公克 (Serving Size 30g)", "30", "g"), parserVersion: Self.v3), .exact)
        XCTAssertEqual(P.exactness(Self.size("每一份量30公克 (Serving Size about 30g)", "30", "g"), parserVersion: Self.v3), .approximate)
        XCTAssertEqual(P.exactness(Self.size("每一份量30公克 Serving size 30g approx", "30", "公克"), parserVersion: Self.v3), .approximate)
        XCTAssertEqual(P.exactness(Self.size("每一份量30公克（2片） 2 pieces", "30", "公克"), parserVersion: Self.v3), .exact)
        // v2 ignores the gloss, unchanged.
        XCTAssertEqual(P.exactness(Self.size("Serving size 30g (2 biscuits), 1 cup is about 120g", "30", "g")), .exact)
        XCTAssertEqual(P.exactness(Self.size("Serving size 30g (2 biscuits), 1 cup is about 120g", "30", "g"), parserVersion: Self.v3),
                       .approximate)
    }

    /// The three inputs left open by the last serving v2 review, decided conservatively for v3
    /// (reader v3 section 5.6, "Serving v3 inputs"), with v2's behaviour pinned unchanged.
    func test5TheServingV2ReviewInputsAreDecidedForV3AndV2IsUnchanged() {
        typealias R = P.PrintedRange
        let cases: [(String, String, String, P.Exactness, P.Exactness)] = [
            // A tilde or wave dash before a bracketed or 約/about piece count: exact, as the bracket exception.
            ("每一份量30公克～約2片", "30", "公克", .approximate, .exact),
            ("每一份量30公克～（2片）", "30", "公克", .approximate, .exact),
            ("每一份量30公克～（約2片）", "30", "公克", .approximate, .exact),
            ("每一份量30公克 〜 約 2 片", "30", "公克", .approximate, .exact),
            // The English form is bilingual, so "about" anywhere in the value is approximate.
            ("Serving size 30g ~ about 2 pieces", "30", "g", .approximate, .approximate),
            // Never a way round a range or a weight.
            ("Serving size 30g ~ 35g", "30", "g", .range(own: R(low: "30", high: "35")), .range(own: R(low: "30", high: "35"))),
            ("每一份量30公克～35公克", "30", "公克", .range(own: R(low: "30", high: "35")), .range(own: R(low: "30", high: "35"))),
            ("每一份量30公克～約35公克", "30", "公克", .approximate, .approximate),
            ("每一份量30公克～（35公克）", "30", "公克", .unmatched, .unmatched), // the bracketed 35 binds first, as in v2
            ("每一份量30公克～", "30", "公克", .approximate, .approximate),
            // A unit word between the low number and the mark is still a range.
            ("Serving size 25 grams - 30g", "30", "g", .exact, .range(own: R(low: "25", high: "30"))),
            ("Serving size 25 grams to 30 g", "30", "g", .exact, .range(own: R(low: "25", high: "30"))),
            ("Serving size 1 ounce - 28g", "28", "g", .exact, .range(own: nil)),
            // A range whose other end has no unit shows the recorded quantity with the range note.
            ("Serving size 30g - 2", "30", "g", .range(own: R(low: "30", high: "2")), .range(own: nil)),
            ("Serving size 30g~35", "30", "g", .range(own: R(low: "30", high: "35")), .range(own: nil)),
            ("Serving size 30g-35g", "30", "g", .range(own: R(low: "30", high: "35")), .range(own: R(low: "30", high: "35"))),
            ("Serving size 25-30g", "30", "g", .range(own: R(low: "25", high: "30")), .range(own: R(low: "25", high: "30"))),
            ("每一份量25公克-30克", "25", "公克", .range(own: R(low: "25", high: "30")), .range(own: R(low: "25", high: "30")))
        ]
        for (line, decimal, unit, v2, v3) in cases {
            let size = Self.size(line, decimal, unit)
            XCTAssertEqual(P.exactness(size), v2, "v2 unchanged: \(line)")
            XCTAssertEqual(P.exactness(size, parserVersion: Self.v2), v2, "v2 by parser version: \(line)")
            XCTAssertEqual(P.exactness(size, parserVersion: Self.v3), v3, "v3: \(line)")
        }
    }

    // MARK: 5. Cross-method refusal between v2 and v3

    func test5AConversionNamingTheOtherPer100MethodIsRefusedAtSaveAndFailsReopen() throws {
        let printed = Self.size("每一份量30公克")
        let v2Input = try F.input(F.per100Manifest(servingSize: printed, parserVersion: Self.v2))
        let v3Input = try F.input(F.per100Manifest(servingSize: printed, parserVersion: Self.v3), evidence: 9_102)
        for (name, input, method) in [("v3 conversion on a parser-v2 manifest", v2Input, P.per100VersionV3),
                                      ("v2 conversion on a parser-v3 manifest", v3Input, P.per100Version)] {
            var state = state(input, 2, .count)
            FoodConfirmationReducer.reduce(state: &state, action: .setConversion(QuantityConversionDraft(
                convertedQuantity: try PositiveQuantity(value: 60, unit: .grams), methodVersion: try LedgerText(method),
                sourceReleaseID: input.sourceReleases[0].sourceReleaseID, evidenceID: input.evidence[0].evidenceID)))
            XCTAssertTrue(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: QuickAddFixtures.london)
                .contains(.sourceServingsRequired), name)
            for harness in try LedgerFixtures.harnesses() {
                defer { harness.cleanup() }
                XCTAssertThrowsError(try F.service(harness).save(state, operationID: LedgerFixtures.operationID(9_720)), "\(name) \(harness.name)")
            }
        }
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let savedV2 = try service.save(state(v2Input, 2, .count), operationID: LedgerFixtures.operationID(9_730))
            let savedV3 = try service.save(state(v3Input, 2, .count), operationID: LedgerFixtures.operationID(9_731))
            XCTAssertEqual(savedV2.quantityConversion?.methodVersion.value, "pasted-label-serving-v2")
            XCTAssertEqual(savedV3.quantityConversion?.methodVersion.value, "pasted-label-serving-v3")
            let tampered = [
                ("v3 relabelled v2", try relabel(savedV3, from: "pasted-label-serving-v3", to: "pasted-label-serving-v2")),
                ("v2 relabelled v3", try relabel(savedV2, from: "pasted-label-serving-v2", to: "pasted-label-serving-v3")),
                ("unknown parser version", try relabel(savedV3, from: "nutrition-label-text-parser-v3", to: "nutrition-label-text-parser-v9"))
            ]
            for (name, saved) in tampered {
                XCTAssertThrowsError(try reopening(harness, saved).reopen(logItemID: saved.logItem.logItemID), "\(harness.name) \(name)") {
                    guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\(name): \($0)") }
                }
            }
            for saved in [savedV2, savedV3] {
                XCTAssertNotNil(try reopening(harness, saved).reopen(logItemID: saved.logItem.logItemID), harness.name)
            }
        }
    }

    private func reopening(_ harness: TestHarness, _ saved: StoredFoodConfirmation) throws -> FoodConfirmationService {
        try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: ReaderV3StoredReader(saved: saved),
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester,
            pastedLabelConversions: GoldenPastedLabelConversions())
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

private struct ReaderV3StoredReader: FoodConfirmationReading {
    let saved: StoredFoodConfirmation
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { saved.sourceReleases.first { $0.sourceReleaseID == id } }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { logItemID == saved.logItem.logItemID ? saved : nil }
    func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? {
        logItemVersionID == saved.logItemVersion.logItemVersionID ? saved : nil
    }
    func evidence(id: EvidenceID) throws -> CaptureEvidence? { saved.evidence.first { $0.evidenceID == id } }
}
