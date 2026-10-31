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
/// visible duration only (5 s, or 10 s at accessibility text sizes), and never after the user has
/// left the screen it was shown on; with VoiceOver running the banner stays until it is dismissed
/// or used. Undo writes one remove through `FoodLogStore`. An Undo press that began before the
/// duration ended still applies (#357): the timeout waits for the finger to lift, and the tap
/// moves the banner to `.removing` synchronously, before the timeout task can run.
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
    /// At accessibility Dynamic Type sizes the text takes longer to read.
    public static let accessibilityVisibleDuration: Duration = .seconds(10)
    /// The VoiceOver announcement waits for Confirm's pop to settle, so focus moving to the new
    /// screen does not cut it off.
    public static let announcementDelay: Duration = .milliseconds(700)

    @Published public private(set) var content: Content?
    /// The layout the tap shield keeps for the banner's whole life: the logged banner, which is
    /// the tallest, so the area where Undo was stays covered after the shorter outcome (#357).
    public private(set) var shieldLayout: Content?
    /// Increases after each applied Undo, so a showing Food Log or Home reloads.
    @Published public private(set) var removals = 0
    /// Set from the environment while VoiceOver runs: the banner is kept until dismissed.
    public var keepsUntilDismissed = false
    /// Set from the environment at accessibility text sizes: the banner stays 10 s.
    public var usesAccessibilityTextSize = false
    /// Where the user is when the banner appears (the navigation path); set by the app shell.
    public var location: @MainActor () -> AnyHashable? = { nil }
    private var anchor: AnyHashable?
    /// The registered screen the banner belongs to (the app reports screens entering and leaving the window).
    private var anchorScreen: UUID?
    /// True while Log's own navigation is still bringing the destination on screen.
    private var awaitsScreen = false
    private var visibleScreen: UUID?
    /// True while a finger is down on Undo; the timeout waits for it to lift.
    private var undoPressed = false
    /// The visible duration ended while Undo was held.
    private var expiredDuringPress = false
    private var generation = 0
    private let store: any FoodLogStore
    private let sleep: @Sendable (Duration) async -> Void
    private let announce: @MainActor (String) -> Void

    public init(store: any FoodLogStore,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                announce: @escaping @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }) {
        self.store = store; self.sleep = sleep; self.announce = announce
    }

    public var visibleDuration: Duration {
        usesAccessibilityTextSize ? Self.accessibilityVisibleDuration : Self.visibleDuration
    }

    /// Called after Log has closed Confirm, so `location` is already the destination. The banner
    /// belongs to the registered screen still showing (a sheet closed over it), or else to the
    /// next one that appears (Confirm popping back to it).
    public func show(_ notice: FoodLoggedNotice) {
        anchor = location()
        anchorScreen = visibleScreen
        awaitsScreen = visibleScreen == nil
        shieldLayout = .logged(notice)
        present(.logged(notice))
    }

    /// One Undo: exactly one remove of the logged version. A second tap, a timed-out or
    /// dismissed banner, or a banner left behind by navigation writes nothing.
    public func undo() async {
        await startUndo()?.value
    }

    /// Undo from a tap: the banner moves to `.removing` before this returns, so a timeout that
    /// runs after the tap (#357) no longer hides it; the remove follows in the returned task.
    /// Nil when Undo is not offered.
    @discardableResult
    public func startUndo() -> Task<Void, Never>? {
        guard case let .logged(notice) = content else { return nil }
        content = .removing(notice)
        let generationAtUndo = generation
        return Task { [store] in
            let outcome = await store.remove(notice.logItemID, expected: notice.logItemVersionID)
            if outcome == .applied { self.removals += 1 }
            guard self.generation == generationAtUndo else { return }
            self.present(.result(FoodLoggedText.outcome(outcome)))
        }
    }

    /// A finger went down on Undo (true) or lifted or was cancelled (false). A timeout that ended
    /// while it was down applies after the lift, once the tap's own action has run.
    public func undoPressChanged(_ pressed: Bool) {
        undoPressed = pressed
        guard !pressed, expiredDuringPress else { return }
        expiredDuringPress = false
        let held = generation
        Task { [weak self] in self?.expire(generation: held) }
    }

    public func dismiss() {
        generation += 1
        content = nil
        shieldLayout = nil
        undoPressed = false
        expiredDuringPress = false
        anchor = nil
        anchorScreen = nil
        awaitsScreen = false
    }

    /// The navigation path changed: a banner left behind is dismissed and Undo is gone.
    public func navigated(to location: AnyHashable) {
        guard content != nil, location != anchor else { return }
        dismiss()
    }

    /// A registered screen appeared. A banner still waiting for its destination takes it.
    public func screenAppeared(_ screen: UUID) {
        visibleScreen = screen
        if awaitsScreen, content != nil {
            anchorScreen = screen
            awaitsScreen = false
        }
    }

    /// A registered screen disappeared (anything pushed over it, or it closed): leaving the
    /// banner's screen dismisses the banner, so Undo is never offered over another screen.
    public func screenDisappeared(_ screen: UUID) {
        if visibleScreen == screen { visibleScreen = nil }
        if content != nil, anchorScreen == screen { dismiss() }
    }

    /// The visible duration ended for the banner of `generation`.
    public func expire(generation expired: Int) {
        guard expired == generation, !keepsUntilDismissed else { return }
        if case .removing = content { return }
        if undoPressed, content?.offersUndo == true {
            expiredDuringPress = true
            return
        }
        dismiss()
    }

    public var currentGeneration: Int { generation }

    /// Whether the banner belongs to a registered screen yet (false while it waits for one).
    public var isAnchoredToScreen: Bool { anchorScreen != nil }
    /// Whether a registered screen is in the window now.
    public var hasVisibleScreen: Bool { visibleScreen != nil }

    /// "Logged · 260 kcal. Undo available." Nil while Undo is in progress: only the logged
    /// banner and Undo's outcome are announced.
    public static func announcement(_ content: Content) -> String? {
        if case .removing = content { return nil }
        var parts = [content.message]
        if let detail = content.detail { parts.append(detail) }
        if content.offersUndo { parts.append("Undo available.") }
        return parts.map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
    }

    private func present(_ next: Content) {
        generation += 1
        // A press is per banner: one left over from a banner that went away mid-press must not
        // hold this one past its duration.
        undoPressed = false
        expiredDuringPress = false
        content = next
        let shown = generation
        let sleep = sleep
        let duration = visibleDuration
        if let text = Self.announcement(next) {
            Task { [weak self] in
                await sleep(Self.announcementDelay)
                // Undo moves the same banner to .removing without a new generation.
                guard let self, self.generation == shown, self.content == next else { return }
                self.announce(text)
            }
        }
        Task { [weak self] in
            await sleep(duration)
            self?.expire(generation: shown)
        }
    }
}

/// The banner: message, an optional line about the favourite, Undo (44 pt) and VoiceOver actions.
/// Shown at the bottom of the destination; outside its own area it never blocks the screen behind it.
public struct FoodLoggedBanner: View {
    @ObservedObject private var model: FoodLoggedBannerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(model: FoodLoggedBannerModel) { self.model = model }

    public var body: some View {
        ZStack {
            if let content = model.content {
                // In place at once, under the sliding banner: a tap in the banner's area before it
                // has slid in is absorbed rather than landing on the control underneath (#357).
                FoodLoggedBannerTapShield(content: model.shieldLayout ?? content)
                    .transition(.identity)
                FoodLoggedBannerContent(content: content, undo: { model.startUndo() }, dismiss: model.dismiss,
                                        undoPressed: model.undoPressChanged)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.content)
        .onAppear {
            model.keepsUntilDismissed = voiceOver
            model.usesAccessibilityTextSize = dynamicTypeSize.isAccessibilitySize
        }
        .onChange(of: voiceOver) { _, enabled in model.keepsUntilDismissed = enabled }
        .onChange(of: dynamicTypeSize) { _, size in model.usesAccessibilityTextSize = size.isAccessibilitySize }
    }
}

/// Takes taps in the banner's area while the banner is still sliding in, and where Undo was once
/// the shorter outcome shows: the logged banner's layout, invisible, hit only inside its rounded
/// card (not the outer margins), and hidden from VoiceOver (the banner itself is the element).
struct FoodLoggedBannerTapShield: View {
    let content: FoodLoggedBannerModel.Content

    var body: some View {
        FoodLoggedBannerContent(content: content, undo: {}, dismiss: {})
            .hidden()
            .overlay {
                Color.clear
                    .contentShape(RoundedRectangle(cornerRadius: FoodLoggedBannerContent.cornerRadius, style: .continuous))
                    .onTapGesture {}
                    .padding(.horizontal, FoodLoggedBannerContent.outerHorizontalPadding)
                    .padding(.bottom, FoodLoggedBannerContent.outerBottomPadding)
            }
            .accessibilityHidden(true)
    }
}

/// The banner's visible content, separate from the model so it renders in tests. For VoiceOver
/// it is one element with an explicit label and explicit Undo and Dismiss actions, so Undo is
/// never listed twice.
public struct FoodLoggedBannerContent: View {
    private let content: FoodLoggedBannerModel.Content
    private let undo: () -> Void
    private let dismiss: () -> Void
    private let undoPressed: (Bool) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// A finger is down on Undo; resets on lift and on cancellation.
    @GestureState private var undoPressing = false

    public init(content: FoodLoggedBannerModel.Content, undo: @escaping () -> Void, dismiss: @escaping () -> Void,
                undoPressed: @escaping (Bool) -> Void = { _ in }) {
        self.content = content; self.undo = undo; self.dismiss = dismiss; self.undoPressed = undoPressed
    }

    static let cornerRadius: CGFloat = 14
    static let outerHorizontalPadding: CGFloat = 16
    static let outerBottomPadding: CGFloat = 8

    /// The VoiceOver label: the message and, when present, the favourite line.
    public static func accessibilityLabel(_ content: FoodLoggedBannerModel.Content) -> String {
        [content.message, content.detail].compactMap { $0 }.joined(separator: ". ")
    }

    /// The VoiceOver actions, in order: Undo while it is offered, then Dismiss.
    public static func accessibilityActionNames(_ content: FoodLoggedBannerModel.Content) -> [String] {
        (content.offersUndo ? [FoodLoggedText.undo] : []) + [FoodLoggedText.dismiss]
    }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: content.offersUndo ? "checkmark.circle.fill" : "info.circle")
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
                .simultaneousGesture(DragGesture(minimumDistance: 0).updating($undoPressing) { _, pressing, _ in pressing = true })
                .onChange(of: undoPressing) { _, pressing in undoPressed(pressing) }
                .onDisappear { undoPressed(false) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).strokeBorder(.separator))
        .padding(.horizontal, Self.outerHorizontalPadding)
        .padding(.bottom, Self.outerBottomPadding)
        // One element: the visible Undo button is not exposed separately, so VoiceOver lists
        // Undo once, as an action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(content))
        .accessibilityHint(content.offersUndo ? FoodLoggedText.undoHint : "")
        .accessibilityActions {
            if content.offersUndo { Button(FoodLoggedText.undo, action: undo) }
            Button(FoodLoggedText.dismiss, action: dismiss)
        }
        .accessibilityAction(.escape, dismiss)
    }

    private var isRemoving: Bool { if case .removing = content { true } else { false } }
}
