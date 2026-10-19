import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// The frozen parity vectors of pasted label PR 1 (`NutritionLabelParsingTests/Fixtures`), read
/// from the source tree and checked against their recorded SHA-256, so the adapter is exercised
/// on exactly the development and untouched cases the parity ports were proven on.
enum FrozenParityCases {
    struct Case {
        let id: String
        let text: String
        let declaredFormat: String
        let split: String
        let expected: [String: Any]
        /// Whether the frozen parser output for this text is a decline.
        let parserDeclined: Bool
    }

    struct FixtureError: Error, CustomStringConvertible { let description: String }

    static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NutritionLabelParsingTests/Fixtures", isDirectory: true)
    }

    static func textCases() throws -> [Case] {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("parity-cases-v1.jsonl"))
        let recorded = try String(contentsOf: fixtures.appendingPathComponent("parity-sha256-v1.txt"), encoding: .utf8)
        let hash = try SHA256Digester().sha256(data).value
        guard recorded.split(separator: "\n").contains(where: { $0.hasPrefix(hash) && $0.hasSuffix("parity-cases-v1.jsonl") }) else {
            throw FixtureError(description: "parity-cases-v1.jsonl does not match its recorded SHA-256")
        }
        return try data.split(separator: 0x0A).compactMap { line in
            guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                throw FixtureError(description: "a line is not an object")
            }
            guard object["kind"] as? String == "text" else { return nil }
            guard let id = object["id"] as? String, let text = object["text"] as? String,
                  let format = object["declared_format"] as? String, let split = object["split"] as? String,
                  let expected = object["expected"] as? [String: Any] else {
                throw FixtureError(description: "a text case is missing a member")
            }
            let declined = (object["candidate"] as? [String: Any])?["declined"] as? Bool ?? false
            return Case(id: id, text: text, declaredFormat: format, split: split, expected: expected, parserDeclined: declined)
        }
    }
}
