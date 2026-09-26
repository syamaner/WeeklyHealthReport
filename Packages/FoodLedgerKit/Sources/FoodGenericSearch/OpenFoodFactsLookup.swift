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

/// v1 supports explicitly declared per-100-g mass records only. Ambiguous/liquid basis is declined.
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
        guard response.status == 200 else { throw OFFLookupError.unavailable }
        guard let document = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let status = document["status"] as? String else { throw OFFLookupError.malformedResponse }
        if status == "failure", (document["result"] as? [String: Any])?["id"] as? String == "product_not_found" { return .notFound }
        guard status == "success", let product = document["product"] as? [String: Any], let returned = product["code"] as? String,
              [8, 12, 13, 14].contains(returned.count), returned.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { throw OFFLookupError.malformedResponse }
        guard String(repeating: "0", count: 14 - returned.count) + returned == gtin.value else { throw OFFLookupError.codeMismatch }
        guard let name = product["product_name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              product["nutrition_data_per"] as? String == "100g",
              let nutrients = product["nutriments"] as? [String: Any] else { return .insufficientData }
        let pack = product["quantity"] as? String ?? ""
        // OFF uses *_100g for mass or volume. Never turn a liquid declaration into mass.
        guard pack.range(of: #"(?i)\d\s*(g|kg)\b"#, options: .regularExpression) != nil,
              pack.range(of: #"(?i)\d\s*(ml|cl|dl|l)\b"#, options: .regularExpression) == nil,
              !(product["categories_tags"] as? [String] ?? []).contains("en:dietary-supplements") else { return .insufficientData }
        let now = clock.now()
        let hash = SHA256.hash(data: response.body).map { String(format: "%02x", $0) }.joined()
        let releaseID = try ExternalIdentifier("off:snapshot:sha256:\(hash):retrieved:\(now.timeIntervalSince1970)")
        let productURL = "https://world.openfoodfacts.org/product/\(returned)"
        let release = try SourceRelease(sourceReleaseID: releaseID, sourceID: ExternalIdentifier("open-food-facts"),
            releasedAt: now, artifactHash: SHA256Digest(hash), schemaVersion: LedgerText("off-v3.6-mass-candidates-v1"),
            pipelineVersion: LedgerText("off-product-projection-v1"),
            licence: LedgerText("ODbL 1.0 https://opendatacommons.org/licenses/odbl/1-0/; contents: https://opendatacommons.org/licenses/dbcl/1-0/"),
            attribution: LedgerText("Open Food Facts · \(productURL) · Retrieved \(ISO8601DateFormatter().string(from: now))"), manifestHash: SHA256Digest(hash))
        let fields: [NutrientKey: String] = [.energyConsumed: "energy-kcal", .protein: "proteins", .carbohydrates: "carbohydrates",
            .fatTotal: "fat", .fatSaturated: "saturated-fat", .fiber: "fiber", .sugar: "sugars"]
        var available = 0
        let entries = try NutrientKey.allCases.map { key -> NutrientEntry in
            guard let field = fields[key], let number = nutrients[field + "_100g"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, number.doubleValue >= 0 else {
                return try NutrientEntry(key: key, value: .unknown(.notDeclared))
            }
            guard nutrients[field + "_unit"] as? String == key.canonicalUnit.rawValue else {
                return try NutrientEntry(key: key, value: .unknown(.missingConversion))
            }
            available += 1
            let amount = number.doubleValue
            let source = try SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)
            let provenance = try NutrientProvenance(sourceKind: .exactProductDataset, sourceID: ExternalIdentifier("open-food-facts"),
                sourceReleaseID: releaseID, recordID: ExternalIdentifier("off:gtin:\(gtin.value)"), manifestReference: LedgerText("\(productURL)#\(field)_100g"))
            return try NutrientEntry(key: key, value: .augmented(ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(source), provenance: [provenance])))
        }
        guard available > 0 else { return .insufficientData }
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown, skin: .unknown,
            drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams)
        let quantity = try EdibleQuantityIdentity.known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil)
        let metadata = try CandidateMatchMetadata(methodVersion: LedgerText("off-product-candidates-v1"), score: 1,
            materialDifferences: [LedgerText("Community product data; check name, package and nutrition basis. Missing values remain unknown.")],
            libraryAliases: [request.identity.lookupAlias])
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: releaseID,
            recordID: ExternalIdentifier("off:gtin:\(gtin.value)"), identity: identity, edibleQuantity: quantity,
            nutrients: NutrientSet(entries: entries), evidenceIDs: [request.evidence.evidenceID], matchMetadata: metadata),
            name: LedgerText(name), brand: (product["brands"] as? String).flatMap { try? LedgerText($0) },
            variant: LedgerText("Open Food Facts · source estimate · \(pack) · per 100 g"), barcode: gtin, itemClass: .food, packFacts: PackFacts())
        return .candidate(try PopulatedFoodConfirmation(evidence: [request.evidence], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: identity, expectedEdibleQuantity: quantity))
    }
}
