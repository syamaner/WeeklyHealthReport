import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation

/// The directory fake transport (docs/pasted-label-ai-text-v1.md 8, A2: "all run over a fake
/// transport"; `send --fake-transport DIR`): canned replies from a directory, so nothing reaches
/// OpenRouter or any provider. A3's live runs use `LiveTransport` instead, chosen explicitly.
///
///     <dir>/catalogue/listing.json   the model's endpoint listing (the catalogue GET)
///     <dir>/catalogue/zdr.json       the zero-data-retention listing (the catalogue GET)
///     <dir>/responses/<label>.json   {"status": 200, "headers": {...}, "body": <object or string>}
///
/// It answers only the three URLs the route uses, and only a POST that carries an Authorization
/// header to the completions endpoint; anything else fails, as an unreachable host would.
public final class DirectoryFakeTransport: LabelPhotoHTTPTransporting, @unchecked Sendable {
    public let directory: URL
    public let labelID: String
    private let lock = NSLock()
    private var posts = 0

    public init(directory: URL, labelID: String) { self.directory = directory; self.labelID = labelID }

    public var postCount: Int { lock.withLock { posts } }

    public func send(_ request: LabelPhotoHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws -> LabelPhotoHTTPResponse {
        if Task.isCancelled { throw LabelPhotoTransportError.cancelled }
        let file: URL
        switch (request.method, request.url) {
        case ("GET", OpenRouterLabelRouteChecker.zeroDataRetentionURL):
            file = directory.appendingPathComponent("catalogue/zdr.json")
        case ("GET", _) where request.url.absoluteString.hasPrefix("https://openrouter.ai/api/v1/models/") && request.url.path.hasSuffix("/endpoints"):
            file = directory.appendingPathComponent("catalogue/listing.json")
        case ("POST", OpenRouterPastedLabelAITextRequest.endpointURL) where request.headers["Authorization"]?.hasPrefix("Bearer ") == true:
            lock.withLock { posts += 1 }
            let safe = labelID.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) }
            guard safe, !labelID.hasPrefix(".") else { throw LabelPhotoTransportError.failed }
            file = directory.appendingPathComponent("responses/\(labelID).json")
        default:
            throw LabelPhotoTransportError.failed
        }
        guard let data = FileManager.default.contents(atPath: file.path) else { throw LabelPhotoTransportError.failed }
        if file.lastPathComponent == "listing.json" || file.lastPathComponent == "zdr.json" {
            return LabelPhotoHTTPResponse(status: 200, headers: [:], body: Self.capped(data, maximumBodyBytes), exceededLimit: data.count > maximumBodyBytes)
        }
        guard let canned = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let status = canned["status"] as? Int else {
            throw LabelPhotoTransportError.failed
        }
        let headers = canned["headers"] as? [String: String] ?? [:]
        let body: Data
        switch canned["body"] {
        case let text as String: body = Data(text.utf8)
        case let object? where JSONSerialization.isValidJSONObject(object):
            body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        default: throw LabelPhotoTransportError.failed
        }
        return LabelPhotoHTTPResponse(status: status, headers: headers, body: Self.capped(body, maximumBodyBytes),
                                      exceededLimit: body.count > maximumBodyBytes)
    }

    static func capped(_ data: Data, _ limit: Int) -> Data { data.count > limit ? data.prefix(limit) : data }
}

/// A key store for the fake transport: a fixed placeholder that is not a credential. The fake path
/// never reads a key from the environment or a file, since nothing is sent; `--live` uses
/// `EnvironmentKey`.
public struct FakeTransportKey: FoodWebKeyStoring {
    public static let placeholder = "fake-transport-placeholder-not-a-key"
    public init() {}
    public func load() throws -> String? { Self.placeholder }
    public func save(_ key: String) throws {}
    public func delete() throws {}
}
