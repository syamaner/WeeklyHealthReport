import Foundation
import FoodLedgerDomain

/// A generic record named by a Your food database entry (import v1 section 4).
public struct GenericRecordReference: Equatable, Hashable, Sendable {
    public let source: PersonalFoodDatabaseGenericSource
    public let corpusSHA256: String
    public let recordID: String

    public init(source: PersonalFoodDatabaseGenericSource, corpusSHA256: String, recordID: String) {
        self.source = source
        self.corpusSHA256 = corpusSHA256
        self.recordID = recordID
    }

    public init(_ reference: PersonalFoodDatabaseGenericReference) {
        self.init(source: reference.source, corpusSHA256: reference.corpusSHA256, recordID: reference.recordID)
    }
}

/// The adapter's own candidate for a referenced record and the adapter's own release.
public struct ResolvedGenericRecord: Equatable, Sendable {
    public let candidate: PopulatedFoodCandidate
    public let release: SourceRelease

    public init(candidate: PopulatedFoodCandidate, release: SourceRelease) {
        self.candidate = candidate
        self.release = release
    }
}

/// Consumer-owned port (import v1 section 3; phase 1 plan section 5.1 item 8). Never throws: a
/// corpus hash that differs from the adapter's pin, an unknown record or another source's record
/// is unresolved (nil / false).
public protocol GenericRecordResolving: Sendable {
    /// The record as the adapter's own candidate builder makes it, with the request's evidence IDs
    /// and `pfc-resolution-v1` match metadata scored for `queryAlias`.
    func resolve(_ reference: GenericRecordReference, evidenceIDs: [EvidenceID], queryAlias: String) -> ResolvedGenericRecord?
    /// Cheap existence check for the Settings unresolved count.
    func contains(_ reference: GenericRecordReference) -> Bool
}

/// Dispatches on `source`; a source with no resolver is unresolved.
public struct GenericRecordResolverSet: GenericRecordResolving {
    private let resolvers: [PersonalFoodDatabaseGenericSource: any GenericRecordResolving]

    public init(_ resolvers: [PersonalFoodDatabaseGenericSource: any GenericRecordResolving]) {
        self.resolvers = resolvers
    }

    public func resolve(_ reference: GenericRecordReference, evidenceIDs: [EvidenceID], queryAlias: String) -> ResolvedGenericRecord? {
        resolvers[reference.source]?.resolve(reference, evidenceIDs: evidenceIDs, queryAlias: queryAlias)
    }

    public func contains(_ reference: GenericRecordReference) -> Bool {
        resolvers[reference.source]?.contains(reference) ?? false
    }
}

/// Pure candidate builder for one Your food database entry (import v1 sections 4.1 and 6; phase 1
/// plan section 5.1 items 2, 3, 9 and 10). Nothing is inferred from a title; a value that cannot be
/// represented stays unknown.
public enum PersonalFoodDatabaseCandidateBuilder {
    public static let methodVersion = "pfc-resolution-v1"

    public struct Built: Equatable, Sendable {
        public let candidate: PopulatedFoodCandidate
        /// Every release the candidate's provenance names, the database release first.
        public let releases: [SourceRelease]
        /// True when the referenced record's values were merged in.
        public let merged: Bool
    }

    /// The entry's own preparation for the merge and its identity (section 4.1).
    static func preparation(_ state: PersonalFoodDatabaseState) throws -> PreparationState {
        switch state {
        case .raw: try PreparationState(kind: .raw)
        case .cooked: try PreparationState(kind: .cooked)
        case .canned, .frozen, .dried, .smoked, .unknown: try PreparationState(kind: .unknown)
        }
    }

    /// Section 5.1 item 2: role `merge`, entry `raw` or `cooked`, basis per 100 g, and a record whose
    /// preparation kind is known and equal, per 100 g with a known 100 g edible quantity, and not
    /// fortified (an entry is never a fortified food).
    public static func mergeEligible(_ entry: PersonalFoodDatabaseEntry, record: PopulatedFoodCandidate) -> Bool {
        guard let reference = entry.genericReference, reference.role == .merge,
              entry.state == .raw || entry.state == .cooked, entry.basis == .per100Grams,
              let entryPreparation = try? preparation(entry.state) else { return false }
        let identity = record.candidate.identity
        guard identity.preparation.kind == entryPreparation.kind, identity.servingBasis == .per100Grams,
              identity.fortification != .fortified else { return false }
        guard case let .known(quantity, conversion) = record.candidate.edibleQuantity, conversion == nil,
              quantity.unit == .grams, quantity.value == 100 else { return false }
        return true
    }

    static func itemClass(_ category: PersonalFoodDatabaseCategory) -> ItemClass {
        category == .beverage || category == .alcohol ? .drink : .food
    }

    /// Builds the entry's candidate, merging `record` only when `mergeEligible`. Returns nil when no
    /// nutrient would be known (section 5.1 item 3).
    public static func build(
        entry: PersonalFoodDatabaseEntry, file: PersonalFoodDatabaseFile, databaseRelease: SourceRelease,
        record: ResolvedGenericRecord?, evidenceIDs: [EvidenceID], score: Double
    ) throws -> Built? {
        let merge = record.flatMap { mergeEligible(entry, record: $0.candidate) ? $0 : nil }
        let basis: ResolutionBasis = entry.basis == .per100Grams ? .per100Grams : .per100Millilitres
        let reference = try LedgerText("\(databaseRelease.sourceReleaseID.value)#\(entry.id)")
        let declared = Dictionary(file.sources.map { ($0.sourceReleaseID, $0) }, uniquingKeysWith: { first, _ in first })
        var cited: [String] = []
        var entries: [NutrientEntry] = []
        var anyKnown = false
        for key in NutrientKey.allCases {
            let labels = entry.labelNutrients.filter { $0.key == key }.map(\.value)
            let manual = try labels.filter { if case .manualDeclaration = $0.source { true } else { false } }
                .map { try labelValue($0, key: key, basis: basis, reference: reference, declared: declared) }
            let product = try labels.filter { if case .exactProductDataset = $0.source { true } else { false } }
                .map { try labelValue($0, key: key, basis: basis, reference: reference, declared: declared) }
            let generic: [NutrientValue] = merge.flatMap { resolved in
                resolved.candidate.candidate.nutrients.entries.first { $0.key == key }.flatMap {
                    if case .augmented = $0.value { [$0.value] } else { nil }
                }
            } ?? []
            // A1 item 2: owner values first; for loose fresh food the generic record precedes a
            // retailer product record.
            let levels = entry.productType == .freshWhole ? [manual, generic, product] : [manual, product, generic]
            guard let level = levels.first(where: { !$0.isEmpty }) else {
                entries.append(try NutrientEntry(key: key, value: .unknown(.notDeclared)))
                continue
            }
            let resolved = try resolve(key: key, level: level)
            entries.append(resolved)
            if resolved.status == .resolved { anyKnown = true }
            for provenance in (resolved.conflictCandidates.isEmpty ? [resolved.value] : resolved.conflictCandidates)
                .flatMap(\.provenance) where !cited.contains(provenance.sourceReleaseID.value) {
                cited.append(provenance.sourceReleaseID.value)
            }
        }
        guard anyKnown else { return nil }
        var releases = [databaseRelease]
        for id in cited where id != databaseRelease.sourceReleaseID.value {
            if let merge, merge.release.sourceReleaseID.value == id {
                releases.append(merge.release)
            } else if let source = declared[id] {
                releases.append(try source.sourceRelease())
            } else {
                throw FoodLedgerValidationError.missingProvenance
            }
        }
        let identity: DecisiveIdentity
        if let merge {
            identity = merge.candidate.candidate.identity
        } else {
            identity = try DecisiveIdentity(preparation: preparation(entry.state), bone: .unknown, skin: .unknown,
                drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: basis)
        }
        let edible = try PositiveQuantity(value: 100, unit: entry.basis == .per100Grams ? .grams : .millilitres)
        let candidate = try PopulatedFoodCandidate(
            candidate: ProviderNeutralCandidate(
                sourceReleaseID: databaseRelease.sourceReleaseID, recordID: ExternalIdentifier(entry.id, field: "record"),
                identity: identity, edibleQuantity: .known(edible, conversionVersionID: nil),
                nutrients: NutrientSet(entries: entries), evidenceIDs: evidenceIDs,
                matchMetadata: CandidateMatchMetadata(methodVersion: LedgerText(methodVersion), score: score,
                    materialDifferences: [LedgerText(entry.basis == .per100Grams
                        ? "Your food database entry · per 100 g"
                        : "Your food database entry · per 100 mL as labelled")])),
            name: LedgerText(entry.title), brand: try entry.brand.map { try LedgerText($0) },
            variant: LedgerText("Your food database"), itemClass: itemClass(entry.category), packFacts: PackFacts())
        return Built(candidate: candidate, releases: releases, merged: merge != nil)
    }

    /// One level of A1: values that agree give that value; a same-level disagreement is a conflict
    /// and the nutrient is unknown (A1 item 3).
    static func resolve(key: NutrientKey, level: [NutrientValue]) throws -> NutrientEntry {
        guard let first = level.first else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
        if level.dropFirst().allSatisfy({ $0 == first }) { return try NutrientEntry(key: key, value: first) }
        return try NutrientEntry(key: key, value: .unknown(.conflictingEvidence), status: .conflict, conflictCandidates: level)
    }

    private static func labelValue(
        _ label: PersonalFoodDatabaseLabelValue, key: NutrientKey, basis: ResolutionBasis, reference: LedgerText,
        declared: [String: PersonalFoodDatabaseDeclaredSource]
    ) throws -> NutrientValue {
        guard let source = declared[label.source.sourceRelease] else { throw FoodLedgerValidationError.missingProvenance }
        let transforms = try label.transform.map {
            [NutrientTransform(transformID: try LedgerText($0.transformID), transformVersion: try LedgerText($0.version))]
        } ?? []
        let original = try SourceExactNutrientValue(amount: label.transform?.sourceValue ?? label.value,
            unit: LedgerText(label.transform?.sourceUnit ?? label.unit.rawValue), basis: basis)
        let releaseID = try ExternalIdentifier(source.sourceReleaseID, field: "source release")
        let sourceID = try ExternalIdentifier(source.sourceID.rawValue, field: "source")
        switch label.source {
        case .manualDeclaration:
            // Decision 11: owner-typed or owner-confirmed label values stay measured.
            let provenance = NutrientProvenance(sourceKind: .manualDeclaration, sourceID: sourceID,
                sourceReleaseID: releaseID, manifestReference: reference, transforms: transforms)
            return .measured(try ExactNutrientValue(amount: label.value, unit: key.canonicalUnit,
                sourceValue: .exact(original), provenance: [provenance]))
        case let .exactProductDataset(_, recordID):
            let provenance = NutrientProvenance(sourceKind: .exactProductDataset, sourceID: sourceID,
                sourceReleaseID: releaseID, recordID: try ExternalIdentifier(recordID, field: "record"),
                manifestReference: reference, transforms: transforms)
            return .augmented(try ExactNutrientValue(amount: label.value, unit: key.canonicalUnit,
                sourceValue: .exact(original), provenance: [provenance]))
        }
    }
}
