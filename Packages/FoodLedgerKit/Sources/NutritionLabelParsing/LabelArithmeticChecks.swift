import Foundation

/// One cell as the arithmetic checks see it. Fields are the candidate's (or truth's) strings,
/// not enums, so the checks behave exactly like the Python reference on any input.
public struct LabelArithmeticCell: Equatable, Sendable {
    public var nutrient: String
    public var basis: String
    public var canonicalUnit: String
    public var comparator: String
    public var decimalText: String?
    public var parentRowID: String?
    public var unit: String
    public var printedText: String

    public init(nutrient: String, basis: String, canonicalUnit: String, comparator: String, decimalText: String?, parentRowID: String?, unit: String, printedText: String) {
        self.nutrient = nutrient
        self.basis = basis
        self.canonicalUnit = canonicalUnit
        self.comparator = comparator
        self.decimalText = decimalText
        self.parentRowID = parentRowID
        self.unit = unit
        self.printedText = printedText
    }

    public init(_ cell: LabelCell) {
        self.init(
            nutrient: cell.nutrient,
            basis: cell.basis.rawValue,
            canonicalUnit: cell.canonicalUnit,
            comparator: cell.comparator.rawValue,
            decimalText: cell.decimalText,
            parentRowID: cell.parentRowID,
            unit: cell.unit,
            printedText: cell.printedText
        )
    }
}

/// The table the arithmetic checks run on: a candidate, or verified truth for the mutation families.
public struct LabelArithmeticTable: Equatable, Sendable {
    public struct Serving: Equatable, Sendable {
        public var decimalText: String?
        public var canonicalUnit: String?
        public init(decimalText: String?, canonicalUnit: String?) {
            self.decimalText = decimalText
            self.canonicalUnit = canonicalUnit
        }
    }

    public struct PerPack: Equatable, Sendable {
        public var decimalText: String?
        public var approximate: Bool
        public init(decimalText: String?, approximate: Bool) {
            self.decimalText = decimalText
            self.approximate = approximate
        }
    }

    /// `uk`, `taiwan` or `us`; see `LabelArithmeticChecks.jurisdiction`.
    public var jurisdiction: String
    public var declined: Bool
    public var servingSize: Serving?
    public var servingsPerPack: PerPack?
    public var cells: [LabelArithmeticCell]

    public init(jurisdiction: String, declined: Bool, servingSize: Serving?, servingsPerPack: PerPack?, cells: [LabelArithmeticCell]) {
        self.jurisdiction = jurisdiction
        self.declined = declined
        self.servingSize = servingSize
        self.servingsPerPack = servingsPerPack
        self.cells = cells
    }

    /// A candidate on the jurisdiction of its gate format (Taiwan or UK).
    public init(_ candidate: LabelCaptureCandidate, format: LabelGateFormat) {
        self.init(
            jurisdiction: format == .taiwan ? "taiwan" : "uk",
            declined: candidate.declined,
            servingSize: candidate.servingSize.map { Serving(decimalText: $0.decimalText, canonicalUnit: $0.canonicalUnit) },
            servingsPerPack: candidate.servingsPerPack.map { PerPack(decimalText: $0.decimalText, approximate: $0.approximate) },
            cells: candidate.cells.map(LabelArithmeticCell.init)
        )
    }
}

public enum LabelCheckStatus: String, Codable, Sendable {
    case pass
    case fail
    case notCheckable = "not_checkable"
}

/// One check's outcome, with the same fields the Python reference records.
public struct LabelCheckResult: Equatable, Sendable {
    public struct EnergyForm: Equatable, Sendable {
        public var form: String
        public var computedKcal: Decimal
        public var difference: Decimal
    }

    public var name: String
    public var basis: String?
    public var status: LabelCheckStatus
    public var nutrient: String?
    public var child: String?
    public var printedKcal: Decimal?
    public var allowedDifference: Decimal?
    public var forms: [EnergyForm]?
    public var ratio: Decimal?
    public var perServing: Decimal?
    public var expected: Decimal?
    public var slack: Decimal?

    init(name: String, basis: String? = nil, status: LabelCheckStatus) {
        self.name = name
        self.basis = basis
        self.status = status
    }
}

public struct LabelArithmeticReport: Equatable, Sendable {
    public var status: LabelCheckStatus
    public var checks: [LabelCheckResult]
    /// Non-blocking warnings. A pass adds nothing and is never shown as confirmation.
    public var warnings: [String]
}

/// Swift port of the arithmetic and consistency checks (`label-arithmetic-checks-v1`, a port of
/// `Tools/NutritionLabelCaptureEvaluation/arithmetic.py`, the evaluation's frozen section 7 policy).
///
/// Checks run on printed values only and never change, fill or remove a value. A failure is a
/// warning; a pass shows nothing. Inputs that are bounds, unknowns or unparseable make a check
/// `not_checkable`, never zero. Arithmetic follows Python `decimal` with its default context:
/// sums and products are exact, and the one division (`kJ / kcal`) is rounded half-even to 28
/// significant digits as Python does.
public enum LabelArithmeticChecks {
    public static let version = "label-arithmetic-checks-v1"

    struct Tolerance {
        let absoluteKcal: Decimal
        let relative: Decimal
    }

    static let tolerances: [String: Tolerance] = [
        "uk": Tolerance(absoluteKcal: 15, relative: decimal("0.10")),
        "taiwan": Tolerance(absoluteKcal: 15, relative: decimal("0.10")),
        "us": Tolerance(absoluteKcal: 20, relative: decimal("0.20")),
    ]
    static let kjPerKcal = decimal("4.184")
    static let kjRatioRelative = decimal("0.02")
    static let amountBases = ["per_100g", "per_100ml", "per_serving"]
    public static let mutations = ["tenfold_serving", "basis_transposition", "bound_replaced_by_exact"]

    /// Python `jurisdiction_for`: a declared jurisdiction, else Taiwan for `zh-Hant` or `mixed`, else UK.
    public static func jurisdiction(declared: String?, language: String?) -> String {
        if let declared, tolerances[declared] != nil { return declared }
        return language == "zh-Hant" || language == "mixed" ? "taiwan" : "uk"
    }

    // MARK: Checks

    /// Python `check_table`: every informing check. Overall fail if any check fails, else pass if any passes.
    public static func check(_ table: LabelArithmeticTable, netQuantity: Decimal? = nil) -> LabelArithmeticReport {
        if table.declined { return LabelArithmeticReport(status: .notCheckable, checks: [], warnings: []) }
        let bases = Set(table.cells.map(\.basis).filter { amountBases.contains($0) }).sorted(by: pythonStringPrecedes)
        var checks: [LabelCheckResult] = []
        for basis in bases {
            checks.append(energyCheck(table, basis: basis))
            checks.append(kjKcalCheck(table, basis: basis))
            checks.append(contentsOf: subrowChecks(table, basis: basis))
        }
        checks.append(contentsOf: scalingChecks(table))
        checks.append(contentsOf: boundConsistencyChecks(table))
        checks.append(netWeightCheck(table, netQuantity: netQuantity))
        let statuses = Set(checks.map(\.status))
        let status: LabelCheckStatus = statuses.contains(.fail) ? .fail : statuses.contains(.pass) ? .pass : .notCheckable
        var warnings: [String] = []
        if checks.contains(where: { $0.name == "energy" && $0.status == .fail }) {
            warnings.append("energy does not match the macronutrients")
        }
        if checks.contains(where: { $0.name != "energy" && $0.status == .fail }) {
            warnings.append("printed values are not arithmetically consistent")
        }
        return LabelArithmeticReport(status: status, checks: checks, warnings: warnings)
    }

    static func exactValue(_ cells: [LabelArithmeticCell], _ nutrient: String, _ unit: String, _ basis: String) -> Decimal? {
        let matching = cells.filter { $0.nutrient == nutrient && $0.basis == basis && $0.canonicalUnit == unit }
        guard matching.count == 1, matching[0].comparator == "=" else { return nil }
        return number(matching[0].decimalText)
    }

    static func energyCheck(_ table: LabelArithmeticTable, basis: String) -> LabelCheckResult {
        let cells = table.cells
        guard let kcal = exactValue(cells, "energy_kcal", "kcal", basis),
              let p = exactValue(cells, "protein", "g", basis),
              let f = exactValue(cells, "fat", "g", basis),
              let c = exactValue(cells, "carbohydrate", "g", basis) else {
            return LabelCheckResult(name: "energy", basis: basis, status: .notCheckable)
        }
        let fibre = exactValue(cells, "fibre", "g", basis)
        let fibrePrinted = cells.contains { $0.nutrient == "fibre" && $0.basis == basis }
        var forms: [(String, Decimal)] = []
        if table.jurisdiction == "taiwan" {
            // Taiwan carbohydrate includes fibre; with a fibre row only the Taiwan form is used.
            if fibrePrinted {
                guard let fibre else { return LabelCheckResult(name: "energy", basis: basis, status: .notCheckable) }
                forms.append(("taiwan", 4 * p + 4 * (c - fibre) + 2 * fibre + 9 * f))
            } else {
                forms.append(("general", 4 * p + 4 * c + 9 * f))
            }
        } else {
            forms.append(("general", 4 * p + 4 * c + 9 * f))
            if let fibre, table.jurisdiction == "uk" {
                forms.append(("uk_fibre", 4 * p + 4 * c + 9 * f + 2 * fibre))
            }
        }
        let tolerance = tolerances[table.jurisdiction] ?? tolerances["uk"]!
        let allowed = Swift.max(tolerance.absoluteKcal, tolerance.relative * kcal)
        var result = LabelCheckResult(name: "energy", basis: basis, status: forms.contains { abs($0.1 - kcal) <= allowed } ? .pass : .fail)
        result.printedKcal = kcal
        result.allowedDifference = allowed
        result.forms = forms.map { LabelCheckResult.EnergyForm(form: $0.0, computedKcal: $0.1, difference: abs($0.1 - kcal)) }
        return result
    }

    static func kjKcalCheck(_ table: LabelArithmeticTable, basis: String) -> LabelCheckResult {
        guard let kj = exactValue(table.cells, "energy_kj", "kJ", basis),
              let kcal = exactValue(table.cells, "energy_kcal", "kcal", basis) else {
            return LabelCheckResult(name: "kj_kcal_ratio", basis: basis, status: .notCheckable)
        }
        if kcal == 0 {
            return LabelCheckResult(name: "kj_kcal_ratio", basis: basis, status: kj == 0 ? .pass : .fail)
        }
        let ratio = PythonDecimalContext.divide(kj, kcal)
        var result = LabelCheckResult(name: "kj_kcal_ratio", basis: basis, status: abs(ratio - kjPerKcal) <= kjPerKcal * kjRatioRelative ? .pass : .fail)
        result.ratio = ratio
        return result
    }

    static func servingQuantity(_ table: LabelArithmeticTable) -> (Decimal, String)? {
        guard let size = table.servingSize, let value = number(size.decimalText), let unit = size.canonicalUnit,
              unit == "g" || unit == "ml", value > 0 else { return nil }
        return (value, unit)
    }

    static func scalingChecks(_ table: LabelArithmeticTable) -> [LabelCheckResult] {
        guard let (grams, unit) = servingQuantity(table) else { return [LabelCheckResult(name: "serving_scaling", status: .notCheckable)] }
        let hundredBasis = unit == "g" ? "per_100g" : "per_100ml"
        var results: [LabelCheckResult] = []
        for serving in table.cells where serving.basis == "per_serving" && serving.canonicalUnit != "%" {
            let partner = table.cells.filter {
                $0.basis == hundredBasis && $0.nutrient == serving.nutrient && $0.canonicalUnit == serving.canonicalUnit && $0.parentRowID == serving.parentRowID
            }
            guard partner.count == 1 else { continue }
            let hundred = partner[0]
            guard serving.comparator == "=", hundred.comparator == "=",
                  let s = number(serving.decimalText), let h = number(hundred.decimalText),
                  let servingText = serving.decimalText, let hundredText = hundred.decimalText else { continue }
            let expected = h * grams / 100
            let slack = decimal("0.5") * power10(-decimals(servingText)) + decimal("0.5") * power10(-decimals(hundredText)) * grams / 100
            var result = LabelCheckResult(name: "serving_scaling", status: abs(s - expected) <= slack + decimal("1e-9") ? .pass : .fail)
            result.nutrient = serving.nutrient
            result.perServing = s
            result.expected = expected
            result.slack = slack
            results.append(result)
        }
        return results.isEmpty ? [LabelCheckResult(name: "serving_scaling", status: .notCheckable)] : results
    }

    static func subrowChecks(_ table: LabelArithmeticTable, basis: String) -> [LabelCheckResult] {
        var pairs = [("saturates", "fat"), ("trans_fat", "fat"), ("sugars", "carbohydrate")]
        if table.jurisdiction == "taiwan" { pairs.append(("fibre", "carbohydrate")) }
        var results: [LabelCheckResult] = []
        for (child, parent) in pairs {
            if let a = exactValue(table.cells, child, "g", basis), let b = exactValue(table.cells, parent, "g", basis) {
                var result = LabelCheckResult(name: "subrow_not_above_parent", basis: basis, status: a <= b ? .pass : .fail)
                result.child = child
                results.append(result)
            }
        }
        return results
    }

    /// A nutrient printed as a bound in one amount column and exact in another is flagged.
    /// Keys are visited in Python's `sorted(keys, key=str)` order (the `repr` of the tuple).
    static func boundConsistencyChecks(_ table: LabelArithmeticTable) -> [LabelCheckResult] {
        let cells = table.cells.filter { amountBases.contains($0.basis) }
        struct Key: Hashable {
            let nutrient: String
            let parent: String?
            let unit: String
            var pythonString: String { "(\(pythonRepr(nutrient)), \(parent.map(pythonRepr) ?? "None"), \(pythonRepr(unit)))" }
        }
        var comparators: [Key: Set<String>] = [:]
        for cell in cells {
            comparators[Key(nutrient: cell.nutrient, parent: cell.parentRowID, unit: cell.canonicalUnit), default: []].insert(cell.comparator)
        }
        return comparators.keys
            .sorted { pythonStringPrecedes($0.pythonString, $1.pythonString) }
            .filter { (comparators[$0]?.count ?? 0) > 1 }
            .map { key in
                var result = LabelCheckResult(name: "bound_consistency", status: .fail)
                result.nutrient = key.nutrient
                return result
            }
    }

    static func netWeightCheck(_ table: LabelArithmeticTable, netQuantity: Decimal?) -> LabelCheckResult {
        guard let netQuantity, let quantity = servingQuantity(table), let perPack = table.servingsPerPack, !perPack.approximate,
              let count = number(perPack.decimalText) else {
            return LabelCheckResult(name: "net_weight", status: .notCheckable)
        }
        return LabelCheckResult(name: "net_weight", status: abs(count * quantity.0 - netQuantity) <= quantity.0 ? .pass : .fail)
    }

    // MARK: Frozen mutations

    /// Python `mutate`: one frozen mutation applied to verified truth, or `nil` when it does not apply.
    public static func mutate(_ table: LabelArithmeticTable, _ mutation: String) -> LabelArithmeticTable? {
        var mutated = table
        switch mutation {
        case "tenfold_serving":
            for index in mutated.cells.indices {
                let cell = mutated.cells[index]
                guard cell.basis == "per_serving", cell.comparator == "=", cell.canonicalUnit != "%" else { continue }
                if let text = cell.decimalText, let value = PythonDecimalText(text.replacingOccurrences(of: ",", with: ".")), !value.isZero {
                    mutated.cells[index].decimalText = value.timesTen().description
                    mutated.cells[index].printedText = (mutated.cells[index].decimalText ?? "") + cell.unit
                    return mutated
                }
            }
            return nil
        case "basis_transposition":
            let bases = Set(mutated.cells.map(\.basis))
            guard bases.contains("per_serving"), bases.contains("per_100g"), let quantity = servingQuantity(mutated), quantity.0 != 100 else { return nil }
            for index in mutated.cells.indices {
                switch mutated.cells[index].basis {
                case "per_serving": mutated.cells[index].basis = "per_100g"
                case "per_100g": mutated.cells[index].basis = "per_serving"
                default: break
                }
            }
            return mutated
        case "bound_replaced_by_exact":
            for index in mutated.cells.indices where ["<", "<="].contains(mutated.cells[index].comparator) {
                mutated.cells[index].comparator = "="
                mutated.cells[index].printedText = (mutated.cells[index].decimalText ?? "") + mutated.cells[index].unit
                return mutated
            }
            return nil
        default:
            return nil
        }
    }

    /// Python `mutation_detection`: (applicable, detected) per mutation over tables whose originals pass.
    public static func mutationDetection(_ tables: [LabelArithmeticTable]) -> [String: (applicable: Int, detected: Int)] {
        var outcome: [String: (applicable: Int, detected: Int)] = [:]
        for mutation in mutations {
            var applicable = 0
            var detected = 0
            for table in tables where check(table).status != .fail {
                guard let mutated = mutate(table, mutation) else { continue }
                applicable += 1
                if check(mutated).status == .fail { detected += 1 }
            }
            outcome[mutation] = (applicable, detected)
        }
        return outcome
    }

    // MARK: Numbers

    /// Python `number`: a `Decimal` from printed decimal text (comma read as a point), else `nil`.
    /// Accepts the plain and exponent forms; Python's `NaN`, `Infinity`, underscores and non-ASCII
    /// digits are not accepted, which never matters for schema-valid `decimal_text`.
    static func number(_ text: String?) -> Decimal? {
        guard let text, !text.isEmpty, let parsed = PythonDecimalText(text.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return parsed.decimal
    }

    /// Python `decimals`: digits after the first point.
    static func decimals(_ text: String) -> Int {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        guard let point = cleaned.firstIndex(of: ".") else { return 0 }
        return cleaned[cleaned.index(after: point)...].count
    }

    static func power10(_ exponent: Int) -> Decimal {
        Decimal(sign: .plus, exponent: exponent, significand: 1)
    }

    static func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }
}

/// Python `repr` of a `str`, for the bound-consistency sort key.
func pythonRepr(_ text: String) -> String {
    let quote: Character = text.contains("'") && !text.contains("\"") ? "\"" : "'"
    var out = String(quote)
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\\": out += "\\\\"
        case "\t": out += "\\t"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        default:
            if Character(scalar) == quote {
                out += "\\" + String(quote)
            } else if scalar.value < 0x20 || scalar.value == 0x7F {
                out += String(format: "\\x%02x", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    out.append(quote)
    return out
}

/// A decimal number as Python `decimal.Decimal` holds it (coefficient digits and exponent), so
/// `str()` of a mutated value is reproduced exactly (`Decimal("2.5") * 10` is `25.0`).
struct PythonDecimalText: Equatable, Sendable {
    var negative: Bool
    var digits: [UInt8]
    var exponent: Int

    init?(_ text: String) {
        var scalars = Substring(text).unicodeScalars[...]
        while let first = scalars.first, first.properties.isWhitespace { scalars = scalars.dropFirst() }
        while let last = scalars.last, last.properties.isWhitespace { scalars = scalars.dropLast() }
        var negative = false
        if let sign = scalars.first, sign == "+" || sign == "-" {
            negative = sign == "-"
            scalars = scalars.dropFirst()
        }
        var digits: [UInt8] = []
        var fraction = 0
        var seenPoint = false
        var mantissaDigits = 0
        while let next = scalars.first, next.isASCII, (next.value >= 0x30 && next.value <= 0x39) || (next == "." && !seenPoint) {
            if next == "." {
                seenPoint = true
            } else {
                digits.append(UInt8(next.value - 0x30))
                mantissaDigits += 1
                if seenPoint { fraction += 1 }
            }
            scalars = scalars.dropFirst()
        }
        guard mantissaDigits > 0 else { return nil }
        var exponent = -fraction
        if let marker = scalars.first, marker == "e" || marker == "E" {
            scalars = scalars.dropFirst()
            var exponentNegative = false
            if let sign = scalars.first, sign == "+" || sign == "-" {
                exponentNegative = sign == "-"
                scalars = scalars.dropFirst()
            }
            var value = 0
            var count = 0
            while let next = scalars.first, next.value >= 0x30, next.value <= 0x39 {
                value = value * 10 + Int(next.value - 0x30)
                count += 1
                scalars = scalars.dropFirst()
                if value > 1_000_000 { return nil }
            }
            guard count > 0 else { return nil }
            exponent += exponentNegative ? -value : value
        }
        guard scalars.isEmpty else { return nil }
        while digits.count > 1, digits.first == 0 { digits.removeFirst() }
        self.negative = negative
        self.digits = digits
        self.exponent = exponent
    }

    var isZero: Bool { digits.allSatisfy { $0 == 0 } }

    /// Python `self * Decimal(10)`: the coefficient gains a digit, the exponent is unchanged.
    func timesTen() -> PythonDecimalText {
        var result = self
        result.digits = isZero ? [0] : digits + [0]
        return result
    }

    var decimal: Decimal? {
        Decimal(string: (negative ? "-" : "") + digits.map(String.init).joined() + "e\(exponent)", locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Python `Decimal.__str__` (`to-scientific-string`).
    var description: String {
        let coefficient = digits.map(String.init).joined()
        let adjusted = exponent + coefficient.count - 1
        var body: String
        if exponent <= 0, adjusted >= -6 {
            if exponent == 0 {
                body = coefficient
            } else if coefficient.count > -exponent {
                let split = coefficient.index(coefficient.endIndex, offsetBy: exponent)
                body = coefficient[..<split] + "." + coefficient[split...]
            } else {
                body = "0." + String(repeating: "0", count: -exponent - coefficient.count) + coefficient
            }
        } else {
            let head = coefficient.prefix(1)
            let tail = coefficient.dropFirst()
            body = String(head) + (tail.isEmpty ? "" : "." + tail) + "E" + (adjusted >= 0 ? "+" : "-") + String(abs(adjusted))
        }
        return (negative ? "-" : "") + body
    }
}

/// Python's default `decimal` context for the one inexact operation the checks perform.
enum PythonDecimalContext {
    static let precision = 28

    /// `a / b` correctly rounded half-even to 28 significant digits, by exact long division on the
    /// operands' coefficients. Foundation's `NSDecimalDivide` keeps up to 38 digits (fewer for some
    /// quotients) and rounding that result again to 28 digits can differ from Python by double
    /// rounding, so it is not used when the coefficients fit.
    ///
    /// Known gap: when either coefficient has more than 17 digits (the long division would overflow
    /// `UInt64`), this falls back to `NSDecimalDivide` and is not guaranteed to equal Python. Printed
    /// label values are far shorter; every exported vector stays on the exact path.
    static func divide(_ a: Decimal, _ b: Decimal) -> Decimal {
        guard let left = Coefficient(a), let right = Coefficient(b), right.value != 0 else {
            var result = Decimal()
            var lhs = a
            var rhs = b
            NSDecimalDivide(&result, &lhs, &rhs, .bankers)
            return result
        }
        if left.value == 0 { return 0 }
        // Quotient digits of left.value / right.value, scaled so there are at least precision + 1 digits.
        var remainder = left.value % right.value
        var integer = left.value / right.value
        var digits = integer == 0 ? [] : String(integer).compactMap { $0.wholeNumberValue }
        var scale = 0
        while digits.count <= precision {
            remainder *= 10
            integer = remainder / right.value
            remainder %= right.value
            if !(digits.isEmpty && integer == 0) { digits.append(Int(integer)) }
            scale += 1
            if digits.isEmpty, scale > 200 { return 0 }
        }
        // `digits` holds precision + 1 significant digits; round the last one away.
        let guardDigit = digits.removeLast()
        scale -= 1
        let sticky = remainder != 0
        let roundUp = guardDigit > 5 || (guardDigit == 5 && (sticky || (digits.last ?? 0) % 2 == 1))
        if roundUp {
            var index = digits.count - 1
            while index >= 0 {
                if digits[index] == 9 {
                    digits[index] = 0
                    index -= 1
                } else {
                    digits[index] += 1
                    break
                }
            }
            if index < 0 { digits.insert(1, at: 0); digits.removeLast(); scale -= 1 }
        }
        let text = (left.negative != right.negative ? "-" : "") + digits.map(String.init).joined() + "e\(left.exponent - right.exponent - scale)"
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    struct Coefficient {
        let negative: Bool
        let value: UInt64
        let exponent: Int

        /// Coefficients up to 17 digits, so `remainder * 10` cannot overflow in the long division.
        init?(_ decimal: Decimal) {
            let text = NSDecimalNumber(decimal: decimal).stringValue
            guard let parsed = PythonDecimalText(text), parsed.digits.count <= 17 else { return nil }
            var value: UInt64 = 0
            for digit in parsed.digits { value = value * 10 + UInt64(digit) }
            self.negative = parsed.negative
            self.value = value
            self.exponent = parsed.exponent
        }
    }
}
