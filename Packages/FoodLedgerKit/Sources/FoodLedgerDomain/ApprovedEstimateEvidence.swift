import Foundation

// Evidence an approved estimate is saved with (estimates v1 section 5.2; estimates on catalogue v2
// sections 3.2, 3.3 and 5). Both payloads are canonical JSON held inline in a `.labelText`
// `CaptureEvidence`, selected by `captureMethodVersion`, so saved evidence never depends on the
// installed database. Decoding is strict: an unknown or missing key at any level is not a manifest.

/// Compares the keys actually present with a closed key set (a typed key container silently drops
/// unknown keys, so a dynamic one is used).
enum ApprovedEstimateStrictKeys {
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    static func require<Keys: CodingKey & CaseIterable>(_ keys: Keys.Type, in decoder: any Decoder) throws {
        let present = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
        guard Set(present) == Set(Keys.allCases.map(\.stringValue)), present.count == Keys.allCases.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected or missing keys"))
        }
    }
}

/// `pfd-estimate-capture-v1`: what was offered when a Your food database candidate with at least one
/// estimate was bound to Confirm. Built once and never edited: a leave-out or a withheld value
/// changes the log, never this record. It holds no time, no evidence ID, no local path and no other
/// entry's data, so the same release and entry always give the same bytes.
public struct ApprovedEstimateCaptureManifest: Codable, Equatable, Sendable {
    public static let schema = ApprovedEstimateProvenance.captureMethodVersion

    /// One estimate with its whole evidence record, as imported.
    public struct Estimate: Codable, Equatable, Sendable {
        public let nutrient: String
        public let value: Double
        public let unit: String
        /// Beside each `national_composition` estimate (estimates on catalogue v2 section 3.2), so a
        /// later re-check reads the record with saved data; null for a page estimate.
        public let corpusSHA256: String?
        public let evidence: Evidence

        enum CodingKeys: String, CodingKey, CaseIterable {
            case nutrient, value, unit, evidence
            case corpusSHA256 = "corpus_sha256"
        }

        public init(_ estimate: PersonalFoodDatabaseEstimate, corpusSHA256: String?) {
            nutrient = estimate.key.rawValue
            value = estimate.value
            unit = estimate.unit.rawValue
            self.corpusSHA256 = corpusSHA256
            evidence = Evidence(estimate.evidence)
        }

        public init(from decoder: any Decoder) throws {
            try ApprovedEstimateStrictKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nutrient = try c.decode(String.self, forKey: .nutrient)
            value = try c.decode(Double.self, forKey: .value)
            unit = try c.decode(String.self, forKey: .unit)
            corpusSHA256 = try c.decode(String?.self, forKey: .corpusSHA256)
            evidence = try c.decode(Evidence.self, forKey: .evidence)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(nutrient, forKey: .nutrient)
            try c.encode(value, forKey: .value)
            try c.encode(unit, forKey: .unit)
            try c.encode(corpusSHA256, forKey: .corpusSHA256)  // an explicit null, never an absent key
            try c.encode(evidence, forKey: .evidence)
        }

        public var key: NutrientKey? { NutrientKey(rawValue: nutrient) }
    }

    /// The wire form of one `estimate_evidence` record (estimates v1 section 2.2, plus `quality`).
    public struct Evidence: Codable, Equatable, Sendable {
        public struct Derivation: Codable, Equatable, Sendable {
            public struct SourceValue: Codable, Equatable, Sendable {
                public let value: Double
                public let unit: String
                enum CodingKeys: String, CodingKey, CaseIterable { case value, unit }
                public init(value: Double, unit: String) { self.value = value; self.unit = unit }
                public init(from decoder: any Decoder) throws {
                    try ApprovedEstimateStrictKeys.require(CodingKeys.self, in: decoder)
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    value = try c.decode(Double.self, forKey: .value)
                    unit = try c.decode(String.self, forKey: .unit)
                }
            }
            public let transformID: String
            public let version: String
            public let sourceValue: SourceValue
            enum CodingKeys: String, CodingKey, CaseIterable {
                case version
                case transformID = "transform_id"
                case sourceValue = "source_value"
            }
            public init(transformID: String, version: String, sourceValue: SourceValue) {
                self.transformID = transformID; self.version = version; self.sourceValue = sourceValue
            }
            public init(from decoder: any Decoder) throws {
                try ApprovedEstimateStrictKeys.require(CodingKeys.self, in: decoder)
                let c = try decoder.container(keyedBy: CodingKeys.self)
                transformID = try c.decode(String.self, forKey: .transformID)
                version = try c.decode(String.self, forKey: .version)
                sourceValue = try c.decode(SourceValue.self, forKey: .sourceValue)
            }
        }

        public let id: String
        public let entryID: String
        public let nutrient: String
        public let approvedAsEstimate: Bool
        public let sourceType: String
        public let compositionSource: String?
        public let sourceReference: String
        public let pageAccess: String?
        public let sourceDigest: String?
        public let retrievedOn: String?
        public let sourceState: String
        public let targetState: String
        public let stateBasis: String
        public let method: String
        public let assumption: String
        public let derivation: Derivation?
        public let quality: String

        enum CodingKeys: String, CodingKey, CaseIterable {
            case id, nutrient, method, assumption, derivation, quality
            case entryID = "entry_id"
            case approvedAsEstimate = "approved_as_estimate"
            case sourceType = "source_type"
            case compositionSource = "composition_source"
            case sourceReference = "source_reference"
            case pageAccess = "page_access"
            case sourceDigest = "source_digest"
            case retrievedOn = "retrieved_on"
            case sourceState = "source_state"
            case targetState = "target_state"
            case stateBasis = "state_basis"
        }

        public init(_ e: PersonalFoodDatabaseEstimateEvidence) {
            id = e.id; entryID = e.entryID; nutrient = e.nutrient.rawValue; approvedAsEstimate = true
            sourceType = e.sourceType.rawValue; compositionSource = e.compositionSource?.rawValue
            sourceReference = e.sourceReference; pageAccess = e.pageAccess?.rawValue; sourceDigest = e.sourceDigest
            retrievedOn = e.retrievedOn?.text; sourceState = e.sourceState; targetState = e.targetState
            stateBasis = e.stateBasis.rawValue; method = e.method.rawValue; assumption = e.assumption
            derivation = e.derivation.map {
                Derivation(transformID: $0.transformID, version: $0.version,
                           sourceValue: .init(value: $0.sourceValue, unit: $0.sourceUnit))
            }
            quality = e.quality.rawValue
        }

        public init(from decoder: any Decoder) throws {
            try ApprovedEstimateStrictKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            entryID = try c.decode(String.self, forKey: .entryID)
            nutrient = try c.decode(String.self, forKey: .nutrient)
            approvedAsEstimate = try c.decode(Bool.self, forKey: .approvedAsEstimate)
            sourceType = try c.decode(String.self, forKey: .sourceType)
            compositionSource = try c.decode(String?.self, forKey: .compositionSource)
            sourceReference = try c.decode(String.self, forKey: .sourceReference)
            pageAccess = try c.decode(String?.self, forKey: .pageAccess)
            sourceDigest = try c.decode(String?.self, forKey: .sourceDigest)
            retrievedOn = try c.decode(String?.self, forKey: .retrievedOn)
            sourceState = try c.decode(String.self, forKey: .sourceState)
            targetState = try c.decode(String.self, forKey: .targetState)
            stateBasis = try c.decode(String.self, forKey: .stateBasis)
            method = try c.decode(String.self, forKey: .method)
            assumption = try c.decode(String.self, forKey: .assumption)
            derivation = try c.decode(Derivation?.self, forKey: .derivation)
            quality = try c.decode(String.self, forKey: .quality)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(entryID, forKey: .entryID)
            try c.encode(nutrient, forKey: .nutrient)
            try c.encode(approvedAsEstimate, forKey: .approvedAsEstimate)
            try c.encode(sourceType, forKey: .sourceType)
            try c.encode(compositionSource, forKey: .compositionSource)
            try c.encode(sourceReference, forKey: .sourceReference)
            try c.encode(pageAccess, forKey: .pageAccess)
            try c.encode(sourceDigest, forKey: .sourceDigest)
            try c.encode(retrievedOn, forKey: .retrievedOn)
            try c.encode(sourceState, forKey: .sourceState)
            try c.encode(targetState, forKey: .targetState)
            try c.encode(stateBasis, forKey: .stateBasis)
            try c.encode(method, forKey: .method)
            try c.encode(assumption, forKey: .assumption)
            try c.encode(derivation, forKey: .derivation)
            try c.encode(quality, forKey: .quality)
        }

        /// The typed record; nil when a token is outside its closed list or a field contradicts its
        /// source type, so nothing unvalidated is shown or exported.
        public var typed: PersonalFoodDatabaseEstimateEvidence? {
            guard approvedAsEstimate, let key = NutrientKey(rawValue: nutrient),
                  let sourceType = PersonalFoodDatabaseEstimateSourceType(rawValue: sourceType),
                  let stateBasis = PersonalFoodDatabaseEstimateStateBasis(rawValue: stateBasis),
                  let method = PersonalFoodDatabaseEstimateMethod(rawValue: method),
                  let quality = PersonalFoodDatabaseEstimateQuality(rawValue: quality) else { return nil }
            let composition = compositionSource.flatMap(PersonalFoodDatabaseGenericSource.init(rawValue:))
            let access = pageAccess.flatMap(PersonalFoodDatabaseEstimatePageAccess.init(rawValue:))
            let date = retrievedOn.flatMap { PersonalFoodDatabaseDate(ascii: Array($0.utf8)) }
            let national = sourceType == .nationalComposition
            guard (compositionSource == nil) == (composition == nil), (pageAccess == nil) == (access == nil),
                  (retrievedOn == nil) == (date == nil), national == (composition != nil), national == (access == nil),
                  (method == .derived) == (derivation != nil) else { return nil }
            let typed = PersonalFoodDatabaseEstimateEvidence(
                id: id, entryID: entryID, nutrient: key, sourceType: sourceType, compositionSource: composition,
                sourceReference: sourceReference, pageAccess: access, sourceDigest: sourceDigest, retrievedOn: date,
                sourceState: sourceState, targetState: targetState, stateBasis: stateBasis, method: method,
                assumption: assumption,
                derivation: derivation.map {
                    PersonalFoodDatabaseEstimateDerivation(transformID: $0.transformID, version: $0.version,
                                                           sourceValue: $0.sourceValue.value, sourceUnit: $0.sourceValue.unit)
                },
                quality: quality)
            // A label photo record keeps its photo rules when stored (label photo estimates v1 2.1).
            return PersonalFoodDatabasePhotoAddress.recordIsValid(typed) ? typed : nil
        }
    }

    public let schema: String
    public let databaseReleaseID: String
    public let entryID: String
    public let basis: String
    /// In nutrient catalogue order.
    public let estimates: [Estimate]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, basis, estimates
        case databaseReleaseID = "database_release_id"
        case entryID = "entry_id"
    }

    /// The manifest of one entry's estimates; nil when the entry has none (a candidate without an
    /// estimate writes no manifest, so its log keeps its contract).
    public init?(databaseReleaseID: String, entry: PersonalFoodDatabaseEntry,
                 corpora: [PersonalFoodDatabaseGenericSource: String]) {
        guard !entry.estimatedNutrients.isEmpty else { return nil }
        schema = Self.schema
        self.databaseReleaseID = databaseReleaseID
        entryID = entry.id
        basis = entry.basis.rawValue
        let byKey = Dictionary(entry.estimatedNutrients.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        estimates = NutrientKey.allCases.compactMap { key in
            byKey[key].map { Estimate($0, corpusSHA256: $0.evidence.compositionSource.flatMap { corpora[$0] }) }
        }
    }

    public init(from decoder: any Decoder) throws {
        try ApprovedEstimateStrictKeys.require(CodingKeys.self, in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(String.self, forKey: .schema)
        databaseReleaseID = try c.decode(String.self, forKey: .databaseReleaseID)
        entryID = try c.decode(String.self, forKey: .entryID)
        basis = try c.decode(String.self, forKey: .basis)
        estimates = try c.decode([Estimate].self, forKey: .estimates)
        guard isWellFormed else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a capture manifest"))
        }
    }

    /// Every estimate names a known nutrient once, in its canonical unit, with a typed evidence
    /// record of this entry and nutrient, and a corpus hash exactly for a composition estimate.
    var isWellFormed: Bool {
        guard schema == Self.schema, PersonalFoodDatabaseBasis(rawValue: basis) != nil, !estimates.isEmpty,
              Set(estimates.map(\.nutrient)).count == estimates.count else { return false }
        return estimates.allSatisfy { estimate in
            guard let key = estimate.key, estimate.unit == key.canonicalUnit.rawValue, estimate.value.isFinite,
                  estimate.value >= 0, let typed = estimate.evidence.typed, typed.nutrient == key,
                  typed.entryID == entryID else { return false }
            return (typed.sourceType == .nationalComposition) == (estimate.corpusSHA256 != nil)
        }
    }

    /// The strict reading of a stored payload; nil for anything that is not exactly a manifest.
    public static func decode(_ data: Data) -> ApprovedEstimateCaptureManifest? {
        try? JSONDecoder().decode(ApprovedEstimateCaptureManifest.self, from: data)
    }

    public func estimate(_ key: NutrientKey) -> Estimate? { estimates.first { $0.nutrient == key.rawValue } }

    /// Whether any estimate is a label photo estimate: such a manifest needs food contract 11.
    public var holdsPhotoEstimate: Bool {
        estimates.contains { $0.evidence.sourceType == PersonalFoodDatabaseEstimateSourceType.productDatasetPhoto.rawValue }
    }
}

/// `pfd-estimate-left-out-v1`: the estimated nutrients the owner left out of one saved resolution
/// version, so a reopened log can say "Left out by you". Keys only, never a value: the estimate that
/// was offered is in the capture manifest. Never lists a withheld key (withholding wins).
public struct ApprovedEstimateLeftOutEvidence: Codable, Equatable, Sendable {
    public static let schema = ApprovedEstimateProvenance.leftOutMethodVersion

    public let schema: String
    public let resolutionVersionID: String
    /// The SHA-256 of the capture manifest's payload this item belongs to.
    public let manifestSHA256: String
    /// Sorted nutrient keys, never empty.
    public let leftOut: [String]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema
        case resolutionVersionID = "resolution_version_id"
        case manifestSHA256 = "manifest_sha256"
        case leftOut = "left_out"
    }

    public init?(resolutionVersionID: String, manifestSHA256: String, leftOut: Set<NutrientKey>) {
        guard !leftOut.isEmpty else { return nil }
        schema = Self.schema
        self.resolutionVersionID = resolutionVersionID
        self.manifestSHA256 = manifestSHA256
        self.leftOut = leftOut.map(\.rawValue).sorted()
    }

    public init(from decoder: any Decoder) throws {
        try ApprovedEstimateStrictKeys.require(CodingKeys.self, in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(String.self, forKey: .schema)
        resolutionVersionID = try c.decode(String.self, forKey: .resolutionVersionID)
        manifestSHA256 = try c.decode(String.self, forKey: .manifestSHA256)
        leftOut = try c.decode([String].self, forKey: .leftOut)
        guard schema == Self.schema, !leftOut.isEmpty, leftOut == leftOut.sorted(), Set(leftOut).count == leftOut.count,
              leftOut.allSatisfy({ NutrientKey(rawValue: $0) != nil }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a leave-out item"))
        }
    }

    public static func decode(_ data: Data) -> ApprovedEstimateLeftOutEvidence? {
        try? JSONDecoder().decode(ApprovedEstimateLeftOutEvidence.self, from: data)
    }

    public var keys: Set<NutrientKey> { Set(leftOut.compactMap(NutrientKey.init(rawValue:))) }
}
