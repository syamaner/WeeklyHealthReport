import Foundation

/// The pre-send panel detector of the pasted label AI text route (docs/pasted-label-ai-text-v1.md
/// 4.7, D13 and D18): a closed, pure check that declines US, Australian and New Zealand panels on
/// markers a UK or EU English declaration does not print, so their text is never sent and no
/// read is spent. It runs on the pasted text before any request is built, and again on the
/// model's candidate (its headers, row labels and nutrients). EU English panels follow the UK
/// rules and pass (D18). Words are maximal runs of letters and digits, lower-cased.
///
/// US panels (Nutrition Facts, including per 100 variants):
/// - `nutrition_facts_title`: the words `nutrition facts`;
/// - `daily_value`: the words `daily value` or `daily values`, or the word `dv`;
/// - `sodium_without_salt`: the word `sodium` with no word `salt`, in a text with no CJK script
///   (Han, Hiragana or Katakana: a bilingual Taiwan paste prints `Sodium` beside `鈉` and is not a
///   US panel).
///
/// Australian and New Zealand panels (the FSANZ nutrition information panel):
/// - `average_quantity`: `average`, `avg`, `ave` or `av` followed by `quantity`;
/// - `per_serve`: the words `per serve`;
/// - `servings_per_package`: the words `servings per package`.
public enum PastedLabelAITextPanelDetector {
    public static let version = "pasted-label-ai-text-panel-detector-v1"

    public enum Marker: String, Equatable, Sendable, Codable, CaseIterable {
        case nutritionFactsTitle = "nutrition_facts_title"
        case dailyValue = "daily_value"
        case sodiumWithoutSalt = "sodium_without_salt"
        case averageQuantity = "average_quantity"
        case perServe = "per_serve"
        case servingsPerPackage = "servings_per_package"

        public var panel: Panel {
            switch self {
            case .nutritionFactsTitle, .dailyValue, .sodiumWithoutSalt: .us
            case .averageQuantity, .perServe, .servingsPerPackage: .australiaNewZealand
            }
        }
    }

    public enum Panel: String, Equatable, Sendable, Codable { case us, australiaNewZealand = "australia_new_zealand" }

    public struct Verdict: Equatable, Sendable, Codable {
        /// The markers found, in `Marker.allCases` order.
        public let markers: [Marker]
        public var declines: Bool { !markers.isEmpty }
        /// The declined panels, in `Panel` order (US first).
        public var panels: [Panel] {
            [Panel.us, .australiaNewZealand].filter { panel in markers.contains { $0.panel == panel } }
        }
    }

    /// The detector on the pasted text, before any request is built.
    public static func detect(text: String) -> Verdict {
        Verdict(markers: markers(words: words(text), hasHan: hasHan(text)))
    }

    /// The detector again on the model's candidate: its header texts and row labels as one text,
    /// plus its nutrients (a `sodium` row without a `salt` row, with no CJK script in the labels).
    public static func detect(candidateHeaders: [String], rowLabels: [String], nutrients: [String]) -> Verdict {
        let text = (candidateHeaders + rowLabels).joined(separator: "\n")
        let han = hasHan(text)
        var found = Set(markers(words: words(text), hasHan: han))
        if nutrients.contains("sodium"), !nutrients.contains("salt"), !han { found.insert(.sodiumWithoutSalt) }
        return Verdict(markers: Marker.allCases.filter(found.contains))
    }

    static func markers(words: [String], hasHan: Bool) -> [Marker] {
        func phrase(_ sequence: [String]) -> Bool {
            guard sequence.count <= words.count else { return false }
            return (0...(words.count - sequence.count)).contains { Array(words[$0..<($0 + sequence.count)]) == sequence }
        }
        var found: [Marker] = []
        if phrase(["nutrition", "facts"]) { found.append(.nutritionFactsTitle) }
        if phrase(["daily", "value"]) || phrase(["daily", "values"]) || words.contains("dv") { found.append(.dailyValue) }
        if words.contains("sodium"), !words.contains("salt"), !hasHan { found.append(.sodiumWithoutSalt) }
        if ["average", "avg", "ave", "av"].contains(where: { phrase([$0, "quantity"]) }) { found.append(.averageQuantity) }
        if phrase(["per", "serve"]) { found.append(.perServe) }
        if phrase(["servings", "per", "package"]) { found.append(.servingsPerPackage) }
        return found
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { PastedLabelTextScan.isCJK($0) }
    }
}
