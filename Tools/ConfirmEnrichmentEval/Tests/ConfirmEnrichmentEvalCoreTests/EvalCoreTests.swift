import ConfirmEnrichmentEvalCore
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import XCTest

/// The evaluation's pure core (docs/confirm-enrichment-openrouter-v1-phase.md sections 8 and 9, G11).
/// Synthetic data only.
final class EvalCoreTests: XCTestCase {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ce1-eval-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    // MARK: Preflight

    func testTheEmbeddedParagraphIsTheCheckoutsWordForWord() throws {
        let policy = try String(contentsOf: Self.repository.appendingPathComponent("docs/privacy-and-egress.md"), encoding: .utf8)
        XCTAssertTrue(policy.split(separator: "\n").contains { $0 == Substring(EvalPreflight.paragraph) })
        XCTAssertNoThrow(try EvalPreflight.check(checkout: policy, originMain: policy))
    }

    func testPreflightRefusesWhenTheParagraphIsMissingLocallyOrOnOriginMain() {
        let with = "# Policy\n\n" + EvalPreflight.paragraph + "\n"
        let without = "# Policy\n\nNo tooling paragraph.\n"
        let altered = "# Policy\n\n" + EvalPreflight.paragraph.replacingOccurrences(of: "$5", with: "$50") + "\n"
        XCTAssertThrowsError(try EvalPreflight.check(checkout: without, originMain: with)) {
            XCTAssertEqual($0 as? EvalPreflight.Refusal, .missingInCheckout)
        }
        XCTAssertThrowsError(try EvalPreflight.check(checkout: with, originMain: without)) {
            XCTAssertEqual($0 as? EvalPreflight.Refusal, .missingOnOriginMain)
        }
        XCTAssertThrowsError(try EvalPreflight.check(checkout: altered, originMain: with), "word for word")
        for refusal in [EvalPreflight.Refusal.missingInCheckout, .missingOnOriginMain] {
            XCTAssertFalse(refusal.description.contains("openrouter.ai"))
        }
    }

    // MARK: Ledger (CE-T15)

    func testTheLedgerRefusesAWorstCaseAboveFiveCentsAndThePastTheProgrammeStop() throws {
        let ledger = EvalSpendLedger(url: try temporaryFolder().appendingPathComponent("ledger.json"))
        XCTAssertThrowsError(try ledger.reserve(part: "nutrients", caseHash: "h", worstCaseMicroUSD: 50_001)) {
            XCTAssertEqual($0 as? EvalSpendLedger.Refusal, .perCallStop)
        }
        var reserved = 0
        while true {
            do { _ = try ledger.reserve(part: "nutrients", caseHash: "h", worstCaseMicroUSD: 50_000); reserved += 1 } catch {
                XCTAssertEqual(error as? EvalSpendLedger.Refusal, .programmeStop)
                break
            }
        }
        XCTAssertEqual(reserved, 100, "$5 at $0.05 a call")
        XCTAssertEqual(try ledger.chargedMicroUSD(), 5_000_000)
    }

    func testSettlementAndRelease() throws {
        let ledger = EvalSpendLedger(url: try temporaryFolder().appendingPathComponent("ledger.json"))
        let a = try ledger.reserve(part: "details", caseHash: "h", worstCaseMicroUSD: 3_000)
        try ledger.settle(a, reportedMicroUSD: 400)
        let b = try ledger.reserve(part: "details", caseHash: "h", worstCaseMicroUSD: 3_000)
        try ledger.settle(b, reportedMicroUSD: nil)
        let c = try ledger.reserve(part: "details", caseHash: "h", worstCaseMicroUSD: 3_000)
        try ledger.release(c)
        XCTAssertEqual(try ledger.chargedMicroUSD(), 400 + 3_000, "an unreported call is charged W; a released one nothing")
        XCTAssertThrowsError(try ledger.settle(a, reportedMicroUSD: 1)) { XCTAssertEqual($0 as? EvalSpendLedger.Refusal, .noOpenReservation) }
        let d = try ledger.reserve(part: "details", caseHash: "h", worstCaseMicroUSD: 3_000)
        try ledger.settle(d, reportedMicroUSD: 60_000)
        XCTAssertThrowsError(try ledger.reserve(part: "details", caseHash: "h", worstCaseMicroUSD: 1)) {
            XCTAssertEqual($0 as? EvalSpendLedger.Refusal, .stopped, "a reported cost above $0.05 stops the run")
        }
    }

    func testAnUnreadableOrForeignLedgerFailsClosed() throws {
        let folder = try temporaryFolder()
        let corrupt = folder.appendingPathComponent("corrupt.json")
        try Data("{".utf8).write(to: corrupt)
        XCTAssertThrowsError(try EvalSpendLedger(url: corrupt).reserve(part: "details", caseHash: "h", worstCaseMicroUSD: 1)) {
            XCTAssertEqual($0 as? EvalSpendLedger.Refusal, .unreadable)
        }
        let foreign = folder.appendingPathComponent("foreign.json")
        try Data(#"{"schema":"pasted-label-ai-text-spend-ledger-v1","entries":[]}"#.utf8).write(to: foreign)
        XCTAssertThrowsError(try EvalSpendLedger(url: foreign).reserve(part: "details", caseHash: "h", worstCaseMicroUSD: 1)) {
            XCTAssertEqual($0 as? EvalSpendLedger.Refusal, .unknownSchema)
        }
    }

    // MARK: Cases, hashes and manifests

    static let offCase = EvalCase(kind: .openFoodFacts, record: "records/synthetic.json", shape: .barcode, retrievedAt: "2026-11-21T10:00:00Z")
    static let rowCase = EvalCase(kind: .bundledRow, table: .cofid, search: "synthetic search", recordID: "cofid:1",
                                  retrievedAt: "2026-11-21T10:00:00Z", hidden: [.fiber])

    func testHashesAndManifestsAreStableAndNameNothingElse() throws {
        let list = EvalCaseList(cases: [Self.offCase, Self.rowCase])
        XCTAssertEqual(try EvalHashes.hash(Self.offCase), try EvalHashes.hash(Self.offCase))
        XCTAssertNotEqual(try EvalHashes.hash(Self.offCase), try EvalHashes.hash(Self.rowCase))
        let manifest = try EvalHashes.manifest(list)
        XCTAssertEqual(manifest.count, 2)
        XCTAssertEqual(manifest.sha256.count, 64)
        let line = EvalConsole.manifestLine(manifest)
        XCTAssertFalse(line.contains("synthetic"))
        let data = try FoundationCanonicalJSONEncoder().encode(list)
        XCTAssertEqual(try EvalCaseList.decode(data), list)
    }

    func testACaseIncompleteForItsKindIsRefused() throws {
        let broken = EvalCase(kind: .bundledRow, table: .cofid, search: "x", recordID: nil, retrievedAt: "2026-11-21T10:00:00Z")
        let data = try FoundationCanonicalJSONEncoder().encode(EvalCaseList(cases: [broken]))
        XCTAssertThrowsError(try EvalCaseList.decode(data)) { XCTAssertEqual($0 as? EvalCaseList.Problem, .malformedCase(index: 0)) }
    }

    func testConsoleLinesHoldOnlyCodesNumbersAndShortHashes() throws {
        let hash = try EvalHashes.hash(Self.rowCase)
        let line = EvalConsole.caseLine(hash: hash, part: "nutrients", outcome: .answered, attempts: 2)
        XCTAssertEqual(line, "case \(hash.prefix(12)) part nutrients outcome answered attempts 2")
    }

    // MARK: Hiding

    func testHidingTurnsAKnownValueIntoAnEligibleUnknown() throws {
        let provenance = NutrientProvenance(sourceKind: .genericCompositionDataset, sourceID: try ExternalIdentifier("cofid"),
                                            sourceReleaseID: try ExternalIdentifier("cofid-release"), recordID: try ExternalIdentifier("1"))
        let fibre = try NutrientEntry(key: .fiber, value: .augmented(try ExactNutrientValue(
            amount: 3, unit: .grams, sourceValue: .exact(try SourceExactNutrientValue(amount: 3, unit: LedgerText("g"), basis: .per100Grams)),
            provenance: [provenance])))
        let set = try NutrientSet(entries: NutrientKey.allCases.map { key in
            key == .fiber ? fibre : try NutrientEntry(key: key, value: .unknown(.notDeclared))
        })
        XCTAssertEqual(EvalHiding.declared(set, key: .fiber), 3)
        let hidden = try EvalHiding.hide(set, keys: [.fiber])
        XCTAssertEqual(hidden.entries.first { $0.key == .fiber }?.value, .unknown(.notDeclared))
        XCTAssertEqual(try EvalHiding.hide(set, keys: []), set)
    }

    func testAPrivateFolderInsideTheRepositoryIsRefused() {
        XCTAssertTrue(EvalPaths.isInside("/tmp/repo/private", repository: "/tmp/repo"))
        XCTAssertTrue(EvalPaths.isInside("/tmp/repo", repository: "/tmp/repo"))
        XCTAssertTrue(EvalPaths.isInside("/tmp/other/../repo/x", repository: "/tmp/repo"))
        XCTAssertFalse(EvalPaths.isInside("/tmp/repository-private", repository: "/tmp/repo"))
        XCTAssertFalse(EvalPaths.isInside("/tmp/eval-private", repository: "/tmp/repo"))
    }

    /// Defect review of PR 3: a negative amount never lowers the total.
    func testANegativeWorstCaseIsRefusedAndANegativeCostStopsTheLedger() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ce1-neg-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let ledger = EvalSpendLedger(url: folder.appendingPathComponent("ledger.json"))
        XCTAssertThrowsError(try ledger.reserve(part: "details", caseHash: "a", worstCaseMicroUSD: -5))
        let id = try ledger.reserve(part: "details", caseHash: "a", worstCaseMicroUSD: 3_000)
        try ledger.settle(id, reportedMicroUSD: -1_000)
        XCTAssertEqual(try ledger.chargedMicroUSD(), 3_000, "charged at W, never the negative report")
        XCTAssertThrowsError(try ledger.reserve(part: "details", caseHash: "b", worstCaseMicroUSD: 1), "the ledger stopped")
    }
}
