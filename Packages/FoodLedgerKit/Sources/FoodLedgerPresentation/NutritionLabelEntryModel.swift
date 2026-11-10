import SwiftUI

/// What the paste control reports (docs/nutrition-label-entry-v1.md section 6), in
/// presentation-owned types only: no content type, item provider or photo UI type crosses this port.
public enum NutritionLabelPasteEvent: Equatable, Sendable {
    /// The control was tapped and the items are loading.
    case loading
    /// What loaded: an image's bytes, if one loaded and opened, and the first plain-text item as it
    /// was, if any.
    case loaded(imageData: Data?, text: String?)
    /// An image was offered but could not be loaded or opened; the first plain-text item, if any.
    case failed(text: String?)
    /// The load stopped before it finished (the control left the screen); nothing was loaded.
    case cancelled
}

/// The paste control behind a consumer-owned port, provided by the composition root in every
/// photo route mode (section 6). The control reads the clipboard only when tapped.
@MainActor
public protocol NutritionLabelControlFactory {
    /// The system paste control. `acceptsImages` false requests plain text only, so image bytes are
    /// never requested or loaded (3.3).
    func pasteControl(acceptsImages: Bool, events: @escaping (NutritionLabelPasteEvent) -> Void) -> AnyView
}

/// The Nutrition label screen (sections 3.2 to 3.5): the photo section only when the photo route
/// is not off, the paste control and Type or paste text. Loaded payloads are held in memory here
/// only until they are routed, and dropped on choosing the other option, on leaving and when the
/// app goes to the background. Nothing is read, sent or saved here.
@MainActor
public final class NutritionLabelEntryModel: ObservableObject {
    public enum PasteState: Equatable, Sendable {
        case idle
        case loading
        /// The image could not be opened; `offersText` when usable text came with it.
        case failed(offersText: Bool)
        /// Both an image and usable text: the user chooses.
        case both
        /// Nothing usable was loaded.
        case nothing
    }

    /// The photo route's mode is not off. Never a blocker: those are shown on the photo screen.
    public let photosEnabled: Bool
    @Published public private(set) var pasteState: PasteState = .idle
    /// Camera access is off: the photo section shows the label photo copy with Open Settings.
    @Published public private(set) var cameraDenied = false
    private var pendingImage: Data?
    private var pendingText: String?
    private let openImage: (Data) -> Void
    private let openText: (String) -> Void

    /// `openImage` pushes the photo screen with the image as its one-shot input; `openText` opens
    /// the pasted-label screen with the text as its initial value, byte for byte ("" for empty).
    public init(photosEnabled: Bool, openImage: @escaping (Data) -> Void, openText: @escaping (String) -> Void) {
        self.photosEnabled = photosEnabled; self.openImage = openImage; self.openText = openText
    }

    // MARK: State

    public var showsPhotoSection: Bool { photosEnabled }
    /// Images are requested only when the photo route is not off (3.3).
    public var acceptsImages: Bool { photosEnabled }
    public var photoFooter: String { NutritionLabelEntryText.photoFooter }
    public var pasteFooter: String { photosEnabled ? NutritionLabelEntryText.pasteFooterPhotos : NutritionLabelEntryText.pasteFooterTextOnly }
    public var addFoodRowSubtitle: String { NutritionLabelEntryText.addFoodRowSubtitle(photosEnabled: photosEnabled) }
    public var isLoading: Bool { pasteState == .loading }
    /// Paste and Type or paste text are disabled while the clipboard is read.
    public var pasteDisabled: Bool { isLoading }
    public var typeOrPasteDisabled: Bool { isLoading }

    /// The inline message for the current state, if any.
    public var message: String? {
        switch pasteState {
        case .idle, .both: nil
        case .loading: NutritionLabelEntryText.loading
        case .failed: NutritionLabelEntryText.imageFailed
        case .nothing: NutritionLabelEntryText.nothing
        }
    }

    /// The buttons the state offers, in order.
    public var choices: [String] {
        switch pasteState {
        case .both: [NutritionLabelEntryText.readImage, NutritionLabelEntryText.readText]
        case .failed(offersText: true): [NutritionLabelEntryText.readText]
        default: []
        }
    }

    /// Whether a payload is held (for tests of the drop rules).
    public var holdsPayload: Bool { pendingImage != nil || pendingText != nil }

    // MARK: Paste

    public func handle(_ event: NutritionLabelPasteEvent) {
        switch event {
        case .loading:
            drop()
            pasteState = .loading
        case let .loaded(imageData, text):
            // A late result after leaving, or one never asked for, is ignored.
            guard pasteState == .loading else { return }
            let image = photosEnabled ? imageData : nil
            let usableText = NutritionLabelPasteKind.hasUsableText(text) ? text : nil
            switch NutritionLabelPasteKind.classify(hasImage: image != nil, hasText: usableText != nil) {
            case .image: route(image: image)
            case .text: route(text: usableText)
            case .both:
                pendingImage = image; pendingText = usableText
                pasteState = .both
            case .neither:
                pasteState = .nothing
            }
        case let .failed(text):
            guard pasteState == .loading else { return }
            // Neither route is called automatically (3.3).
            let usableText = NutritionLabelPasteKind.hasUsableText(text) ? text : nil
            pendingText = usableText
            pasteState = .failed(offersText: usableText != nil)
        case .cancelled:
            // The screen is not left showing "Reading the clipboard…" (Qodo review of #454).
            guard pasteState == .loading else { return }
            drop(); pasteState = .idle
        }
    }

    /// "Read the image with AI" in the Both choice: the text is dropped.
    public func readImage() {
        guard pasteState == .both, let image = pendingImage else { return }
        route(image: image)
    }

    /// "Read the text on this device" in the Both or failed-image choice: the image is dropped.
    public func readText() {
        switch pasteState {
        case .both, .failed(offersText: true): route(text: pendingText)
        default: return
        }
    }

    /// Type or paste text: the text screen opens empty, and nothing is read from the clipboard.
    public func typeOrPaste() {
        guard !typeOrPasteDisabled else { return }
        drop(); pasteState = .idle
        openText("")
    }

    // MARK: Photo section

    /// Take photo or Choose from library: the same path as a pasted image.
    public func photoChosen(_ data: Data) {
        guard photosEnabled else { return }
        drop(); pasteState = .idle; cameraDenied = false
        openImage(data)
    }

    public func cameraWasDenied() { cameraDenied = true }

    // MARK: Leaving

    /// Leaving the screen, or the app going to the background: both payloads are dropped and
    /// nothing is routed. A load still under way is ignored when it finishes.
    public func leave() {
        drop(); pasteState = .idle
    }

    private func drop() { pendingImage = nil; pendingText = nil }

    private func route(image: Data?) {
        guard let image else { return }
        drop(); pasteState = .idle
        openImage(image)
    }

    private func route(text: String?) {
        guard let text else { return }
        drop(); pasteState = .idle
        openText(text)
    }
}
