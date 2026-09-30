import CoreFoundation
import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// One submitted OFF stage: discovery followed by at most two detail reads.
/// Only detail records cross the existing product-admission boundary.
public actor OFFHTTPSearchTransport: OFFSearchTransport {
    public static let version = "off-search-detail-transport-v4"
    public static let maximumBytes = 500_000
    public static let productLimit = 10
    public static let detailLimit = 2
    public static let requestInterval: TimeInterval = 7
    public static let stageDeadline: Duration = .seconds(20)
    private let session: URLSession
    private let clock: any LedgerClock
    private let userAgent: String
    private let pause: @Sendable (TimeInterval) async throws -> Void
    private let timeout: Duration
    private var lastAttempt: Date?
    private var active = false

    public init(userAgent: String, clock: any LedgerClock = SystemLedgerClock(),
                configuration supplied: URLSessionConfiguration = .ephemeral,
                timeout: Duration = OFFHTTPSearchTransport.stageDeadline,
                pause: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.userAgent = userAgent
        self.clock = clock
        self.pause = pause
        // Consumers may shorten, but cannot enlarge, the closed stage deadline.
        self.timeout = min(max(timeout, .milliseconds(1)), Self.stageDeadline)
        let configuration = supplied.copy() as! URLSessionConfiguration
        configuration.httpAdditionalHeaders = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration, delegate: OFFSearchNoRedirects(), delegateQueue: nil)
    }

    public func search(foodTerms: String) async throws -> OFFProductResponse {
        let query = try FoodSearchRemoteQuery(foodTerms: foodTerms)
        try Task.checkCancellation()
        guard !active else { throw FoodSearchEnrichmentError.quotaExceeded }
        if let lastAttempt, clock.now().timeIntervalSince(lastAttempt) < Self.requestInterval {
            throw FoodSearchEnrichmentError.quotaExceeded
        }
        active = true
        defer { active = false }
        let timeout = timeout
        return try await withThrowingTaskGroup(of: OFFProductResponse.self) { group in
            group.addTask { try await self.retrieve(query.foodTerms) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            let response = try await group.next()!
            try Task.checkCancellation()
            return response
        }
    }

    private func retrieve(_ terms: String) async throws -> OFFProductResponse {
        var request = URLRequest(url: URL(string: "https://search.openfoodfacts.org/search")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The deployed OFF server treats unfielded quoted phrases as filters on
        // a literal "*" field. Use full-text words, neutralising query syntax.
        // Lowercase reserved AND/OR/NOT/TO so food terms cannot become operators.
        let literalQuery = terms.lowercased().split(whereSeparator: \.isWhitespace).map { term in
            term.reduce(into: "") { result, character in
                if #"+-&|!(){}[]^\"~*?:\/<>'"#.contains(character) { result.append("\\") }
                result.append(character)
            }
        }.joined(separator: " ")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["q": literalQuery, "langs": ["en"], "page_size": Self.productLimit, "page": 1], options: [.sortedKeys])
        let search = try await send(request, paced: false)
        guard search.status == 200 else { return search }
        guard let envelope = try JSONSerialization.jsonObject(with: search.body) as? [String: Any],
              let timedOut = envelope["timed_out"] as? NSNumber,
              CFGetTypeID(timedOut) == CFBooleanGetTypeID(), !timedOut.boolValue,
              envelope["errors"] == nil || (envelope["errors"] as? [Any])?.isEmpty == true,
              let hits = envelope["hits"] as? [[String: Any]], hits.count <= Self.productLimit else {
            throw FoodSearchEnrichmentError.invalidResponse
        }
        var selected: [(code: String, identity: BarcodeIdentity)] = []
        for hit in Self.prioritisedHits(hits, terms: terms) {
            guard let code = hit["code"] as? String, let identity = OpenFoodFactsSearch.identity(code),
                  !selected.contains(where: { $0.identity == identity }) else { continue }
            selected.append((code, identity))
            if selected.count == Self.detailLimit { break }
        }
        var products: [[String: Any]] = []
        for selection in selected {
            try Task.checkCancellation()
            var url = URLComponents(string: "https://world.openfoodfacts.org/api/v3.6/product/\(selection.code).json")!
            url.queryItems = [URLQueryItem(name: "fields", value: "code,product_name,brands,quantity,categories_tags,nutrition,nutrition_data_per,nutriments")]
            let response = try await send(URLRequest(url: url.url!), paced: true)
            guard response.status == 200 || response.status == 404 else { return response }
            guard let detail = try JSONSerialization.jsonObject(with: response.body) as? [String: Any] else { throw FoodSearchEnrichmentError.invalidResponse }
            if response.status == 404, detail["status"] as? String == "failure",
               (detail["result"] as? [String: Any])?["id"] as? String == "product_not_found" { continue }
            let normalisationOnly = detail["status"] as? String == "success_with_warnings"
                && (detail["warnings"] as? [[String: Any]]).map { warnings in
                    !warnings.isEmpty && warnings.allSatisfy {
                        ($0["message"] as? [String: Any])?["id"] as? String == "different_normalized_product_code"
                            && ($0["impact"] as? [String: Any])?["id"] as? String == "none"
                    }
                } == true
            guard response.status == 200, detail["status"] as? String == "success" || normalisationOnly,
                  let product = detail["product"] as? [String: Any], let code = product["code"] as? String,
                  OpenFoodFactsSearch.identity(code) == selection.identity else { throw FoodSearchEnrichmentError.invalidResponse }
            products.append(product)
        }
        try Task.checkCancellation()
        let body = try JSONSerialization.data(withJSONObject: ["products": products], options: [.sortedKeys])
        guard body.count <= Self.maximumBytes else { throw FoodSearchEnrichmentError.invalidResponse }
        return .init(status: 200, body: body)
    }

    /// Discovery ordering only. Index names can earn an earlier detail read, never
    /// establish identity or nutrition. Unproven hits keep their provider order.
    private static func prioritisedHits(_ hits: [[String: Any]], terms: String) -> [[String: Any]] {
        let query = FoodQueryParser.parse(terms)
        guard query.allowsCandidateDiscovery,
              let percentage = query.attributes["unspecified_percent"] ?? query.attributes["fat_percent"] else { return hits }
        // Retain every other literal descriptor, including brand, flavour and preparation.
        let withoutPercentage = terms.replacingOccurrences(
            of: #"(-?\d+(?:\.\d+)?)\s*(?:%|percent)"#, with: " ", options: [.regularExpression, .caseInsensitive])
        let required = GenericFoodSearchTerms.tokens(withoutPercentage)
        guard !required.isEmpty else { return hits }
        func isExplicitMatch(_ hit: [String: Any]) -> Bool {
            guard let name = hit["product_name"] as? String else { return false }
            let named = FoodQueryParser.parse(name)
            guard named.allowsCandidateDiscovery,
                  (named.attributes["unspecified_percent"] ?? named.attributes["fat_percent"]) == percentage else { return false }
            let brands = (hit["brands"] as? [String])?.joined(separator: " ") ?? (hit["brands"] as? String ?? "")
            return required.isSubset(of: GenericFoodSearchTerms.tokens(name + " " + brands))
        }
        return hits.enumerated().map { (offset: $0.offset, hit: $0.element, explicit: isExplicitMatch($0.element)) }
            .sorted { lhs, rhs in
                if lhs.explicit != rhs.explicit { return lhs.explicit }
                return lhs.offset < rhs.offset
            }.map(\.hit)
    }

    private func send(_ original: URLRequest, paced: Bool) async throws -> OFFProductResponse {
        try Task.checkCancellation()
        if paced, let lastAttempt {
            let remaining = Self.requestInterval - clock.now().timeIntervalSince(lastAttempt)
            if remaining > 0 { try await pause(remaining) }
        }
        try Task.checkCancellation()
        lastAttempt = clock.now() // Failed/cancelled requests also consume the shared budget.
        var request = original
        request.httpMethod = request.httpMethod ?? "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.url == request.url else { throw FoodSearchEnrichmentError.unavailable }
        guard response.expectedContentLength <= Self.maximumBytes else { throw FoodSearchEnrichmentError.invalidResponse }
        var body = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard body.count < Self.maximumBytes else { throw FoodSearchEnrichmentError.invalidResponse }
            body.append(byte)
        }
        try Task.checkCancellation()
        return .init(status: response.statusCode, body: body)
    }
}

private final class OFFSearchNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
