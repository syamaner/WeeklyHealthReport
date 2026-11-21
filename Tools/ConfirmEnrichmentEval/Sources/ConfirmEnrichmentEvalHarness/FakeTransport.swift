import FoodConfirmEnrichment
import Foundation

/// A transport that sends nothing (tests and `send --fake DIR`). It records each request's method, URL
/// and header names (never a header value) and answers from a handler. `directory(_:)` answers from files:
/// `details.json` and `nutrients.json` for the two POSTs, `endpoints.json` for a model's endpoint listing
/// and `zdr.json` for the zero-data-retention listing; a missing file is a 404.
public final class FakeTransport: ConfirmEnrichmentHTTPTransporting, @unchecked Sendable {
    public struct Sent: Equatable, Sendable {
        public let method: String
        public let url: URL
        public let headerNames: [String]
        public let body: Data?
    }

    public typealias Handler = @Sendable (ConfirmEnrichmentHTTPRequest) -> ConfirmEnrichmentHTTPResponse

    private let lock = NSLock()
    private var recorded: [Sent] = []
    private let handler: Handler

    public init(handler: @escaping Handler) { self.handler = handler }

    public static func directory(_ folder: URL) -> FakeTransport {
        FakeTransport { request in
            let name: String
            if request.method == "POST" {
                name = request.url.path.hasSuffix("/systemone") ? "details.json" : "nutrients.json"
            } else {
                name = request.url.path.hasSuffix("/endpoints/zdr") ? "zdr.json" : "endpoints.json"
            }
            guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(name).path) else {
                return ConfirmEnrichmentHTTPResponse(status: 404, headers: [:], body: Data(), exceededLimit: false)
            }
            return ConfirmEnrichmentHTTPResponse(status: 200, headers: [:], body: data, exceededLimit: false)
        }
    }

    public func send(_ request: ConfirmEnrichmentHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws
        -> ConfirmEnrichmentHTTPResponse {
        lock.withLock {
            recorded.append(Sent(method: request.method, url: request.url, headerNames: request.headers.keys.sorted(), body: request.body))
        }
        let response = handler(request)
        guard response.body.count <= maximumBodyBytes else {
            return ConfirmEnrichmentHTTPResponse(status: response.status, headers: response.headers,
                                                 body: response.body.prefix(maximumBodyBytes), exceededLimit: true)
        }
        return response
    }

    public var sent: [Sent] { lock.withLock { recorded } }
}
