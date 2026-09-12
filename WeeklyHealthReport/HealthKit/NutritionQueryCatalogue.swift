import HealthKit

extension NutritionExportUnit {
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

enum NutritionQueryCatalogue {
    static let quantityTypeIdentifiers: [String: HKQuantityTypeIdentifier] = [
        "energy_consumed": .dietaryEnergyConsumed,
        "carbohydrates": .dietaryCarbohydrates,
        "protein": .dietaryProtein,
        "fat_total": .dietaryFatTotal,
        "fat_saturated": .dietaryFatSaturated,
        "fat_monounsaturated": .dietaryFatMonounsaturated,
        "fat_polyunsaturated": .dietaryFatPolyunsaturated,
        "fiber": .dietaryFiber,
        "sugar": .dietarySugar,
        "cholesterol": .dietaryCholesterol,
        "vitamin_a": .dietaryVitaminA,
        "thiamin_b1": .dietaryThiamin,
        "riboflavin_b2": .dietaryRiboflavin,
        "niacin_b3": .dietaryNiacin,
        "pantothenic_acid_b5": .dietaryPantothenicAcid,
        "vitamin_b6": .dietaryVitaminB6,
        "biotin_b7": .dietaryBiotin,
        "folate_b9": .dietaryFolate,
        "vitamin_b12": .dietaryVitaminB12,
        "vitamin_c": .dietaryVitaminC,
        "vitamin_d": .dietaryVitaminD,
        "vitamin_e": .dietaryVitaminE,
        "vitamin_k": .dietaryVitaminK,
        "calcium": .dietaryCalcium,
        "chloride": .dietaryChloride,
        "iron": .dietaryIron,
        "magnesium": .dietaryMagnesium,
        "phosphorus": .dietaryPhosphorus,
        "potassium": .dietaryPotassium,
        "sodium": .dietarySodium,
        "zinc": .dietaryZinc,
        "chromium": .dietaryChromium,
        "copper": .dietaryCopper,
        "iodine": .dietaryIodine,
        "manganese": .dietaryManganese,
        "molybdenum": .dietaryMolybdenum,
        "selenium": .dietarySelenium,
        "water": .dietaryWater,
        "caffeine": .dietaryCaffeine
    ]

    static func quantityTypes() throws -> [(
        definition: NutritionMetricDefinition,
        type: HKQuantityType
    )] {
        try NutritionCatalogue.all.map { definition in
            guard let identifier = quantityTypeIdentifiers[definition.key],
                  let type = HKObjectType.quantityType(forIdentifier: identifier) else {
                throw HealthDataError.missingType("nutrition")
            }
            return (definition, type)
        }
    }
}
