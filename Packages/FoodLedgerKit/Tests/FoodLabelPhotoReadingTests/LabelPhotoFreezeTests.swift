import CryptoKit
import FoodLabelPhotoReading
import XCTest

/// Photo freeze (docs/label-photo-ai-prefill-v1.md 17.8, L3): the files that define a version the
/// app will record are pinned by SHA-256. A change to one is a new version, never an edit.
/// L1 adds the mapping v1, serving v1, attention v1 and the manifest codec here as they land.
final class LabelPhotoFreezeTests: XCTestCase {
    /// Paths relative to the FoodLedgerKit package root.
    static let frozenSources: [String: String] = [
        // label-photo-vision-locate-v2 (L1c, 17.11), carried unchanged from the L0 tool. v1 was
        // ea1ab9c9… (merged in #320, never shipped); a change to this file is a new version.
        "Sources/FoodLabelPhotoReading/LabelValueMatcher.swift": "33e85f9c22f5c429d1cfbbbdc9f9c569282a55af4e1cc4421490770891785bf6",
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
        XCTAssertEqual(LabelValueMatcher.version, "label-photo-vision-locate-v2")
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
