import Foundation
import FoodLedgerDomain

/// One serving policy for every label source (docs/label-photo-ai-prefill-v1.md 4.2 item 3 and
/// 17.20): the pasted label's methods (`pasted-label-serving-v1` to `-v3`, pinned by the reader v3
/// freeze and unchanged), then the label photo's `label-photo-serving-v1`. A candidate is either a
/// pasted label or a photo (`LabelSourceAdmission` refuses a mixed one), so at most one applies.
/// Confirm, the save path, the Food Log and reopen all ask this composite, so a photo entry
/// defaults to servings exactly as a pasted label does.
public enum LabelServingPolicy {
    /// Every servings method a label entry may record (append-only).
    public static let admittedVersions = PastedLabelServingPolicy.admittedVersions + [LabelPhotoServingPolicy.version]

    public static func serving(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> PositiveQuantity? {
        PastedLabelServingPolicy.serving(input, candidate: candidate) ?? LabelPhotoServingPolicy.serving(input, candidate: candidate)
    }

    /// The method a servings amount is recorded under for this selection.
    public static func method(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> String? {
        if let pasted = PastedLabelServingPolicy.method(input, candidate: candidate) { return pasted }
        return LabelPhotoServingPolicy.applies(input, candidate: candidate) ? LabelPhotoServingPolicy.version : nil
    }

    public static func servingsOnly(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        PastedLabelServingPolicy.servingsOnly(input, candidate: candidate) || LabelPhotoServingPolicy.servingsOnly(input, candidate: candidate)
    }

    public static func wholePack(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> PastedLabelWholePack? {
        PastedLabelServingPolicy.wholePack(input, candidate: candidate) ?? LabelPhotoServingPolicy.wholePack(input, candidate: candidate)
    }

    /// Reopen verification of a stored servings conversion, by the method it names.
    public static func verifies(_ stored: QuantityConversionVersion, input: PopulatedFoodConfirmation,
                                candidate: PopulatedFoodCandidate) -> Bool {
        stored.methodVersion.value == LabelPhotoServingPolicy.version
            ? LabelPhotoServingPolicy.verifies(stored, input: input, candidate: candidate)
            : PastedLabelServingPolicy.verifies(stored, input: input, candidate: candidate)
    }

    /// Whether a saved amount was entered in a label's servings: a count recorded through a label
    /// servings method, or a count with no conversion on a label release whose serving has no
    /// weight or volume.
    public static func isServingsAmount(enteredUnit: QuantityUnit, conversion: QuantityConversionVersion?, sourceID: String?) -> Bool {
        guard enteredUnit == .count else { return false }
        if PastedLabelServingPolicy.isServingsAmount(enteredUnit: enteredUnit, conversion: conversion, sourceID: sourceID) { return true }
        if let conversion { return conversion.methodVersion.value == LabelPhotoServingPolicy.version }
        return sourceID == LabelPhotoSource.sourceID
    }
}

extension FoodConfirmationState {
    /// The label serving quantity (pasted or photo) when a label servings method applies.
    public var labelServing: PositiveQuantity? { LabelServingPolicy.serving(input, candidate: selectedCandidate) }

    var labelServingMethod: String? { LabelServingPolicy.method(input, candidate: selectedCandidate) }

    /// Whether the entered amount is in a label's servings.
    var logsLabelServings: Bool { labelServing != nil && quantity.unit == .count }

    /// The pasted rule, for every label method: servings are a plain count, with no direct
    /// weight, plate or conversion other than the method's own; a conversion naming a label
    /// method the selection does not use is never accepted.
    var labelServingMisuse: Bool {
        let method = labelServingMethod
        if let named = quantity.conversion?.methodVersion.value, named != method, LabelServingPolicy.admittedVersions.contains(named) {
            return true
        }
        guard let serving = labelServing else { return false }
        if quantity.unit != .count { return serving.unit == .count }
        return quantity.directWeight != nil || quantity.plateChoice != .foodOnly
            || (quantity.conversion.map { $0.methodVersion.value != method } ?? false)
    }

    /// The quantity the save path records: label servings carry their method's conversion,
    /// recomputed from the count, and none when the serving has no weight or volume.
    func labelPolicyQuantity() throws -> FoodQuantityDraft {
        guard logsLabelServings, let serving = labelServing, let method = labelServingMethod else {
            if let named = quantity.conversion?.methodVersion.value, named != labelServingMethod,
               LabelServingPolicy.admittedVersions.contains(named) {
                throw FoodLedgerValidationError.invalidUnit
            }
            return quantity
        }
        guard !labelServingMisuse else { throw FoodLedgerValidationError.invalidUnit }
        var draft = quantity
        draft.conversion = try PastedLabelServingPolicy.conversion(servings: quantity.calculationInput(), serving: serving,
                                                                   candidate: selectedCandidate, method: method)
        return draft
    }
}
