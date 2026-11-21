import FoodLedgerApplication
import Foundation

/// The live transport of Confirm enrichment (docs/confirm-enrichment-openrouter-v1-phase.md section 3.1):
/// the one file in FoodConfirmEnrichment allowed to load URLs (check-boundaries.sh). As label photo's
/// `OpenRouterTransport`, it uses an ephemeral configuration with no cookie store, URL cache or
/// credential storage; sends a fixed, neutral `User-Agent` and `Accept-Language: *`; refuses every
/// redirect; stops reading past the byte limit; ends each request at its timeout as a whole; and maps a
/// task cancellation, and only that, to `.cancelled`. It adds no header of its own beyond those two:
/// the adapters add the Authorization header to their POST only, and the checker's GETs carry none.
public final class ConfirmEnrichmentTransport: NSObject, ConfirmEnrichmentHTTPTransporting, @unchecked Sendable {
    public static let userAgent = "WeeklyHealthReport-ConfirmEnrichment/1"
    private let session: URLSession

    /// `configure` lets tests install a stub protocol on the same configuration.
    public init(configure: (URLSessionConfiguration) -> Void = { _ in }) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent, "Accept-Language": "*"]
        configuration.waitsForConnectivity = false
        configure(configuration)
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: nil, delegateQueue: delegateQueue)
        super.init()
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ request: ConfirmEnrichmentHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws
        -> ConfirmEnrichmentHTTPResponse {
        guard timeout > 0, timeout.isFinite, timeout <= 300 else { throw ConfirmEnrichmentTransportError.timedOut }
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = false
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let session = session
        let prepared = urlRequest
        do {
            return try await withThrowingTaskGroup(of: ConfirmEnrichmentHTTPResponse.self) { group in
                group.addTask {
                    try await Self.read(prepared, session: session, delegate: RedirectRefusal(), maximumBodyBytes: maximumBodyBytes)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw ConfirmEnrichmentTransportError.timedOut
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw ConfirmEnrichmentTransportError.failed }
                return first
            }
        } catch let error as ConfirmEnrichmentTransportError {
            if error != .timedOut, Task.isCancelled { throw ConfirmEnrichmentTransportError.cancelled }
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    static func read(_ request: URLRequest, session: URLSession, delegate: RedirectRefusal,
                     maximumBodyBytes: Int) async throws -> ConfirmEnrichmentHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse else { throw ConfirmEnrichmentTransportError.failed }
        // A refused redirect arrives as the 3xx itself: never followed, and not an answer.
        if (300..<400).contains(http.statusCode) { throw ConfirmEnrichmentTransportError.failed }
        var body = Data()
        body.reserveCapacity(min(maximumBodyBytes, 64 * 1024))
        for try await byte in bytes {
            if body.count >= maximumBodyBytes {
                bytes.task.cancel()
                return ConfirmEnrichmentHTTPResponse(status: http.statusCode, headers: Self.headers(http), body: body, exceededLimit: true)
            }
            body.append(byte)
        }
        return ConfirmEnrichmentHTTPResponse(status: http.statusCode, headers: Self.headers(http), body: body, exceededLimit: false)
    }

    static func headers(_ response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        return headers
    }

    static func map(_ error: any Error) -> ConfirmEnrichmentTransportError {
        if Task.isCancelled || error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .failed }
        switch urlError.code {
        case .timedOut: return .timedOut
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: return .offline
        default: return .failed
        }
    }

    /// Refuses every redirect: the response is the redirect itself, which `read` rejects.
    final class RedirectRefusal: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            nil
        }
    }
}
