import CryptoKit
import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

public enum OFFLookupError: Error, Equatable {
    case unsupportedCode, unavailable, rateLimited, oversizedResponse, malformedResponse, codeMismatch
}

public struct OFFProductResponse: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) { self.status = status; self.body = body }
}

/// An adapter-owned seam: no URLSession/HTTP types cross into the application port.
public protocol OFFProductTransport: Sendable {
    func product(code: String) async throws -> OFFProductResponse
}

public actor OFFHTTPSProductTransport: OFFProductTransport {
    public static let maximumBytes = 500_000
    private let session: URLSession
    private let clock: any LedgerClock
    private var lastAttempt: Date?
    private let userAgent: String

    public init(userAgent: String, clock: any LedgerClock = SystemLedgerClock(), configuration supplied: URLSessionConfiguration = .ephemeral) {
        self.userAgent = userAgent; self.clock = clock
        let configuration = supplied.copy() as! URLSessionConfiguration
        configuration.httpAdditionalHeaders = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration, delegate: OFFNoRedirects(), delegateQueue: nil)
    }

    public func product(code: String) async throws -> OFFProductResponse {
        guard code.allSatisfy({ $0 >= "0" && $0 <= "9" }), [8, 13].contains(code.count) else { throw OFFLookupError.unsupportedCode }
        try Task.checkCancellation()
        let now = clock.now()
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < 13 { throw OFFLookupError.rateLimited }
        lastAttempt = now // Reserve before suspension; concurrent taps cannot bypass the limit.
        let url = URL(string: "https://world.openfoodfacts.org/api/v3.6/product/\(code).json")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.url == url else { throw OFFLookupError.unavailable }
        guard response.expectedContentLength <= Self.maximumBytes else { throw OFFLookupError.oversizedResponse }
        var body = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard body.count < Self.maximumBytes else { throw OFFLookupError.oversizedResponse }
            body.append(byte)
        }
        return OFFProductResponse(status: response.statusCode, body: body)
    }
}

private final class OFFNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// v2 supports one explicit packaging input set, or legacy fields, for per-100-g mass records only. Ambiguous/liquid basis is declined.
public struct OpenFoodFactsLookup: PackagedFoodCandidateLookingUp {
    private let transport: any OFFProductTransport
    private let clock: any LedgerClock
    public init(transport: any OFFProductTransport, clock: any LedgerClock = SystemLedgerClock()) {
        self.transport = transport; self.clock = clock
    }

    public func lookup(_ request: PackagedFoodLookupRequest) async throws -> PackagedFoodLookupOutcome {
        try Task.checkCancellation()
        guard case let .gtin(gtin) = request.identity, gtin.value.count == 14, gtin.value.first == "0",
              try BarcodeClassifier.classify(code: LedgerText(String(gtin.value.dropFirst())), symbology: .ean13) == request.identity else {
            throw OFFLookupError.unsupportedCode
        }
        let code = gtin.value.hasPrefix("000000") ? String(gtin.value.suffix(8)) : String(gtin.value.suffix(13))
        let response = try await transport.product(code: code)
        try Task.checkCancellation()
        guard response.body.count <= OFFHTTPSProductTransport.maximumBytes else { throw OFFLookupError.oversizedResponse }
        if response.status == 429 { throw OFFLookupError.rateLimited }
        guard [200, 404].contains(response.status) else { throw OFFLookupError.unavailable }
        guard let document = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let status = document["status"] as? String else { throw OFFLookupError.malformedResponse }
        if status == "failure", (document["result"] as? [String: Any])?["id"] as? String == "product_not_found" { return .notFound }
        guard response.status == 200 else { throw OFFLookupError.unavailable }
        let normalizationOnly = status == "success_with_warnings"
            && (document["warnings"] as? [[String: Any]]).map { warnings in
                !warnings.isEmpty && warnings.allSatisfy {
                    ($0["message"] as? [String: Any])?["id"] as? String == "different_normalized_product_code"
                        && ($0["impact"] as? [String: Any])?["id"] as? String == "none"
                }
            } == true
        guard status == "success" || normalizationOnly, let product = document["product"] as? [String: Any], let returned = product["code"] as? String,
              [8, 12, 13, 14].contains(returned.count), returned.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { throw OFFLookupError.malformedResponse }
        guard String(repeating: "0", count: 14 - returned.count) + returned == gtin.value else { throw OFFLookupError.codeMismatch }
        return try OpenFoodFactsProductMapping.project(product: product, artifact: response.body, gtin: gtin,
            evidence: request.evidence, retrievedAt: clock.now())
    }
}
