/// Deterministic, rule-based plural-to-singular folding for retrieval terms
/// (`food-lexical-terms-v9`, see `docs/food-lexical-terms-v9.md`).
///
/// The same function is applied to query terms and source-name terms, so a
/// folded form only has to be consistent, not dictionary-correct. It never
/// rewrites original text, evidence, source names or identity. No language
/// model or operating-system framework is consulted at run time.
public enum FoodLexicalPlurals {
    public static let version = "food-lexical-terms-v9"

    /// Closed exception list, checked before any rule. A value equal to its
    /// key keeps a word that only looks plural (or must not change) as it is.
    /// Changing this list needs a new lexical version.
    public static let exceptions: [String: String] = [
        // Irregular -ves plurals; -ves is never folded by rule (knives is not food).
        "leaves": "leaf", "loaves": "loaf", "halves": "half", "calves": "calf",
        // Singular ends in -ie or -i, so -ies -> -y would be wrong.
        "cookies": "cookie", "brownies": "brownie", "smoothies": "smoothie", "veggies": "veggie",
        "calories": "calorie", "crunchies": "crunchie", "chillies": "chilli", "chilies": "chili",
        // Singular ends in -che or -sse, so the -es rule would be wrong.
        "quiches": "quiche", "brioches": "brioche", "ganaches": "ganache", "mousses": "mousse",
        // Singular ends in -oe, so -oes -> -o would be wrong.
        "sloes": "sloe", "roes": "roe", "aloes": "aloe",
        // Words that only look plural (names, places, dishes, Latin and French terms).
        "molasses": "molasses", "haggis": "haggis", "basis": "basis", "christmas": "christmas",
        "texas": "texas", "thomas": "thomas", "madras": "madras", "pancreas": "pancreas",
        "gras": "gras", "haas": "haas", "gris": "gris", "frais": "frais", "physalis": "physalis",
        "tennis": "tennis", "diabetes": "diabetes", "testes": "testes", "trans": "trans",
        "eccles": "eccles", "atkins": "atkins", "mars": "mars", "always": "always", "kudos": "kudos",
        "horlicks": "horlicks", "salmis": "salmis", "oikos": "oikos", "species": "species",
        // Plural nouns whose singular is a different everyday adjective; folding
        // would widen a search for the noun to every record with the adjective.
        "greens": "greens", "sweets": "sweets", "crisps": "crisps",
    ]

    /// Folds one lowercase retrieval term. Terms that are not plain ASCII
    /// lowercase letters (numbers, mixed tokens, Chinese) are returned unchanged.
    public static func singular(_ word: String) -> String {
        if let mapped = exceptions[word] { return mapped }
        guard word.count >= 4, word.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }) else { return word }
        // -ss (glass, cress, bass), -us (hummus, couscous, asparagus, citrus) and
        // -ys/-as/-os endings other than the rules below keep or lose only the s.
        if word.hasSuffix("ss") || word.hasSuffix("us") { return word }
        if word.count >= 5, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.count >= 5, word.hasSuffix("oes") { return String(word.dropLast(2)) }
        for ending in ["sses", "xes", "ches", "shes", "zzes"] where word.hasSuffix(ending) {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }
}
