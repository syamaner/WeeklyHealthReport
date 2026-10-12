import Foundation
import FoodLedgerDomain

/// The fixed plain water reference record (food quick add contract v1, section 4, Q1 and Q3).
/// Immutable: any change is `plain-water-v2` with a new release and evidence ID, and v1 entries
/// keep resolving to v1. Hashes use the injected digester over the compiled definition bytes.
public struct PlainWaterReference: Sendable {
    public static let sourceID = "weeklyhealthreport.reference"
    public static let release = "plain-water-v1"
    public static let sourceReleaseID = "weeklyhealthreport.reference:plain-water-v1"
    public static let recordID = "plain-water"
    public static let name = "Water"
    /// 2026-10-11T00:00:00Z, the release date and the evidence capture time.
    public static let releasedAt = Date(timeIntervalSince1970: 1_791_676_800)
    public static let evidenceIDValue = "5f1a7e00-0000-4000-8000-00000000a7e1"

    /// The constant canonical definition compiled into the app. Its SHA-256 is the release's
    /// artifact and manifest hash and the evidence byte hash (pinned by a golden test).
    public static let definition = #"{"attribution":"WeeklyHealthReport plain water reference","basis":"per_100_mL","exact":{"carbohydrates":"0 g","cholesterol":"0 mg","energy_consumed":"0 kcal","fat_monounsaturated":"0 g","fat_polyunsaturated":"0 g","fat_saturated":"0 g","fat_total":"0 g","fiber":"0 g","protein":"0 g","sugar":"0 g","water":"100 mL"},"item_class":"water","licence":"App-defined reference; no third-party data","name":"Plain water","record":"plain-water","release":"plain-water-v1","schema":"reference-food-v1","source":"weeklyhealthreport.reference","unknown":"minerals, vitamins and caffeine"}"#

    /// Nutrients known exactly per 100 mL (Q1). Minerals, vitamins and caffeine stay unknown.
    public static let exactPer100Millilitres: [NutrientKey: Double] = [
        .water: 100, .energyConsumed: 0, .protein: 0, .carbohydrates: 0, .fatTotal: 0,
        .fatSaturated: 0, .fatMonounsaturated: 0, .fatPolyunsaturated: 0, .sugar: 0, .fiber: 0, .cholesterol: 0
    ]

    public let definitionHash: SHA256Digest
    public let sourceRelease: SourceRelease
    public let evidence: CaptureEvidence
    public let candidate: PopulatedFoodCandidate
    public let input: PopulatedFoodConfirmation

    public init(digester: any Digesting) throws {
        let hash = try digester.sha256(Data(Self.definition.utf8))
        definitionHash = hash
        let releaseID = try ExternalIdentifier(Self.sourceReleaseID)
        sourceRelease = SourceRelease(
            sourceReleaseID: releaseID, sourceID: try ExternalIdentifier(Self.sourceID),
            releasedAt: Self.releasedAt, artifactHash: hash,
            schemaVersion: try LedgerText("reference-food-v1"), pipelineVersion: try LedgerText(Self.release),
            licence: try LedgerText("App-defined reference; no third-party data"),
            attribution: try LedgerText("WeeklyHealthReport plain water reference"), manifestHash: hash)
        let evidenceID = try EvidenceID(Self.evidenceIDValue)
        evidence = try CaptureEvidence(
            evidenceID: evidenceID, kind: .referenceDefinition, capturedAt: Self.releasedAt,
            locale: LedgerText("en_GB"), captureMethod: LedgerText("app_reference_definition"),
            captureMethodVersion: LedgerText(Self.release),
            originalPayload: .descriptor(LedgerText("weeklyhealthreport.reference/plain-water-v1/plain-water")),
            byteHash: hash)
        let provenance = NutrientProvenance(
            sourceKind: .appReferenceDefinition, sourceID: try ExternalIdentifier(Self.sourceID),
            sourceReleaseID: releaseID, recordID: try ExternalIdentifier(Self.recordID),
            evidenceID: evidenceID, capturedAt: Self.releasedAt, responseHash: hash)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard let amount = Self.exactPer100Millilitres[key] else {
                return try NutrientEntry(key: key, value: .unknown(.notDeclared))
            }
            return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(
                amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Millilitres)),
                provenance: [provenance])))
        })
        let identity = try DecisiveIdentity(
            preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified,
            servingBasis: .per100Millilitres)
        let edible = EdibleQuantityIdentity.known(try PositiveQuantity(value: 100, unit: .millilitres), conversionVersionID: nil)
        let source = try ProviderNeutralCandidate(
            sourceReleaseID: releaseID, recordID: ExternalIdentifier(Self.recordID), identity: identity,
            edibleQuantity: edible, nutrients: nutrients, evidenceIDs: [evidenceID])
        candidate = try PopulatedFoodCandidate(candidate: source, name: LedgerText(Self.name), itemClass: .water)
        input = try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [sourceRelease],
            candidates: [candidate], expectedIdentity: identity, expectedEdibleQuantity: edible)
    }

    /// A fresh confirmation state for logging `millilitres` of plain water now (or at `occurredAt`).
    /// Not accepted: Log in the sheet is the explicit acceptance.
    public func state(millilitres: Double?, occurredAt: Date? = nil) -> FoodConfirmationState {
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        state.quantity = FoodQuantityDraft(value: millilitres, unit: .millilitres)
        state.occurredAt = occurredAt
        return state
    }

    /// The plain water entry predicate: a resolution whose nutrients carry this reference's
    /// provenance (app reference definition, release plain-water-v1, record plain-water). A
    /// corrected entry whose resolution no longer has that provenance leaves the set.
    public static func isPlainWater(_ resolution: NutritionResolutionVersion) -> Bool {
        let provenance = resolution.nutrients.entries.flatMap { $0.value.provenance }
        return !provenance.isEmpty && provenance.allSatisfy {
            $0.sourceKind == .appReferenceDefinition && $0.sourceReleaseID.value == sourceReleaseID
                && $0.recordID?.value == recordID
        }
    }
}

/// Plain water logged on one reporting date, aggregated daily-first in mL (Q8): current heads are
/// summed within the date; removed and superseded versions contribute nothing. Nil means No data
/// (no plain water logged), never 0 mL.
public enum PlainWaterDayTotal {
    public static func millilitres(records: LedgerMutation, reportingDate: String) throws -> Double? {
        let superseded = Set(records.logItemVersions.compactMap(\.supersedesLogItemVersionID))
        let heads = records.logItemVersions.filter { !superseded.contains($0.logItemVersionID) && $0.reportingDate.value == reportingDate }
        let grouped = Dictionary(grouping: records.logItemVersions.filter { !superseded.contains($0.logItemVersionID) }, by: \.logItemID)
        guard heads.allSatisfy({ grouped[$0.logItemID]?.count == 1 }) else { throw FoodIntakeProjectionError.competingVersions }
        let resolutions = Dictionary(records.resolutionVersions.map { ($0.resolutionVersionID, $0) }, uniquingKeysWith: { first, _ in first })
        let bases = Dictionary(records.resolutions.map { ($0.resolutionID, $0.basis) }, uniquingKeysWith: { first, _ in first })
        let contributions: [FoodIntakeContribution] = heads.compactMap { head in
            guard case .product = head.composition,
                  let resolution = resolutions[head.effectiveResolutionVersionID],
                  PlainWaterReference.isPlainWater(resolution) else { return nil }
            return FoodIntakeContribution(quantity: head.edibleQuantity, basis: bases[resolution.resolutionID] ?? .unknown,
                                          nutrients: resolution.nutrients)
        }
        guard !contributions.isEmpty else { return nil }
        return FoodIntakeSummary(contributions: contributions).totals.first { $0.key == .water }?.knownAmount
    }
}
