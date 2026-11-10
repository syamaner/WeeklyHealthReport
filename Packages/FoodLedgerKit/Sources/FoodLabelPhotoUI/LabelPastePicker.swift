#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Nutrition label screen's Paste control (docs/nutrition-label-entry-v1.md 3.3 and 6): the
/// system `PasteButton`, which the system enables only when the clipboard holds a supported type
/// and which shows no paste prompt. The clipboard is read only when it is tapped. This is the only
/// package source that uses `PasteButton`, `NSItemProvider` or `UIPasteboard`.
///
/// With `acceptsImages` false only plain text is requested, so image bytes are never loaded. An
/// image is kept only when it opens as an image; the first plain-text item is passed on exactly
/// as it was. The load is cancelled when the control disappears. Nothing is written to disk.
public struct LabelPastePicker: View {
    public enum Event: Equatable, Sendable {
        case loading
        case loaded(imageData: Data?, text: String?)
        /// An image was offered but could not be loaded or opened.
        case failed(text: String?)
    }

    /// A DEBUG-only synthetic payload (6.2 test 10): tapping emits `.loading`, then this payload
    /// through the same image check, instead of reading the clipboard.
    public struct Sample: Equatable, Sendable {
        public let imageData: Data?
        public let text: String?
        public init(imageData: Data?, text: String?) { self.imageData = imageData; self.text = text }
    }

    private let acceptsImages: Bool
    private let sample: Sample?
    private let events: (Event) -> Void
    @State private var task: Task<Void, Never>?

    public init(acceptsImages: Bool, sample: Sample? = nil, events: @escaping (Event) -> Void) {
        self.acceptsImages = acceptsImages; self.sample = sample; self.events = events
    }

    /// The requested types: images and text when the photo route is not off, plain text only when off.
    public static func contentTypes(acceptsImages: Bool) -> [UTType] {
        acceptsImages ? [.image, .plainText] : [.plainText]
    }

    public var body: some View {
        Group {
            if let sample {
                Button { paste(sample) } label: {
                    Label("Paste", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            } else {
                PasteButton(supportedContentTypes: Self.contentTypes(acceptsImages: acceptsImages)) { providers in
                    Task { @MainActor in paste(providers) }
                }
                .frame(minHeight: 44)
            }
        }
        .accessibilityIdentifier("nutritionLabel.paste")
        .onDisappear { task?.cancel(); task = nil }
    }

    @MainActor private func paste(_ providers: [NSItemProvider]) {
        task?.cancel()
        events(.loading)
        let acceptsImages = acceptsImages
        let image = acceptsImages ? providers.first { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) } : nil
        let text = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
        let pending = Pending(image: image, text: text)
        task = Task { @MainActor in
            let imageData = await pending.loadImage()
            let text = await pending.loadText()
            guard !Task.isCancelled else { return }
            events(Self.event(offeredImage: pending.image != nil, imageData: imageData, text: text))
        }
    }

    @MainActor private func paste(_ sample: Sample) {
        task?.cancel()
        events(.loading)
        task = Task { @MainActor in
            // Long enough for the loading state to be seen and checked.
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            events(Self.event(offeredImage: acceptsImages && sample.imageData != nil, imageData: acceptsImages ? sample.imageData : nil,
                              text: sample.text))
        }
    }

    /// An offered image counts only when its bytes open as an image.
    static func event(offeredImage: Bool, imageData: Data?, text: String?) -> Event {
        guard offeredImage else { return .loaded(imageData: nil, text: text) }
        guard let imageData, UIImage(data: imageData) != nil else { return .failed(text: text) }
        return .loaded(imageData: imageData, text: text)
    }

    /// The providers chosen for loading. Item providers are not `Sendable`; they stay on the main
    /// actor, and only `Data` and `String` come back from their callbacks.
    @MainActor private final class Pending {
        let image: NSItemProvider?
        let text: NSItemProvider?
        init(image: NSItemProvider?, text: NSItemProvider?) { self.image = image; self.text = text }

        func loadImage() async -> Data? {
            guard let image else { return nil }
            let load = LoadHandle()
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    load.progress = image.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        continuation.resume(returning: data)
                    }
                }
            } onCancel: { load.cancel() }
        }

        func loadText() async -> String? {
            guard let text else { return nil }
            let load = LoadHandle()
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    load.progress = text.loadObject(ofClass: NSString.self) { reading, _ in
                        continuation.resume(returning: (reading as? NSString).map { String($0) })
                    }
                }
            } onCancel: { load.cancel() }
        }
    }

    /// The item provider's load, cancelled when the paste task is cancelled (leaving the screen or a
    /// new paste), so the provider stops delivering and is released. A cancelled load still calls
    /// its completion, with no data, so the continuation always resumes.
    private final class LoadHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var _progress: Progress?
        var progress: Progress? {
            get { lock.withLock { _progress } }
            set {
                let cancelNow = lock.withLock { _progress = newValue; return cancelled }
                if cancelNow { newValue?.cancel() }
            }
        }
        func cancel() {
            let current = lock.withLock { cancelled = true; return _progress }
            current?.cancel()
        }
    }
}
#endif
