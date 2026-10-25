import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Synthetic photo fixtures built at test time (docs/label-photo-ai-prefill-v1.md 12.5 tests 13 and
/// 14, 17.8 test 23). Nothing here is a real photo. Each carries the metadata the preparer must
/// remove, and the positive controls assert it is really there before preparation.
enum LabelPhotoFixtureImages {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A white image with a red block in its top-left quarter (as stored, before any orientation).
    static func asymmetric(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        // CoreGraphics' origin is bottom left: the top-left quarter is at the top of the context.
        context.fill(CGRect(x: 0, y: height - height / 2, width: width / 2, height: height / 2))
        return context.makeImage()!
    }

    /// Deterministic noise, which JPEG compresses poorly.
    static func noise(width: Int, height: Int, seed: UInt64 = 0x2545F4914F6CDD1D) -> CGImage {
        var state = seed
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<3 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                bytes[index + channel] = UInt8(truncatingIfNeeded: state >> 56)
            }
            bytes[index + 3] = 255
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: srgb,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// A JPEG with EXIF, GPS, TIFF, IPTC, Apple maker note and XMP, an embedded thumbnail and the
    /// given orientation.
    static func jpegWithEverything(_ image: CGImage, orientation: Int = 6) -> Data {
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataSetValueWithPath(metadata, nil, "dc:title" as CFString, "synthetic label" as CFString)
        CGImageMetadataSetValueWithPath(metadata, nil, "photoshop:City" as CFString, "Taipei" as CFString)
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "synthetic", kCGImagePropertyExifDateTimeOriginal: "2026:10:25 10:00:00"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 25.03, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 121.56, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["label"], kCGImagePropertyIPTCCity: "Taipei"],
            kCGImagePropertyMakerAppleDictionary: ["1": 14, "8": [0.1, 0.2, 0.3]],
            kCGImageDestinationEmbedThumbnail: true,
        ]
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        return out as Data
    }

    /// A HEIC with a depth map and an HDR gain map as auxiliary images.
    static func heicWithDepthAndGainMap(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.heic.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1, kCGImagePropertyGPSDictionary:
            [kCGImagePropertyGPSLatitude: 25.03, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary)
        let depthWidth = 40, depthHeight = 30
        let depth: [CFString: Any] = [
            kCGImageAuxiliaryDataInfoData: Data(count: depthWidth * depthHeight * 2),
            kCGImageAuxiliaryDataInfoDataDescription: [kCGImagePropertyWidth: depthWidth, kCGImagePropertyHeight: depthHeight,
                                                       kCGImagePropertyBytesPerRow: depthWidth * 2, kCGImagePropertyPixelFormat: 0x6864_6570],
        ]
        CGImageDestinationAddAuxiliaryDataInfo(destination, kCGImageAuxiliaryDataTypeDepth, depth as CFDictionary)
        let gainWidth = 100, gainHeight = 75
        let gainMetadata = CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(gainMetadata, "http://ns.apple.com/HDRGainMap/1.0/" as CFString, "HDRGainMap" as CFString, nil)
        CGImageMetadataSetValueWithPath(gainMetadata, nil, "HDRGainMap:HDRGainMapVersion" as CFString, 65_536 as CFNumber)
        let gain: [CFString: Any] = [
            kCGImageAuxiliaryDataInfoData: Data(repeating: 128, count: gainWidth * gainHeight),
            kCGImageAuxiliaryDataInfoDataDescription: [kCGImagePropertyWidth: gainWidth, kCGImagePropertyHeight: gainHeight,
                                                       kCGImagePropertyBytesPerRow: gainWidth, kCGImagePropertyPixelFormat: 0x4C30_3038],
            kCGImageAuxiliaryDataInfoMetadata: gainMetadata,
        ]
        CGImageDestinationAddAuxiliaryDataInfo(destination, kCGImageAuxiliaryDataTypeHDRGainMap, gain as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    /// A PNG with `eXIf` and `tEXt` chunks inserted before its image data.
    static func pngWithExifAndText(_ image: CGImage) -> Data {
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        var png = [UInt8](out as Data)
        // A minimal big-endian TIFF header with no entries is a valid eXIf payload for the test.
        let exif: [UInt8] = Array("MM".utf8) + [0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00]
        let text: [UInt8] = Array("Comment".utf8) + [0] + Array("GPS 25.03N 121.56E".utf8)
        let idat = png.firstIndex(ofSequence: Array("IDAT".utf8))! - 4
        png.insert(contentsOf: chunk("tEXt", text) + chunk("eXIf", exif), at: idat)
        return Data(png)
    }

    static func chunk(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        let typeBytes = Array(type.utf8)
        let length = UInt32(payload.count)
        let crc = crc32(typeBytes + payload)
        return [UInt8(length >> 24), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)] + typeBytes + payload
            + [UInt8(crc >> 24), UInt8(crc >> 16 & 0xFF), UInt8(crc >> 8 & 0xFF), UInt8(crc & 0xFF)]
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    /// The RGB of the decoded pixel at (x, y), with the origin top left.
    static func pixel(_ data: Data, x: Int, y: Int) -> (Int, Int, Int) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = (y * image.width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }
}

extension Array where Element == UInt8 {
    func firstIndex(ofSequence needle: [UInt8]) -> Int? {
        guard needle.count <= count else { return nil }
        return (0...(count - needle.count)).first { Array(self[$0..<($0 + needle.count)]) == needle }
    }
}
