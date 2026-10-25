import Foundation

/// The JPEG marker segments before the image data (docs/label-photo-ai-prefill-v1.md 17.8 M6).
/// Pure: bytes in, bytes or nil out. Used to remove every application segment except APP0 (JFIF)
/// and every comment, so no metadata block an encoder adds can leave the device (invariant 3).
enum JPEGSegments {
    /// The markers (second byte) of the segments before start of scan, in order, or nil when the
    /// bytes are not a well-formed JPEG header.
    static func markers(_ data: Data) -> [UInt8]? {
        segments(data).map { $0.map(\.marker) }
    }

    struct Segment { let marker: UInt8; let range: Range<Int> }

    /// Every segment from SOI up to and including SOS's header; nil when malformed.
    static func segments(_ data: Data) -> [Segment]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var segments: [Segment] = []
        var index = 2
        while index + 4 <= bytes.count {
            guard bytes[index] == 0xFF else { return nil }
            var markerIndex = index + 1
            while markerIndex < bytes.count, bytes[markerIndex] == 0xFF { markerIndex += 1 } // fill bytes
            guard markerIndex + 2 < bytes.count else { return nil }
            let marker = bytes[markerIndex]
            let length = Int(bytes[markerIndex + 1]) << 8 | Int(bytes[markerIndex + 2])
            let end = markerIndex + 1 + length
            guard length >= 2, end <= bytes.count else { return nil }
            segments.append(Segment(marker: marker, range: index..<end))
            if marker == 0xDA { return segments } // start of scan: the rest is image data
            index = end
        }
        return nil
    }

    /// The JPEG with every APP1 to APP15 segment and every comment removed; nil when malformed.
    static func strippingMetadata(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let segments = segments(data), let scan = segments.last, scan.marker == 0xDA else { return nil }
        var out: [UInt8] = [0xFF, 0xD8]
        for segment in segments {
            let isApplication = (0xE1...0xEF).contains(segment.marker)
            if isApplication || segment.marker == 0xFE { continue }
            out += bytes[segment.range]
        }
        out += bytes[scan.range.upperBound...]
        return Data(out)
    }
}
