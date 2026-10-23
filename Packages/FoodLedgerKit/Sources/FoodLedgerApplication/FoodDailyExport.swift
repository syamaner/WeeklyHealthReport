import Foundation
import FoodLedgerDomain

// Food daily export v1 (`docs/food-daily-export-contract-v1.md`, #287): one selected day's food
// log as its own JSON file. These are export DTOs, not domain types: the builder projects a
// ledger snapshot into them, and the serializer owns the only byte form.

/// The whole file. Keys are written explicitly in snake_case; `sortedKeys` orders the bytes.
public struct FoodDailyExportDocument: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

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
        plainWater: "plain_water counts only plain water entries. The water nutrient in summary already includes plain water and water in foods; do not add the two together."
    )

    public let occurredAt: String
    public let unknownValues: String
    public let plainWater: String

    enum CodingKeys: String, CodingKey {
        case occurredAt = "occurred_at"
        case unknownValues = "unknown_values"
        case plainWater = "plain_water"
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

    public init(amount: Double, unit: String, weightBasis: String) {
        self.amount = amount; self.unit = unit; self.weightBasis = weightBasis
    }

    enum CodingKeys: String, CodingKey {
        case amount, unit
        case weightBasis = "weight_basis"
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
    /// Reviewed web proposals only (D2): the public page address and its content hash.
    public let sourceURL: String?
    public let contentHash: String?

    enum CodingKeys: String, CodingKey {
        case sourceKind = "source_kind"
        case sourceReleaseID = "source_release_id"
        case transforms
        case sourceURL = "source_url"
        case contentHash = "content_hash"
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

public enum FoodDailyExportError: Error, Equatable, Sendable {
    case exportedBeforeDataAsOf
    case invalidTimeZone
    /// A log entry's product or effective resolution version is not in the snapshot.
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
        ProvenanceSourceKind.appReferenceDefinition.rawValue: "app_reference"
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
/// `FoodIntakeProjection` (`food-intake-summary-v4`) and plain water from `PlainWaterDayTotal`, so
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
            for total in row.totals where total.knownAmount != nil {
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
        return FoodDailyExportDocument(
            foodDailySchemaVersion: FoodDailyExportDocument.schemaVersion, reportDate: request.reportDate,
            timeZone: request.timeZone.identifier, dataAsOf: timestamp.string(request.dataAsOf),
            exportedAt: timestamp.string(request.exportedAt), nutrientCatalogueVersion: NutrientSet.catalogueVersion,
            summaryVersion: FoodIntakeSummary.version, entries: entries, summary: summary, plainWater: plainWater,
            notes: .current, appContext: request.appContext)
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
        let scale = FoodIntakeSummary.scale(quantity: head.edibleQuantity, basis: resolution.basis)
        let manifest = pastedLabelManifest(version, records: records)
        let rowOrigin = try sourceRowOrigin(version.nutrients, manifest: manifest)
        let nutrients = try version.nutrients.entries.map { entry in
            try value(entry.value, key: entry.key, includeKey: true, scale: scale, manifest: manifest,
                      rowOrigin: rowOrigin, conflict: entry.status == .conflict ? entry.conflictCandidates : nil)
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
                                              weightBasis: weightBasis),
            versions: versions, basis: basis(resolution.basis), scaleFactor: scale, basisOrigin: basisOrigin,
            nutrients: nutrients)
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

    private static func value(_ value: NutrientValue, key: NutrientKey, includeKey: Bool, scale: Double?,
                              manifest: PastedLabelEvidenceManifest?, rowOrigin: String?,
                              conflict: [NutrientValue]?) throws -> FoodDailyExportNutrientValue {
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
                                             rowOrigin: rowOrigin, conflict: nil) }
        }
        let provenance = value.provenance.map(Self.provenance)
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
