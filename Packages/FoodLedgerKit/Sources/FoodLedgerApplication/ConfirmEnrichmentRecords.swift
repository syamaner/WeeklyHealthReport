import Foundation
import FoodLedgerDomain

// Where Confirm enrichment evidence is cited and how a saved B value is verified
// (docs/confirm-enrichment-openrouter-v1-phase.md sections 2.4 and 2.4a; CE1.7).

public enum ConfirmEnrichmentCitation {
    /// Whether a candidate cites any item of the three CE1 method versions.
    public static func citesEnrichment(_ candidate: ProviderNeutralCandidate, evidence: [CaptureEvidence]) -> Bool {
        evidence.contains { candidate.evidenceIDs.contains($0.evidenceID) && ConfirmEnrichmentVersions.isEnrichmentEvidence($0) }
    }

    /// The bound candidate's own IDs: its evidence IDs with every estimates v2 leave-out item and every
    /// CE1 item removed, order kept (phase gate section 2.4a).
    public static func ownEvidenceIDs(_ candidate: ProviderNeutralCandidate, evidence: [CaptureEvidence]) -> [EvidenceID] {
        let dropped = Set(evidence.filter { ConfirmEnrichmentVersions.isEnrichmentEvidence($0) || ApprovedEstimateSource.isLeftOut($0) }
            .map(\.evidenceID))
        return candidate.evidenceIDs.filter { !dropped.contains($0) }
    }

    /// The IDs a new log built from a saved decision drops: every CE1 item (as estimates v2 drops
    /// leave-out items).
    public static func enrichmentEvidenceIDs(_ evidence: [CaptureEvidence]) -> Set<EvidenceID> {
        Set(evidence.filter(ConfirmEnrichmentVersions.isEnrichmentEvidence).map(\.evidenceID))
    }

    /// Whether a nutrient set holds any `openrouter_estimate` value (conflict candidates included).
    public static func holdsOpenRouterEstimate(_ nutrients: NutrientSet) -> Bool {
        nutrients.entries.contains { entry in
            ([entry.value] + entry.conflictCandidates).contains { $0.provenance.contains { $0.sourceKind == .openRouterEstimate } }
        }
    }
}

/// CE1.7 verification of the B values one saved resolution version holds (phase gate section 2.4).
/// The same function runs on save and on reopen; a mismatch reads "Evidence not available" and never
/// changes a stored value.
public enum ConfirmEnrichmentVerification {
    public struct Verified: Equatable, Sendable {
        public let capture: ConfirmNutrientCapture
        public let captureEvidence: CaptureEvidence
        public let choices: ConfirmNutrientChoices
        public let values: [NutrientKey: Double]
    }

    public enum Outcome: Equatable, Sendable {
        /// The version holds no `openrouter_estimate` value and cites no B item.
        case none
        case verified(Verified)
        case notAvailable
    }

    /// - Parameters:
    ///   - nutrients: the saved resolution version's nutrients.
    ///   - resolutionVersionID: that version's ID, which its choices item must name.
    ///   - citedEvidenceIDs: the evidence IDs of the version's decision candidate.
    ///   - layer: the values the version's chosen label estimate layer fills, by key (empty without one).
    public static func verify(nutrients: NutrientSet, resolutionVersionID: ResolutionVersionID,
                              citedEvidenceIDs: [EvidenceID], evidence: [CaptureEvidence],
                              layer: [NutrientKey: Double], digester: any Digesting) -> Outcome {
        let cited = evidence.filter { citedEvidenceIDs.contains($0.evidenceID) }
        let captures = cited.filter { $0.captureMethodVersion.value == ConfirmEnrichmentVersions.nutrientCaptureMethodVersion }
        let choiceItems = cited.filter { $0.captureMethodVersion.value == ConfirmEnrichmentVersions.choicesMethodVersion }
        var saved: [NutrientKey: (Double, NutrientProvenance)] = [:]
        var others: [NutrientKey: Double] = [:]
        for entry in nutrients.entries {
            guard case let .augmented(exact) = entry.value,
                  let provenance = exact.provenance.first, provenance.sourceKind == .openRouterEstimate else {
                if case let .measured(exact) = entry.value { others[entry.key] = exact.amount }
                if case let .augmented(exact) = entry.value { others[entry.key] = exact.amount }
                if entry.conflictCandidates.contains(where: { $0.provenance.contains { $0.sourceKind == .openRouterEstimate } }) {
                    return .notAvailable
                }
                continue
            }
            saved[entry.key] = (exact.amount, provenance)
        }
        if saved.isEmpty && captures.isEmpty && choiceItems.isEmpty { return .none }
        guard !saved.isEmpty, captures.count == 1, choiceItems.count == 1,
              let captureEvidence = captures.first, let hash = captureEvidence.byteHash,
              case let .text(payload) = captureEvidence.originalPayload,
              (try? digester.sha256(Data(payload.value.utf8))) == hash,
              let capture = ConfirmEnrichmentEvidence.nutrients(captureEvidence),
              let choicesEvidence = choiceItems.first, let choicesHash = choicesEvidence.byteHash,
              case let .text(choicesPayload) = choicesEvidence.originalPayload,
              (try? digester.sha256(Data(choicesPayload.value.utf8))) == choicesHash,
              let choices = ConfirmEnrichmentEvidence.choices(choicesEvidence),
              choices.resolutionVersionID == resolutionVersionID.rawValue, choices.captureSHA256 == hash.value,
              saved.values.allSatisfy({ $0.1.evidenceID == captureEvidence.evidenceID && $0.1.responseHash == hash
                  && $0.1.capturedAt == captureEvidence.capturedAt }),
              (try? digester.sha256(Data(capture.response.utf8)))?.value == capture.responseSHA256,
              let inputs = ConfirmNutrientRequestInputs.decode(requestBody: capture.requestBody),
              case let .success(parsed) = ConfirmNutrientResponseCheck.check(
                  Data(capture.response.utf8), request: inputs, models: [capture.model], provider: capture.provider),
              ConfirmNutrientResponseCheck.captureRows(parsed, request: inputs) == capture.rows else {
            return .notAvailable
        }
        // The kept rows of the request-and-reply checks, then the merge-time drops.
        var kept: [NutrientKey: Double] = [:]
        for row in capture.rows where row.result == ConfirmNutrientRowResult.kept.rawValue {
            if let key = NutrientKey(rawValue: row.nutrient), let amount = Double(row.value) { kept[key] = amount }
        }
        let layerDropped = Set(kept.keys).intersection(layer.keys)
        guard layerDropped == choices.layerDroppedKeys else { return .notAvailable }
        layerDropped.forEach { kept[$0] = nil }
        let parentDropped = ConfirmNutrientRowCheck.mergeParentDropped(kept: kept, layer: layer)
        guard parentDropped == choices.mergeParentDroppedKeys else { return .notAvailable }
        parentDropped.forEach { kept[$0] = nil }
        var merged = others
        // The layer's values as the save merged them: a bounded fill enters at its bound, as in
        // ConfirmEnrichmentMerge.merge.
        for (key, amount) in layer where merged[key] == nil { merged[key] = amount }
        for (key, amount) in kept { merged[key] = amount }
        let energyDropped = EstimateEnergyCheck.dropped(merged: merged, estimated: Set(kept.keys))
        guard energyDropped == choices.mergeEnergyDroppedKeys else { return .notAvailable }
        energyDropped.forEach { kept[$0] = nil }
        // Each saved B value equals a kept row not left out, and exactly those are saved.
        let leftOut = choices.leftOutKeys
        guard leftOut.isSubset(of: kept.keys),
              Set(saved.keys) == Set(kept.keys).subtracting(leftOut),
              saved.allSatisfy({ kept[$0.key] == $0.value.0 }) else { return .notAvailable }
        return .verified(Verified(capture: capture, captureEvidence: captureEvidence, choices: choices,
                                  values: saved.mapValues(\.0)))
    }
}

extension ConfirmEnrichmentCitation {
    /// `saved` with each `openrouter_estimate` entry replaced by `expected`'s entry for that key, so a
    /// layered entry's layer check compares everything but the B rows, which verification checks
    /// (CE1 section 5a).
    public static func replacingOpenRouterEstimates(_ saved: NutrientSet, from expected: NutrientSet) -> NutrientSet {
        guard holdsOpenRouterEstimate(saved) else { return saved }
        let entries = saved.entries.map { entry -> NutrientEntry in
            guard entry.value.provenance.contains(where: { $0.sourceKind == .openRouterEstimate }) else { return entry }
            return expected.entries.first { $0.key == entry.key } ?? entry
        }
        return (try? NutrientSet(entries: entries)) ?? saved
    }
}
