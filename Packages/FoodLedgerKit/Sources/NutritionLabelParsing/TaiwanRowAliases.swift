import Foundation

/// `taiwan-row-aliases-v1` (`docs/pasted-nutrition-label-reader-v3.md` section 4): the closed,
/// versioned Taiwan row-name table of parser v3. Matching is exact on the compacted label (spaces
/// and ideographic spaces removed, after the row-marker rule), never substring or prefix, so
/// 不飽和脂肪 is never saturated fat. Extending it is a new alias version and a new parser version.
public enum TaiwanRowAliases {
    public static let version = "taiwan-row-aliases-v1"

    /// One recognised Taiwan row: the reader's key, its fixed parent and, for the eight mandatory
    /// rows of the official template, the template's canonical unit (section 3.9).
    struct Entry: Equatable {
        let row: LabelVocabulary.Row
        let parent: String?
        let templateUnit: String?
    }

    /// Printed label (after normalisation) to row. The 酸 forms of saturated and trans fat are
    /// dev-set evidence; 添加糖 is included so the exact match keeps it away from 糖 (decision 9).
    static let table: [String: Entry] = [
        "熱量": Entry(row: .energy, parent: nil, templateUnit: "kcal"),
        "蛋白質": Entry(row: .nutrient("protein"), parent: nil, templateUnit: "g"),
        "脂肪": Entry(row: .nutrient("fat"), parent: nil, templateUnit: "g"),
        "飽和脂肪": Entry(row: .nutrient("saturates"), parent: "fat", templateUnit: "g"),
        "飽和脂肪酸": Entry(row: .nutrient("saturates"), parent: "fat", templateUnit: "g"),
        "反式脂肪": Entry(row: .nutrient("trans_fat"), parent: "fat", templateUnit: "g"),
        "反式脂肪酸": Entry(row: .nutrient("trans_fat"), parent: "fat", templateUnit: "g"),
        "碳水化合物": Entry(row: .nutrient("carbohydrate"), parent: nil, templateUnit: "g"),
        "糖": Entry(row: .nutrient("sugars"), parent: "carbohydrate", templateUnit: "g"),
        "添加糖": Entry(row: .nutrient("added_sugars"), parent: "sugars", templateUnit: nil),
        "膳食纖維": Entry(row: .nutrient("fibre"), parent: "carbohydrate", templateUnit: nil),
        "鈉": Entry(row: .nutrient("sodium"), parent: nil, templateUnit: "mg"),
    ]

    /// Named so they are never mistaken for a stored row; they stay `unrecognised` in the
    /// candidate (no new nutrient key) and are pinned by tests as never matching a row above.
    static let recognisedNotStored: [String] = [
        "膽固醇", "鈣", "鉀", "鐵", "維生素A", "維生素C", "維生素D", "維生素E", "單元不飽和脂肪", "單元不飽和脂肪酸",
        "多元不飽和脂肪", "多元不飽和脂肪酸", "不飽和脂肪", "不飽和脂肪酸",
    ]

    /// The one normalisation before lookup: remove one trailing bracket group whose content is
    /// exactly 自願標示者 or 自願標示, in ASCII or full-width brackets. Nothing else is stripped.
    static let voluntaryBracket = LabelPattern(#"[(（](?:自願標示者|自願標示)[)）]$"#)

    static func compact(_ label: String) -> String {
        label.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{3000}", with: "")
    }

    static func normalised(_ label: String) -> String {
        let text = compact(label)
        guard let match = voluntaryBracket.matchDetails(in: text).last, match.range.upperBound == text.endIndex else { return text }
        return String(text[..<match.range.lowerBound])
    }

    static func entry(_ label: String) -> Entry? { table[normalised(label)] }

    /// The official Taiwan template order of the eight mandatory rows (3.2 rule 2, decision 2),
    /// as stored nutrient keys (energy as its kcal key).
    static let templateKeys = ["energy_kcal", "protein", "fat", "saturates", "trans_fat", "carbohydrate", "sugars", "sodium"]

    /// The template position of a mandatory row matched in the alias table, else nil (optional
    /// rows, unrecognised rows and English rows have no position).
    static func templatePosition(_ label: String) -> Int? {
        guard let entry = entry(label), entry.templateUnit != nil else { return nil }
        let key = entry.row == .energy ? "energy_kcal" : RowClassifier.key(for: entry.row)
        return templateKeys.firstIndex(of: key)
    }

    /// The units the Taiwan unit rule (3.9) reads for a mandatory row's template unit. Energy is
    /// read in kcal or kJ: kJ is an accepted energy unit with the versioned `kj_to_kcal_v1`
    /// conversion (v1 decision 6), so it is never a wrong-unit binding; with both printed the kcal
    /// cell is stored and the kJ cell is read but not used, exactly as under v1.
    static func readableUnits(template: String) -> Set<String> {
        template == "kcal" ? ["kcal", "kJ"] : [template]
    }
}

/// Row classification under parser v3: the Taiwan alias table first, then parser v2's English
/// table (`RowClassifier`, unchanged; its Chinese table is a subset of the aliases).
enum RowClassifierV3 {
    struct Match: Equatable {
        var key: String
        var row: LabelVocabulary.Row
        var fixedParent: String?
        var ofWhich: Bool
        /// The Taiwan template unit for a mandatory row matched in the alias table, else nil.
        var templateUnit: String?
        /// Matched in the alias table, whose parent column is exact (none for a top-level row).
        var isTaiwanAlias: Bool
    }

    static func classify(_ label: String) -> Match? {
        if let entry = TaiwanRowAliases.entry(label) {
            return Match(key: RowClassifier.key(for: entry.row), row: entry.row, fixedParent: entry.parent, ofWhich: false,
                         templateUnit: entry.templateUnit, isTaiwanAlias: true)
        }
        guard let english = RowClassifier.classify(label) else { return nil }
        return Match(key: english.key, row: english.row, fixedParent: english.fixedParent, ofWhich: english.ofWhich, templateUnit: nil,
                     isTaiwanAlias: false)
    }

    /// Whether a text names a recognised row (alias table or English table).
    static func isRowLabel(_ text: String) -> Bool { classify(text) != nil }
}
