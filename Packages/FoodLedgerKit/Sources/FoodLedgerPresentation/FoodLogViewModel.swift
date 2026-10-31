import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// The Food Log's port (#197), owned by its consumer. The composition root forwards it to
/// `FoodLogReadingService`; only application and domain types cross it.
public protocol FoodLogStore: Sendable {
    func day(_ reportingDate: String) async throws -> FoodLogDayContent
    func savedEntry(_ id: LogItemID) async throws -> SavedFoodEntryDetail?
    func remove(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome
    func restore(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome
}

/// Food Log orchestration: day selection, loading states, remove and restore (#197).
@MainActor
public final class FoodLogViewModel: ObservableObject {
    public enum Failure: Equatable, Sendable { case competingVersions, mixedMeal, unreadable }

    public enum Phase: Equatable {
        case loading
        case loaded(FoodLogDayContentSnapshot)
        case failed(Failure)
    }

    @Published public private(set) var phase: Phase = .loading
    @Published public private(set) var selectedKey: String
    @Published public var pendingRemoval: FoodLogDayContent.Entry?
    @Published public var changeAlert: FoodLogChangeOutcome?
    /// True while the first load of a day has run past `slowLoadingDelay` (#354): the loading
    /// state then says so and offers Try again, so the screen never just waits.
    @Published public private(set) var loadingIsSlow = false

    /// How long the loading state waits before it says the load is slow and offers Try again.
    public static let slowLoadingDelay: Duration = .seconds(3)

    private let store: any FoodLogStore
    private let now: @Sendable () -> Date
    private let calendarProvider: () -> Calendar
    /// Read on every use, so a time-zone change (an auto-updating calendar) is seen at once.
    public var calendar: Calendar { calendarProvider() }
    private var loadToken = 0
    /// The key that was today when the log last loaded, so a later midnight or time-zone change
    /// can tell that the user was looking at "today" (the clock has already moved by then).
    private var loadedTodayKey: String?
    private var isChanging = false
    /// Loads started and not yet finished (superseded ones included).
    private var loadsInFlight = 0
    private let sleep: @Sendable (Duration) async -> Void

    public convenience init(store: any FoodLogStore, now: @escaping @Sendable () -> Date, calendar: Calendar,
                            sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.init(store: store, now: now, calendarProvider: { calendar }, sleep: sleep)
    }

    public init(store: any FoodLogStore, now: @escaping @Sendable () -> Date, calendarProvider: @escaping () -> Calendar,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.store = store
        self.now = now
        self.calendarProvider = calendarProvider
        self.sleep = sleep
        selectedKey = FoodLogDayNavigation(now: now(), calendar: calendarProvider()).todayKey
    }

    public var navigation: FoodLogDayNavigation { FoodLogDayNavigation(now: now(), calendar: calendar) }
    public var isToday: Bool { navigation.isToday(selectedKey) }
    public var canMoveForward: Bool { navigation.canMoveForward(from: selectedKey) }
    /// The selected day as a date for display and the picker (noon in the calendar's time zone).
    public var selectedDate: Date { navigation.date(forKey: selectedKey) ?? now() }
    public var latestSelectableDate: Date { now() }
    /// The day Add food carries when opened from here (owner decision D): the selected past day,
    /// or nil on today. Never persisted.
    public var addFoodDayKey: String? { isToday ? nil : selectedKey }
    /// What When will start as for the selected day, read now for the footnote.
    public var addFoodWhen: FoodEntryWhenPrefill {
        FoodEntryWhenPrefill.resolve(dayKey: addFoodDayKey, now: now(), calendar: calendar)
    }
    public var addFoodFootnote: String? { FoodLogText.addFoodFootnote(addFoodWhen, isToday: isToday) }
    /// Whether the Food Log offers Add food for the selected day: false only for a day older than
    /// the backdating window (the same `FoodEntryWhenPrefill` rule Confirm uses), where the view
    /// shows `FoodLogText.addFoodBeyondWindow` instead (owner decision, 14 October 2026).
    public var canAddFoodForSelectedDay: Bool { addFoodWhen != .beyondBackdatingWindow }

    /// Every load ends in `.loaded` or `.failed` for the latest request; an older one that
    /// finishes later changes nothing. While the screen shows `.loading`, a slow load is reported
    /// through `loadingIsSlow` (#354).
    public func load() async {
        loadToken += 1
        let token = loadToken
        let key = selectedKey
        loadedTodayKey = navigation.todayKey
        loadsInFlight += 1
        defer { loadsInFlight -= 1 }
        if case .loaded = phase {} else { phase = .loading }
        loadingIsSlow = false
        watchForSlowLoad(token)
        do {
            let content = try await store.day(key)
            guard token == loadToken else { return }
            phase = .loaded(FoodLogDayContentSnapshot(content))
        } catch {
            guard token == loadToken else { return }
            phase = .failed(Self.failure(error))
        }
        loadingIsSlow = false
    }

    /// Called whenever the loading state is on screen: starts a load if none is running, so the
    /// screen cannot stay in `.loading` when the appearance that should have loaded it was missed
    /// (#354, for example a push that lands during another transition).
    public func ensureLoading() async {
        guard phase == .loading, loadsInFlight == 0 else { return }
        await load()
    }

    private func watchForSlowLoad(_ token: Int) {
        let sleep = sleep
        Task { [weak self] in
            await sleep(Self.slowLoadingDelay)
            guard let self, self.loadToken == token, self.phase == .loading else { return }
            self.loadingIsSlow = true
        }
    }

    public func showDay(_ key: String) async {
        guard key != selectedKey else { return await load() }
        selectedKey = min(key, navigation.todayKey)
        phase = .loading
        await load()
    }

    public func previousDay() async {
        if let key = navigation.previous(selectedKey) { await showDay(key) }
    }

    public func nextDay() async {
        if let key = navigation.next(selectedKey) { await showDay(key) }
    }

    public func returnToToday() async { await showDay(navigation.todayKey) }

    public func choose(_ date: Date) async { await showDay(navigation.clampedKey(for: date)) }

    /// Re-anchors on today after midnight or a time-zone change when the day shown was today at
    /// the last load; a past day stays selected, and no day after today is kept.
    public func refreshAfterTimeChange() async {
        let today = navigation.todayKey
        if selectedKey == loadedTodayKey || selectedKey > today { selectedKey = today }
        await load()
    }

    public func requestRemoval(_ entry: FoodLogDayContent.Entry) { pendingRemoval = entry }

    public func cancelRemoval() { pendingRemoval = nil }

    /// Removes the confirmed entry once, however many times it is pressed. The entry is passed in
    /// (captured when the alert was shown), because the alert's dismissal clears `pendingRemoval`
    /// before the Remove action's task runs (#211, D9).
    public func confirmRemoval(_ entry: FoodLogDayContent.Entry) async {
        guard !isChanging else { return }
        pendingRemoval = nil
        await change { await $0.remove(entry.logItemID, expected: entry.logItemVersionID) }
    }

    public func restore(_ entry: FoodLogDayContent.RemovedEntry) async {
        guard !isChanging else { return }
        await change { await $0.restore(entry.logItemID, expected: entry.logItemVersionID) }
    }

    private func change(_ action: (any FoodLogStore) async -> FoodLogChangeOutcome) async {
        isChanging = true
        defer { isChanging = false }
        let outcome = await action(store)
        if outcome != .applied { changeAlert = outcome }
        await load()
    }

    static func failure(_ error: Error) -> Failure {
        switch error as? FoodIntakeProjectionError {
        case .competingVersions: .competingVersions
        case .unsupportedMixture: .mixedMeal
        default: .unreadable
        }
    }
}

/// An equatable snapshot of a day for view state.
public struct FoodLogDayContentSnapshot: Equatable {
    public let reportingDate: String
    public let totals: [FoodIntakeTotal]?
    public let entries: [FoodLogDayContent.Entry]
    public let removed: [FoodLogDayContent.RemovedEntry]
    public let plainWater: FoodIntakeTotal?
    /// `FoodLogDayContent.showsFoodTotals` (#304): false on a plain-water-only day.
    public let showsFoodTotals: Bool

    public init(_ content: FoodLogDayContent) {
        reportingDate = content.reportingDate
        totals = content.totals
        showsFoodTotals = content.showsFoodTotals
        entries = content.entries
        removed = content.removed
        plainWater = content.plainWater
    }
}

/// The saved entry screen's orchestration (#197). Read-only content loads separately from the
/// edit model, so a source that no longer verifies leaves content and a reason, never a blank.
@MainActor
public final class SavedFoodEntryViewModel: ObservableObject {
    public enum Phase: Equatable {
        case loading
        case loaded
        case missing
        case failed
    }

    @Published public private(set) var phase: Phase = .loading
    @Published public private(set) var detail: SavedFoodEntryDetail?
    @Published public private(set) var editModel: FoodConfirmationViewModel?
    @Published public private(set) var editUnavailable = false
    @Published public var confirmsRemoval = false
    @Published public var changeAlert: FoodLogChangeOutcome?
    /// Set once the entry is removed; the view returns to the Food Log.
    @Published public private(set) var didRemove = false

    public let logItemID: LogItemID
    private let store: any FoodLogStore
    private let reopen: @MainActor () throws -> FoodConfirmationViewModel?
    private var isRemoving = false

    public init(logItemID: LogItemID, store: any FoodLogStore,
                reopen: @escaping @MainActor () throws -> FoodConfirmationViewModel?) {
        self.logItemID = logItemID
        self.store = store
        self.reopen = reopen
    }

    public func load() async {
        if detail == nil { phase = .loading }
        do {
            if let detail = try await store.savedEntry(logItemID) {
                self.detail = detail
                phase = .loaded
            } else {
                detail = nil
                phase = .missing
            }
        } catch {
            phase = detail == nil ? .failed : .loaded
        }
    }

    /// Builds the edit model; when the retained source no longer verifies, Edit is unavailable
    /// and the read-only content stays.
    @discardableResult
    public func beginEdit() -> FoodConfirmationViewModel? {
        do {
            guard let model = try reopen() else { editUnavailable = true; return nil }
            editUnavailable = false
            editModel = model
            return model
        } catch {
            editUnavailable = true
            return nil
        }
    }

    /// After an edit the content reloads and shows the new history row.
    public func finishEdit() async {
        editModel = nil
        await load()
    }

    public func confirmRemoval() async {
        guard let detail, !isRemoving else { return }
        isRemoving = true
        defer { isRemoving = false }
        let outcome = await store.remove(detail.logItemID, expected: detail.logItemVersionID)
        if outcome == .applied { didRemove = true } else { changeAlert = outcome; await load() }
    }
}
