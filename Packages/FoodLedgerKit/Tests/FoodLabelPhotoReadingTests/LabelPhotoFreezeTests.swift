import CryptoKit
import FoodLabelPhotoReading
import XCTest

/// Photo freeze (docs/label-photo-ai-prefill-v1.md 17.8, L3): the files that define a version the
/// app will record are pinned by SHA-256. A change to one is a new version, never an edit.
/// L1 adds the mapping v1, serving v1, attention v1 and the manifest codec here as they land.
final class LabelPhotoFreezeTests: XCTestCase {
    /// Paths relative to the FoodLedgerKit package root.
    static let frozenSources: [String: String] = [
        // label-photo-vision-locate-v1, carried unchanged from the L0 tool (17.9).
        "Sources/FoodLabelPhotoReading/LabelValueMatcher.swift": "48a77a341f9861c93188cd58e216200fd99e8a88aa00cdc35f36afd8614d4f2b",
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
        XCTAssertEqual(LabelValueMatcher.version, "label-photo-vision-locate-v1")
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
