import FoodLedgerDomain

/// Whether a saved quantity is an estimate (count-portion-estimate-v1, C6): an estimated weight
/// declaration, or a conversion that is an admitted source estimate. A source estimate is named
/// by its method version and its source release ID prefix together, from this frozen table, so
/// typed method text alone never makes a quantity an estimate (gate F6).
public enum FoodQuantityEstimate {
    /// The whole-milk volume rule (cofid-whole-milk-volume-admission-v1) and its PHE release.
    public static let wholeMilkMethodVersion = "cofid-whole-pasteurised-milk-volume-v1"
    public static let wholeMilkReleasePrefix = "phe-npm-2018:"

    public static func isEstimate(declaration: EdibleWeightDeclaration?, conversion: QuantityConversionVersion?) -> Bool {
        if declaration?.basis == .estimated { return true }
        guard let conversion else { return false }
        return isSourceEstimate(methodVersion: conversion.methodVersion, sourceReleaseID: conversion.sourceReleaseID)
    }

    public static func isEstimate(_ log: LogItemVersion, conversion: QuantityConversionVersion?) -> Bool {
        isEstimate(declaration: log.weightDeclaration,
                   conversion: conversion?.quantityConversionVersionID == log.quantityConversionVersionID ? conversion : nil)
    }

    public static func isSourceEstimate(methodVersion: LedgerText, sourceReleaseID: ExternalIdentifier?) -> Bool {
        guard let release = sourceReleaseID?.value else { return false }
        if CountPortionGuideCode.entry(methodVersion) != nil { return release.hasPrefix(CountPortionGuideCode.releasePrefix) }
        if methodVersion.value == wholeMilkMethodVersion { return release.hasPrefix(wholeMilkReleasePrefix) }
        return false
    }
}

/// How a saved amount was obtained, derived at read time from the log version and its conversion
/// (count-portion-estimate-v1, C7). Never stored.
public enum FoodQuantityMethod: Equatable, Sendable {
    /// Grams, millilitres or servings entered directly.
    case direct
    /// A direct weight the user weighed ("I weighed it").
    case weighed
    case estimatedByEye
    case kitchenScale
    case packageWeight
    case typicalWeight(size: FoodEdibleWeightGuideSize, gramsEach: Double)
    case wholeMilkVolume
    /// A conversion recorded before the closed method set, shown in the user's words.
    case recorded(String)

    public var isEstimate: Bool {
        switch self {
        case .estimatedByEye, .typicalWeight, .wholeMilkVolume: true
        default: false
        }
    }

    public static func of(_ log: LogItemVersion, conversion: QuantityConversionVersion?) -> FoodQuantityMethod {
        if let declaration = log.weightDeclaration { return declaration.basis == .estimated ? .estimatedByEye : .weighed }
        guard let conversion, conversion.quantityConversionVersionID == log.quantityConversionVersionID else { return .direct }
        return of(conversion)
    }

    public static func of(_ conversion: QuantityConversionVersion) -> FoodQuantityMethod {
        let method = conversion.methodVersion
        if FoodQuantityEstimate.isSourceEstimate(methodVersion: method, sourceReleaseID: conversion.sourceReleaseID) {
            if let entry = CountPortionGuideCode.entry(method) { return .typicalWeight(size: entry.size, gramsEach: entry.grams) }
            return .wholeMilkVolume
        }
        switch CountConversionMethod(storedCode: method) {
        case .kitchenScale?: return .kitchenScale
        case .packageWeight?: return .packageWeight
        default: break
        }
        // A pasted-label servings conversion is the label's own serving, not a user method.
        if PastedLabelServingPolicy.admittedVersions.contains(method.value) { return .direct }
        return .recorded(method.value)
    }
}

/// Whether an entered count is servings rather than pieces: one predicate for the Food Log row,
/// the saved entry, Recent and history (count-portion-estimate-v1, C8). Pasted-label servings
/// (`PastedLabelServingPolicy.isServingsAmount`) and counts on a per-serving or named-serving
/// basis (source-declared and recipe servings) read "servings"; everything else reads "pieces".
public enum FoodAmountServings {
    public static func isServings(enteredUnit: QuantityUnit, conversion: QuantityConversionVersion?,
                                  sourceID: String?, basis: ResolutionBasis?) -> Bool {
        guard enteredUnit == .count else { return false }
        if PastedLabelServingPolicy.isServingsAmount(enteredUnit: enteredUnit, conversion: conversion, sourceID: sourceID) { return true }
        // A conversion through a portion guide or a user method converts pieces, never servings.
        if let conversion, !PastedLabelServingPolicy.admittedVersions.contains(conversion.methodVersion.value) { return false }
        switch basis {
        case .perServing?, .named?: return true
        default: return false
        }
    }
}

/// The one count noun (count-portion-estimate-v1, C8): "piece" / "pieces" on every surface.
/// Stored, parsed and exported `count` is data, not this word.
public enum FoodAmountNoun {
    public static func count(_ value: Double) -> String { value == 1 ? "piece" : "pieces" }
    public static func servings(_ value: Double) -> String { value == 1 ? "serving" : "servings" }
    /// The unit picker's label for counts.
    public static let countUnitLabel = "pieces"
    /// A quantity unit as shown beside a number: "g", "mL", "piece" / "pieces". Never the raw
    /// stored value (gate F5).
    public static func unit(_ unit: QuantityUnit, value: Double) -> String {
        switch unit {
        case .grams: "g"
        case .millilitres: "mL"
        case .count: count(value)
        }
    }
}
