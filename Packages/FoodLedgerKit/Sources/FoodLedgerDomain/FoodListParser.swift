import Foundation

public enum FoodListNotice: String, Codable, CaseIterable, Sendable {
    case missingQuantity, unknownUnit, ambiguousNumber, multipleAmounts, householdMeasure
    case preparationInput, recipe, supplement, unitSpelling, conflictingPreparation
    case contextLine, possibleUnitTypo

    public var message: String {
        switch self {
        case .missingQuantity: "Enter the amount you consumed."
        case .unknownUnit: "Check the unit; it has not been converted."
        case .ambiguousNumber: "Check the number format before choosing an amount."
        case .multipleAmounts: "Several amounts or a pack multiplier appear here. Choose the consumed amount."
        case .householdMeasure: "A mug, spoon or portion needs a measured amount or an evidenced conversion."
        case .preparationInput: "Coffee grounds describe preparation. Enter the brewed drink amount you consumed."
        case .recipe: "A homemade mixture needs its own saved recipe or an explicitly reviewed alternative."
        case .supplement: "Check the exact supplement, form and dose. Generic food results cannot establish its nutrients."
        case .unitSpelling: "A recognised unit spelling was normalised. Check the proposed unit."
        case .conflictingPreparation: "Both raw and cooked appear here. Choose the preparation state."
        case .contextLine: "This looks like a heading, time, price or note. It has been kept as context."
        case .possibleUnitTypo: "This may be a misspelled unit. Choose the unit and amount explicitly."
        }
    }
}

public struct ParsedFoodListLine: Codable, Equatable, Sendable {
    public let lineNumber: Int
    public let original: String
    public let query: String
    public let quantity: Double?
    public let unit: QuantityUnit?
    public let preparation: PreparationKind?
    public let notices: [FoodListNotice]
}

/// A deliberately bounded grammar. Unrecognised units and multiple amounts stay unresolved.
/// No food spelling, brand, household volume or nutrient value is inferred.
public enum FoodListParser {
    public static let version = "food-list-lexical-v3"
    public static let maximumCharacters = 30_000
    public static let maximumLines = 200

    public enum ParseError: Error { case empty, tooLarge }

    public static func parse(_ text: String) throws -> [ParsedFoodListLine] {
        guard text.count <= maximumCharacters else { throw ParseError.tooLarge }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        guard lines.count <= maximumLines else { throw ParseError.tooLarge }
        let parsed = lines.enumerated().compactMap { index, line in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : parseLine(line, number: index + 1)
        }
        guard !parsed.isEmpty else { throw ParseError.empty }
        return parsed
    }

    public static func number(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if value == "½" { return 0.5 }
        // Three digits after a comma could be a thousands separator.
        guard !matches(#"\d,\d{3}(?:\D|$)"#, in: value) else { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        let result: Double?
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator > 0 {
            result = numerator / denominator
        } else {
            result = Double(value.replacingOccurrences(of: ",", with: "."))
        }
        guard let result, result.isFinite, result > 0 else { return nil }
        return result
    }

    /// A visible, opt-in spelling suggestion; never a silent change to a search request.
    public static func suggestedQuery(_ query: String) -> String? {
        var result = query
        for (spelling, replacement) in foodSpellings.sorted(by: { $0.key < $1.key }) {
            result = result.replacingOccurrences(of: "(?i)\\b\(spelling)\\b", with: replacement, options: .regularExpression)
        }
        return result == query ? nil : result
    }

    /// Shared lexical vocabulary only; callers own their quantity semantics.
    public static func unitDefinition(_ spelling: String) -> (unit: QuantityUnit, scale: Double)? {
        units[spelling.lowercased()].map { (unit: $0.0, scale: $0.1) }
    }

    private static let foodSpellings = [
        "avacado": "avocado", "avacados": "avocados", "avacodo": "avocado",
        "brocolli": "broccoli", "poridge": "porridge", "seseme": "sesame",
        "cauliflour": "cauliflower", "yoghourt": "yoghurt"
    ]

    private static func parseLine(_ original: String, number lineNumber: Int) -> ParsedFoodListLine {
        let text = original.trimmingCharacters(in: .whitespaces)
        let lower = text.lowercased()
        var notices: [FoodListNotice] = []
        var query = text
        var amount: Double?
        var unit: QuantityUnit?
        if isContext(lower) {
            return ParsedFoodListLine(
                lineNumber: lineNumber, original: original, query: text,
                quantity: nil, unit: nil, preparation: nil, notices: [.contextLine]
            )
        }
        let raw = matchesPreparation(#"\b(raw|uncooked)\b"#, in: lower)
        // Coffee roast describes dry grounds, not the consumed drink's state.
        let coffeeInput = matches(#"\bcoffee\b"#, in: lower)
        let cookedPattern = coffeeInput
            ? #"\b(cooked|boiled|grilled|fried|baked|steamed)\b"#
            : #"\b(cooked|roast|roasted|toasted|boiled|grilled|fried|baked|steamed)\b"#
        let cooked = matchesPreparation(cookedPattern, in: lower)
        let preparation: PreparationKind? = raw && cooked ? nil : raw ? .raw : cooked ? .cooked : nil
        if raw && cooked { notices.append(.conflictingPreparation) }

        let content = text.replacingOccurrences(of: #"^[•*\-]\s+"#, with: "", options: .regularExpression)
        if let prefix = capture(#"(?i)^(½|[0-9]+(?:[.,][0-9]+)?(?:/[0-9]+)?|\.[0-9]+|half\b|one\b|two\b|three\b|quarter\b|a\b|an\b)\s*(?:[x×]\s*(?=[\p{L}]))?"#, in: content) {
            amount = wordNumbers[prefix[1].lowercased()] ?? number(prefix[1])
            if amount == nil { notices.append(.ambiguousNumber) }
            let remainder = String(content.dropFirst(prefix[0].count))
            if let token = capture(#"^([\p{L}]+)\b\.?\s*"#, in: remainder) {
                let spelling = token[1].lowercased()
                if let definition = units[spelling] {
                    unit = definition.0
                    amount = amount.map { $0 * definition.1 }
                    query = String(remainder.dropFirst(token[0].count))
                    if ["grm", "grms", "gramme", "mililitre", "mililitres", "milliliteres"].contains(spelling) {
                        notices.append(.unitSpelling)
                    }
                } else if household.contains(spelling) || unsupported.contains(spelling) {
                    notices.append(household.contains(spelling) ? .householdMeasure : .unknownUnit)
                    amount = nil
                    query = remainder
                } else if mayBeMisspelledUnit(spelling) {
                    notices.append(.possibleUnitTypo)
                    amount = nil
                    query = remainder
                } else {
                    // A bare number denotes a count, never a gram weight.
                    unit = .count
                    query = remainder
                }
            } else {
                amount = nil
                notices.append(.unknownUnit)
            }
        } else if let suffix = capture(#"(?i)^(.+?)\s+([0-9]+(?:[.,][0-9]+)?(?:/[0-9]+)?|\.[0-9]+)\s*([\p{L}]+)\.?$"#, in: content),
                  let definition = units[suffix[3].lowercased()], definition.0 != .count {
            // One explicit trailing metric amount is supported. Additional
            // amounts in the remaining query still trigger the guard below.
            amount = number(suffix[2]).map { $0 * definition.1 }
            unit = amount == nil ? nil : definition.0
            query = suffix[1]
            if amount == nil { notices.append(.ambiguousNumber) }
            if ["grm", "grms", "gramme", "mililitre", "mililitres", "milliliteres"].contains(suffix[3].lowercased()) {
                notices.append(.unitSpelling)
            }
        } else {
            notices.append(.missingQuantity)
            query = content
        }

        if matches(#"\b[0-9]+(?:[.,][0-9]+)?\s*[x×]\s*[0-9]+"#, in: lower)
            || matches(#"[0-9]+(?:[.,][0-9]+)?\s*(?:g|gr|grams?|kg|ml|litres?)\b"#, in: query.lowercased()) {
            notices.append(.multipleAmounts)
            amount = nil
            unit = nil
        }
        if lower.contains("coffee"), matches(#"\b(grounds?|beans?|grind)\b"#, in: lower) {
            notices.append(.preparationInput)
            amount = nil
            unit = nil
        }
        if matches(#"\b(home[ -]?made|recipe)\b"#, in: lower) { notices.append(.recipe) }
        if matches(#"\b(supplement|vitamin|multivitamin|omega|capsules?|tablets?|zinc|d3|k2|centrum|tudca)\b"#, in: lower) {
            notices.append(.supplement)
        }
        if let value = amount, !value.isFinite { amount = nil; notices.append(.ambiguousNumber) }
        query = query.replacingOccurrences(of: "(?i)\\bcooked weight\\b", with: "cooked", options: .regularExpression)
            .replacingOccurrences(of: "(?i)^of\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return ParsedFoodListLine(
            lineNumber: lineNumber, original: original, query: query,
            quantity: amount, unit: unit, preparation: preparation, notices: notices
        )
    }

    private static let units: [String: (QuantityUnit, Double)] = {
        var values: [String: (QuantityUnit, Double)] = [:]
        for word in ["g", "gr", "gm", "gram", "grams", "gramme", "grammes", "grm", "grms"] { values[word] = (.grams, 1) }
        for word in ["kg", "kilogram", "kilograms"] { values[word] = (.grams, 1_000) }
        for word in ["ml", "millilitre", "millilitres", "milliliter", "milliliters", "mililitre", "mililitres", "milliliteres"] { values[word] = (.millilitres, 1) }
        for word in ["l", "litre", "litres", "liter", "liters"] { values[word] = (.millilitres, 1_000) }
        for word in ["count", "piece", "pieces"] { values[word] = (.count, 1) }
        return values
    }()
    private static let household: Set<String> = ["mug", "mugs", "cup", "cups", "tsp", "tbsp", "spoon", "spoons", "scoop", "scoops", "portion", "portions", "slice", "slices", "table", "tablespoon", "tablespoons", "teaspoon", "teaspoons", "pack", "packs", "packet", "packets"]
    private static let unsupported: Set<String> = ["mg", "mcg", "ug", "oz", "ounce", "ounces", "lb", "lbs", "pint", "pints", "cl", "dl", "gl", "m", "fl"]
    private static let wordNumbers: [String: Double] = ["half": 0.5, "quarter": 0.25, "one": 1, "two": 2, "three": 3, "a": 1, "an": 1]

    private static func isContext(_ text: String) -> Bool {
        matches(#"^\d{1,2}:\d{2}(?:\s*[-–]\s*\d{1,2}:\d{2})?$"#, in: text)
            || matches(#"^[£$€]?\d+[.,]\d{2}$"#, in: text)
            || matches(#"^(?:[£$€]\d+[.,]\d{2}\b|\d+[.,]\d{2}\s+this is\b)"#, in: text)
            || ["breakfast", "lunch", "dinner", "snack", "snacks", "later"].contains(text.trimmingCharacters(in: CharacterSet(charactersIn: ":")))
            || matches(#"^(i |i'm |i’ve |i've |done |finished |until |this is |for (breakfast|lunch|dinner))"#, in: text)
    }

    // Restrict fuzzy matching to long unit words; one-letter errors can change mg to g.
    private static func mayBeMisspelledUnit(_ token: String) -> Bool {
        guard token.count >= 4 else { return false }
        return ["gram", "grams", "kilogram", "kilograms", "millilitre", "millilitres", "milliliter", "milliliters", "litre", "litres"].contains {
            editDistance(token, $0) == 1
        }
    }

    private static func editDistance(_ first: String, _ second: String) -> Int {
        let right = Array(second)
        var previous = Array(0...right.count)
        for (i, left) in first.enumerated() {
            var row = [i + 1]
            for (j, right) in right.enumerated() {
                row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1)))
            }
            previous = row
        }
        return previous[right.count]
    }

    private static func matchesPreparation(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).contains { match in
            guard let range = Range(match.range, in: text) else { return false }
            let prefix = String(text[..<range.lowerBound])
            return !matches(#"\b(?:not|never)\s+(?:(?:pan|soft)[ -]+)?$|\bnon[ -]$"#, in: prefix)
        }
    }

    private static func matches(_ pattern: String, in text: String) -> Bool { capture(pattern, in: text) != nil }
    private static func capture(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
