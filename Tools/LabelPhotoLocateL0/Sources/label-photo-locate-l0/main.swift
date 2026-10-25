// Phase L0 (#316): prepare each photo as E3 says, run Vision on the prepared bytes on this Mac,
// and locate each returned printed value with the shipped matcher. No network call.
//
//   swift run --package-path Tools/LabelPhotoLocateL0 label-photo-locate-l0 <jobs.json> <out.json>
//
// Jobs and output stay outside the repository (they name photo files and carry model text);
// only counts are committed. The preparation here implements the E3 numbers for measurement;
// the shipped preparer is built and hardened in L2 (section 17.8).
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import LabelValueMatching
import UniformTypeIdentifiers
import Vision

struct Job: Decodable {
    struct Query: Decodable { let id: String; let row_label: String?; let header_text: String?; let printed_text: String }
    let id: String
    let image_path: String
    let headers: [String]
    let column_count: Int
    let queries: [Query]
}

struct Result: Encodable {
    struct Prepared: Encodable { let width: Int; let height: Int; let bytes: Int; let quality: Double; let sha256: String }
    struct Located: Encodable { let id: String; let status: String; let evidence: String }
    let id: String
    let refused: String?
    let prepared: Prepared?
    let vision: [String: String]
    let line_count: Int
    let locations: [Located]
}

struct Refusal: Error { let reason: String; init(_ reason: String) { self.reason = reason } }

enum Preparation {
    static let longEdge = 2048.0, maxPixels = 3_200_000.0, maxBytes = 1_500_000
    /// 240 px is P5 as decided after L0 (480 px in the first L0 run); `L0_MIN_SHORT_EDGE` overrides it for a comparison run only.
    static let minShortEdge = Double(ProcessInfo.processInfo.environment["L0_MIN_SHORT_EDGE"] ?? "") ?? 240
    static let qualities = [0.85, 0.75, 0.65]

    /// E3: orientation applied to pixels, sRGB, long edge <= 2,048 px and <= 3.2 MP, JPEG with no
    /// metadata dictionary, quality ladder 0.85 / 0.75 / 0.65, <= 1,500,000 bytes, short edge >= 240 (P5).
    static func prepare(_ data: Data) -> Swift.Result<(Data, Int, Int, Double), Refusal> {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double else { return .failure(.init("undecodable")) }
        let scale = min(1, longEdge / max(width, height), (maxPixels / (width * height)).squareRoot())
        let target = Int((max(width, height) * scale).rounded(.down))
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: target]
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return .failure(.init("undecodable")) }
        guard Double(min(oriented.width, oriented.height)) >= minShortEdge else {
            return .failure(.init("short_edge_below_minimum"))
        }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: oriented.width, height: oriented.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return .failure(.init("context")) }
        context.draw(oriented, in: CGRect(x: 0, y: 0, width: oriented.width, height: oriented.height))
        guard let pixels = context.makeImage() else { return .failure(.init("context")) }
        for quality in qualities {
            let out = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return .failure(.init("encoder")) }
            CGImageDestinationAddImage(destination, pixels, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return .failure(.init("encoder")) }
            if out.length <= maxBytes { return .success((out as Data, pixels.width, pixels.height, quality)) }
        }
        return .failure(.init("too_large"))
    }
}

let languages = ["zh-Hant", "en-US"]

func recognise(_ jpeg: Data) throws -> ([LabelValueMatcher.Line], [VNRecognizedText]) {
    guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
    let request = VNRecognizeTextRequest()
    request.revision = VNRecognizeTextRequestRevision3
    request.recognitionLevel = .accurate
    request.recognitionLanguages = languages
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
    var lines: [LabelValueMatcher.Line] = [], texts: [VNRecognizedText] = []
    for observation in request.results ?? [] {
        guard let best = observation.topCandidates(1).first else { continue }
        let box = observation.boundingBox
        lines.append(.init(text: best.string, box: .init(x: box.minX, y: box.minY, width: box.width, height: box.height)))
        texts.append(best)
    }
    return (lines, texts)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: label-photo-locate-l0 <jobs.json> <out.json>\n".utf8)); exit(2)
}
let jobs = try JSONDecoder().decode([Job].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
var results: [Result] = []
// Private diagnosis only: `L0_DEBUG_LINES` names a file outside the repository for the recognised lines.
var debug: [[String: String]] = []
let vision = ["locator": LabelValueMatcher.version, "revision": "3", "level": "accurate",
              "languages": languages.joined(separator: ","), "language_correction": "false"]
for job in jobs {
    let original = try Data(contentsOf: URL(fileURLWithPath: job.image_path))
    let jpeg: Data, width: Int, height: Int, quality: Double
    switch Preparation.prepare(original) {
    case let .success(prepared): (jpeg, width, height, quality) = prepared
    case let .failure(refusal):
        results.append(Result(id: job.id, refused: refusal.reason, prepared: nil, vision: vision, line_count: 0, locations: [])); continue
    }
    let (lines, texts) = try recognise(jpeg)
    let queries = job.queries.map { LabelValueMatcher.Query(id: $0.id, rowLabel: $0.row_label, headerText: $0.header_text, printedText: $0.printed_text) }
    let rowLabels = Array(Set(job.queries.compactMap(\.row_label))).sorted()
    let located = LabelValueMatcher.locate(queries, lines: lines, headers: job.headers, rowLabels: rowLabels,
                                           columnCount: job.column_count) { index, range in
        guard let box = try? texts[index].boundingBox(for: range)?.boundingBox else { return nil }
        return .init(x: box.minX, y: box.minY, width: box.width, height: box.height)
    }
    debug.append(["id": job.id, "lines": lines.map(\.text).joined(separator: "\n")])
    let digest = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
    results.append(Result(id: job.id, refused: nil,
                          prepared: .init(width: width, height: height, bytes: jpeg.count, quality: quality, sha256: digest),
                          vision: vision, line_count: lines.count,
                          locations: located.map { .init(id: $0.id, status: $0.status.rawValue, evidence: $0.evidence.rawValue) }))
}
let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
try encoder.encode(results).write(to: URL(fileURLWithPath: arguments[2]))
if let path = ProcessInfo.processInfo.environment["L0_DEBUG_LINES"] {
    try JSONSerialization.data(withJSONObject: debug, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: path))
}
print("located \(results.count) photos")
