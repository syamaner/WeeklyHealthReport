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
    /// The v1 to v3 method version, which resolver-built "Generic" rows keep for every schema.
    public static let methodVersion = PersonalFoodDatabaseRelease.pipelineVersion
    /// Amendment I1.3: the method version of a candidate, re-resolution target or capture built from a
    /// file of this schema (`pfc-resolution-v2` for v4, `pfc-resolution-v1` otherwise).
    public static func methodVersion(for schema: PersonalFoodDatabaseSchema) -> String {
        PersonalFoodDatabaseRelease.pipelineVersion(for: schema)
    }

    /// The frozen prefix of the Confirm note naming the facts taken from `identity_facts` (amendment I1.4).
    /// The note is saved with the candidate, so its text is data, not copy.
    public static let factsNotePrefix = "Food details from your food database:"

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
        mergeEligible(entry, facts: GenericRecordFacts(nutrients: record.candidate.nutrients,
                                                       identity: record.candidate.identity,
                                                       edibleQuantity: record.candidate.edibleQuantity))
    }

    /// The same rule on a record's facts, so the importer (own merge amendment G4) and the builder
    /// can never disagree about what merges.
    ///
    /// Amendment I1.3 (v4 files only, so only when the entry has `identity_facts`): no fact the file
    /// states is known on both sides and different from the record's, under `EstimateIdentityComparison`.
    public static func mergeEligible(_ entry: PersonalFoodDatabaseEntry, facts: GenericRecordFacts) -> Bool {
        guard let reference = entry.genericReference, reference.role == .merge,
              entry.state == .raw || entry.state == .cooked, entry.basis == .per100Grams,
              let entryPreparation = try? preparation(entry.state) else { return false }
        let identity = facts.identity
        guard identity.preparation.kind == entryPreparation.kind && identity.fortification != .fortified
            && facts.isPer100GramsEdible else { return false }
        guard entry.identityFacts != nil else { return true }
        guard let stated = try? ownIdentity(entry) else { return false }
        return EstimateIdentityComparison.contradictions(record: identity, confirmed: stated).isEmpty
    }

    /// Amendment I1.3, no merge: each fact from `identity_facts` where it is not `unknown`, otherwise
    /// today's mapping (preparation from `state`, every other fact unknown).
    public static func ownIdentity(_ entry: PersonalFoodDatabaseEntry) throws -> DecisiveIdentity {
        let basis: ResolutionBasis = entry.basis == .per100Grams ? .per100Grams : .per100Millilitres
        let facts = entry.identityFacts ?? PersonalFoodDatabaseIdentityFacts()
        return try DecisiveIdentity(
            preparation: facts.preparation == .unknown ? preparation(entry.state) : PreparationState(kind: facts.preparation.kind),
            bone: facts.bone, skin: facts.skin, drained: facts.drained, packingMedium: facts.packingMediumState,
            fortification: facts.fortification.state, servingBasis: basis)
    }

    /// The candidate's identity (amendment I1.3) and the facts it took from `identity_facts`: with a
    /// merge, the record's identity with each fact the record leaves unknown taken from the file (for
    /// a v1 to v3 file, the record's identity exactly, as Amendment A1 says); without one, `ownIdentity`.
    public static func identity(_ entry: PersonalFoodDatabaseEntry, merged record: DecisiveIdentity?) throws
        -> (identity: DecisiveIdentity, fromFile: [IdentityContradiction]) {
        let own = try ownIdentity(entry)
        let facts = entry.identityFacts ?? PersonalFoodDatabaseIdentityFacts()
        guard let record else {
            var stated: [IdentityContradiction] = []
            if facts.preparation != .unknown { stated.append(.preparation) }
            if facts.bone != .unknown { stated.append(.bone) }
            if facts.skin != .unknown { stated.append(.skin) }
            if facts.drained != .unknown { stated.append(.drained) }
            if facts.packingMedium != .unknown { stated.append(.packingMedium) }
            if facts.fortification != .unknown { stated.append(.fortification) }
            return (own, stated)
        }
        guard entry.identityFacts != nil else { return (record, []) }
        var taken: [IdentityContradiction] = []
        func fill<T: Equatable>(_ recordValue: T, _ fileValue: T, unknown: T, _ facet: IdentityContradiction) -> T {
            guard recordValue == unknown, fileValue != unknown else { return recordValue }
            taken.append(facet)
            return fileValue
        }
        // A merge needs a known, equal preparation, so the record's preparation always stands.
        let bone = fill(record.bone, own.bone, unknown: .unknown, .bone)
        let skin = fill(record.skin, own.skin, unknown: .unknown, .skin)
        let drained = fill(record.drained, own.drained, unknown: .unknown, .drained)
        let packing = fill(record.packingMedium, own.packingMedium, unknown: .unknown, .packingMedium)
        let fortification = fill(record.fortification, own.fortification, unknown: .unknown, .fortification)
        return (try DecisiveIdentity(preparation: record.preparation, bone: bone, skin: skin, drained: drained,
                                     packingMedium: packing, fortification: fortification,
                                     declaredFortificants: record.declaredFortificants, servingBasis: record.servingBasis), taken)
    }

    /// The Confirm note (amendment I1.4): the frozen prefix and the facts taken from the file, in plain
    /// words, in facet order; nil when none was taken.
    public static func factsNote(_ identity: DecisiveIdentity, facets: [IdentityContradiction]) -> String? {
        let words: [String] = facets.compactMap { facet in
            switch facet {
            case .preparation:
                switch identity.preparation.kind {
                case .asSold: "as sold"
                case .raw: "raw"
                case .cooked: "cooked"
                default: nil
                }
            case .bone:
                switch identity.bone {
                case .withBone: "with bone"
                case .boneless: "boneless"
                case .notApplicable: "no bone"
                case .unknown: nil
                }
            case .skin:
                switch identity.skin {
                case .skinOn: "skin on"
                case .skinless: "skinless"
                case .notApplicable: "no skin"
                case .unknown: nil
                }
            case .drained:
                switch identity.drained {
                case .drained: "drained"
                case .undrained: "not drained"
                case .notApplicable: "nothing to drain"
                case .unknown: nil
                }
            case .packingMedium:
                switch identity.packingMedium {
                case let .named(text):
                    switch text.value {
                    case "as sold": "packing as sold"
                    case "not applicable": "no packing liquid"
                    case "olive_oil": "in olive oil"
                    default: "in \(text.value)"
                    }
                case .unknown: nil
                }
            case .fortification:
                identity.fortification == .unfortified ? "not fortified" : nil
            case .servingBasis, .edibleQuantity: nil
            }
        }
        return words.isEmpty ? nil : "\(factsNotePrefix) \(words.joined(separator: ", "))"
    }

    /// The facets a frozen-prefix note lists, read back from its words (the note is the only record of
    /// which facts came from the file, so no new field is persisted). Nil when the text is not such a
    /// note or holds a word `factsNote` never writes.
    public static func factsNoteFacets(_ note: String) -> Set<IdentityContradiction>? {
        let prefix = factsNotePrefix + " "
        guard note.hasPrefix(prefix) else { return nil }
        let words: [String: IdentityContradiction] = [
            "as sold": .preparation, "raw": .preparation, "cooked": .preparation,
            "with bone": .bone, "boneless": .bone, "no bone": .bone,
            "skin on": .skin, "skinless": .skin, "no skin": .skin,
            "drained": .drained, "not drained": .drained, "nothing to drain": .drained,
            "packing as sold": .packingMedium, "no packing liquid": .packingMedium,
            "not fortified": .fortification]
        var facets = Set<IdentityContradiction>()
        for word in note.dropFirst(prefix.count).components(separatedBy: ", ") {
            if let facet = words[word] {
                facets.insert(facet)
            } else if word.hasPrefix("in "), word.count > 3 {
                facets.insert(.packingMedium)
            } else {
                return nil
            }
        }
        return facets.isEmpty ? nil : facets
    }

    static func itemClass(_ category: PersonalFoodDatabaseCategory) -> ItemClass {
        category == .beverage || category == .alcohol ? .drink : .food
    }

    /// Builds the entry's candidate, merging `record` only when `mergeEligible`. Returns nil when no
    /// nutrient would be known (section 5.1 item 3).
    ///
    /// `estimates` binds the entry's approved estimates to their capture manifest (estimates on
    /// catalogue v2 section 4): per nutrient a label value, then an estimate, then the merged record.
    /// Without it no estimate reaches the candidate. An estimate never promotes a `candidate`
    /// reference to a merge and never changes the entry's identity.
    public static func build(
        entry: PersonalFoodDatabaseEntry, file: PersonalFoodDatabaseFile, databaseRelease: SourceRelease,
        record: ResolvedGenericRecord?, evidenceIDs: [EvidenceID], score: Double,
        estimates: ApprovedEstimateBinding? = nil
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
            // An approved estimate is always augmented and never shares a key with a label value
            // (rule `label-and-estimate`), so it sits between the label levels and the merged record.
            // Own merge amendment G4, defence in depth: when the record merges, an estimate from that
            // same record never fills a key, whatever the stored file holds (the codec runs on load,
            // the importer only on import).
            let estimated: [NutrientValue] = try estimates.flatMap { binding in
                try entry.estimatedNutrients.first {
                    $0.key == key && !(merge != nil && entry.isOwnRecord($0.evidence))
                }.map {
                    [try estimateValue($0, basis: basis, databaseRelease: databaseRelease, binding: binding)]
                }
            } ?? []
            // A1 item 2: owner values first; for loose fresh food the generic record precedes a
            // retailer product record.
            let levels = !estimated.isEmpty ? [manual, product, estimated, generic]
                : entry.productType == .freshWhole ? [manual, generic, product] : [manual, product, generic]
            guard let level = levels.first(where: { !$0.isEmpty }) else {
                // A merged record that gives its own unknown reason keeps it; otherwise not declared.
                let recordUnknown = merge.flatMap { resolved in
                    resolved.candidate.candidate.nutrients.entries.first { $0.key == key }.flatMap {
                        if case .unknown = $0.value, $0.status == .resolved { $0.value } else { nil }
                    }
                }
                entries.append(try NutrientEntry(key: key, value: recordUnknown ?? .unknown(.notDeclared)))
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
        // Amendment I1.3: the file's facts where it states them; with a merge, only the record's blanks.
        let (identity, fromFile) = try Self.identity(entry, merged: merge?.candidate.candidate.identity)
        let edible = try PositiveQuantity(value: 100, unit: entry.basis == .per100Grams ? .grams : .millilitres)
        // An entry filed per 100 ml by the owner's basis decision has no label (gap estimates amendment G2c).
        var differences = [try LedgerText(entry.basis == .per100Grams
            ? "Your food database entry · per 100 g"
            : entry.labelNutrients.isEmpty ? "Your food database entry · per 100 mL"
            : "Your food database entry · per 100 mL as labelled")]
        // Import v2 (owner decision 3, 13 November 2026): values scaled from a per-serving panel say so,
        // as the barcode route's source line does. Only values the candidate uses count.
        differences += try scaledServings(entries).map { try LedgerText(OpenFoodFactsServingText.databaseEntryNote($0)) }
        if let note = factsNote(identity, facets: fromFile) { differences.append(try LedgerText(note)) }
        let candidate = try PopulatedFoodCandidate(
            candidate: ProviderNeutralCandidate(
                sourceReleaseID: databaseRelease.sourceReleaseID, recordID: ExternalIdentifier(entry.id, field: "record"),
                identity: identity, edibleQuantity: .known(edible, conversionVersionID: nil),
                nutrients: NutrientSet(entries: entries),
                // The manifest is this candidate's own evidence, listed after the request's.
                evidenceIDs: evidenceIDs + (estimates != nil && !entry.estimatedNutrients.isEmpty ? [estimates!.evidenceID] : []),
                matchMetadata: CandidateMatchMetadata(methodVersion: LedgerText(methodVersion(for: file.schema)), score: score,
                    materialDifferences: differences)),
            name: LedgerText(entry.title), brand: try entry.brand.map { try LedgerText($0) },
            itemClass: itemClass(entry.category), packFacts: PackFacts())
        return Built(candidate: candidate, releases: releases, merged: merge != nil)
    }

    /// One approved estimate as an augmented value with `approved_estimate` provenance (estimates v1
    /// section 5.1): the `pfe:` evidence ID as its record, the capture manifest as its evidence.
    static func estimateValue(_ estimate: PersonalFoodDatabaseEstimate, basis: ResolutionBasis, databaseRelease: SourceRelease,
                              binding: ApprovedEstimateBinding) throws -> NutrientValue {
        let derivation = estimate.evidence.derivation
        let provenance = NutrientProvenance(
            sourceKind: .approvedEstimate, sourceID: try ExternalIdentifier(ApprovedEstimateProvenance.sourceID, field: "source"),
            sourceReleaseID: databaseRelease.sourceReleaseID,
            recordID: try ExternalIdentifier(estimate.evidence.id, field: "record"), evidenceID: binding.evidenceID,
            responseHash: binding.manifestHash,
            manifestReference: try LedgerText(ApprovedEstimateProvenance.manifestReference(estimate.key)),
            transforms: try derivation.map {
                [NutrientTransform(transformID: try LedgerText($0.transformID), transformVersion: try LedgerText($0.version))]
            } ?? [])
        let source = try SourceExactNutrientValue(amount: derivation?.sourceValue ?? estimate.value,
            unit: LedgerText(derivation?.sourceUnit ?? estimate.unit.rawValue), basis: basis)
        return .augmented(try ExactNutrientValue(amount: estimate.value, unit: estimate.key.canonicalUnit,
                                                 sourceValue: .exact(source), provenance: [provenance]))
    }

    /// One level of A1: values that agree give that value; a same-level disagreement is a conflict
    /// and the nutrient is unknown (A1 item 3).
    static func resolve(key: NutrientKey, level: [NutrientValue]) throws -> NutrientEntry {
        guard let first = level.first else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
        if level.dropFirst().allSatisfy({ $0 == first }) { return try NutrientEntry(key: key, value: first) }
        return try NutrientEntry(key: key, value: .unknown(.conflictingEvidence), status: .conflict, conflictCandidates: level)
    }

    /// The distinct per-serving sizes behind the candidate's resolved values that carry the
    /// `off-serving-to-100` transform, in nutrient order. One per release is guaranteed by the codec's
    /// `serving-mismatch` rule.
    public static func scaledServings(_ entries: [NutrientEntry]) -> [PositiveQuantity] {
        var servings: [PositiveQuantity] = []
        for entry in entries where entry.status == .resolved {
            guard case let .augmented(value) = entry.value, case let .exact(source) = value.sourceValue,
                  case let .perServing(quantity) = source.basis,
                  value.provenance.contains(where: { provenance in provenance.transforms.contains {
                      $0.transformID.value == OpenFoodFactsServingRule.transformID
                          && $0.transformVersion.value == OpenFoodFactsServingRule.transformVersion
                  } }), !servings.contains(quantity) else { continue }
            servings.append(quantity)
        }
        return servings
    }

    private static func labelValue(
        _ label: PersonalFoodDatabaseLabelValue, key: NutrientKey, basis: ResolutionBasis, reference: LedgerText,
        declared: [String: PersonalFoodDatabaseDeclaredSource]
    ) throws -> NutrientValue {
        guard let source = declared[label.source.sourceRelease] else { throw FoodLedgerValidationError.missingProvenance }
        // Transforms in file order; a scaled value's source is per its serving, never per 100 (import
        // v2), which reproduces the barcode route's provenance for the same record.
        let transforms = try (label.transform?.steps ?? []).map {
            NutrientTransform(transformID: try LedgerText($0.transformID), transformVersion: try LedgerText($0.version))
        }
        let original = try SourceExactNutrientValue(amount: label.transform?.sourceValue ?? label.value,
            unit: LedgerText(label.transform?.sourceUnit ?? label.unit.rawValue),
            basis: label.transform?.serving.map { .perServing($0) } ?? basis)
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
