import Foundation
import XCTest

/// Runs one step of the reader v3 fresh-set protocol (section 12.2) on the private folder. Skipped
/// unless both variables are set, so the gates never touch real text:
///
///     WHR_FRESH_SET_DIR=/absolute/private/folder WHR_FRESH_SET_STEP=<step> \
///       swift test --package-path Packages/FoodLedgerKit --filter FreshSetStepTests
///
/// Steps: `seal-texts`, `validate`, `seal-1`, `seal-2`, `run`, `score`. Every output is written
/// inside the private folder; a folder inside any git checkout is refused.
final class FreshSetStepTests: XCTestCase {
    func testFreshSetStep() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["WHR_FRESH_SET_DIR"], let step = environment["WHR_FRESH_SET_STEP"] else {
            throw XCTSkip("WHR_FRESH_SET_DIR and WHR_FRESH_SET_STEP are not set")
        }
        let root = try FreshSet.privateFolder(path)
        switch step {
        case "seal-texts": _ = try FreshSet.seal(.text, root); print("text seal recorded in seals.txt")
        case "validate": try FreshSet.validateTranscriptions(root); print("transcriptions valid")
        case "seal-1": _ = try FreshSet.seal(.seal1, root); print("seal 1 recorded in seals.txt")
        case "seal-2": _ = try FreshSet.seal(.seal2, root); print("seal 2 recorded in seals.txt")
        case "run": print("run wrote \(try FreshSet.runAll(root)) outputs")
        case "score":
            let summary = try FreshSet.scoreAll(root)
            print("scored \(summary.labels) labels; written to results/summary.json; passes: \(summary.passes)")
        default: XCTFail("unknown step \(step)")
        }
    }
}
