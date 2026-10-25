import FoodLabelPhotoReading
import FoodLedgerApplication
import Foundation

/// What the composition root needs from the reader, which the app never links directly (17.2):
/// the frozen-rule reader behind the application's port.
public enum LabelPhotoComponents {
    public static func interpreter() -> any LabelPhotoInterpreting { LabelPhotoReader() }
}

/// Waits between attempts with `Task.sleep`, throwing at once on cancellation.
public struct TaskLabelPhotoSleeper: LabelPhotoSleeping {
    public init() {}
    public func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}
