import FoodLedgerApplication
import Foundation

/// `confirm-enrichment-day-v1.json` (docs/confirm-enrichment-openrouter-v1-phase.md section 2.6): the
/// day record in one small JSON file, beside the cache in the backup-excluded, file-protected app data
/// directory the composition root gives it. A missing file is `.absent`; a file that cannot be read or
/// decoded is `.unreadable`, which the spend policy closes for the day. Each update is one
/// read-modify-write under file coordination and an in-process lock, with an atomic write; a transform
/// that throws stores nothing. Separate from `label-ai-spend-day-v1`.
public final class FileConfirmEnrichmentDayLedger: ConfirmEnrichmentSpendLedger, @unchecked Sendable {
    public static let fileName = "confirm-enrichment-day-v1.json"
    public let url: URL
    private let lock = NSLock()
    private let encoder: any CanonicalEncoding

    public init(url: URL, encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder()) {
        self.url = url; self.encoder = encoder
    }

    static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }

    public func read() -> ConfirmEnrichmentSpendPolicy.Stored {
        lock.withLock { Self.read(url) }
    }

    static func read(_ url: URL) -> ConfirmEnrichmentSpendPolicy.Stored {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let data = FileManager.default.contents(atPath: url.path),
              let day = try? JSONDecoder().decode(ConfirmEnrichmentSpendPolicy.Day.self, from: data) else { return .unreadable }
        return .day(day)
    }

    @discardableResult
    public func update(_ transform: (ConfirmEnrichmentSpendPolicy.Stored) throws -> ConfirmEnrichmentSpendPolicy.Day) throws
        -> ConfirmEnrichmentSpendPolicy.Day {
        try lock.withLock {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var coordinationError: NSError?
            var result: Result<ConfirmEnrichmentSpendPolicy.Day, Error> = .failure(CocoaError(.fileWriteUnknown))
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { target in
                result = Result {
                    let day = try transform(Self.read(target))
                    try encoder.encode(day).write(to: target, options: Self.writeOptions)
                    return day
                }
            }
            if let coordinationError { throw coordinationError }
            return try result.get()
        }
    }
}
