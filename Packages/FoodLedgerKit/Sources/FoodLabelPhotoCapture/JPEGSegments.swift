import Foundation

/// The prepared JPEG's structure, allow-listed (docs/label-photo-ai-prefill-v1.md 17.8 M6 and the
/// #324 review). Pure: bytes in, bytes or nil out. The sanitised file is exactly:
///
/// SOI; optionally one APP0 that is a plain JFIF header (16 bytes, no thumbnail); quantisation and
/// Huffman tables and a restart interval; exactly one baseline frame (SOF0); exactly one scan
/// (SOS); entropy-coded data holding only stuffed `FF 00` and restart markers `FF D0` to `FF D7`;
/// and one EOI as the final two bytes. Application segments other than APP0, and comments, before
/// the scan are dropped (they hold the encoder's metadata, such as an ICC profile). Anything else
/// (an APP0 that is not a plain JFIF header, a standalone or reserved marker before the scan, a
/// progressive or other frame, a second scan, a marker inside the scan data, trailing bytes after
/// EOI, an appended image) makes it nil, and the preparer refuses the read. No metadata block can
/// therefore leave the device.
enum JPEGSegments {
    struct Segment { let marker: UInt8; let range: Range<Int> }

    static let allowedBeforeScan: Set<UInt8> = [0xE0, 0xDB, 0xC4, 0xDD, 0xC0]

    /// The sanitised JPEG, or nil when the bytes are anything but the allow-listed structure.
    static func sanitised(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var out: [UInt8] = [0xFF, 0xD8]
        var index = 2
        var frames = 0
        while true {
            guard index + 4 <= bytes.count, bytes[index] == 0xFF else { return nil }
            let marker = bytes[index + 1]
            // Only length-bearing markers precede the scan: never fill bytes, a standalone marker
            // (SOI, EOI, TEM, RSTn) or a reserved one. Application segments other than APP0 and
            // comments (the encoder's metadata, such as an ICC profile) are dropped; everything
            // else that is not allow-listed refuses the file.
            let droppable = (0xE1...0xEF).contains(marker) || marker == 0xFE
            guard marker == 0xDA || allowedBeforeScan.contains(marker) || droppable else { return nil }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let end = index + 2 + length
            guard length >= 2, end <= bytes.count else { return nil }
            let segment = Array(bytes[index..<end])
            if droppable { index = end; continue }
            switch marker {
            case 0xE0:
                // A plain JFIF header only: identifier `JFIF\0`, no thumbnail (JFXX or a JFIF
                // thumbnail is refused).
                guard length == 16, Array(segment[4..<9]) == [0x4A, 0x46, 0x49, 0x46, 0x00], segment[16] == 0, segment[17] == 0 else {
                    return nil
                }
            case 0xC0:
                frames += 1
                guard frames == 1 else { return nil }
            default: break
            }
            out += segment
            index = end
            if marker == 0xDA { break }
        }
        guard frames == 1 else { return nil }
        // The entropy-coded data: only stuffed bytes and restart markers, then EOI as the last two bytes.
        var position = index
        while position < bytes.count {
            if bytes[position] != 0xFF { position += 1; continue }
            guard position + 1 < bytes.count else { return nil }
            let next = bytes[position + 1]
            if next == 0x00 || (0xD0...0xD7).contains(next) { position += 2; continue }
            guard next == 0xD9, position + 2 == bytes.count else { return nil }
            out += bytes[index..<bytes.count]
            return Data(out)
        }
        return nil
    }

    // MARK: Diagnostics for tests

    /// The markers before the scan as a lenient listing, for test assertions only; nil when the
    /// header cannot be walked at all.
    static func markers(_ data: Data) -> [UInt8]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var markers: [UInt8] = []
        var index = 2
        while index + 4 <= bytes.count {
            guard bytes[index] == 0xFF else { return nil }
            let marker = bytes[index + 1]
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2, index + 2 + length <= bytes.count else { return nil }
            markers.append(marker)
            if marker == 0xDA { return markers }
            index += 2 + length
        }
        return nil
    }
}
