import CryptoKit
import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

public enum USDASearchError: Error, Equatable { case missingCorpus, hashMismatch, invalidCorpus }

/// Offline, whole-record US-composition alternatives. Never backfills another source.
public final class USDAGenericFoodSearch: GenericFoodSearching, @unchecked Sendable {
    public static let matcherVersion = "usda-primary-name-v3"
    public static let corpusSHA256 = "70480d2c58bac9fcf9646b3b66c70be00e52398695536cef0af129ea1528e4c7"
    private let corpus: USDACorpus
    private let releases: [String: SourceRelease]
    private let ids: any LedgerIDGenerating

    public convenience init(ids: any LedgerIDGenerating) throws {
        guard let url = Bundle.module.url(forResource: "usda-generic-v1", withExtension: "json", subdirectory: "Resources") else {
            throw USDASearchError.missingCorpus
        }
        try self.init(corpusURL: url, ids: ids)
    }

    public init(corpusURL: URL, ids: any LedgerIDGenerating) throws {
        let data = try Data(contentsOf: corpusURL, options: .mappedIfSafe)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == Self.corpusSHA256 else { throw USDASearchError.hashMismatch }
        corpus = try JSONDecoder().decode(USDACorpus.self, from: data)
        guard corpus.version == 1, Set(corpus.records.map(\.id)).count == corpus.records.count,
              Set(corpus.sources.map(\.id)).count == corpus.sources.count else { throw USDASearchError.invalidCorpus }
        var sources: [String: SourceRelease] = [:]
        for source in corpus.sources {
            guard let date = ISO8601DateFormatter().date(from: source.date + "T00:00:00Z") else { throw USDASearchError.invalidCorpus }
            sources[source.id] = SourceRelease(
                sourceReleaseID: try ExternalIdentifier(source.id), sourceID: try ExternalIdentifier(source.sourceID),
                releasedAt: date, artifactHash: try SHA256Digest(source.archiveHash),
                schemaVersion: try LedgerText("usda-generic-v1"), pipelineVersion: try LedgerText("usda-projection-v1"),
                licence: try LedgerText("CC0 1.0"),
                attribution: try LedgerText("US Department of Agriculture, Agricultural Research Service. FoodData Central. US composition estimates."),
                manifestHash: try SHA256Digest(Self.corpusSHA256)
            )
        }
        guard corpus.records.allSatisfy({ sources[$0.releaseID] != nil }) else { throw USDASearchError.invalidCorpus }
        releases = sources
        self.ids = ids
    }

    public var recordCount: Int { corpus.records.count }

    public func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        let evidence = try request.captureEvidence ?? CaptureEvidence(
            evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch, capturedAt: request.capturedAt,
            locale: request.locale, captureMethod: LedgerText("typed_generic_food_search"),
            captureMethodVersion: LedgerText(Self.matcherVersion), originalPayload: .text(request.text)
        )
        let evidenceList = [evidence] + request.additionalEvidence
        guard Set(evidenceList.map(\.evidenceID)).count == evidenceList.count else {
            throw FoodLedgerValidationError.duplicateValue("search evidence")
        }
        let tokens = Self.tokens(request.text.value)
        guard !tokens.isEmpty else { return .noResult(GenericFoodNoResultRoute(evidence: evidence, additionalEvidence: request.additionalEvidence)) }
        let ranked = try corpus.records.compactMap { record -> (USDARecord, Double)? in
            let candidateTokens = Self.tokens(record.name)
            guard tokens.isSubset(of: candidateTokens), try Self.accepts(request.identity, identity: Self.identity(record)) else { return nil }
            let primaryBonus = GenericFoodSearchTerms.primaryNameMatches(record.name, query: tokens) ? 0.3 : 0
            return (record, (Double(tokens.count) / Double(candidateTokens.count) + primaryBonus) / 1.3)
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.id < rhs.0.id : lhs.1 > rhs.1
        }.prefix(10)
        guard !ranked.isEmpty else { return .noResult(GenericFoodNoResultRoute(evidence: evidence, additionalEvidence: request.additionalEvidence, suggestedQueries: GenericFoodSearchTerms.suggestions(for: request.text.value, names: corpus.records.map(\.name)))) }
        let matches = try ranked.map { record, score in
            GenericFoodMatch(candidate: try candidate(record, score: score, evidence: evidenceList, query: request.text),
                             isExactName: CoFIDGenericFoodSearch.normalized(record.name) == CoFIDGenericFoodSearch.normalized(request.text.value))
        }
        let sourceIDs = Set(matches.map { $0.candidate.candidate.sourceReleaseID.value })
        let first = matches[0].candidate.candidate
        return .confirmation(GenericFoodConfirmationRoute(
            confirmation: try PopulatedFoodConfirmation(
                evidence: evidenceList, sourceReleases: sourceIDs.sorted().compactMap { releases[$0] },
                candidates: matches.map(\.candidate), expectedIdentity: first.identity, expectedEdibleQuantity: first.edibleQuantity
            ), matches: matches
        ))
    }

    private func candidate(_ record: USDARecord, score: Double, evidence: [CaptureEvidence], query: LedgerText) throws -> PopulatedFoodCandidate {
        guard let release = releases[record.releaseID] else { throw USDASearchError.invalidCorpus }
        let identity = try Self.identity(record)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard let value = record.nutrients[key.rawValue] else {
                return try NutrientEntry(key: key, value: .unknown(.notDeclared))
            }
            guard value.unit == key.canonicalUnit.rawValue else {
                return try NutrientEntry(key: key, value: .unknown(.missingConversion))
            }
            let original = try SourceExactNutrientValue(amount: value.amount, unit: LedgerText(value.unit), basis: .per100Grams)
            let provenance = NutrientProvenance(
                sourceKind: .genericCompositionDataset, sourceID: release.sourceID, sourceReleaseID: release.sourceReleaseID,
                recordID: try ExternalIdentifier(record.id),
                manifestReference: try LedgerText("usda-generic-v1.json:nutrient:\(value.nutrientID)")
            )
            let exact = try ExactNutrientValue(amount: value.amount, unit: key.canonicalUnit, sourceValue: .exact(original), provenance: [provenance])
            return try NutrientEntry(key: key, value: .augmented(exact))
        })
        let alias = try LedgerText("food:name:\(CoFIDGenericFoodSearch.normalized(query.value))")
        let metadata = try CandidateMatchMetadata(
            methodVersion: LedgerText(Self.matcherVersion), score: score,
            materialDifferences: [LedgerText("Search terms: \(Self.tokens(query.value).sorted().joined(separator: " ")); spelling equivalents only, original query retained."), LedgerText("US composition estimate; review cut, grade, fat and preparation."),
                                 LedgerText("US carbohydrate by difference includes fibre; vitamin A RAE is not substituted." )],
            libraryAliases: [alias]
        )
        let value = try ProviderNeutralCandidate(
            sourceReleaseID: release.sourceReleaseID, recordID: ExternalIdentifier(record.id), identity: identity,
            edibleQuantity: .known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil),
            nutrients: nutrients, evidenceIDs: evidence.map(\.evidenceID), matchMetadata: metadata
        )
        return try PopulatedFoodCandidate(candidate: value, name: LedgerText(record.name),
                                          variant: LedgerText("USDA · US composition estimate · per 100 g"), itemClass: .food, packFacts: PackFacts())
    }

    private static func tokens(_ value: String) -> Set<String> {
        GenericFoodSearchTerms.tokens(value)
    }

    private static func identity(_ record: USDARecord) throws -> DecisiveIdentity {
        try DecisiveIdentity(preparation: PreparationState(kind: PreparationKind(rawValue: record.preparation) ?? .unknown),
                            bone: BoneState(rawValue: record.bone) ?? .unknown, skin: .unknown, drained: .unknown,
                            packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams)
    }

    private static func accepts(_ query: GenericFoodIdentityQuery, identity: DecisiveIdentity) -> Bool {
        func accepts<T: Equatable>(_ expected: T?, _ actual: T) -> Bool { expected == nil || expected == actual }
        return accepts(query.preparation, identity.preparation) && accepts(query.bone, identity.bone)
            && accepts(query.skin, identity.skin) && accepts(query.drained, identity.drained)
            && accepts(query.packingMedium, identity.packingMedium) && accepts(query.fortification, identity.fortification)
            && accepts(query.servingBasis, identity.servingBasis)
            && query.edibleQuantity == nil && query.saltState == nil && query.formulation == nil
    }
}

private struct USDACorpus: Decodable { let version: Int; let sources: [USDASource]; let records: [USDARecord] }
private struct USDASource: Decodable { let id: String; let sourceID: String; let date: String; let archiveHash: String }
private struct USDARecord: Decodable { let id: String; let releaseID: String; let name: String; let preparation: String; let bone: String; let nutrients: [String: USDANutrient] }
private struct USDANutrient: Decodable { let amount: Double; let unit: String; let nutrientID: Int }
