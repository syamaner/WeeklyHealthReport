import Foundation
import FoodLedgerDomain

public protocol FoodConfirmationReading: Sendable {
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease?
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation?
    /// The aggregate of one immutable log item version (a favourite's pinned binding). Nil when
    /// the version does not exist or is a removal.
    func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation?
    /// A stored evidence member, for the retained-evidence existence check (Q11).
    func evidence(id: EvidenceID) throws -> CaptureEvidence?
}

public enum FoodConfirmationDecision: Codable, Equatable, Sendable {
    case undecided
    case accepted
    case declined
}

public struct FoodCorrection: Codable, Equatable, Sendable {
    public let name: LedgerText
    public let brand: LedgerText?
    public let variant: LedgerText?
    public let identity: DecisiveIdentity
    public let itemClass: ItemClass?
    public let nutrients: NutrientSet
    public let reason: LedgerText

    public init(
        name: LedgerText,
        brand: LedgerText?,
        variant: LedgerText?,
        identity: DecisiveIdentity,
        itemClass: ItemClass? = nil,
        nutrients: NutrientSet,
        reason: LedgerText
    ) {
        self.name = name
        self.brand = brand
        self.variant = variant
        self.identity = identity
        self.itemClass = itemClass
        self.nutrients = nutrients
        self.reason = reason
    }
}

public struct QuantityConversionDraft: Codable, Equatable, Sendable {
    public let convertedQuantity: PositiveQuantity
    public let methodVersion: LedgerText
    public let sourceReleaseID: ExternalIdentifier?
    public let evidenceID: EvidenceID?

    public init(
        convertedQuantity: PositiveQuantity,
        methodVersion: LedgerText,
        sourceReleaseID: ExternalIdentifier? = nil,
        evidenceID: EvidenceID? = nil
    ) {
        self.convertedQuantity = convertedQuantity
        self.methodVersion = methodVersion
        self.sourceReleaseID = sourceReleaseID
        self.evidenceID = evidenceID
    }
}

public enum PlateWeightChoice: Codable, Equatable, Sendable {
    case foodOnly
    case missing
    case saved(PlateWeightVersion)
    case new(emptyWeight: PositiveQuantity, superseding: PlateWeightVersion?)
}

public struct DirectWeightDraft: Codable, Equatable, Sendable {
    public var totalGrams: Double?
    public var basis: UserWeightBasis?
    public var needsReconfirmation: Bool
    public init(totalGrams: Double? = nil, basis: UserWeightBasis? = nil, needsReconfirmation: Bool = false) {
        self.totalGrams = totalGrams; self.basis = basis; self.needsReconfirmation = needsReconfirmation
    }
}

public struct FoodQuantityDraft: Codable, Equatable, Sendable {
    public var value: Double?
    public var unit: QuantityUnit
    public var conversion: QuantityConversionDraft?
    public var plateChoice: PlateWeightChoice
    public var directWeight: DirectWeightDraft?
    public var invalidOriginalAmountText: Bool?
    /// The selected count portion guide size (count-portion-estimate-v1). Only the code: grams
    /// come from the frozen table for preview and from the service's own port at save.
    public var portionGuideCode: LedgerText?

    public init(
        value: Double? = nil,
        unit: QuantityUnit = .grams,
        conversion: QuantityConversionDraft? = nil,
        plateChoice: PlateWeightChoice = .foodOnly,
        directWeight: DirectWeightDraft? = nil
    ) {
        self.value = value
        self.unit = unit
        self.conversion = conversion
        self.plateChoice = plateChoice
        self.directWeight = directWeight
    }
}

public enum FoodConfirmationPhase: Codable, Equatable, Sendable {
    case editing
    case saving
    case saveFailed(message: String)
    case saved(logItemID: LogItemID)
}

public struct StoredFoodConfirmation: Codable, Equatable, Sendable {
    public let evidence: [CaptureEvidence]
    public let sourceReleases: [SourceRelease]
    public let product: Product
    public let productVersion: ProductVersion
    public let resolution: NutritionResolution
    public let resolutionVersion: NutritionResolutionVersion
    public let logItem: LogItem
    public let logItemVersion: LogItemVersion
    public let quantityConversion: QuantityConversionVersion?
    public let plate: Plate?
    public let plateWeightVersion: PlateWeightVersion?
    public let candidateDecision: CandidateDecision
    public let assertions: [UserAssertion]
    /// The estimate layer of a label or Open Food Facts entry (label-estimate-merge-v1,
    /// off-label-estimate-v1): assembled by the reader from
    /// the resolution's second decision, never stored on its own. `evidence` and `sourceReleases`
    /// stay the label's.
    public let estimate: StoredLabelEstimate?

    public init(
        evidence: [CaptureEvidence],
        sourceReleases: [SourceRelease],
        product: Product,
        productVersion: ProductVersion,
        resolution: NutritionResolution,
        resolutionVersion: NutritionResolutionVersion,
        logItem: LogItem,
        logItemVersion: LogItemVersion,
        quantityConversion: QuantityConversionVersion?,
        plate: Plate?,
        plateWeightVersion: PlateWeightVersion?,
        candidateDecision: CandidateDecision,
        assertions: [UserAssertion],
        estimate: StoredLabelEstimate? = nil
    ) {
        self.evidence = evidence
        self.sourceReleases = sourceReleases
        self.product = product
        self.productVersion = productVersion
        self.resolution = resolution
        self.resolutionVersion = resolutionVersion
        self.logItem = logItem
        self.logItemVersion = logItemVersion
        self.quantityConversion = quantityConversion
        self.plate = plate
        self.plateWeightVersion = plateWeightVersion
        self.candidateDecision = candidateDecision
        self.assertions = assertions
        self.estimate = estimate
    }
}

public struct FoodConfirmationState: Codable, Equatable, Sendable {
    public internal(set) var input: PopulatedFoodConfirmation
    public var selectedCandidateIndex: Int
    public var decision: FoodConfirmationDecision
    public var correction: FoodCorrection?
    public var quantity: FoodQuantityDraft
    public var phase: FoodConfirmationPhase
    public let reopened: StoredFoodConfirmation?
    /// Inline answers to material differences (food_confirmation_v5). Cleared whenever the
    /// selected candidate or the corrected identity changes.
    public var decisions: [IdentityContradiction: FoodLogDecisionChoice]
    /// Explicit occurrence time. Nil on a new entry means "Now", resolved at commit.
    public var occurredAt: Date?
    /// Pasted label Confirm v1 (#306) C4: set only through the presentation entry point for an
    /// editable pasted-label source (a new reading). Transient: never encoded, decodes as false.
    public var answersLabelFortification = false
    /// Where the current correction came from, for Confirm's wording only (#470): the one tap or
    /// details carried from the last entry. Never stored with the entry; any other correction
    /// clears it.
    public var correctionOrigin: FoodCorrectionOrigin?
    /// Approved estimates the owner left out of this log (estimates on catalogue v2 section 5): the
    /// nutrient is unknown for this log. Confirm state of its own, outside `FoodCorrection`. Like the
    /// three members below it is never encoded and decodes as empty, so a state saved before this
    /// change decodes as it did and an unbound state withholds every composition estimate.
    public var leftOutEstimates: Set<NutrientKey> = []
    /// The decisive identity of each record an estimate cites, as `FoodConfirmationService.bindEstimates`
    /// read it. A record that is absent reads as unreadable.
    public var estimateRecords: [ApprovedEstimateRecordKey: ApprovedEstimateRecordState] = [:]
    /// The verified capture manifests of the input's candidates, by evidence ID.
    public var estimateManifests: [EvidenceID: ApprovedEstimateCaptureManifest] = [:]
    /// Set by `reopen` only: the saved leave-out keys and whether the estimate evidence verifies.
    public var estimateSeed = ApprovedEstimateSeed()
    /// Confirm enrichment's suggestion layer (CE1 section 5a): transient, never encoded, decodes empty.
    public var enrichment = ConfirmEnrichmentLayer()

    private enum CodingKeys: String, CodingKey {
        case input, selectedCandidateIndex, decision, correction, quantity, phase, reopened, decisions, occurredAt
    }

    public init(input: PopulatedFoodConfirmation, reopened: StoredFoodConfirmation? = nil,
                queryQuantity: ParsedFoodQuery.Quantity? = nil, prefillSourceQuantity: Bool = true) {
        self.input = input
        selectedCandidateIndex = 0
        decision = .undecided
        correction = nil
        decisions = [:]
        occurredAt = reopened?.logItemVersion.occurredAt
        if let reopened {
            if let declaration = reopened.logItemVersion.weightDeclaration {
                quantity = FoodQuantityDraft(value: declaration.originalInput?.value,
                    unit: declaration.originalInput?.unit ?? .grams,
                    plateChoice: reopened.plateWeightVersion.map(PlateWeightChoice.saved) ?? .foodOnly,
                    directWeight: DirectWeightDraft(totalGrams: declaration.total.value, basis: declaration.basis))
            } else if let conversion = reopened.quantityConversion, CountPortionGuideCode.isGuideCode(conversion.methodVersion) {
                // A saved guide size reopens selected; the state holds only its code (gate F4).
                quantity = FoodQuantityDraft(value: conversion.sourceQuantity.value, unit: conversion.sourceQuantity.unit,
                    plateChoice: reopened.plateWeightVersion.map(PlateWeightChoice.saved) ?? .foodOnly)
                quantity.portionGuideCode = conversion.methodVersion
            } else if let conversion = reopened.quantityConversion {
                quantity = FoodQuantityDraft(
                    value: conversion.sourceQuantity.value,
                    unit: conversion.sourceQuantity.unit,
                    conversion: QuantityConversionDraft(
                        convertedQuantity: conversion.convertedQuantity,
                        methodVersion: conversion.methodVersion,
                        sourceReleaseID: conversion.sourceReleaseID,
                        evidenceID: conversion.evidenceID
                    ),
                    plateChoice: reopened.plateWeightVersion.map(PlateWeightChoice.saved) ?? .foodOnly
                )
            } else if let plate = reopened.plateWeightVersion {
                quantity = FoodQuantityDraft(
                    value: reopened.logItemVersion.edibleQuantity.value + plate.emptyWeight.value,
                    unit: .grams,
                    plateChoice: .saved(plate)
                )
            } else {
                quantity = FoodQuantityDraft(
                    value: reopened.logItemVersion.edibleQuantity.value,
                    unit: reopened.logItemVersion.edibleQuantity.unit
                )
            }
        } else if prefillSourceQuantity, case let .known(value, _) = input.expectedEdibleQuantity {
            quantity = FoodQuantityDraft(value: value.value, unit: value.unit)
        } else {
            quantity = FoodQuantityDraft()
        }
        if reopened == nil, FoodReviewedWebProposalPolicy.scope(input, candidate: input.candidates[0]) != nil {
            switch input.candidates[0].candidate.identity.servingBasis {
            case .per100Millilitres: quantity = FoodQuantityDraft(unit: .millilitres)
            case let .named(_, sourceQuantity) where sourceQuantity.unit == .millilitres:
                quantity = FoodQuantityDraft(unit: .millilitres)
            default: break
            }
        }
        // A pasted label per 100 ml opens on millilitres, its basis unit (#93). One scope
        // predicate, panel admission (pasted label Confirm v1, C6a).
        let pastedLabel = PastedLabelFortificationPolicy.isPastedLabel(input, candidate: input.candidates[0])
        if reopened == nil, pastedLabel, input.candidates[0].candidate.identity.servingBasis == .per100Millilitres,
           quantity.value == nil {
            quantity = FoodQuantityDraft(unit: .millilitres)
        }
        // Pasted label Confirm v1 (#306) C8: servings by default when the label states a serving.
        // Only the unit; the amount stays empty.
        if reopened == nil, pastedLabel, quantity.value == nil, quantity.directWeight == nil,
           LabelServingPolicy.serving(input, candidate: input.candidates[0]) != nil {
            quantity = FoodQuantityDraft(unit: .count)
        }
        if reopened == nil, FoodSourceServingPolicy.applies(input, candidate: input.candidates[0])
            || LabelServingPolicy.servingsOnly(input, candidate: input.candidates[0]) {
            quantity = FoodQuantityDraft(unit: .count)
        }
        // A parsed exact amount is consumed quantity, distinct from the source's 100-unit basis.
        // No conversion or portion weight is inferred here; count/cross-basis saving stays explicit.
        if reopened == nil, !FoodSourceServingPolicy.applies(input, candidate: input.candidates[0]),
           let queryQuantity, queryQuantity.value.isFinite, queryQuantity.value > 0,
           let unit = QuantityUnit(rawValue: queryQuantity.unit == "ml" ? "mL" : queryQuantity.unit) {
            quantity = FoodQuantityDraft(value: queryQuantity.value, unit: unit)
        }
        phase = .editing
        self.reopened = reopened
    }

    public var selectedCandidate: PopulatedFoodCandidate {
        input.candidates[selectedCandidateIndex]
    }

    public var isGenericEstimate: Bool {
        FoodConfirmationPolicy.isGenericEstimate(input, candidate: selectedCandidate)
    }

    public var unresolvedIdentity: [IdentityContradiction] {
        // The effective identity (CE1.4a): a Confirm suggestion layer's fill can satisfy missing details.
        let missing = FoodConfirmationPolicy.unresolvedIdentity(enrichedIdentity, allowingEstimate: isGenericEstimate)
        // Pasted label Confirm v1 (#306) C4: on an editable pasted label, or a reopened entry that
        // recorded Not stated, unknown fortification is an inline decision, not missing identity.
        guard PastedLabelFortificationPolicy.applies(self) else { return missing }
        return missing.filter { $0 != .fortification }
    }

    public var materialDifferences: [IdentityContradiction] {
        let differences = IdentityCompatibility.contradictions(
            between: input.expectedIdentity,
            and: selectedCandidate.candidate.identity,
            expectedEdibleQuantity: input.expectedEdibleQuantity,
            candidateEdibleQuantity: selectedCandidate.candidate.edibleQuantity
        )
        guard isGenericEstimate else { return differences }
        let expected = input.expectedIdentity, candidate = selectedCandidate.candidate.identity
        var filtered = differences.filter {
            switch $0 {
            case .preparation: expected.preparation != candidate.preparation
            case .bone: expected.bone != candidate.bone
            case .skin: expected.skin != candidate.skin
            case .drained: expected.drained != candidate.drained
            case .packingMedium: expected.packingMedium != candidate.packingMedium
            case .fortification: expected.fortification != candidate.fortification
            case .servingBasis: expected.servingBasis != candidate.servingBasis
            case .edibleQuantity: input.expectedEdibleQuantity != selectedCandidate.candidate.edibleQuantity
            }
        }
        if usesSourceDeclaredServing && reopened == nil && !filtered.contains(.edibleQuantity) { filtered.append(.edibleQuantity) }
        return filtered
    }
}

public enum FoodConfirmationAction: Sendable {
    case selectCandidate(Int)
    case accept
    case decideDifference(IdentityContradiction, FoodLogDecisionChoice?)
    case setOccurredAt(Date?)
    case confirmRetainedWeight
    case decline
    case applyCorrection(FoodCorrection)
    case beginDirectWeight
    case endDirectWeight
    case setDirectWeight(Double?)
    case setWeightBasis(UserWeightBasis?)
    case setQuantityText(String)
    case setQuantity(Double?, QuantityUnit)
    /// The unit picker (owner decision B2, 13 Oct 2026): changing between count, g and mL clears
    /// the amount, so `amountMissing` blocks Log until an amount is entered in the new unit.
    case setQuantityUnit(QuantityUnit)
    case setConversion(QuantityConversionDraft?)
    /// Selects a count portion guide size by its code, or clears it (count-portion-estimate-v1).
    case setPortionGuide(LedgerText?)
    case setPlateChoice(PlateWeightChoice)
    /// Leaves one approved estimate out of this log, or undoes that (contract section 5, decision
    /// P6). There is no action that types a value for an estimated nutrient.
    case leaveOutEstimate(NutrientKey)
    case restoreEstimate(NutrientKey)
    /// Confirm enrichment (CE1.4a, CE1.6): a checked A answer pre-fills unknown food details; `Not
    /// these` clears it. A checked B answer pre-fills kept rows; each can be left out or put back.
    case applyDetailsSuggestion(ConfirmDetailsSuggestion)
    case clearDetailsSuggestion
    case applyNutrientSuggestion(ConfirmNutrientSuggestion)
    case clearNutrientSuggestion
    case leaveOutOpenRouterEstimate(NutrientKey)
    case restoreOpenRouterEstimate(NutrientKey)
    /// What the chosen label estimate layer fills, so the merge checks run live (gate section 2.4).
    case setEnrichmentLabelLayer([NutrientKey: Double])
    case beginSaving
    case saveFailed(String)
    case saved(LogItemID)
}

/// Where a correction on Confirm came from (presentation wording only, #470).
public enum FoodCorrectionOrigin: String, Codable, Equatable, Sendable {
    case packagedAsSold
    case carried
}

public enum FoodConfirmationReducer {
    public static func reduce(state: inout FoodConfirmationState, action: FoodConfirmationAction) {
        switch action {
        case let .selectCandidate(index):
            guard state.input.candidates.indices.contains(index) else { return }
            let changed = state.selectedCandidateIndex != index
            let wasServing = state.usesSourceDeclaredServing
            if changed {
                state.quantity.directWeight?.needsReconfirmation = true
                state.quantity.conversion = nil
                // A guide belongs to its record; the view model offers the new record's own sizes.
                state.quantity.portionGuideCode = nil
            }
            state.selectedCandidateIndex = index
            if changed && (wasServing || state.usesSourceDeclaredServing) {
                state.quantity = FoodQuantityDraft(unit: state.usesSourceDeclaredServing ? .count : .grams)
            }
            state.decision = .undecided
            state.correction = nil
            if changed {
                state.decisions = [:]
                state.leftOutEstimates = []  // a leave-out belongs to its candidate
                state.enrichment = ConfirmEnrichmentLayer()  // suggestions belong to their candidate
            }
            state.phase = .editing
        case .accept:
            // Acceptance is the Log press. It never reconfirms a retained weight on its own.
            state.decision = .accepted
            state.phase = .editing
        case let .decideDifference(facet, choice):
            // A fill and a decided difference never stand together (CE1.4a): the fill is cleared first.
            if !state.enrichment.filledFacts.isEmpty { state.enrichment.details = nil }
            state.decisions[facet] = choice
            state.phase = .editing
        case let .setOccurredAt(date):
            state.occurredAt = date
            state.phase = .editing
        case .confirmRetainedWeight:
            state.quantity.directWeight?.needsReconfirmation = false
            state.phase = .editing
        case .decline:
            state.decision = .declined
            state.phase = .editing
        case let .applyCorrection(correction):
            let previousIdentity = state.correction?.identity ?? state.reopened?.productVersion.identity ?? state.selectedCandidate.candidate.identity
            // Confirm rules review v1 (#470 rule 2.4): a correction that only fills in blanks keeps the
            // entered weight, conversion and portion guide; any other correction clears them as v5 did.
            let fill = FoodDetailsFillPolicy.isFill(correction, of: state.selectedCandidate, current: previousIdentity)
            let suggested = state.enrichedIdentity
            state.correction = ConfirmEnrichmentReduction.folding(correction, suggested: suggested, into: &state)
            state.correctionOrigin = nil
            state.decisions = [:]
            state.decision = .accepted
            if !fill {
                state.quantity.conversion = nil
                state.quantity.portionGuideCode = nil
            }
            if !fill, state.quantity.directWeight != nil, previousIdentity != correction.identity {
                state.quantity.directWeight?.needsReconfirmation = true
                state.decision = .undecided
            }
            state.phase = .editing
        case .beginDirectWeight:
            if state.quantity.directWeight == nil { state.quantity.directWeight = DirectWeightDraft() }
            state.quantity.conversion = nil
            state.quantity.portionGuideCode = nil
            state.phase = .editing
        case .endDirectWeight:
            state.quantity.directWeight = nil
            state.phase = .editing
        case let .setDirectWeight(value):
            state.quantity.directWeight?.totalGrams = value
            state.phase = .editing
        case let .setWeightBasis(basis):
            state.quantity.directWeight?.basis = basis
            state.phase = .editing
        case let .setQuantityText(text):
            let value = FoodAmountTextParser.parse(text)
            reduce(state: &state, action: .setQuantity(value, state.quantity.unit))
            state.quantity.invalidOriginalAmountText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value == nil
        case let .setQuantity(value, unit):
            state.quantity.invalidOriginalAmountText = nil
            let previousUnit = state.quantity.unit
            let previousValue = state.quantity.value
            state.quantity.value = value
            state.quantity.unit = unit
            if (previousValue != value || previousUnit != unit) && (unit != .count || previousUnit != unit) {
                state.quantity.conversion = nil
            }
            // A guide size is per piece: a count change keeps it (the total is derived); any other
            // unit drops it.
            if unit != .count { state.quantity.portionGuideCode = nil }
            state.phase = .editing
        case let .setQuantityUnit(unit):
            guard unit != state.quantity.unit else { return }
            state.quantity.value = nil
            state.quantity.invalidOriginalAmountText = nil
            state.quantity.unit = unit
            state.quantity.conversion = nil
            state.quantity.portionGuideCode = nil
            state.phase = .editing
        case let .setConversion(conversion):
            state.quantity.conversion = conversion
            if conversion != nil { state.quantity.portionGuideCode = nil }
            state.phase = .editing
        case let .setPortionGuide(code):
            if let code {
                guard state.quantity.unit == .count, CountPortionGuideCode.entry(code) != nil,
                      CountPortionGuidePolicy.admitsRecord(state) else { return }
                state.quantity.conversion = nil
                state.quantity.directWeight = nil
            }
            state.quantity.portionGuideCode = code
            state.phase = .editing
        case let .setPlateChoice(choice):
            state.quantity.plateChoice = choice
            state.phase = .editing
        case let .leaveOutEstimate(key):
            // Only a value that is shown as an estimate can be left out: never a withheld key, so
            // the saved leave-out evidence never lists one.
            guard state.estimateKeys.contains(key),
                  let entry = state.effectiveNutrients.entries.first(where: { $0.key == key }),
                  ApprovedEstimateSource.isEstimate(entry.value) else { return }
            state.leftOutEstimates.insert(key)
            state.phase = .editing
        case let .restoreEstimate(key):
            guard state.leftOutEstimates.contains(key) else { return }
            state.leftOutEstimates.remove(key)
            state.phase = .editing
        case let .applyDetailsSuggestion(suggestion):
            ConfirmEnrichmentReduction.applyDetails(suggestion, to: &state)
        case .clearDetailsSuggestion:
            state.enrichment.details = nil
            state.enrichment.detailsFolded = false
            state.phase = .editing
        case let .applyNutrientSuggestion(suggestion):
            guard state.reopened == nil, suggestion.capture.captureMethodVersion.value == ConfirmEnrichmentVersions.nutrientCaptureMethodVersion,
                  state.correction.map({ $0.nutrients == state.selectedCandidate.candidate.nutrients }) ?? true
            else { return }
            state.enrichment.nutrients = suggestion
            state.enrichment.leftOut = []
            state.phase = .editing
        case .clearNutrientSuggestion:
            state.enrichment.nutrients = nil
            state.enrichment.leftOut = []
            state.phase = .editing
        case let .leaveOutOpenRouterEstimate(key):
            guard state.enrichmentMerge()?.available[key] != nil else { return }
            state.enrichment.leftOut.insert(key)
            state.phase = .editing
        case let .setEnrichmentLabelLayer(values):
            guard state.reopened == nil else { return }
            state.enrichment.labelLayer = values
        case let .restoreOpenRouterEstimate(key):
            guard state.enrichment.leftOut.contains(key) else { return }
            state.enrichment.leftOut.remove(key)
            state.phase = .editing
        case .beginSaving:
            state.phase = .saving
        case let .saveFailed(message):
            state.phase = .saveFailed(message: message)
        case let .saved(logItemID):
            state.phase = .saved(logItemID: logItemID)
        }
    }
}

public enum FoodConfirmationSaveError: Error, Equatable, Sendable {
    case noAcceptedCandidate
    case unmetRequirements([FoodLogRequirement])
    case staleDecisions
    case invalidQuantity
    case invalidReviewedSource
    /// A `user_verified_panel` value (or a manual declaration claiming an admitted panel
    /// release) that no admitted source verifier accepts against its stored evidence.
    case invalidPastedLabelSource
    /// A chosen label estimate that rule 1, rule 3 or the merge does not admit
    /// (docs/label-estimate-merge-v1.md).
    case invalidLabelEstimate
    /// An approved estimate whose capture manifest does not verify, or a state that would write an
    /// estimated nutrient with any value but the manifest's own or unknown (estimates on catalogue v2).
    case invalidApprovedEstimate
    /// A state that would write an `openrouter_estimate` value that its cited capture and choices item
    /// do not verify (Confirm enrichment v1, CE1.6 rule 4 and CE1.7). No path writes one before the
    /// Confirm suggestion layer lands, so any such value is refused.
    case invalidOpenRouterEstimate
    /// The one-step sheet tried to save an entry that holds an approved estimate or its manifest:
    /// such an entry always goes through Confirm.
    case approvedEstimateNeedsConfirm
}

public final class FoodConfirmationService: @unchecked Sendable {
    private let ledger: FoodLedgerService
    private let reader: any FoodConfirmationReading
    private let clock: any LedgerClock
    private let ids: any LedgerIDGenerating
    private let digester: any Digesting
    private let encoder: any CanonicalEncoding
    private let calendar: Calendar
    private let pastedLabelConversions: (any PastedLabelConversionChecking)?
    private let portionGuides: (any FoodEdibleWeightGuideProviding)?
    private let estimateRecords: (any GenericRecordNutrientLookup)?

    /// `estimateRecords` reads the bundled records that approved estimates cite (estimates on
    /// catalogue v2 section 3.2). Without it every composition estimate is withheld as unreadable
    /// (closed by default).
    /// `pastedLabelConversions` recomputes pasted-label conversions at save and reopen. Without
    /// it, a pasted-label entry with a calculated value fails verification (closed by default).
    /// `portionGuides` resolves a selected count portion guide size at save; without it a new
    /// guide save fails closed (count-portion-estimate-v1, C9).
    public init(
        ledger: FoodLedgerService,
        reader: any FoodConfirmationReading,
        clock: any LedgerClock,
        ids: any LedgerIDGenerating,
        digester: any Digesting,
        calendar: Calendar = .autoupdatingCurrent,
        encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
        pastedLabelConversions: (any PastedLabelConversionChecking)? = nil,
        portionGuides: (any FoodEdibleWeightGuideProviding)? = nil,
        estimateRecords: (any GenericRecordNutrientLookup)? = nil
    ) {
        self.estimateRecords = estimateRecords
        self.pastedLabelConversions = pastedLabelConversions
        self.portionGuides = portionGuides
        self.ledger = ledger
        self.reader = reader
        self.clock = clock
        self.ids = ids
        self.digester = digester
        self.encoder = encoder
        self.calendar = calendar
    }

    /// `estimate` is an optional label estimate chosen on Confirm (pasted label, label photo and
    /// Open Food Facts routes only, docs/label-estimate-merge-v1.md, docs/off-label-estimate-v1.md); without one every save writes what it wrote
    /// before contract 8.
    public func save(
        _ state: FoodConfirmationState,
        operationID: OperationID,
        idempotencyKey: LedgerText? = nil,
        estimate: LabelEstimateChoice? = nil
    ) throws -> StoredFoodConfirmation {
        try save(state, operationID: operationID, idempotencyKey: idempotencyKey, persistedAttachments: [], estimate: estimate)
    }

    /// The one-step sheet's Log (food quick add). An entry that holds an approved estimate, or lists
    /// its capture manifest, is refused here: it always goes through Confirm, where the labels and
    /// tiers are shown and the estimates are re-checked (estimates on catalogue v2 section 5).
    public func saveQuickAdd(_ state: FoodConfirmationState, operationID: OperationID,
                             idempotencyKey: LedgerText? = nil) throws -> StoredFoodConfirmation {
        guard !ApprovedEstimateSource.holdsManifest(state.selectedCandidate.candidate, evidence: state.input.evidence) else {
            throw FoodConfirmationSaveError.approvedEstimateNeedsConfirm
        }
        return try save(state, operationID: operationID, idempotencyKey: idempotencyKey)
    }

    /// Verifies each candidate's capture manifest and reads the records its estimates cite, so the
    /// pure policy can withhold what contradicts the confirmed details (estimates on catalogue v2
    /// section 3.2). Call it when a state is made for a new log, a re-log or a favourite, after a
    /// correction of details on a reopened log and on undo of a leave-out there. Reopening alone
    /// never calls it. A manifest that does not verify is left out, which withholds its estimates.
    public func bindEstimates(_ state: inout FoodConfirmationState) {
        bindEstimates(&state, readingRecords: true)
    }

    private func bindEstimates(_ state: inout FoodConfirmationState, readingRecords: Bool) {
        var manifests: [EvidenceID: ApprovedEstimateCaptureManifest] = [:]
        var records: [ApprovedEstimateRecordKey: ApprovedEstimateRecordState] = [:]
        for candidate in state.input.candidates {
            guard let verified = ApprovedEstimateSource.verifiedManifest(candidate.candidate, evidence: state.input.evidence,
                                                                         digester: digester) else { continue }
            manifests[verified.evidence.evidenceID] = verified.manifest
            guard readingRecords, let lookup = estimateRecords else { continue }
            for estimate in verified.manifest.estimates {
                guard let key = ApprovedEstimateRecordKey(estimate), records[key] == nil else { continue }
                // The manifest's own source, hash and record ID: never the active release's.
                guard let source = PersonalFoodDatabaseGenericSource(rawValue: key.source),
                      case let .success(facts) = lookup.record(source: source, corpusSHA256: key.corpusSHA256,
                                                               recordID: key.recordID) else {
                    records[key] = .unreadable
                    continue
                }
                records[key] = .identity(facts.identity)
            }
        }
        state.estimateManifests = manifests
        if readingRecords { state.estimateRecords = records }
    }

    /// Log for a label photo entry (docs/label-photo-ai-prefill-v1.md 17.3, test 15): the prepared
    /// bytes are persisted first, the image evidence is bound to their attachment, and one ledger
    /// commit then holds the image evidence, the manifest evidence, the release and the log records.
    /// If the bytes do not match the image evidence, policy or the verifier rejects the save, or
    /// the commit fails, the attachment is removed again when nothing references it, so nothing is
    /// kept before a successful Log. `FoodLedgerService.recordEvidenceWithAttachment` is never used
    /// here, because it commits the evidence on its own.
    public func saveLabelPhoto(
        _ state: FoodConfirmationState,
        imageBytes: Data,
        attachmentStore: any EvidenceAttachmentStoring,
        operationID: OperationID,
        idempotencyKey: LedgerText? = nil,
        estimate: LabelEstimateChoice? = nil
    ) throws -> StoredFoodConfirmation {
        if let idempotencyKey, try ledger.confirmedLogItemID(operationID: operationID, idempotencyKey: idempotencyKey) != nil {
            return try save(state, operationID: operationID, idempotencyKey: idempotencyKey)
        }
        let selected = state.selectedCandidate
        guard state.reopened == nil, LabelSourceAdmission.route(state.input, candidate: selected) == .photo,
              selected.candidate.evidenceIDs.count == 2,
              let index = state.input.evidence.firstIndex(where: { $0.evidenceID == selected.candidate.evidenceIDs[1] }),
              state.input.evidence[index].attachment == nil,
              try digester.sha256(imageBytes) == state.input.evidence[index].byteHash else {
            throw FoodConfirmationSaveError.invalidPastedLabelSource
        }
        let image = state.input.evidence[index]
        let descriptor = try attachmentStore.persist(imageBytes, mediaKind: LedgerText(LabelPhotoManifest.mediaType))
        do {
            guard descriptor.sha256 == image.byteHash, descriptor.byteCount == imageBytes.count else {
                throw FoodLedgerStoreError.attachmentFailure("persisted label photo does not match its evidence")
            }
            var evidence = state.input.evidence
            evidence[index] = try CaptureEvidence(evidenceID: image.evidenceID, kind: image.kind, capturedAt: image.capturedAt,
                locale: image.locale, captureMethod: image.captureMethod, captureMethodVersion: image.captureMethodVersion,
                originalPayload: image.originalPayload, byteHash: image.byteHash, attachment: descriptor)
            var attached = state
            attached.input = try PopulatedFoodConfirmation(evidence: evidence, sourceReleases: state.input.sourceReleases,
                candidates: state.input.candidates, expectedIdentity: state.input.expectedIdentity,
                expectedEdibleQuantity: state.input.expectedEdibleQuantity)
            return try save(attached, operationID: operationID, idempotencyKey: idempotencyKey, persistedAttachments: [descriptor],
                            estimate: estimate)
        } catch {
            try? attachmentStore.removeIfUnreferenced(descriptor)
            throw error
        }
    }

    /// Import v1 section 7 (phase 1 plan section 5): a Your food database resolution also links each
    /// upstream release its values cite (owner label, Open Food Facts, merged generic record), after
    /// the existing links, so every provenance release is a linked release. Other sources are
    /// unchanged: their values cite only releases already linked.
    static func linkedReleaseIDs(_ base: [ExternalIdentifier], nutrients: NutrientSet, candidate: ProviderNeutralCandidate,
                                 releases: [SourceRelease]) -> [ExternalIdentifier] {
        guard releases.first(where: { $0.sourceReleaseID == candidate.sourceReleaseID })?.sourceID.value
                == PersonalFoodDatabaseRelease.sourceID else { return base }
        var linked = base
        for entry in nutrients.entries {
            for value in [entry.value] + entry.conflictCandidates {
                for provenance in value.provenance where !linked.contains(provenance.sourceReleaseID) {
                    linked.append(provenance.sourceReleaseID)
                }
            }
        }
        return linked
    }

    private func save(
        _ submitted: FoodConfirmationState,
        operationID: OperationID,
        idempotencyKey: LedgerText?,
        persistedAttachments: Set<AttachmentDescriptor>,
        estimate: LabelEstimateChoice? = nil
    ) throws -> StoredFoodConfirmation {
        // Approved estimates: the service never trusts the state's copy of what was bound. For a new
        // log, a corrected reopened log and an undo it verifies the manifest and reads the records
        // itself; a reopened log that only gains a leave-out reads no record.
        var state = submitted
        // CE1.4a: a Jev fill shown on Confirm is written as a correction, exactly as a sheet fill is.
        if let fill = FoodDetailsFillPolicy.enrichmentFill(state) { state.correction = fill }
        let holdsEstimates = ApprovedEstimateSource.holdsManifest(state.selectedCandidate.candidate, evidence: state.input.evidence)
        if holdsEstimates {
            let undoes = !state.estimateSeed.leftOut.isSubset(of: state.leftOutEstimates)
            bindEstimates(&state, readingRecords: state.reopened == nil || state.correction != nil || undoes)
        }
        if let idempotencyKey,
           let logItemID = try ledger.confirmedLogItemID(operationID: operationID, idempotencyKey: idempotencyKey) {
            guard let stored = try reader.foodConfirmation(logItemID: logItemID) else {
                throw FoodLedgerStoreError.integrityFailure("committed confirmation could not be recovered")
            }
            try stored.logItemVersion.validateWeightDeclaration(emptyPlate: stored.plateWeightVersion)
            _ = try restoredConfirmationInput(stored)
            return stored
        }
        guard state.decision == .accepted else { throw FoodConfirmationSaveError.noAcceptedCandidate }

        let selected = state.selectedCandidate
        if holdsEstimates {
            // A new log needs its manifest to verify, and a correction never changes a nutrient of
            // such a candidate: an estimate is kept, withheld or left out, nothing else.
            guard state.reopened != nil || state.estimateManifest != nil || state.estimateKeys.isEmpty,
                  state.correction.map({ $0.nutrients == selected.candidate.nutrients }) ?? true else {
                throw FoodConfirmationSaveError.invalidApprovedEstimate
            }
        }
        // A reopened entry already has a user-confirmed product identity. The
        // retained source candidate may still contain explicitly asserted gaps.
        let identity = state.correction?.identity ?? state.reopened?.productVersion.identity ?? selected.candidate.identity
        if FoodReviewedWebProposalPolicy.applies(state.input, candidate: selected) {
            guard FoodReviewedWebProposalPolicy.manifestDigestIsValid(evidence: state.input.evidence,
                    releases: state.input.sourceReleases, candidate: selected.candidate, digester: digester),
                  FoodReviewedWebProposalPolicy.scope(state.input, candidate: selected) != nil,
                  identity.servingBasis == selected.candidate.identity.servingBasis,
                  (state.correction?.nutrients ?? state.reopened?.resolutionVersion.nutrients ?? selected.candidate.nutrients) == selected.candidate.nutrients else {
                throw FoodConfirmationSaveError.invalidReviewedSource
            }
        }
        // Label admission (pasted label or label photo, P19): routed by the composite to exactly one
        // verifier against the stored manifest, before policy. A mixed candidate is refused.
        if LabelSourceAdmission.applies(state.input, candidate: selected) {
            // A reopened entry keeps its estimate layer unless corrected (section 6 step 4 at save).
            let expected: NutrientSet?
            if state.correction == nil, let reopened = state.reopened {
                expected = try LabelEstimateLayer.expectedNutrients(reopened, label: selected)
            } else {
                expected = selected.candidate.nutrients
            }
            guard LabelSourceAdmission.verify(state.input, candidate: selected, encoder: encoder, digester: digester,
                                              conversions: pastedLabelConversions),
                  identity.servingBasis == selected.candidate.identity.servingBasis,
                  (state.correction?.nutrients ?? state.reopened?.resolutionVersion.nutrients ?? selected.candidate.nutrients) == expected else {
                throw FoodConfirmationSaveError.invalidPastedLabelSource
            }
        } else if state.correction == nil, let reopened = state.reopened,
                  reopened.estimate != nil || reopened.assertions.contains(where: { $0.labelEstimate != nil }) {
            // An edit of a layered Open Food Facts entry (off-label-estimate-v1 rule 2): the stored
            // candidate is the evidence of record, so the layer is rechecked against it as the label
            // branch does. Entries without a layer never reach this branch.
            guard OpenFoodFactsEstimateSource.applies(state.input, candidate: selected),
                  identity.servingBasis == selected.candidate.identity.servingBasis,
                  let expected = try LabelEstimateLayer.expectedNutrients(reopened, label: selected),
                  // CE1 section 5a: the layer merge plus the B rows, which verification checks.
                  ConfirmEnrichmentCitation.replacingOpenRouterEstimates(reopened.resolutionVersion.nutrients, from: expected) == expected else {
                throw FoodConfirmationSaveError.invalidLabelEstimate
            }
        }
        // Label estimate layer (label-estimate-merge-v1, and off-label-estimate-v1 for an Open Food
        // Facts product): a new, uncorrected entry of an admitted route only, a row that rule 3
        // admits for the confirmed percentage, and a merge on the source's basis.
        let layer: (choice: LabelEstimateChoice, nutrients: NutrientSet, assertion: LabelEstimateAssertion)?
        if let estimate {
            // An identity-only correction keeps an Open Food Facts estimate (decision 6); labels
            // admit none after a correction.
            guard state.reopened == nil,
                  (state.correction == nil && LabelSourceAdmission.applies(state.input, candidate: selected))
                    || OpenFoodFactsEstimateSource.admitsLayer(state),
                  LabelEstimateCompatibility.isCompatible(estimate.generic, cocoaPercent: estimate.cocoaPercent),
                  estimate.evidence.map(\.evidenceID) == estimate.generic.candidate.evidenceIDs,
                  let nutrients = try LabelEstimateLayer.merged(label: selected, generic: estimate.generic.candidate,
                                                                release: estimate.sourceRelease, cocoaPercent: estimate.cocoaPercent) else {
                throw FoodConfirmationSaveError.invalidLabelEstimate
            }
            layer = (estimate, nutrients, try LabelEstimateAssertion(cocoaPercent: estimate.cocoaPercent, cocoaPercentOrigin: estimate.origin,
                compatibilityVersion: LedgerText(LabelEstimateCompatibility.version), mergeVersion: LedgerText(LabelEstimateMerge.version),
                genericName: estimate.generic.name, genericVariant: estimate.generic.variant))
        } else {
            layer = nil
        }
        // A new label photo entry is logged only through `saveLabelPhoto`, which binds the image
        // evidence to the persisted photo in the same commit (17.3).
        if state.reopened == nil, LabelSourceAdmission.route(state.input, candidate: selected) == .photo,
           !state.input.evidence.contains(where: { selected.candidate.evidenceIDs.contains($0.evidenceID) && $0.attachment != nil }) {
            throw FoodConfirmationSaveError.invalidPastedLabelSource
        }
        let now = clock.now()
        // The service is authoritative: the same pure policy that drives the Log button.
        let unmet = FoodLogPolicy.requirements(state, now: now, calendar: calendar)
        guard unmet.isEmpty else { throw FoodConfirmationSaveError.unmetRequirements(unmet) }
        // count-portion-estimate-v1 (gate G6): a guide size only on a record counted in pieces.
        if state.quantity.portionGuideCode != nil, state.quantity.conversion == nil, state.quantity.directWeight == nil,
           !CountPortionGuidePolicy.applies(state) {
            throw FoodConfirmationSaveError.invalidQuantity
        }
        let decisionRecord = try FoodLogPolicy.decisionRecord(state)
        let savesEstimate = FoodLogPolicy.savesEstimate(state)
        let previous = state.reopened
        let occurredAt = state.occurredAt ?? previous?.logItemVersion.occurredAt ?? now
        let reportingDate: LedgerText
        if let previous, previous.logItemVersion.occurredAt == occurredAt {
            reportingDate = previous.logItemVersion.reportingDate
        } else {
            reportingDate = try LedgerText(FoodReportingDay.key(for: occurredAt, calendar: calendar))
        }
        // pasted-label-serving-v1 or -v2 supplies its own conversion for servings, or none (v1 case 3).
        let quantity = try state.labelPolicyQuantity()
        let declaration = try quantity.declaration()
        let entered = try quantity.calculationInput()
        let countedServings = state.usesSourceDeclaredServing || (state.logsLabelServings && quantity.conversion == nil)
        let conversion = declaration == nil
            ? try makeConversion(quantity, entered: entered, previous: previous, at: now, sourceRecipe: countedServings,
                                 state: state)
            : (version: nil, isNew: false)
        let plate = try makePlate(quantity.plateChoice, previous: previous, at: now)
        let edibleQuantity = try state.calculatedEdibleQuantity()

        // The one predicate "the log's food facts changed" (estimates on catalogue v2 section 5): a
        // correction, or a leave-out set that differs from its seed. Without an approved estimate it
        // is the correction test, as before.
        let changesProduct = previous == nil || state.foodFactsChanged
        let savedLeftOut = state.savedLeaveOutSet
        let leaveOutChanged = state.correction == nil && savedLeftOut != state.estimateSeed.leftOut
        // Confirm enrichment (gate section 2.4a): a change of B choices alone on a reopened log.
        let enrichmentChoicesChanged = previous != nil && state.correction == nil && state.enrichment.choicesChanged
        // A leave-out or undo alone on a reopened log: the saved identity, decision record and
        // outcome are carried unchanged into the new assertion and decision.
        let leaveOutOnly = previous != nil && state.correction == nil && (leaveOutChanged || enrichmentChoicesChanged)
        // One leave-out item per saved resolution version whose set is not empty. It names its
        // version, so that ID is made first; saves without a leave-out make their IDs as before.
        var leftOutEvidence: CaptureEvidence?
        var leftOutVersionID: ResolutionVersionID?
        if changesProduct, !savedLeftOut.isEmpty {
            guard let manifest = ApprovedEstimateSource.manifestEvidence(selected.candidate, evidence: state.input.evidence),
                  let manifestHash = manifest.byteHash else { throw FoodConfirmationSaveError.invalidApprovedEstimate }
            let versionID = try ids.makeID(ResolutionVersionTag.self)
            guard let item = ApprovedEstimateLeftOutEvidence(resolutionVersionID: versionID.rawValue,
                                                             manifestSHA256: manifestHash.value, leftOut: savedLeftOut) else {
                throw FoodConfirmationSaveError.invalidApprovedEstimate
            }
            let payload = try encoder.encode(item)
            leftOutEvidence = try CaptureEvidence(
                evidenceID: ids.makeID(EvidenceTag.self), kind: .labelText, capturedAt: now, locale: manifest.locale,
                captureMethod: LedgerText("Estimated values left out by you"),
                captureMethodVersion: LedgerText(ApprovedEstimateProvenance.leftOutMethodVersion),
                originalPayload: .text(LedgerText(String(decoding: payload, as: UTF8.self))), byteHash: digester.sha256(payload))
            leftOutVersionID = versionID
        }
        // Confirm enrichment (gate sections 2.4 and 2.4a): the kept B rows are merged at save after the
        // label layer, with one choices item naming the new version; the A capture is cited while the
        // version keeps a fact it applied. A reopened log whose B choices change keeps its label layer.
        let carriesLayer = changesProduct && layer == nil && state.correction == nil && previous?.estimate != nil
            && state.enrichment.seedLeftOut != nil
        let layerValues: [NutrientKey: Double] = layer.map {
            ConfirmEnrichmentMerge.values($0.nutrients, release: $0.choice.sourceRelease.sourceReleaseID)
        } ?? (carriesLayer ? previous.map(ConfirmEnrichmentMerge.layerValues) ?? [:] : [:])
        var enrichmentMerge: ConfirmEnrichmentMerge.Result?
        var nutrientCapture: CaptureEvidence?
        var choicesEvidence: CaptureEvidence?
        var choicesVersionID: ResolutionVersionID?
        if changesProduct, let rows = state.enrichment.nutrients,
           let merge = state.enrichmentMerge(layer: layerValues, base: layer?.nutrients ?? state.enrichmentBase), !merge.saved.isEmpty {
            let versionID = try leftOutVersionID ?? ids.makeID(ResolutionVersionTag.self)
            choicesEvidence = try ConfirmEnrichmentCaptureBuilder.choices(
                capture: rows.capture, resolutionVersionID: versionID, merge: merge, capturedAt: now,
                id: ids.makeID(EvidenceTag.self), encoder: encoder, digester: digester)
            enrichmentMerge = merge
            nutrientCapture = rows.capture
            choicesVersionID = versionID
        }
        let detailsCapture = changesProduct ? Self.citedDetailsCapture(state: state, selected: selected, identity: identity) : nil
        let enrichmentIDs = [detailsCapture, nutrientCapture, choicesEvidence].compactMap { $0?.evidenceID }
        // Evidence is reached through the decision's embedded candidate, so the new decision's
        // candidate lists the leave-out item after the bound candidate's own evidence IDs, and
        // differs from the bound candidate in that list only.
        // Confirm enrichment (phase gate section 2.4a): a save of a candidate that cites CE1 items, or
        // that writes one, rebuilds the list from the candidate's own IDs, so no earlier CE1 or
        // leave-out item is carried; then the leave-out item, the A capture, the B capture and the
        // version's own choices item, once each.
        let stripsEnrichment = changesProduct
            && (ConfirmEnrichmentCitation.citesEnrichment(selected.candidate, evidence: state.input.evidence) || !enrichmentIDs.isEmpty)
        let decisionCandidate: ProviderNeutralCandidate
        if stripsEnrichment {
            decisionCandidate = try ProviderNeutralCandidate(
                sourceReleaseID: selected.candidate.sourceReleaseID, recordID: selected.candidate.recordID,
                identity: selected.candidate.identity, edibleQuantity: selected.candidate.edibleQuantity,
                nutrients: selected.candidate.nutrients,
                evidenceIDs: ConfirmEnrichmentCitation.ownEvidenceIDs(selected.candidate, evidence: state.input.evidence)
                    + (leftOutEvidence.map { [$0.evidenceID] } ?? []) + enrichmentIDs,
                matchMetadata: selected.candidate.matchMetadata)
        } else {
            decisionCandidate = try leftOutEvidence.map { item in
                try ProviderNeutralCandidate(
                    sourceReleaseID: selected.candidate.sourceReleaseID, recordID: selected.candidate.recordID,
                    identity: selected.candidate.identity, edibleQuantity: selected.candidate.edibleQuantity,
                    nutrients: selected.candidate.nutrients, evidenceIDs: selected.candidate.evidenceIDs + [item.evidenceID],
                    matchMetadata: selected.candidate.matchMetadata)
            } ?? selected.candidate
        }
        let assertion = changesProduct
            ? try makeAssertion(state: state, selected: selected, previous: previous, record: decisionRecord,
                                labelEstimate: layer?.assertion
                                    ?? (carriesLayer ? previous?.assertions.compactMap(\.labelEstimate).last : nil),
                                leftOut: leaveOutChanged ? savedLeftOut : nil,
                                enrichmentLeftOut: enrichmentChoicesChanged ? state.enrichment.leftOut : nil, at: now)
            : nil
        let product: Product
        if let existing = previous?.product {
            product = existing
        } else {
            product = Product(productID: try ids.makeID(ProductTag.self), createdAt: now)
        }
        let productVersion: ProductVersion
        let decision: CandidateDecision
        var estimateDecision: CandidateDecision?
        let resolution: NutritionResolution
        let resolutionVersion: NutritionResolutionVersion
        if changesProduct {
            productVersion = try ProductVersion(
                productVersionID: ids.makeID(ProductVersionTag.self),
                productID: product.productID,
                ordinal: VersionOrdinal((previous?.productVersion.ordinal.value ?? 0) + 1),
                supersedesProductVersionID: previous?.productVersion.productVersionID,
                name: state.correction?.name ?? selected.name,
                brand: state.correction?.brand ?? selected.brand,
                variant: state.correction?.variant ?? selected.variant,
                barcode: selected.barcode,
                itemClass: state.correction?.itemClass ?? selected.itemClass,
                packFacts: selected.packFacts,
                identity: identity,
                evidenceIDs: stripsEnrichment ? decisionCandidate.evidenceIDs : selected.candidate.evidenceIDs,
                assertionIDs: assertion.map { [$0.assertionID] } ?? [],
                createdAt: now
            )
            decision = try CandidateDecision(
                candidateDecisionID: ids.makeID(CandidateDecisionTag.self),
                candidate: decisionCandidate,
                // A leave-out-only save keeps the saved decision's expectations and outcome: the
                // reopened input's expected quantity is the logged amount, which no 100 g candidate
                // equals, and a `selected` outcome admits no difference.
                expectedIdentity: leaveOutOnly ? previous?.candidateDecision.expectedIdentity ?? identity : identity,
                expectedEdibleQuantity: leaveOutOnly ? previous?.candidateDecision.expectedEdibleQuantity
                    ?? state.input.expectedEdibleQuantity : state.input.expectedEdibleQuantity,
                // An unknown-identity estimate (generic, or a pasted label's Not stated, #306) is
                // recorded `rejected` with its contradiction reasons, as v2 records generic ones.
                // An identity-only correction of an Open Food Facts product that keeps its estimate
                // (off-label-estimate-v1 decision 6) is also recorded `rejected`, as every corrected
                // save is: intended. The layer's own decision records the estimate use, and reopen,
                // the commit rules and `isEstimate` never read this outcome.
                requestedOutcome: leaveOutOnly ? previous?.candidateDecision.outcome ?? .rejected
                    : state.correction == nil && ((!state.isGenericEstimate && !PastedLabelFortificationPolicy.applies(state))
                    || IdentityCompatibility.contradictions(
                    between: identity, and: selected.candidate.identity,
                    expectedEdibleQuantity: state.input.expectedEdibleQuantity,
                    candidateEdibleQuantity: selected.candidate.edibleQuantity
                ).isEmpty) ? .selected : .rejected,
                assertionID: assertion?.assertionID,
                createdAt: now
            )
            // The generic row's decision records estimate use, never identity acceptance (rule 4).
            estimateDecision = try layer.map { layer in
                try CandidateDecision(candidateDecisionID: ids.makeID(CandidateDecisionTag.self), candidate: layer.choice.generic.candidate,
                    expectedIdentity: identity, expectedEdibleQuantity: state.input.expectedEdibleQuantity,
                    requestedOutcome: .selectedForEstimate, assertionID: assertion?.assertionID, createdAt: now)
            }
            // A B-only edit of a layered entry keeps its layer: a new estimate decision on the same row,
            // committed with the version, as confirm_food_v4 requires of a resolution's second decision.
            if carriesLayer, let kept = previous?.estimate {
                estimateDecision = try CandidateDecision(candidateDecisionID: ids.makeID(CandidateDecisionTag.self),
                    candidate: kept.candidateDecision.candidate, expectedIdentity: kept.candidateDecision.expectedIdentity,
                    expectedEdibleQuantity: kept.candidateDecision.expectedEdibleQuantity, requestedOutcome: .selectedForEstimate,
                    assertionID: assertion?.assertionID, createdAt: now)
            }
            resolution = NutritionResolution(
                resolutionID: try ids.makeID(ResolutionTag.self),
                productVersionID: productVersion.productVersionID,
                basis: identity.servingBasis,
                createdAt: now
            )
            // The effective set: the candidate's or the correction's, with every withheld or left-out
            // estimate unknown. Without an approved estimate it is what was written before.
            // A reopened version's earlier B values return to the candidate's entries first.
            var nutrients = layer?.nutrients ?? state.enrichmentBase
            if let merge = enrichmentMerge, let capture = nutrientCapture {
                // CE1.6 rule 4, third check: a B value only ever replaces an eligible unknown of the set
                // being saved, and never sits beside a correction that changed the values.
                guard state.correction.map({ $0.nutrients == selected.candidate.nutrients }) ?? true,
                      merge.saved.keys.allSatisfy({ key in
                          nutrients.entries.first { $0.key == key }.map(ConfirmEnrichmentPolicy.isEligibleUnknown) ?? false
                      }) else { throw FoodConfirmationSaveError.invalidOpenRouterEstimate }
                let basis = selected.candidate.identity.servingBasis
                nutrients = try NutrientSet(entries: nutrients.entries.map { entry in
                    guard let amount = merge.saved[entry.key] else { return entry }
                    return try NutrientEntry(key: entry.key,
                        value: ConfirmEnrichmentCaptureBuilder.value(amount, key: entry.key, basis: basis, capture: capture))
                })
            }
            let versionID = try leftOutVersionID ?? choicesVersionID ?? ids.makeID(ResolutionVersionTag.self)
            // CE1.6 rule 4: no `openrouter_estimate` value is written unless it verifies against its cited
            // capture and this version's choices item, on keys still eligible on the candidate.
            if ConfirmEnrichmentCitation.holdsOpenRouterEstimate(nutrients) {
                let evidence = state.input.evidence + [nutrientCapture, choicesEvidence].compactMap { $0 }
                    .filter { item in !state.input.evidence.contains { $0.evidenceID == item.evidenceID } }
                guard let rows = state.enrichment.nutrients, rows.inputs.basis == ConfirmEnrichmentPolicy.basis(identity.servingBasis),
                      case .verified = ConfirmEnrichmentVerification.verify(
                          nutrients: nutrients, resolutionVersionID: versionID, citedEvidenceIDs: decisionCandidate.evidenceIDs,
                          evidence: evidence, layer: layerValues, digester: digester) else {
                    throw FoodConfirmationSaveError.invalidOpenRouterEstimate
                }
            }
            var releaseIDs = [selected.candidate.sourceReleaseID] + (layer.map { [$0.choice.sourceRelease.sourceReleaseID] } ?? [])
            if carriesLayer, let kept = previous?.estimate { releaseIDs.append(kept.sourceRelease.sourceReleaseID) }
            if let capture = nutrientCapture { releaseIDs.append(try ConfirmEnrichmentCaptureBuilder.release(capture).sourceReleaseID) }
            resolutionVersion = try NutritionResolutionVersion(
                resolutionVersionID: versionID,
                resolutionID: resolution.resolutionID,
                ordinal: VersionOrdinal(1),
                methodVersion: LedgerText(FoodConfirmationPolicy.version),
                sourceReleaseIDs: Self.linkedReleaseIDs(releaseIDs, nutrients: nutrients, candidate: selected.candidate,
                                                        releases: state.input.sourceReleases),
                nutrients: nutrients,
                decisionIDs: [decision.candidateDecisionID] + (estimateDecision.map { [$0.candidateDecisionID] } ?? []),
                assertionIDs: assertion.map { [$0.assertionID] } ?? [],
                createdAt: now
            )
        } else {
            guard let previous else { throw FoodConfirmationSaveError.noAcceptedCandidate }
            productVersion = previous.productVersion
            decision = previous.candidateDecision
            resolution = previous.resolution
            resolutionVersion = previous.resolutionVersion
        }
        let logItem: LogItem
        if let existing = previous?.logItem {
            logItem = existing
        } else {
            logItem = LogItem(logItemID: try ids.makeID(LogItemTag.self), createdAt: now)
        }
        let logVersion = try LogItemVersion(
            logItemVersionID: ids.makeID(LogItemVersionTag.self),
            logItemID: logItem.logItemID,
            ordinal: VersionOrdinal((previous?.logItemVersion.ordinal.value ?? 0) + 1),
            supersedesLogItemVersionID: previous?.logItemVersion.logItemVersionID,
            occurredAt: occurredAt,
            reportingDate: reportingDate,
            composition: .product(productVersion.productVersionID),
            edibleQuantity: edibleQuantity,
            weightDeclaration: declaration,
            quantityConversionVersionID: conversion.version?.quantityConversionVersionID,
            plateWeightVersionID: plate.version?.plateWeightVersionID,
            originalResolutionVersionID: previous?.logItemVersion.originalResolutionVersionID ?? resolutionVersion.resolutionVersionID,
            effectiveResolutionVersionID: resolutionVersion.resolutionVersionID,
            correctionReason: previous.map { previous in
                try state.correction?.reason
                    ?? (enrichmentChoicesChanged ? LedgerText(OpenRouterEstimateChoicesText.editReason) : nil)
                    ?? (leaveOutChanged ? LedgerText(ApprovedEstimateLeaveOutText.editReason) : nil)
                    ?? Self.editReason(previous: previous.logItemVersion, occurredAt: occurredAt,
                    edibleQuantity: edibleQuantity, declaration: declaration,
                    conversionID: conversion.version?.quantityConversionVersionID, plateID: plate.version?.plateWeightVersionID)
            },
            createdAt: now
        )
        let libraryRecords: (LibraryEntry?, LibraryEntryVersion?)
        // D6: an estimate never becomes an exact personal-library alias.
        if previous == nil, !savesEstimate,
           let aliases = selected.candidate.matchMetadata?.libraryAliases,
           !aliases.isEmpty {
            let entry = LibraryEntry(
                libraryEntryID: try ids.makeID(LibraryEntryTag.self),
                createdAt: now
            )
            let version = try LibraryEntryVersion(
                libraryEntryVersionID: ids.makeID(LibraryEntryVersionTag.self),
                libraryEntryID: entry.libraryEntryID,
                ordinal: VersionOrdinal(1),
                productVersionID: productVersion.productVersionID,
                aliases: aliases,
                reusableQuantity: edibleQuantity,
                quantityConversionVersionID: conversion.version?.quantityConversionVersionID,
                createdAt: now
            )
            libraryRecords = (entry, version)
        } else {
            libraryRecords = (nil, nil)
        }

        let enrichmentRelease = try nutrientCapture.map(ConfirmEnrichmentCaptureBuilder.release)
        let missingReleases = try (state.input.sourceReleases + (layer.map { [$0.choice.sourceRelease] } ?? [])
                                   + (enrichmentRelease.map { [$0] } ?? [])).filter {
            try reader.sourceRelease(id: $0.sourceReleaseID) == nil
        }
        // Q11: evidence already retained with canonically identical bytes is skipped (re-log,
        // favourites, plain water), as stored source releases are. Anything else is written, so an
        // existing ID with different bytes, or a racing insert, still fails as immutableRecord.
        let inputEvidenceIDs = Set(state.input.evidence.map(\.evidenceID))
        let layerEvidence = layer?.choice.evidence.filter { !inputEvidenceIDs.contains($0.evidenceID) } ?? []
        // One entry's log never stores another entry's capture manifest: a search confirmation holds
        // a manifest for each candidate with estimates, and only the selected candidate's is saved.
        let selectedEvidenceIDs = Set(selected.candidate.evidenceIDs)
        let inputEvidence = state.input.evidence.filter {
            !ApprovedEstimateSource.isManifest($0) || selectedEvidenceIDs.contains($0.evidenceID)
        }
        // CE1 captures are committed only with the Log that cites them, once.
        let enrichmentEvidence = [detailsCapture, nutrientCapture].compactMap { $0 }.filter { !inputEvidenceIDs.contains($0.evidenceID) }
            + (choicesEvidence.map { [$0] } ?? [])
        let newEvidence = (previous == nil ? try (inputEvidence + layerEvidence).filter { try !isRetained($0) } : [])
            + (leftOutEvidence.map { [$0] } ?? []) + enrichmentEvidence
        let mutation = LedgerMutation(
            evidence: newEvidence,
            assertions: assertion.map { [$0] } ?? [],
            products: previous == nil ? [product] : [],
            productVersions: changesProduct ? [productVersion] : [],
            libraryEntries: libraryRecords.0.map { [$0] } ?? [],
            libraryEntryVersions: libraryRecords.1.map { [$0] } ?? [],
            resolutions: changesProduct ? [resolution] : [],
            resolutionVersions: changesProduct ? [resolutionVersion] : [],
            logItems: previous == nil ? [logItem] : [],
            logItemVersions: [logVersion],
            quantityConversions: conversion.isNew ? conversion.version.map { [$0] } ?? [] : [],
            plates: plate.newPlate.map { [$0] } ?? [],
            plateWeightVersions: plate.isNew ? plate.version.map { [$0] } ?? [] : [],
            candidateDecisions: changesProduct ? [decision] + (estimateDecision.map { [$0] } ?? []) : [],
            sourceReleases: missingReleases
        )
        _ = try ledger.commit(
            mutation,
            // confirm_food_v4 carries a new estimate layer, or an edit that keeps one; anything
            // else writes exactly the type it wrote before contract 8.
            type: layer != nil || (!changesProduct && previous?.estimate != nil) || carriesLayer ? .confirmFoodV4
                : assertion?.confirmation != nil ? .confirmFoodV3 : (declaration == nil ? .confirmFood : .confirmFoodV2),
            operationID: operationID,
            idempotencyKey: idempotencyKey,
            persistedAttachments: persistedAttachments
        )
        let keptEstimate: StoredLabelEstimate?
        if carriesLayer, let kept = previous?.estimate, let decision = estimateDecision {
            keptEstimate = StoredLabelEstimate(candidateDecision: decision, evidence: kept.evidence, sourceRelease: kept.sourceRelease)
        } else {
            keptEstimate = changesProduct ? nil : previous?.estimate
        }
        var returnedReleases = (previous?.sourceReleases ?? []) + state.input.sourceReleases.filter { source in
            !(previous?.sourceReleases.contains { $0.sourceReleaseID == source.sourceReleaseID } ?? false)
        }
        if let release = enrichmentRelease, !returnedReleases.contains(where: { $0.sourceReleaseID == release.sourceReleaseID }) {
            returnedReleases.append(release)
        }
        return StoredFoodConfirmation(
            // What the store reads back: without another candidate's manifest, with a new leave-out item.
            evidence: (previous?.evidence ?? inputEvidence) + (leftOutEvidence.map { [$0] } ?? []) + enrichmentEvidence,
            sourceReleases: returnedReleases,
            product: product,
            productVersion: productVersion,
            resolution: resolution,
            resolutionVersion: resolutionVersion,
            logItem: logItem,
            logItemVersion: logVersion,
            quantityConversion: conversion.version,
            plate: plate.newPlate ?? previous?.plate,
            plateWeightVersion: plate.version,
            candidateDecision: decision,
            // An edit that keeps a layer returns its stored cocoa assertion with it, as the reader does.
            assertions: assertion.map { [$0] } ?? (keptEstimate != nil ? previous?.assertions ?? [] : []),
            estimate: keptEstimate ?? estimateDecision.flatMap { decision in
                layer.map { StoredLabelEstimate(candidateDecision: decision, evidence: $0.choice.evidence, sourceRelease: $0.choice.sourceRelease) }
            }
        )
    }

    /// The A capture a saved version cites (gate section 2.4a): the shown fill's, or on reopen the bound
    /// candidate's earlier capture, only while the version keeps at least one fact it applied.
    static func citedDetailsCapture(state: FoodConfirmationState, selected: PopulatedFoodCandidate,
                                    identity: DecisiveIdentity) -> CaptureEvidence? {
        let capture = state.enrichment.details?.capture ?? (state.reopened == nil ? nil : state.input.evidence.first {
            selected.candidate.evidenceIDs.contains($0.evidenceID)
                && $0.captureMethodVersion.value == ConfirmEnrichmentVersions.detailsCaptureMethodVersion
        })
        guard let capture, let payload = ConfirmEnrichmentEvidence.details(capture) else { return nil }
        let choices = Dictionary(payload.answers.map { ($0.fact, $0.choice) }, uniquingKeysWith: { first, _ in first })
        let holds = payload.applied.contains { fact in
            guard let typed = ConfirmDetailsFact(rawValue: fact) else { return false }
            return ConfirmEnrichmentPolicy.token(typed, of: identity) == choices[fact]
        }
        return holds ? capture : nil
    }

    /// Whether this evidence member is already stored with canonically identical bytes.
    private func isRetained(_ member: CaptureEvidence) throws -> Bool {
        guard let stored = try reader.evidence(id: member.evidenceID) else { return false }
        return try encoder.encode(stored) == encoder.encode(member)
    }

    public func reopen(logItemID: LogItemID) throws -> FoodConfirmationState? {
        guard let saved = try reader.foodConfirmation(logItemID: logItemID) else { return nil }
        try saved.logItemVersion.validateWeightDeclaration(emptyPlate: saved.plateWeightVersion)
        let input = try restoredConfirmationInput(saved)
        // A stored conversion naming a pasted-label serving method must be exactly what that
        // method records on this label (contract section 6.3), never another method's or a stale one.
        if let conversion = saved.quantityConversion,
           LabelServingPolicy.admittedVersions.contains(conversion.methodVersion.value),
           !LabelServingPolicy.verifies(conversion, input: input, candidate: input.candidates[0]) {
            throw FoodLedgerStoreError.integrityFailure("pasted label servings conversion does not match its label")
        }
        var state = FoodConfirmationState(input: input, reopened: saved)
        state.decision = .accepted
        seedEstimates(&state, saved: saved)
        seedEnrichment(&state, saved: saved)
        return state
    }

    /// A reopened log's suggestion layer (CE1.7a): rebuilt from the effective version's cited capture
    /// and choices item, verified first (CE1.7, gate section 2.4). Reads no network. Evidence that does
    /// not verify reads "Evidence not available" and changes no stored value.
    private func seedEnrichment(_ state: inout FoodConfirmationState, saved: StoredFoodConfirmation) {
        let layer = ConfirmEnrichmentMerge.layerValues(saved)
        state.enrichment.labelLayer = layer
        switch ConfirmEnrichmentVerification.verify(
            nutrients: saved.resolutionVersion.nutrients, resolutionVersionID: saved.resolutionVersion.resolutionVersionID,
            citedEvidenceIDs: saved.candidateDecision.candidate.evidenceIDs, evidence: saved.evidence, layer: layer,
            digester: digester) {
        case .none: return
        case .notAvailable: state.enrichment.evidenceNotAvailable = true
        case let .verified(verified):
            guard let inputs = ConfirmNutrientRequestInputs.decode(requestBody: verified.capture.requestBody) else {
                state.enrichment.evidenceNotAvailable = true
                return
            }
            state.enrichment.nutrients = ConfirmNutrientSuggestion(
                subjectSHA256: verified.capture.responseSHA256, capture: verified.captureEvidence, inputs: inputs,
                rows: verified.capture.rows, model: verified.capture.model, receivedAt: verified.captureEvidence.capturedAt,
                fromCache: false)
            state.enrichment.leftOut = verified.choices.leftOutKeys
            state.enrichment.seedLeftOut = verified.choices.leftOutKeys
        }
    }

    /// A reopened log's estimate state (estimates on catalogue v2 section 5): its manifest when it
    /// verifies, and the leave-out keys of the effective version's verified evidence. No record is
    /// read: the saved values are shown as saved, also after the corpus pin has moved. Altered
    /// evidence never changes a stored value and never fails the load.
    private func seedEstimates(_ state: inout FoodConfirmationState, saved: StoredFoodConfirmation) {
        let candidate = state.selectedCandidate.candidate
        guard ApprovedEstimateSource.holdsManifest(candidate, evidence: state.input.evidence) else { return }
        bindEstimates(&state, readingRecords: false)
        let manifestHash = ApprovedEstimateSource.verifiedManifest(candidate, evidence: state.input.evidence, digester: digester)?
            .evidence.byteHash
        switch ApprovedEstimateSource.leftOut(resolutionVersionID: saved.resolutionVersion.resolutionVersionID,
                                              manifestHash: manifestHash, evidence: state.input.evidence, digester: digester) {
        case .none: state.estimateSeed = ApprovedEstimateSeed(evidenceAvailable: manifestHash != nil)
        case let .keys(keys): state.estimateSeed = ApprovedEstimateSeed(leftOut: keys, evidenceAvailable: manifestHash != nil)
        case .unavailable: state.estimateSeed = ApprovedEstimateSeed(evidenceAvailable: false)
        }
        if !state.estimateSeed.evidenceAvailable { state.estimateSeed.leftOut = [] }
        state.leftOutEstimates = state.estimateSeed.leftOut
    }

    /// Input for logging a saved entry's food again as a new entry (recent foods). The source
    /// candidate is restored and re-verified exactly as on reopen (reviewed web manifests are
    /// rehashed and rebound); the saved product identity, corrections, decisions and the saved
    /// edible quantity are not carried. Expectations are the source candidate's own, as on the
    /// search route (a reviewed web candidate's edible quantity is always unknown).
    public func relogInput(_ saved: StoredFoodConfirmation) throws -> PopulatedFoodConfirmation {
        let restored = try restoredConfirmationInput(saved)
        var source = restored.candidates[0]
        // A new log built from a saved decision drops that decision's leave-out evidence: earlier
        // leave-outs are not carried, and the capture manifest stays (estimates on catalogue v2 section 5).
        // Confirm enrichment (CE1 section 5a): the earlier A and B capture and choices IDs are dropped too.
        let leftOutIDs = Set(restored.evidence.filter(ApprovedEstimateSource.isLeftOut).map(\.evidenceID))
            .union(ConfirmEnrichmentCitation.enrichmentEvidenceIDs(restored.evidence))
        if !leftOutIDs.isEmpty {
            let kept = try ProviderNeutralCandidate(
                sourceReleaseID: source.candidate.sourceReleaseID, recordID: source.candidate.recordID,
                identity: source.candidate.identity, edibleQuantity: source.candidate.edibleQuantity,
                nutrients: source.candidate.nutrients,
                evidenceIDs: source.candidate.evidenceIDs.filter { !leftOutIDs.contains($0) },
                matchMetadata: source.candidate.matchMetadata)
            source = try PopulatedFoodCandidate(candidate: kept, name: source.name, brand: source.brand, variant: source.variant,
                barcode: source.barcode, itemClass: source.itemClass, packFacts: source.packFacts)
        }
        return try PopulatedFoodConfirmation(evidence: restored.evidence.filter { !leftOutIDs.contains($0.evidenceID) },
            sourceReleases: restored.sourceReleases,
            candidates: [source], expectedIdentity: source.candidate.identity, expectedEdibleQuantity: source.candidate.edibleQuantity)
    }

    /// Input for logging a favourite's pinned entry again (food quick add contract v1). The same
    /// restore and re-verification as `relogInput`, over the pinned immutable version, with the
    /// source candidate's library aliases stripped so quick adds never grow the personal library.
    public func favouriteInput(_ pinned: StoredFoodConfirmation) throws -> PopulatedFoodConfirmation {
        let input = try relogInput(pinned)
        let source = input.candidates[0]
        guard let metadata = source.candidate.matchMetadata, !metadata.libraryAliases.isEmpty else { return input }
        let stripped = try ProviderNeutralCandidate(
            sourceReleaseID: source.candidate.sourceReleaseID, recordID: source.candidate.recordID,
            identity: source.candidate.identity, edibleQuantity: source.candidate.edibleQuantity,
            nutrients: source.candidate.nutrients, evidenceIDs: source.candidate.evidenceIDs,
            matchMetadata: CandidateMatchMetadata(methodVersion: metadata.methodVersion, score: metadata.score,
                materialDifferences: metadata.materialDifferences, libraryAliases: []))
        let candidate = try PopulatedFoodCandidate(candidate: stripped, name: source.name, brand: source.brand,
            variant: source.variant, barcode: source.barcode, itemClass: source.itemClass, packFacts: source.packFacts)
        return try PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: input.sourceReleases,
            candidates: [candidate], expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
    }

    /// The pinned entry of a favourite, read by its immutable log item version.
    public func pinnedConfirmation(_ logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? {
        guard let stored = try reader.foodConfirmation(logItemVersionID: logItemVersionID) else { return nil }
        try stored.logItemVersion.validateWeightDeclaration(emptyPlate: stored.plateWeightVersion)
        return stored
    }

    /// A fresh, unsaved state for re-logging a saved entry: Confirm as a new entry with only the
    /// last entered value and unit prefilled. Nothing is saved until Log.
    public func relogState(logItemID: LogItemID) throws -> FoodConfirmationState? {
        guard let saved = try reader.foodConfirmation(logItemID: logItemID) else { return nil }
        var state = FoodConfirmationState(input: try relogInput(saved), prefillSourceQuantity: false)
        // #470 rule 3: fill-only food details carry, applied before the amount and guide are restored.
        Self.applyCarriedFill(from: saved, to: &state)
        let last = Self.lastEnteredAmount(saved.logItemVersion, conversion: saved.quantityConversion)
        state.quantity = FoodQuantityDraft(value: last.value, unit: last.unit)
        // A typical-weight entry relogs at its saved size; Confirm keeps it only while still offered.
        if let conversion = saved.quantityConversion, CountPortionGuideCode.entry(conversion.methodVersion) != nil, last.unit == .count {
            state.quantity.portionGuideCode = conversion.methodVersion
        }
        return state
    }

    /// Applies the food details a saved entry filled in (docs/confirm-rules-review-v1.md rule 3),
    /// through the ordinary correction action, when they may be carried. Visible on Confirm.
    public static func applyCarriedFill(from saved: StoredFoodConfirmation, to state: inout FoodConfirmationState) {
        guard let carried = FoodDetailsFillPolicy.carriedFill(from: saved, into: state) else { return }
        let decision = state.decision
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(carried))
        // Carrying is not acceptance: Log stays the explicit action.
        state.decision = decision
        state.correctionOrigin = .carried
    }

    /// The amount as the user entered it: the original input of a weight declaration, the source
    /// quantity of a conversion, or otherwise the edible quantity. Value and unit only.
    public static func lastEnteredAmount(_ log: LogItemVersion, conversion: QuantityConversionVersion?) -> (value: Double, unit: QuantityUnit) {
        if let original = log.weightDeclaration?.originalInput { return (original.value, original.unit) }
        if let conversion { return (conversion.sourceQuantity.value, conversion.sourceQuantity.unit) }
        return (log.edibleQuantity.value, log.edibleQuantity.unit)
    }

    /// Estimate status of a saved entry, recomputed from its stored source evidence and decisions.
    public func isEstimate(_ stored: StoredFoodConfirmation) throws -> Bool {
        FoodEntryEstimateStatus.isEstimate(stored, restoredInput: try restoredConfirmationInput(stored))
    }

    static func editReason(previous: LogItemVersion, occurredAt: Date, edibleQuantity: PositiveQuantity,
                           declaration: EdibleWeightDeclaration?, conversionID: QuantityConversionVersionID?,
                           plateID: PlateWeightVersionID?) throws -> LedgerText {
        let timeChanged = previous.occurredAt != occurredAt
        let quantityChanged = previous.edibleQuantity != edibleQuantity || previous.weightDeclaration != declaration
            || previous.quantityConversionVersionID != conversionID || previous.plateWeightVersionID != plateID
        if timeChanged && !quantityChanged { return try LedgerText("Confirmation time correction") }
        if timeChanged { return try LedgerText("Confirmation time, quantity or plate correction") }
        return try LedgerText("Confirmation quantity or plate correction")
    }

    /// Reopen and idempotent recovery share the same retained-source admission.
    private func restoredConfirmationInput(_ saved: StoredFoodConfirmation) throws -> PopulatedFoodConfirmation {
        // The immutable source candidate and the user-corrected saved product are distinct.
        // A corrected fortified category cannot be paired with an originally unknown source identity.
        let original = saved.candidateDecision.candidate
        let sourceItemClass: ItemClass
        if original.identity.fortification == .fortified {
            sourceItemClass = saved.productVersion.itemClass == .supplement ? .supplement : .fortifiedFood
        } else {
            sourceItemClass = saved.productVersion.itemClass == .fortifiedFood ? .food : saved.productVersion.itemClass
        }
        let populated = try PopulatedFoodCandidate(
            candidate: original,
            name: saved.productVersion.name,
            brand: saved.productVersion.brand,
            variant: saved.productVersion.variant,
            barcode: saved.productVersion.barcode,
            itemClass: sourceItemClass,
            packFacts: saved.productVersion.packFacts
        )
        var input = try PopulatedFoodConfirmation(
            evidence: saved.evidence,
            sourceReleases: saved.sourceReleases,
            candidates: [populated],
            expectedIdentity: saved.productVersion.identity,
            expectedEdibleQuantity: .known(
                saved.logItemVersion.edibleQuantity,
                conversionVersionID: saved.logItemVersion.quantityConversionVersionID
            )
        )
        // An estimate layer or a cocoa assertion exists only on a label entry (rule 1) or an Open
        // Food Facts product (off-label-estimate-v1 rules 1 and 2). For the product, the stored
        // candidate is the evidence of record: the resolution must be its merge with the stored
        // layer. An entry without a layer keeps exactly the path it had before.
        if !LabelSourceAdmission.applies(input, candidate: populated),
           saved.estimate != nil || saved.assertions.contains(where: { $0.labelEstimate != nil }) {
            guard OpenFoodFactsEstimateSource.applies(input, candidate: populated),
                  saved.productVersion.identity.servingBasis == populated.candidate.identity.servingBasis,
                  let expected = try? LabelEstimateLayer.expectedNutrients(saved, label: populated),
                  ConfirmEnrichmentCitation.replacingOpenRouterEstimates(saved.resolutionVersion.nutrients, from: expected) == expected else {
                throw FoodLedgerStoreError.integrityFailure("label estimate layer on an entry that is not a label or a matching Open Food Facts product")
            }
        }
        if FoodReviewedWebProposalPolicy.applies(input, candidate: populated) {
            guard FoodReviewedWebProposalPolicy.manifestDigestIsValid(evidence: input.evidence,
                    releases: input.sourceReleases, candidate: populated.candidate, digester: digester),
                  let restored = try FoodReviewedWebProposalPolicy.restoredSourceCandidate(input, candidate: populated),
                  saved.resolutionVersion.nutrients == restored.candidate.nutrients,
                  saved.productVersion.identity.servingBasis == restored.candidate.identity.servingBasis else {
                throw FoodLedgerStoreError.integrityFailure("reviewed web source manifest does not match the retained candidate")
            }
            input = try PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: input.sourceReleases,
                candidates: [restored], expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
        }
        if LabelSourceAdmission.route(input, candidate: input.candidates[0]) == .photo {
            // The label photo route, verified against its stored manifest, never re-read.
            guard let restored = try? LabelPhotoSource.restoredSourceCandidate(input, candidate: input.candidates[0]),
                  LabelSourceAdmission.verify(input, candidate: restored, encoder: encoder, digester: digester,
                                              conversions: pastedLabelConversions),
                  saved.resolutionVersion.nutrients == (try LabelEstimateLayer.expectedNutrients(saved, label: restored)),
                  saved.productVersion.identity.servingBasis == restored.candidate.identity.servingBasis else {
                throw FoodLedgerStoreError.integrityFailure("label photo manifest does not match the retained candidate")
            }
            input = try PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: input.sourceReleases,
                candidates: [restored], expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
        } else if LabelSourceAdmission.applies(input, candidate: input.candidates[0]) {
            // Verified against the stored manifest, never a re-parse. The source candidate's
            // name, brand and class are restored from the manifest, not from the saved product.
            guard let restored = try? PastedLabelSource.restoredSourceCandidate(input, candidate: input.candidates[0]),
                  LabelSourceAdmission.verify(input, candidate: restored, encoder: encoder, digester: digester,
                                              conversions: pastedLabelConversions),
                  saved.resolutionVersion.nutrients == (try LabelEstimateLayer.expectedNutrients(saved, label: restored)),
                  saved.productVersion.identity.servingBasis == restored.candidate.identity.servingBasis else {
                throw FoodLedgerStoreError.integrityFailure("pasted label manifest does not match the retained candidate")
            }
            input = try PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: input.sourceReleases,
                candidates: [restored], expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
        }
        return input
    }

    private func makeConversion(
        _ draft: FoodQuantityDraft,
        entered: PositiveQuantity,
        previous: StoredFoodConfirmation?,
        at date: Date, sourceRecipe: Bool = false, state: FoodConfirmationState
    ) throws -> (version: QuantityConversionVersion?, isNew: Bool) {
        if draft.conversion == nil, let code = draft.portionGuideCode, entered.unit == .count, !sourceRecipe {
            return try makeGuideConversion(code: code, entered: entered, previous: previous, at: date, state: state)
        }
        guard let value = draft.conversion else {
            if entered.unit == .count && !sourceRecipe { throw FoodQuantityValidationError.missingConversion }
            return (nil, false)
        }
        if let old = previous?.quantityConversion,
           FoodLogEditComparison.reusesConversion(old, entered: entered, draft: value) {
            return (old, false)
        }
        // count-conversion-method-v1: the method namespace is closed; there is no estimate code.
        guard CountConversionMethod.admits(value.methodVersion) else { throw FoodConfirmationSaveError.invalidQuantity }
        // count-portion-estimate-v1 (C9): a guide code only ever comes from the selected size,
        // resolved below; a conversion draft naming one is refused.
        guard !CountPortionGuideCode.isGuideCode(value.methodVersion) else { throw FoodConfirmationSaveError.invalidQuantity }
        return (try QuantityConversionVersion(
            quantityConversionVersionID: ids.makeID(QuantityConversionVersionTag.self),
            ordinal: VersionOrdinal((previous?.quantityConversion?.ordinal.value ?? 0) + 1),
            supersedesQuantityConversionVersionID: previous?.quantityConversion?.quantityConversionVersionID,
            sourceQuantity: entered,
            convertedQuantity: value.convertedQuantity,
            methodVersion: value.methodVersion,
            sourceReleaseID: value.sourceReleaseID,
            evidenceID: value.evidenceID,
            createdAt: date
        ), true)
    }

    /// count-portion-estimate-v1 (C9, gate F4): the service resolves the selected size through its
    /// own port and writes count × that size's grams under the size's code and the guide release.
    /// An unchanged re-save keeps the stored conversion, even after a guide was withdrawn.
    private func makeGuideConversion(
        code: LedgerText, entered: PositiveQuantity, previous: StoredFoodConfirmation?,
        at date: Date, state: FoodConfirmationState
    ) throws -> (version: QuantityConversionVersion?, isNew: Bool) {
        if let previous, let old = previous.quantityConversion, old.methodVersion == code, old.sourceQuantity == entered,
           old.sourceReleaseID?.value.hasPrefix(CountPortionGuideCode.releasePrefix) == true,
           // Only for the same record: another candidate resolves through the port.
           state.selectedCandidate.candidate.recordID == previous.candidateDecision.candidate.recordID,
           state.selectedCandidate.candidate.sourceReleaseID == previous.candidateDecision.candidate.sourceReleaseID {
            return (old, false)
        }
        guard CountPortionGuidePolicy.applies(state), let frozen = CountPortionGuideCode.entry(code),
              let guides = portionGuides,
              let entry = try guides.entry(code, for: state.selectedCandidate),
              entry.edibleGramsPerPiece == frozen.grams, entry.size == frozen.size, entry.isDerived == frozen.isDerived,
              let grams = CountPortionGuidePolicy.grams(code: code, count: entered.value) else {
            throw FoodConfirmationSaveError.invalidQuantity
        }
        let release = guides.sourceRelease.sourceReleaseID
        // Gate G4: the guide release must be saved with the entry or already be stored.
        guard release.value.hasPrefix(CountPortionGuideCode.releasePrefix),
              try state.input.sourceReleases.contains(where: { $0.sourceReleaseID == release })
                || reader.sourceRelease(id: release) != nil else {
            throw FoodConfirmationSaveError.invalidQuantity
        }
        return (try QuantityConversionVersion(
            quantityConversionVersionID: ids.makeID(QuantityConversionVersionTag.self),
            ordinal: VersionOrdinal((previous?.quantityConversion?.ordinal.value ?? 0) + 1),
            supersedesQuantityConversionVersionID: previous?.quantityConversion?.quantityConversionVersionID,
            sourceQuantity: entered,
            convertedQuantity: PositiveQuantity(value: grams, unit: .grams),
            methodVersion: code,
            sourceReleaseID: release,
            evidenceID: nil,
            createdAt: date
        ), true)
    }

    private func makePlate(
        _ choice: PlateWeightChoice,
        previous: StoredFoodConfirmation?,
        at date: Date
    ) throws -> (newPlate: Plate?, version: PlateWeightVersion?, isNew: Bool) {
        switch choice {
        case .foodOnly:
            return (nil, nil, false)
        case .missing:
            throw FoodQuantityValidationError.missingPlateWeight
        case let .saved(version):
            return (nil, version, false)
        case let .new(emptyWeight, superseding):
            let plate: Plate
            if let existing = previous?.plate {
                plate = existing
            } else {
                plate = Plate(plateID: try ids.makeID(PlateTag.self), createdAt: date)
            }
            let version = try PlateWeightVersion(
                plateWeightVersionID: ids.makeID(PlateWeightVersionTag.self),
                plateID: plate.plateID,
                ordinal: VersionOrdinal((superseding?.ordinal.value ?? 0) + 1),
                supersedesPlateWeightVersionID: superseding?.plateWeightVersionID,
                emptyWeight: emptyWeight,
                createdAt: date
            )
            return (previous?.plate == nil ? plate : nil, version, true)
        }
    }

    /// Exactly one assertion per save. The reason and claim strings are persisted,
    /// versioned data (food_confirmation_v5), not UI copy.
    private func makeAssertion(
        state: FoodConfirmationState,
        selected: PopulatedFoodCandidate,
        previous: StoredFoodConfirmation?,
        record: FoodLogDecisionRecord?,
        labelEstimate: LabelEstimateAssertion? = nil,
        leftOut: Set<NutrientKey>? = nil,
        enrichmentLeftOut: Set<NutrientKey>? = nil,
        at date: Date
    ) throws -> UserAssertion? {
        let version = FoodConfirmationPolicy.version
        let reason: LedgerText
        let claim: LedgerText
        // The decision record a leave-out-only save of a reopened log carries: the saved version's.
        var carried: FoodLogDecisionRecord?
        // A leave-out on a new log keeps the texts of its own case and names the keys after them.
        let suffix = leftOut.map(ApprovedEstimateLeaveOutText.claimSuffix) ?? ""
        if let correction = state.correction {
            reason = correction.reason
            claim = try LedgerText("Corrected populated confirmation for \(selected.name.value)")
        } else if let previous {
            if let enrichmentLeftOut {
                // Gate section 2.4a: the B texts, with the approved suffix when both change in one save.
                reason = try LedgerText(OpenRouterEstimateChoicesText.reason)
                claim = try LedgerText(OpenRouterEstimateChoicesText.claim(enrichmentLeftOut) + suffix)
            } else {
                guard let leftOut else { return nil }
                reason = try LedgerText(ApprovedEstimateLeaveOutText.reason)
                claim = try LedgerText(ApprovedEstimateLeaveOutText.claim(leftOut))
            }
            carried = previous.assertions.last(where: { $0.confirmation != nil })?.confirmation
        } else if state.isGenericEstimate {
            reason = try LedgerText("Explicitly accepted generic composition estimate; unknown source details remain unknown")
            let base = "Accepted estimate under \(version); not verified product identity"
            claim = try LedgerText((record.map { base + "; decisions: " + $0.claimList } ?? base) + suffix)
        } else if let record {
            reason = try LedgerText("Logged with inline decisions under \(version)")
            claim = try LedgerText("Logged under \(version); decisions: " + record.claimList + suffix)
        } else if let leftOut {
            reason = try LedgerText(ApprovedEstimateLeaveOutText.reason)
            claim = try LedgerText(ApprovedEstimateLeaveOutText.claim(leftOut))
        } else if let labelEstimate {
            // The save's single assertion carries the cocoa percentage (label-estimate-merge-v1).
            reason = try LedgerText("Chose an estimate for unprinted nutrients under \(labelEstimate.mergeVersion.value)")
            claim = try LedgerText("Cocoa percentage on the pack: \(labelEstimate.cocoaPercent.rounded() == labelEstimate.cocoaPercent ? String(Int(labelEstimate.cocoaPercent)) : String(labelEstimate.cocoaPercent))% (\(labelEstimate.cocoaPercentOrigin.rawValue))")
        } else {
            return nil
        }
        return UserAssertion(
            assertionID: try ids.makeID(AssertionTag.self),
            evidenceID: selected.candidate.evidenceIDs.first,
            supersedesAssertionID: previous?.assertions.last?.assertionID,
            author: .user,
            createdAt: date,
            reason: reason,
            claim: claim,
            confirmation: state.correction == nil ? record ?? carried : nil,
            // Only a layer the save admitted reaches here: none after a label correction, and an
            // identity-only correction of an Open Food Facts product keeps it (decision 6).
            labelEstimate: labelEstimate
        )
    }

    public static func unresolvedIdentity(_ value: DecisiveIdentity) -> [IdentityContradiction] {
        FoodConfirmationPolicy.unresolvedIdentity(value, allowingEstimate: false)
    }
}
