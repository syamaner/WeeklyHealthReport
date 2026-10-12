import Foundation
import FoodLedgerDomain

/// Where a Log requirement may be resolved during quick add (contract section 3).
public enum QuickAddRequirementPlacement: Equatable, Sendable {
    /// Blocks Log in the sheet and is fixed inline (amount, time).
    case sheet
    /// Never shown in the sheet: the favourite opens the full Confirm.
    case confirm
}

/// Why a favourite cannot use the one-step sheet.
public enum QuickAddIneligibility: Equatable, Sendable {
    /// The pinned entry is a derived estimate, or the rebuilt state would save one.
    case estimate
    /// The pinned entry carried an identity correction or a re-resolution.
    case corrected
    /// A requirement the sheet cannot resolve (for example a material difference).
    case requirement(FoodLogRequirement)
}

public enum QuickAddEligibility: Equatable, Sendable {
    case sheet
    case confirm(QuickAddIneligibility)
}

/// Pure quick-add policy over `FoodLogPolicy` (application layer). The views render its output;
/// the save service still evaluates `FoodLogPolicy` at save.
public enum QuickAddPolicy {
    /// Q10: the sheet-only bound for a custom plain water amount, in mL.
    public static let maximumCustomWaterMillilitres = 5000.0
    public static let waterPresetsMillilitres: [Double] = [150, 250, 330, 500]

    /// Every requirement case is classified exactly once (contract test 4).
    public static func placement(_ requirement: FoodLogRequirement) -> QuickAddRequirementPlacement {
        switch requirement {
        case .amountMissing, .amountTextInvalid, .occurredAtInFuture, .occurredAtTooEarly:
            return .sheet
        case .decideDifference, .sourceIdentityMissing, .recipeServingsRequired, .sourceServingsRequired,
             .measuredWeightMissing, .weightBasisMissing, .retainedWeightNeedsConfirmation,
             .countNeedsMeasuredAmount, .emptyPlateWeightMissing, .plateNeedsGramTotal, .plateNotLighterThanTotal:
            return .confirm
        }
    }

    /// Whether the pinned entry carried no correction or re-resolution: product version 1, no
    /// correction assertion, a selected (not rejected) candidate decision and an effective
    /// resolution equal to the original one. The rebuilt source candidate drops any correction.
    public static func pinnedIsUncorrected(_ pinned: StoredFoodConfirmation) -> Bool {
        pinned.productVersion.ordinal.value == 1
            && !pinned.assertions.contains { $0.claim.value.hasPrefix(correctionClaimPrefix) }
            && pinned.candidateDecision.outcome != .rejected
            && pinned.logItemVersion.effectiveResolutionVersionID == pinned.logItemVersion.originalResolutionVersionID
    }

    /// The persisted claim prefix `FoodConfirmationService` writes for a correction.
    static let correctionClaimPrefix = "Corrected populated confirmation"

    /// The eligibility union. `pinned` is nil for the plain water reference. `rebuilt` is the
    /// state with the default amount and Now.
    public static func eligibility(pinned: StoredFoodConfirmation?, pinnedIsEstimate: Bool,
                                   rebuilt: FoodConfirmationState, now: Date, calendar: Calendar) -> QuickAddEligibility {
        if pinnedIsEstimate || FoodLogPolicy.savesEstimate(rebuilt) { return .confirm(.estimate) }
        if let pinned, !pinnedIsUncorrected(pinned) { return .confirm(.corrected) }
        if let blocking = FoodLogPolicy.requirements(rebuilt, now: now, calendar: calendar).first(where: { placement($0) == .confirm }) {
            return .confirm(.requirement(blocking))
        }
        return .sheet
    }

    /// Requirements shown in the sheet: the v5 policy plus the Q10 bound for plain water. An
    /// out-of-bound custom water amount is `amountTextInvalid`; Confirm and the service are not bounded.
    public static func sheetRequirements(_ state: FoodConfirmationState, isPlainWater: Bool,
                                         now: Date, calendar: Calendar) -> [FoodLogRequirement] {
        var result = FoodLogPolicy.requirements(state, now: now, calendar: calendar)
        if isPlainWater, !result.contains(.amountTextInvalid), let value = state.quantity.value,
           !(value > 0 && value <= maximumCustomWaterMillilitres) {
            result.removeAll { $0 == .amountMissing }
            result.insert(.amountTextInvalid, at: 0)
        }
        return result
    }
}
