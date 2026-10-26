import FoodLedgerApplication
import Foundation

/// The live transport of the label photo route (docs/label-photo-ai-prefill-v1.md E1, E7, E12 and
/// the 17.18 L5 obligations). The one file allowed to load URLs. It:
///
/// - uses an ephemeral configuration with no cookie store, no URL cache and no credential storage;
/// - sends a fixed, neutral `User-Agent` and a fixed `Accept-Language: *` (URLSession always adds
///   the header, so the device's languages are never sent);
/// - refuses every redirect;
/// - streams the reply and stops reading past the byte cap, reporting `exceededLimit`;
/// - ends each request at the per-attempt timeout, as a whole, not per idle interval;
/// - maps a task cancellation, and only that, to `.cancelled`;
/// - serves the catalogue GETs with the same anonymous configuration (the checker adds no
///   Authorization header; the attempt adds it to its POST only).
public final class OpenRouterTransport: NSObject, LabelPhotoHTTPTransporting, URLSessionTaskDelegate, @unchecked Sendable {
    public static let userAgent = "WeeklyHealthReport-LabelPhoto/1"
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

    public func send(_ request: LabelPhotoHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws -> LabelPhotoHTTPResponse {
        guard timeout > 0 else { throw LabelPhotoTransportError.timedOut }
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = false
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let session = session
        let prepared = urlRequest
        do {
            return try await withThrowingTaskGroup(of: LabelPhotoHTTPResponse.self) { group in
                group.addTask {
                    try await Self.read(prepared, session: session, delegate: RedirectRefusal(), maximumBodyBytes: maximumBodyBytes)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw LabelPhotoTransportError.timedOut
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw LabelPhotoTransportError.failed }
                return first
            }
        } catch let error as LabelPhotoTransportError {
            if error != .timedOut, Task.isCancelled { throw LabelPhotoTransportError.cancelled }
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    static func read(_ request: URLRequest, session: URLSession, delegate: RedirectRefusal,
                     maximumBodyBytes: Int) async throws -> LabelPhotoHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse else { throw LabelPhotoTransportError.failed }
        // A refused redirect arrives as the 3xx itself: never followed, and not an answer.
        if (300..<400).contains(http.statusCode) { throw LabelPhotoTransportError.failed }
        var body = Data()
        body.reserveCapacity(min(maximumBodyBytes, 64 * 1024))
        for try await byte in bytes {
            if body.count >= maximumBodyBytes {
                bytes.task.cancel()
                return LabelPhotoHTTPResponse(status: http.statusCode, headers: Self.headers(http), body: body, exceededLimit: true)
            }
            body.append(byte)
        }
        return LabelPhotoHTTPResponse(status: http.statusCode, headers: Self.headers(http), body: body, exceededLimit: false)
    }

    static func headers(_ response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        return headers
    }

    /// Task cancellation is `.cancelled` only when the task was cancelled; URLSession's own
    /// cancellation (our deadline) is a timeout; no path is offline; anything else failed.
    static func map(_ error: any Error) -> LabelPhotoTransportError {
        if Task.isCancelled || error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .failed }
        switch urlError.code {
        case .timedOut: return .timedOut
        // Offline means no usable network path; a lost connection or a DNS failure happens with a
        // path present (a captive portal, for example) and is a connection failure.
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .offline
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
