import Foundation

/// Synthetic pasted-label texts in the Taiwan template shape of the evaluation's untouched set,
/// written for these tests; none is a real product label.
enum SyntheticLabelTexts {
    static let rows = [
        "熱量  167.7 大卡  419.2 大卡",
        "蛋白質  6.0 公克  15.1 公克",
        "脂肪  3.8 公克  9.6 公克",
        "　飽和脂肪  0.5 公克  1.3 公克",
        "　反式脂肪  < 0.1 公克  < 0.1 公克",
        "碳水化合物  29.2 公克  72.9 公克",
        "　糖  < 0.5 公克  < 0.5 公克",
        "　膳食纖維  3.8 公克  9.6 公克",
        "鈉  101 毫克  252 毫克"
    ]

    static func taiwan(_ rows: [String] = rows, header: String = "　　　　每份  每100公克",
                       serving: String? = "每一份量 40 公克", pack: String? = "本包裝含 2 份") -> String {
        (["營養標示"] + [serving, pack].compactMap { $0 } + [header] + rows).joined(separator: "\n") + "\n"
    }

    static let base = taiwan()
    /// Energy printed in kJ only, in both columns.
    static let kilojoulesOnly = taiwan(["熱量  701.7 kJ  1754 kJ"] + rows.dropFirst())
    /// The per 100 g column is for the food as prepared (沖泡).
    static let asPrepared = taiwan(header: "　　　　每份  每100公克（沖泡後）")
    /// The per 100 g column is for the food drained (瀝乾).
    static let drained = taiwan(header: "　　　　每份  每100公克（瀝乾）")
    /// Sodium not printed: G3 on sodium.
    static let sodiumMissing = taiwan(Array(rows.dropLast()))
    /// No servings-per-pack line: G6 on that line.
    static let packMissing = taiwan(pack: nil)
    /// Per serving only, with and without a readable serving size.
    static let perServingOnly = taiwan(rows.map { String($0[..<$0.range(of: "  ", options: .backwards)!.lowerBound]) },
                                       header: "　　　　每份")
    static let perServingNoSize = taiwan(rows.map { String($0[..<$0.range(of: "  ", options: .backwards)!.lowerBound]) },
                                         header: "　　　　每份", serving: nil)
    /// A supplement marker (gate G2).
    static let supplement = base.replacingOccurrences(of: "營養標示", with: "營養補充食品 營養標示")
    /// Fullwidth digits pass through parser v2 and fail the candidate schema (section 1).
    static let fullwidthDigits = base.replacingOccurrences(of: "167.7", with: "１６７.７")
    /// Energy far above the macronutrients: the arithmetic check fails (a warning only).
    static let energyMismatch = taiwan(["熱量  967.7 大卡  2419.2 大卡"] + rows.dropFirst())
    static let usNutritionFacts = "Nutrition Facts\nServing size 2/3 cup (55g)\nAmount per serving\nCalories 230\nTotal Fat 8g\nSaturated Fat 1g\nTrans Fat 0g\nSodium 160mg\nTotal Carbohydrate 37g\nTotal Sugars 12g\nProtein 3g\n"
    static let ukDeclaration = "Nutrition\nTypical values Per 100g\nEnergy 1550kJ / 370kcal\nFat 3.2g\nof which saturates 1.1g\nCarbohydrate 60g\nof which sugars 5.0g\nFibre 7.0g\nProtein 10g\nSalt 0.6g\n"
    static let japanese = "栄養成分表示\nエネルギー 200kcal\nたんぱく質 5g\n"
}
