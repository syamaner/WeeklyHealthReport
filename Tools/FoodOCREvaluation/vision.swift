import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Vision

struct Candidate: Codable {
    let text: String
    let confidence: Float
}

struct Box: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct Observation: Codable {
    let candidates: [Candidate]
    let boundingBox: Box
    let tokens: [Token]
}

struct Token: Codable {
    let text: String
    let boundingBox: Box
}

struct Result: Codable {
    let schemaVersion: Int
    let imageSHA256: String
    let recognizer: String
    let recognitionLevel: String
    let recognitionLanguages: [String]
    let usesLanguageCorrection: Bool
    let observations: [Observation]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: vision IMAGE")
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("cannot decode image")
}

let imageData: Data
do {
    imageData = try Data(contentsOf: imageURL)
} catch {
    fail("cannot read image bytes: \(error)")
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["en-US"]
request.usesLanguageCorrection = true

do {
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
} catch {
    let nsError = error as NSError
    fail("Vision request failed: domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription) userInfo=\(nsError.userInfo)")
}

let observations = (request.results ?? [])
    .sorted {
        if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01 {
            return $0.boundingBox.midY > $1.boundingBox.midY
        }
        return $0.boundingBox.minX < $1.boundingBox.minX
    }
    .map { observation in
        let recognized = observation.topCandidates(1).first
        let tokens: [Token]
        if let recognized {
            let text = recognized.string
            let expression = try! NSRegularExpression(pattern: #"\S+"#)
            tokens = expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
                guard let range = Range(match.range, in: text),
                      let tokenBox = try? recognized.boundingBox(for: range) else {
                    return nil
                }
                return Token(
                    text: String(text[range]),
                    boundingBox: Box(
                        x: tokenBox.boundingBox.origin.x,
                        y: tokenBox.boundingBox.origin.y,
                        width: tokenBox.boundingBox.width,
                        height: tokenBox.boundingBox.height
                    )
                )
            }
        } else {
            tokens = []
        }
        return Observation(
            candidates: observation.topCandidates(3).map {
                Candidate(text: $0.string, confidence: $0.confidence)
            },
            boundingBox: Box(
                x: observation.boundingBox.origin.x,
                y: observation.boundingBox.origin.y,
                width: observation.boundingBox.width,
                height: observation.boundingBox.height
            ),
            tokens: tokens
        )
    }

let digest = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()

let result = Result(
    schemaVersion: 1,
    imageSHA256: digest,
    recognizer: "Apple Vision VNRecognizeTextRequest",
    recognitionLevel: "accurate",
    recognitionLanguages: ["en-US"],
    usesLanguageCorrection: true,
    observations: observations
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
do {
    FileHandle.standardOutput.write(try encoder.encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    fail("cannot encode result: \(error)")
}
