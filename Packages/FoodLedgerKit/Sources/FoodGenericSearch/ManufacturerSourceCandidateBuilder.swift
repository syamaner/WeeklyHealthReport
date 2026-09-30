import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// Builds candidates only after a source-specific adapter proves product/panel correspondence.
/// This preserves source declarations; it cannot infer decisive identity or accept a food.
enum ManufacturerSourceCandidateBuilder {
    static func make(name: String, panel: FoodSourceNutritionPanel,
                                  page: AcquiredFoodSourcePage, evidence: CaptureEvidence, lexicalScore: Double, namespace: String, label: String, version: String, legacyCells: Bool = false) throws -> GenericFoodConfirmationRoute {
        let basis = panel.declarations[0].value.basis
        guard [.per100Grams, .per100Millilitres].contains(basis),
              panel.declarations.allSatisfy({ $0.value.basis == basis }) else { throw FoodSourceBindingError.basisMismatch }
        let volume = basis == .per100Millilitres
        let sourceID = try ExternalIdentifier(namespace + "-uk-manufacturer-web")
        let recordID = try ExternalIdentifier(page.finalURL.absoluteString + "#table-1")
        let releaseID = try ExternalIdentifier("\(namespace):sha256:\(page.sha256):\(version):retrieved:\(page.retrievedAt.timeIntervalSince1970)")
        let release = try SourceRelease(sourceReleaseID: releaseID, sourceID: sourceID, releasedAt: page.retrievedAt,
            artifactHash: SHA256Digest(page.sha256), schemaVersion: LedgerText(legacyCells ? "manufacturer-source-panel-v1" : "manufacturer-source-panel-v2"),
            pipelineVersion: LedgerText(version + ":" + HTMLFoodSourceTableProjector.version + ":" + (legacyCells ? FoodSourceNutritionBinding.version : panel.declarations[0].bindingVersion)),
            licence: LedgerText("Not specified in the captured source; no redistribution licence inferred."),
            attribution: LedgerText("\(label) · \(page.finalURL.absoluteString) · Retrieved \(ISO8601DateFormatter().string(from: page.retrievedAt))"),
            manifestHash: SHA256Digest(panel.source.sha256))
        let nutrients = try NutrientKey.allCases.map { field -> NutrientEntry in
            guard let declared = panel.declarations.first(where: { $0.field == field }) else {
                return try NutrientEntry(key: field, value: .unknown(.notDeclared))
            }
            let c = declared.sourceCell
            let basisReference: String
            if legacyCells {
                guard let b = declared.basisCell else { throw FoodSourceBindingError.wrongPanel }
                basisReference = "\(b.table),\(b.row),\(b.cell),\(b.segment)"
            } else {
                switch declared.basisLocation {
                case let .cell(b): basisReference = "cell:\(b.table),\(b.row),\(b.cell),\(b.segment)"
                case let .inline(b): basisReference = "inline:\(b.table),\(b.row),\(b.cell),\(b.segment)"
                case let .caption(table, index): basisReference = "caption:\(table),\(index)"
                }
            }
            let bindingReference = legacyCells ? "" : ";binding=\(declared.bindingVersion)"
            let pointer = "\(page.finalURL.absoluteString)#table=\(c.table)/row=\(c.row)/cell=\(c.cell)/segment=\(c.segment);basis=\(basisReference)\(bindingReference);literal=\(declared.declaredLiteral);projection-sha256=\(declared.sha256)"
            let provenance = try NutrientProvenance(sourceKind: .exactProductDataset, sourceID: sourceID,
                sourceReleaseID: releaseID, recordID: recordID, capturedAt: page.retrievedAt,
                responseHash: SHA256Digest(page.sha256), manifestReference: LedgerText(pointer))
            return try NutrientEntry(key: field, value: .augmented(ExactNutrientValue(amount: declared.value.amount,
                unit: field.canonicalUnit, sourceValue: .exact(declared.value), provenance: [provenance])))
        }
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown,
            skin: .unknown, drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: basis)
        let quantity = try EdibleQuantityIdentity.known(PositiveQuantity(value: 100, unit: volume ? .millilitres : .grams), conversionVersionID: nil)
        let metadata = try CandidateMatchMetadata(methodVersion: LedgerText(version), score: lexicalScore,
            materialDifferences: [LedgerText("Manufacturer page declaration; confirm the product, preparation and consumed amount. Missing nutrition stays unknown.")], libraryAliases: [])
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: releaseID,
            recordID: recordID, identity: identity, edibleQuantity: quantity, nutrients: NutrientSet(entries: nutrients),
            evidenceIDs: [evidence.evidenceID], matchMetadata: metadata), name: LedgerText(name),
            variant: LedgerText("\(label) · source declaration · per 100 \(volume ? "ml" : "g")"), itemClass: .food, packFacts: PackFacts())
        let input = try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: identity, expectedEdibleQuantity: quantity)
        return GenericFoodConfirmationRoute(confirmation: input, matches: [GenericFoodMatch(candidate: candidate, isExactName: false)])
    }
}
