import Foundation

/// User quantity provenance; independent of nutrient/source provenance.
public enum UserWeightBasis: String, Codable, Sendable, CaseIterable {
    case measured, estimated
}

public struct EdibleWeightDeclaration: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public let basis: UserWeightBasis
    public let total: PositiveQuantity
    public let originalInput: PositiveQuantity?

    public init(basis: UserWeightBasis, total: PositiveQuantity, originalInput: PositiveQuantity?)
        throws
    {
        guard total.unit == .grams else { throw FoodLedgerValidationError.invalidUnit }
        _ = try PositiveQuantity(value: total.value, unit: total.unit)
        if let originalInput {
            _ = try PositiveQuantity(value: originalInput.value, unit: originalInput.unit)
        }
        version = Self.currentVersion
        self.basis = basis
        self.total = total
        self.originalInput = originalInput
    }

    private enum CodingKeys: String, CodingKey { case version, basis, total, originalInput }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .version) == Self.currentVersion else {
            throw FoodLedgerValidationError.invalidBasis
        }
        try self.init(
            basis: values.decode(UserWeightBasis.self, forKey: .basis),
            total: values.decode(PositiveQuantity.self, forKey: .total),
            originalInput: values.decodeIfPresent(PositiveQuantity.self, forKey: .originalInput))
    }
}
