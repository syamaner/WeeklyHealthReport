import FoodLedgerApplication
import Foundation
import XCTest

/// The preparer's output type (docs/label-photo-ai-prefill-v1.md E3 and 17.8 M6): built only
/// through the package's factory, which computes the SHA-256 of the bytes itself, and only within
/// the E3 bounds. The metadata, orientation and size behaviour of the real preparer are tests 13,
/// 14 and 23 in `FoodLabelPhotoCaptureTests`.
final class PreparedLabelImageTests: XCTestCase {
    let digester = SHA256Digester()

    func testBoundsArePinned() {
        XCTAssertEqual(PreparedLabelImage.maximumLongEdge, 2_048)
        XCTAssertEqual(PreparedLabelImage.maximumPixels, 3_200_000)
        XCTAssertEqual(PreparedLabelImage.maximumBytes, 1_500_000)
    }

    func testTheRecordedHashIsThatOfTheBytes() throws {
        let bytes = Data(repeating: 1, count: 100)
        let image = try PreparedLabelImageFactory.make(bytes: bytes, pixelWidth: 2_048, pixelHeight: 1_500, jpegQuality: "0.8",
                                                       digester: digester)
        XCTAssertEqual(image.sha256, try digester.sha256(bytes).value)
        let record = image.manifestImage
        XCTAssertEqual(record.sha256, image.sha256)
        XCTAssertEqual(record.byteCount, 100)
        XCTAssertEqual(record.mediaType, "image/jpeg")
        XCTAssertEqual(record.preparationVersion, "label-photo-preparation-v1")
    }

    func testAnythingOutsideTheBoundsIsRefused() {
        let cases: [(Data, Int, Int, String)] = [
            (Data(), 100, 100, "0.8"),
            (Data(repeating: 1, count: 1_500_001), 100, 100, "0.8"),
            (Data([1]), 2_049, 100, "0.8"),
            (Data([1]), 2_000, 1_700, "0.8"),
            (Data([1]), 0, 100, "0.8"),
            (Data([1]), 100, 100, "high"),
        ]
        for (bytes, width, height, quality) in cases {
            XCTAssertThrowsError(try PreparedLabelImageFactory.make(bytes: bytes, pixelWidth: width, pixelHeight: height, jpegQuality: quality,
                                                                    digester: digester))
        }
    }
}
