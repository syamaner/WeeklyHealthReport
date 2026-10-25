import CryptoKit
import FoodLabelPhotoReading
import XCTest

/// Photo freeze (docs/label-photo-ai-prefill-v1.md 17.8, L3): the files that define a version the
/// app will record are pinned by SHA-256. A change to one is a new version, never an edit.
/// L1b adds the wire schema and mapping v1, serving v1, attention v1 and the manifest codec.
final class LabelPhotoFreezeTests: XCTestCase {
    /// Paths relative to the FoodLedgerKit package root.
    static let frozenSources: [String: String] = [
        // label-photo-vision-locate-v3 (L1d, 17.15), carried unchanged from the L0 tool. v2 was
        // 25bfb4f2… (#321) and v1 ea1ab9c9… (#320), neither shipped; a change to this file is a new version.
        "Sources/FoodLabelPhotoReading/LabelValueMatcher.swift": "8633366a038ec4f71151f4723f524ef00ba33e920dd98b3589b6088345a9cf3a",
        // label-photo-wire-schema-v1 and label-photo-wire-mapping-v1 (L1b).
        "Sources/FoodLabelPhotoReading/LabelPhotoWire.swift": "4124cf16ee06a16e3cd1015545a914b86d18601256abbd7405de47a8ea3afaea",
        "Sources/FoodLabelPhotoReading/LabelPhotoWireMapping.swift": "a6eb95dfdbc50c7f37950aea2f7b3a0f345b6311302ef6f3754201fedb91f1f9",
        // label-photo-serving-v1, label-photo-attention-v1 and the label-photo-ai-v1 codec (L1b).
        "Sources/FoodLedgerApplication/LabelPhotoServingPolicy.swift": "005cc3c2d8329857f6fc303871e0474020ff435549cbc3fd342e474b591ba9ee",
        "Sources/FoodLedgerApplication/LabelPhotoAttention.swift": "4314c9c239947738d8c4554a22640850780c3f78b80e7e93087fd6915be765f1",
        "Sources/FoodLedgerApplication/LabelPhotoManifest.swift": "c72e3fe426feeaae380de70ee05e38a91124d0e0954dc9c6b264863e937971a9",
    ]

    var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testFrozenSourcesAreUnchanged() throws {
        for (path, expected) in Self.frozenSources.sorted(by: { $0.key < $1.key }) {
            let digest = Self.sha256(try Data(contentsOf: packageRoot.appendingPathComponent(path)))
            XCTAssertEqual(digest, expected, "\(path) changed after its version was pinned; make a new version instead")
        }
    }

    /// The matcher L0 measured is byte for byte the matcher the package ships.
    func testMatcherIsTheOneL0Measured() throws {
        let repository = packageRoot.deletingLastPathComponent().deletingLastPathComponent()
        let measured = repository.appendingPathComponent("Tools/LabelPhotoLocateL0/Sources/LabelValueMatching/LabelValueMatcher.swift")
        let shipped = packageRoot.appendingPathComponent("Sources/FoodLabelPhotoReading/LabelValueMatcher.swift")
        XCTAssertEqual(try Data(contentsOf: measured), try Data(contentsOf: shipped))
    }

    func testMatcherVersionIsPinned() {
        XCTAssertEqual(LabelValueMatcher.version, "label-photo-vision-locate-v3")
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
