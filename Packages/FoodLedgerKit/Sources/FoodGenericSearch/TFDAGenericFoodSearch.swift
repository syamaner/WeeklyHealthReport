import CryptoKit
import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

public enum TFDASearchError: Error, Equatable { case missingCorpus, hashMismatch, invalidCorpus }

/// Reviewed Taiwan composition records. Retrieval aliases never change source identity or values.
public final class TFDAGenericFoodSearch: GenericFoodSearching, @unchecked Sendable {
    public static let matcherVersion = "tfda-reviewed-ranking-v1"
    public static let corpusSHA256 = "95949fcb64a6a45ede5298080ded30feebb9608e1054fa7d3dca6f422a67d72a"
    private let corpus: TFDACorpus
    private let release: SourceRelease
    private let ids: any LedgerIDGenerating

    public convenience init(ids: any LedgerIDGenerating) throws {
        guard let url = Bundle.module.url(forResource: "tfda-generic-v1", withExtension: "json", subdirectory: "Resources") else {
            throw TFDASearchError.missingCorpus
        }
        try self.init(corpusURL: url, ids: ids)
    }

    public init(corpusURL: URL, ids: any LedgerIDGenerating) throws {
        let data = try Data(contentsOf: corpusURL)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == Self.corpusSHA256 else {
            throw TFDASearchError.hashMismatch
        }
        corpus = try JSONDecoder().decode(TFDACorpus.self, from: data)
        guard corpus.schema == "tfda-generic-v1", corpus.projectionVersion == "tfda-projection-v1",
              corpus.aliasPolicy == "tfda-reviewed-names-v1", !corpus.records.isEmpty,
              Set(corpus.records.map(\.id)).count == corpus.records.count,
              let date = ISO8601DateFormatter().date(from: corpus.snapshotDate + "T00:00:00Z") else {
            throw TFDASearchError.invalidCorpus
        }
        release = try SourceRelease(sourceReleaseID: ExternalIdentifier("tfda-taiwan:projection:\(Self.corpusSHA256)"),
            sourceID: ExternalIdentifier("tfda-taiwan"), releasedAt: date, artifactHash: SHA256Digest(corpus.archiveSHA256),
            schemaVersion: LedgerText(corpus.schema), pipelineVersion: LedgerText(corpus.projectionVersion + ":" + corpus.aliasPolicy),
            licence: LedgerText("Open Government Data License 1.0 · https://data.gov.tw/license"),
            attribution: LedgerText("Taiwan Food and Drug Administration, 2026. 食品營養成分資料集 (Nutrition Information Database), snapshot 2026-10-03. Open Data under Open Government Data License 1.0. Reviewed projection and translations; no TFDA endorsement. https://data.gov.tw/en/datasets/8543"),
            manifestHash: SHA256Digest(Self.corpusSHA256))
        self.ids = ids
    }

    public var recordCount: Int { corpus.records.count }

    public func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        let evidence = try request.captureEvidence ?? CaptureEvidence(evidenceID: ids.makeID(EvidenceTag.self),
            kind: .genericSearch, capturedAt: request.capturedAt, locale: request.locale,
            captureMethod: LedgerText("typed_generic_food_search"), captureMethodVersion: LedgerText(Self.matcherVersion),
            originalPayload: .text(request.text))
        let retained = [evidence] + request.additionalEvidence
        guard Set(retained.map(\.evidenceID)).count == retained.count else { throw FoodLedgerValidationError.duplicateValue("search evidence") }
        func miss() -> GenericFoodSearchOutcome {
            .noResult(GenericFoodNoResultRoute(evidence: evidence, additionalEvidence: request.additionalEvidence))
        }
        let parsed = request.parsedQuery
        guard request.interpretation.allowsDiscovery,
              Set(parsed.attributes.keys).isSubset(of: ["preparation", "sweetening", "preservation", "fat_descriptor"]) else { return miss() }
        // Broad raw/cooked states are checked against source metadata. Cooking methods
        // and every other descriptor remain lexical requirements, never silently dropped.
        let words = GenericFoodSearchTerms.tokens([request.retrievalText, parsed.attributes["sweetening"],
            parsed.attributes["preservation"], parsed.attributes["fat_descriptor"]].compactMap { $0 }.joined(separator: " "))
        let terms = words.subtracting(["raw", "uncooked", "cooked"])
        guard !terms.isEmpty else { return miss() }
        let ranked = try corpus.records.compactMap { record -> (TFDARecord, Double, Bool)? in
            let identity = try Self.identity(record)
            guard Self.accepts(request.identity, identity: identity),
                  FoodPreparationDiscoveryPolicy.accepts(requested: request.identity.preparation, actual: identity.preparation,
                    sourceName: record.name, query: parsed) else { return nil }
            let forms = GenericFoodSearchTerms.tokens(record.name).intersection(["frozen", "dried", "salted"])
            // Match one reviewed name at a time, not a bag assembled from unrelated synonyms.
            let names = record.aliases.map { GenericFoodSearchTerms.tokens($0).subtracting(["raw", "uncooked", "cooked"]) }
            let matches = names.filter { !($0.isEmpty) && terms.isSubset(of: $0) }
            // An exact reviewed name can express the form in Chinese or romanisation.
            // Partial matches still need the explicit English form qualifier.
            guard forms.isSubset(of: words) || matches.contains(terms) else { return nil }
            guard let best = matches.min(by: { $0.count < $1.count }) else { return nil }
            return (record, Double(terms.count) / Double(best.count), terms == best)
        }.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.id < b.0.id
        }.prefix(10)
        guard !ranked.isEmpty else { return miss() }
        let matches = try ranked.map { record, score, exact in
            GenericFoodMatch(candidate: try candidate(record, score: score, evidence: retained), isExactName: exact)
        }
        let first = matches[0].candidate.candidate
        return .confirmation(GenericFoodConfirmationRoute(confirmation: try PopulatedFoodConfirmation(
            evidence: retained, sourceReleases: [release], candidates: matches.map(\.candidate),
            expectedIdentity: first.identity, expectedEdibleQuantity: .unknown), matches: matches))
    }

    private func candidate(_ record: TFDARecord, score: Double, evidence: [CaptureEvidence]) throws -> PopulatedFoodCandidate {
        let recordID = try ExternalIdentifier("tfda:" + record.id)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard let value = record.nutrients[key.rawValue] else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            guard value.unit == key.canonicalUnit.rawValue else { throw TFDASearchError.invalidCorpus }
            let original = try SourceExactNutrientValue(amount: value.amount, unit: LedgerText(value.unit), basis: .per100Grams)
            let provenance = try NutrientProvenance(sourceKind: .genericCompositionDataset,
                sourceID: release.sourceID, sourceReleaseID: release.sourceReleaseID, recordID: recordID,
                responseHash: SHA256Digest(corpus.sourceJSONSHA256),
                manifestReference: LedgerText("20_5.json:/\(value.sourceRow)/每100克含量;record=\(record.id);field=\(value.sourceField);literal=\(value.literal);projection=\(Self.corpusSHA256)"))
            return try NutrientEntry(key: key, value: .augmented(ExactNutrientValue(amount: value.amount,
                unit: key.canonicalUnit, sourceValue: .exact(original), provenance: [provenance])))
        })
        let identity = try Self.identity(record)
        let stateLabel = identity.preparation.kind == .raw && !record.name.lowercased().contains("raw") ? ", raw" : ""
        return try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: release.sourceReleaseID,
            recordID: recordID, identity: identity,
            edibleQuantity: .known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil),
            nutrients: nutrients, evidenceIDs: evidence.map(\.evidenceID),
            matchMetadata: CandidateMatchMetadata(methodVersion: LedgerText(Self.matcherVersion), score: score,
                materialDifferences: [LedgerText("Taiwan composition estimate. Review variety, ingredients and preparation; this is not an exact vendor or packaged-product recipe."),
                    LedgerText("Source sample: \(record.sourceName). \(record.description)"),
                    LedgerText("Per 100 g edible portion. Source 熱量 energy and 總碳水化合物 carbohydrate conventions retained; missing values and serving weights remain unknown.")], libraryAliases: [])),
            name: LedgerText(record.name + stateLabel + " · " + record.sourceName),
            variant: LedgerText("TFDA · Taiwan composition estimate · per 100 g edible portion"), itemClass: .food, packFacts: PackFacts())
    }

    private static func identity(_ record: TFDARecord) throws -> DecisiveIdentity {
        guard let kind = PreparationKind(rawValue: record.preparation) else { throw TFDASearchError.invalidCorpus }
        return try DecisiveIdentity(preparation: PreparationState(kind: kind), bone: .unknown, skin: .unknown,
            drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams)
    }

    private static func accepts(_ query: GenericFoodIdentityQuery, identity: DecisiveIdentity) -> Bool {
        func same<T: Equatable>(_ expected: T?, _ actual: T) -> Bool { expected == nil || expected == actual }
        return same(query.bone, identity.bone) && same(query.skin, identity.skin) && same(query.drained, identity.drained)
            && same(query.packingMedium, identity.packingMedium) && same(query.fortification, identity.fortification)
            && same(query.servingBasis, identity.servingBasis) && query.edibleQuantity == nil
            && query.saltState == nil && query.formulation == nil
    }
}

private struct TFDACorpus: Decodable {
    let schema, projectionVersion, aliasPolicy, snapshotDate, archiveSHA256, sourceJSONSHA256: String
    let records: [TFDARecord]
}
private struct TFDARecord: Decodable {
    let id, name, sourceName, description, preparation: String
    let aliases: [String]
    let nutrients: [String: TFDANutrient]
}
private struct TFDANutrient: Decodable {
    let amount: Double
    let unit, sourceField, literal: String
    let sourceRow: Int
}
