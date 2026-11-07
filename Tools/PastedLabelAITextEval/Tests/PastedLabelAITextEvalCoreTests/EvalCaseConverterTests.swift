import Foundation
@testable import PastedLabelAITextEvalCore
import XCTest

/// Contract test 15 (docs/pasted-label-ai-text-v1.md 5.1 and 11.5): the converters round-trip
/// the Taiwan and UK transcription schemas through `pasted-label-ai-text-eval-case-v1`, on
/// synthetic fixtures only (no real label, no private folder).
final class EvalCaseConverterTests: XCTestCase {
    static let textSHA = String(repeating: "ab", count: 32)

    static let taiwan = Data("""
    {"schema": "reader-v3-fresh-transcription-v1", "label_id": "tw-synthetic-01",
     "serving_size": {"number": "30", "unit": "公克"}, "servings_per_pack": {"number": "8", "approximate": true},
     "columns": [{"heading": "每份", "basis": "per_serving"}, {"heading": "每100公克", "basis": "per_100g"}],
     "rows": [
       {"label": "熱量", "nutrient": "energy_kcal", "values": [{"comparator": "=", "number": "150", "unit": "大卡"}, {"comparator": "=", "number": "500", "unit": "大卡"}]},
       {"label": "鈉", "nutrient": "sodium", "values": [{"comparator": "少於", "number": "5", "unit": "毫克"}, null]},
       {"label": "膳食纖維", "nutrient": "other", "values": [{"comparator": "=", "number": "*", "unit": "", "outside_table": true}, null]}
     ],
     "notes": ["synthetic"]}
    """.utf8)

    static let uk = Data("""
    {"schema": "uk-english-v1-fresh-transcription-v1", "label_id": "uk-synthetic-01", "panel": "uk_declaration",
     "columns": [{"heading": "Per 100g", "basis": "per_100g"}, {"heading": "%RI*", "basis": "reference_intake"}, {"heading": null, "basis": null}],
     "rows": [
       {"label": "Energy", "nutrient": "energy_kj", "values": [{"comparator": "=", "number": "1046", "unit": "kJ"}, null, null]},
       {"label": "Energy", "nutrient": "energy_kcal", "values": [{"comparator": "=", "number": "250", "unit": "kcal"}, {"comparator": "=", "number": "13", "unit": "%"}, null]},
       {"label": "Salt", "nutrient": "salt", "values": [{"comparator": "<", "number": "0.01", "unit": "g"}, null, {"comparator": "=", "number": "Trace", "unit": ""}]}
     ],
     "notes": []}
    """.utf8)

    func metadata(_ set: EvalCase.EvalSet, tier: String? = nil) -> EvalCaseConverter.Metadata {
        EvalCaseConverter.Metadata(set: set, tier: tier, copyMethod: "scripted range", textSHA256: Self.textSHA)
    }

    func testTaiwanRoundTrip() throws {
        let original = try JSONDecoder().decode(TranscriptionShapes.TaiwanTranscription.self, from: Self.taiwan)
        let evalCase = try EvalCaseConverter.fromTaiwan(Self.taiwan, metadata: metadata(.taiwanV3Fresh))
        XCTAssertEqual(evalCase.role, .tuning)
        XCTAssertEqual(evalCase.format, .taiwan)
        XCTAssertEqual(evalCase.source, EvalCase.Source(schema: "reader-v3-fresh-transcription-v1", sha256: EvalCase.sha256(Self.taiwan)))
        let decoded = try EvalCase.decode(try evalCase.canonicalJSON())
        XCTAssertEqual(decoded, evalCase)
        XCTAssertEqual(try EvalCaseConverter.taiwanTranscription(decoded), original)
        XCTAssertEqual(try decoded.canonicalJSON(), try evalCase.canonicalJSON(), "canonical bytes are stable")
        XCTAssertEqual(decoded.fields.count, 4)
        XCTAssertEqual(decoded.fields.map(\.basis), ["per_serving", "per_100g", "per_serving", "per_serving"])
    }

    func testUKRoundTripHeldOut() throws {
        let original = try JSONDecoder().decode(TranscriptionShapes.UKTranscription.self, from: Self.uk)
        let evalCase = try EvalCaseConverter.convert(Self.uk, metadata: metadata(.ukV2Fresh, tier: "A"))
        XCTAssertEqual(evalCase.role, .heldOut)
        XCTAssertEqual(evalCase.format, .uk)
        XCTAssertEqual(evalCase.expected.panel, "uk_declaration")
        let decoded = try EvalCase.decode(try evalCase.canonicalJSON())
        XCTAssertEqual(try EvalCaseConverter.ukTranscription(decoded), original)
        XCTAssertThrowsError(try EvalCaseConverter.taiwanTranscription(decoded))
        // The transcription re-encoded from the case decodes to the same transcription.
        XCTAssertEqual(try JSONDecoder().decode(TranscriptionShapes.UKTranscription.self,
                                                from: try JSONEncoder().encode(EvalCaseConverter.ukTranscription(decoded))), original)
    }

    func testUKDevelopmentInTheTaiwanSchema() throws {
        let evalCase = try EvalCaseConverter.convert(Self.taiwan, metadata: metadata(.ukV1Development, tier: "B"))
        XCTAssertEqual(evalCase.format, .uk)
        XCTAssertNil(evalCase.expected.panel)
    }

    func testRefusals() {
        // The held-out set needs a tier, and no set can be relabelled into another role or format.
        XCTAssertThrowsError(try EvalCaseConverter.fromUK(Self.uk, metadata: metadata(.ukV2Fresh)))
        XCTAssertThrowsError(try EvalCaseConverter.fromUK(Self.uk, metadata: metadata(.taiwanV3Fresh)))
        XCTAssertThrowsError(try EvalCaseConverter.fromTaiwan(Self.taiwan, metadata: metadata(.ukV2Fresh, tier: "A")))
        XCTAssertThrowsError(try EvalCaseConverter.fromTaiwan(Self.uk, metadata: metadata(.taiwanV3Fresh)), "a UK file is not the Taiwan schema")
        XCTAssertThrowsError(try EvalCaseConverter.fromTaiwan(Self.taiwan, metadata: EvalCaseConverter.Metadata(
            set: .taiwanV3Fresh, tier: nil, copyMethod: "", textSHA256: Self.textSHA)))
        XCTAssertThrowsError(try EvalCaseConverter.fromTaiwan(Self.taiwan, metadata: EvalCaseConverter.Metadata(
            set: .taiwanV3Fresh, tier: nil, copyMethod: "scripted range", textSHA256: "ABC")))
        let extraKey = Data(String(decoding: Self.uk, as: UTF8.self).replacingOccurrences(of: "\"notes\": []", with: "\"notes\": [], \"extra\": 1").utf8)
        XCTAssertThrowsError(try EvalCaseConverter.fromUK(extraKey, metadata: metadata(.ukV1Fresh)), "an undeclared key is never dropped")
        let shortRow = Data(String(decoding: Self.uk, as: UTF8.self).replacingOccurrences(
            of: "{\"comparator\": \"=\", \"number\": \"1046\", \"unit\": \"kJ\"}, null, null", with: "{\"comparator\": \"=\", \"number\": \"1046\", \"unit\": \"kJ\"}").utf8)
        XCTAssertThrowsError(try EvalCaseConverter.fromUK(shortRow, metadata: metadata(.ukV1Fresh)), "values must match the columns")
        XCTAssertThrowsError(try EvalCaseConverter.convert(Data(#"{"schema": "other"}"#.utf8), metadata: metadata(.ukV1Fresh)))
    }

    /// The fixture with one substring replaced, or a failure when the substring is absent.
    static func replacing(_ data: Data, _ old: String, _ new: String) -> Data {
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(old), old)
        return Data(text.replacingOccurrences(of: old, with: new).utf8)
    }

    func testValuesFollowTheFrozenTranscriptionRules() {
        let uk = metadata(.ukV1Fresh)
        let tw = metadata(.taiwanV3Fresh)
        let refusedUK: [(String, String, String)] = [
            (#""number": "1046", "unit": "kJ"}"#, #""number": "1046", "unit": "joules"}"#, "unit outside the table"),
            (#""comparator": "<", "number": "0.01""#, #""comparator": "about", "number": "0.01""#, "comparator outside the table"),
            (#""number": "250", "unit": "kcal"}"#, #""number": "two fifty", "unit": "kcal"}"#, "number that is not a number"),
            (#""number": "250", "unit": "kcal"}"#, #""number": "1,046", "unit": "kcal"}"#, "a comma before exactly three digits"),
            (#""number": "250", "unit": "kcal"}"#, #""number": "0.5.1", "unit": "kcal"}"#, "two decimal points"),
            (#""number": "Trace", "unit": ""}"#, #""number": "Trace", "unit": "", "outside_table": true}"#, "a class marker with outside_table"),
            (#""number": "Trace", "unit": ""}"#, #""number": "n/a", "unit": ""}"#, "a non-marker word without outside_table"),
        ]
        for (old, new, why) in refusedUK {
            XCTAssertThrowsError(try EvalCaseConverter.fromUK(Self.replacing(Self.uk, old, new), metadata: uk), why)
        }
        XCTAssertNoThrow(try EvalCaseConverter.fromUK(Self.replacing(Self.uk, #""number": "250", "unit": "kcal"}"#,
                                                                     #""number": "2,5", "unit": "kcal"}"#), metadata: uk), "a UK decimal comma")
        XCTAssertNoThrow(try EvalCaseConverter.fromUK(Self.replacing(Self.uk, #""number": "1046", "unit": "kJ"}"#,
                                                                     #""number": "1046", "unit": "joules", "outside_table": true}"#), metadata: uk),
                         "anything outside the lists is allowed with outside_table")
        let refusedTaiwan: [(String, String, String)] = [
            (#"{"number": "30", "unit": "公克"}"#, #"{"number": "30", "unit": "片"}"#, "serving size unit outside the table"),
            (#"{"number": "30", "unit": "公克"}"#, #"{"number": "約30", "unit": "公克"}"#, "serving size number"),
            (#"{"number": "8", "approximate": true}"#, #"{"number": "eight", "approximate": true}"#, "servings per pack"),
            (#""number": "150", "unit": "大卡""#, #""number": "1,5", "unit": "大卡""#, "a Taiwan comma without outside_table"),
            (#""number": "*", "unit": "", "outside_table": true"#, #""number": "*", "unit": """#, "an Amendment 3 marker without outside_table"),
            (#""comparator": "少於""#, #""comparator": "less than""#, "the UK comparator in the Taiwan table"),
        ]
        for (old, new, why) in refusedTaiwan {
            XCTAssertThrowsError(try EvalCaseConverter.fromTaiwan(Self.replacing(Self.taiwan, old, new), metadata: tw), why)
        }
        XCTAssertNoThrow(try EvalCaseConverter.fromTaiwan(Self.replacing(Self.taiwan, #""unit": "大卡"}, {"#, #""unit": "大卡/kcal"}, {"#), metadata: tw),
                         "a compound unit whose parts map to one unit (Amendment 3)")
        XCTAssertThrowsError(try EvalCaseConverter.fromUK(Self.replacing(Self.uk, #""columns": [{"heading": "Per 100g", "basis": "per_100g"}, {"heading": "%RI*", "basis": "reference_intake"}, {"heading": null, "basis": null}]"#,
                                                                         #""columns": []"#), metadata: uk), "no columns")
    }

    func testUKCommaOnACJKLabelNeedsOutsideTable() {
        let uk = metadata(.ukV1Fresh)
        let salt = #""label": "Salt", "nutrient": "salt", "values": [{"comparator": "<", "number": "0.01""#
        XCTAssertNoThrow(try EvalCaseConverter.fromUK(Self.replacing(Self.uk, salt,
            #""label": "Salt", "nutrient": "salt", "values": [{"comparator": "<", "number": "0,5""#), metadata: uk))
        XCTAssertThrowsError(try EvalCaseConverter.fromUK(Self.replacing(Self.uk, salt,
            #""label": "Salt 鹽", "nutrient": "salt", "values": [{"comparator": "<", "number": "0,5""#), metadata: uk))
        XCTAssertNoThrow(try EvalCaseConverter.fromUK(Self.replacing(Self.uk, salt,
            #""label": "Salt 鹽", "nutrient": "salt", "values": [{"comparator": "<", "number": "0,5", "outside_table": true"#), metadata: uk))
    }

    func testUKDevelopmentClassMarkersAreNormalisedAsTheFrozenConverterDoes() throws {
        let marked = Self.replacing(Self.taiwan, #""comparator": "少於", "number": "5", "unit": "毫克"}"#,
                                    #""comparator": "=", "number": "Trace", "unit": "", "outside_table": true}"#)
        let development = try EvalCaseConverter.fromTaiwan(marked, metadata: metadata(.ukV1Development, tier: "A"))
        XCTAssertEqual(development.expected.rows[1].values[0], TranscriptionShapes.Value(comparator: "=", number: "Trace", unit: ""))
        XCTAssertNil(development.expected.rows[1].values[0]?.outsideTable)
        XCTAssertEqual(development.expected.rows[2].values[0]?.outsideTable, true, "an Amendment 3 marker that is not a class marker is kept")
        XCTAssertEqual(try EvalCase.decode(try development.canonicalJSON()), development)
        // The Taiwan set keeps the file's values exactly.
        let taiwan = try EvalCaseConverter.fromTaiwan(marked, metadata: metadata(.taiwanV3Fresh))
        XCTAssertEqual(taiwan.expected.rows[1].values[0]?.outsideTable, true)
    }

    func testSetAndSchemaPairingIsClosed() {
        XCTAssertThrowsError(try EvalCaseConverter.fromTaiwan(Self.taiwan, metadata: metadata(.taiwanV3Development)),
                             "no committed harness records the Taiwan v3 development schema")
        XCTAssertThrowsError(try EvalCaseConverter.fromTaiwan(Self.taiwan, metadata: metadata(.ukV1Fresh, tier: "A")))
        XCTAssertThrowsError(try EvalCaseConverter.fromTaiwan(Self.taiwan, metadata: metadata(.ukV2Fresh, tier: "A")))
        XCTAssertThrowsError(try EvalCaseConverter.fromUK(Self.uk, metadata: metadata(.taiwanV3Development)))
        XCTAssertThrowsError(try EvalCaseConverter.fromUK(Self.uk, metadata: metadata(.taiwanV3Fresh)))
        XCTAssertNoThrow(try EvalCaseConverter.fromUK(Self.uk, metadata: metadata(.ukV1Development, tier: "A")))
        XCTAssertNoThrow(try EvalCaseConverter.fromTaiwan(Self.taiwan, metadata: metadata(.ukV1Development, tier: "A")))
        XCTAssertNoThrow(try EvalCaseConverter.fromTaiwan(Self.taiwan, metadata: metadata(.taiwanV3Fresh)))
        XCTAssertEqual(Set(EvalCase.schemas.keys), Set(EvalCase.EvalSet.allCases))
    }

    func testDecodingIsStrictAndChecksTheRole() throws {
        let evalCase = try EvalCaseConverter.fromUK(Self.uk, metadata: metadata(.ukV1Fresh, tier: "B"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try evalCase.canonicalJSON()) as? [String: Any])
        object["role"] = "held_out"
        XCTAssertThrowsError(try EvalCase.decode(try JSONSerialization.data(withJSONObject: object)), "a tuning set cannot be marked held out")
        object["role"] = "tuning"
        object["unexpected"] = true
        XCTAssertThrowsError(try EvalCase.decode(try JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "unexpected")
        XCTAssertEqual(try EvalCase.decode(try JSONSerialization.data(withJSONObject: object)), evalCase)
    }

    func testSetsAndRoles() {
        XCTAssertEqual(EvalCase.EvalSet.allCases.filter { $0.role == .heldOut }, [.ukV2Fresh])
        XCTAssertEqual(EvalCase.schema, "pasted-label-ai-text-eval-case-v1")
    }
}
