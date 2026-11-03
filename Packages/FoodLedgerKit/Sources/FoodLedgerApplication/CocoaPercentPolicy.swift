import Foundation
import FoodLedgerDomain

/// Cocoa percentage bands, eligibility exceptions, ordering and notes for generic search
/// (`cocoa-percent-policy-v1`, #382, docs/cocoa-aware-search-v1.md). Presentation and ranking
/// only: no nutrient, identity, provenance or selection changes.
public enum CocoaPercentPolicy {
    public static let version = "cocoa-percent-policy-v1"

    public enum Band: Hashable, Sendable {
        /// Read from the source name or description: `L-U% cocoa solids` or `N% cocoa`.
        case declared(lower: Double, upper: Double)
        /// The one owner-approved estimate: US unsweetened baking chocolate as 100% cocoa.
        case estimate100
        /// A parenthesised blend description, which is not a single band.
        case blend

        var range: ClosedRange<Double>? {
            switch self {
            case let .declared(lower, upper): lower...upper
            case .estimate100: 100...100
            case .blend: nil
            }
        }
    }

    /// USDA SR Legacy 2018-04-01 FDC 167568 "Baking chocolate, unsweetened, squares". Chocolate
    /// liquor (21 CFR 163.111); 167567 (liquid) and 167999 (mexican, sweetened) are excluded.
    public static let estimate100RecordID =
        "usda-legacy:2018-04-01:sha256:0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef:fdc:167568"
    static let allowedFoodWords: Set<String> = ["dark", "plain", "bitter", "bittersweet", "extra", "chocolate"]
    static let chocolateTypes: Set<String> = ["milk", "white", "ruby"]

    public static func requested(_ query: ParsedFoodQuery) -> Double? {
        query.attributes["cocoa_percent"].flatMap(Double.init)
    }

    /// True when the parser appended "chocolate" to a bare cocoa percentage ("100% cacao").
    public static func impliesChocolate(_ query: ParsedFoodQuery) -> Bool {
        requested(query) != nil && (query.food ?? "").split(separator: " ").contains("chocolate")
            && !query.original.lowercased().contains("chocolate")
    }

    public static func band(name: String, description: String?, recordID: String?) -> Band? {
        if recordID == estimate100RecordID { return .estimate100 }
        var found: [Band] = []
        for text in [name, description ?? ""] where !text.isEmpty {
            let lowered = text.lowercased()
            if lowered.contains("("), lowered.range(of: #"\([^)]*\d\s*%[^)]*(?:cocoa|cacao)"#, options: .regularExpression) != nil {
                found.append(.blend)
            }
            let outside = lowered.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            for match in captures(#"(\d+(?:\.\d+)?)\s*[-\x{2013}]\s*(\d+(?:\.\d+)?)\s*%\s*(?:cacao|cocoa)\s+solids"#, outside) {
                guard let lower = Double(match[0]), let upper = Double(match[1]), lower <= upper else { return nil }
                found.append(.declared(lower: lower, upper: upper))
            }
            let withoutRanges = outside.replacingOccurrences(
                of: #"\d+(?:\.\d+)?\s*[-\x{2013}]\s*\d+(?:\.\d+)?\s*%"#, with: " ", options: .regularExpression)
            for match in captures(#"(\d+(?:\.\d+)?)\s*%\s*(?:cacao|cocoa)\b"#, withoutRanges) {
                guard let value = Double(match[0]) else { return nil }
                found.append(.declared(lower: value, upper: value))
            }
        }
        let declared = found.filter { $0 != .blend }
        if declared.isEmpty { return found.isEmpty ? nil : .blend }
        guard Set(declared).count == 1, let range = declared[0].range,
              range.lowerBound >= 0, range.upperBound <= 100 else { return nil }
        return declared[0]
    }

    public static func band(_ candidate: PopulatedFoodCandidate) -> Band? {
        band(name: candidate.name.value, description: candidate.variant?.value,
             recordID: candidate.candidate.recordID.value)
    }

    /// The two closed exceptions to full query-word coverage. Other source guards still apply.
    public static func admits(name: String, description: String?, recordID: String?,
                              query: ParsedFoodQuery, foodTerms: Set<String>) -> Bool {
        let nameTerms = Set(GenericFoodRankingPolicy.terms(name))
        if requested(query) == nil {
            // UK name equivalence: "plain chocolate" is the UK name for dark chocolate.
            let lowered = name.lowercased()
            return foodTerms == ["dark", "chocolate"]
                && (lowered == "chocolate, plain" || lowered.hasPrefix("chocolate, plain,"))
        }
        guard foodTerms.isSubset(of: allowedFoodWords), nameTerms.contains("chocolate"),
              nameTerms.intersection(chocolateTypes).isSubset(of: foodTerms) else { return false }
        switch band(name: name, description: description, recordID: recordID) {
        case .declared, .estimate100: return true
        case .blend, nil: return false
        }
    }

    /// Stable tier keys: band contains the request (1); else the greatest band below it (2); other
    /// bands by distance (3); rows with no single band (4). Callers sort by these after
    /// preparation verification (and regional deferral in the composite), before their cut.
    public static func tierKeys(_ bands: [Band?], requested value: Double) -> [TierKey] {
        let ranges = bands.map { $0?.range }
        let below = ranges.compactMap { $0 }.filter { !$0.contains(value) && $0.upperBound < value }.map(\.upperBound).max()
        return ranges.map { range in
            guard let range else { return TierKey(tier: 4, distance: 0) }
            if range.contains(value) { return TierKey(tier: 1, distance: 0) }
            if let below, range.upperBound == below { return TierKey(tier: 2, distance: 0) }
            return TierKey(tier: 3, distance: min(abs(value - range.lowerBound), abs(value - range.upperBound)))
        }
    }

    public struct TierKey: Comparable, Sendable {
        let tier: Int
        let distance: Double
        public static func < (lhs: TierKey, rhs: TierKey) -> Bool {
            lhs.tier == rhs.tier ? lhs.distance < rhs.distance : lhs.tier < rhs.tier
        }
    }

    public static func note(query: ParsedFoodQuery, candidate: PopulatedFoodCandidate) -> String? {
        guard let literal = query.attributes["cocoa_percent"], let value = requested(query) else { return nil }
        let text: String
        switch band(candidate) {
        case let .declared(lower, upper)?:
            text = (lower...upper).contains(value)
                ? "Source covers \(span(lower, upper)) cocoa."
                : "Source covers \(span(lower, upper)) cocoa; you asked for \(literal)%. Estimate only."
        case .estimate100?:
            text = value == 100
                ? "US unsweetened baking chocolate, used as a 100% cocoa estimate. It is not your bar; compare the label."
                : "US unsweetened baking chocolate, a 100% cocoa estimate; you asked for \(literal)%. Estimate only."
        case .blend?: text = "No single cocoa band from this source; you asked for \(literal)%."
        case nil: text = "Cocoa percentage not stated by this source; you asked for \(literal)%."
        }
        return impliesChocolate(query) ? "\(searchedAs(literal)) \(text)" : text
    }

    public static func caution(query: ParsedFoodQuery, candidate: PopulatedFoodCandidate) -> String? {
        guard let literal = query.attributes["cocoa_percent"], let value = requested(query) else { return nil }
        switch band(candidate) {
        case let .declared(lower, upper)?:
            return (lower...upper).contains(value) ? "\(span(lower, upper)) cocoa" : "\(span(lower, upper)) cocoa · requested \(literal)%"
        case .estimate100?:
            return value == 100 ? "100% cocoa estimate · baking chocolate" : "100% cocoa estimate · requested \(literal)%"
        case .blend?: return "No single cocoa band"
        case nil: return "Cocoa % not stated"
        }
    }

    /// Shown in the no-result state when the parser implied chocolate.
    public static func noResultNote(query: ParsedFoodQuery) -> String? {
        guard impliesChocolate(query), let literal = query.attributes["cocoa_percent"] else { return nil }
        return searchedAs(literal)
    }

    private static func searchedAs(_ literal: String) -> String { "Searched as chocolate with \(literal)% cocoa." }

    private static func span(_ lower: Double, _ upper: Double) -> String {
        lower == upper ? "\(number(lower))%" : "\(number(lower)) to \(number(upper))%"
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func captures(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}
