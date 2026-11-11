import Foundation
import FoodLedgerDomain

/// Cocoa percentage bands, eligibility exceptions, ordering and notes for generic search
/// (`cocoa-percent-policy-v1`, #382, docs/cocoa-aware-search-v1.md). Presentation and ranking
/// only: no nutrient, identity, provenance or selection changes.
/// v2 (#384, docs/ciqual-2025-admission-v1.md section 4.1) adds open-ended bands, `.atLeast`,
/// and changes nothing else: every bundled CoFID, USDA and TFDA row reads as under v1.
/// v3 (docs/cocoa-exact-match-v1.md rule 1) adds `displayBand`, which also reads a product
/// named "N% dark chocolate" or "dark chocolate N%". Only Search row notes and the exact online
/// section read it; `band` (ranking, discovery, admission, pre-fill, compatibility) is unchanged.
public enum CocoaPercentPolicy {
    public static let version = "cocoa-percent-policy-v3"

    public enum Band: Hashable, Sendable {
        /// Read from the source name or description: `L-U% cocoa solids` or `N% cocoa`.
        case declared(lower: Double, upper: Double)
        /// The one owner-approved estimate: US unsweetened baking chocolate as 100% cocoa.
        case estimate100
        /// A parenthesised blend description, which is not a single band.
        case blend
        /// v2: an open-ended statement ("more than 40% cocoa", "70% cocoa or more"). It is
        /// not a single band: no range (tier 4), never admitted, never a declared band.
        case atLeast(Double)

        var range: ClosedRange<Double>? {
            switch self {
            case let .declared(lower, upper): lower <= upper ? lower...upper : nil
            case .estimate100: 100...100
            case .blend, .atLeast: nil
            }
        }
    }

    /// USDA SR Legacy 2018-04-01 FDC 167568 "Baking chocolate, unsweetened, squares". Chocolate
    /// liquor (21 CFR 163.111); 167567 (liquid) and 167999 (mexican, sweetened) are excluded.
    public static let estimate100RecordID =
        "usda-legacy:2018-04-01:sha256:0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef:fdc:167568"
    static let allowedFoodWords: Set<String> = ["dark", "plain", "bitter", "bittersweet", "extra", "chocolate"]
    static let chocolateTypes: Set<String> = ["milk", "white", "ruby"]

    /// The requested cocoa percentage when the food is a plain chocolate description
    /// ("dark chocolate", "chocolate"); nil for other chocolate foods ("chocolate milk 2%").
    public static func requested(_ query: ParsedFoodQuery) -> Double? {
        guard Set(GenericFoodRankingPolicy.terms(query.food ?? "")).isSubset(of: allowedFoodWords) else { return nil }
        return query.attributes["cocoa_percent"].flatMap(Double.init)
    }

    /// True when the parser appended "chocolate" to a bare cocoa percentage ("100% cacao").
    public static func impliesChocolate(_ query: ParsedFoodQuery) -> Bool {
        requested(query) != nil && (query.food ?? "").split(separator: " ").contains("chocolate")
            && !query.original.folding(options: .widthInsensitive, locale: Locale(identifier: "en_GB")).lowercased().contains("chocolate")
    }

    public static func band(name: String, description: String?, recordID: String?) -> Band? {
        band(name: name, description: description, recordID: recordID, openEndedAsStated: false)
    }

    /// Rule 2 pre-fill reading (docs/ciqual-2025-admission-v1.md 4.1 rule 6): an open-ended
    /// statement on a label pre-fills its stated value, under the same one-value rule, so
    /// `label-estimate-compatibility-v1` pre-fills exactly as it did under v1.
    public static func prefillBand(text: String) -> Band? {
        band(name: text, description: nil, recordID: nil, openEndedAsStated: true)
    }

    /// "more than / over / at least / minimum N% cocoa" or "N% cocoa (solids) or more / and
    /// more / minimum", outside parentheses. An ingredient word after the cocoa wording is not
    /// a band (the v1 point rule's guard).
    static let openEndedPatterns = [
        #"\b(?:more\s+than|over|at\s+least|minimum)\s+(\d+(?:\.\d+)?)\s*%\s*(?:cacao|cocoa)\b(?!\s*(?:butter|powder|mass|liquor|paste|nibs?|beans?))(?:\s+solids\b)?"#,
        #"(\d+(?:\.\d+)?)\s*%\s*(?:cacao|cocoa)(?:\s+solids)?\s+(?:or\s+more|and\s+more|minimum)\b"#
    ]

    private static func band(name: String, description: String?, recordID: String?, openEndedAsStated: Bool) -> Band? {
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
            var withoutRanges = outside.replacingOccurrences(
                of: #"\d+(?:\.\d+)?\s*[-\x{2013}]\s*\d+(?:\.\d+)?\s*%"#, with: " ", options: .regularExpression)
            // v2: open-ended matches are read, then stripped before the point pass.
            for pattern in openEndedPatterns {
                for match in captures(pattern, withoutRanges) {
                    guard let value = Double(match[0]) else { return nil }
                    found.append(openEndedAsStated ? .declared(lower: value, upper: value) : .atLeast(value))
                }
                withoutRanges = withoutRanges.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            }
            // "30% cocoa butter" or "100% cocoa powder" states an ingredient, not the chocolate's band.
            for match in captures(#"(\d+(?:\.\d+)?)\s*%\s*(?:cacao|cocoa)\b(?!\s*(?:butter|powder|mass|liquor|paste|nibs?|beans?))"#, withoutRanges) {
                guard let value = Double(match[0]) else { return nil }
                found.append(.declared(lower: value, upper: value))
            }
        }
        // A blend is ignored beside any declared or open-ended reading; two distinct readings
        // of any kind give no band.
        let stated = found.filter { $0 != .blend }
        if stated.isEmpty { return found.isEmpty ? nil : .blend }
        guard Set(stated).count == 1 else { return nil }
        if case let .atLeast(value) = stated[0] { return (0...100).contains(value) ? stated[0] : nil }
        guard let range = stated[0].range, range.lowerBound >= 0, range.upperBound <= 100 else { return nil }
        return stated[0]
    }

    public static func band(_ candidate: PopulatedFoodCandidate) -> Band? {
        band(name: candidate.name.value, description: candidate.variant?.value,
             recordID: candidate.candidate.recordID.value)
    }

    /// v3 display reading (rule 1.3): the v2 band when v2 reads one; otherwise, when the primary
    /// name is exactly "N% dark chocolate" or "dark chocolate N%" and the description gives no
    /// cocoa reading of its own, the point band [N, N]. Never used for ranking or estimates.
    public static func displayBand(name: String, description: String?, recordID: String?) -> Band? {
        if let stated = band(name: name, description: description, recordID: recordID) { return stated }
        guard let value = namePhrasePercent(name),
              (description ?? "").lowercased().range(of: #"\d\s*%\s*(?:cacao|cocoa)"#, options: .regularExpression) == nil
        else { return nil }
        return .declared(lower: value, upper: value)
    }

    public static func displayBand(_ candidate: PopulatedFoodCandidate) -> Band? {
        displayBand(name: candidate.name.value, description: candidate.variant?.value,
                    recordID: candidate.candidate.recordID.value)
    }

    /// Rule 1.1 and 1.2: the whole primary name (before the first comma, one trailing "bar" or
    /// "block" removed) must be the phrase, so "biscuits with 70% dark chocolate" is not read.
    static func namePhrasePercent(_ name: String) -> Double? {
        var head = String(name.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        head = head.replacingOccurrences(of: #" (?:bar|block)$"#, with: "", options: .regularExpression)
        for pattern in [#"^(\d+(?:\.\d+)?) ?% dark chocolate$"#, #"^dark chocolate (\d+(?:\.\d+)?) ?%$"#] {
            if let match = captures(pattern, head).first, let value = Double(match[0]), (0...100).contains(value) {
                return value
            }
        }
        return nil
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
        case .blend, .atLeast, nil: return false
        }
    }

    /// True when the request names a cocoa percentage and this row is admitted by its band, so
    /// the Search screen keeps it with the close matches in ranked order (#391).
    public static func isCocoaMatch(query: ParsedFoodQuery, candidate: PopulatedFoodCandidate) -> Bool {
        guard requested(query) != nil else { return false }
        return admits(name: candidate.name.value, description: candidate.variant?.value,
                      recordID: candidate.candidate.recordID.value, query: query,
                      foodTerms: Set(GenericFoodRankingPolicy.terms(query.food ?? "")))
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
        guard let value = requested(query), let literal = query.attributes["cocoa_percent"] else { return nil }
        let text: String
        let fromNameOnly = band(candidate) == nil
        switch displayBand(candidate) {
        case let .declared(lower, _)? where fromNameOnly:
            // v3 rule 1: the reading comes from the product name, so the note says so.
            text = value == lower
                ? "The product name states \(number(lower))% dark chocolate."
                : "The product name states \(number(lower))% dark chocolate; you asked for \(literal)%."
        case let .declared(lower, upper)?:
            text = (lower...upper).contains(value)
                ? "Source covers \(span(lower, upper)) cocoa."
                : "Source covers \(span(lower, upper)) cocoa; you asked for \(literal)%. Estimate only."
        case .estimate100?:
            text = value == 100
                ? "US unsweetened baking chocolate, used as a 100% cocoa estimate. It is not your bar; compare the label."
                : "US unsweetened baking chocolate, a 100% cocoa estimate; you asked for \(literal)%. Estimate only."
        case let .atLeast(lower)?: text = "Source states \(number(lower))% cocoa or more, with no single band; you asked for \(literal)%."
        case .blend?: text = "No single cocoa band from this source; you asked for \(literal)%."
        case nil: text = "Cocoa percentage not stated by this source; you asked for \(literal)%."
        }
        return impliesChocolate(query) ? "\(searchedAs(literal)) \(text)" : text
    }

    public static func caution(query: ParsedFoodQuery, candidate: PopulatedFoodCandidate) -> String? {
        guard let value = requested(query), let literal = query.attributes["cocoa_percent"] else { return nil }
        switch displayBand(candidate) {
        case let .declared(lower, upper)?:
            return (lower...upper).contains(value) ? "\(span(lower, upper)) cocoa" : "\(span(lower, upper)) cocoa · requested \(literal)%"
        case .estimate100?:
            return value == 100 ? "100% cocoa estimate · baking chocolate" : "100% cocoa estimate · requested \(literal)%"
        case let .atLeast(lower)?: return "\(number(lower))% cocoa or more"
        case .blend?: return "No single cocoa band"
        case nil: return "Cocoa % not stated"
        }
    }

    /// Shown once on the Search screen, with results or without, when the parser implied chocolate.
    public static func searchedAsNote(query: ParsedFoodQuery) -> String? {
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
