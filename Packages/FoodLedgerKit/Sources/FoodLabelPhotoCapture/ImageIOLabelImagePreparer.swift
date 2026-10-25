import CoreGraphics
import CryptoKit
import FoodLedgerApplication
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The `LabelImagePreparing` adapter, `label-photo-preparation-v1` (docs/label-photo-ai-prefill-v1.md
/// P3, P5, E3 and 17.8 M6). ImageIO and CoreGraphics are confined to this file.
///
/// In order: decode the primary image with its orientation applied to the pixels; crop to the
/// user's rectangle (normalised to that upright photo); refuse a crop whose short edge is under
/// 240 px; rotate by the user's quarter turns; scale so the long edge is at most 2,048 px and the
/// area at most 3.2 megapixels; draw into an 8-bit sRGB bitmap; encode a baseline JPEG from those
/// pixels alone, at quality 0.85, then 0.75, then 0.65 while it exceeds 1,500,000 bytes (else
/// refuse); and remove every application segment except APP0 and every comment from the encoded
/// bytes. No property of the source is passed to the encoder, so no EXIF, GPS, TIFF, IPTC, XMP,
/// maker note, thumbnail, depth or gain map can leave; the output is untagged sRGB.
public struct ImageIOLabelImagePreparer: LabelImagePreparing {
    public static let qualities: [Double] = [0.85, 0.75, 0.65]

    public init() {}

    public func prepare(_ source: Data, crop: LabelCropRect) throws -> PreparedLabelImage {
        guard let imageSource = CGImageSourceCreateWithData(source as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(imageSource) > 0 else { throw LabelImagePreparationError.unreadable }
        let index = CGImageSourceGetPrimaryImageIndex(imageSource)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw LabelImagePreparationError.unreadable }
        // The full-size image with its orientation applied to the pixels.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(width, height), kCGImageSourceShouldCacheImmediately: true]
        guard let upright = CGImageSourceCreateThumbnailAtIndex(imageSource, index, options as CFDictionary) else {
            throw LabelImagePreparationError.unreadable
        }
        guard crop.shortEdge(pixelWidth: upright.width, pixelHeight: upright.height) >= LabelCropRect.minimumShortEdge else {
            throw LabelImagePreparationError.cropTooSmall
        }
        let rect = CGRect(x: crop.x * Double(upright.width), y: crop.y * Double(upright.height),
                          width: crop.width * Double(upright.width), height: crop.height * Double(upright.height)).integral
            .intersection(CGRect(x: 0, y: 0, width: upright.width, height: upright.height))
        guard !rect.isEmpty, let cropped = upright.cropping(to: rect) else { throw LabelImagePreparationError.unreadable }
        let pixels = try Self.render(cropped, quarterTurns: crop.quarterTurns)
        for quality in Self.qualities {
            let encoded = try Self.encode(pixels, quality: quality)
            guard encoded.count <= PreparedLabelImage.maximumBytes else { continue }
            let digest = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
            return try PreparedLabelImageFactory.make(bytes: encoded, pixelWidth: pixels.width, pixelHeight: pixels.height, sha256: digest,
                                                      jpegQuality: Self.qualityText(quality))
        }
        throw LabelImagePreparationError.outOfBounds
    }

    /// The scale that brings the long edge to at most 2,048 px and the area to at most 3.2 MP.
    static func scale(width: Int, height: Int) -> Double {
        let long = Double(max(width, height)), area = Double(width) * Double(height)
        return min(1, Double(PreparedLabelImage.maximumLongEdge) / long, (Double(PreparedLabelImage.maximumPixels) / area).squareRoot())
    }

    /// The crop turned clockwise by `quarterTurns`, scaled within the bounds, drawn into 8-bit sRGB.
    static func render(_ image: CGImage, quarterTurns: Int) throws -> CGImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        let turnedWidth = turns % 2 == 0 ? image.width : image.height
        let turnedHeight = turns % 2 == 0 ? image.height : image.width
        let factor = scale(width: turnedWidth, height: turnedHeight)
        var width = max(1, Int((Double(turnedWidth) * factor).rounded(.down)))
        var height = max(1, Int((Double(turnedHeight) * factor).rounded(.down)))
        while width * height > PreparedLabelImage.maximumPixels { width -= 1; height = max(1, Int(Double(width) * Double(turnedHeight) / Double(turnedWidth))) }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw LabelImagePreparationError.unreadable }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Quarter turns clockwise, about the centre of the output.
        context.translateBy(x: Double(width) / 2, y: Double(height) / 2)
        context.rotate(by: -Double(turns) * .pi / 2)
        let drawWidth = turns % 2 == 0 ? Double(width) : Double(height)
        let drawHeight = turns % 2 == 0 ? Double(height) : Double(width)
        context.draw(image, in: CGRect(x: -drawWidth / 2, y: -drawHeight / 2, width: drawWidth, height: drawHeight))
        guard let pixels = context.makeImage() else { throw LabelImagePreparationError.unreadable }
        return pixels
    }

    /// A JPEG of the pixels alone: no source property is passed, and the encoder's own metadata
    /// segments are removed afterwards (APP0 is kept).
    static func encode(_ pixels: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw LabelImagePreparationError.outOfBounds
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality, kCGImageDestinationEmbedThumbnail: false,
                                        kCGImageMetadataShouldExcludeXMP: true, kCGImageMetadataShouldExcludeGPS: true]
        CGImageDestinationAddImage(destination, pixels, options as CFDictionary)
        guard CGImageDestinationFinalize(destination), let stripped = JPEGSegments.strippingMetadata(output as Data) else {
            throw LabelImagePreparationError.outOfBounds
        }
        return stripped
    }

    static func qualityText(_ quality: Double) -> String {
        String(format: "%.2f", quality).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }
}
