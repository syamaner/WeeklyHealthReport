import FoodLedgerApplication
import Foundation

// The HTTP shapes the Confirm enrichment adapters and route checker hand to the one transport
// (docs/confirm-enrichment-openrouter-v1-phase.md section 3.1). Infrastructure only: none of these
// types crosses an application port.

/// One request: method, address, headers and body, sent exactly as given.
public struct ConfirmEnrichmentHTTPRequest: Equatable, Sendable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?

    public init(method: String, url: URL, headers: [String: String], body: Data?) {
        self.method = method; self.url = url; self.headers = headers; self.body = body
    }
}

/// One reply, read up to a byte limit.
public struct ConfirmEnrichmentHTTPResponse: Equatable, Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    /// The reply passed the byte limit; reading stopped there.
    public let exceededLimit: Bool

    public init(status: Int, headers: [String: String], body: Data, exceededLimit: Bool) {
        self.status = status; self.headers = headers; self.body = body; self.exceededLimit = exceededLimit
    }

    /// A header by name, ignoring case.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public enum ConfirmEnrichmentTransportError: Error, Equatable, Sendable {
    case offline, timedOut, cancelled, failed
}

/// The transport the adapters and checker use; `ConfirmEnrichmentTransport` is the live one.
public protocol ConfirmEnrichmentHTTPTransporting: Sendable {
    func send(_ request: ConfirmEnrichmentHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws
        -> ConfirmEnrichmentHTTPResponse
}
