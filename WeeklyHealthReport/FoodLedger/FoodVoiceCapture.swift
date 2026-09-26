import Combine
import Foundation

enum FoodSpeechVocabulary {
    static let units = ["gram", "grams", "millilitre", "millilitres", "kilogram", "litre", "ounce", "cup", "mug", "tablespoon", "teaspoon"]

    static func make(namesAndBrands: [String]) -> [String] {
        var seen = Set<String>()
        return (units + namesAndBrands.sorted()).compactMap { value in
            let phrase = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !phrase.isEmpty, phrase.count <= 80, !phrase.hasPrefix("barcode:"),
                  seen.insert(phrase.lowercased()).inserted else { return nil }
            return phrase
        }.prefix(100).map { $0 }
    }
}

/// Session-only text, intentionally without a ledger or notes-store capability.
@MainActor
final class FoodVoiceDraft: ObservableObject {
    @Published var text = "" { didSet { checkedNumbersAndUnits = false } }
    @Published var checkedNumbersAndUnits = false
    @Published var errorMessage: String?

    var canTransfer: Bool {
        checkedNumbersAndUnits && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Self.withinLimits(text)
    }

    func append(_ transcript: String) -> String? {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return "No food text was recognised. Keep typing or try again." }
        let combined = text.isEmpty ? transcript : text + "\n" + transcript
        guard Self.withinLimits(combined) else { return "Keep the food draft within 200 lines and 30,000 characters. Existing text is unchanged." }
        text = combined
        return nil
    }

    private static func withinLimits(_ value: String) -> Bool {
        value.count <= 30_000 && value.components(separatedBy: .newlines).count <= 200
    }
}
