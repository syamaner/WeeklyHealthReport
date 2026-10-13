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
}

extension FavouritesService: FavouriteSaving {}

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

    public init(store: any FavouriteSaving) { self.store = store }

    public func state(for id: LogItemVersionID) -> FavouriteSaveState { states[id] ?? .available }

    /// Marks each version already pinned by an active favourite. A version saved here keeps
    /// "Saved as favourite"; one whose favourite was removed elsewhere becomes available again.
    /// When favourites cannot be read the control stays available and a save reports its own result.
    public func refresh(_ ids: [LogItemVersionID]) {
        let projection = try? store.projection()
        var next: [LogItemVersionID: FavouriteSaveState] = [:]
        for id in ids {
            let active = projection?.activeFavourite(boundTo: id) != nil
            switch (states[id], active) {
            case (.saved?, true): next[id] = .saved
            case (_, true): next[id] = .alreadyFavourite
            case (.failed?, false): next[id] = .failed
            default: next[id] = .available
            }
        }
        states = next
    }

    /// One save for this version. Ignored while saving or once it is a favourite.
    public func save(_ id: LogItemVersionID) {
        switch state(for: id) {
        case .saving, .saved, .alreadyFavourite: return
        case .available, .failed: break
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
            Text(text.title).foregroundStyle(.primary)
            Text(text.detail).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
        // Stacked at accessibility sizes and after a failure, so the name never breaks mid-word.
        if AddFoodRecentRowText.stacks(at: dynamicTypeSize) || state == .failed {
            VStack(alignment: .leading, spacing: 6) {
                label
                control(state, id: id, title: text.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else {
            HStack {
                label
                Spacer(minLength: 8)
                control(state, id: id, title: text.title)
            }
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func control(_ state: FavouriteSaveState, id: LogItemVersionID, title: String) -> some View {
        switch state {
        case .available, .saving:
            Button { model.save(id) } label: {
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
                Button(FavouriteSaveText.tryAgain) { model.save(id) }.buttonStyle(.borderless).frame(minHeight: 44)
                    .accessibilityLabel("\(FavouriteSaveText.tryAgain), save \(title) as a favourite")
            }
        }
    }
}
