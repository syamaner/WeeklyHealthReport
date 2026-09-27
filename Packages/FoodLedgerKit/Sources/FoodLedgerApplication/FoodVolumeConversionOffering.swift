import FoodLedgerDomain
import Foundation

/// Offers a separately sourced conversion for a precisely identified food record.
/// An offer does not change the nutrition source or silently convert an amount.
public protocol FoodVolumeConversionOffering: Sendable {
    var sourceRelease: SourceRelease { get }
    var sourceURL: URL { get }
    func offer(for candidate: PopulatedFoodCandidate, original: PositiveQuantity) throws -> QuantityConversionDraft?
}
