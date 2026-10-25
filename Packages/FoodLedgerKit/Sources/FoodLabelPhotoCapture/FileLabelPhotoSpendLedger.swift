import FoodLedgerApplication
import Foundation

/// Today's label photo reads and cost in one small JSON file (docs/label-photo-ai-prefill-v1.md
/// E10, 17.8 L2 and L4, 17.18; contract tests 24 and 25). The composition root puts it under the
/// backup-excluded, file-protected health-data directory, beside the attachments root. A missing
/// file is a fresh day; a file that cannot be read or decoded is `.unreadable`, which fails closed
/// (the route shows the daily limit and sends nothing). Each update is one read-modify-write under
/// file coordination (other processes and threads) and an in-process lock, with an atomic write.
public final class FileLabelPhotoSpendLedger: LabelPhotoSpendLedger, @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()

    public init(url: URL) { self.url = url }

    public func load() -> LabelPhotoSpendPolicy.Stored {
        lock.withLock { Self.read(url) }
    }

    static func read(_ url: URL) -> LabelPhotoSpendPolicy.Stored {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let data = FileManager.default.contents(atPath: url.path),
              let day = try? JSONDecoder().decode(LabelPhotoSpendPolicy.Day.self, from: data) else { return .unreadable }
        return .day(day)
    }

    @discardableResult
    public func update(_ transform: (LabelPhotoSpendPolicy.Stored) throws -> LabelPhotoSpendPolicy.Day) throws -> LabelPhotoSpendPolicy.Day {
        try lock.withLock {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var coordinationError: NSError?
            var result: Result<LabelPhotoSpendPolicy.Day, Error> = .failure(CocoaError(.fileWriteUnknown))
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { target in
                result = Result {
                    let day = try transform(Self.read(target))
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys]
                    try encoder.encode(day).write(to: target, options: [.atomic, .completeFileProtection])
                    return day
                }
            }
            if let coordinationError { throw coordinationError }
            return try result.get()
        }
    }
}
