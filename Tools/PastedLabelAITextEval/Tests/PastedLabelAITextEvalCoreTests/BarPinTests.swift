import CryptoKit
import Foundation
import XCTest

/// docs/pasted-label-ai-text-v1.md 5.3 (D5, D12 and D19): the held-out bar is committed in A1,
/// before any tuning run, and pinned here by SHA-256 so it cannot change silently before A4. A
/// change to `bar-v1.json` is a new bar version, recorded with the owner's decision.
final class BarPinTests: XCTestCase {
    static let pinnedSHA256 = "5df5642c0d4205383e64c8333000e26b811347d082e175f343db51974e119983"

    var barURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("bar-v1.json")
    }

    func testBarIsPinned() throws {
        let digest = SHA256.hash(data: try Data(contentsOf: barURL)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, Self.pinnedSHA256, "bar-v1.json changed after it was committed; make a new bar version instead")
    }

    func testBarHoldsTheSection53Gates() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: barURL)) as? [String: Any])
        XCTAssertEqual(object["schema"] as? String, "pasted-label-ai-text-bar-v1")
        let heldOut = try XCTUnwrap(object["held_out"] as? [String: Any])
        XCTAssertEqual(heldOut["set"] as? String, "uk_v2_fresh")
        XCTAssertEqual(heldOut["labels"] as? Int, 24)
        XCTAssertEqual(heldOut["runs"] as? Int, 1)
        let gates = try XCTUnwrap(object["gates"] as? [[String: Any]])
        let byID = Dictionary(uniqueKeysWithValues: gates.map { ($0["id"] as! String, $0) })
        XCTAssertEqual(byID.keys.sorted(), ["bar_1", "bar_2", "bar_3", "bar_4_cost", "bar_4_latency"])
        XCTAssertEqual(byID["bar_1"]?["threshold"] as? Int, 0)
        XCTAssertEqual(byID["bar_1"]?["metric"] as? String, "silent_error_tables")
        XCTAssertEqual(byID["bar_2"]?["threshold"] as? Double, 0.8)
        XCTAssertEqual(byID["bar_2"]?["denominator"] as? String, "tables_reaching_confirm")
        XCTAssertEqual(byID["bar_3"]?["threshold"] as? Int, 6)
        XCTAssertEqual(byID["bar_3"]?["denominator_count"] as? Int, 24)
        XCTAssertEqual(byID["bar_3"]?["denominator"] as? String, "all_held_out_labels")
        XCTAssertEqual(byID["bar_4_cost"]?["threshold"] as? Double, 0.01)
        XCTAssertEqual(byID["bar_4_cost"]?["statistic"] as? String, "median")
        XCTAssertEqual(byID["bar_4_cost"]?["rank"] as? Int, 13, "the upper median of 24 (D23)")
        XCTAssertTrue((object["accepted"] as? String)?.contains("D23") ?? false)
        XCTAssertTrue((object["source"] as? String)?.hasPrefix("docs/pasted-label-ai-text-v1.md revision 6") ?? false)
        XCTAssertEqual(byID["bar_4_latency"]?["threshold"] as? Int, 15)
        XCTAssertEqual(byID["bar_4_latency"]?["rank"] as? Int, 22)
        let intervals = try XCTUnwrap(object["intervals"] as? [String: Any])
        XCTAssertEqual(intervals["confidence"] as? Double, 0.95)
        let field = try XCTUnwrap(intervals["field_level_and_per_table"] as? [String: Any])
        XCTAssertEqual(field["resamples"] as? Int, 10000)
        XCTAssertEqual(field["resample"] as? String, "labels")
        XCTAssertEqual(field["seed"] as? String, "seed recorded in each run")
        let comparing = try XCTUnwrap(object["comparing_versions"] as? [String: Any])
        XCTAssertEqual(comparing["seed"] as? String, "seed recorded in each run")
        let label = try XCTUnwrap(intervals["label_level_proportions"] as? [String: Any])
        XCTAssertEqual(label["method"] as? String, "wilson")
        XCTAssertEqual(label["method_when_count_is_zero_or_total"] as? String, "clopper_pearson")
    }
}
