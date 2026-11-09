import CryptoKit
import Foundation
import XCTest

/// Pins the bundled Ciqual 2025 corpus (#384 C1, `docs/ciqual-2025-admission-v1.md`) from the
/// raw JSON, independently of `CiqualGenericFoodSearch` (C2), whose own hash check at load must
/// agree with these values (`CiqualGenericFoodSearchTests`).
final class CiqualCorpusPinTests: XCTestCase {
    static let corpusSHA256 = "2a298bd5e9c43d2e32ed3164c2a53de0dc21f80c9812285faf137dde196f333f"
    static let sourceManifestSHA256 = "3134f8dc9feb3e17e4d297fdc42f7711eff41af3210facb5d24c35194fa0d847"
    static let admittedCodes = ["31000", "31001", "31002", "31004", "31005", "31009", "31010", "31012", "31018", "31020",
                                "31026", "31030", "31032", "31041", "31042", "31063", "31066", "31069", "31070", "31071",
                                "31072", "31073", "31074", "31080", "31084", "31085", "31091", "31098", "31120"]

    private func corpusData() throws -> Data {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: package.appendingPathComponent("Sources/FoodGenericSearch/Resources/ciqual-2025-generic-v1.json"))
    }

    private func corpus() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: corpusData()) as? [String: Any])
    }

    func testCorpusBytesAndSourceManifestArePinned() throws {
        let digest = SHA256.hash(data: try corpusData()).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, Self.corpusSHA256)
        let corpus = try corpus()
        XCTAssertEqual(corpus["schema"] as? String, "ciqual-generic-v1")
        XCTAssertEqual(corpus["projectionVersion"] as? String, "ciqual-projection-v1")
        XCTAssertEqual(corpus["groupScope"] as? String, "ciqual-group-scope-v1")
        XCTAssertEqual(corpus["sourceID"] as? String, "ciqual")
        XCTAssertEqual(corpus["releasedAt"] as? String, "2025-11-19T00:00:00Z")
        XCTAssertEqual(corpus["sourceManifestSHA256"] as? String, Self.sourceManifestSHA256)
        XCTAssertEqual(corpus["sourceReleaseID"] as? String, "ciqual:2025-11-19:sha256:" + Self.sourceManifestSHA256)
        XCTAssertEqual(corpus["compoSHA256"] as? String, "8c46a9032ece4eab4ffccc9dfcb0c490ec2f416aa664cc1ee013b241c6bdd4af")
        let manifest = try XCTUnwrap(corpus["sourceManifest"] as? [String: Any])
        let files = try XCTUnwrap(manifest["files"] as? [[String: Any]])
        XCTAssertEqual(files.compactMap { $0["id"] as? Int }, [666246, 666248, 666249, 666250, 666252])
        XCTAssertEqual(manifest["doi"] as? String, "10.57745/RDMHWY")
    }

    func testAdmittedRecordsAndThe31074Trace() throws {
        let corpus = try corpus()
        let records = try XCTUnwrap(corpus["records"] as? [[String: Any]])
        XCTAssertEqual(records.compactMap { $0["alimCode"] as? String }, Self.admittedCodes)
        XCTAssertTrue(records.allSatisfy { ($0["subgroupCode"] as? String) == "0702" && ($0["nutrients"] as? [String: Any])?.count == 39 })
        let bar = try XCTUnwrap(records.first { ($0["alimCode"] as? String) == "31074" })
        XCTAssertEqual(bar["recordID"] as? String, "ciqual:2025-11-19:sha256:\(Self.sourceManifestSHA256):alim:31074")
        let nutrients = try XCTUnwrap(bar["nutrients"] as? [String: [String: Any]])
        XCTAssertEqual(nutrients["iron"]?["value"] as? String, "11")
        XCTAssertEqual(nutrients["iron"]?["literal"] as? String, "11")
        XCTAssertEqual(nutrients["iron"]?["confidence"] as? String, "A")
        XCTAssertEqual(nutrients["magnesium"]?["value"] as? String, "200")
        XCTAssertEqual(nutrients["selenium"]?["state"] as? String, "bounded")
        XCTAssertEqual(nutrients["selenium"]?["upper"] as? String, "20")
        XCTAssertEqual(nutrients["vitamin_e"]?["value"] as? String, "0.67")
        XCTAssertEqual(nutrients["vitamin_b12"]?["value"] as? String, "0")
        for key in ["biotin_b7", "chromium", "molybdenum", "caffeine", "water", "vitamin_a"] {
            XCTAssertEqual(nutrients[key]?["state"] as? String, "unknown", key)
        }
    }
}
