import CoreGraphics
import FoodLedgerApplication
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The `LabelImagePreparing` adapter, `label-photo-preparation-v1` (docs/label-photo-ai-prefill-v1.md
/// P3, P5, E3, 17.8 M6 and 17.17). ImageIO and CoreGraphics are confined to this file.
///
/// In order: read the photo's size and orientation; refuse a crop (normalised to the upright photo)
/// whose short edge is under 240 px or whose sides differ by more than 8 times; decode the primary
/// image subsampled to the size the crop needs at the output bounds, with its orientation applied
/// to the pixels; crop; turn by the user's quarter turns; scale so the long edge is at most 2,048 px
/// and the area at most 3.2 megapixels, refusing a result whose short edge falls under 240 px; draw
/// into an 8-bit sRGB bitmap; encode a baseline JPEG from those pixels alone, at quality 0.85, then
/// 0.75, then 0.65 while it exceeds 1,500,000 bytes (else refuse); and keep only the allow-listed
/// JPEG structure (`JPEGSegments.sanitised`), refusing anything else. No property of the source is
/// passed to the encoder, so no EXIF, GPS, TIFF, IPTC, XMP, maker note, thumbnail, depth or gain map
/// can leave; the output is untagged sRGB.
public struct ImageIOLabelImagePreparer: LabelImagePreparing {
    public static let qualities: [Double] = [0.85, 0.75, 0.65]
    /// The longest side may be at most this many times the shortest (decided on #324).
    public static let maximumAspectRatio: Double = 8

    let digester: any Digesting

    public init(digester: any Digesting = SHA256Digester()) { self.digester = digester }

    public func prepare(_ source: Data, crop: LabelCropRect) throws -> PreparedLabelImage {
        guard let imageSource = CGImageSourceCreateWithData(source as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(imageSource) > 0 else { throw LabelImagePreparationError.unreadable }
        let index = CGImageSourceGetPrimaryImageIndex(imageSource)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any],
              let storedWidth = properties[kCGImagePropertyPixelWidth] as? Int, let storedHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              storedWidth > 0, storedHeight > 0 else { throw LabelImagePreparationError.unreadable }
        // Orientations 5 to 8 turn the photo a quarter, swapping its sides when upright.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let swaps = (5...8).contains(orientation)
        let width = swaps ? storedHeight : storedWidth, height = swaps ? storedWidth : storedHeight
        let plan = try Self.plan(uprightWidth: width, uprightHeight: height, crop: crop)
        // Decode only as many pixels as the crop needs at the output size, upright.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: plan.decodeMaxPixelSize, kCGImageSourceShouldCacheImmediately: true]
        guard let upright = CGImageSourceCreateThumbnailAtIndex(imageSource, index, options as CFDictionary) else {
            throw LabelImagePreparationError.unreadable
        }
        let rect = CGRect(x: crop.x * Double(upright.width), y: crop.y * Double(upright.height),
                          width: crop.width * Double(upright.width), height: crop.height * Double(upright.height)).integral
            .intersection(CGRect(x: 0, y: 0, width: upright.width, height: upright.height))
        guard !rect.isEmpty, let cropped = upright.cropping(to: rect) else { throw LabelImagePreparationError.unreadable }
        let pixels = try Self.render(cropped, quarterTurns: crop.quarterTurns, width: plan.outputWidth, height: plan.outputHeight)
        let (encoded, quality) = try Self.ladder { quality in
            guard let sanitised = JPEGSegments.sanitised(try Self.encode(pixels, quality: quality)) else {
                throw LabelImagePreparationError.malformedOutput
            }
            return sanitised
        }
        return try PreparedLabelImageFactory.make(bytes: encoded, pixelWidth: pixels.width, pixelHeight: pixels.height,
                                                  jpegQuality: Self.qualityText(quality), digester: digester)
    }

    struct Plan: Equatable {
        let outputWidth: Int
        let outputHeight: Int
        let decodeMaxPixelSize: Int
    }

    /// The output size and the decode size for `crop` of an upright `uprightWidth` × `uprightHeight`
    /// photo; throws when the crop is too small (before or after scaling) or too narrow.
    static func plan(uprightWidth: Int, uprightHeight: Int, crop: LabelCropRect) throws -> Plan {
        guard crop.shortEdge(pixelWidth: uprightWidth, pixelHeight: uprightHeight) >= LabelCropRect.minimumShortEdge else {
            throw LabelImagePreparationError.cropTooSmall
        }
        let cropWidth = crop.width * Double(uprightWidth), cropHeight = crop.height * Double(uprightHeight)
        guard max(cropWidth, cropHeight) / min(cropWidth, cropHeight) <= maximumAspectRatio else {
            throw LabelImagePreparationError.cropTooNarrow
        }
        let turned = crop.quarterTurns % 2 == 0 ? (cropWidth, cropHeight) : (cropHeight, cropWidth)
        let factor = scale(width: turned.0, height: turned.1)
        var width = max(1, Int((turned.0 * factor).rounded(.down)))
        var height = max(1, Int((turned.1 * factor).rounded(.down)))
        while width * height > PreparedLabelImage.maximumPixels {
            width -= 1
            height = max(1, Int((Double(width) * turned.1 / turned.0).rounded(.down)))
        }
        guard Double(min(width, height)) >= LabelCropRect.minimumShortEdge else { throw LabelImagePreparationError.cropTooSmall }
        // The whole upright photo at the crop's scale, with a small margin, never above full size.
        let long = Double(max(uprightWidth, uprightHeight))
        let decode = min(Int(long), Int((long * factor).rounded(.up)) + 2)
        return Plan(outputWidth: width, outputHeight: height, decodeMaxPixelSize: decode)
    }

    /// The scale that brings the long edge to at most 2,048 px and the area to at most 3.2 MP.
    static func scale(width: Double, height: Double) -> Double {
        min(1, Double(PreparedLabelImage.maximumLongEdge) / max(width, height),
            (Double(PreparedLabelImage.maximumPixels) / (width * height)).squareRoot())
    }

    /// The quality ladder: the first encoding within the byte limit, or `outOfBounds`.
    static func ladder(_ encode: (Double) throws -> Data) throws -> (Data, Double) {
        for quality in qualities {
            let data = try encode(quality)
            if data.count <= PreparedLabelImage.maximumBytes { return (data, quality) }
        }
        throw LabelImagePreparationError.outOfBounds
    }

    /// The crop turned clockwise by `quarterTurns`, drawn at `width` × `height` into 8-bit sRGB.
    static func render(_ image: CGImage, quarterTurns: Int, width: Int, height: Int) throws -> CGImage {
        let turns = ((quarterTurns % 4) + 4) % 4
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

    /// A JPEG of the pixels alone: no source property is passed to the encoder.
    static func encode(_ pixels: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw LabelImagePreparationError.malformedOutput
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality, kCGImageDestinationEmbedThumbnail: false,
                                        kCGImageMetadataShouldExcludeXMP: true, kCGImageMetadataShouldExcludeGPS: true]
        CGImageDestinationAddImage(destination, pixels, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LabelImagePreparationError.malformedOutput }
        return output as Data
    }

    static func qualityText(_ quality: Double) -> String {
        String(format: "%.2f", quality).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }
}
