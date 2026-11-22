import FoodLedgerApplication
import FoodLedgerPresentation
import XCTest

/// The session-only "Last Confirm enrichment" lines in Developer tools (docs/confirm-enrichment-openrouter-v1.md
/// CE1.7): every listed item, the last request of each part with A first, and never a key or a body.
/// Synthetic values only.
@MainActor
final class ConfirmEnrichmentDiagnosticsTextTests: XCTestCase {
    static func diagnostics(_ use: OpenRouterUse, outcome: String = "answered") -> ConfirmEnrichmentDiagnostics {
        ConfirmEnrichmentDiagnostics(
            use: use, routeVersion: "synthetic-route-v1", endpoint: "https://example.invalid/v1", model: "synthetic/model",
            provider: "Synthetic", requestFields: ["asked", "description.name"], requestSHA256: String(repeating: "a", count: 64),
            responseSHA256: String(repeating: "b", count: 64), latencyMilliseconds: 1_234, attempts: 2, reportedCostMicroUSD: 870,
            threshold: use == .confirmEnrichmentDetails ? "0.85" : nil, fromCache: false, outcome: outcome)
    }

    func testTheLinesNameEveryItemAndNoBody() {
        let lines = ConfirmEnrichmentDiagnosticsText.lines(Self.diagnostics(.confirmEnrichmentDetails))
        XCTAssertEqual(lines, [
            "use: confirmEnrichmentDetails",
            "route: synthetic-route-v1 https://example.invalid/v1",
            "model: synthetic/model",
            "provider: Synthetic",
            "request fields: asked, description.name",
            "request sha256: " + String(repeating: "a", count: 64),
            "response sha256: " + String(repeating: "b", count: 64),
            "latency: 1234 ms",
            "attempts: 2",
            "reported cost: $0.000870",
            "threshold: 0.85",
            "outcome: answered"
        ])
        XCTAssertFalse(lines.contains { $0.contains("Bearer") || $0.contains("sk-or-") })
    }

    func testTheLogKeepsTheLastRequestOfEachPartDetailsFirst() {
        let log = FoodSearchDiagnosticsLog()
        XCTAssertTrue(log.confirmEnrichmentLines.isEmpty)
        log.recordConfirmEnrichment(Self.diagnostics(.confirmEnrichmentNutrients, outcome: "not_available"))
        log.recordConfirmEnrichment(Self.diagnostics(.confirmEnrichmentDetails))
        log.recordConfirmEnrichment(Self.diagnostics(.confirmEnrichmentNutrients))
        XCTAssertEqual(log.confirmEnrichmentLines.filter { $0.hasPrefix("use: ") },
                       ["use: confirmEnrichmentDetails", "use: confirmEnrichmentNutrients"])
        XCTAssertEqual(log.confirmEnrichmentLines.filter { $0.hasPrefix("outcome: ") }, ["outcome: answered", "outcome: answered"])
        XCTAssertTrue(log.confirmEnrichmentLines.contains("threshold: none"), "B has no threshold")
    }
}
