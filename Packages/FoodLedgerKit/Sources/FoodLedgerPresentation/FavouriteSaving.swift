import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// "Save as favourite" from something already logged (owner decision A, 13 October 2026): a saved
/// entry or a recent food. Consumer-owned port; `FavouritesService` conforms below. The favourite
/// pins the entry's current version through the existing `save_favourite_v1` path (Q2), so no log
/// record is written and a repeat returns the existing favourite.
public protocol FavouriteSaving: AnyObject {
    func projection() throws -> FavouritesProjection
    @discardableResult
    func saveFavourite(logItemVersionID: LogItemVersionID) throws -> FavouriteVersion
    /// The matching active favourite for each version (same food, source, preparation and amount),
    /// read in one pass (#308).
    func activeFavourites(matching logItemVersionIDs: [LogItemVersionID]) throws -> [LogItemVersionID: FavouriteVersion]
}

extension FavouritesService: FavouriteSaving {}

public extension FavouriteSaving {
    /// The active favourite matching this version (#308). The default matches the bound version
    /// only; `FavouritesService` also matches the same source, preparation and amount.
    func activeFavourite(matchingSourceOf logItemVersionID: LogItemVersionID) throws -> FavouriteVersion? {
        try activeFavourites(matching: [logItemVersionID])[logItemVersionID]
    }

    func activeFavourites(matching logItemVersionIDs: [LogItemVersionID]) throws -> [LogItemVersionID: FavouriteVersion] {
        let projection = try projection()
        var result: [LogItemVersionID: FavouriteVersion] = [:]
        for id in logItemVersionIDs { result[id] = projection.activeFavourite(boundTo: id) }
        return result
    }
}

/// Where one logged version stands with respect to favourites.
public enum FavouriteSaveState: Equatable, Sendable {
    /// Not a favourite yet: "Save as favourite" is offered.
    case available
    case saving
    /// Saved by this action.
    case saved
    /// An active favourite already pins this version; saving again writes nothing.
    case alreadyFavourite
    /// The favourite was not written; "Try again" repeats the same idempotent save.
    case failed

    public var isFavourite: Bool { self == .saved || self == .alreadyFavourite }
}

/// Plain copy for the Save as favourite control. British spelling, no emoji.
public enum FavouriteSaveText {
    public static let save = "Save as favourite"
    public static let saving = "Saving favourite"
    public static let saved = "Saved as favourite"
    public static let already = "Already a favourite"
    public static let failed = "Favourite not saved"
    public static let tryAgain = "Try again"
    public static let failedMessage = "The entry is unchanged. Try again to save it as a favourite."
    public static let footer = "A favourite keeps this source and amount, so logging it again takes one step. The entry itself is unchanged."
    public static let saveHint = "Adds this food to Favourites with this amount. Nothing is logged."

    public static func title(_ state: FavouriteSaveState) -> String {
        switch state {
        case .available: save
        case .saving: saving
        case .saved: saved
        case .alreadyFavourite: already
        case .failed: failed
        }
    }
}

/// Save-as-favourite state for one or more logged versions (a saved entry, or the rows of a recent
/// food list). Reads the favourites projection to show "Already a favourite"; one tap writes at
/// most one favourite, and a failure keeps the entry unchanged with Try again.
@MainActor
public final class FavouriteSaveModel: ObservableObject {
    @Published public private(set) var states: [LogItemVersionID: FavouriteSaveState] = [:]
    private let store: any FavouriteSaving
    /// The entry's current product version, read at tap time; nil when it was removed.
    private let currentVersion: ((LogItemID) throws -> LogItemVersionID?)?

    public init(store: any FavouriteSaving, currentVersion: ((LogItemID) throws -> LogItemVersionID?)? = nil) {
        self.store = store
        self.currentVersion = currentVersion
    }

    public func state(for id: LogItemVersionID) -> FavouriteSaveState { states[id] ?? .available }

    /// Marks each version already pinned by an active favourite. A version saved here keeps
    /// "Saved as favourite"; one whose favourite was removed elsewhere becomes available again.
    /// When favourites cannot be read the control stays available and a save reports its own result.
    /// A version counts as a favourite when an active favourite has the same food, source,
    /// preparation and amount, so re-logging a favourite keeps "Already a favourite" (#308). The
    /// matches are read once per refresh, not once per row.
    public func refresh(_ ids: [LogItemVersionID]) {
        let matches = try? store.activeFavourites(matching: ids)
        var next: [LogItemVersionID: FavouriteSaveState] = [:]
        for id in ids {
            let active = matches?[id] != nil
            switch (states[id], active) {
            case (.saved?, true): next[id] = .saved
            case (_, true): next[id] = .alreadyFavourite
            case (.failed?, false): next[id] = .failed
            default: next[id] = .available
            }
        }
        states = next
    }

    /// A recent row's save: the entry's current version is re-read at tap time, so a list left
    /// open while the entry was edited elsewhere never pins the older version it shows. The row
    /// (keyed by the version it shows) takes the result; a removed entry fails and writes nothing.
    public func save(_ shown: LogItemVersionID, logItemID: LogItemID) {
        guard let currentVersion else { return save(shown) }
        switch state(for: shown) {
        case .saving, .saved, .alreadyFavourite: return
        case .available, .failed: break
        }
        let current: LogItemVersionID?
        do { current = try currentVersion(logItemID) } catch { states[shown] = .failed; return }
        guard let current else { states[shown] = .failed; return }
        guard current != shown else { return save(shown) }
        if projectionHasActive(current) { states[current] = .alreadyFavourite } else { save(current) }
        states[shown] = states[current]
    }

    private func projectionHasActive(_ id: LogItemVersionID) -> Bool {
        (try? store.activeFavourite(matchingSourceOf: id)) != nil
    }

    /// One save for this version. Ignored while saving or once it is a favourite.
    public func save(_ id: LogItemVersionID) {
        switch state(for: id) {
        case .saving, .saved, .alreadyFavourite: return
        case .available, .failed: break
        }
        // The same food and source became a favourite elsewhere: say so, write nothing (#308).
        if (try? store.projection().activeFavourite(boundTo: id)) == nil, projectionHasActive(id) {
            states[id] = .alreadyFavourite
            return
        }
        states[id] = .saving
        do {
            try store.saveFavourite(logItemVersionID: id)
            states[id] = .saved
        } catch {
            states[id] = .failed
        }
    }
}

/// The "Favourite not saved" alert with Try again, as pure state. Try again is pressed while the
/// alert is dismissing, so the retry waits until the dismissal has finished; a second failure then
/// presents the alert again instead of being swallowed by the dismissal.
public struct FavouriteRetryAlert: Equatable, Sendable {
    public private(set) var isPresented = false
    public private(set) var retryPending = false

    public init() {}

    /// After a save: present on failure, otherwise stay hidden.
    public mutating func finished(_ state: FavouriteSaveState) { isPresented = state == .failed }
    /// The alert's Try again button.
    public mutating func tryAgain() { retryPending = true }
    /// The alert has gone (either button).
    public mutating func dismissed() { isPresented = false }
    /// Whether a retry should run now that the alert has gone; consumed once.
    public mutating func takeRetry() -> Bool {
        guard !isPresented, retryPending else { return false }
        retryPending = false
        return true
    }
}

/// The saved entry's Save as favourite section: the action, its state and, after a failure,
/// "Favourite not saved" with Try again.
public struct FavouriteSaveSection: View {
    @ObservedObject private var model: FavouriteSaveModel
    private let logItemVersionID: LogItemVersionID

    public init(model: FavouriteSaveModel, logItemVersionID: LogItemVersionID) {
        self.model = model; self.logItemVersionID = logItemVersionID
    }

    public var body: some View {
        let state = model.state(for: logItemVersionID)
        Section {
            switch state {
            case .available, .saving:
                Button { model.save(logItemVersionID) } label: {
                    Label(FavouriteSaveText.title(state), systemImage: "star").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(state == .saving)
                .accessibilityHint(FavouriteSaveText.saveHint)
            case .saved, .alreadyFavourite:
                Label(FavouriteSaveText.title(state), systemImage: "star.fill")
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
            case .failed:
                Label(FavouriteSaveText.failed, systemImage: "exclamationmark.triangle").frame(minHeight: 44)
                Text(FavouriteSaveText.failedMessage).font(.footnote).foregroundStyle(.secondary)
                Button(FavouriteSaveText.tryAgain) { model.save(logItemVersionID) }.frame(minHeight: 44)
            }
        } footer: { Text(FavouriteSaveText.footer) }
    }
}

/// "From what you’ve logged" (owner decision A): recent foods, each with Save as favourite. Opening
/// it writes nothing; each save pins that food's current logged version.
public struct FavouriteFromLoggedView: View {
    public enum Content: Equatable {
        case loading
        case failed
        case items([FoodRecentRelogItem])
    }

    public static let title = "From what you’ve logged"
    public static let emptyText = "Nothing logged in the last 30 days"
    public static let failedText = "What you’ve logged could not be read."
    public static let footer = "Saving pins the food, its source and the amount you last logged. Nothing is logged. Plain water has its own quick add item, so it is not listed."

    /// The foods offered: verified, pinnable, and not plain water.
    public static func offered(_ items: [FoodRecentRelogItem]) -> [FoodRecentRelogItem] {
        items.filter { $0.logItemVersionID != nil && !$0.isPlainWater }
    }

    private let content: Content
    private let now: Date
    private let calendar: Calendar
    @ObservedObject private var model: FavouriteSaveModel
    private let retry: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(content: Content, now: Date, calendar: Calendar, model: FavouriteSaveModel, retry: @escaping () -> Void) {
        self.content = content; self.now = now; self.calendar = calendar; self.model = model; self.retry = retry
    }

    public var body: some View {
        List {
            switch content {
            case .loading:
                Section { ProgressView("Loading what you’ve logged") }
            case .failed:
                Section {
                    Label(Self.failedText, systemImage: "exclamationmark.triangle")
                    Button(FavouriteSaveText.tryAgain, action: retry).frame(minHeight: 44)
                }
            case let .items(items):
                Section {
                    let offered = Self.offered(items)
                    if offered.isEmpty { Text(Self.emptyText).foregroundStyle(.secondary) }
                    ForEach(offered, id: \.item.logItemID) { recent in
                        if let id = recent.logItemVersionID { row(recent, id: id) }
                    }
                } header: { Text("Recent") } footer: { Text(Self.footer) }
            }
        }
        .navigationTitle(Self.title)
        #if os(iOS)
        // Inline, so the long title is never truncated at larger text sizes.
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func row(_ recent: FoodRecentRelogItem, id: LogItemVersionID) -> some View {
        let text = AddFoodRecentRowText(recent, now: now, calendar: calendar)
        let state = model.state(for: id)
        let label = VStack(alignment: .leading, spacing: 3) {
            Text(text.title).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            // Wraps in full at accessibility sizes ("Last: 1…" was cut short, #315).
            Text(text.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
        // Stacked at accessibility sizes and after a failure, so the name never breaks mid-word.
        if AddFoodRecentRowText.stacks(at: dynamicTypeSize) || state == .failed {
            VStack(alignment: .leading, spacing: 6) {
                label
                control(state, id: id, logItemID: recent.item.logItemID, title: text.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else {
            HStack {
                label
                Spacer(minLength: 8)
                control(state, id: id, logItemID: recent.item.logItemID, title: text.title)
            }
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func control(_ state: FavouriteSaveState, id: LogItemVersionID, logItemID: LogItemID, title: String) -> some View {
        switch state {
        case .available, .saving:
            Button { model.save(id, logItemID: logItemID) } label: {
                Label(FavouriteSaveText.save, systemImage: "star").labelStyle(.titleAndIcon).font(.subheadline)
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .disabled(state == .saving)
            .accessibilityLabel("\(FavouriteSaveText.save), \(title)")
            .accessibilityHint(FavouriteSaveText.saveHint)
        case .saved, .alreadyFavourite:
            Label(FavouriteSaveText.title(state), systemImage: "star.fill").font(.subheadline).foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .accessibilityLabel("\(title), \(FavouriteSaveText.title(state).lowercased())")
        case .failed:
            HStack {
                Label(FavouriteSaveText.failed, systemImage: "exclamationmark.triangle").font(.subheadline)
                Spacer(minLength: 8)
                Button(FavouriteSaveText.tryAgain) { model.save(id, logItemID: logItemID) }.buttonStyle(.borderless).frame(minHeight: 44)
                    .accessibilityLabel("\(FavouriteSaveText.tryAgain), save \(title) as a favourite")
            }
        }
    }
}
