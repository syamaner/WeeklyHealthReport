import Foundation
import FoodLedgerDomain

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
    /// A schema-1 or schema-2 file carrying an `approved_estimate` value or an estimate field.
    case unexpectedEstimate
    /// A schema-3 file with no `approved_estimate` value.
    case missingEstimate
    /// An `approved_estimate` value without its four tokens, or with one outside its closed list,
    /// or an estimate field on a value of another source kind.
    case invalidEstimateFields
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
        2: ["food-intake-summary-v6"],
        3: ["food-intake-summary-v6"],
        5: ["food-intake-summary-v6"],
        7: ["food-intake-summary-v6"]
    ]

    /// The closed estimate source-type list of each schema (label photo phase gate section 1): never
    /// `allCases`, so a new case cannot widen a released version.
    static func estimateSourceTypes(schema: Int) -> Set<PersonalFoodDatabaseEstimateSourceType> {
        switch schema {
        case 3: Set(PersonalFoodDatabaseEstimateSourceType.estimatesV2List)
        case 5, 7: Set(PersonalFoodDatabaseEstimateSourceType.estimatesV2List + [.productDatasetPhoto])
        default: []
        }
    }

    /// Whether any value of the entry is a label photo estimate (conflict candidates included).
    public static func holdsPhotoEstimate(_ entry: FoodDailyExportEntry) -> Bool {
        provenance(entry).contains {
            $0.isApprovedEstimate && $0.estimateSourceType == PersonalFoodDatabaseEstimateSourceType.productDatasetPhoto.rawValue
        }
    }

    /// Whether any value of the entry is an OpenRouter estimate (conflict candidates included).
    public static func holdsOpenRouterEstimate(_ entry: FoodDailyExportEntry) -> Bool {
        provenance(entry).contains(where: \.isOpenRouterEstimate)
    }

    static let openRouterEstimateOrigin = "openrouter_estimate"

    /// Schema 7: an `openrouter_estimate` provenance carries the constant release ID, `low`, the model,
    /// the contract and a 64-hex response hash, no estimates v2 token, address or digest; no other
    /// provenance carries one of the three fields.
    static func validateOpenRouterFields(_ provenance: FoodDailyExportProvenance) throws {
        guard provenance.isOpenRouterEstimate else {
            guard !provenance.hasOpenRouterField else { throw FoodDailyExportShapeError.invalidEstimateFields }
            return
        }
        guard provenance.sourceReleaseID == OpenRouterEstimateProvenance.sourceID, provenance.transforms.isEmpty,
              provenance.sourceURL == nil, provenance.contentHash == nil,
              provenance.estimateSourceType == nil, provenance.estimateMethod == nil, provenance.estimateStateBasis == nil,
              provenance.estimateQuality == OpenRouterEstimateProvenance.tier,
              let model = provenance.estimateModel, !model.isEmpty,
              provenance.estimateContract == ConfirmEnrichmentVersions.contract,
              let hash = provenance.estimateResponseSHA256, hash.utf8.count == 64,
              hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw FoodDailyExportShapeError.invalidEstimateFields
        }
    }

    /// Schema 7: a value whose provenance is an OpenRouter estimate is `estimated`, origin
    /// `openrouter_estimate`, not calculated, with that one provenance. No other value carries that
    /// origin: an unknown keeps its source's origin.
    static func validateOpenRouterValue(_ value: FoodDailyExportNutrientValue) throws {
        let provenance = value.provenance ?? []
        guard provenance.contains(where: \.isOpenRouterEstimate) else {
            if value.origin == openRouterEstimateOrigin { throw FoodDailyExportShapeError.invalidEstimateFields }
            return
        }
        guard provenance.count == 1, value.state == "estimated", value.origin == openRouterEstimateOrigin,
              value.calculated == false else {
            throw FoodDailyExportShapeError.invalidEstimateFields
        }
    }

    /// Whether any value of the entry is an approved estimate (conflict candidates included).
    public static func holdsApprovedEstimate(_ entry: FoodDailyExportEntry) -> Bool {
        provenance(entry).contains(where: \.isApprovedEstimate)
    }

    static func provenance(_ entry: FoodDailyExportEntry) -> [FoodDailyExportProvenance] {
        values(entry).flatMap { $0.provenance ?? [] }
    }

    static func values(_ entry: FoodDailyExportEntry) -> [FoodDailyExportNutrientValue] {
        entry.nutrients.flatMap { [$0] + ($0.candidates ?? []) }
    }

    static let approvedEstimateOrigin = "approved_estimate"

    /// Schema 3: a value whose provenance is an approved estimate is exactly what the builder
    /// writes for one: state `estimated`, origin `approved_estimate`, that one provenance, a page
    /// address (https, no query or fragment) exactly for a page estimate, and a content hash only on
    /// a page estimate. A value with that origin and no such provenance is an unknown value of an
    /// entry led by an estimate, and nothing else.
    static func validateEstimateValue(_ value: FoodDailyExportNutrientValue, schema: Int) throws {
        let provenance = value.provenance ?? []
        guard provenance.contains(where: \.isApprovedEstimate) else {
            if value.origin == approvedEstimateOrigin, value.state != "unknown" { throw FoodDailyExportShapeError.invalidEstimateFields }
            return
        }
        guard provenance.count == 1, let only = provenance.first, value.state == "estimated",
              value.origin == approvedEstimateOrigin,
              let type = only.estimateSourceType.flatMap(PersonalFoodDatabaseEstimateSourceType.init(rawValue:)),
              estimateSourceTypes(schema: schema).contains(type) else {
            throw FoodDailyExportShapeError.invalidEstimateFields
        }
        if type == .productDatasetPhoto {
            // Label photo estimates v1 section 2.1: the photo address form and a 64-hex digest.
            guard let url = only.sourceURL, PersonalFoodDatabasePhotoAddress.isPhoto(url),
                  let hash = only.contentHash, hash.utf8.count == 64,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw FoodDailyExportShapeError.invalidEstimateFields
            }
        } else if type == .nationalComposition {
            guard only.sourceURL == nil, only.contentHash == nil else { throw FoodDailyExportShapeError.invalidEstimateFields }
        } else {
            guard let url = only.sourceURL, url.hasPrefix("https://"), !url.contains("?"), !url.contains("#") else {
                throw FoodDailyExportShapeError.invalidEstimateFields
            }
        }
    }

    /// Schema 3 (estimates on catalogue v2): every `approved_estimate` provenance carries its four
    /// tokens from the closed lists, and no other provenance carries one.
    static func validateEstimateFields(_ provenance: FoodDailyExportProvenance, schema: Int) throws {
        guard provenance.isApprovedEstimate else {
            // An OpenRouter estimate's `estimate_quality` is checked by its own schema 7 rule.
            guard provenance.isOpenRouterEstimate || !provenance.hasEstimateField else {
                throw FoodDailyExportShapeError.invalidEstimateFields
            }
            return
        }
        guard let type = provenance.estimateSourceType.flatMap(PersonalFoodDatabaseEstimateSourceType.init(rawValue:)),
              estimateSourceTypes(schema: schema).contains(type),
              provenance.estimateMethod.flatMap(PersonalFoodDatabaseEstimateMethod.init(rawValue:)) != nil,
              provenance.estimateStateBasis.flatMap(PersonalFoodDatabaseEstimateStateBasis.init(rawValue:)) != nil,
              provenance.estimateQuality.flatMap(PersonalFoodDatabaseEstimateQuality.init(rawValue:)) != nil else {
            throw FoodDailyExportShapeError.invalidEstimateFields
        }
    }

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
        let provenance = document.entries.flatMap(provenance)
        let values = document.entries.flatMap(values)
        // The OpenRouter estimate origin and its three fields exist only in schema 7, which requires one.
        if schema == 7 {
            guard provenance.contains(where: \.isOpenRouterEstimate) else { throw FoodDailyExportShapeError.missingEstimate }
            guard document.notes.openRouterEstimates == FoodDailyExportNotes.openRouterEstimatesSentence else {
                throw FoodDailyExportShapeError.invalidEstimateFields
            }
            try provenance.forEach(validateOpenRouterFields)
            try values.forEach(validateOpenRouterValue)
            // Approved and photo estimates may be present alongside, as version 5 admits them.
            try provenance.forEach { try validateEstimateFields($0, schema: schema) }
            try values.forEach { try validateEstimateValue($0, schema: schema) }
        } else if provenance.contains(where: { $0.isOpenRouterEstimate || $0.hasOpenRouterField })
                    || values.contains(where: { $0.origin == Self.openRouterEstimateOrigin })
                    || document.notes.openRouterEstimates != nil {
            throw FoodDailyExportShapeError.unexpectedEstimate
        } else if schema == 3 || schema == 5 {
            guard provenance.contains(where: \.isApprovedEstimate) else { throw FoodDailyExportShapeError.missingEstimate }
            // Schema 5 exactly when a photo estimate is present (label photo estimates v1 section 4).
            guard (schema == 5) == document.entries.contains(where: holdsPhotoEstimate) else {
                throw FoodDailyExportShapeError.invalidEstimateFields
            }
            try provenance.forEach { try validateEstimateFields($0, schema: schema) }
            try values.forEach { try validateEstimateValue($0, schema: schema) }
        } else if provenance.contains(where: { $0.isApprovedEstimate || $0.hasEstimateField })
                    || values.contains(where: { $0.origin == Self.approvedEstimateOrigin }) {
            // Schemas 1 and 2 never carry an estimate: no provenance kind, field or origin.
            throw FoodDailyExportShapeError.unexpectedEstimate
        }
        switch schema {
        case 1:
            guard document.entries.allSatisfy({ $0.quantity.amountMethod == nil }) else {
                throw FoodDailyExportShapeError.unexpectedAmountMethod
            }
            guard document.notes.quantityEstimates == nil else { throw FoodDailyExportShapeError.unexpectedQuantityEstimates }
        case 2, 3, 5, 7:
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
