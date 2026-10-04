import Foundation
import FoodLedgerDomain

/// Foundation accepts duplicate object keys. Scan keys first so ambiguous provider
/// JSON cannot be decoded differently by the schema checker and the typed decoder.
enum StrictFoodProposalJSON {
    static func object(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= 200_000 else { throw GenericFoodProposalError.invalidSchema }
        var scanner = KeyScanner(bytes: Array(data)); try scanner.value(depth: 0)
        scanner.space()
        guard scanner.index == scanner.bytes.count,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GenericFoodProposalError.invalidSchema
        }
        return result
    }

    static func validate(_ value: Any, schema: [String: Any]) throws {
        if let alternatives = schema["anyOf"] as? [[String: Any]] {
            guard alternatives.contains(where: { (try? validate(value, schema: $0)) != nil }) else {
                throw GenericFoodProposalError.invalidSchema
            }
            return
        }
        let types = (schema["type"] as? [String]) ?? (schema["type"] as? String).map { [$0] } ?? []
        if value is NSNull {
            guard types.contains("null") else { throw GenericFoodProposalError.invalidSchema }
        } else if let text = value as? String {
            guard types.contains("string"), text.count <= 1500 else { throw GenericFoodProposalError.invalidSchema }
        } else if let array = value as? [Any] {
            guard types.contains("array"), array.count <= 40, let items = schema["items"] as? [String: Any] else {
                throw GenericFoodProposalError.invalidSchema
            }
            for item in array { try validate(item, schema: items) }
        } else if let object = value as? [String: Any] {
            guard types.contains("object"), let properties = schema["properties"] as? [String: [String: Any]],
                  Set(object.keys) == Set(properties.keys) else { throw GenericFoodProposalError.invalidSchema }
            for (key, item) in object { try validate(item, schema: properties[key]!) }
        } else { throw GenericFoodProposalError.invalidSchema }
        if let values = schema["enum"] as? [Any] {
            guard values.contains(where: { candidate in
                if value is NSNull { return candidate is NSNull }
                return (candidate as? String).map { $0 == (value as? String) } ?? false
            }) else { throw GenericFoodProposalError.invalidSchema }
        }
    }

    private struct KeyScanner {
        let bytes: [UInt8]
        var index = 0
        var nodes = 0
        mutating func space() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        mutating func consume(_ byte: UInt8) throws {
            space()
            guard index < bytes.count, bytes[index] == byte else { throw GenericFoodProposalError.invalidSchema }
            index += 1
        }
        mutating func string() throws -> String {
            space(); let start = index; try consume(34)
            while index < bytes.count {
                if bytes[index] == 92 { index += 2; continue }
                if bytes[index] == 34 {
                    index += 1
                    guard let value = try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: [.fragmentsAllowed]) as? String else {
                        throw GenericFoodProposalError.invalidSchema
                    }
                    return value
                }
                index += 1
            }
            throw GenericFoodProposalError.invalidSchema
        }
        mutating func value(depth: Int) throws {
            nodes += 1; space()
            guard depth <= 64, nodes <= 20_000, index < bytes.count else { throw GenericFoodProposalError.invalidSchema }
            switch bytes[index] {
            case 34: _ = try string()
            case 123:
                index += 1; space(); var keys = Set<String>()
                if index < bytes.count, bytes[index] == 125 { index += 1; return }
                while true {
                    let key = try string()
                    guard keys.insert(key).inserted else { throw GenericFoodProposalError.invalidSchema }
                    try consume(58); try value(depth: depth + 1); space()
                    guard index < bytes.count else { throw GenericFoodProposalError.invalidSchema }
                    if bytes[index] == 125 { index += 1; return }
                    try consume(44)
                }
            case 91:
                index += 1; space()
                if index < bytes.count, bytes[index] == 93 { index += 1; return }
                while true {
                    try value(depth: depth + 1); space()
                    guard index < bytes.count else { throw GenericFoodProposalError.invalidSchema }
                    if bytes[index] == 93 { index += 1; return }
                    try consume(44)
                }
            default:
                let start = index
                while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw GenericFoodProposalError.invalidSchema }
            }
        }
    }
}
