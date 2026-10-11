import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// Synthetic reviewed web proposals and digest-consistent rewrites for manifest contracts.
enum ReviewedWebFixtures {
    static let query = "tofu pudding"

    /// A review whose successful applicability check suggests `choice` among one or two
    /// literally bound candidates (`c1`, and `c2` when `second` is true).
    static func review(serving: Bool = true, query: String = query, choice: String? = "c1", rankingUnavailable: Bool = false,
                       representativeOnly: Bool = false, second: Bool = false) throws -> (GenericFoodProposalReview, BoundFoodProposal) {
        let text = serving ? "豆花 每份一碗 熱量150大卡 蛋白質6公克" : "豆花 每100g 熱量150大卡 蛋白質6公克"
        let document = try GenericFoodDocumentProjector.project(Data(text.utf8), url: URL(string: "https://example.com/tofu")!,
            mediaType: "text/plain", retrievedAt: LedgerFixtures.date, origin: "synthetic_fixture")
        let ref: [[String: Any]] = [["block_id": "b1", "quote": text]]
        let values: [[String: Any]] = FoodProposalNutrientKey.allCases.map { key in
            let known = key == .energy || key == .protein
            return ["key": key.rawValue, "state": known ? "declared" : "unknown",
                "value": known ? (key == .energy ? "150" : "6") as Any : NSNull(), "unit": known ? key.unit as Any : NSNull(),
                "evidence": known ? ref : [], "unknown_reason": known ? NSNull() : "not_observed" as Any]
        }
        func candidate(_ id: String) -> [String: Any] {
            ["id": id, "document_id": document.id, "name": "豆花", "brand": NSNull(), "preparation": NSNull(),
             "identity_evidence": ref, "panel_evidence": ref,
             "basis": ["amount": serving ? "1" : "100", "unit": serving ? "serving" : "g", "label": serving ? "每份一碗" : "每100g", "evidence": ref],
             "nutrients": values, "limitations": []]
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try JSONSerialization.data(withJSONObject: ["version": FoodProposalExtraction.schemaVersion,
            "candidates": [candidate("c1")] + (second ? [candidate("c2")] : []), "preferred_id": "c1"])
        let validation = try FoodProposalBinding.validate(decoder.decode(FoodProposalExtraction.self, from: data), documents: [document])
        let selection = try choice.map { try FoodProposalSelection(unscoredChoice: $0, validation: validation) }
        let review = GenericFoodProposalReview(foodTerms: query, discovery: nil, documents: [document], validation: validation,
            selection: selection, rankingUnavailable: rankingUnavailable, representativeSourceOnly: representativeOnly)
        return (review, try XCTUnwrap(validation.candidates.first))
    }

    static func manifestText(_ input: PopulatedFoodConfirmation) throws -> String {
        guard case let .text(text) = input.evidence[0].originalPayload else { throw GenericFoodProposalError.invalidDocument }
        return text.value
    }

    /// Replace the retained manifest text and rebind every digest-derived identifier (evidence
    /// hash, release ID and hash, per-nutrient references), so only the semantic checks can reject.
    static func rebind(_ input: PopulatedFoodConfirmation, manifest: String, schemaVersion: String? = nil,
                       pipelineVersion: String? = nil, captureMethodVersion: String? = nil) throws -> PopulatedFoodConfirmation {
        let evidence = input.evidence[0], release = input.sourceReleases[0], candidate = input.candidates[0]
        let hash = try SHA256Digester().sha256(Data(manifest.utf8))
        let releaseID = try ExternalIdentifier("reviewed-web:" + hash.value)
        let newEvidence = try CaptureEvidence(evidenceID: evidence.evidenceID, kind: evidence.kind, capturedAt: evidence.capturedAt,
            locale: evidence.locale, captureMethod: evidence.captureMethod,
            captureMethodVersion: captureMethodVersion.map { try LedgerText($0) } ?? evidence.captureMethodVersion,
            originalPayload: .text(LedgerText(manifest)), byteHash: hash)
        let newRelease = SourceRelease(sourceReleaseID: releaseID, sourceID: release.sourceID, releasedAt: release.releasedAt,
            artifactHash: release.artifactHash, schemaVersion: try schemaVersion.map { try LedgerText($0) } ?? release.schemaVersion,
            pipelineVersion: try pipelineVersion.map { try LedgerText($0) } ?? release.pipelineVersion, licence: release.licence,
            attribution: release.attribution, manifestHash: hash)
        let entries = try candidate.candidate.nutrients.entries.map { entry -> NutrientEntry in
            guard case let .augmented(value) = entry.value else { return entry }
            let provenance = try value.provenance.map { item in
                NutrientProvenance(sourceKind: item.sourceKind, sourceID: item.sourceID, sourceReleaseID: releaseID,
                    recordID: item.recordID, evidenceID: item.evidenceID, capturedAt: item.capturedAt, responseHash: item.responseHash,
                    manifestReference: try item.manifestReference.map { try LedgerText($0.value.replacingOccurrences(of: release.manifestHash.value, with: hash.value)) })
            }
            return try NutrientEntry(key: entry.key, value: .augmented(ExactNutrientValue(amount: value.amount, unit: value.unit,
                sourceValue: value.sourceValue, provenance: provenance)))
        }
        let source = candidate.candidate
        let newCandidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: releaseID,
            recordID: source.recordID, identity: source.identity, edibleQuantity: source.edibleQuantity,
            nutrients: NutrientSet(entries: entries), evidenceIDs: source.evidenceIDs, matchMetadata: source.matchMetadata),
            name: candidate.name, brand: candidate.brand, variant: candidate.variant, itemClass: candidate.itemClass)
        return try PopulatedFoodConfirmation(evidence: [newEvidence], sourceReleases: [newRelease], candidates: [newCandidate],
            expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
    }

    static func rewrite(_ input: PopulatedFoodConfirmation, replacing: String, with replacement: String) throws -> PopulatedFoodConfirmation {
        let text = try manifestText(input)
        XCTAssertTrue(text.contains(replacing), "Fixture must contain \(replacing)")
        return try rebind(input, manifest: text.replacingOccurrences(of: replacing, with: replacement))
    }

    /// Literal v1 fixtures captured from the shipping implementation at 9fc734d.
    static func v1Fixture(_ name: String) throws -> (input: PopulatedFoodConfirmation, manifest: Data) {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/reviewed-web-v1")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let input = try decoder.decode(PopulatedFoodConfirmation.self, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
        return (input, try Data(contentsOf: directory.appendingPathComponent(name + "-manifest.json")))
    }
}
