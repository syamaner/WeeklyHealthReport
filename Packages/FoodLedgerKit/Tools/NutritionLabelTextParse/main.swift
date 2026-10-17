import CryptoKit
import Foundation
import NutritionLabelParsing

// Evaluation-only CLI for routes A and B of the nutrition-label capture evaluation (#255).
// Reads a JSON array of {"id": String, "text": String, "route"?: "A" | "B",
// "input_sha256"?: String} from standard input and writes a JSON array of
// {"id", "parser_version", "candidate"} to standard output. Route A (the default) hashes
// the UTF-8 text here so the parser stays pure; route B passes the image hash, because
// its scored input is the photo, not the serialised text. No network, no files, no persistence.

struct Case: Decodable {
    let id: String
    let text: String
    let route: String?
    let inputSHA256: String?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case route
        case inputSHA256 = "input_sha256"
    }
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
if let bad = cases.first(where: { !["A", "B"].contains($0.route ?? "A") || ($0.route == "B" && $0.inputSHA256 == nil) }) {
    FileHandle.standardError.write(Data("invalid route or missing input_sha256 for \(bad.id)\n".utf8))
    exit(2)
}
let outputs = cases.map { item in
    let route = item.route ?? "A"
    let digest = route == "B" ? item.inputSHA256! : SHA256.hash(data: Data(item.text.utf8)).map { String(format: "%02x", $0) }.joined()
    return Output(id: item.id, parserVersion: NutritionLabelTextParser.version, candidate: parser.parse(item.text, route: route, inputSHA256: digest))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
FileHandle.standardOutput.write(try encoder.encode(outputs))
