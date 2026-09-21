import CryptoKit
import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

public enum CoFIDSearchError: Error, Equatable, Sendable {
    case missingBundledCorpus
    case corpusHashMismatch
    case malformedCorpus
}

public final class CoFIDGenericFoodSearch: GenericFoodSearching, @unchecked Sendable {
    public static let matcherVersion = "deterministic-lexical-hard-rules-v1"
    public static let corpusCanonicalSHA256 = "2b0fbbade4d405eabcad440cabb1560e9861d9388c5fb4032ef24c81fb45f445"
    public static let candidateLimit = 10
    public static let minimumScore = 0.25
    public static let weights = (
        exactName: 0.55,
        queryCoverage: 0.20,
        candidateCoverage: 0.15,
        jaccard: 0.10
    )

    private let corpus: Corpus
    private let release: SourceRelease
    private let library: (any GenericFoodLibrarySearching)?
    private let ids: any LedgerIDGenerating

    public convenience init(
        library: (any GenericFoodLibrarySearching)? = nil,
        ids: any LedgerIDGenerating
    ) throws {
        guard let url = Bundle.module.url(
            forResource: "cofid-2021-generic-search-v1",
            withExtension: "json",
            subdirectory: "Resources"
        ) else { throw CoFIDSearchError.missingBundledCorpus }
        try self.init(corpusURL: url, library: library, ids: ids)
    }

    public init(
        corpusURL: URL,
        library: (any GenericFoodLibrarySearching)? = nil,
        ids: any LedgerIDGenerating
    ) throws {
        let data = try Data(contentsOf: corpusURL, options: [.mappedIfSafe])
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == Self.corpusCanonicalSHA256 else { throw CoFIDSearchError.corpusHashMismatch }
        do {
            corpus = try JSONDecoder().decode(Corpus.self, from: data)
            release = try Self.makeRelease(source: corpus.source)
        } catch let error as CoFIDSearchError {
            throw error
        } catch {
            throw CoFIDSearchError.malformedCorpus
        }
        self.library = library
        self.ids = ids
    }

    public var recordCount: Int { corpus.records.count }
    public var sourceRelease: SourceRelease { release }

    public func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        let evidence = try CaptureEvidence(
            evidenceID: ids.makeID(EvidenceTag.self),
            kind: .genericSearch,
            capturedAt: request.capturedAt,
            locale: request.locale,
            captureMethod: LedgerText("typed_generic_food_search"),
            captureMethodVersion: LedgerText(Self.matcherVersion),
            originalPayload: .text(request.text)
        )
        let alias = try LedgerText("food:name:\(Self.normalized(request.text.value))")
        if let saved = try library?.exactMatches(alias: alias), saved.count == 1,
           let route = try savedRoute(record: saved[0], evidence: evidence) {
            return .confirmation(route)
        }

        let ranked = try rankedRecords(for: request)
        guard !ranked.isEmpty else {
            return .noResult(GenericFoodNoResultRoute(evidence: evidence))
        }
        let matches = try ranked.map { value in
            GenericFoodMatch(
                candidate: try populatedCandidate(
                    record: value.record,
                    evidenceID: evidence.evidenceID,
                    score: value.score,
                    differences: value.differences,
                    queryAlias: alias
                ),
                isExactName: value.exact
            )
        }
        let first = matches[0].candidate.candidate
        let confirmation = try PopulatedFoodConfirmation(
            evidence: [evidence],
            sourceReleases: [release],
            candidates: matches.map(\.candidate),
            expectedIdentity: first.identity,
            expectedEdibleQuantity: first.edibleQuantity
        )
        return .confirmation(GenericFoodConfirmationRoute(
            confirmation: confirmation,
            matches: matches
        ))
    }

    private func savedRoute(
        record: BarcodeLibraryRecord,
        evidence: CaptureEvidence
    ) throws -> GenericFoodConfirmationRoute? {
        guard let sourceRelease = record.sourceReleases.first else { return nil }
        let quantity = record.libraryEntryVersion.reusableQuantity.map {
            EdibleQuantityIdentity.known(
                $0,
                conversionVersionID: record.libraryEntryVersion.quantityConversionVersionID
            )
        } ?? .unknown
        let metadata = try CandidateMatchMetadata(
            methodVersion: LedgerText("personal-library-exact-v1"),
            score: 1,
            materialDifferences: []
        )
        let providerCandidate = try ProviderNeutralCandidate(
            sourceReleaseID: sourceRelease.sourceReleaseID,
            recordID: ExternalIdentifier(
                "personal-library:\(record.libraryEntryVersion.libraryEntryVersionID.rawValue)"
            ),
            identity: record.productVersion.identity,
            edibleQuantity: quantity,
            nutrients: record.resolutionVersion.nutrients,
            evidenceIDs: [evidence.evidenceID],
            matchMetadata: metadata
        )
        let populated = try PopulatedFoodCandidate(
            candidate: providerCandidate,
            name: record.productVersion.name,
            brand: record.productVersion.brand,
            variant: record.productVersion.variant,
            barcode: record.productVersion.barcode,
            itemClass: record.productVersion.itemClass,
            packFacts: record.productVersion.packFacts
        )
        return GenericFoodConfirmationRoute(
            confirmation: try PopulatedFoodConfirmation(
                evidence: [evidence],
                sourceReleases: record.sourceReleases,
                candidates: [populated],
                expectedIdentity: providerCandidate.identity,
                expectedEdibleQuantity: providerCandidate.edibleQuantity
            ),
            matches: [GenericFoodMatch(candidate: populated, isExactName: true)],
            reuse: BarcodeReuseReference(record: record)
        )
    }

    private func rankedRecords(for request: GenericFoodSearchRequest) throws -> [RankedRecord] {
        let query = Self.normalized(request.text.value)
        let queryTokens = Set(query.split(separator: " ").map(String.init))
        guard !queryTokens.isEmpty else { return [] }
        var ranked: [RankedRecord] = []
        for record in corpus.records {
            guard Self.contradictions(query: request.identity, record: record).isEmpty else { continue }
            let candidate = Self.normalized(record.name)
            let candidateTokens = Set(candidate.split(separator: " ").map(String.init))
            let intersection = queryTokens.intersection(candidateTokens)
            let union = queryTokens.union(candidateTokens)
            let exact = query == candidate
            let exactScore: Double = exact ? Self.weights.exactName : 0
            let queryCoverage = Double(intersection.count) / Double(queryTokens.count)
            let candidateCoverage = Double(intersection.count) / Double(candidateTokens.count)
            let jaccard = Double(intersection.count) / Double(union.count)
            let score = exactScore
                + Self.weights.queryCoverage * queryCoverage
                + Self.weights.candidateCoverage * candidateCoverage
                + Self.weights.jaccard * jaccard
            guard score >= Self.minimumScore else { continue }
            let differences = candidateTokens.subtracting(queryTokens).sorted().map { "candidate_only_token:\($0)" }
                + queryTokens.subtracting(candidateTokens).sorted().map { "query_only_token:\($0)" }
            ranked.append(RankedRecord(record: record, score: score, exact: exact, differences: differences))
        }
        return Array(ranked.sorted {
            $0.score == $1.score ? $0.record.recordID < $1.record.recordID : $0.score > $1.score
        }.prefix(Self.candidateLimit))
    }

    private func populatedCandidate(
        record: CorpusRecord,
        evidenceID: EvidenceID,
        score: Double,
        differences: [String],
        queryAlias: LedgerText
    ) throws -> PopulatedFoodCandidate {
        let identity = try Self.identity(record.identity)
        let basisQuantity: PositiveQuantity
        switch identity.servingBasis {
        case .per100Millilitres:
            basisQuantity = try PositiveQuantity(value: 100, unit: .millilitres)
        default:
            basisQuantity = try PositiveQuantity(value: 100, unit: .grams)
        }
        let canonicalAlias = try LedgerText("food:name:\(Self.normalized(record.name))")
        let aliases = queryAlias == canonicalAlias ? [queryAlias] : [queryAlias, canonicalAlias]
        let metadata = try CandidateMatchMetadata(
            methodVersion: LedgerText(Self.matcherVersion),
            score: score,
            materialDifferences: try differences.map { try LedgerText($0) },
            libraryAliases: aliases
        )
        let candidate = try ProviderNeutralCandidate(
            sourceReleaseID: release.sourceReleaseID,
            recordID: ExternalIdentifier(record.recordID),
            identity: identity,
            edibleQuantity: .known(basisQuantity, conversionVersionID: nil),
            nutrients: try nutrients(record: record, identity: identity),
            evidenceIDs: [evidenceID],
            matchMetadata: metadata
        )
        return try PopulatedFoodCandidate(
            candidate: candidate,
            name: LedgerText(record.name),
            variant: record.description.isEmpty ? nil : LedgerText(record.description),
            itemClass: Self.itemClass(record: record),
            packFacts: PackFacts()
        )
    }

    private func nutrients(record: CorpusRecord, identity: DecisiveIdentity) throws -> NutrientSet {
        let provenance = { (key: NutrientKey) throws -> NutrientProvenance in
            NutrientProvenance(
                sourceKind: .genericCompositionDataset,
                sourceID: self.release.sourceID,
                sourceReleaseID: self.release.sourceReleaseID,
                recordID: try ExternalIdentifier(record.recordID),
                manifestReference: try LedgerText("cofid-2021-generic-search-v1.json")
            )
        }
        return try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard let value = record.nutrients[key.rawValue] else {
                return try NutrientEntry(key: key, value: .unknown(.notDeclared))
            }
            guard value.state == "numeric", let text = value.value, let amount = Double(text) else {
                let reason: UnknownReason = value.state == "blank" || value.state == "unmapped"
                    ? .notDeclared : .noCompatibleSource
                return try NutrientEntry(key: key, value: .unknown(reason))
            }
            guard value.sourceUnit == key.canonicalUnit.rawValue else {
                return try NutrientEntry(key: key, value: .unknown(.missingConversion))
            }
            let source = try SourceExactNutrientValue(
                amount: amount,
                unit: LedgerText(value.sourceUnit ?? key.canonicalUnit.rawValue),
                basis: identity.servingBasis
            )
            let exact = try ExactNutrientValue(
                amount: amount,
                unit: key.canonicalUnit,
                sourceValue: .exact(source),
                provenance: [provenance(key)]
            )
            return try NutrientEntry(key: key, value: .augmented(exact))
        })
    }

    private static func identity(_ source: CorpusIdentity) throws -> DecisiveIdentity {
        let preparation = try PreparationState(kind: PreparationKind(rawValue: source.preparation) ?? .unknown)
        let packing: PackingMediumState = source.packingMedium == "unknown"
            ? .unknown : .named(try LedgerText(source.packingMedium))
        return try DecisiveIdentity(
            preparation: preparation,
            bone: BoneState(rawValue: source.bone) ?? .unknown,
            skin: SkinState(rawValue: source.skin) ?? .unknown,
            drained: DrainedState(rawValue: source.drained) ?? .unknown,
            packingMedium: packing,
            fortification: FortificationState(rawValue: source.fortification) ?? .unknown,
            servingBasis: source.servingBasis == "per_100_ml" ? .per100Millilitres : .per100Grams
        )
    }

    private static func itemClass(record: CorpusRecord) -> ItemClass {
        if record.identity.fortification == "fortified" { return .fortifiedFood }
        if record.publishedGroup.hasPrefix("Q") { return .drink }
        if normalized(record.name) == "water" { return .water }
        return .food
    }

    private static func contradictions(
        query: GenericFoodIdentityQuery,
        record: CorpusRecord
    ) -> [String] {
        var values: [String] = []
        func require<Value: Equatable>(_ expected: Value?, _ actual: Value?, _ field: String) {
            guard let expected else { return }
            if actual == nil || actual != expected { values.append(field) }
        }
        require(query.preparation, try? PreparationState(kind: PreparationKind(rawValue: record.identity.preparation) ?? .unknown), "preparation")
        require(query.bone, BoneState(rawValue: record.identity.bone), "bone")
        require(query.skin, SkinState(rawValue: record.identity.skin), "skin")
        require(query.drained, DrainedState(rawValue: record.identity.drained), "drained")
        let packing: PackingMediumState? = record.identity.packingMedium == "unknown"
            ? .unknown : (try? .named(LedgerText(record.identity.packingMedium)))
        require(query.packingMedium, packing, "packing_medium")
        require(query.fortification, FortificationState(rawValue: record.identity.fortification), "fortification")
        let basis: ResolutionBasis = record.identity.servingBasis == "per_100_ml" ? .per100Millilitres : .per100Grams
        require(query.servingBasis, basis, "serving_basis")
        if query.edibleQuantity != nil, record.identity.edibleQuantity == "unknown" { values.append("edible_quantity") }
        if let salt = query.saltState, salt.value != record.identity.saltState { values.append("salt_state") }
        if let formulation = query.formulation, formulation.value != record.identity.formulation { values.append("formulation") }
        return values
    }

    public static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let aliases = [
            "aubergines": "aubergine", "eggplant": "aubergine", "eggplants": "aubergine",
            "garbanzo": "chickpea", "garbanzos": "chickpea", "yogurt": "yoghurt", "yogurts": "yoghurt"
        ]
        let tokens = folded.lowercased().split { !$0.isASCII || !$0.isLetter && !$0.isNumber }
        return tokens.map { aliases[String($0)] ?? String($0) }.joined(separator: " ")
    }

    private static func makeRelease(source: CorpusSource) throws -> SourceRelease {
        SourceRelease(
            sourceReleaseID: try ExternalIdentifier(source.releaseID),
            sourceID: try ExternalIdentifier(source.sourceID),
            releasedAt: ISO8601DateFormatter().date(from: "2021-03-19T00:00:00Z")!,
            artifactHash: try SHA256Digest(source.artifactSHA256),
            schemaVersion: try LedgerText("cofid-generic-search-v1"),
            pipelineVersion: try LedgerText("cofid-projection-v1"),
            licence: try LedgerText(source.licence),
            attribution: try LedgerText(source.attribution),
            manifestHash: try SHA256Digest(Self.corpusCanonicalSHA256)
        )
    }
}

private struct RankedRecord {
    let record: CorpusRecord
    let score: Double
    let exact: Bool
    let differences: [String]
}

private struct Corpus: Decodable {
    let source: CorpusSource
    let records: [CorpusRecord]
}

private struct CorpusSource: Decodable {
    let sourceID: String
    let releaseID: String
    let artifactSHA256: String
    let licence: String
    let attribution: String

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case releaseID = "release_id"
        case artifactSHA256 = "artifact_sha256"
        case licence, attribution
    }
}

private struct CorpusRecord: Decodable {
    let recordID: String
    let name: String
    let description: String
    let publishedGroup: String
    let identity: CorpusIdentity
    let nutrients: [String: CorpusNutrient]

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id"
        case name, description
        case publishedGroup = "published_group"
        case identity, nutrients
    }
}

private struct CorpusIdentity: Decodable {
    let preparation: String
    let bone: String
    let skin: String
    let drained: String
    let packingMedium: String
    let fortification: String
    let saltState: String
    let servingBasis: String
    let edibleQuantity: String
    let formulation: String

    enum CodingKeys: String, CodingKey {
        case preparation, bone, skin, drained, fortification, formulation
        case packingMedium = "packing_medium"
        case saltState = "salt_state"
        case servingBasis = "serving_basis"
        case edibleQuantity = "edible_quantity"
    }
}

private struct CorpusNutrient: Decodable {
    let state: String
    let sourceUnit: String?
    let canonicalUnit: String
    let value: String?

    enum CodingKeys: String, CodingKey {
        case state, value
        case sourceUnit = "source_unit"
        case canonicalUnit = "canonical_unit"
    }
}
