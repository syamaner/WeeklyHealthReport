import Foundation

/// Synthetic unheaded tables for the basis choice (`docs/pasted-nutrition-label-reader-v3.md`
/// section 8.4.13): one per layout with one column and with two, plus the edge cases. Invented
/// values and names, modelled on layout shapes only; no real label text.
enum UnheadedTableFixtures {
    static let serving = "營養標示\n每一份量 30公克\n本包裝含 8份\n"
    static let servingMl = "營養標示\n每一份量 250毫升\n本包裝含 1份\n"

    static let rows1 = ["熱量 120大卡", "蛋白質 3.0公克", "脂肪 4.5公克", "飽和脂肪 1.5公克", "反式脂肪 0公克", "碳水化合物 18.0公克",
                        "糖 6.0公克", "鈉 60毫克"]
    static let rows2 = ["熱量 120大卡 400大卡", "蛋白質 3.0公克 10.0公克", "脂肪 4.5公克 15.0公克", "飽和脂肪 1.5公克 5.0公克",
                        "反式脂肪 0公克 0公克", "碳水化合物 18.0公克 60.0公克", "糖 6.0公克 20.0公克", "鈉 60毫克 200毫克"]

    /// Each value on its own line under its label.
    static func stacked(_ rows: [String]) -> String {
        rows.map { row -> String in
            let parts = row.split(separator: " ").map(String.init)
            return ([parts[0]] + parts.dropFirst()).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    static let inline1 = serving + rows1.joined(separator: "\n") + "\n"
    static let inline2 = serving + rows2.joined(separator: "\n") + "\n"
    static let inline1Ml = servingMl + rows1.joined(separator: "\n") + "\n"
    static let stacked1 = serving + stacked(rows1) + "\n"
    static let stacked2 = serving + stacked(rows2) + "\n"
    static let flattened1 = serving + rows1.joined(separator: "，") + "\n"
    static let flattened2 = serving + rows2.joined(separator: "，") + "\n"
    static let bilingual1 = "營養標示 Nutrition Facts\n每一份量 Serving Size 30公克\n本包裝含8份 (8 Servings Per Package)\n"
        + "熱量 Calories 120(kcal)大卡\n蛋白質 Protein 3.0(g)公克\n脂肪 Total Fat 4.5(g)公克\n飽和脂肪 Saturated Fat 1.5(g)公克\n"
        + "反式脂肪 Trans Fat 0(g)公克\n碳水化合物 Total Carbohydrate 18.0(g)公克\n糖 Sugars 6.0(g)公克\n鈉 Sodium 60(mg)毫克\n"
    static let bilingual2 = "營養標示 Nutrition Facts\n每一份量 Serving Size 30公克\n本包裝含8份 (8 Servings Per Package)\n"
        + "熱量 Calories 120(kcal)大卡 400(kcal)大卡\n蛋白質 Protein 3.0(g)公克 10.0(g)公克\n脂肪 Total Fat 4.5(g)公克 15.0(g)公克\n"
        + "飽和脂肪 Saturated Fat 1.5(g)公克 5.0(g)公克\n反式脂肪 Trans Fat 0(g)公克 0(g)公克\n"
        + "碳水化合物 Total Carbohydrate 18.0(g)公克 60.0(g)公克\n糖 Sugars 6.0(g)公克 20.0(g)公克\n鈉 Sodium 60(mg)毫克 200(mg)毫克\n"

    /// The basis printed only in the energy line (3.5, decision 23), no serving lines.
    static let energyLine = "營養標示\n熱量 45大卡(每100毫升)\n蛋白質 1.2公克\n脂肪 1.5公克\n飽和脂肪 0.9公克\n反式脂肪 0公克\n碳水化合物 6.4公克\n"
        + "糖 6.1公克\n鈉 38毫克\n"
    /// The same with a serving size in millilitres.
    static let energyLineServing = "營養標示\n每一份量 200毫升\n本包裝含 1份\n熱量 45大卡(每100毫升)\n蛋白質 1.2公克\n脂肪 1.5公克\n飽和脂肪 0.9公克\n"
        + "反式脂肪 0公克\n碳水化合物 6.4公克\n糖 6.1公克\n鈉 38毫克\n"

    /// A printed reference-intake header with unheaded amount columns (8.4.13).
    static let referenceHeader = serving + "每日參考值百分比\n"
        + ["熱量 120大卡 6%", "蛋白質 3.0公克 5%", "脂肪 4.5公克 8%", "飽和脂肪 1.5公克 8%", "反式脂肪 0公克 *",
           "碳水化合物 18.0公克 6%", "糖 6.0公克 *", "鈉 60毫克 3%"].joined(separator: "\n") + "\n"
    /// The same with the percentage before the amount on one row: no sheet.
    static let referenceNotLast = serving + "每日參考值百分比\n"
        + ["熱量 120大卡 6%", "蛋白質 5% 3.0公克", "脂肪 4.5公克 8%", "飽和脂肪 1.5公克 8%", "反式脂肪 0公克 *",
           "碳水化合物 18.0公克 6%", "糖 6.0公克 *", "鈉 60毫克 3%"].joined(separator: "\n") + "\n"

    /// One amount header printed and one not ("mixed"), in each layout: no sheet.
    static let mixedInline = serving + "每份\n" + rows2.joined(separator: "\n") + "\n"
    static let mixedStacked = serving + "每份\n" + stacked(rows2) + "\n"
    static let mixedFlattened = serving + "每份 " + rows2.joined(separator: "，") + "\n"
    static let mixedBilingual = "營養標示 Nutrition Facts\n每一份量 Serving Size 30公克\n本包裝含8份 (8 Servings Per Package)\n每份 Per Serving\n"
        + "熱量 Calories 120(kcal)大卡 400(kcal)大卡\n蛋白質 Protein 3.0(g)公克 10.0(g)公克\n脂肪 Total Fat 4.5(g)公克 15.0(g)公克\n"
        + "飽和脂肪 Saturated Fat 1.5(g)公克 5.0(g)公克\n反式脂肪 Trans Fat 0(g)公克 0(g)公克\n"
        + "碳水化合物 Total Carbohydrate 18.0(g)公克 60.0(g)公克\n糖 Sugars 6.0(g)公克 20.0(g)公克\n鈉 Sodium 60(mg)毫克 200(mg)毫克\n"

    /// Two columns with no serving size: the parser has a shape, the options table declines.
    static let twoColumnsNoServing = "營養標示\n" + rows2.joined(separator: "\n") + "\n"
    /// Too few mandatory rows: every option declines `too_little_read`.
    static let tooLittle = serving + ["熱量 120大卡", "蛋白質 3.0公克", "鈉 60毫克"].joined(separator: "\n") + "\n"
    /// Implausible per 100 g (values for a 250 g serving).
    static let heavyServing = "營養標示\n每一份量 250公克\n本包裝含 1份\n"
        + ["熱量 950大卡", "蛋白質 30.0公克", "脂肪 45.0公克", "飽和脂肪 15.0公克", "反式脂肪 0公克", "碳水化合物 110.0公克",
           "糖 60.0公克", "鈉 600毫克"].joined(separator: "\n") + "\n"

    /// Every in-scope fixture with its expected amount column count (8.4.13).
    static let inScope: [(name: String, text: String, columns: Int)] = [
        ("inline 1", inline1, 1), ("inline 2", inline2, 2), ("inline 1 ml", inline1Ml, 1),
        ("stacked 1", stacked1, 1), ("stacked 2", stacked2, 2),
        ("flattened 1", flattened1, 1), ("flattened 2", flattened2, 2),
        ("bilingual 1", bilingual1, 1), ("bilingual 2", bilingual2, 2),
        ("energy line", energyLine, 1), ("energy line serving", energyLineServing, 1),
        ("reference header", referenceHeader, 1), ("heavy serving", heavyServing, 1)
    ]

    static let mixed: [(name: String, text: String)] = [
        ("inline", mixedInline), ("stacked", mixedStacked), ("flattened", mixedFlattened), ("bilingual", mixedBilingual)
    ]
}
