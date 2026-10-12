import Foundation
import FoodLedgerDomain

public enum FavouritesProjectionError: Error, Equatable, Sendable {
    /// Two current versions of one favourite: nothing chooses by ordinal or time.
    case competingFavouriteHeads
    /// Two current arrangement versions.
    case competingArrangementHeads
}

/// One quick-add item: the built-in Water 250 mL (Q7) or a favourite's current version.
public enum QuickAddItem: Equatable, Sendable {
    case builtInWater
    case favourite(FavouriteVersion)

    public static let builtInWaterMillilitres = 250.0
}

/// Favourites in quick-add order (pure). Removed favourites are dropped even if listed; active
/// favourites missing from the arrangement are appended by creation time. The built-in water item
/// is first until any favourite chain bound to plain water exists, active or removed.
public struct FavouritesProjection: Equatable, Sendable {
    public static let todayCount = 4

    /// Active favourites' current versions, in quick-add order.
    public let favourites: [FavouriteVersion]
    /// Every favourite's current version, removed ones included.
    public let heads: [FavouriteID: FavouriteVersion]
    public let arrangement: FavouriteArrangement?
    public let showsBuiltInWater: Bool

    public init(records: FavouriteMutation) throws {
        let superseded = Set(records.favouriteVersions.compactMap(\.supersedesFavouriteVersionID))
        var heads: [FavouriteID: FavouriteVersion] = [:]
        for version in records.favouriteVersions where !superseded.contains(version.favouriteVersionID) {
            guard heads[version.favouriteID] == nil else { throw FavouritesProjectionError.competingFavouriteHeads }
            heads[version.favouriteID] = version
        }
        let supersededArrangements = Set(records.arrangements.compactMap(\.supersedesArrangementVersionID))
        let arrangementHeads = records.arrangements.filter { !supersededArrangements.contains($0.arrangementVersionID) }
        guard arrangementHeads.count <= 1 else { throw FavouritesProjectionError.competingArrangementHeads }
        arrangement = arrangementHeads.first
        self.heads = heads
        let active = heads.filter { $0.value.state == .active }
        let listed = (arrangement?.order ?? []).compactMap { active[$0] }
        let listedIDs = Set(listed.map(\.favouriteID))
        let created = Dictionary(records.favourites.map { ($0.favouriteID, $0.createdAt) }, uniquingKeysWith: { first, _ in first })
        let missing = active.values.filter { !listedIDs.contains($0.favouriteID) }.sorted {
            let left = created[$0.favouriteID] ?? $0.createdAt, right = created[$1.favouriteID] ?? $1.createdAt
            return left == right ? $0.favouriteID.rawValue < $1.favouriteID.rawValue : left < right
        }
        favourites = listed + missing
        showsBuiltInWater = !heads.values.contains { $0.binding == .reference(.plainWaterV1) }
    }

    /// The built-in water item (when shown) followed by the favourites.
    public var quickAddItems: [QuickAddItem] {
        (showsBuiltInWater ? [.builtInWater] : []) + favourites.map(QuickAddItem.favourite)
    }

    /// The first four: Home's chips and "On Today's quick add".
    public var todayItems: [QuickAddItem] { Array(quickAddItems.prefix(Self.todayCount)) }
    /// "Other favourites".
    public var otherItems: [QuickAddItem] { Array(quickAddItems.dropFirst(Self.todayCount)) }

    public func activeFavourite(boundTo logItemVersionID: LogItemVersionID) -> FavouriteVersion? {
        favourites.first { $0.binding == .savedEntry(logItemVersionID) }
    }
}

/// A rebuilt, unsaved quick-add state and where it may be logged.
public struct QuickAddPreparation: Sendable {
    public let item: QuickAddItem
    public let state: FoodConfirmationState
    public let eligibility: QuickAddEligibility
    public let isPlainWater: Bool
    public let label: String
    /// Value and unit offered in the sheet, the default amount.
    public let defaultAmount: FavouriteAmount
}

public enum FavouritesServiceError: Error, Equatable, Sendable {
    /// The pinned entry or its retained source could not be rebuilt and re-verified.
    case sourceUnverifiable
    case unknownFavourite
    case removedFavourite
}

/// Favourite records and quick-add preparation (food quick add contract v1). Favourite operations
/// are separate from log saves; nothing here writes a log, product, resolution or assertion record.
public final class FavouritesService: @unchecked Sendable {
    private let ledger: FoodLedgerService
    private let reader: any FavouriteReading
    private let confirmations: FoodConfirmationService
    private let water: PlainWaterReference
    private let clock: any LedgerClock
    private let ids: any LedgerIDGenerating
    private let digester: any Digesting
    private let calendar: Calendar

    public init(ledger: FoodLedgerService, reader: any FavouriteReading, confirmations: FoodConfirmationService,
                clock: any LedgerClock, ids: any LedgerIDGenerating, digester: any Digesting,
                calendar: Calendar = .autoupdatingCurrent) throws {
        self.ledger = ledger
        self.reader = reader
        self.confirmations = confirmations
        self.clock = clock
        self.ids = ids
        self.digester = digester
        self.calendar = calendar
        water = try PlainWaterReference(digester: digester)
    }

    public func projection() throws -> FavouritesProjection {
        try FavouritesProjection(records: reader.favouriteRecords())
    }

    // MARK: Save as favourite (save_favourite_v1)

    /// Saves a favourite bound to one logged entry version. Returns the existing active favourite
    /// for that version without writing. Otherwise commits with an operation ID derived from the
    /// version, so a retry after a lost response cannot create a second favourite. After removal,
    /// favouriting the same version again writes a new favourite with a fresh operation ID.
    @discardableResult
    public func saveFavourite(logItemVersionID: LogItemVersionID) throws -> FavouriteVersion {
        if let existing = try projection().activeFavourite(boundTo: logItemVersionID) { return existing }
        guard let pinned = try confirmations.pinnedConfirmation(logItemVersionID) else {
            throw FavouritesServiceError.sourceUnverifiable
        }
        let input: PopulatedFoodConfirmation
        do { input = try confirmations.favouriteInput(pinned) } catch { throw FavouritesServiceError.sourceUnverifiable }
        let last = FoodConfirmationService.lastEnteredAmount(pinned.logItemVersion, conversion: pinned.quantityConversion)
        let now = clock.now()
        let entry = FavouriteEntry(favouriteID: try ids.makeID(FavouriteTag.self), createdAt: now)
        let version = try FavouriteVersion(
            favouriteVersionID: ids.makeID(FavouriteVersionTag.self), favouriteID: entry.favouriteID,
            ordinal: VersionOrdinal(1), binding: .savedEntry(logItemVersionID), label: input.candidates[0].name,
            defaultAmount: FavouriteAmount(value: last.value, unit: last.unit), state: .active, createdAt: now)
        let key = try LedgerText("save_favourite_v1:\(logItemVersionID.rawValue)")
        let derived = try Self.derivedOperationID(key.value, digester: digester)
        let operationID = try ledger.hasOperation(derived) ? ids.makeID(OperationTag.self) : derived
        do {
            _ = try ledger.commitFavourites(FavouriteMutation(favourites: [entry], favouriteVersions: [version]),
                                            type: .saveFavourite, operationID: operationID, idempotencyKey: key)
        } catch FoodLedgerStoreError.divergentDuplicateOperation {
            // A concurrent save with the same derived ID won: return its favourite.
            if let existing = try projection().activeFavourite(boundTo: logItemVersionID) { return existing }
            throw FoodLedgerStoreError.divergentDuplicateOperation
        }
        return version
    }

    /// A deterministic operation ID: the first 128 bits of SHA-256 over the idempotency key.
    static func derivedOperationID(_ key: String, digester: any Digesting) throws -> OperationID {
        let hex = Array(try digester.sha256(Data(key.utf8)).value.prefix(32))
        let parts = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }
        return try OperationID(parts.joined(separator: "-"))
    }

    // MARK: Edits (revise_favourite_v1, arrange_favourites_v1)

    public func rename(_ favouriteID: FavouriteID, to label: LedgerText) throws {
        try revise(favouriteID) { head, next in
            try FavouriteVersion(favouriteVersionID: next.id, favouriteID: favouriteID, ordinal: next.ordinal,
                supersedesFavouriteVersionID: head.favouriteVersionID, binding: head.binding, label: label,
                defaultAmount: head.defaultAmount, state: .active, createdAt: next.at)
        }
    }

    public func setDefaultAmount(_ favouriteID: FavouriteID, to amount: FavouriteAmount) throws {
        try revise(favouriteID) { head, next in
            try FavouriteVersion(favouriteVersionID: next.id, favouriteID: favouriteID, ordinal: next.ordinal,
                supersedesFavouriteVersionID: head.favouriteVersionID, binding: head.binding, label: head.label,
                defaultAmount: amount, state: .active, createdAt: next.at)
        }
    }

    /// Writes a `removed` version (a tombstone). No log record is touched.
    public func remove(_ favouriteID: FavouriteID) throws {
        try revise(favouriteID) { head, next in
            try FavouriteVersion(favouriteVersionID: next.id, favouriteID: favouriteID, ordinal: next.ordinal,
                supersedesFavouriteVersionID: head.favouriteVersionID, binding: head.binding, label: head.label,
                defaultAmount: head.defaultAmount, state: .removed, createdAt: next.at)
        }
    }

    private func revise(_ favouriteID: FavouriteID,
                        _ make: (FavouriteVersion, (id: FavouriteVersionID, ordinal: VersionOrdinal, at: Date)) throws -> FavouriteVersion) throws {
        guard let head = try projection().heads[favouriteID] else { throw FavouritesServiceError.unknownFavourite }
        guard head.state == .active else { throw FavouritesServiceError.removedFavourite }
        let version = try make(head, (try ids.makeID(FavouriteVersionTag.self), try VersionOrdinal(head.ordinal.value + 1), clock.now()))
        _ = try ledger.commitFavourites(FavouriteMutation(favouriteVersions: [version]), type: .reviseFavourite,
                                        operationID: ids.makeID(OperationTag.self))
    }

    /// Writes one arrangement version. When the order includes the built-in water item, its
    /// favourite record is written in the same operation (Q7) and the built-in item disappears.
    public func arrange(_ items: [QuickAddItem]) throws {
        let projection = try projection()
        let now = clock.now()
        var created = FavouriteMutation()
        let order: [FavouriteID] = try items.map { item in
            switch item {
            case let .favourite(version): return version.favouriteID
            case .builtInWater:
                let (entry, version) = try builtInWaterRecords(label: LedgerText(PlainWaterReference.name),
                    amount: FavouriteAmount(value: QuickAddItem.builtInWaterMillilitres, unit: .millilitres), state: .active, at: now)
                created.favourites.append(entry); created.favouriteVersions.append(version)
                return entry.favouriteID
            }
        }
        let arrangement = try FavouriteArrangement(
            arrangementVersionID: ids.makeID(FavouriteArrangementVersionTag.self),
            ordinal: VersionOrdinal((projection.arrangement?.ordinal.value ?? 0) + 1),
            supersedesArrangementVersionID: projection.arrangement?.arrangementVersionID, order: order, createdAt: now)
        created.arrangements = [arrangement]
        _ = try ledger.commitFavourites(created, type: created.favourites.isEmpty ? .arrangeFavourites : .saveFavourite,
                                        operationID: ids.makeID(OperationTag.self))
    }

    /// Editing the built-in water item writes its favourite record (Q7).
    public func saveBuiltInWater(label: LedgerText, millilitres: Double) throws {
        let (entry, version) = try builtInWaterRecords(label: label,
            amount: FavouriteAmount(value: millilitres, unit: .millilitres), state: .active, at: clock.now())
        _ = try ledger.commitFavourites(FavouriteMutation(favourites: [entry], favouriteVersions: [version]),
                                        type: .saveFavourite, operationID: ids.makeID(OperationTag.self))
    }

    /// Removing the built-in water item writes its favourite record as a removed version, which
    /// hides the built-in item for good.
    public func removeBuiltInWater() throws {
        let (entry, version) = try builtInWaterRecords(label: LedgerText(PlainWaterReference.name),
            amount: FavouriteAmount(value: QuickAddItem.builtInWaterMillilitres, unit: .millilitres), state: .removed, at: clock.now())
        _ = try ledger.commitFavourites(FavouriteMutation(favourites: [entry], favouriteVersions: [version]),
                                        type: .saveFavourite, operationID: ids.makeID(OperationTag.self))
    }

    private func builtInWaterRecords(label: LedgerText, amount: FavouriteAmount, state: FavouriteState,
                                     at date: Date) throws -> (FavouriteEntry, FavouriteVersion) {
        let entry = FavouriteEntry(favouriteID: try ids.makeID(FavouriteTag.self), createdAt: date)
        let version = try FavouriteVersion(favouriteVersionID: ids.makeID(FavouriteVersionTag.self), favouriteID: entry.favouriteID,
            ordinal: VersionOrdinal(1), binding: .reference(.plainWaterV1), label: label, defaultAmount: amount,
            state: state, createdAt: date)
        return (entry, version)
    }

    // MARK: Quick add

    /// Rebuilds a fresh confirmation for the item with its default amount and Now. Writes nothing.
    public func prepare(_ item: QuickAddItem) throws -> QuickAddPreparation {
        let now = clock.now()
        switch item {
        case .builtInWater:
            let amount = try FavouriteAmount(value: QuickAddItem.builtInWaterMillilitres, unit: .millilitres)
            return preparation(item, state: water.state(millilitres: amount.value), pinned: nil, estimate: false,
                               isPlainWater: true, label: PlainWaterReference.name, amount: amount, now: now)
        case let .favourite(version):
            switch version.binding {
            case .reference(.plainWaterV1):
                return preparation(item, state: water.state(millilitres: version.defaultAmount.value), pinned: nil,
                                   estimate: false, isPlainWater: true, label: version.label.value,
                                   amount: version.defaultAmount, now: now)
            case let .savedEntry(logItemVersionID):
                let pinned: StoredFoodConfirmation
                let input: PopulatedFoodConfirmation
                let estimate: Bool
                do {
                    guard let stored = try confirmations.pinnedConfirmation(logItemVersionID) else {
                        throw FavouritesServiceError.sourceUnverifiable
                    }
                    pinned = stored
                    input = try confirmations.favouriteInput(stored)
                    estimate = try confirmations.isEstimate(stored)
                } catch { throw FavouritesServiceError.sourceUnverifiable }
                var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
                state.quantity = FoodQuantityDraft(value: version.defaultAmount.value, unit: version.defaultAmount.unit)
                return preparation(item, state: state, pinned: pinned, estimate: estimate,
                                   isPlainWater: PlainWaterReference.isPlainWater(pinned.resolutionVersion),
                                   label: version.label.value, amount: version.defaultAmount, now: now)
            }
        }
    }

    private func preparation(_ item: QuickAddItem, state: FoodConfirmationState, pinned: StoredFoodConfirmation?,
                             estimate: Bool, isPlainWater: Bool, label: String, amount: FavouriteAmount,
                             now: Date) -> QuickAddPreparation {
        QuickAddPreparation(item: item, state: state,
            eligibility: QuickAddPolicy.eligibility(pinned: pinned, pinnedIsEstimate: estimate, rebuilt: state, now: now, calendar: calendar),
            isPlainWater: isPlainWater, label: label, defaultAmount: amount)
    }

    /// Whether a favourite's pinned entry is a derived estimate; nil when it cannot be verified.
    public func isEstimate(_ version: FavouriteVersion) -> Bool? {
        guard case let .savedEntry(id) = version.binding else { return false }
        guard let pinned = try? confirmations.pinnedConfirmation(id), (try? confirmations.favouriteInput(pinned)) != nil else { return nil }
        return try? confirmations.isEstimate(pinned)
    }
}
