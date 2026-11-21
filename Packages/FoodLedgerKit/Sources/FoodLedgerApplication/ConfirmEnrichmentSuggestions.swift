import Foundation
import FoodLedgerDomain

// The Confirm suggestion layer (docs/confirm-enrichment-openrouter-v1.md section 5a, CE1.4a, CE1.6 and
// CE1.7a; phase gate sections 2.1 to 2.4a). Suggestions live in one transient value on
// `FoodConfirmationState`, never encoded with it: neither the candidate nor `FoodCorrection` ever holds
// a model value. Captures are built when an answer arrives and committed only with a Log that uses them.

/// A checked A answer, ready to pre-fill.
public struct ConfirmDetailsSuggestion: Equatable, Sendable {
    public let subjectSHA256: String
    /// The `confirm-details-capture-v1` evidence, committed only with a Log that keeps a fact it applied.
    public let capture: CaptureEvidence
    /// The facts pre-filled: not `unknown`, at or above 0.85, and (for Your food database) agreeing
    /// with the entry's state. Empty when the answer pre-fills nothing.
    public let applied: [ConfirmDetailsFact: String]
    public let model: String
    public let receivedAt: Date
    public let fromCache: Bool

    public init(subjectSHA256: String, capture: CaptureEvidence, applied: [ConfirmDetailsFact: String], model: String,
                receivedAt: Date, fromCache: Bool) {
        self.subjectSHA256 = subjectSHA256; self.capture = capture; self.applied = applied; self.model = model
        self.receivedAt = receivedAt; self.fromCache = fromCache
    }
}

/// A checked B answer: the capture rows and the values the request-and-reply checks kept.
public struct ConfirmNutrientSuggestion: Equatable, Sendable {
    public let subjectSHA256: String
    public let capture: CaptureEvidence
    public let inputs: ConfirmNutrientRequestInputs
    public let rows: [ConfirmNutrientCapture.Row]
    public let model: String
    public let receivedAt: Date
    public let fromCache: Bool

    public init(subjectSHA256: String, capture: CaptureEvidence, inputs: ConfirmNutrientRequestInputs,
                rows: [ConfirmNutrientCapture.Row], model: String, receivedAt: Date, fromCache: Bool) {
        self.subjectSHA256 = subjectSHA256; self.capture = capture; self.inputs = inputs; self.rows = rows
        self.model = model; self.receivedAt = receivedAt; self.fromCache = fromCache
    }

    /// The kept rows, by key, as numbers.
    public var kept: [NutrientKey: Double] {
        var result: [NutrientKey: Double] = [:]
        for row in rows where row.result == ConfirmNutrientRowResult.kept.rawValue {
            if let key = NutrientKey(rawValue: row.nutrient), let amount = Double(row.value) { result[key] = amount }
        }
        return result
    }
}

/// The transient layer on Confirm.
public struct ConfirmEnrichmentLayer: Equatable, Sendable {
    /// The A fill. While `folded` is false it is the suggestion line; once the owner applies the sheet
    /// its facts are folded into the correction and it stays only for the A capture's citation rule.
    public var details: ConfirmDetailsSuggestion?
    public var detailsFolded = false
    /// The B rows and which kept rows the owner left out.
    public var nutrients: ConfirmNutrientSuggestion?
    public var leftOut: Set<NutrientKey> = []
    /// Set by reopen only: the saved version's left-out keys, so a change of choices is seen.
    public var seedLeftOut: Set<NutrientKey>?
    /// Reopen found B values whose evidence does not verify ("Evidence not available"): nothing changes.
    public var evidenceNotAvailable = false
    /// B rows were removed because the food details changed on a reopened log (CE1.7a).
    public var removedBecauseDetailsChanged = false
    /// What the chosen label estimate layer fills, by key: set by reopen from the saved layer, and by
    /// the view model whenever the layer choice changes on Confirm, so the merge checks run live.
    public var labelLayer: [NutrientKey: Double] = [:]

    public init() {}

    /// The facts the fill sets while it is shown as a suggestion.
    public var filledFacts: [ConfirmDetailsFact: String] {
        guard let details, !detailsFolded else { return [:] }
        return details.applied
    }

    /// Whether the owner's choices differ from a reopened log's saved ones.
    public var choicesChanged: Bool {
        // A seed exists only when the saved version kept B values: removing the rows is a change too.
        guard let seedLeftOut else { return false }
        return nutrients == nil || leftOut != seedLeftOut
    }
}

/// The merge of kept B rows onto the saved nutrients at save, and live on Confirm whenever the label
/// layer choice changes (CE1 section 5a, CE1.6 rule 3; gate section 2.4).
public enum ConfirmEnrichmentMerge {
    public struct Result: Equatable, Sendable {
        /// The B values the version keeps: kept rows, minus every drop, minus the owner's left-out keys.
        public let saved: [NutrientKey: Double]
        /// Kept rows after every drop, left-out keys included (what Put back can return).
        public let available: [NutrientKey: Double]
        public let layerDropped: Set<NutrientKey>
        public let mergeParentDropped: Set<NutrientKey>
        public let mergeEnergyDropped: Set<NutrientKey>
        public let leftOut: Set<NutrientKey>
    }

    /// `base` is the version's nutrients before B (the candidate's or correction's, with estimates v2's
    /// hidden keys unknown and the label layer merged); `layer` is what the chosen label layer fills.
    public static func merge(kept: [NutrientKey: Double], leftOut: Set<NutrientKey>, base: NutrientSet,
                             layer: [NutrientKey: Double]) -> Result {
        var remaining = kept
        let layerDropped = Set(kept.keys).intersection(layer.keys)
        layerDropped.forEach { remaining[$0] = nil }
        let parentDropped = ConfirmNutrientRowCheck.mergeParentDropped(kept: remaining, layer: layer)
        parentDropped.forEach { remaining[$0] = nil }
        var merged: [NutrientKey: Double] = [:]
        for entry in base.entries {
            guard !entry.value.provenance.contains(where: { $0.sourceKind == .openRouterEstimate }) else { continue }
            if case let .measured(exact) = entry.value { merged[entry.key] = exact.amount }
            if case let .augmented(exact) = entry.value { merged[entry.key] = exact.amount }
        }
        for (key, amount) in remaining { merged[key] = amount }
        let energyDropped = EstimateEnergyCheck.dropped(merged: merged, estimated: Set(remaining.keys))
        energyDropped.forEach { remaining[$0] = nil }
        let left = leftOut.intersection(remaining.keys)
        return Result(saved: remaining.filter { !left.contains($0.key) }, available: remaining, layerDropped: layerDropped,
                      mergeParentDropped: parentDropped, mergeEnergyDropped: energyDropped, leftOut: left)
    }

    /// The label layer's values in a saved version: values from the layer's own release.
    public static func layerValues(_ saved: StoredFoodConfirmation) -> [NutrientKey: Double] {
        guard let release = saved.estimate?.sourceRelease.sourceReleaseID else { return [:] }
        return values(saved.resolutionVersion.nutrients, release: release)
    }

    /// What a chosen label layer fills on this Confirm, merged as save merges it.
    public static func layerValues(_ choice: LabelEstimateChoice, state: FoodConfirmationState) -> [NutrientKey: Double] {
        guard let merged = try? LabelEstimateLayer.merged(label: state.selectedCandidate, generic: choice.generic.candidate,
                                                          release: choice.sourceRelease, cocoaPercent: choice.cocoaPercent) else { return [:] }
        return values(merged, release: choice.sourceRelease.sourceReleaseID)
    }

    static func values(_ nutrients: NutrientSet, release: ExternalIdentifier) -> [NutrientKey: Double] {
        var result: [NutrientKey: Double] = [:]
        for entry in nutrients.entries {
            guard entry.value.provenance.contains(where: { $0.sourceReleaseID == release }) else { continue }
            if case let .augmented(exact) = entry.value { result[entry.key] = exact.amount }
            if case let .measured(exact) = entry.value { result[entry.key] = exact.amount }
        }
        return result
    }
}

/// The evidence, release and values of Confirm enrichment (gate sections 2.1 to 2.4). Every payload is
/// canonical JSON, hashed through `Digesting`.
public enum ConfirmEnrichmentCaptureBuilder {
    static func evidence(_ payload: Data, id: EvidenceID, capturedAt: Date, locale: LedgerText, method: String,
                         version: String, digester: any Digesting) throws -> CaptureEvidence {
        try CaptureEvidence(evidenceID: id, kind: .labelText, capturedAt: capturedAt, locale: locale,
                            captureMethod: LedgerText(method), captureMethodVersion: LedgerText(version),
                            originalPayload: .text(LedgerText(String(decoding: payload, as: UTF8.self))),
                            byteHash: digester.sha256(payload))
    }

    /// The locale of a capture: that of the first of the bound candidate's own evidence IDs, or `en_GB`.
    public static func locale(_ candidate: ProviderNeutralCandidate, evidence: [CaptureEvidence]) -> LedgerText {
        let own = ConfirmEnrichmentCitation.ownEvidenceIDs(candidate, evidence: evidence)
        for id in own { if let item = evidence.first(where: { $0.evidenceID == id }) { return item.locale } }
        return (try? LedgerText("en_GB"))!
    }

    public static func details(request: ConfirmEnrichmentPolicy.DetailsRequest, route: ConfirmEnrichmentRoute, response: Data,
                               parsed: ConfirmDetailsResponseCheck.Parsed, applied: [String], model: String, receivedAt: Date,
                               locale: LedgerText, id: EvidenceID, encoder: any CanonicalEncoding,
                               digester: any Digesting) throws -> CaptureEvidence {
        let capture = try ConfirmDetailsCapture(
            model: model, provider: route.provider, endpoint: route.endpoint, generationID: parsed.usage.generationID,
            requestBody: String(decoding: request.body, as: UTF8.self), response: String(decoding: response, as: UTF8.self),
            responseSHA256: try digester.sha256(response).value, answers: parsed.answers, applied: applied)
        return try evidence(encoder.encode(capture), id: id, capturedAt: ConfirmEnrichmentTime.truncated(receivedAt), locale: locale,
                            method: ConfirmEnrichmentVersions.detailsCaptureMethod,
                            version: ConfirmEnrichmentVersions.detailsCaptureMethodVersion, digester: digester)
    }

    public static func nutrients(request: ConfirmEnrichmentPolicy.NutrientRequest, route: ConfirmEnrichmentRoute, response: Data,
                                 rows: [ConfirmNutrientCapture.Row], generationID: String?, model: String, receivedAt: Date,
                                 locale: LedgerText, id: EvidenceID, encoder: any CanonicalEncoding,
                                 digester: any Digesting) throws -> CaptureEvidence {
        let capture = try ConfirmNutrientCapture(
            model: model, provider: route.provider, endpoint: route.endpoint, generationID: generationID,
            requestBody: String(decoding: request.body, as: UTF8.self), response: String(decoding: response, as: UTF8.self),
            responseSHA256: try digester.sha256(response).value, rows: rows)
        return try evidence(encoder.encode(capture), id: id, capturedAt: ConfirmEnrichmentTime.truncated(receivedAt), locale: locale,
                            method: ConfirmEnrichmentVersions.nutrientCaptureMethod,
                            version: ConfirmEnrichmentVersions.nutrientCaptureMethodVersion, digester: digester)
    }

    /// The choices item of one saved version, at the time of the save.
    public static func choices(capture: CaptureEvidence, resolutionVersionID: ResolutionVersionID, merge: ConfirmEnrichmentMerge.Result,
                               capturedAt: Date, id: EvidenceID, encoder: any CanonicalEncoding,
                               digester: any Digesting) throws -> CaptureEvidence {
        guard let hash = capture.byteHash else { throw FoodConfirmationSaveError.invalidOpenRouterEstimate }
        let item = ConfirmNutrientChoices(resolutionVersionID: resolutionVersionID.rawValue, captureSHA256: hash.value,
                                          leftOut: merge.leftOut, layerDropped: merge.layerDropped,
                                          mergeParentDropped: merge.mergeParentDropped, mergeEnergyDropped: merge.mergeEnergyDropped)
        return try evidence(encoder.encode(item), id: id, capturedAt: capturedAt, locale: capture.locale,
                            method: ConfirmEnrichmentVersions.choicesCaptureMethod,
                            version: ConfirmEnrichmentVersions.choicesMethodVersion, digester: digester)
    }

    /// The per-capture source release (gate section 2.1).
    public static func release(_ capture: CaptureEvidence) throws -> SourceRelease {
        guard let hash = capture.byteHash else { throw FoodConfirmationSaveError.invalidOpenRouterEstimate }
        return SourceRelease(
            sourceReleaseID: try ExternalIdentifier(OpenRouterEstimateProvenance.sourceReleaseID(captureHash: hash)),
            sourceID: try ExternalIdentifier(OpenRouterEstimateProvenance.sourceID), releasedAt: capture.capturedAt,
            artifactHash: hash, schemaVersion: try LedgerText(ConfirmEnrichmentVersions.nutrientCaptureMethodVersion),
            pipelineVersion: try LedgerText(ConfirmEnrichmentVersions.nutrientRoute),
            licence: try LedgerText(ConfirmEnrichmentVersions.releaseLicence),
            attribution: try LedgerText(ConfirmEnrichmentVersions.releaseAttribution), manifestHash: hash)
    }

    /// One B value with the pinned provenance of section 2.1.
    public static func value(_ amount: Double, key: NutrientKey, basis: ResolutionBasis, capture: CaptureEvidence) throws -> NutrientValue {
        guard let hash = capture.byteHash else { throw FoodConfirmationSaveError.invalidOpenRouterEstimate }
        let provenance = NutrientProvenance(
            sourceKind: .openRouterEstimate, sourceID: try ExternalIdentifier(OpenRouterEstimateProvenance.sourceID),
            sourceReleaseID: try ExternalIdentifier(OpenRouterEstimateProvenance.sourceReleaseID(captureHash: hash)),
            recordID: try ExternalIdentifier(OpenRouterEstimateProvenance.recordID(evidenceID: capture.evidenceID)),
            evidenceID: capture.evidenceID, capturedAt: capture.capturedAt, responseHash: hash,
            manifestReference: try LedgerText(OpenRouterEstimateProvenance.manifestReference(key)))
        return .augmented(try ExactNutrientValue(
            amount: amount, unit: key.canonicalUnit,
            sourceValue: .exact(try SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: basis)),
            provenance: [provenance]))
    }
}

/// Your foods rows never carry B values (CE1 section 2): each saved `openrouter_estimate` key becomes
/// unknown (`not_declared`), so the row is classified by its real source.
public enum OpenRouterEstimateCarry {
    public static func sourceNutrients(_ nutrients: NutrientSet) -> NutrientSet {
        guard ConfirmEnrichmentCitation.holdsOpenRouterEstimate(nutrients) else { return nutrients }
        let entries = nutrients.entries.map { entry -> NutrientEntry in
            let estimated = ([entry.value] + entry.conflictCandidates).contains { $0.provenance.contains { $0.sourceKind == .openRouterEstimate } }
            return estimated ? ((try? NutrientEntry(key: entry.key, value: .unknown(.notDeclared))) ?? entry) : entry
        }
        return (try? NutrientSet(entries: entries)) ?? nutrients
    }

    /// CE1.7a: the saved nutrients equal the source candidate's except at keys where the saved value
    /// holds `openrouter_estimate` provenance and the source holds an eligible unknown. Checked beside,
    /// not inside, `ApprovedEstimateSource.matchesExceptHiddenEstimates`.
    public static func matchesExceptOpenRouterEstimates(_ saved: NutrientSet, candidate: ProviderNeutralCandidate) -> Bool {
        guard ConfirmEnrichmentCitation.holdsOpenRouterEstimate(saved), saved.entries.count == candidate.nutrients.entries.count else {
            return false
        }
        return zip(saved.entries, candidate.nutrients.entries).allSatisfy { stored, offered in
            guard stored.key == offered.key else { return false }
            if stored == offered { return true }
            return stored.value.provenance.contains { $0.sourceKind == .openRouterEstimate }
                && ConfirmEnrichmentPolicy.isEligibleUnknown(offered)
        }
    }
}

/// The persisted texts of a B choices save on a reopened log (gate section 2.4a): data, not UI copy.
public enum OpenRouterEstimateChoicesText {
    public static let reason = "Changed kept or left-out OpenRouter estimates under \(ConfirmEnrichmentVersions.choicesMethodVersion)"
    public static let editReason = "OpenRouter estimates left out or restored"

    public static func claim(_ keys: Set<NutrientKey>) -> String { "Kept OpenRouter estimates; left out: \(ApprovedEstimateLeaveOutText.keys(keys))" }
}

extension FoodConfirmationState {
    /// The effective identity (CE1.4a): the correction, else the reopened saved product, else the
    /// candidate with the suggested facts applied.
    public var enrichedIdentity: DecisiveIdentity {
        if let correction { return correction.identity }
        if let reopened { return reopened.productVersion.identity }
        let facts = enrichment.filledFacts
        let candidate = selectedCandidate.candidate.identity
        guard !facts.isEmpty else { return candidate }
        return (try? ConfirmEnrichmentPolicy.applying(facts, to: candidate)) ?? candidate
    }

    /// The facts the fill sets, as contradictions.
    var enrichmentFilledFacets: Set<IdentityContradiction> {
        Set(enrichment.filledFacts.keys.map(ConfirmEnrichmentPolicy.contradiction))
    }

    /// The B merge for this state (no label layer is known to the state; callers that hold one pass it).
    public func enrichmentMerge(layer: [NutrientKey: Double]? = nil, base: NutrientSet? = nil) -> ConfirmEnrichmentMerge.Result? {
        guard let nutrients = enrichment.nutrients else { return nil }
        let kept = nutrients.kept.filter { key, _ in
            selectedCandidate.candidate.nutrients.entries.first { $0.key == key }.map(ConfirmEnrichmentPolicy.isEligibleUnknown) ?? false
        }
        return ConfirmEnrichmentMerge.merge(kept: kept, leftOut: enrichment.leftOut, base: base ?? enrichmentBase,
                                            layer: layer ?? enrichment.labelLayer)
    }

    /// The nutrients B is merged onto: the effective nutrients with every earlier B value returned to the
    /// candidate's own entry (a reopened version already holds them).
    var enrichmentBase: NutrientSet { enrichmentBase(of: effectiveNutrients) }

    func enrichmentBase(of effective: NutrientSet) -> NutrientSet {
        // Evidence that does not verify changes no stored value: the saved B values stay as they are,
        // and a save that would write them again is refused by verification.
        guard !enrichment.evidenceNotAvailable, ConfirmEnrichmentCitation.holdsOpenRouterEstimate(effective) else { return effective }
        let source = selectedCandidate.candidate.nutrients
        let entries = effective.entries.map { entry -> NutrientEntry in
            guard entry.value.provenance.contains(where: { $0.sourceKind == .openRouterEstimate }) else { return entry }
            return source.entries.first { $0.key == entry.key } ?? entry
        }
        return (try? NutrientSet(entries: entries)) ?? effective
    }

    /// The nutrients Confirm shows and totals: the source display set with the kept B rows (not left
    /// out) in their place. Without a B answer it is exactly `sourceDisplayNutrients`.
    public var displayNutrients: NutrientSet {
        // A reopened, uncorrected version that holds B values shows them as saved, also when their
        // evidence does not verify ("Evidence not available" changes nothing, values included).
        var shown = sourceDisplayNutrients
        if let reopened, correction == nil, estimateKeys.isEmpty,
           ConfirmEnrichmentCitation.holdsOpenRouterEstimate(reopened.resolutionVersion.nutrients) {
            shown = reopened.resolutionVersion.nutrients
            if enrichment.evidenceNotAvailable { return shown }
        }
        guard enrichment.nutrients != nil || ConfirmEnrichmentCitation.holdsOpenRouterEstimate(shown) else { return shown }
        guard let merge = enrichmentMerge(), let capture = enrichment.nutrients?.capture else {
            // Rows cleared on a reopened log: earlier B values return to the candidate's entries.
            return enrichmentBase(of: shown)
        }
        let entries = shown.entries.map { entry -> NutrientEntry in
            if entry.value.provenance.contains(where: { $0.sourceKind == .openRouterEstimate }), merge.saved[entry.key] == nil {
                return selectedCandidate.candidate.nutrients.entries.first { $0.key == entry.key } ?? entry
            }
            guard let amount = merge.saved[entry.key],
                  let value = try? ConfirmEnrichmentCaptureBuilder.value(amount, key: entry.key, basis: selectedCandidate.candidate.identity.servingBasis,
                                                                          capture: capture),
                  let rebuilt = try? NutrientEntry(key: entry.key, value: value) else { return entry }
            return rebuilt
        }
        return (try? NutrientSet(entries: entries)) ?? shown
    }

    /// CE1.6 rule 7: at least one B value would be saved and no value from any other source is known.
    public var onlyEstimatedByOpenRouter: Bool {
        guard let merge = enrichmentMerge(), !merge.saved.isEmpty else { return false }
        return !enrichmentBase.entries.contains { entry in
            switch entry.value {
            case .measured, .augmented, .bounded: true
            case .unknown: false
            }
        }
    }
}

/// The reducer's Confirm enrichment rules, kept beside the layer they change.
enum ConfirmEnrichmentReduction {
    /// A pre-fills only on a new, uncorrected Confirm with nothing decided or pending, and only facts
    /// the candidate leaves unknown (CE1.1 rule 1, CE1.4).
    static func applyDetails(_ suggestion: ConfirmDetailsSuggestion, to state: inout FoodConfirmationState) {
        let identity = state.selectedCandidate.candidate.identity
        guard state.reopened == nil, state.correction == nil, state.decisions.isEmpty,
              suggestion.capture.captureMethodVersion.value == ConfirmEnrichmentVersions.detailsCaptureMethodVersion,
              !suggestion.applied.isEmpty,
              suggestion.applied.allSatisfy({ ConfirmEnrichmentPolicy.isUnknown($0.key, in: identity) && $0.value != "unknown" }),
              suggestion.applied[.fortification].map({ $0 == "unfortified" }) ?? true else { return }
        let previous = state.enrichment.details
        state.enrichment.details = nil
        guard FoodLogPolicy.pendingDifferences(state).isEmpty else {
            state.enrichment.details = previous
            return
        }
        state.enrichment.details = suggestion
        state.enrichment.detailsFolded = false
        state.phase = .editing
    }

    /// A correction applied on Confirm: B rows stay only while B's subject is unchanged (CE1.6 rule 6,
    /// CE1.7a), and a shown fill is folded into the correction, keeping the Jev reason when every
    /// saved fact equals the suggestion (CE1.4a).
    static func folding(_ correction: FoodCorrection, suggested: DecisiveIdentity,
                        into state: inout FoodConfirmationState) -> FoodCorrection {
        if let rows = state.enrichment.nutrients {
            let unchanged = ConfirmEnrichmentPolicy.knownDetails(correction.identity) == rows.inputs.identity
                && ConfirmEnrichmentPolicy.basis(correction.identity.servingBasis) == rows.inputs.basis
                && correction.nutrients == state.selectedCandidate.candidate.nutrients
            if !unchanged {
                state.enrichment.nutrients = nil
                state.enrichment.leftOut = []
                if state.reopened != nil { state.enrichment.removedBecauseDetailsChanged = true }
            }
        }
        guard state.enrichment.details != nil, !state.enrichment.detailsFolded else { return correction }
        state.enrichment.detailsFolded = true
        guard correction.identity == suggested, correction.reason.value == FoodDetailsFillPolicy.filledReason,
              let reason = try? LedgerText(FoodDetailsFillPolicy.suggestedByJevReason) else { return correction }
        return FoodCorrection(name: correction.name, brand: correction.brand, variant: correction.variant, identity: correction.identity,
                              itemClass: correction.itemClass, nutrients: correction.nutrients, reason: reason)
    }
}

extension FoodConfirmationState {
    /// The keys of B rows Confirm offers Leave out or Put back for: kept after every drop.
    public var openRouterEstimateRows: [NutrientKey: Double] { enrichmentMerge()?.available ?? [:] }
}
