import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// Re-resolution uses the frozen corpus directly, never a saved-name shortcut.
public final class CoFIDReresolutionProvider: FoodReresolutionProviding, @unchecked Sendable {
    private let search: CoFIDGenericFoodSearch

    public init(ids: any LedgerIDGenerating) throws { search = try CoFIDGenericFoodSearch(ids: ids) }

    public func targets() throws -> [FoodReresolutionTarget] {
        [FoodReresolutionTarget(sourceRelease: search.sourceRelease, methodVersion: try LedgerText(CoFIDGenericFoodSearch.matcherVersion))]
    }

    public func candidates(for record: StoredFoodConfirmation, target: FoodReresolutionTarget, at date: Date) throws -> GenericFoodSearchOutcome {
        guard try targets().contains(target) else { throw FoodReresolutionError.unavailableTarget }
        return try search.search(GenericFoodSearchRequest(
            text: record.productVersion.name,
            // Retrieve within the unchanged basis; the application rejects known
            // contradictions and requires explicit assertions for source gaps.
            // Passing confirmed fields here would discard all unknown-source rows.
            identity: GenericFoodIdentityQuery(servingBasis: record.productVersion.identity.servingBasis),
            capturedAt: date, locale: LedgerText("en_GB")
        ))
    }
}
