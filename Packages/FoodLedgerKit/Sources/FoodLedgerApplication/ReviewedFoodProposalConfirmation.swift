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

/// Frozen v1 manifest (`reviewed-web-proposal-v1`). Synthesised, lenient `Codable` is
/// retained exactly so that every stored v1 payload decodes as it did when written.
/// Nothing writes v1 any more; stored bytes are rehashed as they are, never re-encoded.
public struct FoodProposalReviewManifestV1: Codable, Equatable, Sendable {
    public let version: String
    public let query: String
    public let document: CapturedFoodDocument
    public let candidate: FoodProposalCandidate
    public let scope: FoodProposalReviewScope
    public let acknowledgement: FoodProposalAcknowledgement
    public let reviewedAt: Date
}

/// Historical name of the v1 manifest type.
public typealias FoodProposalReviewManifest = FoodProposalReviewManifestV1

/// The single review acknowledgement of manifest v2: "Use this source" on a named,
/// closed screen-content contract. Admission checks only that the identifiers are known.
public struct FoodProposalReviewAction: Codable, Equatable, Sendable {
    public static let useThisSource = "use_this_source"
    public static let webLookupReviewV1 = "web-lookup-review-v1"
    public static let knownPresentations: Set<String> = [webLookupReviewV1]
    public let action: String
    public let presentation: String

    init(action: String = useThisSource, presentation: String = webLookupReviewV1) {
        self.action = action; self.presentation = presentation
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case action, presentation }
    public init(from decoder: any Decoder) throws {
        try StrictManifestKeys.require(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(String.self, forKey: .action)
        presentation = try container.decode(String.self, forKey: .presentation)
        guard isKnown else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown review action or presentation"))
        }
    }
    public var isKnown: Bool { action == Self.useThisSource && Self.knownPresentations.contains(presentation) }
}

/// The applicability gate decision recorded when the user acted. The model's choice is
/// recorded, never re-run, and never becomes save authority on its own.
public struct FoodProposalReviewGateRecord: Codable, Equatable, Sendable {
    public static let knownChoicePolicies: Set<String> = [GenericFoodProposalReview.choicePolicyVersion]
    public let choicePolicy: String
    public let rankingAvailable: Bool
    public let selectionChoice: String
    public let representativeSourceOnly: Bool

    init(choicePolicy: String = GenericFoodProposalReview.choicePolicyVersion, rankingAvailable: Bool,
                selectionChoice: String, representativeSourceOnly: Bool) {
        self.choicePolicy = choicePolicy; self.rankingAvailable = rankingAvailable
        self.selectionChoice = selectionChoice; self.representativeSourceOnly = representativeSourceOnly
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case choicePolicy, rankingAvailable, selectionChoice, representativeSourceOnly }
    public init(from decoder: any Decoder) throws {
        try StrictManifestKeys.require(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choicePolicy = try container.decode(String.self, forKey: .choicePolicy)
        rankingAvailable = try container.decode(Bool.self, forKey: .rankingAvailable)
        selectionChoice = try container.decode(String.self, forKey: .selectionChoice)
        representativeSourceOnly = try container.decode(Bool.self, forKey: .representativeSourceOnly)
        guard Self.knownChoicePolicies.contains(choicePolicy), !selectionChoice.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown choice policy or empty choice"))
        }
    }
    /// Closed admission rule: the recorded gate must have permitted exactly this candidate and scope.
    public func permits(candidateID: String, scope: FoodProposalReviewScope) -> Bool {
        Self.knownChoicePolicies.contains(choicePolicy) && rankingAvailable
            && selectionChoice == candidateID && !["none", "clarify"].contains(selectionChoice)
            && !(representativeSourceOnly && scope == .exactProduct)
    }
}

/// Manifest v2 (`reviewed-web-proposal-v2`): one review action and the recorded gate.
/// Strict decoding: any extra or missing key at this level, in `review` or in `gate` throws.
public struct FoodProposalReviewManifestV2: Codable, Equatable, Sendable {
    public let version: String
    public let query: String
    public let document: CapturedFoodDocument
    public let candidate: FoodProposalCandidate
    public let scope: FoodProposalReviewScope
    public let review: FoodProposalReviewAction
    public let gate: FoodProposalReviewGateRecord
    public let reviewedAt: Date

    init(version: String = ReviewedFoodProposalConfirmation.version, query: String, document: CapturedFoodDocument,
                candidate: FoodProposalCandidate, scope: FoodProposalReviewScope, review: FoodProposalReviewAction,
                gate: FoodProposalReviewGateRecord, reviewedAt: Date) {
        self.version = version; self.query = query; self.document = document; self.candidate = candidate
        self.scope = scope; self.review = review; self.gate = gate; self.reviewedAt = reviewedAt
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case version, query, document, candidate, scope, review, gate, reviewedAt }
    public init(from decoder: any Decoder) throws {
        try StrictManifestKeys.require(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        guard version == ReviewedFoodProposalConfirmation.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "Not a v2 manifest")
        }
        query = try container.decode(String.self, forKey: .query)
        document = try container.decode(CapturedFoodDocument.self, forKey: .document)
        candidate = try container.decode(FoodProposalCandidate.self, forKey: .candidate)
        scope = try container.decode(FoodProposalReviewScope.self, forKey: .scope)
        review = try container.decode(FoodProposalReviewAction.self, forKey: .review)
        gate = try container.decode(FoodProposalReviewGateRecord.self, forKey: .gate)
        reviewedAt = try container.decode(Date.self, forKey: .reviewedAt)
    }
}

/// Compares the keys actually present with a closed key set. `KeyedDecodingContainer.allKeys`
/// for a typed key enum silently drops unknown keys, so a dynamic key container is used.
enum StrictManifestKeys {
    private struct AnyKey: CodingKey {
        let stringValue: String; let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    static func require<Keys: CodingKey & CaseIterable>(_ keys: Keys.Type, in decoder: any Decoder) throws {
        let present = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
        guard Set(present) == Set(Keys.allCases.map(\.stringValue)), present.count == Keys.allCases.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected or missing manifest keys"))
        }
    }
}

/// A decoded retained manifest of a known version. Dispatch is by the `version` field;
/// unknown versions fail closed.
public enum FoodProposalReviewManifestRecord: Equatable, Sendable {
    case v1(FoodProposalReviewManifestV1)
    case v2(FoodProposalReviewManifestV2)

    public static func decode(_ data: Data) -> FoodProposalReviewManifestRecord? {
        struct Probe: Decodable { let version: String }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let probe = try? decoder.decode(Probe.self, from: data) else { return nil }
        switch probe.version {
        case ReviewedFoodProposalConfirmation.version1:
            return (try? decoder.decode(FoodProposalReviewManifestV1.self, from: data)).map(Self.v1)
        case ReviewedFoodProposalConfirmation.version:
            return (try? decoder.decode(FoodProposalReviewManifestV2.self, from: data)).map(Self.v2)
        default: return nil
        }
    }
    public var version: String { switch self { case let .v1(m): m.version; case let .v2(m): m.version } }
    public var query: String { switch self { case let .v1(m): m.query; case let .v2(m): m.query } }
    public var document: CapturedFoodDocument { switch self { case let .v1(m): m.document; case let .v2(m): m.document } }
    public var candidate: FoodProposalCandidate { switch self { case let .v1(m): m.candidate; case let .v2(m): m.candidate } }
    public var scope: FoodProposalReviewScope { switch self { case let .v1(m): m.scope; case let .v2(m): m.scope } }
    /// v1 needs its complete three-part acknowledgement; v2 needs the single known action
    /// and a recorded gate that permitted exactly this candidate and scope.
    public var reviewIsAdmissible: Bool {
        switch self {
        case let .v1(m): m.acknowledgement.isComplete
        case let .v2(m): m.review.isKnown && m.gate.permits(candidateID: m.candidate.id, scope: m.scope)
        }
    }
}

/// Explicit review prepares a confirmation, never a saved log entry. Complete
/// source material and original unknowns survive the eventual ledger write.
public struct ReviewedFoodProposalConfirmation: Sendable {
    public static let version = "reviewed-web-proposal-v2"
    public static let version1 = "reviewed-web-proposal-v1"
    /// Closed admission: each manifest version is tied to exactly one stored pipeline
    /// triple. v1 is every record written since 6b5f279 (admission v5); v2 is admission v6.
    public static let admittedPipelines: [String: String] = [
        version1: version1 + ":food-proposal-binding-v7:reviewed-web-admission-v5",
        version: version + ":" + FoodProposalBinding.version + ":" + FoodReviewedWebProposalPolicy.version
    ]
    private let ids: any LedgerIDGenerating
    private let clock: any LedgerClock
    private let encoder: any CanonicalEncoding
    private let digester: any Digesting

    public init(ids: any LedgerIDGenerating, clock: any LedgerClock,
                encoder: any CanonicalEncoding, digester: any Digesting) {
        self.ids = ids; self.clock = clock; self.encoder = encoder; self.digester = digester
    }

    /// The single review step. The applicability gate is enforced here, in the application:
    /// only the current suggested eligible candidate of a successful check can prepare, and
    /// a representative-only source cannot be used as an exact product. The gate decision is
    /// recorded in the manifest and re-checked from that record at save and reopen.
    public func prepare(review: GenericFoodProposalReview, proposal: BoundFoodProposal, scope: FoodProposalReviewScope,
                        locale: LedgerText) throws -> PopulatedFoodConfirmation {
        guard review.permitsConfirmation(of: proposal), let selection = review.selection,
              !(review.representativeSourceOnly && scope == .exactProduct) else {
            throw GenericFoodProposalError.invalidSelection
        }
        let gate = FoodProposalReviewGateRecord(rankingAvailable: !review.rankingUnavailable,
            selectionChoice: selection.choice, representativeSourceOnly: review.representativeSourceOnly)
        guard gate.permits(candidateID: proposal.candidate.id, scope: scope) else { throw GenericFoodProposalError.invalidSelection }
        let capturedAt = try Self.validated(proposal, query: review.foodTerms)
        let manifest = FoodProposalReviewManifestV2(query: review.foodTerms, document: proposal.document,
            candidate: proposal.candidate, scope: scope, review: FoodProposalReviewAction(), gate: gate, reviewedAt: clock.now())
        return try build(manifestData: encoder.encode(manifest), version: Self.version, proposal: proposal,
                         scope: scope, capturedAt: capturedAt, locale: locale)
    }

    /// Regression fixtures only: writes the frozen v1 shape. Production never calls this.
    @_spi(ReviewedWebRegression)
    public func prepareVersion1(_ proposal: BoundFoodProposal, query: String, scope: FoodProposalReviewScope,
                                acknowledgement: FoodProposalAcknowledgement, locale: LedgerText) throws -> PopulatedFoodConfirmation {
        guard acknowledgement.isComplete else { throw GenericFoodProposalError.invalidSelection }
        let capturedAt = try Self.validated(proposal, query: query)
        let manifest = FoodProposalReviewManifestV1(version: Self.version1, query: query, document: proposal.document,
            candidate: proposal.candidate, scope: scope, acknowledgement: acknowledgement, reviewedAt: clock.now())
        return try build(manifestData: encoder.encode(manifest), version: Self.version1, proposal: proposal,
                         scope: scope, capturedAt: capturedAt, locale: locale)
    }

    private static func validated(_ proposal: BoundFoodProposal, query: String) throws -> Date {
        guard proposal.selectionEligible, !query.isEmpty, query.count <= 300,
              !FoodProposalQueryPolicy.hasBasisConflict(query: query, basis: proposal.candidate.basis),
              let capturedAt = ISO8601DateFormatter().date(from: proposal.document.retrievedAt) else {
            throw GenericFoodProposalError.invalidSelection
        }
        return capturedAt
    }

    private func build(manifestData: Data, version: String, proposal: BoundFoodProposal, scope: FoodProposalReviewScope,
                       capturedAt: Date, locale: LedgerText) throws -> PopulatedFoodConfirmation {
        guard let pipeline = Self.admittedPipelines[version] else { throw GenericFoodProposalError.invalidSelection }
        let original = proposal.candidate
        let basis = try Self.basis(original.basis)
        let now = clock.now()
        let manifestHash = try digester.sha256(manifestData)
        let evidenceID = try ids.makeID(EvidenceTag.self)
        let rawHash = try SHA256Digest(proposal.document.rawSha256)
        let sourceID = try ExternalIdentifier("reviewed-web-proposal")
        let releaseID = try ExternalIdentifier("reviewed-web:" + manifestHash.value)
        let recordID = try ExternalIdentifier(proposal.document.url + "#proposal=" + original.id)
        let evidence = try CaptureEvidence(evidenceID: evidenceID, kind: .labelText, capturedAt: now, locale: locale,
            captureMethod: LedgerText("User reviewed captured web proposal"), captureMethodVersion: LedgerText(version),
            originalPayload: .text(LedgerText(String(decoding: manifestData, as: UTF8.self))), byteHash: manifestHash)
        let release = try SourceRelease(sourceReleaseID: releaseID, sourceID: sourceID, releasedAt: capturedAt,
            artifactHash: rawHash, schemaVersion: LedgerText(Self.schema(scope, version: version)),
            pipelineVersion: LedgerText(pipeline),
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
        let metadata = try CandidateMatchMetadata(methodVersion: LedgerText(version), score: 0,
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

    public static func schema(_ scope: FoodProposalReviewScope, version: String = version) -> String { version + ":" + scope.rawValue }
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
    public static let version = "reviewed-web-admission-v6"
    public static func applies(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        input.sourceReleases.contains { $0.sourceReleaseID == candidate.candidate.sourceReleaseID && $0.sourceID.value == "reviewed-web-proposal" }
            || candidate.candidate.nutrients.entries.flatMap { $0.value.provenance }.contains { $0.sourceKind == .reviewedWebProposal }
    }

    /// A corrected saved product is separate from the original source identity.
    /// Restore only a presentation that passes the complete retained-manifest policy.
    public static func restoredSourceCandidate(_ input: PopulatedFoodConfirmation,
                                              candidate: PopulatedFoodCandidate) throws -> PopulatedFoodCandidate? {
        for evidence in input.evidence where candidate.candidate.evidenceIDs.contains(evidence.evidenceID) {
            guard case let .text(payload) = evidence.originalPayload,
                  let manifest = FoodProposalReviewManifestRecord.decode(Data(payload.value.utf8)) else { continue }
            let restored = try PopulatedFoodCandidate(candidate: candidate.candidate, name: LedgerText(manifest.candidate.name),
                brand: manifest.candidate.brand.map { try LedgerText($0) }, variant: candidate.variant,
                barcode: candidate.barcode, itemClass: candidate.itemClass, packFacts: candidate.packFacts)
            let restoredInput = try PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: input.sourceReleases,
                candidates: [restored], expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
            if scope(restoredInput, candidate: restored) != nil { return restored }
        }
        return nil
    }

    /// Release schema `"<manifest version>:<scope>"`, split without inference.
    static func schemaParts(_ schema: String) -> (version: String, scope: FoodProposalReviewScope)? {
        let parts = schema.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let scope = FoodProposalReviewScope(rawValue: String(parts[1])) else { return nil }
        return (String(parts[0]), scope)
    }

    public static func scope(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> FoodProposalReviewScope? {
        let source = candidate.candidate
        guard let release = input.sourceReleases.first(where: { $0.sourceReleaseID == source.sourceReleaseID }),
              release.sourceID.value == "reviewed-web-proposal",
              let parts = schemaParts(release.schemaVersion.value),
              let pipeline = ReviewedFoodProposalConfirmation.admittedPipelines[parts.version],
              release.pipelineVersion.value == pipeline,
              let evidence = input.evidence.first(where: { source.evidenceIDs.contains($0.evidenceID)
                  && $0.kind == .labelText && $0.captureMethodVersion.value == parts.version
                  && $0.byteHash == release.manifestHash }) else { return nil }
        let scope = parts.scope
        guard case let .text(payload) = evidence.originalPayload else { return nil }
        guard let manifest = FoodProposalReviewManifestRecord.decode(Data(payload.value.utf8)),
              manifest.version == parts.version, manifest.scope == scope,
              manifest.reviewIsAdmissible, manifest.document.rawSha256 == release.artifactHash.value,
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
              let parts = schemaParts(release.schemaVersion.value),
              ReviewedFoodProposalConfirmation.admittedPipelines[parts.version] != nil,
              let retained = evidence.first(where: { candidate.evidenceIDs.contains($0.evidenceID)
                  && $0.kind == .labelText && $0.captureMethodVersion.value == parts.version
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
