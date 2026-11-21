import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// The Label photo screen (docs/label-photo-ai-prefill-v1.md 4.1, 7.1, 7.2 and 9, as amended by
/// docs/openrouter-single-consent-v1-amendment.md O1.4): the cropped photo as it will be sent, Name
/// and Brand (never sent) and the one Read label with AI action. Every send is an explicit tap with
/// Settings › OpenRouter turned on; Try again is a new tap. The photo stays in memory only and
/// leaves with the screen. There is no first-use sheet.
@MainActor
public final class LabelPhotoScreenModel: ObservableObject {
    /// Why Read label with AI is disabled before any tap (section 9), each with its 7.2 copy.
    public enum Blocker: Equatable, Sendable {
        /// The O1.4 blocked row (switch off, no key, key not validated), in place of the earlier
        /// `turnedOff`, `noKey` and `keyNotValidated` blockers.
        case openRouter(OpenRouterBlockedReason)
        case offline, dailyLimit, paused, routeUnavailable

        public var text: String {
            switch self {
            case let .openRouter(reason): OpenRouterBlockedText.text(reason)
            case .offline: LabelPhotoText.offline
            case .dailyLimit: LabelPhotoText.dailyLimit
            case .paused: LabelPhotoText.failedCostPaused
            case .routeUnavailable: LabelPhotoText.routeUnavailable
            }
        }

        /// The one-tap way out, if any.
        public var action: String? {
            switch self {
            case .openRouter: OpenRouterBlockedText.link
            case .offline: LabelPhotoText.pasteLabel
            case .dailyLimit, .paused, .routeUnavailable: nil
            }
        }
    }

    public enum KeyState: Equatable, Sendable {
        case missing, notValidated, valid

        /// Case for case, the application's key state (section 6).
        public var openRouter: OpenRouterKeyState {
            switch self {
            case .missing: .missing
            case .notValidated: .notValidated
            case .valid: .valid
            }
        }
    }

    public enum Phase: Equatable {
        case editing
        case reading
        case retrying(attempt: Int)
        /// The reasons shown with the photo kept, and Paste nutrition label and Search foods.
        case declined([String])
        case failed(String)
    }

    /// Everything the screen reaches, injected by the composition root.
    public struct Environment {
        public let prepare: (Data, LabelCropRect) -> Result<PreparedLabelImage, LabelImagePreparationError>
        public let read: (PreparedLabelImage, @escaping @Sendable (Int) -> Void) async -> LabelPhotoReadFlow.Outcome
        public let status: () async -> LabelPhotoReadSession.Status
        public let keyState: () -> KeyState
        public let isOnline: () -> Bool
        /// The gate's answer for a label photo read (Settings › OpenRouter), asked before every tap,
        /// so turning the switch off shows the blocked row and stops the next send (O1.2).
        public let consentOn: () -> Bool
        public let makeConfirm: (LabelPhotoReview, PreparedLabelImage, PastedLabelDetails) throws -> LabelPhotoSourceModel

        public init(prepare: @escaping (Data, LabelCropRect) -> Result<PreparedLabelImage, LabelImagePreparationError>,
                    read: @escaping (PreparedLabelImage, @escaping @Sendable (Int) -> Void) async -> LabelPhotoReadFlow.Outcome,
                    status: @escaping () async -> LabelPhotoReadSession.Status, keyState: @escaping () -> KeyState, isOnline: @escaping () -> Bool,
                    consentOn: @escaping () -> Bool,
                    makeConfirm: @escaping (LabelPhotoReview, PreparedLabelImage, PastedLabelDetails) throws -> LabelPhotoSourceModel) {
            self.prepare = prepare; self.read = read; self.status = status; self.keyState = keyState; self.isOnline = isOnline
            self.consentOn = consentOn; self.makeConfirm = makeConfirm
        }
    }

    @Published public var name = ""
    @Published public var brand = ""
    @Published public private(set) var photo: Data?
    @Published public private(set) var crop: LabelCropRect = .whole
    @Published public private(set) var prepared: PreparedLabelImage?
    /// Why the crop cannot be sent (7.2), shown in place of the photo's caption.
    @Published public private(set) var preparationFailure: String?
    @Published public var cropping = false
    @Published public private(set) var cameraDenied = false
    @Published public private(set) var phase: Phase = .editing
    /// The day's admission and the session's route state; nil until first read, when nothing is
    /// claimed about the allowance and Read stays disabled.
    @Published public private(set) var status: LabelPhotoReadSession.Status?
    /// Confirm for a usable reading; the flow pushes it.
    @Published public var confirmSource: LabelPhotoSourceModel?
    /// A send attempted this tap, for the "Cancelled after sending" copy.
    private var readTask: Task<Void, Never>?
    /// Bumped whenever the photo is replaced or dropped, so a read that finishes late (after Back,
    /// Retake or a new photo on the visit's shared model) cannot change the screen or open Confirm
    /// with the earlier photo's reading (Qodo review of #454).
    private var photoGeneration = 0
    private var refreshes = 0
    private let environment: Environment

    public init(environment: Environment) { self.environment = environment }

    // MARK: State

    public var blocker: Blocker? {
        if let reason = OpenRouterAccess.blockedReason(consentOn: environment.consentOn(), keyState: environment.keyState().openRouter) {
            return .openRouter(reason)
        }
        if !environment.isOnline() { return .offline }
        guard let status else { return nil }
        if status.routeUnavailable { return .routeUnavailable }
        switch status.day {
        case .open: return nil
        case .limitReached, .unreadable: return .dailyLimit
        case .paused: return .paused
        }
    }

    public var isBusy: Bool {
        switch phase {
        case .reading, .retrying: true
        default: false
        }
    }

    /// Read label with AI: disabled with no photo, no name, a blocking state, or a read in flight.
    public var canRead: Bool {
        prepared != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && status != nil && blocker == nil && !isBusy
    }

    public var progressText: String? {
        switch phase {
        case .reading: LabelPhotoText.reading
        case let .retrying(attempt): LabelPhotoText.retrying(attempt: attempt)
        default: nil
        }
    }

    // MARK: Actions

    /// Only the latest refresh publishes, so a slow earlier one (a stale read's, say) cannot put
    /// back an older count or blocker (Qodo review of #454).
    public func refresh() async {
        refreshes += 1
        let mine = refreshes
        let fetched = await environment.status()
        if mine == refreshes { status = fetched }
    }

    /// Back from Confirm (Retake, back, or a failed save): today's count is read again, so it is
    /// never one behind (#327 journey QA). Every read outcome refreshes it too (`finish`).
    public func returnedFromConfirm() async { await refresh() }

    /// A photo from the camera or the library: the crop screen opens over it.
    public func choose(_ data: Data) {
        dropRead()
        photo = data; crop = .whole; prepared = nil; preparationFailure = nil; phase = .editing; cameraDenied = false
        cropping = true
    }

    public func cameraWasDenied() { cameraDenied = true }

    /// Use crop: the photo is prepared now, so the screen shows exactly the bytes that would be sent.
    public func useCrop(_ rect: LabelCropRect) {
        guard let photo else { return }
        crop = rect
        cropping = false
        switch environment.prepare(photo, rect) {
        case let .success(image): prepared = image; preparationFailure = nil
        case let .failure(error): prepared = nil; preparationFailure = LabelPhotoText.preparation(error)
        }
        phase = .editing
    }

    public func cancelCrop() {
        cropping = false
        if prepared == nil { photo = nil }
    }

    /// Retake or Choose another: the photo and any outcome are dropped.
    public func retake() {
        dropRead()
        photo = nil; prepared = nil; preparationFailure = nil; phase = .editing; confirmSource = nil
    }

    /// A setting the blockers read on demand changed (Settings › OpenRouter, say): redraw so the screen
    /// shows the current blocker, or none, without waiting for an unrelated change (Qodo review of #316).
    public func settingsChanged() { objectWillChange.send() }

    /// Read label with AI. There is no first-use sheet: Settings › OpenRouter is the consent (O1.4).
    public func readTapped() {
        // A blocker read on demand (the Settings switch, say) changes without publishing, so a
        // refused tap redraws the screen to show why instead of doing nothing (Qodo review of #316).
        guard canRead else { objectWillChange.send(); return }
        startRead()
    }

    /// Cancel during Reading or Retrying: stops at once; the session charges per E10.
    public func cancel() { readTask?.cancel() }

    /// Leave without saving: the photo and every answer are discarded from memory.
    public func leave() {
        dropRead()
        photo = nil; prepared = nil; confirmSource = nil; phase = .editing; name = ""; brand = ""
    }

    /// Stops any read under way and makes its late result stale.
    private func dropRead() {
        readTask?.cancel()
        readTask = nil
        photoGeneration += 1
    }

    private func startRead() {
        guard let image = prepared, canRead else { return }
        phase = .reading
        let details = PastedLabelDetails(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                         brand: brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : brand)
        let read = environment.read
        let generation = photoGeneration
        // Only the current photo's read may show its retry attempt (Qodo review of #454).
        let progress: @Sendable (Int) -> Void = { [weak self] attempt in
            guard attempt > 1 else { return }
            Task { @MainActor in
                guard let self, self.photoGeneration == generation, self.isBusy else { return }
                self.phase = .retrying(attempt: attempt)
            }
        }
        readTask = Task { [weak self] in
            let outcome = await read(image, progress)
            await self?.finish(outcome, image: image, details: details, generation: generation)
        }
    }

    /// A read's outcome. `generation` is the photo it was started for; a stale one only refreshes
    /// today's count, which the send may have changed.
    func finish(_ outcome: LabelPhotoReadFlow.Outcome, image: PreparedLabelImage, details: PastedLabelDetails,
                generation: Int? = nil) async {
        let current = { generation == nil || generation == self.photoGeneration }
        if current() { readTask = nil }
        await refresh()
        guard current() else { return }
        switch outcome {
        case let .review(review):
            do {
                confirmSource = try environment.makeConfirm(review, image, details)
                phase = .editing
            } catch {
                phase = .failed(LabelPhotoText.failedUnusable)
            }
        case let .declined(codes):
            phase = .declined(LabelPhotoText.declines(codes))
        case .failed(.notPermitted) where isOpenRouterBlocked, .failed(.keyMissing) where isOpenRouterBlocked:
            // Nothing was sent: the blocked row alone says why (O1.2, O1.4).
            phase = .editing
            objectWillChange.send()
        case let .failed(failure):
            phase = .failed(LabelPhotoText.failure(failure))
        }
    }

    private var isOpenRouterBlocked: Bool {
        if case .openRouter = blocker { return true }
        return false
    }
}
