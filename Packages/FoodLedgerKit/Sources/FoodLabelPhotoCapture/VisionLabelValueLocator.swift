import FoodLabelPhotoReading
import FoodLedgerApplication
import Foundation
import Vision

/// The `LabelValueLocating` adapter (docs/label-photo-ai-prefill-v1.md 6.1 and 12.1): Apple
/// Vision text recognition on the same prepared bytes that were sent, then the pinned pure
/// matcher (`LabelValueMatcher`, locator v3). Vision is confined to this file. On device, no
/// network. Recognition: revision 3, accurate, `zh-Hant` and `en-US` (those the running revision
/// supports), language correction off.
public struct VisionLabelValueLocator: LabelValueLocating {
    public static let revision = VNRecognizeTextRequestRevision3
    public static let languages = ["zh-Hant", "en-US"]

    public init() {}

    public func locate(_ image: PreparedLabelImage, candidate: PastedLabelManifest.Candidate) async throws -> LabelPhotoManifest.Locations {
        try Self.locate(image.bytes, candidate: candidate)
    }

    static func locate(_ jpeg: Data, candidate: PastedLabelManifest.Candidate) throws -> LabelPhotoManifest.Locations {
        let request = VNRecognizeTextRequest()
        request.revision = revision
        request.recognitionLevel = .accurate
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let languages = languages.filter(supported.contains)
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = false
        // The prepared bytes are upright with no orientation tag, so Vision reads them as they are.
        try VNImageRequestHandler(data: jpeg, orientation: .up, options: [:]).perform([request])
        var lines: [LabelValueMatcher.Line] = []
        var texts: [VNRecognizedText] = []
        for observation in request.results ?? [] {
            guard let best = observation.topCandidates(1).first else { continue }
            let box = observation.boundingBox
            lines.append(.init(text: best.string, box: .init(x: box.minX, y: box.minY, width: box.width, height: box.height)))
            texts.append(best)
        }
        let inputs = LabelPhotoLocatorQueries.inputs(candidate)
        let located = LabelValueMatcher.locate(inputs.queries, lines: lines, headers: inputs.headers, rowLabels: inputs.rowLabels,
                                               columnCount: inputs.columnCount, headerBases: inputs.headerBases) { index, range in
            guard let box = try? texts[index].boundingBox(for: range)?.boundingBox else { return nil }
            return .init(x: box.minX, y: box.minY, width: box.width, height: box.height)
        }
        return LabelPhotoManifest.Locations(locatorVersion: LabelValueMatcher.version, visionRevision: revision, languages: languages,
                                            records: LabelPhotoLocatorQueries.records(inputs.queries, located: located))
    }
}
