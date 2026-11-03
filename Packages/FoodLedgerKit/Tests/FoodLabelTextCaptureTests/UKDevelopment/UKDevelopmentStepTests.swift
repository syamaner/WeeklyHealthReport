import Foundation
import XCTest

/// Runs one step of the UK development set (`docs/pasted-nutrition-label-uk-english-v1.md` P1) on
/// the private folder. Skipped unless both variables are set, so the gates never touch real text:
///
///     WHR_UK_DEV_DIR=/absolute/private/folder WHR_UK_DEV_STEP=<run|score> \
///       swift test --package-path Packages/FoodLedgerKit --filter UKDevelopmentStepTests
///
/// Every output is written inside the private folder; a folder inside any git checkout is refused.
final class UKDevelopmentStepTests: XCTestCase {
    func testUKDevelopmentStep() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["WHR_UK_DEV_DIR"], let step = environment["WHR_UK_DEV_STEP"] else {
            throw XCTSkip("WHR_UK_DEV_DIR and WHR_UK_DEV_STEP are not set")
        }
        let root = try FreshSet.privateFolder(path)
        switch step {
        case "run":
            let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
            print("run wrote \(try UKDevelopmentSet.runAll(root, commit: try Self.git(["-C", checkout, "rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines))) outputs")
        case "score":
            let summary = try UKDevelopmentSet.scoreAll(root)
            print("scored \(summary.labels) labels; written to results/summary.json; wrong values: \(summary.wrongValues)")
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
