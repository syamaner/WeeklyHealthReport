import FoodLedgerDomain

// Labelled estimates on catalogue v2 (docs/personal-food-catalogue-estimates-v2-proposal.md sections
// 3.1 and 7): the bundled-record lookup and the importer's checks. No file, network or clock.

public enum GenericRecordLookupFailure: Error, Equatable, Sendable {
    /// The corpus hash is not the one the app has pinned for that source (or the source is unknown).
    case corpusMismatch
    case recordMissing
}

/// Consumer-owned port (contract section 7): one bundled record's facts by source, corpus hash and
/// record ID exactly as a file writes them (`tfda:` prefix for TFDA only). Unlike
/// `GenericRecordResolving.resolve`, it tells a moved corpus pin from a missing record.
public protocol GenericRecordNutrientLookup: Sendable {
    func record(source: PersonalFoodDatabaseGenericSource, corpusSHA256: String, recordID: String)
        -> Result<GenericRecordFacts, GenericRecordLookupFailure>
}

/// Dispatches on `source`; a source with no lookup has no pinned corpus.
public struct GenericRecordLookupSet: GenericRecordNutrientLookup {
    private let lookups: [PersonalFoodDatabaseGenericSource: any GenericRecordNutrientLookup]

    public init(_ lookups: [PersonalFoodDatabaseGenericSource: any GenericRecordNutrientLookup]) { self.lookups = lookups }

    public func record(source: PersonalFoodDatabaseGenericSource, corpusSHA256: String, recordID: String)
        -> Result<GenericRecordFacts, GenericRecordLookupFailure> {
        lookups[source]?.record(source: source, corpusSHA256: corpusSHA256, recordID: recordID) ?? .failure(.corpusMismatch)
    }
}

/// The importer's rules for a file the codec accepted (contract section 3.1). For each
/// `national_composition` estimate, in `estimate_evidence` order: `corpus-mismatch`,
/// `record-missing`, `value-unquantified`, `value-mismatch` (the first that fails; the last two need
/// the record), then `estimate-contradiction`, `estimate-basis` and `estimate-own-merge`, each whenever
/// the record was read (gap estimates amendment G2, docs/personal-food-catalogue-gap-estimates-v1-amendment.md;
/// own merge amendment G4, docs/personal-food-catalogue-own-merge-amendment-v1.md).
public enum PersonalFoodDatabaseEstimateAdmission {
    public static let tolerance = 0.005

    /// At zero the file value and the record's value must be exactly equal; otherwise they differ
    /// when more than 0.5 per cent of the record's value apart.
    public static func valueMatches(file: Double, record: Double) -> Bool {
        if record == 0 || file == 0 { return file == record }
        return abs(file - record) <= tolerance * abs(record)
    }

    /// The closed, mechanical contradiction list of contract section 3.1. The basis bullet applies to a
    /// per 100 g entry only; a per 100 ml entry's basis is `basisMismatch` (amendment G2).
    public static func contradicts(entry: PersonalFoodDatabaseEntry, record: GenericRecordFacts) -> Bool {
        if entry.state == .raw || entry.state == .cooked,
           let preparation = try? PersonalFoodDatabaseCandidateBuilder.preparation(entry.state),
           EstimateIdentityComparison.preparationContradicts(record.identity.preparation, preparation) { return true }
        if record.identity.fortification == .fortified { return true }
        return entry.basis == .per100Grams && !record.isPer100GramsEdible
    }

    /// Amendment G2, for a per 100 ml entry: a per 100 ml record (G2b) or, from a per 100 g record, a
    /// value that is exactly zero in the record and in the file (G2a: zero needs no density). Anything
    /// else is `estimate-basis`. A per 100 g entry never gets this code.
    public static func basisMismatch(entry: PersonalFoodDatabaseEntry, estimate: PersonalFoodDatabaseEstimate,
                                     record: GenericRecordFacts) -> Bool {
        guard entry.basis == .per100MillilitresAsLabelled else { return false }
        if record.isPer100Millilitres { return false }
        return !(record.isPer100GramsEdible && estimate.value == 0 && record.quantified(estimate.key) == 0)
    }

    public static func codes(file: PersonalFoodDatabaseFile, lookup: any GenericRecordNutrientLookup) -> [PersonalFoodDatabaseRuleCode] {
        var bound: [(entry: PersonalFoodDatabaseEntry, estimate: PersonalFoodDatabaseEstimate)] = []
        for entry in file.entries {
            for estimate in entry.estimatedNutrients where estimate.evidence.sourceType == .nationalComposition {
                bound.append((entry, estimate))
            }
        }
        // `estimate_evidence` is sorted by ID (rule `evidence-order`), so this is the file's order.
        bound.sort { $0.estimate.evidence.id < $1.estimate.evidence.id }
        var codes: [PersonalFoodDatabaseRuleCode] = []
        for (entry, estimate) in bound {
            guard let source = estimate.evidence.compositionSource, let corpus = file.genericCorpora[source] else {
                codes.append(.corpusMismatch)
                continue
            }
            switch lookup.record(source: source, corpusSHA256: corpus, recordID: estimate.evidence.sourceReference) {
            case .failure(.corpusMismatch): codes.append(.corpusMismatch)
            case .failure(.recordMissing): codes.append(.recordMissing)
            case let .success(record):
                if let value = record.quantified(estimate.key) {
                    if !valueMatches(file: estimate.value, record: value) { codes.append(.valueMismatch) }
                } else {
                    codes.append(.valueUnquantified)
                }
                if contradicts(entry: entry, record: record) { codes.append(.estimateContradiction) }
                if basisMismatch(entry: entry, estimate: estimate, record: record) { codes.append(.estimateBasis) }
                // G4: an estimate from the entry's own merge record only where the app does not merge it.
                if entry.isOwnRecord(estimate.evidence),
                   PersonalFoodDatabaseCandidateBuilder.mergeEligible(entry, facts: record) {
                    codes.append(.estimateOwnMerge)
                }
            }
        }
        return codes
    }
}
