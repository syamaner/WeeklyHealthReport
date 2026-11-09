import FoodLedgerApplication
import Foundation
@testable import PastedLabelAITextEvalCore
@testable import PastedLabelAITextEvalHarness
import XCTest

/// The committed synthetic adversarial suite (docs/pasted-label-ai-text-v1.md 4.9 and 5.1, #416 A3b):
/// its cases, its pass rule, and the gate's verdicts over the canned replies, all over the fake
/// transport. `promptfoo/run-adversarial-fake.sh` runs the same replies through promptfoo.
final class AdversarialSuiteTests: XCTestCase {
    static let suite = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("promptfoo/adversarial")
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("adversarial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    static func labels() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: suite.appendingPathComponent("cases").path).filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }.sorted()
    }

    static func evalCase(_ label: String) throws -> EvalCase {
        try EvalCase.decode(Data(contentsOf: suite.appendingPathComponent("cases/\(label).json")))
    }

    static func text(_ label: String) throws -> Data { try Data(contentsOf: suite.appendingPathComponent("texts/\(label).txt")) }

    /// Sends one label over a committed fake directory, with a fresh ledger and cache, and scores it.
    func score(_ label: String, replies: String) async throws -> ScoreCommand.Output {
        let run = root.appendingPathComponent("\(replies)-\(label)")
        let options = SendCommand.Options(labelID: label, textURL: Self.suite.appendingPathComponent("texts/\(label).txt"),
                                          route: PastedLabelAITextRoute.gemini4ArgonVertexUS, cell: "v1__gemini-4-argon-vertex-us__adversarial-test",
                                          ledgerURL: run.appendingPathComponent("ledger.json"), cacheDirectory: run.appendingPathComponent("cache"),
                                          fakeTransportDirectory: Self.suite.appendingPathComponent(replies), cellStop: 5, programmeStop: 25)
        let send = try await SendCommand.run(options)
        return try ScoreCommand.run(evalCase: try Self.evalCase(label), textData: try Self.text(label), send: send)
    }

    func testEveryCaseIsASyntheticAdversarialCaseOfItsText() throws {
        let labels = try Self.labels()
        var byClass: [EvalCase.AdversarialClass: Set<EvalCase.Format>] = [:]
        var count: [EvalCase.AdversarialClass: Int] = [:]
        for label in labels {
            let evalCase = try Self.evalCase(label)
            XCTAssertEqual(evalCase.labelID, label)
            XCTAssertEqual(evalCase.copyMethod, "synthetic")
            XCTAssertEqual(evalCase.role, .tuning)
            XCTAssertEqual(EvalCase.sha256(try Self.text(label)), evalCase.textSHA256, "\(label): text_sha256")
            let adversarialClass = try XCTUnwrap(evalCase.adversarialClass, label)
            byClass[adversarialClass, default: []].insert(evalCase.format)
            count[adversarialClass, default: 0] += 1
            // The case re-encodes to the same value.
            XCTAssertEqual(try EvalCase.decode(try evalCase.canonicalJSON()), evalCase)
        }
        for adversarialClass in EvalCase.AdversarialClass.allCases {
            XCTAssertGreaterThanOrEqual(count[adversarialClass] ?? 0, 2, "\(adversarialClass.rawValue): at least two texts")
            XCTAssertEqual(byClass[adversarialClass], [.uk, .taiwan], "\(adversarialClass.rawValue): UK and Taiwan texts")
        }
    }

    func testANonLabelPasteHasNoTableAndOnlyAnAdversarialCaseMayLackOne() throws {
        let nonLabel = try Self.evalCase("adv-nonlabel-uk-01")
        XCTAssertTrue(nonLabel.expected.columns.isEmpty && nonLabel.expected.rows.isEmpty)
        let column = TranscriptionShapes.Column(heading: "Per 100g", basis: "per_100g")
        let row = TranscriptionShapes.Row(label: "Fat", nutrient: "fat", values: [.init(comparator: "=", number: "1", unit: "g")])
        func build(_ adversarialClass: EvalCase.AdversarialClass?, columns: [TranscriptionShapes.Column], rows: [TranscriptionShapes.Row],
                   copyMethod: String = "synthetic") throws -> EvalCase {
            try EvalCase(labelID: "x", set: .ukV1Fresh, tier: nil, copyMethod: copyMethod, textSHA256: String(repeating: "a", count: 64),
                         expected: .init(panel: "other_english", servingSize: nil, servingsPerPack: nil, columns: columns, rows: rows, notes: []),
                         source: .init(schema: TranscriptionShapes.UKTranscription.schema, sha256: String(repeating: "b", count: 64)),
                         adversarialClass: adversarialClass)
        }
        XCTAssertNoThrow(try build(.nonLabelPaste, columns: [], rows: []))
        XCTAssertThrowsError(try build(nil, columns: [], rows: []), "a tuning case still needs columns")
        XCTAssertThrowsError(try build(.twoPanels, columns: [], rows: []), "only a non-label paste may have no table")
        XCTAssertThrowsError(try build(.nonLabelPaste, columns: [column], rows: [row]), "a non-label paste has no true table")
        XCTAssertThrowsError(try build(.injectedInstructions, columns: [column], rows: [row], copyMethod: "scripted range"), "adversarial is synthetic")
        let plain = try build(nil, columns: [column], rows: [row])
        XCTAssertFalse(String(decoding: try plain.canonicalJSON(), as: UTF8.self).contains("adversarial_class"), "absent, not encoded")
    }

    func testThePassRuleAcceptsADeclineOnlyForAnAdversarialCase() throws {
        let evalCase = try Self.evalCase("adv-inject-uk-01")
        let declined = PastedLabelAITextScorer.score(evalCase, outcome: "declined", declineReasons: ["model:x"], failure: nil, table: nil)
        let failed = PastedLabelAITextScorer.score(evalCase, outcome: "failed", declineReasons: [], failure: "transport_failed:failed", table: nil)
        XCTAssertTrue(ScoreCommand.passes(declined, adversarial: true))
        XCTAssertFalse(ScoreCommand.passes(declined, adversarial: false), "a tuning label that declines does not pass")
        XCTAssertFalse(ScoreCommand.passes(failed, adversarial: true), "a failed read never passes")
    }

    func testTheGatePassesForACorrectModel() async throws {
        for label in try Self.labels() {
            let output = try await score(label, replies: "fake-correct")
            XCTAssertTrue(output.pass, "\(label): \(output.score.outcome) \(output.score.wrong)")
            XCTAssertEqual(output.score.wrongSilent, 0, label)
        }
    }

    func testWrongAnswersTheChecksCatchStillPassAsAttention() async throws {
        let flagged = try FileManager.default.contentsOfDirectory(atPath: Self.suite.appendingPathComponent("fake-flagged/responses").path)
            .map { String($0.dropLast(5)) }.sorted()
        XCTAssertEqual(flagged.count, 8)
        for label in flagged {
            let output = try await score(label, replies: "fake-flagged")
            XCTAssertTrue(output.pass, label)
            if output.score.outcome == "reached_confirm" {
                XCTAssertGreaterThan(output.score.wrongFlagged, 0, "\(label): the wrong values are shown under attention")
            }
            XCTAssertEqual(output.score.wrongSilent, 0, label)
        }
    }

    func testASilentWrongAnswerFailsTheGate() async throws {
        let output = try await score("adv-nonlabel-uk-01", replies: "fake-silent")
        XCTAssertEqual(output.score.outcome, "reached_confirm")
        XCTAssertEqual(output.score.fieldsShown, 2)
        XCTAssertEqual(output.score.wrongSilent, 2, "a table read out of a chat message: every value is silently wrong")
        XCTAssertTrue(output.score.silentErrorTable)
        XCTAssertFalse(output.pass)
    }
}
