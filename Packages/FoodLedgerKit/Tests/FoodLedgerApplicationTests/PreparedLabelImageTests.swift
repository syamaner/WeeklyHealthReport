import FoodLedgerApplication
import Foundation
import XCTest

/// The preparer's output type (docs/label-photo-ai-prefill-v1.md E3 and 17.8 M6): built only
/// within this package (its initialiser is `package`, so the app and other packages cannot make
/// one), and only within the E3 bounds. The metadata, orientation and size behaviour of the real
/// preparer are tests 13, 14 and 23 in L2.
final class PreparedLabelImageTests: XCTestCase {
    let digest = String(repeating: "0f", count: 32)

    func testBoundsArePinned() {
        XCTAssertEqual(PreparedLabelImage.maximumLongEdge, 2_048)
        XCTAssertEqual(PreparedLabelImage.maximumPixels, 3_200_000)
        XCTAssertEqual(PreparedLabelImage.maximumBytes, 1_500_000)
    }

    func testAnImageWithinTheBoundsRecordsItsManifestImage() throws {
        let image = try PreparedLabelImage(bytes: Data(repeating: 1, count: 100), pixelWidth: 2_048, pixelHeight: 1_500, sha256: digest,
                                           jpegQuality: "0.8")
        let record = image.manifestImage
        XCTAssertEqual(record.sha256, digest)
        XCTAssertEqual(record.byteCount, 100)
        XCTAssertEqual(record.mediaType, "image/jpeg")
        XCTAssertEqual(record.preparationVersion, "label-photo-preparation-v1")
    }

    func testAnythingOutsideTheBoundsIsRefused() {
        let cases: [(Data, Int, Int, String, String)] = [
            (Data(), 100, 100, digest, "0.8"),
            (Data(repeating: 1, count: 1_500_001), 100, 100, digest, "0.8"),
            (Data([1]), 2_049, 100, digest, "0.8"),
            (Data([1]), 2_000, 1_700, digest, "0.8"),
            (Data([1]), 0, 100, digest, "0.8"),
            (Data([1]), 100, 100, digest.uppercased(), "0.8"),
            (Data([1]), 100, 100, "abc", "0.8"),
            (Data([1]), 100, 100, digest, "high"),
        ]
        for (bytes, width, height, sha, quality) in cases {
            XCTAssertThrowsError(try PreparedLabelImage(bytes: bytes, pixelWidth: width, pixelHeight: height, sha256: sha, jpegQuality: quality))
        }
    }
}
