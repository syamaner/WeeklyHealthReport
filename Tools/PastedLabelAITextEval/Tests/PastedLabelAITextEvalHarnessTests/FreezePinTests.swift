import CryptoKit
import FoodLabelPhotoCapture
import FoodLabelTextAIReading
import FoodLedgerApplication
import Foundation
@testable import PastedLabelAITextEvalCore
import XCTest

/// The A3 freeze (docs/pasted-label-ai-text-v1.md 5.2 item 6, 5.4, 11.5 item 15; D35, owner,
/// 8 November 2026): what A4 runs on the held-out set is pinned here by SHA-256 before any held-out
/// text is read. That is the scorer and converter sources (the whole `PastedLabelAITextEvalCore`
/// target, plus the harness's `score` step), the statistics script, the bar A4 reads
/// (`bar-v2.json`, D34), the `prompt-v2` instruction, the promptfoo version, the frozen route
/// candidate and the reader versions.
///
/// A deliberate change to any of these after the freeze is a new version with an owner decision,
/// never an edit to a pin without one. A4 ran once under this freeze from `main` at `6e2fd69`
/// (scorer v5), which is its record. After A4 the owner moved the scorer to v6 (D37, 9 November
/// 2026), so `Scorer.swift` and the `score` step's comment in `Score.swift` are re-pinned here under that
/// decision; every other pin is unchanged. Switching `PastedLabelAITextRoute.current` and the request builder's
/// default prompt version is A5's, with T8 to T12, so this test asserts both are still unchanged.
final class FreezePinTests: XCTestCase {
    /// Paths relative to the repository root.
    static let frozenFiles: [String: String] = [
        // pasted-label-ai-text-scorer-v6 (D37, after A4; A4 ran v5 at 6e2fd69) and the converters (the PastedLabelAITextEvalCore target, whole).
        "Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalCore/ConvertCommand.swift": "d659113d54de2d5d8745e7befdc38a1d99151e2198c356aeab2a6fe1532fdc8d",
        "Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalCore/EvalCase.swift": "f50ebbf65665a611a292937ad0792ded8dcab7c13dab2911367ca730dc53227a",
        "Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalCore/EvalCaseConverter.swift": "8b8e07d6c4306e27ab30fcb6590302e30e8bf73a04238ffc3a85d0925b8343be",
        "Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalCore/LegacyTranscription.swift": "b732e84db21693a2190592d19e14f797deedbf1e3ce825d1903b5bc9083c17e5",
        "Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalCore/Scorer.swift": "bbc05e3de1af0d5d317b0fb52361928abc6e1478f0697db89eb9dbdce17997a9",
        "Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalCore/StrictDecoding.swift": "f660f564d10c6bdf999440ec1fa252e4460a2c8d2adfc61589c9fc463d8f57bb",
        "Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalCore/TranscriptionRules.swift": "ff791b056ed09e76a99e1d8f23f56fa8d350f62b764ee861b005ebb89b0d2024",
        "Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalCore/TranscriptionShapes.swift": "ebb67e03c3822e9ada798a0e7311c372715196ded844c21db04653b6d28c9eb6",
        // The `score` step: the shipped steps in product order, then the scorer (5.2 item 2).
        "Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalHarness/Score.swift": "eb4f4a69300116853c252dc5bd7c046c786404a375aa3739f1bae1ff0d3359c2",
        // The statistics script (5.2 item 4), defaulting to bar-v2.
        "Tools/PastedLabelAITextEval/statistics/pasted_label_ai_text_stats.py": "cf24388b86af9fc34fb715fb735ffb6106798945bfbdb0c4e15aa435c9b59cc6",
        // The bar A4 reads (D34); BarV2PinTests pins it too.
        "Tools/PastedLabelAITextEval/bar-v2.json": "a4b94900211877d8b2723373d8412f9b80e119737b178a215660ea5fdbc92968",
        // The prompt-v2 instruction, as the request builder pins it.
        "Packages/FoodLedgerKit/Sources/FoodLabelPhotoCapture/Resources/pasted-label-ai-text-instruction-v2.txt": "3ea63efb3f1fc1fff22402941de021c999bdead05438fe45333dc1dcc31ab513",
        // promptfoo 0.125.0, exact, with its lockfile.
        "Tools/PastedLabelAITextEval/promptfoo/package.json": "ff3a0e4ffb4b6d7c789437c498b5334d580868017ef0df0f34219e9b98e7ef78",
        "Tools/PastedLabelAITextEval/promptfoo/package-lock.json": "682bcd4774e0ae684c69c22bda19f5135452390214c175562d9d7f3facc0dcba",
    ]

    static let frozenPromptSHA256 = "3ea63efb3f1fc1fff22402941de021c999bdead05438fe45333dc1dcc31ab513"

    var repositoryRoot: URL {
        // Tools/PastedLabelAITextEval/Tests/PastedLabelAITextEvalHarnessTests/FreezePinTests.swift
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 { url.deleteLastPathComponent() }
        return url
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func testFrozenFilesAreUnchanged() throws {
        for (path, expected) in Self.frozenFiles.sorted(by: { $0.key < $1.key }) {
            let digest = Self.sha256(try Data(contentsOf: repositoryRoot.appendingPathComponent(path)))
            XCTAssertEqual(digest, expected, "\(path) changed after the A3 freeze (D35); make a new version with an owner decision instead")
        }
    }

    /// No file can join the scorer and converter target without being pinned.
    func testEveryCoreSourceIsPinned() throws {
        let directory = repositoryRoot.appendingPathComponent("Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalCore")
        let present = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") }.sorted()
        let pinned = Self.frozenFiles.keys.filter { $0.hasPrefix("Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalCore/") }
            .map { ($0 as NSString).lastPathComponent }.sorted()
        XCTAssertEqual(present, pinned)
    }

    func testTheScorerIsV6() {
        XCTAssertTrue(PastedLabelAITextScorer.version.hasPrefix("pasted-label-ai-text-scorer-v6 "), "v5 until A4, v6 from D37")
    }

    func testTheFrozenPromptIsV2() {
        let prompt = OpenRouterPastedLabelAITextRequest.PromptVersion.v2
        XCTAssertEqual(prompt.rawValue, "prompt-v2")
        XCTAssertEqual(prompt.instructionVersion, "pasted-label-ai-text-instruction-v2")
        XCTAssertEqual(prompt.instructionSHA256, Self.frozenPromptSHA256)
    }

    func testThePromptfooVersionIsExact() throws {
        let root = repositoryRoot.appendingPathComponent("Tools/PastedLabelAITextEval/promptfoo")
        let package = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("package.json"))) as? [String: Any])
        XCTAssertEqual((package["dependencies"] as? [String: String])?["promptfoo"], "0.125.0")
        let lock = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("package-lock.json"))) as? [String: Any])
        let packages = try XCTUnwrap(lock["packages"] as? [String: Any])
        XCTAssertEqual((packages["node_modules/promptfoo"] as? [String: Any])?["version"] as? String, "0.125.0")
    }

    func testTheFrozenRouteCandidate() throws {
        let route = try XCTUnwrap(PastedLabelAITextRoute.candidate("gpt-6.1-sol-azure-4k"))
        XCTAssertEqual(route, PastedLabelAITextRoute.gpt61SolAzure4K)
        XCTAssertEqual(route.version, "pasted-label-ai-text-route-v1")
        XCTAssertEqual(route.model, "openai/gpt-6.1-sol")
        XCTAssertEqual(route.endpoint, "azure")
        XCTAssertEqual(route.providerName, "Azure")
        XCTAssertEqual(route.maxOutputTokens, 4_000)
        XCTAssertEqual(route.reasoning, .budget(500))
        XCTAssertTrue(PastedLabelAITextRoute.isAdmitted(route))
    }

    /// The named fallback (D35), tested only from scratch on a fresh held-out set if the frozen
    /// configuration fails the bar in A4.
    func testTheNamedFallbackCandidate() throws {
        let route = try XCTUnwrap(PastedLabelAITextRoute.candidate("gpt-6.1-terra-azure-4k-noreason"))
        XCTAssertEqual(route.model, "openai/gpt-6.1-terra")
        XCTAssertEqual(route.endpoint, "azure")
        XCTAssertEqual(route.maxOutputTokens, 4_000)
        XCTAssertEqual(route.reasoning, .off)
    }

    func testTheFrozenReaderVersions() {
        let versions = PastedLabelAITextReader.versions
        XCTAssertEqual(versions.wireSchema, "pasted-label-ai-text-wire-schema-v1")
        XCTAssertEqual(versions.mapping, "pasted-label-ai-text-mapping-v4")
        XCTAssertEqual(versions.locator, "pasted-label-text-locate-v4")
        XCTAssertEqual(versions.vocabulary, "pasted-label-ai-text-vocabulary-v3")
        XCTAssertEqual(versions.detector, "pasted-label-ai-text-panel-detector-v2")
        XCTAssertEqual(versions.attention, "pasted-label-ai-text-attention-v1")
        XCTAssertEqual(versions.format, "pasted-label-ai-text-format-v1")
        XCTAssertEqual(versions.gate, "label-capture-decline-gate-v2")
        XCTAssertEqual(versions.arithmetic, "label-arithmetic-checks-v2")
        XCTAssertEqual(versions.conversion, "pasted-label-conversions-v1")
    }

    /// A3 records and pins; the product switch belongs to A5 with T8 to T12.
    func testTheProductRouteIsNotSwitchedYet() {
        XCTAssertNil(PastedLabelAITextRoute.current)
        XCTAssertEqual(OpenRouterPastedLabelAITextRequest.defaultPromptVersion, .v1)
    }
}
