import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// The Label photo screen (docs/label-photo-ai-prefill-v1.md 4.1, 7.1, 7.2 and 9): the cropped
/// photo as it will be sent, Name and Brand (never sent), the egress statement and the one Read
/// label with AI action. Every send is an explicit tap, first behind a one-time sheet; Try again
/// is a new tap. The photo stays in memory only and leaves with the screen.
@MainActor
public final class LabelPhotoScreenModel: ObservableObject {
    /// Why Read label with AI is disabled before any tap (section 9), each with its 7.2 copy.
    public enum Blocker: Equatable, Sendable {
        case noKey, keyNotValidated, offline, dailyLimit, paused, routeUnavailable

        public var text: String {
            switch self {
            case .noKey: LabelPhotoText.noKey
            case .keyNotValidated: LabelPhotoText.keyNotValidated
            case .offline: LabelPhotoText.offline
            case .dailyLimit: LabelPhotoText.dailyLimit
            case .paused: LabelPhotoText.failedCostPaused
            case .routeUnavailable: LabelPhotoText.routeUnavailable
            }
        }

        /// The one-tap way out, if any.
        public var action: String? {
            switch self {
            case .noKey: LabelPhotoText.openRouterSettings
            case .keyNotValidated: LabelPhotoText.validateKey
            case .offline: LabelPhotoText.pasteLabel
            case .dailyLimit, .paused, .routeUnavailable: nil
            }
        }
    }

    public enum KeyState: Equatable, Sendable { case missing, notValidated, valid }

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
        public let hasConsented: () -> Bool
        public let recordConsent: () -> Void
        public let makeConfirm: (LabelPhotoReview, PreparedLabelImage, PastedLabelDetails) throws -> LabelPhotoSourceModel

        public init(prepare: @escaping (Data, LabelCropRect) -> Result<PreparedLabelImage, LabelImagePreparationError>,
                    read: @escaping (PreparedLabelImage, @escaping @Sendable (Int) -> Void) async -> LabelPhotoReadFlow.Outcome,
                    status: @escaping () async -> LabelPhotoReadSession.Status, keyState: @escaping () -> KeyState, isOnline: @escaping () -> Bool,
                    hasConsented: @escaping () -> Bool, recordConsent: @escaping () -> Void,
                    makeConfirm: @escaping (LabelPhotoReview, PreparedLabelImage, PastedLabelDetails) throws -> LabelPhotoSourceModel) {
            self.prepare = prepare; self.read = read; self.status = status; self.keyState = keyState; self.isOnline = isOnline
            self.hasConsented = hasConsented; self.recordConsent = recordConsent; self.makeConfirm = makeConfirm
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
    @Published public var showsFirstUseSheet = false
    /// The day's admission and the session's route state; nil until first read, when nothing is
    /// claimed about the allowance and Read stays disabled.
    @Published public private(set) var status: LabelPhotoReadSession.Status?
    /// Confirm for a usable reading; the flow pushes it.
    @Published public var confirmSource: LabelPhotoSourceModel?
    /// A send attempted this tap, for the "Cancelled after sending" copy.
    private var readTask: Task<Void, Never>?
    private let environment: Environment

    public init(environment: Environment) { self.environment = environment }

    // MARK: State

    public var blocker: Blocker? {
        switch environment.keyState() {
        case .missing: return .noKey
        case .notValidated: return .keyNotValidated
        case .valid: break
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

    /// "Uses your OpenRouter key and credit. Today: n of 30 reads.", only once the count is known.
    public var underButton: String? {
        guard case let .open(reads)? = status?.day else { return nil }
        return LabelPhotoText.underButton(reads: reads)
    }

    // MARK: Actions

    public func refresh() async { status = await environment.status() }

    /// A photo from the camera or the library: the crop screen opens over it.
    public func choose(_ data: Data) {
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
        photo = nil; prepared = nil; preparationFailure = nil; phase = .editing; confirmSource = nil
    }

    /// Read label with AI. The first use shows the sheet; nothing is sent until Send photo.
    public func readTapped() {
        guard canRead else { return }
        if environment.hasConsented() { startRead() } else { showsFirstUseSheet = true }
    }

    public func firstUseAccepted() {
        environment.recordConsent()
        showsFirstUseSheet = false
        startRead()
    }

    public func firstUseDeclined() { showsFirstUseSheet = false }

    /// Cancel during Reading or Retrying: stops at once; the session charges per E10.
    public func cancel() { readTask?.cancel() }

    /// Leave without saving: the photo and every answer are discarded from memory.
    public func leave() {
        readTask?.cancel()
        photo = nil; prepared = nil; confirmSource = nil; phase = .editing; name = ""; brand = ""
    }

    private func startRead() {
        guard let image = prepared, canRead else { return }
        phase = .reading
        let details = PastedLabelDetails(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                         brand: brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : brand)
        let read = environment.read
        let progress: @Sendable (Int) -> Void = { [weak self] attempt in
            guard attempt > 1 else { return }
            Task { @MainActor in
                if self?.isBusy == true { self?.phase = .retrying(attempt: attempt) }
            }
        }
        readTask = Task { [weak self] in
            let outcome = await read(image, progress)
            await self?.finish(outcome, image: image, details: details)
        }
    }

    func finish(_ outcome: LabelPhotoReadFlow.Outcome, image: PreparedLabelImage, details: PastedLabelDetails) async {
        readTask = nil
        await refresh()
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
        case let .failed(failure):
            phase = .failed(LabelPhotoText.failure(failure))
        }
    }
}
