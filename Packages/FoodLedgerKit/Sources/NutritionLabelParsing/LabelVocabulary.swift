import Foundation

/// Closed vocabulary for printed nutrition labels: canonical nutrient keys,
/// row labels, units and column headers. Extending it is a versioned change.
enum LabelVocabulary {
    static let nutrients: Set<String> = [
        "energy_kj", "energy_kcal", "fat", "saturates", "trans_fat", "carbohydrate",
        "sugars", "added_sugars", "fibre", "protein", "salt", "sodium",
    ]

    /// Row-level nutrient for a label; energy is split by unit later.
    enum Row: Equatable {
        case energy
        case nutrient(String)
    }

    /// Taiwan 營養標示 rows and their fixed parents.
    static let chineseRows: [(label: String, row: Row, parent: String?)] = [
        ("熱量", .energy, nil),
        ("蛋白質", .nutrient("protein"), nil),
        ("飽和脂肪", .nutrient("saturates"), "fat"),
        ("反式脂肪", .nutrient("trans_fat"), "fat"),
        ("脂肪", .nutrient("fat"), nil),
        ("碳水化合物", .nutrient("carbohydrate"), nil),
        ("膳食纖維", .nutrient("fibre"), "carbohydrate"),
        ("糖", .nutrient("sugars"), "carbohydrate"),
        ("鈉", .nutrient("sodium"), nil),
    ]

    /// English row labels after lower-casing, removing `of which` and trimming.
    static let englishRows: [String: Row] = [
        "energy": .energy,
        "calories": .energy,
        "fat": .nutrient("fat"),
        "total fat": .nutrient("fat"),
        "saturates": .nutrient("saturates"),
        "saturated fat": .nutrient("saturates"),
        "saturated": .nutrient("saturates"),
        "trans fat": .nutrient("trans_fat"),
        "carbohydrate": .nutrient("carbohydrate"),
        "carbohydrates": .nutrient("carbohydrate"),
        "total carbohydrate": .nutrient("carbohydrate"),
        "sugars": .nutrient("sugars"),
        "total sugars": .nutrient("sugars"),
        "fibre": .nutrient("fibre"),
        "fiber": .nutrient("fibre"),
        "dietary fiber": .nutrient("fibre"),
        "dietary fibre": .nutrient("fibre"),
        "protein": .nutrient("protein"),
        "salt": .nutrient("salt"),
        "sodium": .nutrient("sodium"),
    ]

    /// Printed unit to canonical unit. Units outside this table are unrecognised.
    static let units: [String: String] = [
        "kj": "kJ", "kcal": "kcal", "cal": "cal", "g": "g", "mg": "mg",
        "µg": "µg", "μg": "µg", "mcg": "µg", "ml": "ml", "%": "%",
        "大卡": "kcal", "千卡": "kcal", "公克": "g", "克": "g", "毫克": "mg",
        "微克": "µg", "毫升": "ml",
    ]

    static func canonicalUnit(_ printed: String) -> String? {
        units[printed] ?? units[printed.lowercased()]
    }

    static func allowedUnits(for row: Row) -> Set<String> {
        switch row {
        case .energy: ["kJ", "kcal", "cal"]
        case .nutrient: ["g", "mg", "µg"]
        }
    }

    /// Characters that only appear in Simplified Chinese or Japanese kana.
    static let unsupportedScriptMarkers: Set<Character> = [
        "营", "养", "质", "钠", "纤", "维", "饱", "热", "总", "钙", "铁", "单", "称", "参",
    ]
}
