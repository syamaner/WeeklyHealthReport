import Foundation
import FoodLedgerDomain

/// Closed, typed reasons that block the Log action. Produced only by `FoodLogPolicy`;
/// presentation renders them generically and the save service enforces the same list.
public enum FoodLogRequirement: Equatable, Hashable, Sendable {
    case decideDifference(IdentityContradiction)
    case sourceIdentityMissing([IdentityContradiction])
    case amountMissing
    case amountTextInvalid
    case recipeServingsRequired
    case sourceServingsRequired
    case measuredWeightMissing
    case weightBasisMissing
    case retainedWeightNeedsConfirmation
    case countNeedsMeasuredAmount
    case emptyPlateWeightMissing
    case plateNeedsGramTotal
    case plateNotLighterThanTotal
    case occurredAtInFuture
    case occurredAtTooEarly
}

/// Pure food_confirmation_v5 policy shared by the view model and the save service.
public enum FoodLogPolicy {
    public static let backdatingDays = 7

    public static func requirements(_ state: FoodConfirmationState, now: Date, calendar: Calendar) -> [FoodLogRequirement] {
        var result = pendingDifferences(state).filter { state.decisions[$0] == nil }.map(FoodLogRequirement.decideDifference)
        let missing = state.unresolvedIdentity
        if !missing.isEmpty { result.append(.sourceIdentityMissing(missing)) }
        let quantity = state.quantity
        if quantity.invalidOriginalAmountText == true {
            result.append(.amountTextInvalid)
        } else if quantity.directWeight == nil || quantity.value != nil {
            if let amount = quantity.value, amount.isFinite, amount > 0 {} else { result.append(.amountMissing) }
        }
        let servingMisuse = quantity.unit != .count || quantity.directWeight != nil
            || quantity.conversion != nil || quantity.plateChoice != .foodOnly
        if state.isSourceRecipe && servingMisuse { result.append(.recipeServingsRequired) }
        if state.usesSourceDeclaredServing && !state.isSourceRecipe && servingMisuse { result.append(.sourceServingsRequired) }
        if state.pastedLabelServingMisuse { result.append(.sourceServingsRequired) }
        if let direct = quantity.directWeight {
            if direct.totalGrams.map({ !$0.isFinite || $0 <= 0 }) ?? true { result.append(.measuredWeightMissing) }
            if direct.basis == nil { result.append(.weightBasisMissing) }
            if direct.needsReconfirmation { result.append(.retainedWeightNeedsConfirmation) }
        }
        if quantity.directWeight == nil && quantity.unit == .count && quantity.conversion == nil && !state.usesSourceDeclaredServing
            && !state.logsPastedLabelServings {
            result.append(.countNeedsMeasuredAmount)
        }
        result += plateRequirements(quantity)
        if let time = timeRequirement(state, now: now, calendar: calendar) { result.append(time) }
        return result
    }

    /// Differences the user must decide inline. Today's bypasses are kept exactly: a reopened
    /// entry or an applied correction is not asked. A facet already blocked as missing source
    /// identity is not asked either, because no inline answer can resolve it.
    public static func pendingDifferences(_ state: FoodConfirmationState) -> [IdentityContradiction] {
        guard state.reopened == nil, state.correction == nil else { return [] }
        let missing = Set(state.unresolvedIdentity)
        return state.materialDifferences.filter { !missing.contains($0) }
    }

    public static func sourceState(_ state: FoodConfirmationState, facet: IdentityContradiction) -> FoodLogSourceState {
        FoodLogSourceState(facet: facet, identity: state.selectedCandidate.candidate.identity,
            edibleQuantity: state.selectedCandidate.candidate.edibleQuantity)
    }

    public static func offeredChoices(_ state: FoodConfirmationState, facet: IdentityContradiction) -> [FoodLogDecisionChoice] {
        FoodLogFacetDecision.offeredChoices(facet: facet, sourceState: sourceState(state, facet: facet))
    }

    /// The typed record for the current decisions, or nil when there are none.
    /// Throws when decisions are stale, extra, missing or not offered for the selected source.
    public static func decisionRecord(_ state: FoodConfirmationState) throws -> FoodLogDecisionRecord? {
        let pending = pendingDifferences(state)
        guard Set(state.decisions.keys) == Set(pending) else { throw FoodConfirmationSaveError.staleDecisions }
        guard !pending.isEmpty else { return nil }
        do {
            return try FoodLogDecisionRecord(policyVersion: LedgerText(FoodLogDecisionRecord.currentPolicyVersion),
                decisions: IdentityContradiction.allCases.filter(pending.contains).map { facet in
                    try FoodLogFacetDecision(facet: facet, sourceState: sourceState(state, facet: facet),
                        choice: state.decisions[facet]!)
                })
        } catch { throw FoodConfirmationSaveError.staleDecisions }
    }

    /// Whether saving this state writes an estimate. One rule shared with `FoodEntryEstimateStatus`:
    /// a generic composition source (regardless of any identity correction), or any non-matching or
    /// uncertain inline decision. A reopened entry without a new product version keeps its saved status.
    /// Drives the primary-screen notice and the D6 alias rule.
    public static func savesEstimate(_ state: FoodConfirmationState) -> Bool {
        if let reopened = state.reopened, state.correction == nil {
            return FoodEntryEstimateStatus.isEstimate(reopened, restoredInput: state.input)
        }
        return FoodEntryEstimateStatus.isEstimate(
            sourceIsGeneric: state.isGenericEstimate,
            identity: state.correction?.identity ?? state.selectedCandidate.candidate.identity,
            decisions: pendingDifferences(state).compactMap { state.decisions[$0] })
    }

    // MARK: When

    /// Start of the local day `backdatingDays` before today, in the calendar's time zone,
    /// computed with a Gregorian calendar so display calendars cannot change the window.
    public static func windowStart(now: Date, calendar: Calendar) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let today = gregorian.startOfDay(for: now)
        return gregorian.date(byAdding: .day, value: -backdatingDays, to: today) ?? today
    }

    /// A chosen time differing from the stored instant must lie within [windowStart, now].
    public static func timeRequirement(_ state: FoodConfirmationState, now: Date, calendar: Calendar) -> FoodLogRequirement? {
        guard let chosen = state.occurredAt, chosen != state.reopened?.logItemVersion.occurredAt else { return nil }
        if chosen > now { return .occurredAtInFuture }
        if chosen < windowStart(now: now, calendar: calendar) { return .occurredAtTooEarly }
        return nil
    }

    private static func plateRequirements(_ quantity: FoodQuantityDraft) -> [FoodLogRequirement] {
        guard quantity.plateChoice != .foodOnly else { return [] }
        if case .missing = quantity.plateChoice { return [.emptyPlateWeightMissing] }
        guard let entered = try? quantity.calculationInput() else { return [] }
        guard entered.unit == .grams else { return [.plateNeedsGramTotal] }
        let emptyWeight: Double
        switch quantity.plateChoice {
        case let .saved(plate): emptyWeight = plate.emptyWeight.value
        case let .new(weight, _): emptyWeight = weight.value
        default: return []
        }
        return entered.value <= emptyWeight ? [.plateNotLighterThanTotal] : []
    }
}

/// Pure projection: whether a saved entry is a labelled estimate. Legacy closest-match
/// entries are not relabelled unless the generic-estimate rule holds for their stored source.
public enum FoodEntryEstimateStatus {
    /// The single estimate rule: a generic composition source whose saved identity still has an
    /// unknown decisive detail (the v2 unknown-identity estimate, whether or not a correction was
    /// applied), or any non-matching or uncertain decision. A generic match whose identity the user
    /// fully resolved keeps v2's known-identity exact reuse.
    public static func isEstimate(sourceIsGeneric: Bool, identity: DecisiveIdentity, decisions: [FoodLogDecisionChoice]) -> Bool {
        let unresolved = !FoodConfirmationPolicy.unresolvedIdentity(identity, allowingEstimate: false).isEmpty
        return (sourceIsGeneric && unresolved) || decisions.contains { $0.isEstimate }
    }

    /// Status of the current saved version. Assertions are those of the current product and
    /// resolution versions, so a later correction (which carries no decisions) is an estimate
    /// only when its source is generic.
    public static func isEstimate(_ stored: StoredFoodConfirmation, restoredInput: PopulatedFoodConfirmation) -> Bool {
        let generic = restoredInput.candidates.first.map { FoodConfirmationPolicy.isGenericEstimate(restoredInput, candidate: $0) } ?? false
        return isEstimate(sourceIsGeneric: generic, identity: stored.productVersion.identity,
                          decisions: stored.assertions.flatMap { $0.confirmation?.decisions.map(\.choice) ?? [] })
    }
}
