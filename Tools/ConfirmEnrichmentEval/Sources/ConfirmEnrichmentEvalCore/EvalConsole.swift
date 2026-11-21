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

    /// A stop: the reason's code only, never case data.
    public static func stopLine(_ reason: String) -> String { "stop \(reason)" }
}
