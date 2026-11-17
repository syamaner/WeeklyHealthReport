import FoodLedgerApplication
import FoodLedgerDomain

// Your food database references (import v1 section 3; phase 1 plan section 5.1 items 8 and 12): each
// record as its adapter's own builder makes it, under `pfc-resolution-v1`, with the adapter's own
// release. The owner chose the record, so its score is 1. Kept apart from the adapters so
// check-boundaries.sh holds this file to no URL loading.

extension CoFIDGenericFoodSearch: GenericRecordResolving {
    public func contains(_ reference: GenericRecordReference) -> Bool {
        reference.source == .cofid && reference.corpusSHA256 == Self.corpusCanonicalSHA256 && hasRecord(reference.recordID)
    }

    public func resolve(_ reference: GenericRecordReference, evidenceIDs: [EvidenceID], queryAlias: String) -> ResolvedGenericRecord? {
        guard reference.source == .cofid, reference.corpusSHA256 == Self.corpusCanonicalSHA256,
              let candidate = referencedCandidate(reference.recordID, evidenceIDs: evidenceIDs, queryAlias: queryAlias) else { return nil }
        return ResolvedGenericRecord(candidate: candidate, release: sourceRelease)
    }
}

extension USDAGenericFoodSearch: GenericRecordResolving {
    public func contains(_ reference: GenericRecordReference) -> Bool {
        reference.source == .usda && reference.corpusSHA256 == Self.corpusSHA256 && hasRecord(reference.recordID)
    }

    public func resolve(_ reference: GenericRecordReference, evidenceIDs: [EvidenceID], queryAlias: String) -> ResolvedGenericRecord? {
        guard reference.source == .usda, reference.corpusSHA256 == Self.corpusSHA256,
              let (candidate, release) = referencedCandidate(reference.recordID, evidenceIDs: evidenceIDs, queryAlias: queryAlias)
        else { return nil }
        return ResolvedGenericRecord(candidate: candidate, release: release)
    }
}

/// Record IDs carry the `tfda:` prefix; the corpus IDs are bare.
extension TFDAGenericFoodSearch: GenericRecordResolving {
    public func contains(_ reference: GenericRecordReference) -> Bool {
        guard let id = Self.corpusID(reference) else { return false }
        return hasRecord(id)
    }

    public func resolve(_ reference: GenericRecordReference, evidenceIDs: [EvidenceID], queryAlias: String) -> ResolvedGenericRecord? {
        guard let id = Self.corpusID(reference), let candidate = referencedCandidate(id, evidenceIDs: evidenceIDs) else { return nil }
        return ResolvedGenericRecord(candidate: candidate, release: sourceRelease)
    }

    private static func corpusID(_ reference: GenericRecordReference) -> String? {
        guard reference.source == .tfda, reference.corpusSHA256 == corpusSHA256, reference.recordID.hasPrefix("tfda:") else { return nil }
        return String(reference.recordID.dropFirst("tfda:".count))
    }
}

// Estimates on catalogue v2 (contract section 7): each record's facts for the importer and Confirm,
// taken from the same candidate `resolve` builds, so the two always agree. A corpus hash other than
// the adapter's pin is told apart from a missing record.

private func facts(_ candidate: PopulatedFoodCandidate) -> GenericRecordFacts {
    GenericRecordFacts(nutrients: candidate.candidate.nutrients, identity: candidate.candidate.identity,
                       edibleQuantity: candidate.candidate.edibleQuantity)
}

extension CoFIDGenericFoodSearch: GenericRecordNutrientLookup {
    public func record(source: PersonalFoodDatabaseGenericSource, corpusSHA256: String, recordID: String)
        -> Result<GenericRecordFacts, GenericRecordLookupFailure> {
        guard source == .cofid, corpusSHA256 == Self.corpusCanonicalSHA256 else { return .failure(.corpusMismatch) }
        guard let candidate = referencedCandidate(recordID, evidenceIDs: [], queryAlias: "") else { return .failure(.recordMissing) }
        return .success(facts(candidate))
    }
}

extension USDAGenericFoodSearch: GenericRecordNutrientLookup {
    public func record(source: PersonalFoodDatabaseGenericSource, corpusSHA256: String, recordID: String)
        -> Result<GenericRecordFacts, GenericRecordLookupFailure> {
        guard source == .usda, corpusSHA256 == Self.corpusSHA256 else { return .failure(.corpusMismatch) }
        guard let (candidate, _) = referencedCandidate(recordID, evidenceIDs: [], queryAlias: "record") else {
            return .failure(.recordMissing)
        }
        return .success(facts(candidate))
    }
}

extension TFDAGenericFoodSearch: GenericRecordNutrientLookup {
    public func record(source: PersonalFoodDatabaseGenericSource, corpusSHA256: String, recordID: String)
        -> Result<GenericRecordFacts, GenericRecordLookupFailure> {
        guard source == .tfda, corpusSHA256 == Self.corpusSHA256 else { return .failure(.corpusMismatch) }
        guard recordID.hasPrefix("tfda:"),
              let candidate = referencedCandidate(String(recordID.dropFirst("tfda:".count)), evidenceIDs: []) else {
            return .failure(.recordMissing)
        }
        return .success(facts(candidate))
    }
}
