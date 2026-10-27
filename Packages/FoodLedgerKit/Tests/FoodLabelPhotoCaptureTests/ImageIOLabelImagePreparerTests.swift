import CryptoKit
@testable import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
import ImageIO
import XCTest

/// Contract tests 13, 14 and 23 (docs/label-photo-ai-prefill-v1.md 12.5 and 17.8): the prepared
/// bytes carry no metadata, are upright, untagged sRGB, inside the E3 bounds, hash to their
/// recorded SHA-256, and a crop under 160 px is refused. The fixtures are synthetic and the
/// positive controls prove each fixture really holds what must be removed.
final class ImageIOLabelImagePreparerTests: XCTestCase {
    typealias Images = LabelPhotoFixtureImages
    let preparer = ImageIOLabelImagePreparer()

    // MARK: Test 13 and 23: metadata stripping, with positive controls

    func testJPEGWithEveryMetadataBlockComesOutWithNone() throws {
        let fixture = Images.jpegWithEverything(Images.asymmetric(width: 800, height: 600))
        // Positive controls: the fixture holds what must be removed.
        let source = try XCTUnwrap(CGImageSourceCreateWithData(fixture as CFData, nil))
        let before = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary,
                    kCGImagePropertyIPTCDictionary, kCGImagePropertyMakerAppleDictionary] {
            XCTAssertNotNil(before[key], "fixture lacks \(key)")
        }
        XCTAssertEqual(before[kCGImagePropertyOrientation] as? Int, 6)
        XCTAssertNotNil(CGImageSourceCopyMetadataAtIndex(source, 0, nil), "fixture lacks XMP")
        XCTAssertTrue(Self.hasEmbeddedThumbnail(fixture), "fixture lacks an embedded thumbnail")
        for signature in ["Exif\u{0}\u{0}", "http://ns.adobe.com/xap", "Photoshop 3.0"] {
            XCTAssertTrue(Self.contains(fixture, signature), "fixture lacks \(signature)")
        }
        let prepared = try preparer.prepare(fixture, crop: .whole)
        try assertClean(prepared.bytes)
    }

    func testHEICWithDepthAndGainMapComesOutAsOneJPEGWithNoAuxiliaryData() throws {
        guard let fixture = Images.heicWithDepthAndGainMap(Images.asymmetric(width: 800, height: 600)) else {
            throw XCTSkip("No HEIC encoder on this system")
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(fixture as CFData, nil))
        XCTAssertNotNil(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDepth), "fixture lacks depth")
        XCTAssertNotNil(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap), "fixture lacks a gain map")
        let prepared = try preparer.prepare(fixture, crop: .whole)
        try assertClean(prepared.bytes)
    }

    func testPNGWithExifAndTextChunksComesOutWithNone() throws {
        let fixture = Images.pngWithExifAndText(Images.asymmetric(width: 800, height: 600))
        XCTAssertTrue(Self.contains(fixture, "eXIf") && Self.contains(fixture, "tEXt"), "fixture lacks its chunks")
        let prepared = try preparer.prepare(fixture, crop: .whole)
        try assertClean(prepared.bytes)
        XCTAssertFalse(Self.contains(prepared.bytes, "GPS 25.03N"))
    }

    /// No metadata dictionary, no XMP, orientation 1 or absent, one image and no auxiliary data, no
    /// metadata byte signatures, and no application segment but APP0.
    func assertClean(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil), file: file, line: line)
        XCTAssertEqual(CGImageSourceGetCount(source), 1, file: file, line: line)
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg", file: file, line: line)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], file: file, line: line)
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary,
                    kCGImagePropertyIPTCDictionary, kCGImagePropertyMakerAppleDictionary, kCGImagePropertyExifAuxDictionary,
                    kCGImagePropertyCIFFDictionary, kCGImagePropertyMakerCanonDictionary, kCGImagePropertyMakerNikonDictionary,
                    kCGImagePropertyMakerFujiDictionary, kCGImagePropertyMakerOlympusDictionary, kCGImagePropertyMakerPentaxDictionary,
                    kCGImagePropertyMakerMinoltaDictionary] {
            XCTAssertNil(properties[key], "\(key) left", file: file, line: line)
        }
        XCTAssertTrue([nil, 1].contains(properties[kCGImagePropertyOrientation] as? Int), file: file, line: line)
        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        XCTAssertTrue(metadata.map { (CGImageMetadataCopyTags($0) as? [Any] ?? []).isEmpty } ?? true, "XMP left", file: file, line: line)
        XCTAssertNil(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDepth), file: file, line: line)
        XCTAssertNil(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap), file: file, line: line)
        XCTAssertFalse(Self.hasEmbeddedThumbnail(data), "embedded thumbnail left", file: file, line: line)
        // Untagged sRGB: no ICC profile segment (ImageIO still reports sRGB as the assumed profile name).
        for signature in ["Exif\u{0}\u{0}", "http://ns.adobe.com/xap", "Photoshop 3.0", "ICC_PROFILE", "MM\u{0}*", "II*\u{0}"] {
            XCTAssertFalse(Self.contains(data, signature), "\(signature) left", file: file, line: line)
        }
        let markers = try XCTUnwrap(JPEGSegments.markers(data), file: file, line: line)
        XCTAssertFalse(markers.contains { (0xE1...0xEF).contains($0) || $0 == 0xFE }, "\(markers)", file: file, line: line)
    }

    static func contains(_ data: Data, _ text: String) -> Bool { data.range(of: Data(text.utf8)) != nil }

    /// A second JPEG start (FF D8) inside an application segment: an embedded thumbnail.
    static func hasEmbeddedThumbnail(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var index = 2
        while index + 4 <= bytes.count, bytes[index] == 0xFF, bytes[index + 1] != 0xDA {
            let end = index + 2 + (Int(bytes[index + 2]) << 8 | Int(bytes[index + 3]))
            guard end <= bytes.count else { return false }
            if (0xE0...0xEF).contains(bytes[index + 1]), Array(bytes[(index + 4)..<end]).firstIndex(ofSequence: [0xFF, 0xD8]) != nil { return true }
            index = end
        }
        // Anything after EOI (an appended image) also counts.
        if let eoi = bytes.lastIndex(of: 0xD9), eoi > 0, bytes[eoi - 1] == 0xFF, eoi + 1 < bytes.count { return true }
        return false
    }

    // MARK: Test 13: upright pixels from a known asymmetric fixture

    func testOrientationIsAppliedToThePixels() throws {
        // Stored 800 x 600 with red in the stored top-left quarter; orientation 6 shows it turned a
        // quarter clockwise, so upright it is 600 x 800 with red in the top-right quarter.
        let prepared = try preparer.prepare(Images.jpegWithEverything(Images.asymmetric(width: 800, height: 600)), crop: .whole)
        XCTAssertEqual(prepared.pixelWidth, 600)
        XCTAssertEqual(prepared.pixelHeight, 800)
        XCTAssertTrue(Self.isRed(Images.pixel(prepared.bytes, x: 450, y: 200)), "top right is red")
        XCTAssertTrue(Self.isWhite(Images.pixel(prepared.bytes, x: 150, y: 200)), "top left is white")
        XCTAssertTrue(Self.isWhite(Images.pixel(prepared.bytes, x: 450, y: 600)), "bottom right is white")
    }

    func testCropAndQuarterTurnsApplyToTheUprightPhoto() throws {
        let upright = Images.jpegWithEverything(Images.asymmetric(width: 800, height: 600), orientation: 1)
        // The left half of the upright photo: red on top.
        let left = try XCTUnwrap(LabelCropRect(x: 0, y: 0, width: 0.5, height: 1))
        let cropped = try preparer.prepare(upright, crop: left)
        XCTAssertEqual(cropped.pixelWidth, 400)
        XCTAssertEqual(cropped.pixelHeight, 600)
        XCTAssertTrue(Self.isRed(Images.pixel(cropped.bytes, x: 200, y: 100)))
        XCTAssertTrue(Self.isWhite(Images.pixel(cropped.bytes, x: 200, y: 500)))
        // The same crop turned a quarter clockwise: 600 x 400, red on the right.
        let turned = try preparer.prepare(upright, crop: try XCTUnwrap(LabelCropRect(x: 0, y: 0, width: 0.5, height: 1, quarterTurns: 1)))
        XCTAssertEqual(turned.pixelWidth, 600)
        XCTAssertEqual(turned.pixelHeight, 400)
        XCTAssertTrue(Self.isRed(Images.pixel(turned.bytes, x: 500, y: 200)))
        XCTAssertTrue(Self.isWhite(Images.pixel(turned.bytes, x: 100, y: 200)))
    }

    static func isRed(_ rgb: (Int, Int, Int)) -> Bool { rgb.0 > 200 && rgb.1 < 60 && rgb.2 < 60 }
    static func isWhite(_ rgb: (Int, Int, Int)) -> Bool { rgb.0 > 200 && rgb.1 > 200 && rgb.2 > 200 }

    // MARK: Test 14 and E3: size bounds, the minimum crop and the recorded hash

    func testLargePhotosAreScaledInsideTheBounds() throws {
        for (width, height) in [(5_000, 4_000), (4_000, 800), (2_048, 2_048)] {
            let fixture = Images.jpegWithEverything(Images.asymmetric(width: width, height: height), orientation: 1)
            let prepared = try preparer.prepare(fixture, crop: .whole)
            XCTAssertLessThanOrEqual(max(prepared.pixelWidth, prepared.pixelHeight), 2_048, "\(width)x\(height)")
            XCTAssertLessThanOrEqual(prepared.pixelWidth * prepared.pixelHeight, 3_200_000, "\(width)x\(height)")
            XCTAssertLessThanOrEqual(prepared.bytes.count, 1_500_000)
        }
    }

    func testNoisyPhotosStepDownTheQualityLadderOrAreRefused() throws {
        let fixture = Images.jpegWithEverything(Images.noise(width: 2_048, height: 1_536), orientation: 1)
        do {
            let prepared = try preparer.prepare(fixture, crop: .whole)
            XCTAssertLessThanOrEqual(prepared.bytes.count, 1_500_000)
            XCTAssertTrue(["0.85", "0.75", "0.65"].contains(prepared.jpegQuality))
        } catch LabelImagePreparationError.outOfBounds {
            // Refused rather than sent over the byte limit.
        }
        XCTAssertEqual(ImageIOLabelImagePreparer.qualities, [0.85, 0.75, 0.65])
    }

    func testACropUnder160PixelsIsRefusedAnd160IsAccepted() throws {
        let fixture = Images.jpegWithEverything(Images.asymmetric(width: 1_000, height: 1_000), orientation: 1)
        XCTAssertThrowsError(try preparer.prepare(fixture, crop: try XCTUnwrap(LabelCropRect(x: 0, y: 0, width: 0.159, height: 0.5)))) {
            XCTAssertEqual($0 as? LabelImagePreparationError, .cropTooSmall)
        }
        XCTAssertNoThrow(try preparer.prepare(fixture, crop: try XCTUnwrap(LabelCropRect(x: 0, y: 0, width: 0.16, height: 0.5))))
    }

    func testSmallWholePhotosLikeE13sRefusalsArePrepared() throws {
        // E13 (17.21): whole photos of 175 x 174, 215 x 350 and 230 x 220 px were refused at 240 px.
        for (width, height) in [(175, 174), (215, 350), (230, 220), (160, 400)] {
            let prepared = try preparer.prepare(Images.jpegWithEverything(Images.asymmetric(width: width, height: height)), crop: .whole)
            XCTAssertEqual([prepared.pixelWidth, prepared.pixelHeight].sorted(), [width, height].sorted(), "never scaled up (the fixture is turned upright)")
        }
        XCTAssertThrowsError(try preparer.prepare(Images.jpegWithEverything(Images.asymmetric(width: 159, height: 400)), crop: .whole)) {
            XCTAssertEqual($0 as? LabelImagePreparationError, .cropTooSmall)
        }
    }

    func testTheRecordedHashIsThatOfTheBytesAndUnreadableInputIsRefused() throws {
        let prepared = try preparer.prepare(Images.jpegWithEverything(Images.asymmetric(width: 640, height: 480)), crop: .whole)
        XCTAssertEqual(prepared.sha256, SHA256.hash(data: prepared.bytes).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(prepared.manifestImage.byteCount, prepared.bytes.count)
        XCTAssertThrowsError(try preparer.prepare(Data("not an image".utf8), crop: .whole)) {
            XCTAssertEqual($0 as? LabelImagePreparationError, .unreadable)
        }
    }

    // MARK: The quality ladder (injectable encoder)

    func testTheLadderStepsDownAndRefusesPastTheLastQuality() throws {
        func sizes(_ map: [Double: Int]) -> (Double) throws -> Data { { Data(count: map[$0]!) } }
        let at075 = try ImageIOLabelImagePreparer.ladder(sizes([0.85: 2_000_000, 0.75: 1_400_000, 0.65: 900_000]))
        XCTAssertEqual(at075.1, 0.75)
        let at065 = try ImageIOLabelImagePreparer.ladder(sizes([0.85: 2_000_000, 0.75: 1_600_000, 0.65: 1_500_000]))
        XCTAssertEqual(at065.1, 0.65)
        XCTAssertThrowsError(try ImageIOLabelImagePreparer.ladder(sizes([0.85: 3_000_000, 0.75: 2_000_000, 0.65: 1_500_001]))) {
            XCTAssertEqual($0 as? LabelImagePreparationError, .outOfBounds)
        }
        XCTAssertEqual(ImageIOLabelImagePreparer.qualityText(0.75), "0.75")
    }

    // MARK: The plan: decode size, short edge after scaling, aspect ratio (#324 decisions)

    func testTheDecodeSizeIsWhatTheCropNeedsAtTheOutputBounds() throws {
        let whole = try ImageIOLabelImagePreparer.plan(uprightWidth: 8_000, uprightHeight: 6_000, crop: .whole)
        XCTAssertLessThanOrEqual(whole.decodeMaxPixelSize, 2_050, "a full 8,000 px photo is decoded near the output size")
        XCTAssertLessThanOrEqual(whole.outputWidth * whole.outputHeight, 3_200_000)
        let corner = try ImageIOLabelImagePreparer.plan(uprightWidth: 8_000, uprightHeight: 6_000,
                                                         crop: try XCTUnwrap(LabelCropRect(x: 0, y: 0, width: 0.1, height: 0.1)))
        XCTAssertEqual(corner.decodeMaxPixelSize, 8_000, "a small crop needs the full resolution")
        XCTAssertEqual(corner.outputWidth, 800)
    }

    func testANarrowCropIsRefusedAndTheShortEdgeHoldsAfterScaling() throws {
        XCTAssertThrowsError(try ImageIOLabelImagePreparer.plan(uprightWidth: 4_500, uprightHeight: 500, crop: .whole)) {
            XCTAssertEqual($0 as? LabelImagePreparationError, .cropTooNarrow)
        }
        XCTAssertNoThrow(try ImageIOLabelImagePreparer.plan(uprightWidth: 4_000, uprightHeight: 500, crop: .whole))
        let eightToOne = try ImageIOLabelImagePreparer.plan(uprightWidth: 4_000, uprightHeight: 500, crop: .whole)
        XCTAssertGreaterThanOrEqual(min(eightToOne.outputWidth, eightToOne.outputHeight), 160)
        XCTAssertEqual(ImageIOLabelImagePreparer.maximumAspectRatio, 8)
    }

    func testALargeSourceIsPreparedThroughTheSubsampledDecode() throws {
        let fixture = Images.jpegWithEverything(Images.asymmetric(width: 6_000, height: 4_500), orientation: 1)
        let prepared = try preparer.prepare(fixture, crop: .whole)
        XCTAssertLessThanOrEqual(max(prepared.pixelWidth, prepared.pixelHeight), 2_048)
        XCTAssertTrue(Self.isRed(Images.pixel(prepared.bytes, x: prepared.pixelWidth / 4, y: prepared.pixelHeight / 4)))
        XCTAssertTrue(Self.isWhite(Images.pixel(prepared.bytes, x: prepared.pixelWidth * 3 / 4, y: prepared.pixelHeight * 3 / 4)))
        try assertClean(prepared.bytes)
        // A large source stored sideways (orientation 6): the decode keeps the long edge, and the
        // upright result is portrait with red in the top-right quarter.
        let sideways = Images.jpegWithEverything(Images.asymmetric(width: 6_000, height: 4_500), orientation: 6)
        let upright = try preparer.prepare(sideways, crop: .whole)
        XCTAssertEqual(max(upright.pixelWidth, upright.pixelHeight), 2_048)
        XCTAssertLessThan(upright.pixelWidth, upright.pixelHeight)
        XCTAssertTrue(Self.isRed(Images.pixel(upright.bytes, x: upright.pixelWidth * 3 / 4, y: upright.pixelHeight / 4)))
        XCTAssertTrue(Self.isWhite(Images.pixel(upright.bytes, x: upright.pixelWidth / 4, y: upright.pixelHeight / 4)))
        try assertClean(upright.bytes)
    }

    func testQuarterTurnsTwoAndThree() throws {
        let upright = Images.jpegWithEverything(Images.asymmetric(width: 800, height: 600), orientation: 1)
        // Red is the top-left quarter. Two turns put it bottom right; three put it bottom left.
        let half = try preparer.prepare(upright, crop: try XCTUnwrap(LabelCropRect(x: 0, y: 0, width: 1, height: 1, quarterTurns: 2)))
        XCTAssertEqual(half.pixelWidth, 800)
        XCTAssertTrue(Self.isRed(Images.pixel(half.bytes, x: 600, y: 450)))
        XCTAssertTrue(Self.isWhite(Images.pixel(half.bytes, x: 200, y: 150)))
        let three = try preparer.prepare(upright, crop: try XCTUnwrap(LabelCropRect(x: 0, y: 0, width: 1, height: 1, quarterTurns: 3)))
        XCTAssertEqual(three.pixelWidth, 600)
        XCTAssertEqual(three.pixelHeight, 800)
        XCTAssertTrue(Self.isRed(Images.pixel(three.bytes, x: 150, y: 600)))
        XCTAssertTrue(Self.isWhite(Images.pixel(three.bytes, x: 450, y: 200)))
    }
}
