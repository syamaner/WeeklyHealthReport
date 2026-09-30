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
        return try Self.project(product: product, artifact: response.body, gtin: gtin,
            evidence: request.evidence, retrievedAt: clock.now())
    }

    /// Shared closed admission rules for barcode and text-search records.
    /// Search callers pass the actual product JSON, never a fabricated scan response.
    static func project(product: [String: Any], artifact: Data, gtin: LedgerText,
                        evidence: CaptureEvidence, retrievedAt now: Date,
                        searchScore: Double? = nil, searchCategory: String? = nil) throws -> PackagedFoodLookupOutcome {
        guard let returned = product["code"] as? String else { throw OFFLookupError.malformedResponse }
        guard let name = product["product_name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .insufficientData }
        let pack = product["quantity"] as? String ?? ""
        let mass = pack.range(of: #"(?i)\d\s*(g|kg)\b"#, options: .regularExpression) != nil
        let volume = pack.range(of: #"(?i)\d\s*(ml|cl|dl|l)\b"#, options: .regularExpression) != nil
        guard mass != volume,
              !(product["categories_tags"] as? [String] ?? []).contains("en:dietary-supplements"),
              let sourceSet = Self.sourceNutrients(product, volume: volume) else { return .insufficientData }
        let basis: ResolutionBasis = volume ? .per100Millilitres : .per100Grams
        let nutrients = sourceSet.values
        let hash = SHA256.hash(data: artifact).map { String(format: "%02x", $0) }.joined()
        let projectionVersion = "off-product-projection-v4"
        let schemaVersion = searchScore == nil ? "off-v3.6-explicit-basis-candidates-v4" : "off-search-explicit-basis-candidates-v5"
        let releaseID = try ExternalIdentifier("off:snapshot:sha256:\(hash):projection:\(projectionVersion):schema:\(schemaVersion):retrieved:\(now.timeIntervalSince1970)")
        let productURL = "https://world.openfoodfacts.org/product/\(returned)"
        let release = try SourceRelease(sourceReleaseID: releaseID, sourceID: ExternalIdentifier("open-food-facts"),
            releasedAt: now, artifactHash: SHA256Digest(hash), schemaVersion: LedgerText(schemaVersion),
            pipelineVersion: LedgerText(projectionVersion),
            licence: LedgerText("ODbL 1.0 https://opendatacommons.org/licenses/odbl/1-0/; contents: https://opendatacommons.org/licenses/dbcl/1-0/"),
            attribution: LedgerText("Open Food Facts · \(productURL) · Retrieved \(ISO8601DateFormatter().string(from: now))"), manifestHash: SHA256Digest(hash))
        let fields: [NutrientKey: String] = [.energyConsumed: "energy-kcal", .protein: "proteins", .carbohydrates: "carbohydrates",
            .fatTotal: "fat", .fatSaturated: "saturated-fat", .fiber: "fiber", .sugar: "sugars", .sodium: "sodium"]
        var available = 0
        let entries = try NutrientKey.allCases.map { key -> NutrientEntry in
            // Legacy sodium _100g is normalised independently of the contributor unit.
            guard key != .sodium || sourceSet.isModern,
                  let field = fields[key], let number = nutrients[field + "_100g"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, number.doubleValue >= 0 else {
                return try NutrientEntry(key: key, value: .unknown(.notDeclared))
            }
            guard let sourceUnit = nutrients[field + "_unit"] as? String else {
                return try NutrientEntry(key: key, value: .unknown(.missingConversion))
            }
            let convertsGrams = key == .sodium && sourceUnit == "g"
            guard sourceUnit == key.canonicalUnit.rawValue || convertsGrams else {
                return try NutrientEntry(key: key, value: .unknown(.missingConversion))
            }
            let rawModifier = nutrients[field + "_modifier"]
            guard rawModifier == nil || rawModifier is String else {
                return try NutrientEntry(key: key, value: .unknown(.noCompatibleSource))
            }
            let modifier = rawModifier as? String ?? ""
            guard ["", "<", "<=", ">", ">="].contains(modifier) else {
                return try NutrientEntry(key: key, value: .unknown(.noCompatibleSource))
            }
            let sourceAmount = number.doubleValue
            let amount = sourceAmount * (convertsGrams ? 1_000 : 1)
            guard amount.isFinite else { return try NutrientEntry(key: key, value: .unknown(.missingConversion)) }
            available += 1
            let unit = try LedgerText(sourceUnit)
            let transforms = convertsGrams ? [try NutrientTransform(transformID: LedgerText("mass-g-to-mg"), transformVersion: LedgerText("v1"))] : []
            let source = try SourceExactNutrientValue(amount: sourceAmount, unit: unit, basis: basis)
            let provenance = try NutrientProvenance(sourceKind: .exactProductDataset, sourceID: ExternalIdentifier("open-food-facts"),
                sourceReleaseID: releaseID, recordID: ExternalIdentifier("off:gtin:\(gtin.value)"), manifestReference: LedgerText("\(productURL)#\(sourceSet.path)/\(sourceSet.path == "nutriments" ? field + "_100g" : field)"), transforms: transforms)
            if !modifier.isEmpty {
                let upper = modifier.hasPrefix("<") ? amount : nil
                let lower = modifier.hasPrefix(">") ? amount : nil
                let closed = modifier.hasSuffix("=")
                let bound = try SourceBoundedNutrientValue(lower: lower == nil ? nil : sourceAmount, upper: upper == nil ? nil : sourceAmount,
                    lowerClosed: lower != nil && closed, upperClosed: upper != nil && closed,
                    unit: unit, basis: basis)
                return try NutrientEntry(key: key, value: .bounded(NutrientBounds(lower: lower, upper: upper,
                    lowerClosed: bound.lowerClosed, upperClosed: bound.upperClosed, origin: .augmented,
                    unit: key.canonicalUnit, sourceValue: .bounded(bound), provenance: [provenance])))
            }
            return try NutrientEntry(key: key, value: .augmented(ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(source), provenance: [provenance])))
        }
        guard available > 0 else { return .insufficientData }
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown, skin: .unknown,
            drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: basis)
        let quantity = try EdibleQuantityIdentity.known(PositiveQuantity(value: 100, unit: volume ? .millilitres : .grams), conversionVersionID: nil)
        let metadata = try CandidateMatchMetadata(methodVersion: LedgerText(searchScore == nil ? "off-product-candidates-v4" : "off-search-candidates-v5"), score: searchScore ?? 1,
            materialDifferences: [LedgerText("Community product data; check name, package and nutrition basis. Missing values remain unknown.")],
            libraryAliases: searchScore == nil ? [try BarcodeIdentity.gtin(gtin).lookupAlias] : [])
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: releaseID,
            recordID: ExternalIdentifier("off:gtin:\(gtin.value)"), identity: identity, edibleQuantity: quantity,
            nutrients: NutrientSet(entries: entries), evidenceIDs: [evidence.evidenceID], matchMetadata: metadata),
            name: LedgerText(name), brand: (product["brands"] as? String).flatMap { try? LedgerText($0) },
            variant: LedgerText("Open Food Facts · source estimate · \(pack) · per 100 \(volume ? "ml" : "g")" + (searchCategory.map { "; source category: \($0). Review this type against your request." } ?? "")), barcode: gtin, itemClass: .food, packFacts: PackFacts())
        return .candidate(try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: identity, expectedEdibleQuantity: quantity))
    }
    // Choose one source input set. OFF's aggregate may mix packaging, estimates and
    // preparations, so it is never used to backfill this candidate.
    private static func sourceNutrients(_ product: [String: Any], volume: Bool) -> (values: [String: Any], path: String, isModern: Bool)? {
        if product["nutrition"] != nil {
            guard let nutrition = product["nutrition"] as? [String: Any], let sets = nutrition["input_sets"] as? [[String: Any]] else { return nil }
            let eligible = sets.enumerated().filter {
                $0.element["source"] as? String == "packaging" && $0.element["per"] as? String == (volume ? "100ml" : "100g")
                    && $0.element["preparation"] as? String == "as_sold"
            }
            guard eligible.count == 1, let values = eligible[0].element["nutrients"] as? [String: Any] else { return nil }
            let panel = eligible[0].element
            if let quantity = panel["per_quantity"] {
                guard let number = quantity as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == 100 else { return nil }
            }
            if let unit = panel["per_unit"] {
                guard unit as? String == (volume ? "ml" : "g") else { return nil }
            }
            var result: [String: Any] = [:]
            for (field, raw) in values {
                guard let value = raw as? [String: Any] else { continue }
                result[field + "_100g"] = value["value"]
                result[field + "_unit"] = value["unit"]
                result[field + "_modifier"] = value["modifier"]
            }
            return (result, "nutrition/input_sets/\(eligible[0].offset)/nutrients", true)
        }
        guard !volume else { return nil } // Legacy *_100g does not distinguish mass from volume.
        guard product["nutrition_data_per"] as? String == "100g" else { return nil }
        guard let values = product["nutriments"] as? [String: Any] else { return nil }
        return (values, "nutriments", false)
    }

}
