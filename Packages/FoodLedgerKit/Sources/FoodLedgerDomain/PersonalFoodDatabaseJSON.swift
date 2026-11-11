import Foundation

/// Text from the database file, held as its exact UTF-8 bytes. Equality, hashing and order are by
/// those bytes (so by Unicode scalar, as in Python), never by Swift `String` equality, which treats
/// canonically equivalent spellings (NFC and NFD) as equal.
struct PersonalFoodDatabaseText: Hashable, Comparable, Sendable {
    let bytes: [UInt8]

    init(bytes: [UInt8]) { self.bytes = bytes }
    init(_ ascii: StaticString) {
        bytes = ascii.withUTF8Buffer { Array($0) }
    }

    var string: String { String(decoding: bytes, as: UTF8.self) }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.bytes.lexicographicallyPrecedes(rhs.bytes) }

    func hasPrefix(_ prefix: PersonalFoodDatabaseText) -> Bool { bytes.starts(with: prefix.bytes) }
    func hasSuffix(_ suffix: [UInt8]) -> Bool { bytes.count >= suffix.count && Array(bytes.suffix(suffix.count)) == suffix }
}

/// A parsed JSON value. Objects keep their members in file order. Not `indirect`: containers hold
/// their children in arrays already, so scalars stay inline and a dense file stays small in memory.
enum PersonalFoodDatabaseJSONValue: Sendable {
    case object([(key: PersonalFoodDatabaseText, value: PersonalFoodDatabaseJSONValue)])
    case array([PersonalFoodDatabaseJSONValue])
    case string(PersonalFoodDatabaseText)
    /// May be infinite (a literal beyond the `Double` range); the codec decides what that means.
    case number(Double)
    case bool(Bool)
    case null
}

/// The strict reader for `personal-food-catalogue-v1` bytes (import v1 section 4.2), in the stages
/// and with the rule codes of the skill's `export_v1.check_bytes`: size, byte-order mark, UTF-8,
/// nesting depth, then parsing (non-JSON tokens, repeated keys, integers over 4,300 digits) and
/// finally unpaired surrogate escapes. Foundation's JSON APIs are not used: they accept repeated
/// keys and lose the number text.
enum PersonalFoodDatabaseJSON {
    static let limitBytes = 26_214_400
    /// Deepest array or object nesting accepted, the same constant as `export_v1.MAX_DEPTH`.
    static let maxDepth = 64
    /// Python refuses to convert an integer literal of more digits than this.
    static let maxIntegerDigits = 4_300
    /// Most JSON values (object keys not counted) a file may hold, the same constant as
    /// `export_v1.MAX_VALUES`. It bounds the parsed tree's memory on the phone: a real file holds far
    /// fewer values than its bytes allow, so only a dense or hostile file reaches it.
    static let maxValues = 4_000_000

    /// `valueBudget` exists for tests; production always uses `maxValues`.
    static func read(_ data: Data, valueBudget: Int = maxValues) -> Result<PersonalFoodDatabaseJSONValue, PersonalFoodDatabaseRuleCode> {
        if data.count > limitBytes { return .failure(.size) }
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return .failure(.bom) }
        guard isValidUTF8(bytes) else { return .failure(.encoding) }
        guard depthWithinLimit(bytes) else { return .failure(.json) }
        var parser = Parser(bytes: bytes, valueBudget: valueBudget)
        let value: PersonalFoodDatabaseJSONValue
        do {
            parser.skipSpace()
            value = try parser.value()
            parser.skipSpace()
            guard parser.index == bytes.count else { return .failure(.json) }
        } catch let failure as ParseFailure {
            return .failure(failure.code)
        } catch {
            return .failure(.json)
        }
        // After a successful parse, as export_v1 checks them: the value budget, then surrogates.
        if parser.overBudget { return .failure(.count) }
        return parser.sawLoneSurrogate ? .failure(.json) : .success(value)
    }

    /// Strict UTF-8 as Python decodes it: no overlong forms, no encoded surrogates, nothing above U+10FFFF.
    static func isValidUTF8(_ bytes: [UInt8]) -> Bool {
        var i = 0
        let n = bytes.count
        while i < n {
            let b0 = bytes[i]
            if b0 < 0x80 { i += 1; continue }
            let length: Int
            var lower: UInt8 = 0x80, upper: UInt8 = 0xBF
            switch b0 {
            case 0xC2...0xDF: length = 2
            case 0xE0: length = 3; lower = 0xA0
            case 0xE1...0xEC, 0xEE...0xEF: length = 3
            case 0xED: length = 3; upper = 0x9F
            case 0xF0: length = 4; lower = 0x90
            case 0xF1...0xF3: length = 4
            case 0xF4: length = 4; upper = 0x8F
            default: return false
            }
            guard i + length <= n else { return false }
            let b1 = bytes[i + 1]
            guard b1 >= lower, b1 <= upper else { return false }
            for k in 2..<max(2, length) where !(0x80...0xBF).contains(bytes[i + k]) { return false }
            i += length
        }
        return true
    }

    /// The same scan as `export_v1._depth_ok`: strings (with their escapes) are skipped whole, and an
    /// unterminated string runs to the end of the file.
    static func depthWithinLimit(_ bytes: [UInt8]) -> Bool {
        var depth = 0
        var i = 0
        let n = bytes.count
        while i < n {
            switch bytes[i] {
            case UInt8(ascii: "\""):
                i += 1
                while i < n, bytes[i] != UInt8(ascii: "\"") {
                    i += bytes[i] == UInt8(ascii: "\\") ? 2 : 1
                }
            case UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
                if depth > maxDepth { return false }
            case UInt8(ascii: "]"), UInt8(ascii: "}"):
                depth -= 1
            default:
                break
            }
            i += 1
        }
        return true
    }

    struct ParseFailure: Error {
        let code: PersonalFoodDatabaseRuleCode
        static let json = ParseFailure(code: .json)
    }

    struct Parser {
        let bytes: [UInt8]
        var index = 0
        var sawLoneSurrogate = false
        /// Every value parsed. Past the budget nothing more is stored, but parsing goes on so a
        /// later syntax error or repeated key is still reported first, as in Python.
        var valueCount = 0
        let valueBudget: Int
        var overBudget: Bool { valueCount > valueBudget }

        init(bytes: [UInt8], valueBudget: Int) {
            self.bytes = bytes
            self.valueBudget = valueBudget
        }

        mutating func skipSpace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }

        mutating func expect(_ literal: [UInt8]) throws {
            guard index + literal.count <= bytes.count, Array(bytes[index..<index + literal.count]) == literal else {
                throw ParseFailure.json
            }
            index += literal.count
        }

        mutating func value() throws -> PersonalFoodDatabaseJSONValue {
            guard let byte = peek() else { throw ParseFailure.json }
            valueCount += 1
            switch byte {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try expect(Array("true".utf8)); return .bool(true)
            case UInt8(ascii: "f"): try expect(Array("false".utf8)); return .bool(false)
            case UInt8(ascii: "n"): try expect(Array("null".utf8)); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try number()
            default: throw ParseFailure.json  // NaN, Infinity and every other token
            }
        }

        mutating func object() throws -> PersonalFoodDatabaseJSONValue {
            index += 1
            var members: [(key: PersonalFoodDatabaseText, value: PersonalFoodDatabaseJSONValue)] = []
            var seen = Set<PersonalFoodDatabaseText>()
            var repeated = false
            skipSpace()
            if peek() == UInt8(ascii: "}") { index += 1; return .object(members) }
            while true {
                skipSpace()
                guard peek() == UInt8(ascii: "\"") else { throw ParseFailure.json }
                let key = try string()
                skipSpace()
                try expect([UInt8(ascii: ":")])
                skipSpace()
                let item = try value()
                if !seen.insert(key).inserted { repeated = true }
                if !overBudget { members.append((key, item)) }
                skipSpace()
                guard let next = peek() else { throw ParseFailure.json }
                index += 1
                if next == UInt8(ascii: "}") { break }
                guard next == UInt8(ascii: ",") else { throw ParseFailure.json }
            }
            // As Python's object hook: a repeat is reported when its object closes, after any
            // parse error inside it.
            if repeated { throw ParseFailure(code: .duplicateKey) }
            return .object(members)
        }

        mutating func array() throws -> PersonalFoodDatabaseJSONValue {
            index += 1
            var items: [PersonalFoodDatabaseJSONValue] = []
            skipSpace()
            if peek() == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                skipSpace()
                let item = try value()
                if !overBudget { items.append(item) }
                skipSpace()
                guard let next = peek() else { throw ParseFailure.json }
                index += 1
                if next == UInt8(ascii: "]") { break }
                guard next == UInt8(ascii: ",") else { throw ParseFailure.json }
            }
            return .array(items)
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count else { throw ParseFailure.json }
            var v: UInt32 = 0
            for _ in 0..<4 {
                let b = bytes[index]
                let digit: UInt32
                switch b {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(b - UInt8(ascii: "0"))
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(b - UInt8(ascii: "a") + 10)
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(b - UInt8(ascii: "A") + 10)
                default: throw ParseFailure.json
                }
                v = v * 16 + digit
                index += 1
            }
            return v
        }

        static func appendUTF8(_ scalar: UInt32, to out: inout [UInt8]) {
            switch scalar {
            case ..<0x80: out.append(UInt8(scalar))
            case ..<0x800:
                out += [UInt8(0xC0 | (scalar >> 6)), UInt8(0x80 | (scalar & 0x3F))]
            case ..<0x10000:
                out += [UInt8(0xE0 | (scalar >> 12)), UInt8(0x80 | ((scalar >> 6) & 0x3F)), UInt8(0x80 | (scalar & 0x3F))]
            default:
                out += [UInt8(0xF0 | (scalar >> 18)), UInt8(0x80 | ((scalar >> 12) & 0x3F)),
                        UInt8(0x80 | ((scalar >> 6) & 0x3F)), UInt8(0x80 | (scalar & 0x3F))]
            }
        }

        mutating func string() throws -> PersonalFoodDatabaseText {
            index += 1
            var out: [UInt8] = []
            while true {
                guard let b = peek() else { throw ParseFailure.json }
                index += 1
                switch b {
                case UInt8(ascii: "\""):
                    return PersonalFoodDatabaseText(bytes: out)
                case 0x00..<0x20:
                    throw ParseFailure.json  // a raw control character, as Python's strict mode
                case UInt8(ascii: "\\"):
                    guard let e = peek() else { throw ParseFailure.json }
                    index += 1
                    switch e {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(e)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        var scalar = try hex4()
                        if (0xD800...0xDBFF).contains(scalar), index + 6 <= bytes.count,
                           bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                            let save = index
                            index += 2
                            let low = try hex4()
                            if (0xDC00...0xDFFF).contains(low) {
                                scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                            } else {
                                index = save  // the next escape stands on its own
                            }
                        }
                        if (0xD800...0xDFFF).contains(scalar) {
                            sawLoneSurrogate = true  // refused after parsing, as export_v1 does
                            scalar = 0xFFFD
                        }
                        Self.appendUTF8(scalar, to: &out)
                    default:
                        throw ParseFailure.json
                    }
                default:
                    out.append(b)  // the file is valid UTF-8, so multi-byte sequences copy through
                }
            }
        }

        mutating func number() throws -> PersonalFoodDatabaseJSONValue {
            let start = index
            func digits() -> Int {
                let from = index
                while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
                return index - from
            }
            if peek() == UInt8(ascii: "-") { index += 1 }
            let intStart = index
            if peek() == UInt8(ascii: "0") {
                index += 1
            } else if digits() == 0 {
                throw ParseFailure.json
            }
            let intDigits = index - intStart
            var isInteger = true
            if peek() == UInt8(ascii: "."), index + 1 < bytes.count,
               (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index + 1]) {
                index += 1
                _ = digits()
                isInteger = false
            }
            if let e = peek(), e == UInt8(ascii: "e") || e == UInt8(ascii: "E") {
                let save = index
                index += 1
                if let sign = peek(), sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { index += 1 }
                if digits() == 0 {
                    index = save  // as Python's scanner: "1e" is the number 1 followed by stray text
                } else {
                    isInteger = false
                }
            }
            if isInteger, intDigits > maxIntegerDigits { throw ParseFailure.json }
            // Plain ASCII JSON number syntax, which `Double` parses with correct rounding; a literal
            // out of range becomes ±infinity.
            let double = Double(String(decoding: bytes[start..<index], as: UTF8.self)) ?? .nan
            return .number(double)
        }
    }
}
