import Foundation
import FoodLedgerDomain

// Food daily export (`docs/food-daily-export-contract-v1.md`, #287, amended by
// `docs/food-daily-export-contract-v2.md`, #312): one selected day's food log as its own JSON file. These are export DTOs, not domain types: the builder projects a
// ledger snapshot into them, and the serializer owns the only byte form.

/// The whole file. Keys are written explicitly in snake_case; `sortedKeys` orders the bytes.
public struct FoodDailyExportDocument: Codable, Equatable, Sendable {
    /// The schema this build writes (contract v2, #312). Files already written as schema 1 stay
    /// valid and are still read; `FoodDailyExportShape` holds what each schema number admits.
    public static let schemaVersion = 2
    /// The schema of a document holding at least one `approved_estimate` value (estimates on
    /// catalogue v2, daily export version 3): schema 2's shape plus the estimate fields. Any other
    /// document is written as schema 2, byte for byte as before.
    public static let estimatesSchemaVersion = 3

    public let foodDailySchemaVersion: Int
    public let reportDate: String
    public let timeZone: String
    public let dataAsOf: String
    public let exportedAt: String
    public let nutrientCatalogueVersion: Int
    public let summaryVersion: String
    public let entries: [FoodDailyExportEntry]
    public let summary: [FoodDailyExportTotal]
    public let plainWater: FoodDailyExportPlainWater
    public let notes: FoodDailyExportNotes
    public let appContext: FoodDailyExportAppContext

    enum CodingKeys: String, CodingKey {
        case foodDailySchemaVersion = "food_daily_schema_version"
        case reportDate = "report_date"
        case timeZone = "time_zone"
        case dataAsOf = "data_as_of"
        case exportedAt = "exported_at"
        case nutrientCatalogueVersion = "nutrient_catalogue_version"
        case summaryVersion = "summary_version"
        case entries
        case summary
        case plainWater = "plain_water"
        case notes
        case appContext = "app_context"
    }
}

/// Fixed statements the contract requires the file to make about itself, so a reader does not
/// misread sparse or zone-rendered values. Constant text; never personal data.
public struct FoodDailyExportNotes: Codable, Equatable, Sendable {
    public static let current = FoodDailyExportNotes(
        occurredAt: "occurred_at is rendered in time_zone, the zone frozen when the file was prepared. Log entries do not store the zone in force when the food was logged.",
        unknownValues: "Unknown is never zero. A total with any unknown, bounded or unscalable contribution is a known minimum. Most micronutrients are unknown on most days because printed labels usually list only macronutrients and salt.",
        plainWater: "plain_water counts only plain water entries. The water nutrient in summary already includes plain water and water in foods; do not add the two together.",
        quantityEstimates: "quantity.amount_method.is_estimate marks an amount that was estimated (a typical weight, the whole-milk volume rule or an estimate by eye). Every nutrient value in that entry is scaled from the estimated amount, including values whose state is measured. is_estimate false means no estimate rule was recorded for the amount, not that the amount was measured. The code recorded means the method is not described."
    )

    public let occurredAt: String
    public let unknownValues: String
    public let plainWater: String
    /// Schema 2 only (`docs/food-daily-export-contract-v2.md` 3.4, #312): the constant sentence
    /// about estimated amounts. Absent from a schema-1 file, so it is encoded only when present.
    public let quantityEstimates: String?

    init(occurredAt: String, unknownValues: String, plainWater: String, quantityEstimates: String? = nil) {
        self.occurredAt = occurredAt; self.unknownValues = unknownValues; self.plainWater = plainWater
        self.quantityEstimates = quantityEstimates
    }

    enum CodingKeys: String, CodingKey {
        case occurredAt = "occurred_at"
        case unknownValues = "unknown_values"
        case plainWater = "plain_water"
        case quantityEstimates = "quantity_estimates"
    }
}

public struct FoodDailyExportAppContext: Codable, Equatable, Sendable {
    public let appVersion: String
    public let appBuild: String

    public init(appVersion: String, appBuild: String) {
        self.appVersion = appVersion; self.appBuild = appBuild
    }

    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case appBuild = "app_build"
    }
}

public struct FoodDailyExportEntry: Codable, Equatable, Sendable {
    public let logItemID: String
    public let headVersionID: String
    public let occurredAt: String
    public let displayName: String
    public let itemClass: String
    public let quantity: FoodDailyExportQuantity
    public let versions: [FoodDailyExportVersion]
    public let basis: FoodDailyExportBasis
    /// The factor from the basis to the quantity eaten; null when the two cannot be scaled.
    public let scaleFactor: Double?
    /// `chosen_by_you` when the stored pasted-label manifest records an assisted basis choice.
    public let basisOrigin: String?
    public let nutrients: [FoodDailyExportNutrientValue]

    enum CodingKeys: String, CodingKey {
        case logItemID = "log_item_id"
        case headVersionID = "head_version_id"
        case occurredAt = "occurred_at"
        case displayName = "display_name"
        case itemClass = "item_class"
        case quantity
        case versions
        case basis
        case scaleFactor = "scale_factor"
        case basisOrigin = "basis_origin"
        case nutrients
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        logItemID = try values.decode(String.self, forKey: .logItemID)
        headVersionID = try values.decode(String.self, forKey: .headVersionID)
        occurredAt = try values.decode(String.self, forKey: .occurredAt)
        displayName = try values.decode(String.self, forKey: .displayName)
        itemClass = try values.decode(String.self, forKey: .itemClass)
        quantity = try values.decode(FoodDailyExportQuantity.self, forKey: .quantity)
        versions = try values.decode([FoodDailyExportVersion].self, forKey: .versions)
        basis = try values.decode(FoodDailyExportBasis.self, forKey: .basis)
        scaleFactor = try values.decodeIfPresent(Double.self, forKey: .scaleFactor)
        basisOrigin = try values.decodeIfPresent(String.self, forKey: .basisOrigin)
        nutrients = try values.decode([FoodDailyExportNutrientValue].self, forKey: .nutrients)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(logItemID, forKey: .logItemID)
        try values.encode(headVersionID, forKey: .headVersionID)
        try values.encode(occurredAt, forKey: .occurredAt)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(itemClass, forKey: .itemClass)
        try values.encode(quantity, forKey: .quantity)
        try values.encode(versions, forKey: .versions)
        try values.encode(basis, forKey: .basis)
        // An explicit null: "cannot be scaled" is stated, not left out.
        try values.encode(scaleFactor, forKey: .scaleFactor)
        try values.encodeIfPresent(basisOrigin, forKey: .basisOrigin)
        try values.encode(nutrients, forKey: .nutrients)
    }

    init(logItemID: String, headVersionID: String, occurredAt: String, displayName: String, itemClass: String,
         quantity: FoodDailyExportQuantity, versions: [FoodDailyExportVersion], basis: FoodDailyExportBasis,
         scaleFactor: Double?, basisOrigin: String?, nutrients: [FoodDailyExportNutrientValue]) {
        self.logItemID = logItemID; self.headVersionID = headVersionID; self.occurredAt = occurredAt
        self.displayName = displayName; self.itemClass = itemClass; self.quantity = quantity
        self.versions = versions; self.basis = basis; self.scaleFactor = scaleFactor
        self.basisOrigin = basisOrigin; self.nutrients = nutrients
    }
}

public struct FoodDailyExportQuantity: Codable, Equatable, Sendable {
    public let amount: Double
    public let unit: String
    /// `declared` (weighed), `estimated`, or `unknown` when no weight declaration was recorded.
    public let weightBasis: String
    /// Schema 2 only (contract v2 3.1, #312): how the amount was obtained. Absent from every
    /// entry of a schema-1 file, so it is encoded only when present.
    public let amountMethod: FoodDailyExportAmountMethod?

    public init(amount: Double, unit: String, weightBasis: String, amountMethod: FoodDailyExportAmountMethod? = nil) {
        self.amount = amount; self.unit = unit; self.weightBasis = weightBasis; self.amountMethod = amountMethod
    }

    enum CodingKeys: String, CodingKey {
        case amount, unit
        case weightBasis = "weight_basis"
        case amountMethod = "amount_method"
    }
}

/// `quantity.amount_method` of a schema-2 file (contract v2 3.1): the method code, whether the
/// amount is an estimate, what the person entered and, for a source-backed estimate, its frozen
/// rule and release. Every key is always written; a value that does not apply is an explicit
/// `null`, and a file that leaves one of the keys out does not decode (a missing key is not a
/// null). The closed sets are checked by `FoodDailyExportShape`, not here.
public struct FoodDailyExportAmountMethod: Codable, Equatable, Sendable {
    public let code: String
    public let isEstimate: Bool
    /// The amount the person entered when it differs from the exported amount; null otherwise,
    /// or when no original input was stored. Never zero for "unknown".
    public let entered: Entered?
    /// Only for `typical_weight` and `whole_milk_volume`.
    public let source: Source?

    public init(code: String, isEstimate: Bool, entered: Entered?, source: Source?) {
        self.code = code; self.isEstimate = isEstimate; self.entered = entered; self.source = source
    }

    public struct Entered: Codable, Equatable, Sendable {
        public let amount: Double
        /// `g`, `mL`, `count` or `serving`.
        public let unit: String

        public init(amount: Double, unit: String) { self.amount = amount; self.unit = unit }
    }

    public struct Source: Codable, Equatable, Sendable {
        public let methodVersion: String
        public let sourceReleaseID: String
        /// `small`, `medium`, `large` or `extra_large` for a typical weight; null for whole milk.
        public let size: String?

        public init(methodVersion: String, sourceReleaseID: String, size: String?) {
            self.methodVersion = methodVersion; self.sourceReleaseID = sourceReleaseID; self.size = size
        }

        enum CodingKeys: String, CodingKey {
            case methodVersion = "method_version"
            case sourceReleaseID = "source_release_id"
            case size
        }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            methodVersion = try values.decode(String.self, forKey: .methodVersion)
            sourceReleaseID = try values.decode(String.self, forKey: .sourceReleaseID)
            size = try values.decodeExplicit(String.self, forKey: .size)
        }

        public func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(methodVersion, forKey: .methodVersion)
            try values.encode(sourceReleaseID, forKey: .sourceReleaseID)
            try values.encode(size, forKey: .size) // explicit null for whole milk
        }
    }

    enum CodingKeys: String, CodingKey {
        case code
        case isEstimate = "is_estimate"
        case entered, source
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        code = try values.decode(String.self, forKey: .code)
        isEstimate = try values.decode(Bool.self, forKey: .isEstimate)
        entered = try values.decodeExplicit(Entered.self, forKey: .entered)
        source = try values.decodeExplicit(Source.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(code, forKey: .code)
        try values.encode(isEstimate, forKey: .isEstimate)
        try values.encode(entered, forKey: .entered) // explicit null: stated, not left out
        try values.encode(source, forKey: .source)
    }
}

private extension KeyedDecodingContainer {
    /// A value or an explicit `null`; a missing key throws, unlike `decodeIfPresent`.
    func decodeExplicit<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: codingPath, debugDescription: "\(key.stringValue) must be written, as a value or null"))
        }
        return try decodeIfPresent(type, forKey: key)
    }
}

public struct FoodDailyExportVersion: Codable, Equatable, Sendable {
    public let versionID: String
    public let ordinal: Int
    public let supersedesVersionID: String?
    public let correctionReason: String?
    public let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case versionID = "version_id"
        case ordinal
        case supersedesVersionID = "supersedes_version_id"
        case correctionReason = "correction_reason"
        case occurredAt = "occurred_at"
    }
}

public struct FoodDailyExportBasis: Codable, Equatable, Sendable {
    /// `per_100_g`, `per_100_mL`, `per_serving`, `per_unit`, `named` or `unknown`.
    public let kind: String
    public let name: String?
    public let portion: FoodDailyExportPortion?

    public init(kind: String, name: String?, portion: FoodDailyExportPortion?) {
        self.kind = kind; self.name = name; self.portion = portion
    }
}

public struct FoodDailyExportPortion: Codable, Equatable, Sendable {
    public let amount: Double
    public let unit: String

    public init(amount: Double, unit: String) { self.amount = amount; self.unit = unit }
}

/// One nutrient value as an explicit state object (`measured`, `estimated`, `bounded`, `unknown`).
/// `key` is present in an entry's list and absent on conflict candidates.
public struct FoodDailyExportNutrientValue: Codable, Equatable, Sendable {
    public let key: String?
    public let state: String
    public let amount: Double?
    public let lower: Double?
    public let upper: Double?
    public let lowerClosed: Bool?
    public let upperClosed: Bool?
    /// Bounded values only: the bound comes from an estimate (`augmented`) rather than a measurement.
    public let estimated: Bool?
    public let unit: String?
    public let reason: String?
    public let origin: String
    public let calculated: Bool?
    public let provenance: [FoodDailyExportProvenance]?
    public let conflict: Bool?
    public let candidates: [FoodDailyExportNutrientValue]?

    enum CodingKeys: String, CodingKey {
        case key, state, amount, lower, upper
        case lowerClosed = "lower_closed"
        case upperClosed = "upper_closed"
        case estimated, unit, reason, origin, calculated, provenance, conflict, candidates
    }
}

public struct FoodDailyExportProvenance: Codable, Equatable, Sendable {
    public let sourceKind: String
    public let sourceReleaseID: String
    public let transforms: [FoodDailyExportTransform]
    /// Reviewed web proposals (D2): the public page address and its content hash. Approved
    /// estimates from a page (schema 3): the page address and the retained artefact's digest,
    /// absent when none was kept. Never the capture manifest's own hash.
    public let sourceURL: String?
    public let contentHash: String?
    /// Schema 3, `approved_estimate` values only (estimates on catalogue v2 section 3.3; estimates
    /// v1 section 7): the closed tokens of the evidence record. No free text is exported.
    public let estimateSourceType: String?
    public let estimateMethod: String?
    public let estimateStateBasis: String?
    public let estimateQuality: String?

    init(sourceKind: String, sourceReleaseID: String, transforms: [FoodDailyExportTransform], sourceURL: String?,
         contentHash: String?, estimateSourceType: String? = nil, estimateMethod: String? = nil,
         estimateStateBasis: String? = nil, estimateQuality: String? = nil) {
        self.sourceKind = sourceKind; self.sourceReleaseID = sourceReleaseID; self.transforms = transforms
        self.sourceURL = sourceURL; self.contentHash = contentHash; self.estimateSourceType = estimateSourceType
        self.estimateMethod = estimateMethod; self.estimateStateBasis = estimateStateBasis
        self.estimateQuality = estimateQuality
    }

    enum CodingKeys: String, CodingKey {
        case sourceKind = "source_kind"
        case sourceReleaseID = "source_release_id"
        case transforms
        case sourceURL = "source_url"
        case contentHash = "content_hash"
        case estimateSourceType = "estimate_source_type"
        case estimateMethod = "estimate_method"
        case estimateStateBasis = "estimate_state_basis"
        case estimateQuality = "estimate_quality"
    }

    public var isApprovedEstimate: Bool { sourceKind == ProvenanceSourceKind.approvedEstimate.rawValue }
    var hasEstimateField: Bool {
        estimateSourceType != nil || estimateMethod != nil || estimateStateBasis != nil || estimateQuality != nil
    }
}

public struct FoodDailyExportTransform: Codable, Equatable, Sendable {
    public let transformID: String
    public let transformVersion: String

    enum CodingKeys: String, CodingKey {
        case transformID = "transform_id"
        case transformVersion = "transform_version"
    }
}

/// One day total from `FoodIntakeSummary` v4.
public struct FoodDailyExportTotal: Codable, Equatable, Sendable {
    public let key: String
    public let knownAmount: Double?
    public let unit: String
    /// `complete`, `known_minimum`, `none_known` or `unavailable` (overflowed).
    public let state: String
    public let incompleteContributions: Int
    public let includesEstimates: Bool
    public let logItemVersionIDs: [String]

    enum CodingKeys: String, CodingKey {
        case key
        case knownAmount = "known_amount"
        case unit, state
        case incompleteContributions = "incomplete_contributions"
        case includesEstimates = "includes_estimates"
        case logItemVersionIDs = "log_item_version_ids"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decode(String.self, forKey: .key)
        knownAmount = try values.decodeIfPresent(Double.self, forKey: .knownAmount)
        unit = try values.decode(String.self, forKey: .unit)
        state = try values.decode(String.self, forKey: .state)
        incompleteContributions = try values.decode(Int.self, forKey: .incompleteContributions)
        includesEstimates = try values.decode(Bool.self, forKey: .includesEstimates)
        logItemVersionIDs = try values.decode([String].self, forKey: .logItemVersionIDs)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(key, forKey: .key)
        try values.encode(knownAmount, forKey: .knownAmount) // explicit null when nothing is known
        try values.encode(unit, forKey: .unit)
        try values.encode(state, forKey: .state)
        try values.encode(incompleteContributions, forKey: .incompleteContributions)
        try values.encode(includesEstimates, forKey: .includesEstimates)
        try values.encode(logItemVersionIDs, forKey: .logItemVersionIDs)
    }

    init(key: String, knownAmount: Double?, unit: String, state: String, incompleteContributions: Int,
         includesEstimates: Bool, logItemVersionIDs: [String]) {
        self.key = key; self.knownAmount = knownAmount; self.unit = unit; self.state = state
        self.incompleteContributions = incompleteContributions; self.includesEstimates = includesEstimates
        self.logItemVersionIDs = logItemVersionIDs
    }
}

/// `PlainWaterDayTotal.total` in mL, labelled so it is not added to the summary's `water`.
public struct FoodDailyExportPlainWater: Codable, Equatable, Sendable {
    public let knownAmount: Double?
    public let unit: String
    public let state: String
    public let incompleteContributions: Int
    public let includedInSummaryWater: Bool

    enum CodingKeys: String, CodingKey {
        case knownAmount = "known_amount"
        case unit, state
        case incompleteContributions = "incomplete_contributions"
        case includedInSummaryWater = "included_in_summary_water"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        knownAmount = try values.decodeIfPresent(Double.self, forKey: .knownAmount)
        unit = try values.decode(String.self, forKey: .unit)
        state = try values.decode(String.self, forKey: .state)
        incompleteContributions = try values.decode(Int.self, forKey: .incompleteContributions)
        includedInSummaryWater = try values.decode(Bool.self, forKey: .includedInSummaryWater)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(knownAmount, forKey: .knownAmount)
        try values.encode(unit, forKey: .unit)
        try values.encode(state, forKey: .state)
        try values.encode(incompleteContributions, forKey: .incompleteContributions)
        try values.encode(includedInSummaryWater, forKey: .includedInSummaryWater)
    }

    init(knownAmount: Double?, unit: String, state: String, incompleteContributions: Int) {
        self.knownAmount = knownAmount; self.unit = unit; self.state = state
        self.incompleteContributions = incompleteContributions; includedInSummaryWater = true
    }
}

/// A stored amount the closed `amount_method` table (contract v2 3.2) has no row for. None is
/// reachable from a save route; each means no file, like a document the shape rule rejects.
enum FoodDailyExportAmountMethodError: Error, Equatable {
    /// A method that needs its conversion was read without one.
    case conversionNotStored
    /// A source-backed estimate whose conversion names no source release.
    case sourceReleaseNotStored
    /// A label servings conversion whose entered amount is not a count of servings.
    case labelConversionNotInServings
}

public enum FoodDailyExportError: Error, Equatable, Sendable {
    case exportedBeforeDataAsOf
    case invalidTimeZone
    /// A log entry's product, effective resolution version or quantity conversion is not in the
    /// snapshot.
    case missingReference
    /// A provenance source kind has no origin in the closed rule (needs a contract revision).
    case unmappedSource(String)
    /// An entry has no known value and no provenance, so its unknowns have no source row origin.
    case unattributedEntry
}

/// The closed origin rule (contract, Entries). Keyed by the stored raw value so an unmapped kind
/// fails closed at run time as well as at compile time.
public enum FoodDailyExportOrigin {
    public static let bySourceKind: [String: String] = [
        ProvenanceSourceKind.userVerifiedPanel.rawValue: "label_checked_by_you",
        ProvenanceSourceKind.manualDeclaration.rawValue: "entered_by_you",
        ProvenanceSourceKind.exactProductDataset.rawValue: "product_database",
        ProvenanceSourceKind.genericCompositionDataset.rawValue: "food_database",
        ProvenanceSourceKind.recipeReconstruction.rawValue: "recipe",
        ProvenanceSourceKind.reviewedWebProposal.rawValue: "web_review",
        ProvenanceSourceKind.appReferenceDefinition.rawValue: "app_reference",
        ProvenanceSourceKind.approvedEstimate.rawValue: "approved_estimate"
    ]

    public static func origin(sourceKind rawValue: String) throws -> String {
        guard let origin = bySourceKind[rawValue] else { throw FoodDailyExportError.unmappedSource(rawValue) }
        return origin
    }

    /// A pasted-label value's origin, from the one projection every surface uses.
    public static func origin(_ origin: NutrientValueOrigin) -> String {
        switch origin {
        case .printed: "printed"
        case .calculated: "calculated"
        case .correctedByYou: "corrected_by_you"
        case .enteredByYou: "entered_by_you"
        case let .unknown(reason): reason.rawValue
        }
    }
}

public struct FoodDailyExportRequest: Sendable {
    public let records: LedgerMutation
    public let reportDate: String
    public let timeZone: TimeZone
    public let dataAsOf: Date
    public let exportedAt: Date
    public let appContext: FoodDailyExportAppContext

    public init(records: LedgerMutation, reportDate: String, timeZone: TimeZone, dataAsOf: Date, exportedAt: Date,
                appContext: FoodDailyExportAppContext) {
        self.records = records; self.reportDate = reportDate; self.timeZone = timeZone
        self.dataAsOf = dataAsOf; self.exportedAt = exportedAt; self.appContext = appContext
    }
}

/// Projects one reporting date of a ledger snapshot into the export document. Pure: the snapshot,
/// zone and instants are injected. Head-version selection and totals come from
/// `FoodIntakeProjection` (`food-intake-summary-v6`) and plain water from `PlainWaterDayTotal`, so
/// Home, the Health food section and the file cannot disagree. Any error means no document.
public enum FoodDailyExportBuilder {
    public static func make(_ request: FoodDailyExportRequest) throws -> FoodDailyExportDocument {
        guard request.exportedAt >= request.dataAsOf else { throw FoodDailyExportError.exportedBeforeDataAsOf }
        guard !request.timeZone.identifier.isEmpty else { throw FoodDailyExportError.invalidTimeZone }
        let records = request.records
        let projection = try FoodIntakeProjection(records: records, reportingDate: request.reportDate)
        let water = try PlainWaterDayTotal.total(records: records, reportingDate: request.reportDate)
        let timestamp = FoodDailyExportTimestamp(timeZone: request.timeZone)

        var contributors: [NutrientKey: [String]] = [:]
        let entries = try projection.rows.map { row -> FoodDailyExportEntry in
            // v5 (#304): plain water contributes to the summary's water only, as in the summary.
            for total in row.totals where total.knownAmount != nil && (!row.isPlainWater || total.key == .water) {
                contributors[total.key, default: []].append(row.logItemVersionID.rawValue)
            }
            return try entry(row, records: records, timestamp: timestamp)
        }
        let summary = projection.summary.totals.map { total in
            FoodDailyExportTotal(
                key: total.key.rawValue, knownAmount: total.knownAmount, unit: total.key.canonicalUnit.rawValue,
                state: state(total), incompleteContributions: total.incompleteContributions,
                includesEstimates: total.includesEstimates,
                logItemVersionIDs: total.overflowed ? [] : contributors[total.key] ?? [])
        }
        let plainWater = FoodDailyExportPlainWater(
            knownAmount: water?.knownAmount, unit: NutrientUnit.millilitres.rawValue,
            state: water.map(state) ?? "none_known", incompleteContributions: water?.incompleteContributions ?? 0)
        // Schema 3 only for a document holding an approved estimate; a day whose only estimate was
        // withheld or left out holds none and is written as schema 2.
        let holdsEstimate = entries.contains { FoodDailyExportShape.holdsApprovedEstimate($0) }
        let document = FoodDailyExportDocument(
            foodDailySchemaVersion: holdsEstimate ? FoodDailyExportDocument.estimatesSchemaVersion
                : FoodDailyExportDocument.schemaVersion, reportDate: request.reportDate,
            timeZone: request.timeZone.identifier, dataAsOf: timestamp.string(request.dataAsOf),
            exportedAt: timestamp.string(request.exportedAt), nutrientCatalogueVersion: NutrientSet.catalogueVersion,
            summaryVersion: FoodIntakeSummary.version, entries: entries, summary: summary, plainWater: plainWater,
            notes: .current, appContext: request.appContext)
        // Fail closed: the writer never emits a file its own readers would reject (for example a
        // stored combination where the method and the estimate rule disagree). No document then.
        try FoodDailyExportShape.validate(document)
        return document
    }

    static func state(_ total: FoodIntakeTotal) -> String {
        if total.overflowed { return "unavailable" }
        guard total.knownAmount != nil else { return "none_known" }
        return total.incompleteContributions == 0 ? "complete" : "known_minimum"
    }

    private static func entry(_ row: FoodIntakeLogRow, records: LedgerMutation,
                              timestamp: FoodDailyExportTimestamp) throws -> FoodDailyExportEntry {
        guard let head = records.logItemVersions.first(where: { $0.logItemVersionID == row.logItemVersionID }),
              case let .product(productID) = head.composition,
              let product = records.productVersions.first(where: { $0.productVersionID == productID }),
              let version = records.resolutionVersions.first(where: { $0.resolutionVersionID == head.effectiveResolutionVersionID }),
              let resolution = records.resolutions.first(where: { $0.resolutionID == version.resolutionID }) else {
            throw FoodDailyExportError.missingReference
        }
        // Q7 (contract v2 section 7): a contributing head that names a conversion the snapshot
        // does not hold produces no file. Checked before the method is read, because the
        // projection treats a missing conversion as a direct amount.
        var conversion: QuantityConversionVersion?
        if let conversionID = head.quantityConversionVersionID {
            guard let stored = records.quantityConversions.first(where: { $0.quantityConversionVersionID == conversionID }) else {
                throw FoodDailyExportError.missingReference
            }
            conversion = stored
        }
        let amountMethod = try amountMethod(row, head: head, conversion: conversion)
        let scale = FoodIntakeSummary.scale(quantity: head.edibleQuantity, basis: resolution.basis)
        let manifest = pastedLabelManifest(version, records: records)
        let rowOrigin = try sourceRowOrigin(version.nutrients, manifest: manifest)
        let estimates = EstimateManifests(records: records)
        let nutrients = try version.nutrients.entries.map { entry in
            try value(entry.value, key: entry.key, includeKey: true, scale: scale, manifest: manifest,
                      rowOrigin: rowOrigin, conflict: entry.status == .conflict ? entry.conflictCandidates : nil,
                      estimates: estimates)
        }
        let versions = records.logItemVersions.filter { $0.logItemID == head.logItemID }
            .sorted { $0.ordinal.value < $1.ordinal.value }
            .map { FoodDailyExportVersion(versionID: $0.logItemVersionID.rawValue, ordinal: $0.ordinal.value,
                                          supersedesVersionID: $0.supersedesLogItemVersionID?.rawValue,
                                          correctionReason: $0.correctionReason?.value, occurredAt: timestamp.string($0.occurredAt)) }
        let weightBasis = switch head.weightDeclaration?.basis {
        case .measured: "declared"
        case .estimated: "estimated"
        case nil: "unknown"
        }
        var basisOrigin: String?
        if let manifest, case .chosenByYou = manifest.basisOrigin { basisOrigin = "chosen_by_you" }
        return FoodDailyExportEntry(
            logItemID: head.logItemID.rawValue, headVersionID: head.logItemVersionID.rawValue,
            occurredAt: timestamp.string(head.occurredAt), displayName: product.name.value,
            itemClass: product.itemClass.rawValue,
            quantity: FoodDailyExportQuantity(amount: head.edibleQuantity.value, unit: head.edibleQuantity.unit.rawValue,
                                              weightBasis: weightBasis, amountMethod: amountMethod),
            versions: versions, basis: basis(resolution.basis), scaleFactor: scale, basisOrigin: basisOrigin,
            nutrients: nutrients)
    }

    /// `quantity.amount_method` (contract v2 3.1 and 3.2): the export spelling of the projection
    /// row's `quantityMethod`, the value the Food Log row and the saved entry show, so the method
    /// is not derived a second time. `is_estimate` is the one estimate rule that also feeds the
    /// summary's `includes_estimates`. `entered` and `source` are stated per code; a value that
    /// does not apply is nil here and an explicit null in the bytes, never zero. The typed text
    /// of a legacy method (`recorded`) is not read into the file. A state the closed table has
    /// no row for throws, so no file is produced.
    static func amountMethod(_ row: FoodIntakeLogRow, head: LogItemVersion,
                             conversion: QuantityConversionVersion?) throws -> FoodDailyExportAmountMethod {
        typealias Entered = FoodDailyExportAmountMethod.Entered
        typealias Source = FoodDailyExportAmountMethod.Source
        let isEstimate = FoodQuantityEstimate.isEstimate(head, conversion: conversion)
        func method(_ code: String, entered: Entered?, source: Source? = nil) -> FoodDailyExportAmountMethod {
            FoodDailyExportAmountMethod(code: code, isEstimate: isEstimate, entered: entered, source: source)
        }
        func converted() throws -> (entered: Entered, conversion: QuantityConversionVersion) {
            guard let conversion else { throw FoodDailyExportAmountMethodError.conversionNotStored }
            return (Entered(amount: conversion.sourceQuantity.value, unit: conversion.sourceQuantity.unit.rawValue), conversion)
        }
        func source(size: FoodEdibleWeightGuideSize?) throws -> (entered: Entered, source: Source) {
            let stored = try converted()
            guard let release = stored.conversion.sourceReleaseID else { throw FoodDailyExportAmountMethodError.sourceReleaseNotStored }
            return (stored.entered, Source(methodVersion: stored.conversion.methodVersion.value, sourceReleaseID: release.value,
                                           size: size?.rawValue))
        }
        switch row.quantityMethod {
        case .direct:
            guard let conversion else { return method("direct", entered: nil) }
            // A label servings conversion (pasted or photo): the servings the person entered, in
            // the word the Food Log row uses (F1). Anything else has no row in the closed table.
            guard row.amountIsServings, conversion.sourceQuantity.unit == .count else {
                throw FoodDailyExportAmountMethodError.labelConversionNotInServings
            }
            return method("direct", entered: Entered(amount: conversion.sourceQuantity.value, unit: "serving"))
        case .weighed, .estimatedByEye:
            // The original input only when it differs from the exported (net) amount (F5); an
            // absent original input is not the same as the exported amount, so it stays null.
            let original = head.weightDeclaration?.originalInput
            let entered = original.flatMap { $0 == head.edibleQuantity ? nil : Entered(amount: $0.value, unit: $0.unit.rawValue) }
            return method(row.quantityMethod == .weighed ? "weighed" : "estimated_by_eye", entered: entered)
        case .kitchenScale:
            return method("kitchen_scale", entered: try converted().entered)
        case .packageWeight:
            return method("package_weight", entered: try converted().entered)
        case .recorded:
            return method("recorded", entered: try converted().entered)
        case let .typicalWeight(size, _):
            let stored = try source(size: size)
            return method("typical_weight", entered: stored.entered, source: stored.source)
        case .wholeMilkVolume:
            let stored = try source(size: nil)
            return method("whole_milk_volume", entered: stored.entered, source: stored.source)
        }
    }

    /// The stored pasted-label manifest of the entry's source, read the way the saved entry reads it.
    private static func pastedLabelManifest(_ version: NutritionResolutionVersion,
                                            records: LedgerMutation) -> PastedLabelEvidenceManifest? {
        for decisionID in version.decisionIDs {
            guard let decision = records.candidateDecisions.first(where: { $0.candidateDecisionID == decisionID }),
                  records.sourceReleases.contains(where: { $0.sourceReleaseID == decision.candidate.sourceReleaseID
                      && $0.sourceID.value == PastedLabelSource.sourceID }) else { continue }
            if let manifest = PastedLabelValueOrigins.manifest(evidence: records.evidence,
                                                               evidenceIDs: decision.candidate.evidenceIDs) {
                return manifest
            }
        }
        return nil
    }

    /// The origin an unknown carries when no pasted-label manifest decides it: the source row's
    /// origin, from the first provenance in catalogue order (conflict candidates included).
    private static func sourceRowOrigin(_ nutrients: NutrientSet, manifest: PastedLabelEvidenceManifest?) throws -> String? {
        guard manifest == nil else { return nil }
        let provenance = nutrients.entries.lazy.flatMap { [$0.value] + $0.conflictCandidates }.flatMap(\.provenance).first
        return try provenance.map { try FoodDailyExportOrigin.origin(sourceKind: $0.sourceKind.rawValue) }
    }

    /// The capture manifests of a snapshot, read by evidence ID: an `approved_estimate` value's
    /// exported tokens and page address come from its manifest's evidence record, never from the
    /// installed database (estimates v1 section 7).
    struct EstimateManifests {
        let records: LedgerMutation

        func evidence(_ provenance: NutrientProvenance, key: NutrientKey, amount: Double,
                      unit: NutrientUnit) throws -> PersonalFoodDatabaseEstimateEvidence {
            // The manifest must be the one the value names (its stored hash is the provenance's) and
            // must hold this very value, so an altered or swapped manifest never supplies the
            // exported tokens or page address.
            guard let id = provenance.evidenceID,
                  let stored = records.evidence.first(where: { $0.evidenceID == id }),
                  stored.captureMethodVersion.value == ApprovedEstimateProvenance.captureMethodVersion,
                  let hash = stored.byteHash, hash == provenance.responseHash,
                  case let .text(payload) = stored.originalPayload,
                  let manifest = ApprovedEstimateCaptureManifest.decode(Data(payload.value.utf8)),
                  manifest.databaseReleaseID == provenance.sourceReleaseID.value,
                  let captured = manifest.estimate(key), captured.value == amount, captured.unit == unit.rawValue,
                  let typed = captured.evidence.typed, typed.id == provenance.recordID?.value else {
                // Fail closed: an estimate whose manifest cannot be read produces no file.
                throw FoodDailyExportError.missingReference
            }
            return typed
        }
    }

    private static func value(_ value: NutrientValue, key: NutrientKey, includeKey: Bool, scale: Double?,
                              manifest: PastedLabelEvidenceManifest?, rowOrigin: String?,
                              conflict: [NutrientValue]?, estimates: EstimateManifests) throws -> FoodDailyExportNutrientValue {
        let origin: String
        if let manifest {
            origin = FoodDailyExportOrigin.origin(NutrientValueOrigin.project(value, key: key, manifest: manifest))
        } else if let first = value.provenance.first {
            origin = try FoodDailyExportOrigin.origin(sourceKind: first.sourceKind.rawValue)
        } else if let rowOrigin {
            origin = rowOrigin
        } else {
            throw FoodDailyExportError.unattributedEntry
        }
        let candidates = try conflict.map { values in
            try values.map { try self.value($0, key: key, includeKey: false, scale: scale, manifest: manifest,
                                             rowOrigin: rowOrigin, conflict: nil, estimates: estimates) }
        }
        let provenance = try value.provenance.map { provenance -> FoodDailyExportProvenance in
            guard provenance.sourceKind == .approvedEstimate else { return Self.provenance(provenance) }
            // An approved estimate is always an exact augmented value (`NutrientEntry` validation).
            guard case let .augmented(exact) = value else { throw FoodDailyExportError.missingReference }
            return Self.estimateProvenance(provenance, evidence: try estimates.evidence(
                provenance, key: key, amount: exact.amount, unit: exact.unit))
        }
        let calculated = NutrientDerivation.isCalculated(value)
        let exportKey = includeKey ? key.rawValue : nil
        func unknown(_ reason: UnknownReason) -> FoodDailyExportNutrientValue {
            FoodDailyExportNutrientValue(key: exportKey, state: "unknown", amount: nil, lower: nil, upper: nil,
                                         lowerClosed: nil, upperClosed: nil, estimated: nil, unit: nil,
                                         reason: reason.rawValue, origin: origin, calculated: nil, provenance: nil,
                                         conflict: candidates == nil ? nil : true, candidates: candidates)
        }
        switch value {
        case let .measured(exact), let .augmented(exact):
            // An unscalable amount, or one that overflows when scaled, is unknown, never zero.
            guard let scale, (exact.amount * scale).isFinite else { return unknown(.missingConversion) }
            let state = if case .augmented = value { "estimated" } else { "measured" }
            return FoodDailyExportNutrientValue(
                key: exportKey, state: state, amount: exact.amount * scale, lower: nil, upper: nil,
                lowerClosed: nil, upperClosed: nil, estimated: nil, unit: exact.unit.rawValue, reason: nil,
                origin: origin, calculated: calculated, provenance: provenance, conflict: nil, candidates: nil)
        case let .bounded(bounds):
            let lower = scale.flatMap { scale in bounds.lower.map { $0 * scale } }
            let upper = scale.flatMap { scale in bounds.upper.map { $0 * scale } }
            guard scale != nil, lower?.isFinite != false, upper?.isFinite != false else { return unknown(.missingConversion) }
            return FoodDailyExportNutrientValue(
                key: exportKey, state: "bounded", amount: nil, lower: lower, upper: upper,
                lowerClosed: bounds.lowerClosed, upperClosed: bounds.upperClosed,
                estimated: bounds.origin == .augmented, unit: bounds.unit.rawValue, reason: nil, origin: origin,
                calculated: calculated, provenance: provenance, conflict: nil, candidates: nil)
        case let .unknown(reason):
            return unknown(reason)
        }
    }

    /// An approved estimate's provenance (schema 3): the four closed tokens, and for a page type its
    /// public address under the D4 URL rule and the retained artefact's digest when one was kept.
    private static func estimateProvenance(_ provenance: NutrientProvenance,
                                           evidence: PersonalFoodDatabaseEstimateEvidence) -> FoodDailyExportProvenance {
        let page = evidence.sourceType != .nationalComposition
        return FoodDailyExportProvenance(
            sourceKind: provenance.sourceKind.rawValue, sourceReleaseID: provenance.sourceReleaseID.value,
            transforms: provenance.transforms.map {
                FoodDailyExportTransform(transformID: $0.transformID.value, transformVersion: $0.transformVersion.value)
            },
            // HTTPS only (the file rule), and the artefact digest only for a page, as
            // `privacy-and-egress.md` records.
            sourceURL: page && evidence.sourceReference.hasPrefix("https://") ? publicSourceURL(evidence.sourceReference) : nil,
            contentHash: page ? evidence.sourceDigest : nil,
            estimateSourceType: evidence.sourceType.rawValue, estimateMethod: evidence.method.rawValue,
            estimateStateBasis: evidence.stateBasis.rawValue, estimateQuality: evidence.quality.rawValue)
    }

    private static func provenance(_ provenance: NutrientProvenance) -> FoodDailyExportProvenance {
        let web = provenance.sourceKind == .reviewedWebProposal
        let url = web ? provenance.recordID.flatMap { publicSourceURL($0.value) } : nil
        return FoodDailyExportProvenance(
            sourceKind: provenance.sourceKind.rawValue, sourceReleaseID: provenance.sourceReleaseID.value,
            transforms: provenance.transforms.map {
                FoodDailyExportTransform(transformID: $0.transformID.value, transformVersion: $0.transformVersion.value)
            },
            sourceURL: url, contentHash: web ? provenance.responseHash?.value : nil)
    }

    /// The page address a reviewed web value came from: scheme, host, port and path only. The
    /// record ID is "<page URL>#proposal=<candidate>"; the fragment and any query string (which
    /// could carry search words) never leave (owner decision 24 October 2026). Nil when the
    /// record is not an http(s) address, so nothing unparsed is exported.
    static func publicSourceURL(_ record: String) -> String? {
        guard var components = URLComponents(string: record),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              components.host?.isEmpty == false else { return nil }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string
    }

    private static func basis(_ basis: ResolutionBasis) -> FoodDailyExportBasis {
        func portion(_ quantity: PositiveQuantity) -> FoodDailyExportPortion {
            FoodDailyExportPortion(amount: quantity.value, unit: quantity.unit.rawValue)
        }
        return switch basis {
        case .per100Grams: FoodDailyExportBasis(kind: "per_100_g", name: nil, portion: nil)
        case .per100Millilitres: FoodDailyExportBasis(kind: "per_100_mL", name: nil, portion: nil)
        case let .perServing(quantity): FoodDailyExportBasis(kind: "per_serving", name: nil, portion: portion(quantity))
        case let .perUnit(quantity): FoodDailyExportBasis(kind: "per_unit", name: nil, portion: portion(quantity))
        case let .named(name, quantity): FoodDailyExportBasis(kind: "named", name: name.value, portion: portion(quantity))
        case .unknown: FoodDailyExportBasis(kind: "unknown", name: nil, portion: nil)
        }
    }
}

/// ISO 8601 text with milliseconds and the frozen zone's offset, the file's one date form.
public struct FoodDailyExportTimestamp: Sendable {
    public static let format = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    private let timeZone: TimeZone

    public init(timeZone: TimeZone) { self.timeZone = timeZone }

    public func string(_ date: Date) -> String { formatter().string(from: date) }

    /// Parses only this exact form (a value without milliseconds is rejected).
    public static func date(_ text: String) -> Date? {
        let parser = FoodDailyExportTimestamp(timeZone: TimeZone(secondsFromGMT: 0)!).formatter()
        return parser.date(from: text)
    }

    private func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = Self.format
        return formatter
    }
}

/// The file's only byte form: separate from `FoundationCanonicalJSONEncoder` and from the health
/// serializer so neither can drift. Decoding and re-encoding reproduces a file byte for byte.
public enum FoodDailyExportSerializer {
    public static func encode(_ document: FoodDailyExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> FoodDailyExportDocument {
        try JSONDecoder().decode(FoodDailyExportDocument.self, from: data)
    }
}
