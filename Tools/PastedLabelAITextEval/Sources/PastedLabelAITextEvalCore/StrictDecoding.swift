import Foundation

/// Strict decoding for the evaluation formats: a key the type does not declare is an error, so a
/// conversion never drops a field silently.
struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

func rejectUnknownKeys(_ decoder: any Decoder, allowed: [String], in type: String) throws {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    let unknown = container.allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
    guard unknown.isEmpty else {
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath,
                                                                debugDescription: "\(type): unknown keys \(unknown.joined(separator: ", "))"))
    }
}
