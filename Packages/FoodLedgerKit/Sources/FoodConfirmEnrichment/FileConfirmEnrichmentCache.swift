import FoodLedgerApplication
import Foundation

/// `confirm-enrichment-cache-v1.json` (docs/confirm-enrichment-openrouter-v1.md CE1.2; phase gate
/// section 2.5), under `ConfirmEnrichmentCachePolicy`. A corrupt, unknown-schema or over-size file is
/// deleted whole and rebuilt empty; a read failure is a miss. Writes are atomic with complete file
/// protection where the platform has it, in the backup-excluded directory the composition root gives.
public final class FileConfirmEnrichmentCache: ConfirmEnrichmentCaching, @unchecked Sendable {
    public static let fileName = "confirm-enrichment-cache-v1.json"
    public let url: URL
    private let lock = NSLock()
    private let encoder: any CanonicalEncoding

    public init(url: URL, encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder()) {
        self.url = url; self.encoder = encoder
    }

    /// The stored answers; a file that must be discarded is deleted here.
    private func load() -> [ConfirmEnrichmentCachedAnswer] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? Int.max
        guard size <= ConfirmEnrichmentCachePolicy.maximumFileBytes, let data = FileManager.default.contents(atPath: url.path),
              let answers = ConfirmEnrichmentCachePolicy.decode(data) else {
            try? FileManager.default.removeItem(at: url)
            return []
        }
        return answers
    }

    private func write(_ answers: [ConfirmEnrichmentCachedAnswer]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ConfirmEnrichmentCachePolicy.encode(answers, encoder: encoder).write(to: url, options: FileConfirmEnrichmentDayLedger.writeOptions)
        } catch {
            // A failed write is a later miss, never a reason to send twice within the same Confirm.
        }
    }

    public func answer(subject: String, part: ConfirmEnrichmentPart, now: Date) -> ConfirmEnrichmentCachedAnswer? {
        lock.withLock { ConfirmEnrichmentCachePolicy.lookup(load(), subject: subject, part: part, now: now) }
    }

    public func store(_ answer: ConfirmEnrichmentCachedAnswer, now: Date) {
        lock.withLock { write(ConfirmEnrichmentCachePolicy.storing(answer, in: load(), now: now)) }
    }

    public func remove(subject: String, part: ConfirmEnrichmentPart) {
        lock.withLock { write(ConfirmEnrichmentCachePolicy.removing(subject: subject, part: part, from: load())) }
    }

    public func clear() {
        lock.withLock { _ = try? FileManager.default.removeItem(at: url) }
    }
}
