#if os(iOS)
import AVFoundation
import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI
import Vision
import VisionKit

@MainActor
public final class VisionKitBarcodeScanner: NSObject, BarcodeScanning {
    public let viewController: DataScannerViewController
    private var continuation: CheckedContinuation<BarcodeScan, any Error>?

    public override init() {
        viewController = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [
                .ean8, .ean13, .upce, .code128, .dataMatrix, .qr
            ])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        super.init()
        viewController.delegate = self
    }

    public func authorization() async -> BarcodeCameraAuthorization {
        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorised
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .authorised : .denied
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .unavailable
        }
    }

    public func scan() async throws -> BarcodeScan {
        guard continuation == nil else { throw ScannerError.captureAlreadyActive }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { value in
                guard !Task.isCancelled else {
                    value.resume(throwing: CancellationError())
                    return
                }
                continuation = value
                do {
                    try viewController.startScanning()
                } catch {
                    continuation = nil
                    value.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    public func cancel() {
        viewController.stopScanning()
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    public enum ScannerError: Error, Equatable {
        case captureAlreadyActive
        case missingPayload
    }
}

extension VisionKitBarcodeScanner: DataScannerViewControllerDelegate {
    public func dataScanner(
        _ dataScanner: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        guard continuation != nil else { return }
        for item in addedItems {
            guard case let .barcode(barcode) = item,
                  let payload = barcode.payloadStringValue,
                  let code = try? LedgerText(payload),
                  let original = try? LedgerText(barcode.observation.symbology.rawValue),
                  let locale = try? LedgerText(Locale.current.identifier),
                  let method = try? LedgerText("visionkit"),
                  let methodVersion = try? LedgerText("visionkit-barcode-v1") else { continue }
            let scan = BarcodeScan(
                code: code,
                symbology: Self.map(barcode.observation.symbology),
                originalSymbology: original,
                capturedAt: Date(),
                locale: locale,
                captureMethod: method,
                captureMethodVersion: methodVersion
            )
            dataScanner.stopScanning()
            continuation?.resume(returning: scan)
            continuation = nil
            return
        }
    }

    public func dataScanner(
        _ dataScanner: DataScannerViewController,
        becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
    ) {
        dataScanner.stopScanning()
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private static func map(_ value: VNBarcodeSymbology) -> FoodLedgerDomain.BarcodeSymbology {
        switch value {
        case .ean8: .ean8
        case .ean13: .ean13
        case .upce: .upce
        case .code128: .code128
        case .dataMatrix: .dataMatrix
        case .qr: .qr
        default: .unknown
        }
    }
}

public struct VisionKitBarcodeScannerView: UIViewControllerRepresentable {
    private let scanner: VisionKitBarcodeScanner

    public init(scanner: VisionKitBarcodeScanner) {
        self.scanner = scanner
    }

    public func makeUIViewController(context: Context) -> DataScannerViewController {
        scanner.viewController
    }

    public func updateUIViewController(
        _ uiViewController: DataScannerViewController,
        context: Context
    ) {}
}
#endif
