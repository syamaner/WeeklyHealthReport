#if os(iOS)
import FoodLedgerApplication
import SwiftUI
import UIKit

/// Crop to the label (docs/label-photo-ai-prefill-v1.md 7.1, 15, 17.2). The crop is a pure
/// `LabelCropRect` on the upright photo, with quarter turns applied after it. Corners drag (44 pt
/// handles), a drag inside the frame moves it, a pinch scales it, and Rotate turns 90°.
/// The preparer refuses a crop that is too small, with the 7.2 copy, on the next screen.
public struct LabelPhotoCropView: View {
    private let image: UIImage?
    private let use: (LabelCropRect) -> Void
    private let cancel: () -> Void
    @State private var rect: CGRect
    @State private var turns: Int
    @State private var dragStart: CGRect?
    @State private var pinchStart: CGRect?

    public init(photo: Data, initial: LabelCropRect, use: @escaping (LabelCropRect) -> Void, cancel: @escaping () -> Void) {
        image = UIImage(data: photo)
        self.use = use; self.cancel = cancel
        _rect = State(initialValue: CGRect(x: initial.x, y: initial.y, width: initial.width, height: initial.height))
        _turns = State(initialValue: initial.quarterTurns)
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("Drag the corners so the nutrition table fills the frame. Only this part is sent.")
                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            GeometryReader { geometry in
                if let image {
                    let fitted = Self.fitted(image.size, turns: turns, in: geometry.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image).resizable()
                            .frame(width: fitted.unrotated.width, height: fitted.unrotated.height)
                            .rotationEffect(.degrees(Double(turns % 4) * 90))
                            .position(x: fitted.frame.midX, y: fitted.frame.midY)
                            .accessibilityLabel("Photo to crop")
                        cropOverlay(fitted.frame)
                    }
                    .gesture(MagnifyGesture().onChanged { value in
                        let start = pinchStart ?? rect
                        pinchStart = start
                        rect = Self.scaled(start, by: value.magnification)
                    }.onEnded { _ in pinchStart = nil })
                } else {
                    Text("This photo could not be opened. Choose another photo.").padding()
                }
            }
            // Room for the 44 pt corner handles at the frame's edges.
            .padding(.horizontal, 24)
            HStack {
                Button("Cancel", action: cancel).frame(minHeight: 44)
                Spacer()
                Button { turns = (turns + 1) % 4 } label: { Label("Rotate", systemImage: "rotate.right") }
                    .frame(minHeight: 44)
                    .accessibilityValue("\(turns * 90) degrees")
                Spacer()
                Button("Use crop") {
                    if let crop = LabelCropRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height, quarterTurns: turns) {
                        use(crop)
                    }
                }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
                .accessibilityIdentifier("labelPhoto.useCrop")
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    /// The crop frame in view space. The crop is kept in upright-photo space; the display is
    /// turned by `turns`, so view points map back through the inverse turn.
    private func cropOverlay(_ frame: CGRect) -> some View {
        let shown = Self.toView(rect, turns: turns, in: frame)
        return ZStack(alignment: .topLeading) {
            Rectangle().path(in: shown).stroke(Color.white, lineWidth: 3)
            Rectangle().path(in: shown).stroke(Color.black, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            Color.clear.contentShape(Rectangle()).frame(width: shown.width, height: shown.height).offset(x: shown.minX, y: shown.minY)
                .gesture(DragGesture().onChanged { value in
                    let start = dragStart ?? rect
                    dragStart = start
                    let delta = Self.toPhoto(value.translation, turns: turns, in: frame)
                    rect = Self.clamped(start.offsetBy(dx: delta.width, dy: delta.height), keepingSize: true)
                }.onEnded { _ in dragStart = nil })
                .accessibilityLabel("Crop frame")
            ForEach(0..<4, id: \.self) { corner in
                let point = Self.corner(corner, of: shown)
                Circle().fill(Color.white).overlay(Circle().stroke(Color.black, lineWidth: 1))
                    .frame(width: 22, height: 22)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .position(point)
                    .gesture(DragGesture().onChanged { value in
                        let start = dragStart ?? rect
                        dragStart = start
                        let delta = Self.toPhoto(value.translation, turns: turns, in: frame)
                        rect = Self.moved(corner: Self.photoCorner(corner, turns: turns), of: start, by: delta)
                    }.onEnded { _ in dragStart = nil })
                    .accessibilityLabel("Crop corner \(corner + 1)")
            }
        }
    }

    // MARK: Geometry (pure)

    struct Fitted { let frame: CGRect; let unrotated: CGSize }

    static func fitted(_ size: CGSize, turns: Int, in container: CGSize) -> Fitted {
        let turned = turns % 2 == 1 ? CGSize(width: size.height, height: size.width) : size
        let scale = min(container.width / max(turned.width, 1), container.height / max(turned.height, 1))
        let shown = CGSize(width: turned.width * scale, height: turned.height * scale)
        let frame = CGRect(x: (container.width - shown.width) / 2, y: (container.height - shown.height) / 2, width: shown.width, height: shown.height)
        return Fitted(frame: frame, unrotated: CGSize(width: size.width * scale, height: size.height * scale))
    }

    /// A normalised upright-photo point to its normalised position on the turned display.
    static func turn(_ p: CGPoint, _ turns: Int) -> CGPoint {
        switch ((turns % 4) + 4) % 4 {
        case 1: CGPoint(x: 1 - p.y, y: p.x)
        case 2: CGPoint(x: 1 - p.x, y: 1 - p.y)
        case 3: CGPoint(x: p.y, y: 1 - p.x)
        default: p
        }
    }

    static func toView(_ r: CGRect, turns: Int, in frame: CGRect) -> CGRect {
        let a = turn(CGPoint(x: r.minX, y: r.minY), turns), b = turn(CGPoint(x: r.maxX, y: r.maxY), turns)
        return CGRect(x: frame.minX + min(a.x, b.x) * frame.width, y: frame.minY + min(a.y, b.y) * frame.height,
                      width: abs(a.x - b.x) * frame.width, height: abs(a.y - b.y) * frame.height)
    }

    /// A view translation as a normalised upright-photo translation.
    static func toPhoto(_ t: CGSize, turns: Int, in frame: CGRect) -> CGSize {
        let dx = t.width / max(frame.width, 1), dy = t.height / max(frame.height, 1)
        switch ((turns % 4) + 4) % 4 {
        case 1: return CGSize(width: dy, height: -dx)
        case 2: return CGSize(width: -dx, height: -dy)
        case 3: return CGSize(width: -dy, height: dx)
        default: return CGSize(width: dx, height: dy)
        }
    }

    /// Corner 0 top-left, 1 top-right, 2 bottom-right, 3 bottom-left of the shown frame.
    static func corner(_ index: Int, of r: CGRect) -> CGPoint {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)][index]
    }

    /// The upright-photo corner a shown corner is, under the turn.
    static func photoCorner(_ shown: Int, turns: Int) -> Int { ((shown - turns) % 4 + 4) % 4 }

    static func moved(corner: Int, of r: CGRect, by d: CGSize) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch corner {
        case 0: minX += d.width; minY += d.height
        case 1: maxX += d.width; minY += d.height
        case 2: maxX += d.width; maxY += d.height
        default: minX += d.width; maxY += d.height
        }
        let minimum = 0.05
        minX = max(0, min(minX, maxX - minimum)); minY = max(0, min(minY, maxY - minimum))
        maxX = min(1, max(maxX, minX + minimum)); maxY = min(1, max(maxY, minY + minimum))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func scaled(_ r: CGRect, by factor: CGFloat) -> CGRect {
        let width = min(1, max(0.05, r.width * factor)), height = min(1, max(0.05, r.height * factor))
        return clamped(CGRect(x: r.midX - width / 2, y: r.midY - height / 2, width: width, height: height), keepingSize: true)
    }

    static func clamped(_ r: CGRect, keepingSize: Bool) -> CGRect {
        CGRect(x: min(max(0, r.minX), 1 - r.width), y: min(max(0, r.minY), 1 - r.height), width: r.width, height: r.height)
    }
}
#endif
