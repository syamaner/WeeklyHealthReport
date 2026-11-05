import CryptoKit
import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

public enum CiqualSearchError: Error, Equatable { case missingCorpus, hashMismatch, invalidCorpus }

/// Offline Ciqual 2025 French composition estimates, the chocolate subgroup only
/// (docs/ciqual-2025-admission-v1.md). Whole-record candidates with the USDA eligibility rules;
/// never backfills another source and never a re-resolution target. Wired as a reference-only
/// source of `composite-generic-ranking-v11`.
public final class CiqualGenericFoodSearch: GenericFoodSearching, GenericSourceRecordDetailing, @unchecked Sendable {
    public static let matcherVersion = "ciqual-generic-ranking-v1"
    public static let corpusSHA256 = "2a298bd5e9c43d2e32ed3164c2a53de0dc21f80c9812285faf137dde196f333f"
    public static let sourceManifestSHA256 = "3134f8dc9feb3e17e4d297fdc42f7711eff41af3210facb5d24c35194fa0d847"
    static let compoSHA256 = "8c46a9032ece4eab4ffccc9dfcb0c490ec2f416aa664cc1ee013b241c6bdd4af"
    static let licence = "Etalab Open Licence 2.0 · https://www.etalab.gouv.fr/licence-ouverte-open-licence/"
    static let attribution = "Anses. 2025. Table de composition nutritionnelle des aliments Ciqual 2025. https://doi.org/10.57745/RDMHWY. Reviewed projection of the chocolate group; English names as published by Anses; no Anses endorsement."
    static let variant = "Ciqual · French composition estimate · per 100 g"
    private let corpus: CiqualCorpus
    private let release: SourceRelease
    private let nutrientSets: [String: NutrientSet]
    private let recordDetails: [String: GenericSourceRecordDetails]
    private let ids: any LedgerIDGenerating

    public convenience init(ids: any LedgerIDGenerating) throws {
        guard let url = Bundle.module.url(forResource: "ciqual-2025-generic-v1", withExtension: "json", subdirectory: "Resources") else {
            throw CiqualSearchError.missingCorpus
        }
        try self.init(corpusURL: url, ids: ids)
    }

    public init(corpusURL: URL, ids: any LedgerIDGenerating) throws {
        let data = try Data(contentsOf: corpusURL)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == Self.corpusSHA256 else {
            throw CiqualSearchError.hashMismatch
        }
        corpus = try JSONDecoder().decode(CiqualCorpus.self, from: data)
        let sourceReleaseID = "ciqual:2025-11-19:sha256:" + Self.sourceManifestSHA256
        guard corpus.schema == "ciqual-generic-v1", corpus.projectionVersion == "ciqual-projection-v1",
              corpus.groupScope == "ciqual-group-scope-v1", corpus.sourceID == "ciqual",
              corpus.sourceManifestSHA256 == Self.sourceManifestSHA256, corpus.sourceReleaseID == sourceReleaseID,
              corpus.compoSHA256 == Self.compoSHA256, corpus.releasedAt == "2025-11-19T00:00:00Z",
              corpus.basis == "per100Grams", corpus.preparationPolicy == "usda-preparation-words-v2",
              corpus.licence == Self.licence, corpus.attribution == Self.attribution, corpus.variant == Self.variant,
              !corpus.records.isEmpty, Set(corpus.records.map(\.alimCode)).count == corpus.records.count,
              corpus.records.allSatisfy({ $0.subgroupCode == "0702" && $0.recordID == "\(sourceReleaseID):alim:\($0.alimCode)"
                  && Set($0.nutrients.keys) == Set(NutrientKey.allCases.map(\.rawValue)) && PreparationKind(rawValue: $0.preparation) != nil }),
              let date = ISO8601DateFormatter().date(from: corpus.releasedAt) else {
            throw CiqualSearchError.invalidCorpus
        }
        // A corrected projection must coexist with immutable releases in older saves (as USDA).
        release = try SourceRelease(sourceReleaseID: ExternalIdentifier("\(sourceReleaseID):projection:\(Self.corpusSHA256)"),
            sourceID: ExternalIdentifier("ciqual"), releasedAt: date, artifactHash: SHA256Digest(Self.sourceManifestSHA256),
            schemaVersion: LedgerText(corpus.schema), pipelineVersion: LedgerText(corpus.projectionVersion + ":" + corpus.groupScope),
            licence: LedgerText(Self.licence), attribution: LedgerText(Self.attribution), manifestHash: SHA256Digest(Self.corpusSHA256))
        var sets: [String: NutrientSet] = [:]
        for record in corpus.records {
            sets[record.alimCode] = try Self.nutrients(record, release: release)
        }
        nutrientSets = sets
        recordDetails = try Dictionary(uniqueKeysWithValues: corpus.records.map { ($0.recordID, try Self.details($0)) })
        self.ids = ids
    }

    public var recordCount: Int { corpus.records.count }

    /// Developer tools only (section 7, D5, A7): the French name and each value's literal,
    /// confidence, source code and `min`/`max` literals. Nothing here reaches a candidate.
    public func details(recordID: ExternalIdentifier) -> GenericSourceRecordDetails? { recordDetails[recordID.value] }

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
        // No suggestions: a reference-only source never changes another source's no-result route.
        func miss() -> GenericFoodSearchOutcome {
            .noResult(GenericFoodNoResultRoute(evidence: evidence, additionalEvidence: request.additionalEvidence))
        }
        let food = request.retrievalText
        let parsed = request.parsedQuery
        let tokens = GenericFoodSearchTerms.tokens(food)
        guard !tokens.isEmpty else { return miss() }
        // The USDA eligibility rules: every meaningful query word in the English name, the
        // phase A cocoa exception, food form, derivative names and identity guards. CoFID's UK
        // name equivalence matches only CoFID's "Chocolate, plain" names, never a Ciqual name.
        let eligible = try corpus.records.compactMap { record -> (CiqualRecord, Double, GenericFoodRankingPolicy.Preference)? in
            let candidateTokens = GenericFoodSearchTerms.tokens(record.name)
            let identity = try Self.identity(record)
            guard tokens.isSubset(of: candidateTokens)
                    || CocoaPercentPolicy.admits(name: record.name, description: nil, recordID: record.recordID, query: parsed, foodTerms: tokens),
                  GenericFoodSearchTerms.acceptsFoodForm(name: record.name, query: tokens, literal: false),
                  GenericFoodRankingPolicy.allowsDerivativeFoodName(record.name, query: food),
                  Self.accepts(request.identity, identity: identity, name: record.name, parsed: parsed) else { return nil }
            let primaryBonus = GenericFoodSearchTerms.primaryNameMatches(record.name, query: tokens) ? 0.3 : 0
            return (record, (Double(tokens.count) / Double(candidateTokens.count) + primaryBonus) / 1.3,
                GenericFoodRankingPolicy.preference(name: record.name, food: food, requestedText: request.text.value))
        }
        // The cocoa tier applies before the cut, so a single-source caller sees the same rows.
        let cocoa = CocoaPercentPolicy.requested(parsed).map { value in
            CocoaPercentPolicy.tierKeys(eligible.map { CocoaPercentPolicy.band(name: $0.0.name, description: nil, recordID: $0.0.recordID) }, requested: value)
        }
        let ranked = eligible.indices.sorted { left, right in
            let lhs = eligible[left], rhs = eligible[right]
            let a = FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation,
                actual: PreparationKind(rawValue: lhs.0.preparation) ?? .unknown)
            let b = FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation,
                actual: PreparationKind(rawValue: rhs.0.preparation) ?? .unknown)
            if a != b { return !a }
            if let cocoa, cocoa[left] != cocoa[right] { return cocoa[left] < cocoa[right] }
            if lhs.2 != rhs.2 { return GenericFoodRankingPolicy.prefers(lhs.2, over: rhs.2) }
            return lhs.1 == rhs.1 ? lhs.0.alimCode < rhs.0.alimCode : lhs.1 > rhs.1
        }.prefix(10).map { eligible[$0] }
        guard !ranked.isEmpty else { return miss() }
        let matches = try ranked.map { record, score, _ in
            GenericFoodMatch(candidate: try candidate(record, score: score, evidence: evidenceList, query: request.text),
                             isExactName: CoFIDGenericFoodSearch.normalized(record.name) == CoFIDGenericFoodSearch.normalized(food))
        }
        let first = matches[0].candidate.candidate
        return .confirmation(GenericFoodConfirmationRoute(
            confirmation: try PopulatedFoodConfirmation(
                evidence: evidenceList, sourceReleases: [release], candidates: matches.map(\.candidate),
                expectedIdentity: first.identity, expectedEdibleQuantity: first.edibleQuantity
            ), matches: matches
        ))
    }

    private func candidate(_ record: CiqualRecord, score: Double, evidence: [CaptureEvidence], query: LedgerText) throws -> PopulatedFoodCandidate {
        guard let nutrients = nutrientSets[record.alimCode] else { throw CiqualSearchError.invalidCorpus }
        let alias = try LedgerText("food:name:\(CoFIDGenericFoodSearch.normalized(query.value))")
        let metadata = try CandidateMatchMetadata(
            methodVersion: LedgerText(Self.matcherVersion), score: score,
            materialDifferences: [
                LedgerText("French composition estimate. Review the product, filling and sweetening; this is not an exact brand or packaged-product recipe."),
                LedgerText("Per 100 g as sold. Energy is the published EU regulation kcal value; carbohydrate excludes fibre; values published as less than a figure stay upper bounds; traces, missing values, vitamin A and water stay unknown.")
            ],
            libraryAliases: [alias]
        )
        // The French name stays in the corpus (Developer tools only): never the name or variant.
        let value = try ProviderNeutralCandidate(
            sourceReleaseID: release.sourceReleaseID, recordID: ExternalIdentifier(record.recordID), identity: Self.identity(record),
            edibleQuantity: .known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil),
            nutrients: nutrients, evidenceIDs: evidence.map(\.evidenceID), matchMetadata: metadata
        )
        return try PopulatedFoodCandidate(candidate: value, name: LedgerText(record.name),
                                          variant: LedgerText(Self.variant), itemClass: .food, packFacts: PackFacts())
    }

    /// `ciqual-projection-v1` values: exact decimal strings, open upper bounds for "< n" and
    /// unknown with the corpus reason. Never zero for an unknown, never exact for a bound.
    private static func nutrients(_ record: CiqualRecord, release: SourceRelease) throws -> NutrientSet {
        try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard let value = record.nutrients[key.rawValue] else { throw CiqualSearchError.invalidCorpus }
            switch value.state {
            case "unknown":
                guard let raw = value.reason, let reason = UnknownReason(rawValue: raw), reason != .conflictingEvidence,
                      value.value == nil, value.upper == nil else { throw CiqualSearchError.invalidCorpus }
                return try NutrientEntry(key: key, value: .unknown(reason))
            case "exact":
                guard let amount = decimal(value.value), value.upper == nil, value.reason == nil,
                      value.unit == key.canonicalUnit.rawValue else { throw CiqualSearchError.invalidCorpus }
                let source = try SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)
                return try NutrientEntry(key: key, value: .augmented(ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                    sourceValue: .exact(source), provenance: [provenance(record, value, release: release)])))
            case "bounded":
                guard let upper = decimal(value.upper), upper > 0, value.upperClosed == false, value.value == nil,
                      value.reason == nil, value.unit == key.canonicalUnit.rawValue else { throw CiqualSearchError.invalidCorpus }
                let source = try SourceBoundedNutrientValue(lower: nil, upper: upper, lowerClosed: false, upperClosed: false,
                                                            unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)
                return try NutrientEntry(key: key, value: .bounded(NutrientBounds(lower: nil, upper: upper, lowerClosed: false,
                    upperClosed: false, origin: .augmented, unit: key.canonicalUnit, sourceValue: .bounded(source),
                    provenance: [provenance(record, value, release: release)])))
            default:
                throw CiqualSearchError.invalidCorpus
            }
        })
    }

    /// Every value with a source row, in catalogue order; the four keys with no constituent
    /// have none. A row whose codes do not match its literal is a corrupt corpus.
    private static func details(_ record: CiqualRecord) throws -> GenericSourceRecordDetails {
        let values = try NutrientKey.allCases.compactMap { key -> GenericSourceRecordDetails.Value? in
            guard let value = record.nutrients[key.rawValue], let literal = value.literal else { return nil }
            // A "-" carries no confidence or source code; every other literal carries both (3.2).
            let dash = literal == "-"
            guard let constCode = value.constCode, dash == (value.confidence == nil), dash == (value.sourceCode == nil),
                  value.confidence.map({ ["A", "B", "C", "D"].contains($0) }) ?? true else { throw CiqualSearchError.invalidCorpus }
            return GenericSourceRecordDetails.Value(key: key, constituentCode: constCode, literal: literal, confidence: value.confidence,
                                                    sourceCode: value.sourceCode, minimum: value.min, maximum: value.max)
        }
        return GenericSourceRecordDetails(sourceName: "Ciqual", originalNameLanguage: "French",
                                          originalName: record.frenchName, values: values)
    }

    /// The per-value reference is built at runtime from the corpus SHA-256, as TFDA does.
    private static func provenance(_ record: CiqualRecord, _ value: CiqualValue, release: SourceRelease) throws -> NutrientProvenance {
        guard let constCode = value.constCode, let literal = value.literal, let confidence = value.confidence,
              ["A", "B", "C", "D"].contains(confidence) else { throw CiqualSearchError.invalidCorpus }
        return try NutrientProvenance(sourceKind: .genericCompositionDataset, sourceID: release.sourceID,
            sourceReleaseID: release.sourceReleaseID, recordID: ExternalIdentifier(record.recordID),
            responseHash: SHA256Digest(compoSHA256),
            manifestReference: LedgerText("compo_2025_11_03.xml;alim=\(record.alimCode);const=\(constCode);literal=\(literal);confidence=\(confidence);projection=\(corpusSHA256)"))
    }

    /// A fixed decimal rule (digits, one optional point and digits), never a locale.
    static func decimal(_ text: String?) -> Double? {
        guard let text, text.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private static func identity(_ record: CiqualRecord) throws -> DecisiveIdentity {
        try DecisiveIdentity(preparation: PreparationState(kind: PreparationKind(rawValue: record.preparation) ?? .unknown),
                             bone: .unknown, skin: .unknown, drained: .unknown, packingMedium: .unknown,
                             fortification: .unknown, servingBasis: .per100Grams)
    }

    private static func accepts(_ query: GenericFoodIdentityQuery, identity: DecisiveIdentity, name: String, parsed: ParsedFoodQuery) -> Bool {
        func accepts<T: Equatable>(_ expected: T?, _ actual: T) -> Bool { expected == nil || expected == actual }
        return FoodPreparationDiscoveryPolicy.accepts(requested: query.preparation, actual: identity.preparation, sourceName: name, query: parsed)
            && accepts(query.bone, identity.bone)
            && accepts(query.skin, identity.skin) && accepts(query.drained, identity.drained)
            && accepts(query.packingMedium, identity.packingMedium) && accepts(query.fortification, identity.fortification)
            && accepts(query.servingBasis, identity.servingBasis)
            && query.edibleQuantity == nil && query.saltState == nil && query.formulation == nil
    }
}

private struct CiqualCorpus: Decodable {
    let schema, projectionVersion, groupScope, sourceID, sourceManifestSHA256, sourceReleaseID, compoSHA256: String
    let releasedAt, basis, preparationPolicy, licence, attribution, variant: String
    let records: [CiqualRecord]
}
private struct CiqualRecord: Decodable {
    let alimCode, recordID, name, frenchName, subgroupCode, preparation: String
    let nutrients: [String: CiqualValue]
}
private struct CiqualValue: Decodable {
    let state: String
    let value, upper, unit, constCode, literal, confidence, reason, sourceCode, min, max: String?
    let upperClosed: Bool?
}
