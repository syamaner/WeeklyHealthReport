// Route B recogniser adapter for the nutrition-label capture evaluation (#255).
//
// Reads a JSON array of {"id": String, "path": String} from standard input and writes a
// JSON object with the recogniser configuration and one result per image to standard
// output. Each result lists the recognised lines (top candidate text, confidence and
// bounding box) and, within each line, tokens with their own boxes. Tokens are maximal
// runs of Han characters or of other non-space characters, so `367.2大卡` gives `367.2`
// and `大卡` with separate geometry. The adapter decides nothing about nutrition: binding
// is the serialiser's job (`serialise_lines.py`) and parsing is the shared Swift parser's.
//
// Geometry is normalised to the image with the origin at the TOP left (Vision's origin is
// bottom left; the conversion is done here once). No network, no persistence; the image
// is read, recognised and released.
//
// Build: xcrun swiftc -O vision_v3.swift -o <outside the repository>/vision_v3

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Vision

let adapterVersion = "label-capture-vision-v3"
// Plan section 2: zh-Hant and en, using the exact identifiers the Vision revision
// advertises on the run day. `en-GB` is not advertised by revision 3 on macOS 27.0.1,
// so the English identifier is `en-US` (recorded, not represented as British support).
let requestedLanguages = ["zh-Hant", "en-US"]
// Inherited unchanged from the frozen v1 adapter (`frozen-contract-v1.json`, language_correction true).
let languageCorrection = true

struct Job: Decodable {
    let id: String
    let path: String
}

struct Box: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct Token: Encodable {
    let text: String
    let box: Box
}

struct Line: Encodable {
    let text: String
    let confidence: Float
    let box: Box
    let tokens: [Token]
}

struct ImageResult: Encodable {
    let id: String
    let imageSHA256: String
    let pixelWidth: Int
    let pixelHeight: Int
    let lines: [Line]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id
        case imageSHA256 = "image_sha256"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
        case lines
        case error
    }
}

struct Output: Encodable {
    let adapterVersion: String
    let requestRevision: Int
    let recognitionLevel: String
    let recognitionLanguages: [String]
    let supportedLanguages: [String]
    let usesLanguageCorrection: Bool
    let operatingSystem: String
    let results: [ImageResult]

    enum CodingKeys: String, CodingKey {
        case adapterVersion = "adapter_version"
        case requestRevision = "request_revision"
        case recognitionLevel = "recognition_level"
        case recognitionLanguages = "recognition_languages"
        case supportedLanguages = "supported_languages"
        case usesLanguageCorrection = "uses_language_correction"
        case operatingSystem = "operating_system"
        case results
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Vision rectangles are normalised with a bottom-left origin; flip to top-left.
func topLeft(_ rect: CGRect) -> Box {
    Box(x: rect.origin.x, y: 1 - rect.origin.y - rect.height, width: rect.width, height: rect.height)
}

let tokenPattern = try! NSRegularExpression(pattern: #"\p{Han}+|[^\s\p{Han}]+"#)

func makeRequest() -> VNRecognizeTextRequest {
    let request = VNRecognizeTextRequest()
    request.revision = VNRecognizeTextRequestRevision3
    request.recognitionLevel = .accurate
    request.recognitionLanguages = requestedLanguages
    request.usesLanguageCorrection = languageCorrection
    return request
}

func recognise(_ job: Job) -> ImageResult {
    let url = URL(fileURLWithPath: job.path)
    guard let data = try? Data(contentsOf: url) else {
        return ImageResult(id: job.id, imageSHA256: "", pixelWidth: 0, pixelHeight: 0, lines: [], error: "cannot read image bytes")
    }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return ImageResult(id: job.id, imageSHA256: digest, pixelWidth: 0, pixelHeight: 0, lines: [], error: "cannot decode image")
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientationValue = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
    let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
    let request = makeRequest()
    do {
        try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
    } catch {
        let nsError = error as NSError
        return ImageResult(id: job.id, imageSHA256: digest, pixelWidth: image.width, pixelHeight: image.height, lines: [],
                           error: "Vision request failed: domain=\(nsError.domain) code=\(nsError.code)")
    }
    let lines: [Line] = (request.results ?? []).compactMap { observation in
        guard let best = observation.topCandidates(1).first else { return nil }
        let text = best.string
        let tokens: [Token] = tokenPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let rect = (try? best.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
            return Token(text: String(text[range]), box: topLeft(rect))
        }
        return Line(text: text, confidence: best.confidence, box: topLeft(observation.boundingBox), tokens: tokens)
    }
    return ImageResult(id: job.id, imageSHA256: digest, pixelWidth: image.width, pixelHeight: image.height, lines: lines, error: nil)
}

let input = FileHandle.standardInput.readDataToEndOfFile()
let jobs: [Job]
do {
    jobs = try JSONDecoder().decode([Job].self, from: input)
} catch {
    fail("invalid input: \(error)")
}

let probe = makeRequest()
let supported = (try? probe.supportedRecognitionLanguages()) ?? []
let missing = requestedLanguages.filter { !supported.contains($0) }
if !missing.isEmpty {
    fail("recognition languages not advertised by this Vision revision: \(missing)")
}

let output = Output(
    adapterVersion: adapterVersion,
    requestRevision: probe.revision,
    recognitionLevel: "accurate",
    recognitionLanguages: requestedLanguages,
    supportedLanguages: supported,
    usesLanguageCorrection: languageCorrection,
    operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
    results: jobs.map(recognise)
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
FileHandle.standardOutput.write(try encoder.encode(output))
