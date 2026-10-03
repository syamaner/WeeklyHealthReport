import Foundation

/// Retrieval hints only. Original input remains the capture evidence; these values never establish nutrition.
public struct ParsedFoodQuery: Codable, Equatable, Sendable {
    public enum Route: String, Codable, Sendable { case search, clarify, reject }
    public struct Quantity: Codable, Equatable, Sendable {
        public let value: Double
        public let unit: String
    }
    public static let discoveryPolicyVersion = FoodQueryDiscoveryPolicy.version
    /// Discovery may retain a literal percentage or a bounded named dish without resolving it.
    /// `route` and `quantity` stay unchanged, so this cannot authorise intake prefill.
    public var allowsCandidateDiscovery: Bool {
        route == .search || (route == .clarify && reasons == ["percentage_meaning_unknown"]
            && attributes["unspecified_percent"] != nil && food?.isEmpty == false)
            || requiresRecipeReview
    }
    public var requiresRecipeReview: Bool { FoodQueryDiscoveryPolicy.allowsNamedDishDiscovery(self) }
    public var discoveryReviewMessage: String? {
        requiresRecipeReview ? FoodQueryDiscoveryPolicy.recipeReviewMessage : nil
    }
    public let original: String
    public let food: String?
    public let attributes: [String: String]
    public let quantity: Quantity?
    public let route: Route
    public let reasons: [String]
}

public enum FoodQueryParser {
    public static let version = "food-query-parser-v7"
    public static func parse(_ original: String, recognisedBrands: [String] = ["olympus", "olympos", "quaker", "quakers", "kirkland", "costco", "ortiz", "coop", "the estate dairy"]) -> ParsedFoodQuery {
        var text = original.folding(options: .widthInsensitive, locale: Locale(identifier: "en_GB")).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var attributes: [String: String] = [:]
        var quantities: [ParsedFoodQuery.Quantity] = []
        var reasons: [String] = []
        func matches(_ pattern: String, _ input: String) -> [NSTextCheckingResult] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        }
        func capture(_ match: NSTextCheckingResult, _ group: Int, _ input: String) -> String {
            guard let range = Range(match.range(at: group), in: input) else { return "" }
            return String(input[range])
        }
        func remove(_ pattern: String) {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        // A negated cooking word is retained as evidence, never inverted into
        // an affirmative preparation or an inferred opposite state.
        func preparationMatches(_ pattern: String) -> [NSTextCheckingResult] {
            matches(pattern, text).filter { match in
                guard let range = Range(match.range, in: text) else { return false }
                let prefix = String(text[..<range.lowerBound])
                return matches(#"\b(?:not|never)\s+(?:(?:pan|soft)[ -]+)?$|\bnon[ -]$"#, prefix).isEmpty
            }
        }
        func removePreparation(_ pattern: String) {
            for match in preparationMatches(pattern).reversed() {
                if let range = Range(match.range, in: text) { text.replaceSubrange(range, with: " ") }
            }
        }
        func result(_ route: ParsedFoodQuery.Route, food: String? = nil) -> ParsedFoodQuery {
            ParsedFoodQuery(original: original, food: food, attributes: attributes,
                            quantity: route == .search && quantities.count == 1 ? quantities[0] : nil,
                            route: route, reasons: reasons)
        }
        guard !text.isEmpty else { reasons = ["empty_query"]; return result(.reject) }
        guard text.count <= 500 else { reasons = ["input_too_long"]; return result(.reject) }
        if !matches(#"\b(ignore|automatically|barcode|nan|infinity)\b|\d[eE][+-]?\d|\b(?:nan|infinity)(?:ml|kg|g|l)\b|\bsave\b.*\bwithout confirmation\b"#, text).isEmpty {
            reasons = ["unsupported_input"]; return result(.reject)
        }
        // Unsupported fraction glyphs and bounds are never exact intake amounts.
        if !matches("[⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]", text).isEmpty {
            reasons.append("fraction_requires_portion_confirmation")
        }
        if !matches("[≤≥<>≈≲≳]", text).isEmpty {
            reasons.append("quantity_is_not_exact")
        }
        // Standardise number notation without changing the retained evidence.
        for dash in ["−", "–", "—"] { text = text.replacingOccurrences(of: dash, with: "-") }
        for m in matches(#"(?<![\w.])(-?\d+)\s+(\d+)/(\d+)(?![\d/])"#, text).reversed() {
            let whole = Double(capture(m, 1, text)) ?? 0
            let numerator = Double(capture(m, 2, text)) ?? 0
            let denominator = Double(capture(m, 3, text)) ?? 0
            guard denominator > 0 else { reasons = ["invalid_quantity"]; return result(.reject) }
            let value = (abs(whole) + numerator / denominator) * (capture(m, 1, text).hasPrefix("-") ? -1 : 1)
            if let range = Range(m.range, in: text) { text.replaceSubrange(range, with: String(value)) }
        }
        for (glyph, fraction) in [("½", 0.5), ("¼", 0.25), ("¾", 0.75)] {
            for m in matches(#"(\d+)?"# + glyph, text).reversed() {
                let whole = Double(capture(m, 1, text)) ?? 0
                if let range = Range(m.range, in: text) { text.replaceSubrange(range, with: String(whole + fraction)) }
            }
        }
        for m in matches(#"(?<![\w.])(\d+)/(\d+)(?![\d/])"#, text).reversed() {
            let numerator = Double(capture(m, 1, text)) ?? 0
            let denominator = Double(capture(m, 2, text)) ?? 0
            guard denominator > 0 else { reasons = ["invalid_quantity"]; return result(.reject) }
            if let range = Range(m.range, in: text) { text.replaceSubrange(range, with: String(numerator / denominator)) }
        }
        for m in matches(#"(?<![\d,])\d{1,3}(?:,\d{3})+(?:\.\d+)?(?![\d,])"#, text).reversed() {
            if let range = Range(m.range, in: text) {
                text.replaceSubrange(range, with: String(text[range]).replacingOccurrences(of: ",", with: ""))
            }
        }
        if !matches(#"\b(about|approximately|roughly|up to|at least)\b"#, text).isEmpty {
            reasons.append("quantity_is_not_exact")
        }
        if !matches(#"\b(dairy-free|plant-based)\b"#, text).isEmpty { reasons.append("identity_requires_review") }
        if !matches(#"\d\s*(?:%|percent)\s*(?:less|more)\b"#, text).isEmpty { reasons.append("relative_percentage") }
        if !matches(#"\d\s*(?:%|percent)\s*or\s*\d|\d\s*-\s*\d\s*(?:%|percent)"#, text).isEmpty {
            reasons.append("percentage_scope_ambiguous")
        }
        // Numbers in clocks, supplements and prose are not food quantities.
        if !matches(#"\b\d{1,2}:\d{2}\b|\b(supplement|capsule|vitamin|multivitamin|omega|centrum|momentous|solgar)\b|\b(i had|i ate|dinner at|nothing until|look up)\b"#, text).isEmpty {
            reasons = ["non_food_or_narrative_context"]; return result(.clarify)
        }
        for (wrong, correct) in [("yogurt", "yoghurt"), ("youghurt", "yoghurt"), ("avacado", "avocado"), ("rib-eye", "ribeye"), ("rib eye", "ribeye"), ("sour dough", "sourdough"), ("whole fat", "whole"), ("full fat", "full-fat"), ("low fat", "low-fat"), ("fat free", "fat-free")] {
            text = text.replacingOccurrences(of: #"\b"# + NSRegularExpression.escapedPattern(for: wrong) + #"\b"#, with: correct, options: .regularExpression)
        }
        for brand in recognisedBrands.sorted(by: { $0.count > $1.count }) {
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: brand.lowercased()) + #"\b"#
            if !matches(pattern, text).isEmpty {
                if attributes["brand"] != nil { reasons.append("competing_brands") }
                attributes["brand"] = brand
                remove(pattern)
            }
        }
        let percentPattern = #"(-?\d+(?:\.\d+)?)\s*(?:%|percent)\s*(fat)?"#
        for m in matches(percentPattern, text) {
            let number = capture(m, 1, text)
            guard let value = Double(number) else { reasons.append("invalid_percentage"); continue }
            if value < 0, m.range.location > 0,
               let before = Range(NSRange(location: m.range.location - 1, length: 1), in: text),
               text[before].allSatisfy(\.isNumber) { continue } // range separator, already routed to clarification
            guard value >= 0, value <= 100 else { reasons.append("invalid_percentage"); continue }
            let key = !capture(m, 2, text).isEmpty ? "fat_percent" : text.contains("chocolate") ? "cocoa_percent" : text.contains("peanut butter") ? "ingredient_percent" : "unspecified_percent"
            if let existing = attributes[key], Double(existing) != value { reasons.append("conflicting_variants") }
            attributes[key] = value.rounded() == value ? String(Int(value)) : String(value)
            if key == "unspecified_percent" { reasons.append("percentage_meaning_unknown") }
        }
        remove(percentPattern)
        if !matches(#"\d\s*-\s*\d|\beach\b|\d[^,]*\bor\b[^,]*\d"#, text).isEmpty { reasons.append("quantity_scope_ambiguous") }
        let quantityPattern = #"(?<![\w.])(-?(?:\d+(?:\.\d+)?|\.\d+))\s*(kilograms?|kg|grams?|g|millilitres?|milliliters?|ml|litres?|liters?|l)\b"#
        for m in matches(quantityPattern, text) {
            let value = Double(capture(m, 1, text)) ?? 0
            let unit = capture(m, 2, text)
            let factor: Double = unit == "kg" || unit.hasPrefix("kilogram") || unit == "l" || unit.hasPrefix("litre") || unit.hasPrefix("liter") ? 1000 : 1
            let canonical = unit == "ml" || unit.hasPrefix("millil") || unit == "l" || unit.hasPrefix("litre") || unit.hasPrefix("liter") ? "ml" : "g"
            if value < 0, m.range.location > 0,
               let before = Range(NSRange(location: m.range.location - 1, length: 1), in: text),
               text[before].allSatisfy(\.isNumber) { continue }
            if value <= 0 || !(value * factor).isFinite { reasons.append("invalid_quantity") }
            else { quantities.append(.init(value: value * factor, unit: canonical)) }
        }
        remove(quantityPattern)
        if quantities.count > 1 { reasons.append("competing_quantities") }
        let householdAmount = !matches(#"\b(bowl|handfuls?|jars?|tubs?|cans?|bags?|packets?|pieces?|ladles?|pot|pack|glass|cup|mug|tins?|sachets?|bottles?|plates?|pints?|dollops?|cartons?|scoops?|servings?|portions?|tablespoons?|teaspoons?|oz|ounce|some)\b"#, text).isEmpty
        let hasSliceDescriptor = !matches(#"\bslices?\b"#, text).isEmpty
        let hasSingleMass = quantities.count == 1 && quantities[0].unit == "g"
        if householdAmount || (hasSliceDescriptor && !hasSingleMass) { reasons.append("portion_requires_confirmation") }
        if text.contains("grounds") { reasons.append("grounds_are_not_drink_weight") }
        if text.contains("homemade") || text.contains("smoothie") || text.contains("mixed vegetables") { reasons.append("recipe_unknown") }
        // A bounded whole-item name admits counts, never an estimated mass.
        // The end anchor keeps pepper soup/sauce and other preparations out.
        let countedFood = #"(?:medium\s+)?(?:soft boiled\s+|boiled\s+)?(?:eggs?|bananas?|avocados?|apples?|clementines?|mandarins?|pretzels?)\b"#
        let discretePepper = #"(?:(?:small|medium|large)\s+)?(?:(?:red|green|yellow|orange|bell)\s+)*peppers?(?:\s+(?:raw|cooked))?\s*$"#
        let countPattern = #"^(half|zero|one|two|three|a|an|-?\d+(?:\.\d+)?)\s*x?\s*(?:an?\s+)?(?=(?:"# + countedFood + #"|"# + discretePepper + #"))"#
        if let m = matches(countPattern, text).first {
            let token = capture(m, 1, text)
            let words: [String: Double] = ["half": 0.5, "zero": 0, "one": 1, "two": 2, "three": 3, "a": 1, "an": 1]
            let value = words[token] ?? Double(token) ?? 0
            if value <= 0 || !value.isFinite { reasons.append("invalid_quantity") }
            else { quantities.append(.init(value: value, unit: "count")) }
            remove(countPattern)
            if quantities.count > 1 { reasons.append("count_and_mass_need_basis_confirmation") }
        }
        if text.contains("half") { reasons.append("fraction_requires_portion_confirmation") }
        // Keep cooking methods in retrieval text, but reject incompatible states
        // even when a method is not represented by a preparation descriptor below.
        let rawWords = #"\b(raw|uncooked)\b"#
        let cookedWords = #"\b(cooked|roast|roasted|boiled|grilled|broiled|fried|baked|steamed|braised|poached|stewed)\b"#
        if !preparationMatches(rawWords).isEmpty && !preparationMatches(cookedWords).isEmpty {
            reasons.append("conflicting_preparation")
        }
        let descriptors: [(String, String, String)] = [
            ("soft boiled", "preparation", "soft-boiled"), ("boiled", "preparation", "boiled"),
            ("pan-fried", "preparation", "pan-fried"), ("pan fried", "preparation", "pan-fried"),
            ("roasted", "preparation", "roasted"), ("raw", "preparation", "raw"),
            ("uncooked", "preparation", "raw"), ("cooked", "preparation", "cooked"),
            ("full-fat", "fat_descriptor", "full-fat"), ("low-fat", "fat_descriptor", "low-fat"), ("fat-free", "fat_descriptor", "fat-free"),
            ("whole", "fat_descriptor", "whole"), ("skimmed", "fat_descriptor", "skimmed"), ("unsweetened", "sweetening", "unsweetened"),
            ("lactose-free", "lactose", "free"), ("canned", "preservation", "canned"), ("frozen", "preservation", "frozen"),
            ("medium", "size", "medium")]
        for basis in ["cooked", "raw", "drained"] {
            let pattern = #"\b"# + basis + #" weight\b"#
            guard !preparationMatches(pattern).isEmpty else { continue }
            attributes["weight_basis"] = basis
            if basis != "drained" { attributes["preparation"] = basis }
            removePreparation(pattern)
        }
        for (phrase, key, value) in descriptors {
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: phrase) + #"\b"#
            let occurrences = key == "preparation" ? preparationMatches(pattern) : matches(pattern, text)
            if !occurrences.isEmpty {
                if let existing = attributes[key], existing != value { reasons.append("conflicting_" + key) }
                attributes[key] = value
                if key == "preparation" { removePreparation(pattern) } else { remove(pattern) }
            }
        }
        for phrase in ["without skin or stone", "without seed or skin", "without skin or seed"] where text.contains(phrase) {
            attributes["edible_portion"] = "without skin or stone"; remove(NSRegularExpression.escapedPattern(for: phrase))
        }
        for (phrase, value) in [("without skin", "without"), ("with skin", "with")] where text.contains(phrase) {
            attributes["skin"] = value; remove(NSRegularExpression.escapedPattern(for: phrase))
        }
        // Brand discovery remains a retrieval concern; unknown words are retained, never discarded as brands.
        remove(#"\bof\b"#)
        text = text.replacingOccurrences(of: "(whey)", with: "whey")
        text = text.replacingOccurrences(of: #"[(),.]"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let singular = ["eggs":"egg", "bananas":"banana", "apples":"apple", "clementines":"clementine", "mandarins":"mandarin", "strawberries":"strawberry", "blueberries":"blueberry", "chia seeds":"chia seed", "almonds":"almond", "sesame seeds":"sesame seed"]
        for (plural, single) in singular { text = text.replacingOccurrences(of: #"\b"# + plural + #"\b"#, with: single, options: .regularExpression) }
        if text == "protein powder whey" { text = "whey protein powder" }
        if !matches(#"\d"#, text).isEmpty { reasons.append("unresolved_number") }
        if text.contains(" and ") || text.contains(" with ") || text.contains(" & ") || text.contains(" on ") {
            // One bounded bread name may contain both grain terms. This is
            // not a general exception for food conjunctions or mixed meals.
            let compoundBread = #"^(?:rye and (?:wheat|wholemeal)|(?:wheat|wholemeal) and rye) (?:bread|sourdough(?: bread)?)$"#
            if matches(compoundBread, text).isEmpty { reasons.append("multiple_foods_or_recipe") }
        }
        if text.isEmpty { reasons.append("food_missing") }
        let invalid = reasons.contains("invalid_quantity") || reasons.contains("invalid_percentage") || text.isEmpty
        return result(invalid ? .reject : reasons.isEmpty ? .search : .clarify, food: text.isEmpty ? nil : text)
    }
}
