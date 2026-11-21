import ConfirmEnrichmentEvalCore
import FoodLedgerApplication
import Foundation

/// Private evidence for one completed logical request. Only the accepted attempt's bytes can
/// contribute fills or kept nutrients. Costs and elapsed time include retries.
struct EvalRequestEvidence: Codable {
    static let version = "confirm-enrichment-eval-request-v1"
    let schema: String
    let runID: UUID
    let requestSHA256: String
    let responseSHA256: String?
    let attempt: Int
    let timing: EvalScoring.Timing

    init(runID: UUID, request: Data, response: Data?, attempt: Int, timing: EvalScoring.Timing) throws {
        schema = Self.version
        self.runID = runID
        requestSHA256 = try Self.hash(request)
        responseSHA256 = try response.map(Self.hash)
        self.attempt = attempt
        self.timing = timing
    }

    static func hash(_ bytes: Data) throws -> String { try SHA256Digester().sha256(bytes).value }

    static func responseURL(folder: URL, hash: String, part: ConfirmEnrichmentPart, attempt: Int) -> URL {
        folder.appendingPathComponent("responses").appendingPathComponent("\(hash)-\(part.rawValue)-\(attempt).json")
    }

    static func evidenceURL(folder: URL, hash: String, part: ConfirmEnrichmentPart) -> URL {
        folder.appendingPathComponent("responses").appendingPathComponent("\(hash)-\(part.rawValue)-evidence.json")
    }

    func write(folder: URL, hash: String, part: ConfirmEnrichmentPart) throws {
        let url = Self.evidenceURL(folder: folder, hash: hash, part: part)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func read(folder: URL, hash: String, part: ConfirmEnrichmentPart, runID: UUID, request: Data) throws -> (EvalScoring.Timing, Data?) {
        let url = evidenceURL(folder: folder, hash: hash, part: part)
        let evidence = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard evidence.schema == version, evidence.runID == runID, evidence.requestSHA256 == (try Self.hash(request)),
              (1...ConfirmEnrichmentRetryPolicy.maxAttempts).contains(evidence.attempt),
              evidence.timing.elapsedSeconds.isFinite, evidence.timing.elapsedSeconds >= 0 else { throw Invalid() }
        guard let expected = evidence.responseSHA256 else { return (evidence.timing, nil) }
        let response = try Data(contentsOf: responseURL(folder: folder, hash: hash, part: part, attempt: evidence.attempt))
        guard try Self.hash(response) == expected else { throw Invalid() }
        return (evidence.timing, response)
    }

    struct Invalid: Error {}
}

/// A probe or a partial run cannot be scored as a completed set. Each completion binds the
/// request evidence to one run and to the original, unhidden case list.
struct EvalCompletedRun: Codable {
    static let version = "confirm-enrichment-eval-completed-run-v1"
    let schema: String
    let runID: UUID
    let manifestSHA256: String

    private static func url(folder: URL, part: ConfirmEnrichmentPart) -> URL {
        folder.appendingPathComponent("completed-\(part.rawValue).json")
    }

    static func write(runID: UUID, list: EvalCaseList, folder: URL, part: ConfirmEnrichmentPart) throws {
        let manifest = try EvalHashes.manifest(list)
        let record = Self(schema: version, runID: runID, manifestSHA256: manifest.sha256)
        try JSONEncoder().encode(record).write(to: url(folder: folder, part: part), options: .atomic)
    }

    static func read(list: EvalCaseList, folder: URL, part: ConfirmEnrichmentPart) throws -> UUID {
        let manifest = try EvalHashes.manifest(list)
        let data = try Data(contentsOf: url(folder: folder, part: part))
        let record = try JSONDecoder().decode(Self.self, from: data)
        guard record.schema == version, record.manifestSHA256 == manifest.sha256 else { throw EvalRequestEvidence.Invalid() }
        return record.runID
    }
}
