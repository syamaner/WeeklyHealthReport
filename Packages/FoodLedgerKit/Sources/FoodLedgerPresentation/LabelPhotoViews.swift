import FoodLedgerApplication
import SwiftUI

/// What the photo pane is asked to show (docs/label-photo-ai-prefill-v1.md section 5): a value's
/// region, centred and outlined, with a caption, or a message when it was not found. Regions are
/// application types; `Rect` is normalised to the prepared image with the origin at the top left.
public struct LabelPhotoFocus: Equatable, Sendable {
    public struct Rect: Equatable, Sendable {
        public let x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
        /// A stored region is in Vision's normalised coordinates, origin bottom left (17.17); the
        /// pane draws from the top left, so the vertical position is flipped here.
        public init?(_ region: LabelPhotoManifest.Region?) {
            guard let region, let x = Double(region.x), let y = Double(region.y), let w = Double(region.w), let h = Double(region.h) else {
                return nil
            }
            self.init(x: x, y: max(0, 1 - y - h), width: w, height: h)
        }
    }

    /// The value's region; nil for a value not found on the photo (the pane fits the whole photo).
    public let region: Rect?
    /// The row label's region, drawn with a thinner dashed outline when found.
    public let rowLabel: Rect?
    /// "Fat, per 100 g": the white-backed caption beside the outline, so colour is never alone.
    public let caption: String
    /// Said under the photo when the value has no region.
    public let message: String?
    /// Increments on every request, so tapping the same value again re-centres it.
    public let request: Int

    public init(region: Rect?, rowLabel: Rect?, caption: String, message: String?, request: Int) {
        self.region = region; self.rowLabel = rowLabel; self.caption = caption; self.message = message; self.request = request
    }
}

/// The platform views the label photo route needs, provided by `FoodLabelPhotoUI` through the
/// composition root (17.2: presentation never imports UIKit, PhotosUI or ImageIO). Every view is
/// display or capture only: none edits a value or sends anything.
@MainActor
public protocol LabelPhotoViewFactory {
    /// Take photo and Choose from library. `photo` receives the chosen image's bytes; `cameraDenied`
    /// is called when camera access is off, so the screen can show the 7.2 copy.
    func sourceButtons(photo: @escaping (Data) -> Void, cameraDenied: @escaping () -> Void) -> AnyView
    /// The crop screen over the chosen photo: corners, pinch and pan, Rotate, Use crop, Cancel.
    func crop(photo: Data, initial: LabelCropRect, use: @escaping (LabelCropRect) -> Void, cancel: @escaping () -> Void) -> AnyView
    /// The prepared crop, as it will be sent.
    func preparedPhoto(_ bytes: Data) -> AnyView
    /// The zoomable photo pane with the focus highlight. `fullScreen` opens it in a sheet.
    func pane(_ bytes: Data, focus: LabelPhotoFocus?, fullScreen: @escaping () -> Void) -> AnyView
    /// The full-screen pane, keeping the highlight.
    func fullScreenPane(_ bytes: Data, focus: LabelPhotoFocus?, done: @escaping () -> Void) -> AnyView
}
