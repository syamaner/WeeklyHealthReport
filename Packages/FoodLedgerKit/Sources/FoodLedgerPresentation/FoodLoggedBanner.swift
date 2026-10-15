import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// What the banner shown after Log refers to: the entry just logged and its text (owner decision,
/// 15 October 2026). Undo removes exactly this entry version through the Food Log remove path.
public struct FoodLoggedNotice: Equatable, Sendable {
    public let logItemID: LogItemID
    public let logItemVersionID: LogItemVersionID
    public let message: String
    /// Set when a favourite was saved with the entry: Undo removes only the entry.
    public let detail: String?

    public init(logItemID: LogItemID, logItemVersionID: LogItemVersionID, message: String, detail: String? = nil) {
        self.logItemID = logItemID; self.logItemVersionID = logItemVersionID
        self.message = message; self.detail = detail
    }

    public init(saved: StoredFoodConfirmation, message: String, detail: String? = nil) {
        self.init(logItemID: saved.logItem.logItemID, logItemVersionID: saved.logItemVersion.logItemVersionID,
                  message: message, detail: detail)
    }
}

/// Plain text for the banner. The figure is the one the Log button showed: energy on Confirm,
/// the amount on the quick-add sheet; nothing when it was not known.
public enum FoodLoggedText {
    public static let logged = "Logged"
    public static let loggedAndFavourite = "Logged and saved as favourite"
    public static let favouriteStays = "Undo removes the entry. The favourite stays."
    public static let undo = "Undo"
    public static let dismiss = "Dismiss"
    public static let removed = "Entry removed"
    public static let unchanged = "Entry unchanged. It changed elsewhere."
    public static let notRemoved = "Entry not removed. Remove it from the Food Log."
    public static let undoHint = "Removes the entry just logged. You can restore it from Removed in the Food Log."

    /// "Logged · 260 kcal", "Logged", "Logged without nutrition", "Logged and saved as favourite · 260 kcal".
    public static func message(figure: String?, withoutNutrition: Bool, savedFavourite: Bool) -> String {
        if withoutNutrition {
            return savedFavourite ? "Logged without nutrition and saved as favourite" : "Logged without nutrition"
        }
        let base = savedFavourite ? loggedAndFavourite : logged
        guard let figure else { return base }
        return "\(base) · \(figure)"
    }

    public static func detail(savedFavourite: Bool) -> String? { savedFavourite ? favouriteStays : nil }

    public static func outcome(_ outcome: FoodLogChangeOutcome) -> String {
        switch outcome {
        case .applied: removed
        case .changedElsewhere: unchanged
        case .notSaved: notRemoved
        }
    }
}

/// The one banner shown on the destination after Log closes Confirm. Undo is offered for the
/// visible duration only, and never after the user has navigated away; with VoiceOver running the
/// banner stays until it is dismissed or used. Undo writes one remove through `FoodLogStore`.
@MainActor
public final class FoodLoggedBannerModel: ObservableObject {
    public enum Content: Equatable {
        case logged(FoodLoggedNotice)
        case removing(FoodLoggedNotice)
        /// The result of Undo; no further Undo is offered.
        case result(String)

        public var message: String {
            switch self {
            case let .logged(notice), let .removing(notice): notice.message
            case let .result(text): text
            }
        }

        public var detail: String? {
            switch self {
            case let .logged(notice), let .removing(notice): notice.detail
            case .result: nil
            }
        }

        public var offersUndo: Bool { if case .logged = self { true } else { false } }
    }

    public static let visibleDuration: Duration = .seconds(5)

    @Published public private(set) var content: Content?
    /// Increases after each applied Undo, so a showing Food Log or Home reloads.
    @Published public private(set) var removals = 0
    /// Set from the environment while VoiceOver runs: the banner is kept until dismissed.
    public var keepsUntilDismissed = false
    /// Where the user is when the banner appears (the navigation path); set by the app shell.
    public var location: @MainActor () -> AnyHashable? = { nil }
    private var anchor: AnyHashable?
    private var generation = 0
    private let store: any FoodLogStore
    private let sleep: @Sendable (Duration) async -> Void

    public init(store: any FoodLogStore,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.store = store; self.sleep = sleep
    }

    /// Called after Log has closed Confirm, so `location` is already the destination.
    public func show(_ notice: FoodLoggedNotice) {
        anchor = location()
        present(.logged(notice))
    }

    /// One Undo: exactly one remove of the logged version. A second tap, a timed-out or
    /// dismissed banner, or a banner left behind by navigation writes nothing.
    public func undo() async {
        guard case let .logged(notice) = content else { return }
        content = .removing(notice)
        let generationAtUndo = generation
        let outcome = await store.remove(notice.logItemID, expected: notice.logItemVersionID)
        if outcome == .applied { removals += 1 }
        guard generation == generationAtUndo else { return }
        present(.result(FoodLoggedText.outcome(outcome)))
    }

    public func dismiss() {
        generation += 1
        content = nil
        anchor = nil
    }

    /// The navigation path changed: a banner left behind is dismissed and Undo is gone.
    public func navigated(to location: AnyHashable) {
        guard content != nil, location != anchor else { return }
        dismiss()
    }

    /// The visible duration ended for the banner of `generation`.
    public func expire(generation expired: Int) {
        guard expired == generation, !keepsUntilDismissed else { return }
        if case .removing = content { return }
        dismiss()
    }

    public var currentGeneration: Int { generation }

    private func present(_ next: Content) {
        generation += 1
        content = next
        let shown = generation
        let sleep = sleep
        Task { [weak self] in
            await sleep(Self.visibleDuration)
            self?.expire(generation: shown)
        }
    }
}

/// The banner: message, an optional line about the favourite, Undo (44 pt) and VoiceOver actions.
/// Shown at the bottom of the destination; it never blocks the screen behind it.
public struct FoodLoggedBanner: View {
    @ObservedObject private var model: FoodLoggedBannerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    public init(model: FoodLoggedBannerModel) { self.model = model }

    public var body: some View {
        ZStack {
            if let content = model.content {
                FoodLoggedBannerContent(content: content, undo: { Task { await model.undo() } }, dismiss: model.dismiss)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.content)
        .onAppear { model.keepsUntilDismissed = voiceOver }
        .onChange(of: voiceOver) { _, enabled in model.keepsUntilDismissed = enabled }
        .onChange(of: model.content) { _, content in
            guard let content else { return }
            AccessibilityNotification.Announcement(Self.announcement(content)).post()
        }
    }

    /// "Logged · 260 kcal. Undo available."
    public static func announcement(_ content: FoodLoggedBannerModel.Content) -> String {
        var parts = [content.message]
        if let detail = content.detail { parts.append(detail) }
        if content.offersUndo { parts.append("Undo available.") }
        return parts.map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
    }
}

/// The banner's visible content, separate from the model so it renders in tests.
public struct FoodLoggedBannerContent: View {
    private let content: FoodLoggedBannerModel.Content
    private let undo: () -> Void
    private let dismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(content: FoodLoggedBannerModel.Content, undo: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.content = content; self.undo = undo; self.dismiss = dismiss
    }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: content.offersUndo ? "checkmark.circle.fill" : "info.circle")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.message).font(.subheadline.weight(.semibold))
                    if let detail = content.detail {
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if content.offersUndo || isRemoving {
                Button(action: undo) {
                    Text(FoodLoggedText.undo).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!content.offersUndo)
                .accessibilityHint(FoodLoggedText.undoHint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([content.message, content.detail].compactMap { $0 }.joined(separator: ". "))
        .accessibilityAction(named: FoodLoggedText.dismiss, dismiss)
        .accessibilityActions {
            if content.offersUndo { Button(FoodLoggedText.undo, action: undo) }
        }
        .accessibilityAction(.escape, dismiss)
    }

    private var isRemoving: Bool { if case .removing = content { true } else { false } }
}
