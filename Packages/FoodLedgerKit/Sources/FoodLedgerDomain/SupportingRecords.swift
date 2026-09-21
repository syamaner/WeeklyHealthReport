import Foundation

public struct QuantityConversionVersion: Codable, Equatable, Sendable {
    public let quantityConversionVersionID: QuantityConversionVersionID
    public let ordinal: VersionOrdinal
    public let supersedesQuantityConversionVersionID: QuantityConversionVersionID?
    public let sourceQuantity: PositiveQuantity
    public let convertedQuantity: PositiveQuantity
    public let methodVersion: LedgerText
    public let sourceReleaseID: ExternalIdentifier?
    public let evidenceID: EvidenceID?
    public let createdAt: Date

    public init(
        quantityConversionVersionID: QuantityConversionVersionID,
        ordinal: VersionOrdinal,
        supersedesQuantityConversionVersionID: QuantityConversionVersionID? = nil,
        sourceQuantity: PositiveQuantity,
        convertedQuantity: PositiveQuantity,
        methodVersion: LedgerText,
        sourceReleaseID: ExternalIdentifier? = nil,
        evidenceID: EvidenceID? = nil,
        createdAt: Date
    ) throws {
        guard sourceQuantity.unit != convertedQuantity.unit || sourceQuantity.value != convertedQuantity.value else {
            throw FoodLedgerValidationError.invalidUnit
        }
        self.quantityConversionVersionID = quantityConversionVersionID
        self.ordinal = ordinal
        self.supersedesQuantityConversionVersionID = supersedesQuantityConversionVersionID
        self.sourceQuantity = sourceQuantity
        self.convertedQuantity = convertedQuantity
        self.methodVersion = methodVersion
        self.sourceReleaseID = sourceReleaseID
        self.evidenceID = evidenceID
        self.createdAt = createdAt
    }
}

public struct Plate: Codable, Equatable, Sendable {
    public let plateID: PlateID
    public let createdAt: Date

    public init(plateID: PlateID, createdAt: Date) {
        self.plateID = plateID
        self.createdAt = createdAt
    }
}

public struct PlateWeightVersion: Codable, Equatable, Sendable {
    public let plateWeightVersionID: PlateWeightVersionID
    public let plateID: PlateID
    public let ordinal: VersionOrdinal
    public let supersedesPlateWeightVersionID: PlateWeightVersionID?
    public let emptyWeight: PositiveQuantity
    public let evidenceID: EvidenceID?
    public let createdAt: Date

    public init(
        plateWeightVersionID: PlateWeightVersionID,
        plateID: PlateID,
        ordinal: VersionOrdinal,
        supersedesPlateWeightVersionID: PlateWeightVersionID? = nil,
        emptyWeight: PositiveQuantity,
        evidenceID: EvidenceID? = nil,
        createdAt: Date
    ) throws {
        guard emptyWeight.unit == .grams else { throw FoodLedgerValidationError.invalidUnit }
        self.plateWeightVersionID = plateWeightVersionID
        self.plateID = plateID
        self.ordinal = ordinal
        self.supersedesPlateWeightVersionID = supersedesPlateWeightVersionID
        self.emptyWeight = emptyWeight
        self.evidenceID = evidenceID
        self.createdAt = createdAt
    }
}

public struct CandidateMatchMetadata: Codable, Equatable, Sendable {
    public let methodVersion: LedgerText
    public let score: Double
    public let materialDifferences: [LedgerText]
    public let selectionPolicy: LedgerText
    public let libraryAliases: [LedgerText]

    public init(
        methodVersion: LedgerText,
        score: Double,
        materialDifferences: [LedgerText],
        libraryAliases: [LedgerText] = []
    ) throws {
        guard score.isFinite else { throw FoodLedgerValidationError.nonFinite("candidate score") }
        guard (0 ... 1).contains(score) else { throw FoodLedgerValidationError.invalidBasis }
        guard Set(materialDifferences).count == materialDifferences.count else {
            throw FoodLedgerValidationError.duplicateValue("candidate differences")
        }
        guard Set(libraryAliases).count == libraryAliases.count else {
            throw FoodLedgerValidationError.duplicateValue("candidate library aliases")
        }
        self.methodVersion = methodVersion
        self.score = score
        self.materialDifferences = materialDifferences
        selectionPolicy = try LedgerText("explicit_user_selection_v1")
        self.libraryAliases = libraryAliases
    }
}

public struct ProviderNeutralCandidate: Codable, Equatable, Sendable {
    public let sourceReleaseID: ExternalIdentifier
    public let recordID: ExternalIdentifier
    public let identity: DecisiveIdentity
    public let edibleQuantity: EdibleQuantityIdentity
    public let nutrients: NutrientSet
    public let evidenceIDs: [EvidenceID]
    public let matchMetadata: CandidateMatchMetadata?

    public init(
        sourceReleaseID: ExternalIdentifier,
        recordID: ExternalIdentifier,
        identity: DecisiveIdentity,
        edibleQuantity: EdibleQuantityIdentity,
        nutrients: NutrientSet,
        evidenceIDs: [EvidenceID] = [],
        matchMetadata: CandidateMatchMetadata? = nil
    ) throws {
        guard Set(evidenceIDs).count == evidenceIDs.count else {
            throw FoodLedgerValidationError.duplicateValue("candidate evidence")
        }
        self.sourceReleaseID = sourceReleaseID
        self.recordID = recordID
        self.identity = identity
        self.edibleQuantity = edibleQuantity
        self.nutrients = nutrients
        self.evidenceIDs = evidenceIDs
        self.matchMetadata = matchMetadata
    }
}

public enum CandidateOutcome: String, Codable, Sendable {
    case selected
    case rejected
    case retainedConflict = "retained_conflict"
}

public struct CandidateDecision: Codable, Equatable, Sendable {
    public let candidateDecisionID: CandidateDecisionID
    public let candidate: ProviderNeutralCandidate
    public let expectedIdentity: DecisiveIdentity
    public let expectedEdibleQuantity: EdibleQuantityIdentity
    public let outcome: CandidateOutcome
    public let contradictionReasons: [IdentityContradiction]
    public let assertionID: AssertionID?
    public let createdAt: Date

    public init(
        candidateDecisionID: CandidateDecisionID,
        candidate: ProviderNeutralCandidate,
        expectedIdentity: DecisiveIdentity,
        expectedEdibleQuantity: EdibleQuantityIdentity,
        requestedOutcome: CandidateOutcome,
        assertionID: AssertionID? = nil,
        createdAt: Date
    ) throws {
        let contradictions = IdentityCompatibility.contradictions(
            between: expectedIdentity,
            and: candidate.identity,
            expectedEdibleQuantity: expectedEdibleQuantity,
            candidateEdibleQuantity: candidate.edibleQuantity
        )
        guard contradictions.isEmpty || requestedOutcome != .selected else {
            throw FoodLedgerValidationError.hardIdentityContradiction(contradictions)
        }
        self.candidateDecisionID = candidateDecisionID
        self.candidate = candidate
        self.expectedIdentity = expectedIdentity
        self.expectedEdibleQuantity = expectedEdibleQuantity
        self.outcome = contradictions.isEmpty ? requestedOutcome : .rejected
        self.contradictionReasons = contradictions
        self.assertionID = assertionID
        self.createdAt = createdAt
    }
}

public struct VersionReference: Codable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard value == value.lowercased(), UUID(uuidString: value)?.uuidString.lowercased() == value else {
            throw FoodLedgerValidationError.invalidIdentifier(value)
        }
        self.value = value
    }
}

public enum ConflictKind: String, Codable, Sendable {
    case competingProductSuccessors = "competing_product_successors"
    case competingLibrarySuccessors = "competing_library_successors"
    case competingResolutionSuccessors = "competing_resolution_successors"
    case competingLogCorrections = "competing_log_corrections"
    case competingQuantityVersions = "competing_quantity_versions"
    case competingPlateVersions = "competing_plate_versions"
}

public struct LedgerConflict: Codable, Equatable, Sendable {
    public let conflictID: ConflictID
    public let kind: ConflictKind
    public let ancestorVersionID: VersionReference
    public let competingVersionIDs: [VersionReference]
    public let createdAt: Date

    public init(
        conflictID: ConflictID,
        kind: ConflictKind,
        ancestorVersionID: VersionReference,
        competingVersionIDs: [VersionReference],
        createdAt: Date
    ) throws {
        guard Set(competingVersionIDs).count >= 2,
              Set(competingVersionIDs).count == competingVersionIDs.count,
              !competingVersionIDs.contains(ancestorVersionID) else {
            throw FoodLedgerValidationError.invalidConflict
        }
        self.conflictID = conflictID
        self.kind = kind
        self.ancestorVersionID = ancestorVersionID
        self.competingVersionIDs = competingVersionIDs
        self.createdAt = createdAt
    }
}

public struct SourceRelease: Codable, Equatable, Sendable {
    public let sourceReleaseID: ExternalIdentifier
    public let sourceID: ExternalIdentifier
    public let releasedAt: Date
    public let artifactHash: SHA256Digest
    public let schemaVersion: LedgerText
    public let pipelineVersion: LedgerText
    public let licence: LedgerText
    public let attribution: LedgerText
    public let manifestHash: SHA256Digest

    public init(
        sourceReleaseID: ExternalIdentifier,
        sourceID: ExternalIdentifier,
        releasedAt: Date,
        artifactHash: SHA256Digest,
        schemaVersion: LedgerText,
        pipelineVersion: LedgerText,
        licence: LedgerText,
        attribution: LedgerText,
        manifestHash: SHA256Digest
    ) {
        self.sourceReleaseID = sourceReleaseID
        self.sourceID = sourceID
        self.releasedAt = releasedAt
        self.artifactHash = artifactHash
        self.schemaVersion = schemaVersion
        self.pipelineVersion = pipelineVersion
        self.licence = licence
        self.attribution = attribution
        self.manifestHash = manifestHash
    }
}

public struct SourceInstallation: Codable, Equatable, Sendable {
    public let sourceReleaseID: ExternalIdentifier
    public let manifestRelativePath: LedgerText
    public let recordCount: Int
    public let installedAt: Date

    public init(
        sourceReleaseID: ExternalIdentifier,
        manifestRelativePath: LedgerText,
        recordCount: Int,
        installedAt: Date
    ) throws {
        guard recordCount >= 0 else { throw FoodLedgerValidationError.negative("record count") }
        guard !manifestRelativePath.value.hasPrefix("/"),
              !manifestRelativePath.value.split(separator: "/").contains("..") else {
            throw FoodLedgerValidationError.invalidIdentifier(manifestRelativePath.value)
        }
        self.sourceReleaseID = sourceReleaseID
        self.manifestRelativePath = manifestRelativePath
        self.recordCount = recordCount
        self.installedAt = installedAt
    }
}
