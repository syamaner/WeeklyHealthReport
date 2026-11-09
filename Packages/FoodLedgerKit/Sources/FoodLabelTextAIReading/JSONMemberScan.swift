import Foundation

/// A small scan of raw JSON bytes that finds a member name repeated within one object (Qodo
/// finding 1 on A2). Names are compared after JSON unescaping, so `"a"` and `"a"` are the same
/// member. It fails closed: bytes it cannot scan as JSON, or nesting deeper than `maximumDepth`,
/// are treated as having duplicates. It decides nothing else; the strict decoder does the rest.
enum JSONMemberScan {
    static let maximumDepth = 128

    static func hasNoDuplicateMembers(_ data: Data) -> Bool {
        var scanner = Scanner(bytes: Array(data))
        guard scanner.value(depth: 0) else { return false }
        scanner.skipSpace()
        return scanner.index == scanner.bytes.count
    }

    struct Scanner {
        let bytes: [UInt8]
        var index = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipSpace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        /// One value; false when the bytes are not JSON or an object repeats a member.
        mutating func value(depth: Int) -> Bool {
            guard depth <= JSONMemberScan.maximumDepth else { return false }
            skipSpace()
            guard index < bytes.count else { return false }
            switch bytes[index] {
            case UInt8(ascii: "{"): return object(depth: depth + 1)
            case UInt8(ascii: "["): return array(depth: depth + 1)
            case UInt8(ascii: "\""): return string() != nil
            default: return scalar()
            }
        }

        mutating func object(depth: Int) -> Bool {
            index += 1
            var names: Set<String> = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return true }
            while true {
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\""), let name = string(), names.insert(name).inserted else { return false }
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return false }
                index += 1
                guard value(depth: depth) else { return false }
                skipSpace()
                guard index < bytes.count else { return false }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return true }
                return false
            }
        }

        mutating func array(depth: Int) -> Bool {
            index += 1
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return true }
            while true {
                guard value(depth: depth) else { return false }
                skipSpace()
                guard index < bytes.count else { return false }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return true }
                return false
            }
        }

        /// A string token, unescaped through JSONSerialization; nil when it is not one.
        mutating func string() -> String? {
            let start = index
            index += 1
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\\"): index += 2
                case UInt8(ascii: "\""):
                    index += 1
                    let token = Data(bytes[start..<index])
                    return (try? JSONSerialization.jsonObject(with: token, options: [.fragmentsAllowed])) as? String
                default: index += 1
                }
            }
            return nil
        }

        /// A number, `true`, `false` or `null`: the run of bytes up to a delimiter (validated by the decoder).
        mutating func scalar() -> Bool {
            let start = index
            while index < bytes.count, ![UInt8(ascii: ","), UInt8(ascii: "]"), UInt8(ascii: "}"), 0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
                index += 1
            }
            return index > start
        }
    }
}
