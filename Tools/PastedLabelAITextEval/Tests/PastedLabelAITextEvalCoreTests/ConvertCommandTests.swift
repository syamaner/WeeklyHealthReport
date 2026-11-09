import Foundation
@testable import PastedLabelAITextEvalCore
import XCTest

/// `convert` and `convert-legacy` (A3 of #416): the option checks, the held-out refusal, the case
/// ID and layout shape, and the round-trip check, on the synthetic fixtures of the converter tests
/// only. No real file was opened to write these.
final class ConvertCommandTests: XCTestCase {
    static let textSHA = String(repeating: "ab", count: 32)

    func options(set: String?, tier: String? = nil, shape: String? = nil, labelID: String? = nil) -> ConvertCommand.Options {
        .init(set: set, tier: tier, copyMethod: "scripted DOM range (Playwright)", textSHA256: Self.textSHA, layoutShape: shape, labelID: labelID)
    }

    func testConvertNamesTheCaseAndSetsTheShape() throws {
        let evalCase = try ConvertCommand.convert(EvalCaseConverterTests.uk, options(set: "uk_v1_fresh", shape: "one_value_per_line", labelID: "ukv1fresh-F01"))
        XCTAssertEqual(evalCase.labelID, "ukv1fresh-F01")
        XCTAssertEqual(evalCase.layoutShape, .oneValuePerLine)
        XCTAssertEqual(evalCase.role, .tuning)
        XCTAssertEqual(evalCase.set, .ukV1Fresh)
        XCTAssertEqual(try EvalCase.decode(try evalCase.canonicalJSON()), evalCase)
        let json = String(decoding: try evalCase.canonicalJSON(), as: UTF8.self)
        XCTAssertTrue(json.contains(#""layout_shape" : "one_value_per_line""#))
        XCTAssertTrue(json.contains(#""label_id" : "ukv1fresh-F01""#))
    }

    func testConvertWithoutOptionsKeepsTheTranscriptionLabelIDAndNoShape() throws {
        let evalCase = try ConvertCommand.convert(EvalCaseConverterTests.taiwan, options(set: "taiwan_v3_fresh"))
        XCTAssertEqual(evalCase.labelID, "tw-synthetic-01")
        XCTAssertNil(evalCase.layoutShape)
        XCTAssertEqual(try evalCase.canonicalJSON(), try EvalCaseConverter.fromTaiwan(EvalCaseConverterTests.taiwan, metadata:
            .init(set: .taiwanV3Fresh, tier: nil, copyMethod: "scripted DOM range (Playwright)", textSHA256: Self.textSHA)).canonicalJSON(),
            "no shape and no case ID leave the A1 canonical bytes unchanged")
    }

    func testUKDevelopmentFromTheTaiwanSchemaRoundTripsUnderItsNormalisation() throws {
        let evalCase = try ConvertCommand.convert(EvalCaseConverterTests.taiwan, options(set: "uk_v1_development", shape: "misaligned", labelID: "ukv1dev-U01"))
        XCTAssertEqual(evalCase.format, .uk)
        XCTAssertEqual(evalCase.layoutShape, .misaligned)
    }

    func testTheHeldOutSetIsRefused() {
        XCTAssertThrowsError(try ConvertCommand.convert(EvalCaseConverterTests.uk, options(set: "uk_v2_fresh", tier: "A"))) { error in
            XCTAssertTrue("\(error)".contains("uk_v2_fresh is the sealed held-out set"), "\(error)")
        }
    }

    func testOptionRefusals() {
        let refused: [(Data, ConvertCommand.Options)] = [
            (EvalCaseConverterTests.uk, options(set: nil)),
            (EvalCaseConverterTests.uk, options(set: "uk_v3_fresh")),
            (EvalCaseConverterTests.uk, options(set: "UK_V1_FRESH")),
            (EvalCaseConverterTests.uk, options(set: "uk_v1_fresh", shape: "two_columns")),
            (EvalCaseConverterTests.uk, options(set: "uk_v1_fresh", labelID: "../escape")),
            (EvalCaseConverterTests.uk, options(set: "uk_v1_fresh", labelID: ".hidden")),
            (EvalCaseConverterTests.uk, options(set: "uk_v1_fresh", labelID: "has space")),
            (EvalCaseConverterTests.uk, options(set: "uk_v1_fresh", labelID: "")),
            (EvalCaseConverterTests.uk, options(set: "taiwan_v3_fresh")), // a UK-schema file is not a Taiwan fresh transcription
        ]
        for (data, options) in refused {
            XCTAssertThrowsError(try ConvertCommand.convert(data, options), "\(options)")
        }
    }

    func testConvertLegacyTakesTheShapeAndCaseID() throws {
        let evalCase = try ConvertCommand.convertLegacy(LegacyConverterTests.strings, options(set: nil, shape: "one_row_per_line", labelID: "tw3dev-01"))
        XCTAssertEqual(evalCase.set, .taiwanV3Development)
        XCTAssertEqual(evalCase.labelID, "tw3dev-01")
        XCTAssertEqual(evalCase.layoutShape, .oneRowPerLine)
        XCTAssertEqual(try EvalCaseConverter.taiwanLegacyTranscription(evalCase).id, "tw3dev-01")
        XCTAssertThrowsError(try ConvertCommand.convertLegacy(LegacyConverterTests.strings, options(set: "taiwan_v3_development")))
        XCTAssertThrowsError(try ConvertCommand.convertLegacy(LegacyConverterTests.strings, options(set: nil, tier: "A")))
    }

    func testWithKeepsValidation() throws {
        let evalCase = try EvalCaseConverter.fromUK(EvalCaseConverterTests.uk, metadata: .init(set: .ukV1Fresh, tier: nil, copyMethod: "m", textSHA256: Self.textSHA))
        XCTAssertThrowsError(try evalCase.with(labelID: "", layoutShape: .other), "an empty label ID is still refused")
        let shaped = try evalCase.with(layoutShape: .unitless)
        XCTAssertEqual(shaped.labelID, evalCase.labelID)
        XCTAssertNil(try shaped.with(layoutShape: nil).layoutShape)
    }

    func testRoundTripCheckRefusesOtherBytes() throws {
        let evalCase = try EvalCaseConverter.fromUK(EvalCaseConverterTests.uk, metadata: .init(set: .ukV1Fresh, tier: nil, copyMethod: "m", textSHA256: Self.textSHA))
        XCTAssertNoThrow(try EvalCaseConverter.verifyRoundTrip(evalCase, source: EvalCaseConverterTests.uk))
        XCTAssertThrowsError(try EvalCaseConverter.verifyRoundTrip(evalCase, source: EvalCaseConverterTests.uk + Data(" ".utf8)), "other bytes, other SHA")
        XCTAssertThrowsError(try EvalCaseConverter.verifyRoundTrip(evalCase, source: EvalCaseConverterTests.taiwan))
    }
}
