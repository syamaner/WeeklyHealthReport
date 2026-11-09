import FoodLedgerApplication
import SwiftUI

/// Lets only the newest of overlapping reloads apply its result (#399): each reload takes a
/// token when it begins, and an older read finishing later finds its token superseded.
public struct LatestReloadGate: Equatable, Sendable {
    private var generation = 0

    public init() {}

    public mutating func begin() -> Int {
        generation += 1
        return generation
    }

    public func isCurrent(_ token: Int) -> Bool { token == generation }
}

/// Add food's Recent section as read off the main actor (#399): loading until the first read
/// finishes, failed (never "No recent foods") when the ledger cannot be read, and only the
/// newest of overlapping reads applied, so an older read finishing last never restores an
/// older list. Items and order are the loader's.
@MainActor
public final class AddFoodRecentsModel: ObservableObject {
    @Published public private(set) var recents: [FoodRecentRelogItem] = []
    @Published public private(set) var loaded = false
    @Published public private(set) var failed = false
    private var gate = LatestReloadGate()
    private let load: @MainActor () async -> [FoodRecentRelogItem]?

    /// `load` returns nil when the ledger cannot be read.
    public init(load: @escaping @MainActor () async -> [FoodRecentRelogItem]?) { self.load = load }

    public var state: AddFoodRecentsState { AddFoodRecentsState(recents, loading: !loaded, failed: failed) }

    /// True when this read's result was applied: it was still the newest read and its task
    /// was not cancelled.
    @discardableResult
    public func reload() async -> Bool {
        let token = gate.begin()
        let result = await load()
        guard gate.isCurrent(token), !Task.isCancelled else { return false }
        recents = result ?? []
        failed = result == nil
        loaded = true
        return true
    }
}
