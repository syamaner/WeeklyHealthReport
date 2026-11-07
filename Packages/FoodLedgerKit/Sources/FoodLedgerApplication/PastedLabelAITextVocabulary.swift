import Foundation

/// `pasted-label-ai-text-vocabulary-v1` (docs/pasted-label-ai-text-v1.md 4.4, D11): a closed
/// vocabulary of English and Traditional Chinese row-label and header words, mapping to the
/// nutrient and basis identifiers the wire schema and transcriptions use. It checks the model's
/// assignments and never assigns anything: a nutrient or basis that disagrees with the entry for
/// the printed label or header is `vocabulary_mismatch`, and a label or header the vocabulary
/// does not know (or reads as more than one basis) is `label_unknown`. Both are attention items.
/// A new entry is a new version.
public enum PastedLabelAITextVocabulary {
    public static let version = "pasted-label-ai-text-vocabulary-v1"

    public enum Verdict: String, Equatable, Sendable, Codable, CaseIterable {
        case agrees
        case mismatch = "vocabulary_mismatch"
        case unknown = "label_unknown"
    }

    /// Row-label words, after `normalisedRowLabel`, to the nutrients they may name. `Energy` and
    /// `熱量` name either energy row, since a kJ and a kcal row may share one printed label; which
    /// unit is which is left to `kj_kcal_ratio`. `unrecognised` is the wire schema's identifier
    /// for a row outside its closed nutrient list.
    public static let rowLabels: [String: Set<String>] = {
        var table: [String: Set<String>] = [:]
        func add(_ nutrients: Set<String>, _ words: [String]) { for word in words { table[word] = nutrients } }
        add(["energy_kj", "energy_kcal"], ["energy", "熱量"])
        add(["fat"], ["fat", "total fat", "脂肪"])
        add(["saturates"], ["saturates", "saturated fat", "saturated fats", "saturated fatty acids", "飽和脂肪"])
        add(["trans_fat"], ["trans fat", "trans fats", "trans fatty acids", "反式脂肪"])
        add(["unrecognised"], ["mono-unsaturates", "monounsaturates", "polyunsaturates", "poly-unsaturates", "polyols", "starch"])
        add(["carbohydrate"], ["carbohydrate", "carbohydrates", "total carbohydrate", "碳水化合物"])
        add(["sugars"], ["sugars", "sugar", "total sugars", "糖"])
        add(["added_sugars"], ["added sugars", "添加糖"])
        add(["fibre"], ["fibre", "fiber", "dietary fibre", "dietary fiber", "膳食纖維"])
        add(["protein"], ["protein", "蛋白質"])
        add(["salt"], ["salt"])
        add(["sodium"], ["sodium", "鈉"])
        return table
    }()

    /// The bases a header may name (`per_100g`, `per_100ml`, `per_serving`, `reference_intake`).
    public static let bases: Set<String> = ["per_100g", "per_100ml", "per_serving", "reference_intake"]

    // MARK: Row labels

    static let leadingMarks: Set<Unicode.Scalar> = ["-", "\u{2013}", "\u{2014}", "\u{2022}", "\u{00B7}", "\u{2027}", "\u{FF0E}", "*"]

    /// The closed normalisation of a printed row label: separators to spaces, trailing footnote
    /// marks and punctuation dropped, trailing unit-only groups (`(g)`, `kJ/kcal`, `（公克）`) dropped, Latin
    /// letters lower-cased, leading dashes and bullets dropped, a leading `of which` dropped, and
    /// spaces collapsed.
    public static func normalisedRowLabel(_ printed: String) -> String {
        var text = String(String.UnicodeScalarView(printed.unicodeScalars.map { scalar in
            scalar == "\t" || scalar == "\u{00A0}" || scalar == "\u{202F}" || scalar == "\u{3000}" ? " " : scalar
        })).lowercased()
        func collapse(_ value: String) -> String { value.split(separator: " ").joined(separator: " ") }
        func isUnitGroup(_ value: String) -> Bool {
            let parts = value.split { $0 == "/" || $0 == " " || $0 == "／" }
            return !parts.isEmpty && parts.allSatisfy { part in
                PastedLabelAITextValueGrammar.valueUnits.contains { $0.lowercased() == part.lowercased() }
            }
        }
        var changed = true
        while changed {
            changed = false
            text = collapse(text)
            // Trailing footnote marks and punctuation (`:`, `：`, `-`), but not a closing bracket,
            // which may end a unit group (Qodo finding 4 on #421).
            while let last = text.unicodeScalars.last, last == "*" || last == "†"
                    || (PastedLabelTextScan.isPunctuation(last) && last != ")" && last != "）") {
                text.unicodeScalars.removeLast(); changed = true
            }
            text = collapse(text)
            if let last = text.last, last == ")" || last == "）",
               let open = text.lastIndex(where: { $0 == "(" || $0 == "（" }) {
                let inside = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
                if isUnitGroup(inside) { text = String(text[..<open]); changed = true; continue }
            }
            if let space = text.lastIndex(of: " "), isUnitGroup(String(text[text.index(after: space)...])) {
                text = String(text[..<space]); changed = true
            }
        }
        while let first = text.unicodeScalars.first, leadingMarks.contains(first) || first == " " { text.unicodeScalars.removeFirst() }
        text = collapse(text)
        for prefix in ["of which:", "of which,", "of which"] where text.hasPrefix(prefix) {
            text = collapse(String(text.dropFirst(prefix.count)))
            break
        }
        return text
    }

    /// The nutrients the vocabulary allows for a printed row label, or nil when it is unknown.
    public static func nutrients(forRowLabel printed: String) -> Set<String>? { rowLabels[normalisedRowLabel(printed)] }

    public static func checkRow(printedLabel: String, nutrient: String) -> Verdict {
        guard let allowed = nutrients(forRowLabel: printedLabel) else { return .unknown }
        return allowed.contains(nutrient) ? .agrees : .mismatch
    }

    // MARK: Headers

    /// The basis a printed header names, or nil when it names none or more than one. English
    /// words are whole words of the lower-cased header (`%` its own word); Chinese words are
    /// substrings of the header with its spaces removed. A reference-intake word decides the
    /// basis on its own (`%RI per serving` is the reference-intake column). A header that names a
/// quantity (`serving size`, `portion size`, `servings per pack`, `每份重量`, `本包裝含`, `份量`)
/// names no basis.
    public static func basis(forHeader printed: String) -> String? {
        let lower = printed.lowercased()
        var words: [String] = []
        var current = ""
        for character in lower {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else {
                if !current.isEmpty { words.append(current); current = "" }
                if character == "%" { words.append("%") }
            }
        }
        if !current.isEmpty { words.append(current) }
        let compact = lower.filter { !$0.isWhitespace }
        func phrase(_ sequence: [String]) -> Bool {
            guard sequence.count <= words.count else { return false }
            return (0...(words.count - sequence.count)).contains { Array(words[$0..<($0 + sequence.count)]) == sequence }
        }
        let referenceIntake = phrase(["reference", "intake"]) || phrase(["reference", "intakes"]) || words.contains("ri")
            || words.contains("gda") || compact.contains("每日參考值")
        if referenceIntake { return "reference_intake" }
        // A header that names a quantity (a serving size, a pack count) is not an amount basis,
        // so `Serving size` never passes as per serving (Qodo review of A1).
        let quantity = phrase(["serving", "size"]) || phrase(["portion", "size"]) || phrase(["servings", "per"])
            || phrase(["portions", "per"]) || compact.contains("每份重量") || compact.contains("本包裝含") || compact.contains("份量")
        if quantity { return nil }
        var found: Set<String> = []
        if words.contains("100g") || phrase(["100", "g"]) || compact.contains("每100公克") || compact.contains("每100克")
            || compact.contains("每100g") { found.insert("per_100g") }
        if words.contains("100ml") || phrase(["100", "ml"]) || compact.contains("每100毫升") || compact.contains("每100ml") {
            found.insert("per_100ml")
        }
        if words.contains("serving") || words.contains("portion") || compact.contains("每份") || compact.contains("每一份") {
            found.insert("per_serving")
        }
        return found.count == 1 ? found.first : nil
    }

    public static func checkHeader(printedText: String, basis: String) -> Verdict {
        guard let expected = self.basis(forHeader: printedText) else { return .unknown }
        return expected == basis ? .agrees : .mismatch
    }
}
