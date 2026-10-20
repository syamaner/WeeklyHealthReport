import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Reader v3 section 8.4 (PR 4): manifest v2 and its one dispatcher, the v2 verifier, the
/// tightened v1 verifier, cross-route rejection, the contract version, the options table, the
/// integer `basis_choices.at`, the asserted headers' conversions, decision 24's record, save and
/// reopen on both stores, and the reader's orchestration through the port. Contract tests 1 to 8,
/// 11, 19, 20 and 22 of 8.4.15. Every manifest here is written by hand (synthetic, not parsed).
final class PastedLabelManifestV2ContractTests: XCTestCase {
    private typealias F = PastedLabelFixtures
    private static let v2Pipeline = "nutrition-label-text-parser-v3:label-capture-decline-gate-v2:label-arithmetic-checks-v2:pasted-label-conversions-v1"
    private static let pastedText = "營養標示\n每一份量30公克\n本包裝含10份\n熱量 120大卡 400大卡\n蛋白質 3.0公克 10.0公克\n脂肪 4.5公克 15.0公克\n"
        + "碳水化合物 18.0公克 60.0公克\n鈉 60毫克 200毫克\n"
    /// The choice, one millisecond before the evidence's capture.
    private static let at: Int64 = 1_699_999_999_999

    // MARK: Fixtures

    private static func cell(_ row: String, _ nutrient: String, _ header: String, _ basis: String, _ decimal: String, _ unit: String,
                             _ canonical: String, conversion: String) -> PastedLabelManifest.Candidate.Cell {
        .init(rowID: nutrient, parentRowID: nil, nutrient: nutrient, printedLabel: row, headerID: header, basis: basis,
              printedText: decimal + unit, comparator: "=", decimalText: decimal, unit: unit, canonicalUnit: canonical, servingConversion: conversion)
    }

    /// One column (`header_1`) chosen `basis`, or two (`per_serving`, then `second`).
    private static func candidate(columns: [String], headerText: String = "", headerConversion: String? = nil,
                                  servingConversion: String = "30公克", warnings: [String] = [],
                                  reference: Bool = false) throws -> PastedLabelManifest.Candidate {
        let values: [(String, String, [String], String, String)] = [
            ("熱量", "energy_kcal", ["120", "400"], "大卡", "kcal"), ("蛋白質", "protein", ["3.0", "10.0"], "公克", "g"),
            ("脂肪", "fat", ["4.5", "15.0"], "公克", "g"), ("碳水化合物", "carbohydrate", ["18.0", "60.0"], "公克", "g"),
            ("鈉", "sodium", ["60", "200"], "毫克", "mg")
        ]
        var headers: [PastedLabelManifest.Candidate.Header] = columns.enumerated().map {
            .init(headerID: "header_\($0.offset + 1)", printedText: headerText, basis: $0.element, servingConversion: headerConversion)
        }
        var cells: [PastedLabelManifest.Candidate.Cell] = []
        for (index, basis) in columns.enumerated() {
            for value in values {
                cells.append(cell(value.0, value.1, "header_\(index + 1)", basis, value.2[columns.count == 1 ? 1 : index], value.3, value.4,
                                  conversion: basis == "per_serving" ? servingConversion : "not_applicable"))
            }
        }
        if reference {
            headers.append(.init(headerID: "header_\(columns.count + 1)", printedText: "每日參考值百分比", basis: "reference_intake", servingConversion: nil))
        }
        return .init(route: "A", inputSHA256: try F.textHash(pastedText), declined: false, declineReasons: [], wouldMarkReady: warnings.isEmpty,
                     language: "zh-Hant", servingSize: .init(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"),
                     servingsPerPack: .init(printedText: "本包裝含10份", decimalText: "10", approximate: false),
                     headers: headers, cells: cells, warnings: warnings)
    }

    private static func offered(_ columns: Int) -> [String] {
        columns == 1 ? ["per_serving", "per_100g", "per_100ml"] : ["per_serving,per_100g", "per_serving,per_100ml"]
    }

    private static func v2(columns: [String] = ["per_100g"], candidate: PastedLabelManifest.Candidate? = nil,
                           choices: [PastedLabelManifestV2.BasisChoice]? = nil, offered: [String]? = nil, at: Int64 = at,
                           warningsShown: [String] = [], arithmetic: String = "label-arithmetic-checks-v2") throws -> PastedLabelManifestV2 {
        let candidate = try candidate ?? self.candidate(columns: columns)
        let amount = candidate.headers.filter { $0.basis != "reference_intake" }
        let records = choices ?? amount.map {
            .init(headerID: $0.headerID, basis: $0.basis, offered: offered ?? self.offered(amount.count), at: at)
        }
        let stored = amount.first { $0.basis != "per_serving" } ?? amount[0]
        let basis: ResolutionBasis = switch stored.basis {
        case "per_100g": .per100Grams
        case "per_100ml": .per100Millilitres
        default: .perServing(try PositiveQuantity(value: 30, unit: .grams))
        }
        return PastedLabelManifestV2(pastedText: pastedText, pastedTextSHA256: try F.textHash(pastedText),
            parserVersion: PastedLabelSource.parserVersionV3, gateVersion: PastedLabelSource.gateVersion, arithmeticVersion: arithmetic,
            conversionVersion: PastedLabelSource.conversionVersion, labelFormat: "taiwan_nutrition_labelling",
            launchScope: ["taiwan_nutrition_labelling"], identityMapping: try .init(fortificationAnswer: .no, servingBasis: basis),
            candidate: candidate, storedHeaderID: stored.headerID, conversions: [], flagsShown: [], corrections: [],
            warningsShown: warningsShown, name: "Synthetic chosen biscuits", brand: nil, basisChoices: records)
    }

    private static func input(_ manifest: PastedLabelEvidenceManifest, capturedAt: Date = LedgerFixtures.date) throws -> PopulatedFoodConfirmation {
        try PastedLabelSource.confirmation(manifest: manifest, evidenceID: LedgerFixtures.id(9_500, EvidenceTag.self), capturedAt: capturedAt,
            locale: LedgerText("zh_TW"), encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester,
            conversions: GoldenPastedLabelConversions())
    }

    private static func verifies(_ manifest: PastedLabelEvidenceManifest) -> Bool { (try? input(manifest)) != nil }

    private static func data(_ manifest: PastedLabelEvidenceManifest) throws -> Data { try LedgerFixtures.encoder.encode(manifest) }

    // MARK: 1. Golden round-trips; 22. the v2 schema version

    func test1ManifestV2RoundTripsByteForByteWithOneAndTwoColumns() throws {
        for (columns, golden) in [(["per_100g"], Self.oneColumnGoldenSHA256), (["per_serving", "per_100g"], Self.twoColumnGoldenSHA256)] {
            let manifest = PastedLabelEvidenceManifest.v2(try Self.v2(columns: columns))
            let bytes = try Self.data(manifest)
            let text = String(decoding: bytes, as: UTF8.self)
            XCTAssertEqual(try LedgerFixtures.digester.sha256(bytes).value, golden, "\(columns)")
            XCTAssertTrue(text.contains(#""version":"pasted-nutrition-label-v2""#))
            XCTAssertTrue(text.contains(#""offered":["# + Self.offered(columns.count).map { "\"\($0)\"" }.joined(separator: ",") + "]"), text)
            XCTAssertTrue(text.contains(#""at":1699999999999"#), "at is a JSON integer")
            XCTAssertTrue(text.contains(#""printed_text":"""#), "an asserted header has empty printed text")
            let decoded = try XCTUnwrap(PastedLabelEvidenceManifest.decode(bytes))
            XCTAssertEqual(decoded, manifest)
            XCTAssertEqual(try Self.data(decoded), bytes)
            let input = try Self.input(manifest)
            XCTAssertEqual(input.sourceReleases[0].schemaVersion.value, "pasted-nutrition-label-v2:taiwan_nutrition_labelling")
            XCTAssertEqual(input.sourceReleases[0].pipelineVersion.value, Self.v2Pipeline)
            XCTAssertEqual(input.evidence[0].captureMethodVersion.value, "pasted-nutrition-label-v2")
        }
        // v1 is unchanged: its goldens (PR 1) keep their bytes and never gain basis_choices.
        let v1 = try F.data(F.manifest(parserVersion: PastedLabelSource.parserVersionV3))
        XCTAssertEqual(try LedgerFixtures.digester.sha256(v1).value, PastedLabelReaderV3ContractTests.parserV3ManifestGoldenSHA256)
        XCTAssertFalse(String(decoding: v1, as: UTF8.self).contains("basis_choices"))
    }

    static let oneColumnGoldenSHA256 = "729c25ec486b6ce85402d3f6af6f574c0a6cdf47d960ff33b8b4be4ff08f89eb"
    static let twoColumnGoldenSHA256 = "4ccd6ca2fb17132dd15bb8493be4482d7b82451e3b36dd75a80530871b51127c"

    // MARK: 2. Version dispatch

    func test2EachVersionDecodesOnlyThroughItsOwnType() throws {
        let v1Bytes = try F.data(F.manifest())
        let v2Bytes = try Self.data(.v2(Self.v2()))
        XCTAssertEqual(PastedLabelEvidenceManifest.versions, ["pasted-nutrition-label-v1", "pasted-nutrition-label-v2"])
        guard case .v1 = PastedLabelEvidenceManifest.decode(v1Bytes) else { return XCTFail("v1") }
        guard case .v2 = PastedLabelEvidenceManifest.decode(v2Bytes) else { return XCTFail("v2") }
        XCTAssertNil(PastedLabelManifest.decode(v2Bytes), "the v1 type never decodes v2 bytes")
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(PastedLabelManifestV2.self, from: v1Bytes), "the v2 type never decodes v1 bytes")
        func replacing(_ data: Data, _ from: String, _ to: String) -> Data {
            Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: from, with: to).utf8)
        }
        // A v1 manifest relabelled v2 lacks basis_choices; a v2 manifest relabelled v1 has an unknown key.
        XCTAssertNil(PastedLabelEvidenceManifest.decode(replacing(v1Bytes, "pasted-nutrition-label-v1", "pasted-nutrition-label-v2")))
        XCTAssertNil(PastedLabelEvidenceManifest.decode(replacing(v2Bytes, "pasted-nutrition-label-v2", "pasted-nutrition-label-v1")))
        XCTAssertNil(PastedLabelEvidenceManifest.decode(replacing(v2Bytes, "pasted-nutrition-label-v2", "pasted-nutrition-label-v3")))
        // basis_choices records decode strictly, and never empty.
        XCTAssertNil(PastedLabelEvidenceManifest.decode(replacing(v2Bytes, #""at":1699999999999,"#, #""at":1699999999999,"note":"x","#)))
        XCTAssertNil(PastedLabelEvidenceManifest.decode(try Self.data(.v2(Self.v2(choices: [])))))
    }

    // MARK: 20. basis_choices.at

    func test20AtIsAnIntegerTruncatedAtStampingAndNoLaterThanTheCapture() throws {
        let bytes = try Self.data(.v2(Self.v2()))
        let fractional = Data(String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: #""at":1699999999999"#, with: #""at":1699999999999.5"#).utf8)
        XCTAssertNil(PastedLabelEvidenceManifest.decode(fractional), "a non-integer at is rejected")
        XCTAssertEqual(PastedLabelBasisChoice.milliseconds(Date(timeIntervalSince1970: 1_700_000_000.123_9)), 1_700_000_000_123)
        XCTAssertEqual(PastedLabelBasisChoice.milliseconds(Date(timeIntervalSince1970: 1_700_000_000.999_9)), 1_700_000_000_999)
        // Every whole millisecond survives the millisecondsSince1970 Double round trip unchanged.
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        for k in stride(from: Int64(1_700_000_000_000), to: 1_700_000_020_000, by: 1) {
            let date = Date(timeIntervalSince1970: Double(k) / 1000)
            let back = try decoder.decode([Date].self, from: encoder.encode([date]))[0]
            XCTAssertEqual(PastedLabelBasisChoice.milliseconds(date), k)
            XCTAssertEqual(PastedLabelBasisChoice.milliseconds(back), k)
        }
        XCTAssertTrue(Self.verifies(.v2(try Self.v2(at: 1_700_000_000_000))), "at equal to the capture")
        XCTAssertFalse(Self.verifies(.v2(try Self.v2(at: 1_700_000_000_001))), "at after the capture")
    }

    // MARK: 3. The v2 verifier

    func test3TheV2VerifierChecksEveryRule() throws {
        XCTAssertTrue(Self.verifies(.v2(try Self.v2())))
        XCTAssertTrue(Self.verifies(.v2(try Self.v2(columns: ["per_serving", "per_100g"]))))
        XCTAssertTrue(Self.verifies(.v2(try Self.v2(columns: ["per_serving"]))))
        XCTAssertTrue(Self.verifies(.v2(try Self.v2(candidate: Self.candidate(columns: ["per_100ml"], reference: true)))),
                      "a printed reference header keeps its text and has no record")
        let rejected: [(String, PastedLabelManifestV2)] = [
            ("printed amount header", try Self.v2(candidate: Self.candidate(columns: ["per_100g"], headerText: "每100公克"))),
            ("header conversion", try Self.v2(candidate: Self.candidate(columns: ["per_serving"], headerConversion: "30公克"))),
            ("record basis differs", try Self.v2(choices: [.init(headerID: "header_1", basis: "per_100ml", offered: Self.offered(1), at: Self.at)])),
            ("record header differs", try Self.v2(choices: [.init(headerID: "header_2", basis: "per_100g", offered: Self.offered(1), at: Self.at)])),
            ("reference record", try Self.v2(candidate: Self.candidate(columns: ["per_100g"], reference: true),
                choices: [.init(headerID: "header_1", basis: "per_100g", offered: Self.offered(1), at: Self.at),
                          .init(headerID: "header_2", basis: "reference_intake", offered: Self.offered(1), at: Self.at)])),
            ("missing record", try Self.v2(columns: ["per_serving", "per_100g"],
                choices: [.init(headerID: "header_1", basis: "per_serving", offered: Self.offered(2), at: Self.at)])),
            ("records out of order", try Self.v2(columns: ["per_serving", "per_100g"],
                choices: [.init(headerID: "header_2", basis: "per_100g", offered: Self.offered(2), at: Self.at),
                          .init(headerID: "header_1", basis: "per_serving", offered: Self.offered(2), at: Self.at)])),
            ("offered differs between records", try Self.v2(columns: ["per_serving", "per_100g"],
                choices: [.init(headerID: "header_1", basis: "per_serving", offered: Self.offered(2), at: Self.at),
                          .init(headerID: "header_2", basis: "per_100g", offered: ["per_serving,per_100g"], at: Self.at)])),
            ("at differs between records", try Self.v2(columns: ["per_serving", "per_100g"],
                choices: [.init(headerID: "header_1", basis: "per_serving", offered: Self.offered(2), at: Self.at),
                          .init(headerID: "header_2", basis: "per_100g", offered: Self.offered(2), at: Self.at - 1)])),
            ("offered is not the options function", try Self.v2(offered: ["per_100g", "per_serving", "per_100ml"])),
            ("offered without the choice", try Self.v2(columns: ["per_100ml", "per_100g"],
                offered: ["per_serving,per_100g", "per_serving,per_100ml"])),
            ("I'm not sure offered", try Self.v2(offered: ["per_serving", "per_100g", "per_100ml", "not_sure"])),
            ("per-serving cell conversion", try Self.v2(candidate: Self.candidate(columns: ["per_serving"], servingConversion: "25公克"))),
            ("checks v1 under v2", try Self.v2(arithmetic: "label-arithmetic-checks-v1"))
        ]
        for (name, manifest) in rejected {
            XCTAssertFalse(Self.verifies(.v2(manifest)), name)
        }
        XCTAssertFalse(Self.verifies(.v2(try Self.v2().withExtra(.init(headerID: "header_2", basis: "per_100g", offered: Self.offered(1),
                                                                         at: Self.at)))), "a record naming no header")
    }

    // MARK: 19. Decision 24's record

    func test19TheHintCodeIsAdmittedOnlyWithExactlyOneHintWarningAndLast() throws {
        let hinted = try Self.candidate(columns: ["per_100g"], warnings: ["basis_hint: energy_line: (每100毫升)"])
        XCTAssertTrue(Self.verifies(.v2(try Self.v2(candidate: hinted, warningsShown: ["basis_hint:energy_line"]))))
        XCTAssertTrue(Self.verifies(.v2(try Self.v2(candidate: hinted))), "an agreeing hint records nothing")
        XCTAssertFalse(Self.verifies(.v2(try Self.v2(warningsShown: ["basis_hint:energy_line"]))), "no hint warning")
        let twice = try Self.candidate(columns: ["per_100g"], warnings: ["basis_hint: energy_line: (每100毫升)", "basis_hint: energy_line: (每100公克)"])
        XCTAssertFalse(Self.verifies(.v2(try Self.v2(candidate: twice, warningsShown: ["basis_hint:energy_line"]))))
        XCTAssertFalse(Self.verifies(.v2(try Self.v2(candidate: hinted, warningsShown: ["basis_hint:energy_line", "energy:per_100g"]))), "not last")
        XCTAssertFalse(Self.verifies(.v2(try Self.v2(candidate: hinted, warningsShown: ["basis_hint:energy_line", "basis_hint:energy_line"]))))
        // The origin is read from the record, never re-derived.
        guard case let .v2(stored) = PastedLabelEvidenceManifest.v2(try Self.v2(candidate: hinted, warningsShown: ["basis_hint:energy_line"])) else { return }
        XCTAssertEqual(PastedLabelBasisOrigin(.v2(stored)), .chosenByYou(hint: "(每100毫升)"))
        XCTAssertEqual(PastedLabelBasisOrigin(.v2(try Self.v2(candidate: hinted))), .chosenByYou(hint: nil))
        XCTAssertEqual(PastedLabelBasisOrigin(.v1(try F.manifest())), .printed)
    }

    // MARK: 4. The v1 verifier rejects an empty-text amount header

    func test4TheV1VerifierRejectsAnEmptyTextAmountHeader() throws {
        let full = try F.candidate()
        let headers = full.headers.map { $0.headerID == "h2" ? .init(headerID: "h2", printedText: "", basis: "per_100g", servingConversion: nil) : $0 }
        let emptied = PastedLabelManifest.Candidate(route: "A", inputSHA256: full.inputSHA256, declined: false, declineReasons: [],
            wouldMarkReady: true, language: full.language, servingSize: full.servingSize, servingsPerPack: full.servingsPerPack,
            headers: headers, cells: full.cells, warnings: [])
        XCTAssertNoThrow(try F.input(F.manifest()))
        XCTAssertThrowsError(try F.input(F.manifest(candidate: emptied)))
        // And v1 never shows the hint code.
        let shown = try F.manifest()
        let withHint = PastedLabelManifest(pastedText: shown.pastedText, pastedTextSHA256: shown.pastedTextSHA256, parserVersion: shown.parserVersion,
            gateVersion: shown.gateVersion, arithmeticVersion: shown.arithmeticVersion, conversionVersion: shown.conversionVersion,
            labelFormat: shown.labelFormat, launchScope: shown.launchScope, identityMapping: shown.identityMapping, candidate: shown.candidate,
            storedHeaderID: shown.storedHeaderID, conversions: shown.conversions, flagsShown: shown.flagsShown, corrections: shown.corrections,
            warningsShown: ["basis_hint:energy_line"], name: shown.name, brand: shown.brand)
        XCTAssertThrowsError(try F.input(withHint))
    }

    // MARK: 5. Cross-route rejection and relabelled versions

    func test5RelabelledVersionsAndTheReviewedWebRouteAreRejected() throws {
        let input = try Self.input(.v2(Self.v2()))
        XCTAssertTrue(PanelSourceAdmission.applies(input, candidate: input.candidates[0]))
        XCTAssertTrue(PanelSourceAdmission.verify(input, candidate: input.candidates[0], encoder: LedgerFixtures.encoder,
                                                  digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions()))
        XCTAssertFalse(FoodReviewedWebProposalPolicy.applies(input, candidate: input.candidates[0]))
        XCTAssertNil(FoodReviewedWebProposalPolicy.scope(input, candidate: input.candidates[0]))
        let v1 = try F.input(F.manifest())
        for (name, source, version) in [("v2 relabelled v1", input, "pasted-nutrition-label-v1"), ("v1 relabelled v2", v1, "pasted-nutrition-label-v2"),
                                        ("reviewed web", input, ReviewedFoodProposalConfirmation.version)] {
            let original = source.evidence[0]
            let relabelled = try CaptureEvidence(evidenceID: original.evidenceID, kind: .labelText, capturedAt: original.capturedAt,
                locale: original.locale, captureMethod: original.captureMethod, captureMethodVersion: LedgerText(version),
                originalPayload: original.originalPayload, byteHash: original.byteHash)
            let swapped = try PopulatedFoodConfirmation(evidence: [relabelled], sourceReleases: source.sourceReleases, candidates: source.candidates,
                expectedIdentity: source.expectedIdentity, expectedEdibleQuantity: source.expectedEdibleQuantity)
            XCTAssertFalse(PastedLabelSource.verify(swapped, candidate: swapped.candidates[0], encoder: LedgerFixtures.encoder,
                                                    digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions()), name)
            XCTAssertFalse(PanelSourceAdmission.verify(swapped, candidate: swapped.candidates[0], encoder: LedgerFixtures.encoder,
                                                       digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions()), name)
        }
        let reviewed = try ReviewedWebFixtures.v1Fixture("representative-serving").input
        XCTAssertFalse(PastedLabelSource.verify(reviewed, candidate: reviewed.candidates[0], encoder: LedgerFixtures.encoder,
                                                digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions()))
    }

    // MARK: 6. The contract version (decision 26)

    func test6BothManifestVersionsNeedContract7() throws {
        let v2 = try Self.input(.v2(Self.v2()))
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: LedgerMutation(evidence: v2.evidence)), 7)
        let v1 = try F.input(F.manifest())
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: LedgerMutation(evidence: v1.evidence)), 7)
    }

    // MARK: 8. The options function

    func test8TheOptionsTableIsClosed() {
        typealias O = PastedLabelBasisOptions
        func ids(_ columns: Int, _ unit: O.ServingUnit) -> [String]? { O.options(amountColumnCount: columns, servingUnit: unit)?.map(\.identifier) }
        XCTAssertEqual(ids(1, .none), ["per_100g", "per_100ml"])
        XCTAssertEqual(ids(1, .grams), ["per_serving", "per_100g", "per_100ml"])
        XCTAssertEqual(ids(1, .millilitres), ["per_serving", "per_100ml", "per_100g"])
        XCTAssertNil(ids(2, .none), "two columns and no serving size: no sheet")
        XCTAssertEqual(ids(2, .grams), ["per_serving,per_100g", "per_serving,per_100ml"])
        XCTAssertEqual(ids(2, .millilitres), ["per_serving,per_100ml", "per_serving,per_100g"])
        XCTAssertNil(ids(0, .grams))
        XCTAssertNil(ids(3, .grams))
        // One serving-unit mapping: exact, approximate and range sizes map by their unit.
        typealias S = PastedLabelManifest.Candidate.ServingSize
        XCTAssertEqual(O.servingUnit(S(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g")), .grams)
        XCTAssertEqual(O.servingUnit(S(printedText: "每一份量約30公克", decimalText: "30", unit: "公克", canonicalUnit: "g")), .grams)
        XCTAssertEqual(O.servingUnit(S(printedText: "每一份量25-30公克", decimalText: "25", unit: "公克", canonicalUnit: "g")), .grams)
        XCTAssertEqual(O.servingUnit(S(printedText: "每一份量250毫升", decimalText: "250", unit: "毫升", canonicalUnit: "ml")), .millilitres)
        XCTAssertEqual(O.servingUnit(S(printedText: "每一份量1包", decimalText: nil, unit: nil, canonicalUnit: nil)), .none)
        XCTAssertEqual(O.servingUnit(nil), .none)
        XCTAssertEqual(O.Arrangement(identifier: "per_serving,per_100g")?.bases, [.perServing, .per100g])
        XCTAssertNil(O.Arrangement(identifier: "reference_intake"))
        XCTAssertNil(O.Arrangement(identifier: "per_serving, per_100g"), "no spaces in the encoding")
    }

    // MARK: Save and reopen on both stores; a tampered choice fails reopen

    func testManifestV2SavesAndReopensAndATamperedChoiceFailsReopen() throws {
        let input = try Self.input(.v2(Self.v2(columns: ["per_serving", "per_100g"])))
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let saved = try service.save(F.state(input), operationID: LedgerFixtures.operationID(9_960))
            XCTAssertEqual(saved.sourceReleases.first?.pipelineVersion.value, Self.v2Pipeline, harness.name)
            XCTAssertEqual(saved.productVersion.identity.servingBasis, .per100Grams, harness.name)
            XCTAssertNotNil(try service.reopen(logItemID: saved.logItem.logItemID), harness.name)
        }
        // A changed record, with every hash rebound so only the content check can catch it, is
        // refused at save (invalidPastedLabelSource) and fails reopen (integrityFailure).
        let original = String(decoding: try Self.data(.v2(Self.v2(columns: ["per_serving", "per_100g"]))), as: UTF8.self)
        let changed = original.replacingOccurrences(of: #""basis":"per_100g","header_id":"header_2""#, with: #""basis":"per_100ml","header_id":"header_2""#)
        XCTAssertNotEqual(changed, original)
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let tamperedInput = try F.rebinding(input, manifestText: original, with: changed)
            XCTAssertThrowsError(try F.service(harness).save(F.state(tamperedInput), operationID: LedgerFixtures.operationID(9_961))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource, harness.name)
            }
            let saved = try F.service(harness).save(F.state(input), operationID: LedgerFixtures.operationID(9_962))
            let tamperedSaved = try F.rebinding(saved, manifestText: original, with: changed)
            let reopening = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: StoredReader(saved: tamperedSaved),
                clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester,
                pastedLabelConversions: GoldenPastedLabelConversions())
            XCTAssertThrowsError(try reopening.reopen(logItemID: saved.logItem.logItemID), harness.name) {
                guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\($0)") }
            }
        }
    }

    // MARK: 11. The reader's orchestration through the port

    func test11EveryOptionIsReadWithItsAssertedBasesAndAnyDeclineMeansNoSheet() throws {
        let unheaded = UnheadedTable(amountColumnCount: 1, referenceColumnPrinted: false,
            servingSize: .init(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"), servingsPerPack: nil, energyLineHint: nil)
        let declined = try reading(candidate: .init(route: "A", inputSHA256: "", declined: true, declineReasons: ["no_basis_header"],
            wouldMarkReady: false, language: "zh-Hant", servingSize: nil, servingsPerPack: nil, headers: [], cells: [], warnings: []),
            unheaded: unheaded)
        let usable = Dictionary(uniqueKeysWithValues: try ["per_serving", "per_100g", "per_100ml"].map { id in
            (id, try reading(candidate: Self.candidate(columns: [id]), stored: "header_1"))
        })
        let scripted = ScriptedLabelTextReader(unasserted: declined, asserted: usable)
        let outcome = PastedLabelReader(reader: scripted, digester: LedgerFixtures.digester).read(Self.pastedText)
        guard case let .needsBasisChoice(request) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(request.offered, ["per_serving", "per_100g", "per_100ml"])
        XCTAssertEqual(scripted.received, [nil, AssertedBases([.perServing]), AssertedBases([.per100g]), AssertedBases([.per100ml])],
                       "one unasserted read, then one read per offered option with its bases")
        // One option declining (here the launch scope) means no sheet: its codes stand.
        var failing = usable
        failing["per_100g"] = try reading(candidate: Self.candidate(columns: ["per_100g"]), stored: "header_1", format: "uk_nutrition_declaration")
        let noSheet = PastedLabelReader(reader: ScriptedLabelTextReader(unasserted: declined, asserted: failing), digester: LedgerFixtures.digester)
            .read(Self.pastedText)
        XCTAssertEqual(noSheet.declineCodes, ["layout_not_supported"])
        // Without an unheaded table, or with other decline codes, today's decline stands and nothing is asserted.
        let plain = ScriptedLabelTextReader(unasserted: try reading(candidate: declined.candidate, unheaded: nil), asserted: usable)
        XCTAssertEqual(PastedLabelReader(reader: plain, digester: LedgerFixtures.digester).read(Self.pastedText).declineCodes, ["no_basis_header"])
        XCTAssertEqual(plain.received, [nil])
    }

    // MARK: 20. A re-stamped at survives save and reopen on both stores

    /// Final review of #284: when the clock moved backwards, `at` is the capture's whole
    /// milliseconds; after the store's millisecondsSince1970 round trip the check `at <= capturedAt`
    /// (whole milliseconds on both sides) still passes, on exact millisecond boundaries and with
    /// sub-millisecond parts.
    func test20AReStampedAtSavesAndReopensOnBothStores() throws {
        struct Clock: LedgerClock { let date: Date; func now() -> Date { date } }
        let unheaded = UnheadedTable(amountColumnCount: 1, referenceColumnPrinted: false,
            servingSize: .init(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"), servingsPerPack: nil, energyLineHint: nil)
        let declined = try reading(candidate: .init(route: "A", inputSHA256: "", declined: true, declineReasons: ["no_basis_header"],
            wouldMarkReady: false, language: "zh-Hant", servingSize: nil, servingsPerPack: nil, headers: [], cells: [], warnings: []),
            unheaded: unheaded)
        let asserted = Dictionary(uniqueKeysWithValues: try ["per_serving", "per_100g", "per_100ml"].map { id in
            (id, try reading(candidate: Self.candidate(columns: [id]), stored: "header_1"))
        })
        let reader = PastedLabelReader(reader: ScriptedLabelTextReader(unasserted: declined, asserted: asserted),
                                       digester: LedgerFixtures.digester)
        guard case let .needsBasisChoice(request) = reader.read(Self.pastedText) else { return XCTFail("the sheet") }
        let arrangement = try XCTUnwrap(PastedLabelBasisOptions.Arrangement(identifier: "per_100g"))
        // Captures on exact millisecond boundaries and with sub-millisecond parts, each after a
        // choice stamped later (the clock moved backwards).
        let captures: [TimeInterval] = [1_700_000_050.5, 1_700_000_050.001, 1_700_000_050.007, 1_700_000_050.123,
                                        1_700_000_050.123_456_7, 1_700_000_050.999_999, 1_791_800_000.3, 1_700_000_050]
        for (offset, capture) in captures.enumerated() {
            let builder = { (date: Date) in
                PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: Clock(date: date), encoder: LedgerFixtures.encoder,
                                        digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions())
            }
            let review = try builder(Date(timeIntervalSince1970: capture + 60)).choose(arrangement, in: request)
            let input = try builder(Date(timeIntervalSince1970: capture)).confirmation(review, details: .init(name: "Synthetic", fortification: .no),
                                                                                       corrections: [], locale: LedgerText("zh_TW"))
            let stored = try XCTUnwrap(PastedLabelValueOrigins.manifest(input, candidate: input.candidates[0]))
            XCTAssertEqual(stored.basisChoices.first?.at, PastedLabelBasisChoice.milliseconds(Date(timeIntervalSince1970: capture)), "\(capture)")
            for harness in try LedgerFixtures.harnesses() {
                defer { harness.cleanup() }
                let service = try F.service(harness)
                let saved = try service.save(F.state(input), operationID: LedgerFixtures.operationID(9_970 + offset))
                XCTAssertNotNil(try service.reopen(logItemID: saved.logItem.logItemID), "\(harness.name) \(capture)")
            }
        }
    }

    private func reading(candidate: PastedLabelManifest.Candidate, unheaded: UnheadedTable? = nil, stored: String? = nil,
                         format: String = "taiwan_nutrition_labelling") throws -> LabelReading {
        let versions = LabelReading.Versions(parser: PastedLabelSource.parserVersionV3, gate: PastedLabelSource.gateVersion,
            arithmetic: stored == nil ? PastedLabelSource.arithmeticVersion : PastedLabelSource.arithmeticVersionV2,
            conversion: PastedLabelSource.conversionVersion, formatInference: "pasted-label-format-inference-v1")
        let gate = candidate.declined ? nil : LabelReading.Gate(format: format == "taiwan_nutrition_labelling" ? "taiwan_nutrition_labelling" : format,
                                                                skipped: nil, hardDeclines: [], flags: [])
        return LabelReading(origin: .pastedText, textSHA256: try F.textHash(Self.pastedText), candidate: candidate, format: format, gate: gate,
                            checks: [], conversions: [], storedHeaderID: stored, versions: versions, unheadedTable: unheaded)
    }
}

private extension PastedLabelManifestV2 {
    /// The same manifest with one more record (a test of record counts).
    func withExtra(_ record: BasisChoice) -> PastedLabelManifestV2 {
        PastedLabelManifestV2(pastedText: pastedText, pastedTextSHA256: pastedTextSHA256, parserVersion: parserVersion, gateVersion: gateVersion,
            arithmeticVersion: arithmeticVersion, conversionVersion: conversionVersion, labelFormat: labelFormat, launchScope: launchScope,
            identityMapping: identityMapping, candidate: candidate, storedHeaderID: storedHeaderID, conversions: conversions,
            flagsShown: flagsShown, corrections: corrections, warningsShown: warningsShown, name: name, brand: brand,
            basisChoices: basisChoices + [record])
    }
}

private struct StoredReader: FoodConfirmationReading {
    let saved: StoredFoodConfirmation
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { saved.sourceReleases.first { $0.sourceReleaseID == id } }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { logItemID == saved.logItem.logItemID ? saved : nil }
    func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? {
        logItemVersionID == saved.logItemVersion.logItemVersionID ? saved : nil
    }
    func evidence(id: EvidenceID) throws -> CaptureEvidence? { saved.evidence.first { $0.evidenceID == id } }
}
