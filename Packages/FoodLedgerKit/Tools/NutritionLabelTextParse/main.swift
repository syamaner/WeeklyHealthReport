import CryptoKit
import Foundation
import NutritionLabelParsing

// Evaluation-only CLI for route A of the nutrition-label capture evaluation (#255).
// Reads a JSON array of {"id": String, "text": String} from standard input and writes
// a JSON array of {"id", "parser_version", "candidate"} to standard output. The input
// hash is the SHA-256 of the UTF-8 text, computed here so the parser stays pure.
// No network, no files, no persistence.

struct Case: Decodable {
    let id: String
    let text: String
}

struct Output: Encodable {
    let id: String
    let parserVersion: String
    let candidate: LabelCaptureCandidate

    enum CodingKeys: String, CodingKey {
        case id
        case parserVersion = "parser_version"
        case candidate
    }
}

let input = FileHandle.standardInput.readDataToEndOfFile()
let cases: [Case]
do {
    cases = try JSONDecoder().decode([Case].self, from: input)
} catch {
    FileHandle.standardError.write(Data("invalid input: \(error)\n".utf8))
    exit(2)
}
let parser = NutritionLabelTextParser()
let outputs = cases.map { item in
    let digest = SHA256.hash(data: Data(item.text.utf8)).map { String(format: "%02x", $0) }.joined()
    return Output(id: item.id, parserVersion: NutritionLabelTextParser.version, candidate: parser.parse(item.text, route: "A", inputSHA256: digest))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
FileHandle.standardOutput.write(try encoder.encode(outputs))
