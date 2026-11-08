import Foundation
@testable import PastedLabelAITextEvalCore
import XCTest

/// The legacy converter for the Taiwan reader v3 development set's older answer format
/// (docs/pasted-label-ai-text-v1.md 5.1, contract test 15), round-tripped on synthetic fixtures
/// only. No real file was opened to write these.
final class LegacyConverterTests: XCTestCase {
    static let textSHA = String(repeating: "cd", count: 32)

    static let strings = Data("""
    {"id": "tw-dev-synthetic-01", "transcribed_by": "synthetic",
     "columns": [{"key": "per_serving", "printed": "每份"}, {"key": "c2", "printed": "每100公克"}],
     "serving_size": {"value": "30", "unit": "公克"}, "servings_per_pack": {"value": "8", "approximate": false},
     "values": [
       {"nutrient": "energy_kcal", "column": "per_serving", "value": "150", "unit": "大卡", "comparator": "="},
       {"nutrient": "sodium", "column": "c2", "value": "5", "unit": "毫克", "comparator": "少於"},
       {"nutrient": "energy_kcal", "column": "c2", "value": "500", "unit": "大卡", "comparator": "="}
     ],
     "notes": "synthetic"}
    """.utf8)

    static let numbers = Data("""
    {"id": "tw-dev-synthetic-02", "columns": [{"key": "k1", "printed": "每100毫升"}],
     "values": [{"nutrient": "protein", "column": "k1", "value": 3.5, "unit": "公克", "comparator": "="}],
     "servings_per_pack": {"value": 2, "approximate": true}, "notes": ["a", "b"]}
    """.utf8)

    func metadata() -> EvalCaseConverter.Metadata {
        .init(set: .taiwanV3Development, tier: nil, copyMethod: "owner selection", textSHA256: Self.textSHA)
    }

    func testStringValuesRoundTrip() throws {
        let original = try JSONDecoder().decode(TranscriptionShapes.TaiwanLegacyTranscription.self, from: Self.strings)
        let evalCase = try EvalCaseConverter.fromTaiwanLegacy(Self.strings, metadata: metadata())
        XCTAssertEqual(evalCase.source.schema, "reader-v3-development-transcription-legacy")
        XCTAssertEqual(evalCase.role, .tuning)
        XCTAssertEqual(evalCase.format, .taiwan)
        XCTAssertEqual(evalCase.expected.columns.map(\.basis), ["per_serving", "per_100g"], "a basis key, then the printed Taiwan heading")
        XCTAssertEqual(evalCase.expected.rows.map(\.nutrient), ["energy_kcal", "sodium"])
        XCTAssertEqual(evalCase.expected.rows[1].values, [nil, .init(comparator: "少於", number: "5", unit: "毫克")])
        XCTAssertEqual(evalCase.fields.count, 3)
        let decoded = try EvalCase.decode(try evalCase.canonicalJSON())
        XCTAssertEqual(decoded, evalCase)
        XCTAssertEqual(try decoded.canonicalJSON(), try evalCase.canonicalJSON(), "canonical bytes are stable")
        XCTAssertEqual(try EvalCaseConverter.taiwanLegacyTranscription(decoded), original)
    }

    func testNumberValuesRoundTrip() throws {
        let original = try JSONDecoder().decode(TranscriptionShapes.TaiwanLegacyTranscription.self, from: Self.numbers)
        let evalCase = try EvalCaseConverter.fromTaiwanLegacy(Self.numbers, metadata: metadata())
        XCTAssertEqual(evalCase.legacy?.numberEncoding, "number")
        XCTAssertEqual(evalCase.expected.rows[0].values[0]?.number, "3.5")
        XCTAssertEqual(evalCase.expected.columns[0].basis, "per_100ml")
        XCTAssertEqual(try EvalCaseConverter.taiwanLegacyTranscription(try EvalCase.decode(try evalCase.canonicalJSON())), original)
    }

    func testRefusals() {
        let refused = [
            #"{"id": "x", "columns": [{"key": "a", "printed": "每份"}], "values": [{"nutrient": "protein", "column": "a", "value": "1", "unit": "公克", "comparator": "="}, {"nutrient": "fat", "column": "a", "value": 2, "unit": "公克", "comparator": "="}]}"#,
            #"{"id": "x", "columns": [{"key": "a", "printed": "每份"}], "values": [{"nutrient": "protein", "column": "b", "value": "1", "unit": "公克", "comparator": "="}]}"#,
            #"{"id": "x", "columns": [{"key": "a", "printed": "每份"}], "values": [{"nutrient": "protein", "column": "a", "value": "1", "unit": "公克", "comparator": "="}, {"nutrient": "protein", "column": "a", "value": "2", "unit": "公克", "comparator": "="}]}"#,
            #"{"id": "x", "columns": [{"key": "a", "printed": "每份"}, {"key": "a", "printed": "每份"}], "values": []}"#,
            #"{"id": "x", "columns": [], "values": [], "extra": 1}"#,
            #"{"id": "x", "columns": [{"key": "a", "printed": "每份", "basis": "per_serving"}], "values": []}"#,
            #"{"id": "x", "columns": [{"key": "a", "printed": "每份"}], "values": [{"nutrient": "vitamin_c", "column": "a", "value": "1", "unit": "毫克", "comparator": "="}]}"#,
            // A basis key that disagrees with the heading it prints (A2 gate finding 11).
            #"{"id": "x", "columns": [{"key": "per_100g", "printed": "每份"}], "values": []}"#,
        ]
        for json in refused {
            XCTAssertThrowsError(try EvalCaseConverter.fromTaiwanLegacy(Data(json.utf8), metadata: metadata()), json)
        }
    }

    func testABasisKeyAgreeingWithItsHeadingOrWithAnUnknownHeadingIsKept() throws {
        let agreeing = #"{"id": "x", "columns": [{"key": "per_100g", "printed": "每100公克"}, {"key": "per_serving", "printed": "Per portion"}], "values": []}"#
        let evalCase = try EvalCaseConverter.fromTaiwanLegacy(Data(agreeing.utf8), metadata: metadata())
        XCTAssertEqual(evalCase.expected.columns.map(\.basis), ["per_100g", "per_serving"])
    }

    func testOnlyTheDevelopmentSetTakesTheLegacySchema() throws {
        for set in EvalCase.EvalSet.allCases where set != .taiwanV3Development {
            let tier: String? = set.format == .uk ? "A" : nil
            XCTAssertThrowsError(try EvalCaseConverter.fromTaiwanLegacy(Self.strings, metadata: .init(set: set, tier: tier, copyMethod: "m", textSHA256: Self.textSHA)),
                                 set.rawValue)
        }
        XCTAssertEqual(EvalCase.schemas[.taiwanV3Development], ["reader-v3-development-transcription-legacy"])
    }

    func testCasesFromOtherSchemasHaveNoLegacyMember() throws {
        let uk = try EvalCaseConverter.convert(EvalCaseConverterTests.uk, metadata: .init(set: .ukV1Fresh, tier: "A", copyMethod: "m", textSHA256: Self.textSHA))
        XCTAssertFalse(String(decoding: try uk.canonicalJSON(), as: UTF8.self).contains("legacy"))
        // A legacy member on another schema is refused.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try uk.canonicalJSON()) as? [String: Any])
        object["legacy"] = ["column_keys": [], "value_order": [], "number_encoding": "string"]
        XCTAssertThrowsError(try EvalCase.decode(try JSONSerialization.data(withJSONObject: object)))
    }
}

/// The two members A3 found when it first ran the converter on the real files, `extra` on a value
/// and `transcription_corrections` on the file, on synthetic fixtures only.
final class LegacyExtraMembersTests: XCTestCase {
    static let withExtras = Data("""
    {"id": "tw-dev-synthetic-03", "transcribed_by": "synthetic",
     "columns": [{"key": "per_serving", "printed": "每份"}],
     "values": [
       {"nutrient": "protein", "column": "per_serving", "value": "2", "unit": "公克", "comparator": "="},
       {"nutrient": "fibre", "column": "per_serving", "value": "0.5", "unit": "公克", "comparator": "=", "extra": true}
     ],
     "notes": "synthetic", "transcription_corrections": ["2026-01-01 synthetic: servings approximate"]}
    """.utf8)

    func metadata() -> EvalCaseConverter.Metadata {
        .init(set: .taiwanV3Development, tier: nil, copyMethod: "synthetic", textSHA256: LegacyConverterTests.textSHA)
    }

    func testExtraAndCorrectionsRoundTrip() throws {
        let original = try JSONDecoder().decode(TranscriptionShapes.TaiwanLegacyTranscription.self, from: Self.withExtras)
        let evalCase = try EvalCaseConverter.fromTaiwanLegacy(Self.withExtras, metadata: metadata())
        XCTAssertEqual(evalCase.legacy?.extraValues, ["fibre@per_serving"])
        XCTAssertEqual(evalCase.legacy?.transcriptionCorrections, ["2026-01-01 synthetic: servings approximate"])
        XCTAssertEqual(evalCase.fields.count, 2, "an extra value stays a printed field")
        let decoded = try EvalCase.decode(try evalCase.canonicalJSON())
        XCTAssertEqual(try EvalCaseConverter.taiwanLegacyTranscription(decoded), original)
        XCTAssertNoThrow(try EvalCaseConverter.verifyRoundTrip(decoded, source: Self.withExtras))
    }

    func testAbsentMembersLeaveTheCanonicalBytesUnchanged() throws {
        let json = String(decoding: try EvalCaseConverter.fromTaiwanLegacy(LegacyConverterTests.strings, metadata: metadata()).canonicalJSON(), as: UTF8.self)
        XCTAssertFalse(json.contains("extra_values"))
        XCTAssertFalse(json.contains("transcription_corrections"))
    }

    func testExtraFalseIsRefused() {
        let data = Data(String(decoding: Self.withExtras, as: UTF8.self).replacingOccurrences(of: #""extra": true"#, with: #""extra": false"#).utf8)
        XCTAssertThrowsError(try EvalCaseConverter.fromTaiwanLegacy(data, metadata: metadata()))
    }
}
