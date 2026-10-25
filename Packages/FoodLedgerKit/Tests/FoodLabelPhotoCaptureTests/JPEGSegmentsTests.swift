@testable import FoodLabelPhotoCapture
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// The allow-listed JPEG structure (docs/label-photo-ai-prefill-v1.md 17.8 M6 and the #324 review):
/// pure adversarial vectors built from a real baseline JPEG. Each must be refused (nil); the
/// sanitised output keeps only APP0, the tables, one SOF0, one SOS, the scan data and EOI.
final class JPEGSegmentsTests: XCTestCase {
    /// A small baseline JPEG straight from ImageIO, with whatever metadata segments it writes.
    static let baseline: [UInt8] = {
        let image = LabelPhotoFixtureImages.asymmetric(width: 64, height: 48)
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return [UInt8](JPEGSegments.sanitised(out as Data)!)
    }()

    /// Where the SOS segment starts in the sanitised baseline.
    static var sosIndex: Int {
        var index = 2
        while true {
            let length = Int(baseline[index + 2]) << 8 | Int(baseline[index + 3])
            if baseline[index + 1] == 0xDA { return index }
            index += 2 + length
        }
    }

    static func segment(_ marker: UInt8, _ payload: [UInt8]) -> [UInt8] {
        let length = payload.count + 2
        return [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
    }

    func refuse(_ bytes: [UInt8], _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(JPEGSegments.sanitised(Data(bytes)), name, file: file, line: line)
    }

    func testTheBaselineIsExactlyTheAllowedStructure() throws {
        let bytes = Self.baseline
        let markers = try XCTUnwrap(JPEGSegments.markers(Data(bytes)))
        XCTAssertTrue(Set(markers).isSubset(of: [0xE0, 0xDB, 0xC4, 0xDD, 0xC0, 0xDA]), "\(markers)")
        XCTAssertEqual(markers.filter { $0 == 0xC0 }.count, 1)
        XCTAssertEqual(Array(bytes.suffix(2)), [0xFF, 0xD9])
        // Sanitising is idempotent.
        XCTAssertEqual(JPEGSegments.sanitised(Data(bytes)), Data(bytes))
    }

    func testMetadataSegmentsBeforeTheScanAreDropped() {
        let sos = Self.sosIndex
        let exif = Self.segment(0xE1, Array("Exif".utf8) + [0, 0] + Array("MM".utf8) + [0, 0x2A, 0, 0, 0, 8])
        let icc = Self.segment(0xE2, Array("ICC_PROFILE".utf8) + [0, 1, 1, 0, 0])
        let comment = Self.segment(0xFE, Array("a comment".utf8))
        let withMetadata = Array(Self.baseline[..<sos]) + exif + icc + comment + Array(Self.baseline[sos...])
        XCTAssertEqual(JPEGSegments.sanitised(Data(withMetadata)), Data(Self.baseline))
    }

    func testAdversarialStructuresAreRefused() {
        let base = Self.baseline
        let sos = Self.sosIndex
        // Trailing data after EOI, and an appended second image with an MPF segment pointing at it.
        refuse(base + [0x00, 0x01], "trailing data")
        let mpf = Self.segment(0xE2, Array("MPF".utf8) + [0, 0x4D, 0x4D, 0, 0x2A])
        refuse(Array(base[..<sos]) + mpf + Array(base[sos...]) + base, "APP2 MPF with an appended image")
        // A standalone marker before the scan, which has no length and must never be read as one.
        refuse(Array(base[..<sos]) + [0xFF, 0xD0] + Array(base[sos...]), "standalone RST before the scan")
        refuse(Array(base[..<2]) + [0xFF, 0xD8] + Array(base[2...]), "a second SOI")
        refuse(Array(base[..<sos]) + Self.segment(0xF0, [1, 2]) + Array(base[sos...]), "reserved marker")
        // A progressive (or any other) frame instead of SOF0.
        refuse(base.enumerated().map { $0.element == 0xC0 && $0.offset > 0 && base[$0.offset - 1] == 0xFF ? 0xC2 : $0.element }, "progressive frame")
        // A second frame header.
        let frameStart = (2..<sos).first { base[$0] == 0xFF && base[$0 + 1] == 0xC0 }!
        let frameLength = Int(base[frameStart + 2]) << 8 | Int(base[frameStart + 3])
        let frame = Array(base[frameStart..<(frameStart + 2 + frameLength)])
        refuse(Array(base[..<sos]) + frame + Array(base[sos...]), "second SOF0")
        // A second scan, and a comment between scans, inside the entropy-coded data.
        let sosLength = Int(base[sos + 2]) << 8 | Int(base[sos + 3])
        let scanHeader = Array(base[sos..<(sos + 2 + sosLength)])
        let eoi = base.count - 2
        refuse(Array(base[..<eoi]) + scanHeader + [0x12, 0x34] + [0xFF, 0xD9], "second SOS")
        refuse(Array(base[..<eoi]) + Self.segment(0xFE, Array("x".utf8)) + [0xFF, 0xD9], "comment between scans")
        refuse(Array(base[..<eoi]) + Self.segment(0xE1, Array("Exif".utf8) + [0, 0]) + [0xFF, 0xD9], "APP1 after the scan")
        // JFXX, or a JFIF header carrying a thumbnail.
        let app0 = Array(base[2..<20])
        XCTAssertEqual(Array(app0[4..<9]), Array("JFIF".utf8) + [0], "the baseline starts with a JFIF APP0")
        var jfxx = app0; jfxx.replaceSubrange(4..<9, with: Array("JFXX".utf8) + [0])
        refuse(Array(base[..<2]) + jfxx + Array(base[20...]), "JFXX APP0")
        var thumbnail = app0; thumbnail[16] = 1; thumbnail[17] = 1
        refuse(Array(base[..<2]) + thumbnail + Array(base[20...]), "JFIF APP0 with a thumbnail")
        // A truncated file and no EOI.
        refuse(Array(base.dropLast(2)), "no EOI")
        refuse(Array(base.prefix(sos + 3)), "truncated in the scan header")
        refuse(Array("GIF89a".utf8), "not a JPEG")
    }

    /// The #324 re-review hardening: APP0 only directly after SOI, exact DRI, SOF0 and SOS lengths,
    /// and restart markers only under a declared interval and in sequence modulo 8.
    func testSegmentLengthsAndPositionsAreExact() {
        let base = Self.baseline
        let sos = Self.sosIndex
        let app0 = Array(base[2..<20])
        // A second APP0, and an APP0 after a dropped segment, are refused.
        refuse(Array(base[..<20]) + app0 + Array(base[20...]), "second APP0")
        let comment = Self.segment(0xFE, Array("c".utf8))
        refuse(Array(base[..<2]) + comment + Array(base[2...]), "APP0 not directly after SOI")
        // DRI must be exactly 4 bytes long, and only once.
        refuse(Array(base[..<sos]) + Self.segment(0xDD, [0, 4, 0]) + Array(base[sos...]), "DRI of length 5")
        let dri = Self.segment(0xDD, [0, 4])
        refuse(Array(base[..<sos]) + dri + dri + Array(base[sos...]), "two DRI")
        // SOF0 and SOS lengths must match their component counts.
        let frameStart = (2..<sos).first { base[$0] == 0xFF && base[$0 + 1] == 0xC0 }!
        var frame = base; frame[frameStart + 9] = frame[frameStart + 9] &+ 1     // Nf off by one
        refuse(frame, "SOF0 length does not match its components")
        var scan = base; scan[sos + 4] = scan[sos + 4] &+ 1                          // Ns off by one
        refuse(scan, "SOS length does not match its components")
    }

    func testRestartMarkersNeedADeclaredIntervalAndTheirSequence() throws {
        // The header of the baseline without the encoder's own DRI, and a synthetic scan: the
        // sanitiser is structural, so the entropy-coded bytes need not decode.
        let base = Self.baseline
        let sos = Self.sosIndex
        var header: [UInt8] = [0xFF, 0xD8]
        var index = 2
        while index < sos {
            let end = index + 2 + (Int(base[index + 2]) << 8 | Int(base[index + 3]))
            if base[index + 1] != 0xDD { header += base[index..<end] }
            index = end
        }
        let sosLength = Int(base[sos + 2]) << 8 | Int(base[sos + 3])
        let scanHeader = Array(base[sos..<(sos + 2 + sosLength)])
        func withRestarts(_ dri: [UInt8]?, _ restarts: [UInt8]) -> [UInt8] {
            header + (dri.map { Self.segment(0xDD, $0) } ?? []) + scanHeader + [0x12, 0x34]
                + restarts.flatMap { [0xFF, $0, 0x12] } + [0xFF, 0xD9]
        }
        XCTAssertNotNil(JPEGSegments.sanitised(Data(withRestarts(nil, []))), "no restarts and no DRI")
        let sequence: [UInt8] = (0..<10).map { 0xD0 + UInt8($0 % 8) }
        let accepted = withRestarts([0, 4], sequence)
        XCTAssertEqual(JPEGSegments.sanitised(Data(accepted)), Data(accepted), "in sequence, wrapping modulo 8")
        refuse(withRestarts(nil, [0xD0]), "RST without DRI")
        refuse(withRestarts([0, 0], [0xD0]), "RST under a zero restart interval")
        refuse(withRestarts([0, 4], [0xD1]), "RST out of sequence")
        refuse(withRestarts([0, 4], [0xD0, 0xD0]), "RST repeated")
    }
}
