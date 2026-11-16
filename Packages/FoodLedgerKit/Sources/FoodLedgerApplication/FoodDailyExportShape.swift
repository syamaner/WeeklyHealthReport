import Foundation

/// Why a decoded food daily file does not have the shape its schema number promises.
public enum FoodDailyExportShapeError: Error, Equatable, Sendable {
    case unknownSchemaVersion(Int)
    case summaryVersionNotAccepted(schema: Int, summaryVersion: String)
    /// A schema-1 file carrying a schema-2 field (a mixed file).
    case unexpectedAmountMethod
    case unexpectedQuantityEstimates
    /// A schema-2 file missing a schema-2 field on any entry or in `notes`.
    case missingAmountMethod
    case missingQuantityEstimates
    case unknownCode(String)
    case estimateFlagMismatch(code: String)
    case unexpectedSource(code: String)
    case missingSource(code: String)
    /// A typical weight whose `source.size` is null.
    case missingSize
    /// A whole-milk volume whose `source.size` is not null.
    case unexpectedSize
    case unknownSize(String)
    case unknownEnteredUnit(String)
}

/// The per-version shape rule of the food daily file (`docs/food-daily-export-contract-v2.md`
/// sections 3.2 and 5, #312): which summary versions each schema admits, which schema carries
/// `quantity.amount_method` and `notes.quantity_estimates`, and the closed `amount_method` table
/// row by row. Pure, and shared by the Drive identity policy and the contract tests so there is
/// one rule. A schema number this build does not know is rejected.
///
/// The rule reads a decoded document, so it is not sufficient on its own: a JSON `null` for an
/// absent-only key and an unknown extra key both decode to the same document as a well-formed
/// file. A caller validating bytes must also require that the document re-encodes to exactly
/// those bytes, as `DailyFoodExportIdentityPolicy.validate` does.
public enum FoodDailyExportShape {
    /// Schema number to the summary versions it admits. Schema 1 files were written under v4, v5
    /// and v6; schema 2 exists only with v6.
    public static let acceptedSummaryVersions: [Int: Set<String>] = [
        1: ["food-intake-summary-v4", "food-intake-summary-v5", "food-intake-summary-v6"],
        2: ["food-intake-summary-v6"]
    ]

    /// The closed `code` set with the `is_estimate` each code must carry (contract 3.2).
    public static let codes: [String: Bool] = [
        "direct": false, "weighed": false, "estimated_by_eye": true, "kitchen_scale": false,
        "package_weight": false, "typical_weight": true, "whole_milk_volume": true, "recorded": false
    ]
    public static let typicalWeightCode = "typical_weight"
    public static let wholeMilkVolumeCode = "whole_milk_volume"
    public static let enteredUnits: Set<String> = ["g", "mL", "count", "serving"]
    public static let sizes: Set<String> = ["small", "medium", "large", "extra_large"]

    public static func validate(_ document: FoodDailyExportDocument) throws {
        let schema = document.foodDailySchemaVersion
        guard let summaryVersions = acceptedSummaryVersions[schema] else {
            throw FoodDailyExportShapeError.unknownSchemaVersion(schema)
        }
        guard summaryVersions.contains(document.summaryVersion) else {
            throw FoodDailyExportShapeError.summaryVersionNotAccepted(schema: schema, summaryVersion: document.summaryVersion)
        }
        switch schema {
        case 1:
            guard document.entries.allSatisfy({ $0.quantity.amountMethod == nil }) else {
                throw FoodDailyExportShapeError.unexpectedAmountMethod
            }
            guard document.notes.quantityEstimates == nil else { throw FoodDailyExportShapeError.unexpectedQuantityEstimates }
        case 2:
            for entry in document.entries {
                guard let method = entry.quantity.amountMethod else { throw FoodDailyExportShapeError.missingAmountMethod }
                try validate(method)
            }
            guard document.notes.quantityEstimates != nil else { throw FoodDailyExportShapeError.missingQuantityEstimates }
        default:
            // A schema added to the map without its presence rule fails closed.
            throw FoodDailyExportShapeError.unknownSchemaVersion(schema)
        }
    }

    /// One row of the closed table.
    static func validate(_ method: FoodDailyExportAmountMethod) throws {
        guard let isEstimate = codes[method.code] else { throw FoodDailyExportShapeError.unknownCode(method.code) }
        guard method.isEstimate == isEstimate else { throw FoodDailyExportShapeError.estimateFlagMismatch(code: method.code) }
        let sourceBacked = method.code == typicalWeightCode || method.code == wholeMilkVolumeCode
        switch (method.source, sourceBacked) {
        case (nil, true): throw FoodDailyExportShapeError.missingSource(code: method.code)
        case (.some, false): throw FoodDailyExportShapeError.unexpectedSource(code: method.code)
        case (nil, false): break
        case let (source?, true):
            if method.code == wholeMilkVolumeCode {
                guard source.size == nil else { throw FoodDailyExportShapeError.unexpectedSize }
            } else {
                guard let size = source.size else { throw FoodDailyExportShapeError.missingSize }
                guard sizes.contains(size) else { throw FoodDailyExportShapeError.unknownSize(size) }
            }
        }
        if let entered = method.entered, !enteredUnits.contains(entered.unit) {
            throw FoodDailyExportShapeError.unknownEnteredUnit(entered.unit)
        }
    }
}
