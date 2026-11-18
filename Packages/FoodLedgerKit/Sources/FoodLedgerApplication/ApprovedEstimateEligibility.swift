import FoodLedgerDomain

// Approved estimates on Confirm (estimates on catalogue v2 section 3.2): one pure policy, used when a
// candidate is bound to Confirm, after each correction of details, on undo of a leave-out and in
// re-resolution. It never reads a record itself: the caller supplies what it read.

/// The bundled record a `national_composition` estimate cites, as its capture manifest names it.
public struct ApprovedEstimateRecordKey: Hashable, Codable, Sendable {
    public let source: String
    public let corpusSHA256: String
    public let recordID: String

    public init(source: String, corpusSHA256: String, recordID: String) {
        self.source = source; self.corpusSHA256 = corpusSHA256; self.recordID = recordID
    }

    /// Nil for a page estimate, or a composition estimate whose manifest holds no corpus hash.
    public init?(_ estimate: ApprovedEstimateCaptureManifest.Estimate) {
        guard let source = estimate.evidence.compositionSource, let corpus = estimate.corpusSHA256 else { return nil }
        self.init(source: source, corpusSHA256: corpus, recordID: estimate.evidence.sourceReference)
    }
}

/// What was read for a cited record. A record that was never read counts as unreadable.
public enum ApprovedEstimateRecordState: Equatable, Codable, Sendable {
    case identity(DecisiveIdentity)
    /// The corpus pin moved, the record is missing, or no lookup is wired.
    case unreadable
}

/// Why an estimate is unknown for this log although the file offered it.
public enum ApprovedEstimateWithholding: Hashable, Sendable {
    /// A decisive facet known on both sides and different.
    case facet(IdentityContradiction)
    /// The serving basis was changed away from the entry's own: a value is never reinterpreted.
    case basis
    /// "Estimate left out: its source record could not be read".
    case unreadableRecord
    /// The capture manifest is missing or does not verify.
    case evidenceUnavailable
}

public enum ApprovedEstimateEligibility {
    /// The estimates withheld for these details, with the reason. Nothing is substituted: a withheld
    /// nutrient is unknown for the log.
    public static func withheld(
        manifest: ApprovedEstimateCaptureManifest, records: [ApprovedEstimateRecordKey: ApprovedEstimateRecordState],
        confirmed: DecisiveIdentity, candidateBasis: ResolutionBasis
    ) -> [NutrientKey: ApprovedEstimateWithholding] {
        var result: [NutrientKey: ApprovedEstimateWithholding] = [:]
        for estimate in manifest.estimates {
            guard let key = estimate.key else { continue }
            if let reason = withholding(estimate, records: records, confirmed: confirmed, candidateBasis: candidateBasis) {
                result[key] = reason
            }
        }
        return result
    }

    public static func withholding(
        _ estimate: ApprovedEstimateCaptureManifest.Estimate,
        records: [ApprovedEstimateRecordKey: ApprovedEstimateRecordState],
        confirmed: DecisiveIdentity, candidateBasis: ResolutionBasis
    ) -> ApprovedEstimateWithholding? {
        // Page estimates included: no approved estimate survives a basis change.
        if confirmed.servingBasis != candidateBasis { return .basis }
        guard estimate.evidence.sourceType == PersonalFoodDatabaseEstimateSourceType.nationalComposition.rawValue else { return nil }
        guard let key = ApprovedEstimateRecordKey(estimate), case let .identity(record)? = records[key] else {
            return .unreadableRecord
        }
        return EstimateIdentityComparison.contradictions(record: record, confirmed: confirmed).first.map(ApprovedEstimateWithholding.facet)
    }
}
