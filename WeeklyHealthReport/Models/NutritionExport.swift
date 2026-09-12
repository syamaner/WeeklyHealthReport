import Foundation

enum NutritionCategory: String, Codable, Equatable {
    case energy
    case macronutrient
    case vitamin
    case mineral
    case ultratraceMineral = "ultratrace_mineral"
    case hydration
    case caffeination
}

enum NutritionExportUnit: String, Codable, Equatable {
    case kilocalories = "kcal"
    case grams = "g"
    case milligrams = "mg"
    case micrograms = "mcg"
    case millilitres = "mL"
}

struct NutritionMetricDefinition: Equatable {
    let key: String
    let label: String
    let category: NutritionCategory
    let unit: NutritionExportUnit
}

enum NutritionCatalogue {
    static let reportingPolicyID = "nutrition_last_7_completed_days_v1"

    static let all: [NutritionMetricDefinition] = [
        .init(key: "energy_consumed", label: "Energy Consumed", category: .energy, unit: .kilocalories),
        .init(key: "carbohydrates", label: "Carbohydrates", category: .macronutrient, unit: .grams),
        .init(key: "protein", label: "Protein", category: .macronutrient, unit: .grams),
        .init(key: "fat_total", label: "Total Fat", category: .macronutrient, unit: .grams),
        .init(key: "fat_saturated", label: "Saturated Fat", category: .macronutrient, unit: .grams),
        .init(key: "fat_monounsaturated", label: "Monounsaturated Fat", category: .macronutrient, unit: .grams),
        .init(key: "fat_polyunsaturated", label: "Polyunsaturated Fat", category: .macronutrient, unit: .grams),
        .init(key: "fiber", label: "Fibre", category: .macronutrient, unit: .grams),
        .init(key: "sugar", label: "Sugar", category: .macronutrient, unit: .grams),
        .init(key: "cholesterol", label: "Cholesterol", category: .macronutrient, unit: .milligrams),
        .init(key: "vitamin_a", label: "Vitamin A", category: .vitamin, unit: .micrograms),
        .init(key: "thiamin_b1", label: "Thiamin (B1)", category: .vitamin, unit: .milligrams),
        .init(key: "riboflavin_b2", label: "Riboflavin (B2)", category: .vitamin, unit: .milligrams),
        .init(key: "niacin_b3", label: "Niacin (B3)", category: .vitamin, unit: .milligrams),
        .init(key: "pantothenic_acid_b5", label: "Pantothenic Acid (B5)", category: .vitamin, unit: .milligrams),
        .init(key: "vitamin_b6", label: "Vitamin B6", category: .vitamin, unit: .milligrams),
        .init(key: "biotin_b7", label: "Biotin (B7)", category: .vitamin, unit: .micrograms),
        .init(key: "folate_b9", label: "Folate (B9)", category: .vitamin, unit: .micrograms),
        .init(key: "vitamin_b12", label: "Vitamin B12", category: .vitamin, unit: .micrograms),
        .init(key: "vitamin_c", label: "Vitamin C", category: .vitamin, unit: .milligrams),
        .init(key: "vitamin_d", label: "Vitamin D", category: .vitamin, unit: .micrograms),
        .init(key: "vitamin_e", label: "Vitamin E", category: .vitamin, unit: .milligrams),
        .init(key: "vitamin_k", label: "Vitamin K", category: .vitamin, unit: .micrograms),
        .init(key: "calcium", label: "Calcium", category: .mineral, unit: .milligrams),
        .init(key: "chloride", label: "Chloride", category: .mineral, unit: .milligrams),
        .init(key: "iron", label: "Iron", category: .mineral, unit: .milligrams),
        .init(key: "magnesium", label: "Magnesium", category: .mineral, unit: .milligrams),
        .init(key: "phosphorus", label: "Phosphorus", category: .mineral, unit: .milligrams),
        .init(key: "potassium", label: "Potassium", category: .mineral, unit: .milligrams),
        .init(key: "sodium", label: "Sodium", category: .mineral, unit: .milligrams),
        .init(key: "zinc", label: "Zinc", category: .mineral, unit: .milligrams),
        .init(key: "chromium", label: "Chromium", category: .ultratraceMineral, unit: .micrograms),
        .init(key: "copper", label: "Copper", category: .ultratraceMineral, unit: .milligrams),
        .init(key: "iodine", label: "Iodine", category: .ultratraceMineral, unit: .micrograms),
        .init(key: "manganese", label: "Manganese", category: .ultratraceMineral, unit: .milligrams),
        .init(key: "molybdenum", label: "Molybdenum", category: .ultratraceMineral, unit: .micrograms),
        .init(key: "selenium", label: "Selenium", category: .ultratraceMineral, unit: .micrograms),
        .init(key: "water", label: "Water", category: .hydration, unit: .millilitres),
        .init(key: "caffeine", label: "Caffeine", category: .caffeination, unit: .milligrams)
    ]
}

struct NutritionSource: Codable, Equatable, Hashable, Identifiable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }

    static func orderedUnique(_ values: [NutritionSource]) -> [NutritionSource] {
        var byBundleIdentifier: [String: NutritionSource] = [:]
        for value in values where !value.bundleIdentifier.isEmpty {
            if let existing = byBundleIdentifier[value.bundleIdentifier],
               existing.name <= value.name {
                continue
            }
            byBundleIdentifier[value.bundleIdentifier] = value
        }
        return byBundleIdentifier.values.sorted {
            ($0.name, $0.bundleIdentifier) < ($1.name, $1.bundleIdentifier)
        }
    }
}

struct NutritionDailyTotal: Equatable {
    let day: Date
    let value: Double?
}

struct NutritionNutrientTotals: Equatable {
    let key: String
    let today: Double?
    let currentDays: [NutritionDailyTotal]
    let previousDays: [NutritionDailyTotal]
}

struct NutritionExportInput: Equatable {
    let source: NutritionSource
    let nutrients: [NutritionNutrientTotals]
}

protocol NutritionSourceSelectionPersisting {
    func loadBundleIdentifier() -> String?
    func saveBundleIdentifier(_ bundleIdentifier: String?)
}

struct UserDefaultsNutritionSourceSelectionStore: NutritionSourceSelectionPersisting {
    private static let key = "daily-export.nutrition-source-bundle-identifier.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadBundleIdentifier() -> String? {
        defaults.string(forKey: Self.key)
    }

    func saveBundleIdentifier(_ bundleIdentifier: String?) {
        if let bundleIdentifier {
            defaults.set(bundleIdentifier, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
