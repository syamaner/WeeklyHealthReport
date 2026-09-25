import FoodLedgerApplication
import SwiftUI

public enum BarcodeCapturePhase: Equatable, Sendable {
    case idle, capturing
    case result(BarcodeCaptureOutcome)
    case failed
}

@MainActor
public final class BarcodeCaptureViewModel: ObservableObject {
    @Published public private(set) var phase: BarcodeCapturePhase = .idle
    private let coordinator: BarcodeCaptureCoordinator
    private var generation = 0

    public init(coordinator: BarcodeCaptureCoordinator) { self.coordinator = coordinator }

    public func capture(using scanner: any BarcodeScanning) async {
        guard phase != .capturing else { return }
        generation += 1
        let attempt = generation
        phase = .capturing
        do {
            let result = try await coordinator.capture(using: scanner)
            guard attempt == generation else { return }
            phase = Task.isCancelled ? .idle : .result(result)
        } catch is CancellationError {
            if attempt == generation { phase = .idle }
        } catch {
            guard attempt == generation else { return }
            phase = Task.isCancelled ? .idle : .failed
        }
    }

    public func cancel() {
        generation += 1
        if phase == .capturing { phase = .idle }
    }

    public func showUnavailable() {
        cancel()
        phase = .result(.permissionGuidance(BarcodePermissionGuidance(unavailable: true)))
    }
}
