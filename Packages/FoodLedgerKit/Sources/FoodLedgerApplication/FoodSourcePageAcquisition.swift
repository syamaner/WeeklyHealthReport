import Foundation

/// Fetched source content, not a nutrition candidate or an identity assertion.
public struct AcquiredFoodSourcePage: Equatable, Sendable {
    public struct Hop: Equatable, Sendable {
        public let url: URL
        public let status: Int
        public init(url: URL, status: Int) { self.url = url; self.status = status }
    }
    public let requestedURL: URL
    public let finalURL: URL
    public let hops: [Hop]
    public let html: Data
    public let sha256: String
    public let retrievedAt: Date
    public init(requestedURL: URL, finalURL: URL, hops: [Hop], html: Data, sha256: String, retrievedAt: Date) {
        self.requestedURL = requestedURL; self.finalURL = finalURL; self.hops = hops
        self.html = html; self.sha256 = sha256; self.retrievedAt = retrievedAt
    }
}

/// Acquisition must be independent of model-generated excerpts or table projections.
public protocol FoodSourcePageAcquiring: Sendable {
    func acquire(_ url: URL) async throws -> AcquiredFoodSourcePage
}

public enum FoodSourceAcquisitionError: Error, Equatable, Sendable {
    case invalidURL, hostNotAdmitted, invalidResponse, unsupportedContent, responseTooLarge
    case unavailable, requestLimit, quotaExceeded, timedOut
}
