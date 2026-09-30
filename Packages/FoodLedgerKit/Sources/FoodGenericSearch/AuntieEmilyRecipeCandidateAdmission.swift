import CryptoKit
import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// Reviewed representative recipe only. No arbitrary recipe host or identity promotion.
public struct AuntieEmilyRecipeCandidateAdmission: FoodSourceCandidateAdmitting {
    public static let version = "auntie-emily-recipe-candidate-v1"
    public static let contentHosts: Set<String> = ["auntieemily.com"]
    public init() { }
    public func admit(_ source: FoodReviewedSource, query: FoodSearchRemoteQuery,
                      evidence: CaptureEvidence) throws -> GenericFoodConfirmationRoute? {
        let page = source.page
        let policy = try FoodSourceURLPolicy(allowedHosts: Self.contentHosts)
        guard (try? policy.canonicalURL(page.finalURL)) == page.finalURL,
              URLComponents(url: page.finalURL, resolvingAgainstBaseURL: false)?.path == "/taiwan-night-market-steak/", page.finalURL.query == nil,
              page.requestedURL == source.citation.url, page.retrievedAt.timeIntervalSince1970.isFinite,
              page.sha256 == SHA256.hash(data: page.html).map({ String(format: "%02x", $0) }).joined() else { return nil }
        let profile = try WPRecipeSourceParser.profile(page.html, sourceURL: page.finalURL)
        guard source.recipes == [profile], source.panels.isEmpty else { return nil }
        let parsed = FoodQueryParser.parse(query.foodTerms)
        guard parsed.allowsCandidateDiscovery, parsed.attributes.isEmpty, let food = parsed.food else { return nil }
        let terms = Self.terms(food)
        let nameTerms = Self.terms(profile.name)
        let available = Self.terms(profile.name + " " + profile.ingredients.joined(separator: " "))
        guard terms.contains("steak"), terms.isSubset(of: available), !terms.isDisjoint(with: nameTerms) else { return nil }
        let sourceID = try ExternalIdentifier("auntie-emily-representative-recipe-web")
        let recordID = try ExternalIdentifier(profile.recordID)
        let releaseID = try ExternalIdentifier("auntie-emily:sha256:\(page.sha256):\(Self.version)")
        let release = try SourceRelease(sourceReleaseID: releaseID, sourceID: sourceID, releasedAt: page.retrievedAt,
            artifactHash: SHA256Digest(page.sha256), schemaVersion: LedgerText(FoodSourceRecipeProfile.schema),
            pipelineVersion: LedgerText(Self.version + ":" + WPRecipeSourceParser.version + ":" + FoodSourceRecipeProfile.version),
            licence: LedgerText("Not specified in the captured recipe; no redistribution licence inferred."),
            attribution: LedgerText("Auntie Emily’s Kitchen · representative home recipe · \(page.finalURL.absoluteString)"),
            manifestHash: SHA256Digest(page.sha256))
        let nutrients = try NutrientKey.allCases.map { field -> NutrientEntry in
            guard let d = profile.declarations.first(where: { $0.field == field }) else {
                return try NutrientEntry(key: field, value: .unknown(.notDeclared))
            }
            let reference = "\(page.finalURL.absoluteString);json=\(d.jsonPointer);visible-value-node=\(d.visibleValueNode);visible-unit-node=\(d.visibleUnitNode);basis=\(profile.recipePointer)/nutrition/servingSize;literal=\(d.literal);binding=\(FoodSourceRecipeProfile.version);raw-sha256=\(page.sha256)"
            let provenance = try NutrientProvenance(sourceKind: .recipeReconstruction, sourceID: sourceID,
                sourceReleaseID: releaseID, recordID: recordID, capturedAt: page.retrievedAt,
                responseHash: SHA256Digest(page.sha256), manifestReference: LedgerText(reference))
            return try NutrientEntry(key: field, value: .augmented(ExactNutrientValue(amount: d.value.amount,
                unit: field.canonicalUnit, sourceValue: .exact(d.value), provenance: [provenance])))
        }
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown,
            skin: .unknown, drained: .unknown, packingMedium: .unknown, fortification: .unknown,
            servingBasis: FoodSourceRecipeProfile.basis)
        let sourceQuantity = try EdibleQuantityIdentity.known(PositiveQuantity(value: 1, unit: .count), conversionVersionID: nil)
        let metadata = try CandidateMatchMetadata(methodVersion: LedgerText(Self.version), score: 0.5,
            materialDifferences: [LedgerText("Representative home recipe, not your vendor’s recipe. The source lists: \(profile.ingredients.joined(separator: "; ")). Cut, sauce, oil and portion may differ; cooked serving weight is unknown. Choose this only as an explicit estimate.")], libraryAliases: [])
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: releaseID,
            recordID: recordID, identity: identity, edibleQuantity: sourceQuantity, nutrients: NutrientSet(entries: nutrients),
            evidenceIDs: [evidence.evidenceID], matchMetadata: metadata), name: LedgerText(profile.name),
            variant: LedgerText("Representative recipe · per 1 recipe serving · \(profile.servings.formatted()) servings in source recipe"),
            itemClass: .food, packFacts: PackFacts())
        let input = try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: identity, expectedEdibleQuantity: .unknown)
        return GenericFoodConfirmationRoute(confirmation: input, matches: [.init(candidate: candidate, isExactName: false)])
    }
    private static func terms(_ text: String) -> Set<String> {
        let ignored: Set<String> = ["with", "and", "n", "fried"]
        return Set(GenericFoodSearchTerms.tokens(text).filter { !ignored.contains($0) }.map {
            switch $0 { case "taiwanese": "taiwan"; case "noodles", "noodle": "pasta"; case "eggs": "egg"; default: $0 }
        })
    }
}

/// Composition of existing provider-specific admission contracts.
public struct GroundedFoodSourceCandidateAdmission: FoodSourceCandidateAdmitting {
    public static let contentHosts = ManufacturerSourceCandidateAdmission.contentHosts.union(AuntieEmilyRecipeCandidateAdmission.contentHosts)
    public init() { }
    public func admit(_ source: FoodReviewedSource, query: FoodSearchRemoteQuery,
                      evidence: CaptureEvidence) throws -> GenericFoodConfirmationRoute? {
        if AuntieEmilyRecipeCandidateAdmission.contentHosts.contains(source.page.finalURL.host?.lowercased() ?? "") {
            return try AuntieEmilyRecipeCandidateAdmission().admit(source, query: query, evidence: evidence)
        }
        return try ManufacturerSourceCandidateAdmission().admit(source, query: query, evidence: evidence)
    }
}
