import FoodLedgerApplication
import Foundation

/// Every line the tool prints (G11): a case is named only by the short form of its hash, and no line
/// holds a request body, a response, a barcode or a description. Lines are built here from closed codes
/// and numbers only, so no other file formats case data for the console.
public enum EvalConsole {
    public enum Outcome: String, Sendable {
        case answered, failedChecks = "failed_checks", notSent = "not_sent", transportFailed = "transport_failed"
        case refusedByLedger = "refused_by_ledger", routeUnavailable = "route_unavailable", notEligible = "not_eligible"
        case buildRefused = "build_refused", caseUnreadable = "case_unreadable"
    }

    public static func caseLine(hash: String, part: String, outcome: Outcome, attempts: Int) -> String {
        "case \(EvalHashes.short(hash)) part \(part) outcome \(outcome.rawValue) attempts \(attempts)"
    }

    public static func manifestLine(_ manifest: EvalHashes.Manifest) -> String {
        "cases \(manifest.count) sha256 \(manifest.sha256)"
    }

    public static func summaryLine(part: String, counts: [Outcome: Int]) -> String {
        let parts = counts.keys.map(\.rawValue).sorted().map { name in "\(name) \(counts[Outcome(rawValue: name)!] ?? 0)" }
        return "summary part \(part) " + parts.joined(separator: " ")
    }

    /// The scan's pool: counts only.
    public static func poolLine(scanned: Int, eligible: Int, uk: Int, taiwan: Int, fortified: Int) -> String {
        "pool scanned \(scanned) eligible \(eligible) uk \(uk) taiwan \(taiwan) fortified \(fortified)"
    }

    /// One selected set: its closed count names and numbers only.
    public static func selectionLine(set: String, counts: [(String, Int)]) -> String {
        "selected \(set) " + counts.map { "\($0.0) \($0.1)" }.joined(separator: " ")
    }

    /// One set's committed manifest.
    public static func setManifestLine(set: String, _ manifest: EvalHashes.Manifest) -> String {
        "manifest \(set) " + manifestLine(manifest)
    }

    public static func scoreLine(_ result: EvalScoring.Result) -> String {
        let verdict = result.passed ? "pass" : "fail"
        return "\(result.part.rawValue) \(result.bar.rawValue) \(verdict) within \(result.within) outside \(result.outside)"
    }

    public static func firstRequestLine(part: ConfirmEnrichmentPart, maxTokensSent: Bool, sha256: String) -> String {
        "first_request \(part.rawValue) accepted max_tokens_sent \(maxTokensSent) sha256 \(sha256)"
    }

    /// A stop: the reason's code only, never case data.
    public static func stopLine(_ reason: String) -> String { "stop \(reason)" }
}
