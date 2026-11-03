import Foundation
import XCTest

/// Runs one step of the UK English fresh-set protocol (`docs/pasted-nutrition-label-uk-english-v1-p3.md`
/// section 2) on the private folder. Skipped unless both variables are set, so the gates never
/// touch real text:
///
///     WHR_UK_FRESH_SET_DIR=/absolute/private/folder WHR_UK_FRESH_SET_STEP=<step> \
///       swift test --package-path Packages/FoodLedgerKit --filter UKFreshSetStepTests
///
/// Steps: `seal-texts`, `validate`, `seal-1`, `seal-2`, `run`, `score`. Every output is written
/// inside the private folder; a folder inside any git checkout is refused. Only the UK schema is
/// accepted.
final class UKFreshSetStepTests: XCTestCase {
    func testUKFreshSetStep() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["WHR_UK_FRESH_SET_DIR"], let step = environment["WHR_UK_FRESH_SET_STEP"] else {
            throw XCTSkip("WHR_UK_FRESH_SET_DIR and WHR_UK_FRESH_SET_STEP are not set")
        }
        let root = try FreshSet.privateFolder(path)
        switch step {
        case "seal-texts": _ = try UKFreshSet.seal(.text, root); print("text seal recorded in seals.txt")
        case "validate": try UKFreshSet.validateTranscriptions(root); print("transcriptions valid")
        case "seal-1": _ = try UKFreshSet.seal(.seal1, root); print("seal 1 recorded in seals.txt")
        case "seal-2": _ = try UKFreshSet.seal(.seal2, root); print("seal 2 recorded in seals.txt")
        case "run":
            // The commit this checkout is at, with no local change, goes into the run log (12.2.7 item 1).
            let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
            guard try Self.git(["-C", checkout, "status", "--porcelain"]).isEmpty else {
                throw FreshSet.Failure("refused: the checkout has local changes; run from a clean checkout of the freeze reference")
            }
            let commit = try Self.git(["-C", checkout, "rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
            print("run wrote \(try UKFreshSet.runAll(root, commit: commit)) outputs")
        case "score":
            let summary = try UKFreshSet.scoreAll(root)
            print("scored \(summary.overall.labels) labels; written to results/summary.json; passes: \(summary.overall.passes)")
        default: XCTFail("unknown step \(step)")
        }
    }

    private static func git(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FreshSet.Failure("git \(arguments.joined(separator: " ")) failed") }
        return String(decoding: data, as: UTF8.self)
    }
}
