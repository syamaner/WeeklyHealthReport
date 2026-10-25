import FoodLabelPhotoReading
import Foundation
import NutritionLabelParsing
import XCTest

/// Contract tests 1 and 16 (docs/label-photo-ai-prefill-v1.md 12.5 and 17.8): the Swift wire
/// mapping gives exactly the candidate the evaluation's `route_c_mapping.map_wire` gives. The
/// committed vectors are built from committed truth and synthetic answers by
/// `Tools/NutritionLabelCaptureEvaluation/export_photo_parity.py vectors`; the saved route C
/// answers stay outside the repository and are checked when `LABEL_PHOTO_PRIVATE_PARITY` names
/// the vectors `export_photo_parity.py private` wrote.
final class LabelPhotoWireMappingParityTests: XCTestCase {
    struct Vectors: Decodable {
        let version: String
        let mapping: String
        let vectors: [Vector]
    }

    struct Vector: Decodable {
        let id: String
        let inputSHA256: String
        let wire: AnyJSON?
        let wireText: String?
        let candidate: LabelCaptureCandidate

        enum CodingKeys: String, CodingKey {
            case id, wire, candidate
            case inputSHA256 = "input_sha256"
            case wireText = "wire_text"
        }
    }

    /// The wire answer kept as JSON bytes so the strict decoder reads exactly what Python mapped.
    struct AnyJSON: Decodable {
        let data: Data
        init(from decoder: any Decoder) throws {
            let value = try JSONValue(from: decoder)
            data = try JSONEncoder().encode(value)
        }
    }

    indirect enum JSONValue: Codable {
        case string(String), number(Double), bool(Bool), null, array([JSONValue]), object([String: JSONValue])
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Double.self) { self = .number(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
            else { self = .object(try container.decode([String: JSONValue].self)) }
        }
        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .string(value): try container.encode(value)
            case let .number(value): try container.encode(value)
            case let .bool(value): try container.encode(value)
            case .null: try container.encodeNil()
            case let .array(value): try container.encode(value)
            case let .object(value): try container.encode(value)
            }
        }
    }

    func check(_ vectors: Vectors, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(vectors.mapping, LabelPhotoWireMapping.version, file: file, line: line)
        var mismatches: [String] = []
        for vector in vectors.vectors {
            let bytes = vector.wireText.map { Data($0.utf8) } ?? vector.wire?.data
            guard let bytes, let wire = try? JSONDecoder().decode(LabelPhotoWire.self, from: bytes) else {
                mismatches.append("\(vector.id): wire not decoded"); continue
            }
            let mapped = LabelPhotoWireMapping.map(wire, inputSHA256: vector.inputSHA256)
            if mapped != vector.candidate { mismatches.append(vector.id) }
        }
        XCTAssertEqual(mismatches, [], file: file, line: line)
    }

    func testCommittedVectorsMatchTheReference() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "label-photo-wire-mapping-v1-vectors", withExtension: "json",
                                                  subdirectory: "Fixtures"))
        let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(vectors.vectors.count, 150)
        check(vectors)
    }

    /// The saved route C answers of the untouched and development runs (kept outside the
    /// repository): `wire_text` maps to the stored candidate byte for byte (test 16).
    func testPrivateSavedAnswersMatchWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["LABEL_PHOTO_PRIVATE_PARITY"] else {
            throw XCTSkip("LABEL_PHOTO_PRIVATE_PARITY is not set; the saved answers are kept outside the repository")
        }
        let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertGreaterThan(vectors.vectors.count, 0)
        check(vectors)
    }

    // MARK: Strict wire decoding (schema-valid only)

    let valid = #"{"declined":false,"decline_reasons":[],"language":"zh-Hant","serving_size_text":"unknown","servings_per_pack_text":"unknown","headers":[{"header_id":"h1","printed_text":"每份","basis":"per_serving"}],"rows":[{"printed_label":"熱量","nutrient":"energy_kcal","parent_nutrient":"none","values":[{"header_id":"h1","printed_text":"120大卡"}]}]}"#

    func testWireDecodingIsStrict() {
        XCTAssertNotNil(LabelPhotoWire.decode(valid))
        let broken = [
            valid.replacingOccurrences(of: #""declined":false,"#, with: ""),
            valid.replacingOccurrences(of: #""declined":false,"#, with: #""declined":false,"confidence":0.9,"#),
            valid.replacingOccurrences(of: #""language":"zh-Hant""#, with: #""language":"zh-Hans""#),
            valid.replacingOccurrences(of: #""basis":"per_serving""#, with: #""basis":"per_portion""#),
            valid.replacingOccurrences(of: #""nutrient":"energy_kcal""#, with: #""nutrient":"vitamin_c""#),
            valid.replacingOccurrences(of: #""printed_text":"120大卡"}"#, with: #""printed_text":"120大卡","box":[0,0,1,1]}"#),
            valid.replacingOccurrences(of: #""parent_nutrient":"none","#, with: ""),
            "[]", "not json"
        ]
        for text in broken { XCTAssertNil(LabelPhotoWire.decode(text), text) }
    }

    func testVersionIsPinned() {
        XCTAssertEqual(LabelPhotoWireMapping.version, "label-photo-wire-mapping-v1")
        XCTAssertEqual(LabelPhotoWire.schemaVersion, "label-photo-wire-schema-v1")
    }
}
