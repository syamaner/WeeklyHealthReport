import Foundation
import HealthKit

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

    var healthKitUnit: HKUnit {
        switch self {
        case .kilocalories: .kilocalorie()
        case .grams: .gramUnit(with: .none)
        case .milligrams: .gramUnit(with: .milli)
        case .micrograms: .gramUnit(with: .micro)
        case .millilitres: .literUnit(with: .milli)
        }
    }
}

struct NutritionMetricDefinition: Equatable {
    let identifier: HKQuantityTypeIdentifier
    let key: String
    let label: String
    let category: NutritionCategory
    let unit: NutritionExportUnit
}

enum NutritionCatalogue {
    static let reportingPolicyID = "nutrition_last_7_completed_days_v1"

    static let all: [NutritionMetricDefinition] = [
        .init(identifier: .dietaryEnergyConsumed, key: "energy_consumed", label: "Energy Consumed", category: .energy, unit: .kilocalories),
        .init(identifier: .dietaryCarbohydrates, key: "carbohydrates", label: "Carbohydrates", category: .macronutrient, unit: .grams),
        .init(identifier: .dietaryProtein, key: "protein", label: "Protein", category: .macronutrient, unit: .grams),
        .init(identifier: .dietaryFatTotal, key: "fat_total", label: "Total Fat", category: .macronutrient, unit: .grams),
        .init(identifier: .dietaryFatSaturated, key: "fat_saturated", label: "Saturated Fat", category: .macronutrient, unit: .grams),
        .init(identifier: .dietaryFatMonounsaturated, key: "fat_monounsaturated", label: "Monounsaturated Fat", category: .macronutrient, unit: .grams),
        .init(identifier: .dietaryFatPolyunsaturated, key: "fat_polyunsaturated", label: "Polyunsaturated Fat", category: .macronutrient, unit: .grams),
        .init(identifier: .dietaryFiber, key: "fiber", label: "Fibre", category: .macronutrient, unit: .grams),
        .init(identifier: .dietarySugar, key: "sugar", label: "Sugar", category: .macronutrient, unit: .grams),
        .init(identifier: .dietaryCholesterol, key: "cholesterol", label: "Cholesterol", category: .macronutrient, unit: .milligrams),
        .init(identifier: .dietaryVitaminA, key: "vitamin_a", label: "Vitamin A", category: .vitamin, unit: .micrograms),
        .init(identifier: .dietaryThiamin, key: "thiamin_b1", label: "Thiamin (B1)", category: .vitamin, unit: .milligrams),
        .init(identifier: .dietaryRiboflavin, key: "riboflavin_b2", label: "Riboflavin (B2)", category: .vitamin, unit: .milligrams),
        .init(identifier: .dietaryNiacin, key: "niacin_b3", label: "Niacin (B3)", category: .vitamin, unit: .milligrams),
        .init(identifier: .dietaryPantothenicAcid, key: "pantothenic_acid_b5", label: "Pantothenic Acid (B5)", category: .vitamin, unit: .milligrams),
        .init(identifier: .dietaryVitaminB6, key: "vitamin_b6", label: "Vitamin B6", category: .vitamin, unit: .milligrams),
        .init(identifier: .dietaryBiotin, key: "biotin_b7", label: "Biotin (B7)", category: .vitamin, unit: .micrograms),
        .init(identifier: .dietaryFolate, key: "folate_b9", label: "Folate (B9)", category: .vitamin, unit: .micrograms),
        .init(identifier: .dietaryVitaminB12, key: "vitamin_b12", label: "Vitamin B12", category: .vitamin, unit: .micrograms),
        .init(identifier: .dietaryVitaminC, key: "vitamin_c", label: "Vitamin C", category: .vitamin, unit: .milligrams),
        .init(identifier: .dietaryVitaminD, key: "vitamin_d", label: "Vitamin D", category: .vitamin, unit: .micrograms),
        .init(identifier: .dietaryVitaminE, key: "vitamin_e", label: "Vitamin E", category: .vitamin, unit: .milligrams),
        .init(identifier: .dietaryVitaminK, key: "vitamin_k", label: "Vitamin K", category: .vitamin, unit: .micrograms),
        .init(identifier: .dietaryCalcium, key: "calcium", label: "Calcium", category: .mineral, unit: .milligrams),
        .init(identifier: .dietaryChloride, key: "chloride", label: "Chloride", category: .mineral, unit: .milligrams),
        .init(identifier: .dietaryIron, key: "iron", label: "Iron", category: .mineral, unit: .milligrams),
        .init(identifier: .dietaryMagnesium, key: "magnesium", label: "Magnesium", category: .mineral, unit: .milligrams),
        .init(identifier: .dietaryPhosphorus, key: "phosphorus", label: "Phosphorus", category: .mineral, unit: .milligrams),
        .init(identifier: .dietaryPotassium, key: "potassium", label: "Potassium", category: .mineral, unit: .milligrams),
        .init(identifier: .dietarySodium, key: "sodium", label: "Sodium", category: .mineral, unit: .milligrams),
        .init(identifier: .dietaryZinc, key: "zinc", label: "Zinc", category: .mineral, unit: .milligrams),
        .init(identifier: .dietaryChromium, key: "chromium", label: "Chromium", category: .ultratraceMineral, unit: .micrograms),
        .init(identifier: .dietaryCopper, key: "copper", label: "Copper", category: .ultratraceMineral, unit: .milligrams),
        .init(identifier: .dietaryIodine, key: "iodine", label: "Iodine", category: .ultratraceMineral, unit: .micrograms),
        .init(identifier: .dietaryManganese, key: "manganese", label: "Manganese", category: .ultratraceMineral, unit: .milligrams),
        .init(identifier: .dietaryMolybdenum, key: "molybdenum", label: "Molybdenum", category: .ultratraceMineral, unit: .micrograms),
        .init(identifier: .dietarySelenium, key: "selenium", label: "Selenium", category: .ultratraceMineral, unit: .micrograms),
        .init(identifier: .dietaryWater, key: "water", label: "Water", category: .hydration, unit: .millilitres),
        .init(identifier: .dietaryCaffeine, key: "caffeine", label: "Caffeine", category: .caffeination, unit: .milligrams)
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
