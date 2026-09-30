import CryptoKit
import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// Closed HTTP acquisition boundary. Host admission belongs to composition, never model output.
/// The user-approved Gemini stage allows one source job with at most three physical attempts.
public actor HTTPSFoodSourcePageAcquirer: FoodSourcePageAcquiring {
    public static let version = "food-source-page-acquisition-v3"
    public static let maximumBytes = FoodSourceContentLimits.htmlBytes
    public static let maximumURLBytes = 4096
    public static let maximumRequests = 3
    public static let requestInterval: TimeInterval = 7
    public static let deadline: Duration = .seconds(20)
    private let urlPolicy: FoodSourceURLPolicy
    private let session: URLSession
    private let clock: any LedgerClock
    private let pause: @Sendable (TimeInterval) async throws -> Void
    private let userAgent: String
    private let timeout: Duration
    private var lastAttempt: Date?
    private var active = false

    public init(allowedHosts: Set<String>, userAgent: String,
                clock: any LedgerClock = SystemLedgerClock(),
                configuration supplied: URLSessionConfiguration = .ephemeral,
                timeout: Duration = HTTPSFoodSourcePageAcquirer.deadline,
                pause: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) throws {
        urlPolicy = try FoodSourceURLPolicy(allowedHosts: allowedHosts)
        self.userAgent = userAgent; self.clock = clock; self.pause = pause
        self.timeout = min(max(timeout, .milliseconds(1)), Self.deadline)
        let configuration = supplied.copy() as! URLSessionConfiguration
        configuration.httpAdditionalHeaders = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration, delegate: NoSourceRedirects(), delegateQueue: nil)
    }

    public func acquire(_ url: URL) async throws -> AcquiredFoodSourcePage {
        try Task.checkCancellation()
        let initialURL = try urlPolicy.canonicalURL(url)
        guard !active else { throw FoodSourceAcquisitionError.quotaExceeded }
        if let lastAttempt, clock.now().timeIntervalSince(lastAttempt) < Self.requestInterval {
            throw FoodSourceAcquisitionError.quotaExceeded
        }
        active = true
        defer { active = false }
        let timeout = timeout
        return try await withThrowingTaskGroup(of: AcquiredFoodSourcePage.self) { group in
            group.addTask { try await self.retrieve(initialURL, requestedURL: url) }
            group.addTask { try await Task.sleep(for: timeout); throw FoodSourceAcquisitionError.timedOut }
            defer { group.cancelAll() }
            let result = try await group.next()!
            try Task.checkCancellation()
            return result
        }
    }

    private func retrieve(_ initialURL: URL, requestedURL: URL) async throws -> AcquiredFoodSourcePage {
        var current = initialURL
        var hops: [AcquiredFoodSourcePage.Hop] = []
        for attempt in 0..<Self.maximumRequests {
            try Task.checkCancellation()
            current = try urlPolicy.canonicalURL(current)
            guard !hops.contains(where: { $0.url == current }) else { throw FoodSourceAcquisitionError.requestLimit }
            if attempt > 0, let lastAttempt {
                let remaining = Self.requestInterval - clock.now().timeIntervalSince(lastAttempt)
                if remaining > 0 { try await pause(remaining) }
            }
            try Task.checkCancellation()
            lastAttempt = clock.now()
            var request = URLRequest(url: current)
            request.httpMethod = "GET"
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let (bytes, reply) = try await session.bytes(for: request)
            guard let response = reply as? HTTPURLResponse, response.url == current else { throw FoodSourceAcquisitionError.invalidResponse }
            guard response.expectedContentLength <= Self.maximumBytes else { throw FoodSourceAcquisitionError.responseTooLarge }
            var body = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard body.count < Self.maximumBytes else { throw FoodSourceAcquisitionError.responseTooLarge }
                body.append(byte)
            }
            try Task.checkCancellation()
            hops.append(.init(url: current, status: response.statusCode))
            if [301, 302, 303, 307, 308].contains(response.statusCode) {
                guard let location = response.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: current)?.absoluteURL else { throw FoodSourceAcquisitionError.invalidResponse }
                current = try urlPolicy.canonicalURL(next)
                continue
            }
            guard response.statusCode == 200 else { throw FoodSourceAcquisitionError.unavailable }
            guard response.mimeType?.lowercased() == "text/html",
                  response.textEncodingName == nil || ["utf-8", "utf8"].contains(response.textEncodingName!.lowercased()),
                  !body.isEmpty, String(data: body, encoding: .utf8) != nil else { throw FoodSourceAcquisitionError.unsupportedContent }
            let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
            return AcquiredFoodSourcePage(requestedURL: requestedURL, finalURL: current, hops: hops,
                html: body, sha256: digest, retrievedAt: clock.now())
        }
        throw FoodSourceAcquisitionError.requestLimit
    }


}

private final class NoSourceRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
