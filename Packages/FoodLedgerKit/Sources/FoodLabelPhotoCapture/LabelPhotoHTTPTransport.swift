import Foundation

/// One HTTP exchange for the label photo route (docs/label-photo-ai-prefill-v1.md E1, E7, E12).
/// A protocol only: the live conformer (`OpenRouterTransport.swift`, the one file allowed to load
/// URLs) is wired in L5 with the egress records (E16). Until then tests use a fake.
public struct LabelPhotoHTTPRequest: Equatable, Sendable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?

    public init(method: String, url: URL, headers: [String: String], body: Data?) {
        self.method = method; self.url = url; self.headers = headers; self.body = body
    }
}

public struct LabelPhotoHTTPResponse: Equatable, Sendable {
    public let status: Int
    /// Header names as received; look them up with `header(_:)`, which ignores case.
    public let headers: [String: String]
    /// At most the requested maximum number of bytes.
    public let body: Data
    /// True when the reply was longer than the maximum and the transport stopped reading.
    public let exceededLimit: Bool

    public init(status: Int, headers: [String: String], body: Data, exceededLimit: Bool) {
        self.status = status; self.headers = headers; self.body = body; self.exceededLimit = exceededLimit
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public enum LabelPhotoTransportError: Error, Equatable, Sendable {
    /// The per-attempt timeout passed.
    case timedOut
    /// The task was cancelled; bytes may already have been sent.
    case cancelled
    /// The device has no network path.
    case offline
    /// Any other transport failure.
    case failed
}

/// Sends one request and reads at most `maximumBodyBytes` of the reply, within `timeout` seconds,
/// stopping at once when its task is cancelled. It never retries, follows no redirect to another
/// host and adds no header of its own beyond what HTTP requires.
public protocol LabelPhotoHTTPTransporting: Sendable {
    func send(_ request: LabelPhotoHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws -> LabelPhotoHTTPResponse
}
