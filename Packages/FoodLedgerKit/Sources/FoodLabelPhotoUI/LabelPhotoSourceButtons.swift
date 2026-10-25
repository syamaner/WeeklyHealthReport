#if os(iOS)
import AVFoundation
import FoodLedgerApplication
import PhotosUI
import SwiftUI
import UIKit

/// Take photo and Choose from library (docs/label-photo-ai-prefill-v1.md 4.1, 7.1, 7.2, 15).
/// The camera asks for permission only when chosen; a denied camera calls `cameraDenied` so the
/// screen shows the 7.2 copy with the library still offered. The library uses the system
/// PhotosPicker, which runs out of process and needs no library permission. AVFoundation is used
/// only for the camera's authorisation status (17.19).
public struct LabelPhotoSourceButtons: View {
    private let photo: (Data) -> Void
    private let cameraDenied: () -> Void
    /// The fake route's photo source (17.19): Choose from library yields this synthetic label.
    private let sample: Data?
    @State private var item: PhotosPickerItem?
    @State private var showsCamera = false

    public init(photo: @escaping (Data) -> Void, cameraDenied: @escaping () -> Void, sample: Data? = nil) {
        self.photo = photo; self.cameraDenied = cameraDenied; self.sample = sample
    }

    public var body: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button { takePhoto() } label: {
                Label("Take photo", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .sheet(isPresented: $showsCamera) {
                CameraPicker(photo: { data in showsCamera = false; photo(data) }, cancel: { showsCamera = false })
                    .ignoresSafeArea()
            }
        }
        if let sample {
            Button { photo(sample) } label: {
                Label("Choose from library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("labelPhoto.chooseFromLibrary")
        } else {
            PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                Label("Choose from library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("labelPhoto.chooseFromLibrary")
            .onChange(of: item) { _, chosen in
                guard let chosen else { return }
                Task { @MainActor in
                    if let data = try? await chosen.loadTransferable(type: Data.self) { photo(data) }
                    item = nil
                }
            }
        }
    }

    private func takePhoto() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showsCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in if granted { showsCamera = true } else { cameraDenied() } }
            }
        default: cameraDenied()
        }
    }
}

/// The system camera, returning the photo's bytes. The preparer later removes every metadata
/// block; nothing is written to the photo library.
struct CameraPicker: UIViewControllerRepresentable {
    let photo: (Data) -> Void
    let cancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(photo: photo, cancel: cancel) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let photo: (Data) -> Void
        let cancel: () -> Void
        init(photo: @escaping (Data) -> Void, cancel: @escaping () -> Void) { self.photo = photo; self.cancel = cancel }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) { photo(data) } else { cancel() }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { cancel() }
    }
}

/// The synthetic Taiwan label the fake route reads, drawn on device from its lines (17.19). Never
/// a real photo.
public enum LabelPhotoSyntheticRenderer {
    public static func jpeg(lines: [[String]]) -> Data {
        let size = CGSize(width: 900, height: 120 + CGFloat(lines.count) * 90)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // Traditional Chinese glyphs, as printed on Taiwan labels (the system font's fallback
            // may pick another CJK face).
            let font = UIFont(name: "PingFangTC-Regular", size: 44) ?? UIFont.systemFont(ofSize: 44)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            let columns: [CGFloat] = [60, 400, 650]
            for (index, line) in lines.enumerated() {
                let y = 60 + CGFloat(index) * 90
                for (column, text) in line.enumerated() where column < columns.count {
                    (text as NSString).draw(at: CGPoint(x: columns[column], y: y), withAttributes: attributes)
                }
            }
            UIColor.black.setStroke()
            context.stroke(CGRect(x: 30, y: 30, width: size.width - 60, height: size.height - 60))
        }
        return image.jpegData(compressionQuality: 0.95) ?? Data()
    }
}
#endif
