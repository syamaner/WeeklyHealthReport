import Foundation

/// The two labelled conversions of `pasted-label-conversions-v1` (`docs/pasted-nutrition-label-v1.md`
/// section 3.5): kcal from a printed kJ value, and sodium from a printed salt value.
public enum PastedLabelConversionRule: String, Codable, CaseIterable, Sendable {
    case kjToKcal = "kj_to_kcal_v1"
    case saltToSodium = "salt_to_sodium_v1"

    public var nutrient: String { self == .kjToKcal ? "energy_kcal" : "sodium" }
    public var sourceNutrient: String { self == .kjToKcal ? "energy_kj" : "salt" }
    public var operandUnit: String { self == .kjToKcal ? "kJ" : "g_salt" }
    public var factorText: String { self == .kjToKcal ? "4.184" : "2.5" }
}

/// A printed comparator a conversion carries through. The parser prints only `=`, `<` and `<=`;
/// the lower bounds exist so outward rounding is defined for both ends.
public enum PastedLabelConversionComparator: String, Codable, Sendable {
    case equal = "="
    case less = "<"
    case lessOrEqual = "<="
    case greater = ">"
    case greaterOrEqual = ">="

    init(_ comparator: LabelComparator) {
        switch comparator {
        case .equal: self = .equal
        case .less: self = .less
        case .lessOrEqual: self = .lessOrEqual
        }
    }

    var isUpperBound: Bool { self == .less || self == .lessOrEqual }
    var isLowerBound: Bool { self == .greater || self == .greaterOrEqual }
}

/// The exact conversion record (`conversions[]` in the manifest). Encode it with sorted keys and
/// unescaped slashes, as the canonical manifest encoder does. `comparator` and `rounding` are
/// present only for a bound.
public struct PastedLabelConversionRecord: Codable, Equatable, Sendable {
    public var nutrient: String
    public var rule: PastedLabelConversionRule
    public var ruleVersion: String
    public var sourceHeaderID: String
    public var sourceRowID: String
    public var operandText: String
    public var operandUnit: String
    public var factorText: String
    public var intermediateText: String
    public var storedText: String
    public var comparator: PastedLabelConversionComparator?
    public var rounding: String?

    enum CodingKeys: String, CodingKey {
        case nutrient
        case rule
        case ruleVersion = "rule_version"
        case sourceHeaderID = "source_header_id"
        case sourceRowID = "source_row_id"
        case operandText = "operand_text"
        case operandUnit = "operand_unit"
        case factorText = "factor_text"
        case intermediateText = "intermediate_text"
        case storedText = "stored_text"
        case comparator
        case rounding
    }

    /// The ledger amount: `Double(storedText)`, never computed through `Double` arithmetic.
    public var storedAmount: Double? { Double(storedText) }
}

/// One conversion's working: the record plus the unrounded quotient, for audit and golden tests.
public struct PastedLabelConversion: Equatable, Sendable {
    public var record: PastedLabelConversionRecord
    public var operand: Decimal
    public var quotient: Decimal
}

/// `pasted-label-conversions-v1`. Pure decimal arithmetic in Foundation `Decimal`; no `Double`
/// until the stored string is parsed for the ledger, no locale, no clock.
public enum PastedLabelConversions {
    public static let version = "pasted-label-conversions-v1"
    static let posix = Locale(identifier: "en_US_POSIX")

    /// Steps 1 to 4 of section 3.5 for one printed operand. Returns `nil` when the operand is not
    /// plain printed decimal text (digits, optionally one `.` or `,` and more digits).
    public static func convert(
        _ rule: PastedLabelConversionRule,
        operandText: String,
        comparator: PastedLabelConversionComparator = .equal,
        sourceHeaderID: String,
        sourceRowID: String
    ) -> PastedLabelConversion? {
        guard let operand = parseOperand(operandText) else { return nil }
        let quotient = quotient(rule, operand)
        let intermediate = rounded(quotient, scale: 6, mode: .bankers)
        let stored: Decimal
        if comparator.isUpperBound {
            stored = rounded(quotient, scale: 1, mode: .up)
        } else if comparator.isLowerBound {
            stored = rounded(quotient, scale: 1, mode: .down)
        } else {
            stored = rounded(intermediate, scale: 1, mode: .plain)
        }
        let bound = comparator != .equal
        let record = PastedLabelConversionRecord(
            nutrient: rule.nutrient,
            rule: rule,
            ruleVersion: version,
            sourceHeaderID: sourceHeaderID,
            sourceRowID: sourceRowID,
            operandText: operandText,
            operandUnit: rule.operandUnit,
            factorText: rule.factorText,
            intermediateText: fixedPoint(intermediate, places: 6),
            storedText: fixedPoint(stored, places: 1),
            comparator: bound ? comparator : nil,
            rounding: bound ? "outward" : nil
        )
        return PastedLabelConversion(record: record, operand: operand, quotient: quotient)
    }

    /// Recomputes steps 1 to 4 from `operand_text` and the rule and compares the stored string
    /// only; the intermediate is audit evidence and never compared (section 3.5).
    public static func storedTextMatches(_ record: PastedLabelConversionRecord) -> Bool {
        guard record.ruleVersion == version, record.factorText == record.rule.factorText, record.operandUnit == record.rule.operandUnit,
              let recomputed = convert(record.rule, operandText: record.operandText, comparator: record.comparator ?? .equal, sourceHeaderID: record.sourceHeaderID, sourceRowID: record.sourceRowID) else {
            return false
        }
        return recomputed.record.storedText == record.storedText
    }

    // MARK: Which cells convert

    /// The conversions for the stored column: kcal only when that column prints kJ and no kcal,
    /// sodium only when it prints salt and no sodium. Printed always wins; a conversion reads only
    /// one printed cell of the same column and never another conversion.
    public static func conversions(for candidate: LabelCaptureCandidate, storedHeaderID: String) -> [PastedLabelConversion] {
        let column = candidate.cells.filter { $0.headerID == storedHeaderID && $0.basis != .referenceIntake }
        var out: [PastedLabelConversion] = []
        for rule in PastedLabelConversionRule.allCases {
            guard !column.contains(where: { $0.nutrient == rule.nutrient }) else { continue }
            let sources = column.filter { cell in
                cell.nutrient == rule.sourceNutrient && cell.canonicalUnit == (rule == .kjToKcal ? "kJ" : "g")
            }
            guard sources.count == 1, let source = sources.first,
                  let conversion = convert(rule, operandText: source.decimalText, comparator: .init(source.comparator), sourceHeaderID: source.headerID, sourceRowID: source.rowID) else {
                continue
            }
            out.append(conversion)
        }
        return out
    }

    // MARK: Arithmetic

    static func parseOperand(_ text: String) -> Decimal? {
        guard LabelDeclineGate.isPythonDecimalText(text), !text.hasSuffix("\n") else { return nil }
        return Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: posix)
    }

    static func quotient(_ rule: PastedLabelConversionRule, _ operand: Decimal) -> Decimal {
        var lhs = operand
        var factor = Decimal(string: rule.factorText, locale: posix)!
        var result = Decimal()
        NSDecimalDivide(&result, &lhs, &factor, .bankers)
        if rule == .saltToSodium {
            var thousand = Decimal(1000)
            var scaled = Decimal()
            NSDecimalMultiply(&scaled, &result, &thousand, .bankers)
            result = scaled
        }
        return result
    }

    static func rounded(_ value: Decimal, scale: Int, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, mode)
        return output
    }

    /// Plain fixed-point text with exactly `places` digits after the point: no exponent, no `+`,
    /// no grouping (`370.5`, `240.0`, `0.0`).
    static func fixedPoint(_ value: Decimal, places: Int) -> String {
        let scaled = rounded(value * Decimal(sign: .plus, exponent: places, significand: 1), scale: 0, mode: .plain)
        let negative = scaled < 0
        var digits = NSDecimalNumber(decimal: negative ? -scaled : scaled).stringValue
        if digits.count <= places { digits = String(repeating: "0", count: places + 1 - digits.count) + digits }
        let split = digits.index(digits.endIndex, offsetBy: -places)
        return (negative ? "-" : "") + digits[..<split] + "." + digits[split...]
    }
}

/// Which column is stored (section 6.3), and what the stored column yields.
public enum PastedLabelStoredColumn {
    /// Nutrients the ledger stores. kJ and salt are never stored as themselves: printed beside kcal
    /// or sodium they are read but not used, and alone they are the source of a calculated value.
    public static let storedNutrients: Set<String> = [
        "energy_kcal", "fat", "saturates", "trans_fat", "carbohydrate", "sugars", "added_sugars", "fibre", "protein", "sodium",
    ]

    /// The per 100 g or per 100 ml column when one is printed, else the per-serving column.
    public static func headerID(for candidate: LabelCaptureCandidate) -> String? {
        candidate.headers.first { $0.basis == .per100g || $0.basis == .per100ml }?.headerID
            ?? candidate.headers.first { $0.basis == .perServing }?.headerID
    }

    /// A value the stored column yields: a printed cell of that column, or a calculated value
    /// from exactly one such cell.
    public enum Value: Equatable, Sendable {
        case printed(LabelCell)
        case calculated(PastedLabelConversionRecord)

        public var nutrient: String {
            switch self {
            case .printed(let cell): cell.nutrient
            case .calculated(let record): record.nutrient
            }
        }
    }

    /// Every stored value of the column, in candidate order, then the conversions. Nothing is
    /// read from another column, from a reference-intake column or from a percentage.
    public static func values(for candidate: LabelCaptureCandidate, storedHeaderID: String) -> [Value] {
        let printed = candidate.cells.filter {
            $0.headerID == storedHeaderID && $0.basis != .referenceIntake && $0.canonicalUnit != "%" && storedNutrients.contains($0.nutrient)
        }
        return printed.map(Value.printed) + PastedLabelConversions.conversions(for: candidate, storedHeaderID: storedHeaderID).map { .calculated($0.record) }
    }
}

/// Format inference (`pasted-label-format-inference-v1`, section 5). The evaluation declared each
/// case's format from its corpus; the product infers it from the candidate, deterministically.
public enum LabelFormatInference {
    public static let version = "pasted-label-format-inference-v1"

    public enum Outcome: String, Codable, Sendable {
        case taiwan = "taiwan_nutrition_labelling"
        case uk = "uk_nutrition_declaration"
        case usNutritionFacts = "us_nutrition_facts"
        case ambiguous = "format_ambiguous"

        /// The gate format, when gate v2 has one.
        public var gateFormat: LabelGateFormat? {
            switch self {
            case .taiwan: .taiwan
            case .uk: .uk
            case .usNutritionFacts, .ambiguous: nil
            }
        }

        /// The hard-decline code when there is no gate format.
        public var declineCode: String? {
            switch self {
            case .taiwan, .uk: nil
            case .usNutritionFacts: "layout_not_supported"
            case .ambiguous: "format_ambiguous"
            }
        }
    }

    /// `zh-Hant` is Taiwan; English with a per 100 g or per 100 ml column is UK; other English is
    /// US (declined in v1); `mixed` and `unknown` are ambiguous.
    public static func infer(_ candidate: LabelCaptureCandidate) -> Outcome {
        switch candidate.language {
        case .traditionalChinese:
            return .taiwan
        case .english:
            return candidate.headers.contains { $0.basis == .per100g || $0.basis == .per100ml } ? .uk : .usNutritionFacts
        case .mixed, .unknown:
            return .ambiguous
        }
    }
}
