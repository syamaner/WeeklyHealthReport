#if os(iOS)
import FoodLedgerApplication
import SwiftUI
import UIKit

/// The photo pane on Confirm (docs/label-photo-ai-prefill-v1.md section 5). Pinch to zoom from 1x
/// to 8x, drag to pan, double-tap to toggle between fit and 3x at the tapped point, Fit to reset,
/// Full screen. A focused value is centred at a legible scale and drawn with a 2 pt outline plus a
/// white-backed caption, so it never relies on colour alone. VoiceOver: one adjustable element;
/// swipe up or down zooms. Display only: it edits nothing and sends nothing.
public struct LabelPhotoPane: View {
    /// A region normalised to the photo (origin top left), its caption, and a request counter so
    /// the same value can be re-centred.
    public struct Highlight: Equatable {
        public let rect: CGRect?
        public let caption: String
        public let request: Int
        public init(rect: CGRect?, caption: String, request: Int) { self.rect = rect; self.caption = caption; self.request = request }
    }

    public static let minimumScale: CGFloat = 1
    public static let maximumScale: CGFloat = 8
    public static let doubleTapScale: CGFloat = 3

    private let image: UIImage?
    private let highlight: Highlight?
    private let fullScreen: (() -> Void)?
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var pinchStart: CGFloat?
    @State private var panStart: CGSize?

    public init(photo: Data, highlight: Highlight?, fullScreen: (() -> Void)?) {
        image = UIImage(data: photo); self.highlight = highlight; self.fullScreen = fullScreen
    }

    public var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                if let image {
                    let fitted = Self.fittedFrame(image.size, in: geometry.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image).resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .scaleEffect(scale)
                            .offset(offset)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        if let rect = highlight?.rect {
                            highlightOverlay(Self.viewRect(rect, fitted: fitted, container: geometry.size, scale: scale, offset: offset))
                        }
                    }
                    .clipped()
                    .contentShape(Rectangle())
                    // Pan only while zoomed in, so a vertical swipe on the fitted photo scrolls Confirm.
                    .simultaneousGesture(DragGesture().onChanged { value in
                        let start = panStart ?? offset
                        panStart = start
                        offset = Self.clampedOffset(CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height),
                                                    scale: scale, fitted: fitted, container: geometry.size)
                    }.onEnded { _ in panStart = nil }, including: scale > 1.01 ? .all : .subviews)
                    .gesture(
                        MagnifyGesture().onChanged { value in
                            let start = pinchStart ?? scale
                            pinchStart = start
                            scale = Self.clampedScale(start * value.magnification)
                            offset = Self.clampedOffset(offset, scale: scale, fitted: fitted, container: geometry.size)
                        }.onEnded { _ in pinchStart = nil })
                    .onTapGesture(count: 2, coordinateSpace: .local) { location in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if scale > 1.01 { scale = 1; offset = .zero } else {
                                scale = Self.doubleTapScale
                                let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                offset = Self.clampedOffset(CGSize(width: (centre.x - location.x) * (scale - 1), height: (centre.y - location.y) * (scale - 1)),
                                                            scale: scale, fitted: fitted, container: geometry.size)
                            }
                        }
                    }
                    .onChange(of: highlight) { _, focus in
                        guard let focus else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            (scale, offset) = Self.focus(focus.rect, fitted: fitted, container: geometry.size)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Label photo")
                    .accessibilityValue(highlight.map { "Showing \($0.caption)" } ?? "Zoom \(Int(scale.rounded()))x")
                    .accessibilityHint("Swipe up or down to zoom.")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: scale = Self.clampedScale(scale * 1.5)
                        case .decrement: scale = Self.clampedScale(scale / 1.5)
                        @unknown default: break
                        }
                        offset = Self.clampedOffset(offset, scale: scale, fitted: fitted, container: geometry.size)
                    }
                    .accessibilityScrollAction { edge in
                        let step: CGFloat = 80
                        switch edge {
                        case .top: offset.height += step
                        case .bottom: offset.height -= step
                        case .leading: offset.width += step
                        case .trailing: offset.width -= step
                        }
                        offset = Self.clampedOffset(offset, scale: scale, fitted: fitted, container: geometry.size)
                    }
                    .accessibilityIdentifier("labelPhoto.pane")
                } else {
                    Text("The photo is not on this device.").padding()
                }
            }
            HStack {
                Button("Fit") { withAnimation { scale = 1; offset = .zero } }.frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("labelPhoto.fit")
                Spacer()
                if let fullScreen {
                    Button("Full screen", action: fullScreen).frame(minHeight: 44).accessibilityIdentifier("labelPhoto.fullScreen")
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func highlightOverlay(_ rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().path(in: rect.insetBy(dx: -3, dy: -3)).stroke(Color.accentColor, lineWidth: 2)
            if let caption = highlight?.caption {
                Text(caption).font(.caption.weight(.semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.4), lineWidth: 1))
                    .offset(x: rect.minX, y: max(0, rect.minY - 26))
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("labelPhoto.highlight")
    }

    // MARK: Geometry (pure)

    static func fittedFrame(_ size: CGSize, in container: CGSize) -> CGSize {
        let scale = min(container.width / max(size.width, 1), container.height / max(size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    static func clampedScale(_ value: CGFloat) -> CGFloat { min(maximumScale, max(minimumScale, value)) }

    /// Keeps the zoomed photo covering the pane where it can.
    static func clampedOffset(_ offset: CGSize, scale: CGFloat, fitted: CGSize, container: CGSize) -> CGSize {
        let limitX = max(0, (fitted.width * scale - container.width) / 2)
        let limitY = max(0, (fitted.height * scale - container.height) / 2)
        return CGSize(width: min(limitX, max(-limitX, offset.width)), height: min(limitY, max(-limitY, offset.height)))
    }

    /// A normalised region in view coordinates under the current zoom and pan.
    static func viewRect(_ region: CGRect, fitted: CGSize, container: CGSize, scale: CGFloat, offset: CGSize) -> CGRect {
        let centre = CGPoint(x: container.width / 2, y: container.height / 2)
        let x = (region.minX - 0.5) * fitted.width * scale + centre.x + offset.width
        let y = (region.minY - 0.5) * fitted.height * scale + centre.y + offset.height
        return CGRect(x: x, y: y, width: region.width * fitted.width * scale, height: region.height * fitted.height * scale)
    }

    /// The zoom and pan that centre a region at a legible scale (about a third of the pane wide),
    /// or fit the whole photo when there is no region.
    static func focus(_ region: CGRect?, fitted: CGSize, container: CGSize) -> (CGFloat, CGSize) {
        guard let region, region.width > 0, region.height > 0 else { return (1, .zero) }
        let target = clampedScale(min(container.width * 0.35 / (region.width * fitted.width),
                                      container.height * 0.35 / (region.height * fitted.height)))
        let offset = CGSize(width: -(region.midX - 0.5) * fitted.width * target, height: -(region.midY - 0.5) * fitted.height * target)
        return (target, clampedOffset(offset, scale: target, fitted: fitted, container: container))
    }
}

/// The prepared crop on the Label photo screen, as it will be sent: display only.
public struct LabelPhotoPreview: View {
    private let image: UIImage?
    public init(photo: Data) { image = UIImage(data: photo) }
    public var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 240)
        } else {
            Text("The photo is not on this device.")
        }
    }
}

/// The pane in a sheet, keeping the highlight.
public struct LabelPhotoFullScreenPane: View {
    private let photo: Data
    private let highlight: LabelPhotoPane.Highlight?
    private let done: () -> Void

    public init(photo: Data, highlight: LabelPhotoPane.Highlight?, done: @escaping () -> Void) {
        self.photo = photo; self.highlight = highlight; self.done = done
    }

    public var body: some View {
        NavigationStack {
            LabelPhotoPane(photo: photo, highlight: highlight, fullScreen: nil)
                .padding()
                .navigationTitle("Label photo")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) } }
        }
    }
}
#endif
