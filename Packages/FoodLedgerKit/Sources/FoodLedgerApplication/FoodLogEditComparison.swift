import Foundation
import FoodLedgerDomain

/// One definition of "this edit changes the saved entry" (#197), shared by the Save changes
/// button (`FoodLogPolicy.editChanges`) and the save path's conversion reuse. It gates
/// presentation only: the service still accepts an unchanged save and no requirement is added.
public enum FoodLogEditComparison {
    /// The save path's reuse rule: a stored conversion is reused only when every field matches.
    public static func reusesConversion(_ stored: QuantityConversionVersion?, entered: PositiveQuantity,
                                        draft: QuantityConversionDraft) -> Bool {
        guard let stored else { return false }
        return stored.sourceQuantity == entered
            && stored.convertedQuantity == draft.convertedQuantity
            && stored.methodVersion == draft.methodVersion
            && stored.sourceReleaseID == draft.sourceReleaseID
            && stored.evidenceID == draft.evidenceID
    }

    /// Whether saving `state` would record anything different from the reopened version. A new
    /// entry, or a draft that cannot be calculated, always counts as a change (requirements
    /// then explain what blocks it).
    public static func hasChanges(_ state: FoodConfirmationState) -> Bool {
        guard let stored = state.reopened else { return true }
        if state.correction != nil { return true }
        let log = stored.logItemVersion
        if let occurredAt = state.occurredAt, occurredAt != log.occurredAt { return true }
        switch state.quantity.plateChoice {
        case .new, .missing: return true
        case .foodOnly: if log.plateWeightVersionID != nil { return true }
        case let .saved(version): if version.plateWeightVersionID != log.plateWeightVersionID { return true }
        }
        let declaration: EdibleWeightDeclaration?
        do { declaration = try state.quantity.declaration() } catch { return true }
        if declaration != log.weightDeclaration { return true }
        if declaration == nil {
            if let draft = state.quantity.conversion {
                guard let entered = try? state.quantity.calculationInput(),
                      reusesConversion(stored.quantityConversion, entered: entered, draft: draft),
                      stored.quantityConversion?.quantityConversionVersionID == log.quantityConversionVersionID else { return true }
            } else if log.quantityConversionVersionID != nil {
                return true
            }
        }
        guard let edible = try? state.calculatedEdibleQuantity() else { return true }
        return edible != log.edibleQuantity
    }
}

extension FoodLogPolicy {
    /// Whether an edit differs from the stored version; true for a new entry.
    public static func editChanges(_ state: FoodConfirmationState) -> Bool { FoodLogEditComparison.hasChanges(state) }
}
