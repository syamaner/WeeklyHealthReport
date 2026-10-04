import Foundation
import FoodLedgerDomain

public enum FoodProposalReviewScope: String, Codable, Sendable {
    case exactProduct = "exact_product"
    case representativeEstimate = "representative_estimate"
}

public struct FoodProposalAcknowledgement: Codable, Equatable, Sendable {
    public let identityAndScopeReviewed: Bool
    public let basisReviewed: Bool
    public let nutrientsAndUnknownsReviewed: Bool
    public init(identityAndScopeReviewed: Bool, basisReviewed: Bool, nutrientsAndUnknownsReviewed: Bool) {
        self.identityAndScopeReviewed = identityAndScopeReviewed; self.basisReviewed = basisReviewed
        self.nutrientsAndUnknownsReviewed = nutrientsAndUnknownsReviewed
    }
    public var isComplete: Bool { identityAndScopeReviewed && basisReviewed && nutrientsAndUnknownsReviewed }
}

public struct FoodProposalReviewManifest: Codable, Equatable, Sendable {
    public let version: String
    public let query: String
    public let document: CapturedFoodDocument
    public let candidate: FoodProposalCandidate
    public let scope: FoodProposalReviewScope
    public let acknowledgement: FoodProposalAcknowledgement
    public let reviewedAt: Date
}

/// Explicit review prepares a confirmation, never a saved log entry. Complete
/// source material and original unknowns survive the eventual ledger write.
public struct ReviewedFoodProposalConfirmation: Sendable {
    public static let version = "reviewed-web-proposal-v1"
    private let ids: any LedgerIDGenerating
    private let clock: any LedgerClock
    private let encoder: any CanonicalEncoding
    private let digester: any Digesting

    public init(ids: any LedgerIDGenerating, clock: any LedgerClock,
                encoder: any CanonicalEncoding, digester: any Digesting) {
        self.ids = ids; self.clock = clock; self.encoder = encoder; self.digester = digester
    }

    public func prepare(_ proposal: BoundFoodProposal, query: String, scope: FoodProposalReviewScope,
                        acknowledgement: FoodProposalAcknowledgement, locale: LedgerText) throws -> PopulatedFoodConfirmation {
        guard proposal.selectionEligible, acknowledgement.isComplete, !query.isEmpty, query.count <= 300,
              !FoodProposalQueryPolicy.hasBasisConflict(query: query, basis: proposal.candidate.basis),
              let capturedAt = ISO8601DateFormatter().date(from: proposal.document.retrievedAt) else {
            throw GenericFoodProposalError.invalidSelection
        }
        let original = proposal.candidate
        let basis = try Self.basis(original.basis)
        let now = clock.now()
        let manifest = FoodProposalReviewManifest(version: Self.version, query: query, document: proposal.document,
            candidate: original, scope: scope, acknowledgement: acknowledgement, reviewedAt: now)
        let manifestData = try encoder.encode(manifest)
        let manifestHash = try digester.sha256(manifestData)
        let evidenceID = try ids.makeID(EvidenceTag.self)
        let rawHash = try SHA256Digest(proposal.document.rawSha256)
        let sourceID = try ExternalIdentifier("reviewed-web-proposal")
        let releaseID = try ExternalIdentifier("reviewed-web:" + manifestHash.value)
        let recordID = try ExternalIdentifier(proposal.document.url + "#proposal=" + original.id)
        let evidence = try CaptureEvidence(evidenceID: evidenceID, kind: .labelText, capturedAt: now, locale: locale,
            captureMethod: LedgerText("User reviewed captured web proposal"), captureMethodVersion: LedgerText(Self.version),
            originalPayload: .text(LedgerText(String(decoding: manifestData, as: UTF8.self))), byteHash: manifestHash)
        let release = try SourceRelease(sourceReleaseID: releaseID, sourceID: sourceID, releasedAt: capturedAt,
            artifactHash: rawHash, schemaVersion: LedgerText(Self.schema(scope)),
            pipelineVersion: LedgerText(Self.version + ":" + FoodProposalBinding.version + ":" + FoodReviewedWebProposalPolicy.version),
            licence: LedgerText("No redistribution licence inferred from the captured page."),
            attribution: LedgerText("Reviewed web proposal · " + proposal.document.url + " · " + proposal.document.retrievedAt), manifestHash: manifestHash)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard let declared = original.nutrients.first(where: { $0.key.ledgerKey == key }) else {
                return try NutrientEntry(key: key, value: .unknown(.notDeclared))
            }
            if declared.state == .unknown {
                return try NutrientEntry(key: key, value: .unknown(declared.unknownReason == .notObserved ? .notDeclared : .noCompatibleSource))
            }
            guard let literal = declared.value, let decimal = FoodProposalBinding.decimal(literal) else { throw GenericFoodProposalError.invalidNutrient }
            let amount = NSDecimalNumber(decimal: decimal).doubleValue
            let reference = Self.manifestReference(hash: manifestHash, candidateID: original.id, nutrient: declared, literal: literal)
            let provenance = try NutrientProvenance(sourceKind: .reviewedWebProposal, sourceID: sourceID, sourceReleaseID: releaseID,
                recordID: recordID, evidenceID: evidenceID, capturedAt: capturedAt, responseHash: rawHash, manifestReference: LedgerText(reference))
            let source = try SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: basis)
            return try NutrientEntry(key: key, value: .augmented(ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(source), provenance: [provenance])))
        })
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown, skin: .unknown,
            drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: basis)
        let differences = scope == .representativeEstimate
            ? "You reviewed this as a representative estimate. Your ingredients, preparation and portion may differ. Missing nutrients remain unknown."
            : "You reviewed this source proposal for an exact product. Confirm the product's missing identity details and your consumed amount before saving."
        let metadata = try CandidateMatchMetadata(methodVersion: LedgerText(Self.version), score: 0,
            materialDifferences: [LedgerText(differences)], libraryAliases: [])
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: releaseID,
            recordID: recordID, identity: identity, edibleQuantity: .unknown, nutrients: nutrients,
            evidenceIDs: [evidenceID], matchMetadata: metadata), name: LedgerText(original.name),
            brand: original.brand.map { try LedgerText($0) },
            variant: LedgerText(scope == .representativeEstimate ? "Reviewed web estimate" : "Reviewed web product proposal"), itemClass: .food)
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: identity, expectedEdibleQuantity: .unknown)
    }

    static func manifestReference(hash: SHA256Digest, candidateID: String, nutrient: FoodProposalNutrient, literal: String) -> String {
        "manifest-sha256=\(hash.value);candidate=\(candidateID);nutrient=\(nutrient.key.rawValue);blocks=\(nutrient.evidence.map(\.blockId).joined(separator: ","));literal=\(literal);binding=\(FoodProposalBinding.version)"
    }

    public static func schema(_ scope: FoodProposalReviewScope) -> String { version + ":" + scope.rawValue }
    static func basis(_ proposal: FoodProposalBasis) throws -> ResolutionBasis {
        guard let unit = proposal.unit, let text = proposal.amount, let amount = FoodProposalBinding.decimal(text), amount > 0,
              let label = proposal.label else { throw GenericFoodProposalError.invalidBasis }
        if unit == .g && amount == 100 { return .per100Grams }
        if unit == .ml && amount == 100 { return .per100Millilitres }
        let quantity = try PositiveQuantity(value: NSDecimalNumber(decimal: amount).doubleValue,
            unit: unit == .g ? .grams : unit == .ml ? .millilitres : .count)
        return try .named(LedgerText(label), quantity)
    }
}

/// Closed admission profile, not a provider plug-in. Review scope is never inferred
/// from a name match or confidence; it is retained in a versioned source release.
public enum FoodReviewedWebProposalPolicy {
    public static let version = "reviewed-web-admission-v5"
    public static func applies(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        input.sourceReleases.contains { $0.sourceReleaseID == candidate.candidate.sourceReleaseID && $0.sourceID.value == "reviewed-web-proposal" }
            || candidate.candidate.nutrients.entries.flatMap { $0.value.provenance }.contains { $0.sourceKind == .reviewedWebProposal }
    }

    /// A corrected saved product is separate from the original source identity.
    /// Restore only a presentation that passes the complete retained-manifest policy.
    public static func restoredSourceCandidate(_ input: PopulatedFoodConfirmation,
                                              candidate: PopulatedFoodCandidate) throws -> PopulatedFoodCandidate? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        for evidence in input.evidence where candidate.candidate.evidenceIDs.contains(evidence.evidenceID) {
            guard case let .text(payload) = evidence.originalPayload,
                  let manifest = try? decoder.decode(FoodProposalReviewManifest.self, from: Data(payload.value.utf8)) else { continue }
            let restored = try PopulatedFoodCandidate(candidate: candidate.candidate, name: LedgerText(manifest.candidate.name),
                brand: manifest.candidate.brand.map { try LedgerText($0) }, variant: candidate.variant,
                barcode: candidate.barcode, itemClass: candidate.itemClass, packFacts: candidate.packFacts)
            let restoredInput = try PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: input.sourceReleases,
                candidates: [restored], expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
            if scope(restoredInput, candidate: restored) != nil { return restored }
        }
        return nil
    }

    public static func scope(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> FoodProposalReviewScope? {
        let source = candidate.candidate
        guard let release = input.sourceReleases.first(where: { $0.sourceReleaseID == source.sourceReleaseID }),
              release.sourceID.value == "reviewed-web-proposal",
              release.pipelineVersion.value == ReviewedFoodProposalConfirmation.version + ":" + FoodProposalBinding.version + ":" + version,
              let scope = [FoodProposalReviewScope.exactProduct, .representativeEstimate].first(where: { release.schemaVersion.value == ReviewedFoodProposalConfirmation.schema($0) }),
              let evidence = input.evidence.first(where: { source.evidenceIDs.contains($0.evidenceID)
                  && $0.kind == .labelText && $0.captureMethodVersion.value == ReviewedFoodProposalConfirmation.version
                  && $0.byteHash == release.manifestHash }) else { return nil }
        guard case let .text(payload) = evidence.originalPayload else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let manifest = try? decoder.decode(FoodProposalReviewManifest.self, from: Data(payload.value.utf8)),
              manifest.version == ReviewedFoodProposalConfirmation.version, manifest.scope == scope,
              manifest.acknowledgement.isComplete, manifest.document.rawSha256 == release.artifactHash.value,
              manifest.candidate.name == candidate.name.value, manifest.candidate.brand == candidate.brand?.value,
              !manifest.query.isEmpty, manifest.query.count <= 300,
              manifest.document.url + "#proposal=" + manifest.candidate.id == source.recordID.value,
              let capturedAt = ISO8601DateFormatter().date(from: manifest.document.retrievedAt),
              release.releasedAt == capturedAt,
              (try? ReviewedFoodProposalConfirmation.basis(manifest.candidate.basis)) == source.identity.servingBasis,
              let bound = try? FoodProposalBinding.validate(.init(candidates: [manifest.candidate], preferredId: manifest.candidate.id), documents: [manifest.document]),
              bound.candidates.first?.selectionEligible == true,
              !FoodProposalQueryPolicy.hasBasisConflict(query: manifest.query, basis: manifest.candidate.basis) else { return nil }
        // The retained proposal must describe the actual candidate being saved,
        // not merely accompany it with matching provenance identifiers.
        for entry in source.nutrients.entries {
            let original = manifest.candidate.nutrients.first { $0.key.ledgerKey == entry.key }
            if original?.state == .declared {
                guard let original, let literal = original.value, let decimal = FoodProposalBinding.decimal(literal),
                      case let .augmented(value) = entry.value,
                      value.amount == NSDecimalNumber(decimal: decimal).doubleValue,
                      value.unit == entry.key.canonicalUnit,
                      case let .exact(sourceValue) = value.sourceValue,
                      sourceValue.amount == value.amount, sourceValue.unit.value == value.unit.rawValue,
                      sourceValue.basis == source.identity.servingBasis,
                      value.provenance.allSatisfy({ $0.transforms.isEmpty && $0.capturedAt == capturedAt
                          && $0.manifestReference?.value == ReviewedFoodProposalConfirmation.manifestReference(
                              hash: release.manifestHash, candidateID: manifest.candidate.id, nutrient: original, literal: literal)
                      }) else { return nil }
            } else {
                let expected: UnknownReason = original == nil || original?.unknownReason == .notObserved ? .notDeclared : .noCompatibleSource
                guard entry.value == .unknown(expected) else { return nil }
            }
        }
        let provenance = source.nutrients.entries.flatMap { $0.value.provenance }
        guard !provenance.isEmpty, provenance.allSatisfy({ $0.sourceKind == .reviewedWebProposal
            && $0.sourceID == release.sourceID && $0.sourceReleaseID == source.sourceReleaseID
            && $0.recordID == source.recordID && $0.evidenceID == evidence.evidenceID
            && $0.responseHash == release.artifactHash && $0.manifestReference != nil }) else { return nil }
        return scope
    }
    /// Verify the exact retained bytes independently of semantic rebinding. The
    /// hashing capability is supplied by the confirmation composition root.
    public static func manifestDigestIsValid(evidence: [CaptureEvidence], releases: [SourceRelease],
                                            candidate: ProviderNeutralCandidate, digester: any Digesting) -> Bool {
        guard let release = releases.first(where: { $0.sourceReleaseID == candidate.sourceReleaseID
            && $0.sourceID.value == "reviewed-web-proposal" }),
              release.sourceReleaseID.value == "reviewed-web:" + release.manifestHash.value,
              let retained = evidence.first(where: { candidate.evidenceIDs.contains($0.evidenceID)
                  && $0.kind == .labelText && $0.captureMethodVersion.value == ReviewedFoodProposalConfirmation.version
                  && $0.byteHash == release.manifestHash }),
              case let .text(payload) = retained.originalPayload else { return false }
        return (try? digester.sha256(Data(payload.value.utf8))) == release.manifestHash
    }

    public static func allowsNamedServing(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        guard scope(input, candidate: candidate) != nil,
              case let .named(_, quantity) = candidate.candidate.identity.servingBasis else { return false }
        return quantity.unit == .count && quantity.value == 1
    }
}
