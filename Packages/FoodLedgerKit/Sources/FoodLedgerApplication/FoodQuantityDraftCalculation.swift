import FoodLedgerDomain

public enum DirectWeightError: Error { case missingBasis, invalidTotal, needsReconfirmation }

extension FoodQuantityDraft {
    public func declaration() throws -> EdibleWeightDeclaration? {
        guard invalidOriginalAmountText != true else {
            throw FoodConfirmationSaveError.invalidQuantity
        }
        guard let directWeight else { return nil }
        guard !directWeight.needsReconfirmation else { throw DirectWeightError.needsReconfirmation }
        guard let basis = directWeight.basis else { throw DirectWeightError.missingBasis }
        guard let total = directWeight.totalGrams,
            let grams = try? PositiveQuantity(value: total, unit: .grams)
        else { throw DirectWeightError.invalidTotal }
        let original: PositiveQuantity?
        if let value {
            guard let entered = try? PositiveQuantity(value: value, unit: unit) else {
                throw FoodConfirmationSaveError.invalidQuantity
            }
            original = entered
        } else {
            original = nil
        }
        return try EdibleWeightDeclaration(basis: basis, total: grams, originalInput: original)
    }

    public func calculationInput() throws -> PositiveQuantity {
        guard invalidOriginalAmountText != true else {
            throw FoodConfirmationSaveError.invalidQuantity
        }
        if let directWeight {
            guard let total = directWeight.totalGrams,
                let grams = try? PositiveQuantity(value: total, unit: .grams)
            else { throw DirectWeightError.invalidTotal }
            return grams
        }
        guard let value, let entered = try? PositiveQuantity(value: value, unit: unit) else {
            throw FoodConfirmationSaveError.invalidQuantity
        }
        return entered
    }

    /// Preview and saving use the same edible-quantity calculation, without allocating persisted IDs.
    public func calculatedEdibleQuantity() throws -> PositiveQuantity {
        _ = try declaration()
        let entered = try calculationInput()
        switch plateChoice {
        case .foodOnly:
            if directWeight != nil { return entered }
            if let conversion {
                guard conversion.convertedQuantity != entered else {
                    throw FoodLedgerValidationError.invalidUnit
                }
                return conversion.convertedQuantity
            }
            guard entered.unit != .count else {
                throw FoodQuantityValidationError.missingConversion
            }
            return entered
        case .missing: throw FoodQuantityValidationError.missingPlateWeight
        case .saved(let plate):
            return try FoodQuantityCalculator.subtractPlate(total: entered, emptyPlate: plate)
        case .new(let emptyWeight, _):
            return try FoodQuantityCalculator.subtractPlate(
                total: entered, emptyWeight: emptyWeight)
        }
    }
}
