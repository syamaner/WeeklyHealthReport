import Foundation

/// A conservative URL-marker check, not country verification. Unknown geography
/// still needs model applicability checks and explicit human source review.
public enum FoodSourceMarketPolicy {
    public static let version = "food-source-market-conflict-v1"

    // Deliberately closed to the markets exercised by this feature. Do not infer
    // country from arbitrary two-letter labels or globally used suffixes (.ai/.io).
    private static let markers = ["uk": "UK", "gb": "UK", "ie": "IE", "tw": "TW"]

    public static func hasExplicitConflict(foodTerms: String, url: URL) -> Bool {
        let text = foodTerms.lowercased()
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let phrase = " " + words.joined(separator: " ") + " "
        var requested = Set<String>()
        if words.contains("uk") || phrase.contains(" united kingdom ") || text.contains("英國") || text.contains("英国") {
            requested.insert("UK")
        }
        if words.contains("taiwan") || text.contains("台灣") || text.contains("臺灣") || text.contains("台湾") {
            requested.insert("TW")
        }
        if words.contains("ireland") || text.contains("愛爾蘭") || text.contains("爱尔兰") {
            requested.insert("IE")
        }
        // A comparison or an ambiguous request does not have one target market.
        guard requested.count == 1, let market = requested.first else { return false }
        let host = (url.host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = host.split(separator: ".").map(String.init)
        let leadingHost = labels.first == "www" ? labels.dropFirst().first : labels.first
        let leadingPath = url.path.split(separator: "/").first.map(String.init)?.lowercased()
        var indicated = Set<String>()
        if let suffix = labels.last, let country = markers[suffix] { indicated.insert(country) }
        for component in [leadingHost, leadingPath].compactMap({ $0 }) {
            if let country = markers[component] { indicated.insert(country) }
            // A language alone does not identify a country. A complete locale
            // segment (en-IE, zh-TW) may supply an explicit recognised region.
            let locale = component.split(separator: "-", omittingEmptySubsequences: false)
            if locale.count == 2, ["en", "zh"].contains(String(locale[0])),
               let country = markers[String(locale[1])] { indicated.insert(country) }
        }
        return indicated.contains { $0 != market }
    }
}
