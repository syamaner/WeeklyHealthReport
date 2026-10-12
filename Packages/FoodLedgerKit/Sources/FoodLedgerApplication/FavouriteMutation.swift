import Foundation
import FoodLedgerDomain

/// Favourite records written by one favourite operation, and the favourites member of the
/// canonical projection. Kept outside `LedgerMutation` so every existing encoded mutation,
/// payload hash and projection byte stays unchanged (food quick add contract v1, section 5).
public struct FavouriteMutation: Codable, Equatable, Sendable {
    public var favourites: [FavouriteEntry]
    public var favouriteVersions: [FavouriteVersion]
    public var arrangements: [FavouriteArrangement]

    public init(
        favourites: [FavouriteEntry] = [],
        favouriteVersions: [FavouriteVersion] = [],
        arrangements: [FavouriteArrangement] = []
    ) {
        self.favourites = favourites
        self.favouriteVersions = favouriteVersions
        self.arrangements = arrangements
    }

    public var isEmpty: Bool { favourites.isEmpty && favouriteVersions.isEmpty && arrangements.isEmpty }

    public var recordCount: Int { favourites.count + favouriteVersions.count + arrangements.count }

    /// The favourite, favourite version and arrangement version IDs, sorted.
    public var affectedIDs: [String] {
        (favourites.map(\.favouriteID.rawValue)
            + favouriteVersions.map(\.favouriteVersionID.rawValue)
            + arrangements.map(\.arrangementVersionID.rawValue)).sorted()
    }
}
