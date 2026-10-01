import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// OFF-specific transport details stay inside the infrastructure target.
public protocol OFFSearchTransport: Sendable {
    func search(foodTerms: String) async throws -> OFFProductResponse
}

/// Whole OFF product alternatives, never cross-record nutrient augmentation.
public struct OpenFoodFactsSearch: FoodSearchEnriching {
    private let transport: any OFFSearchTransport
    private let clock: any LedgerClock
    private let ids: any LedgerIDGenerating
    private let locale: LedgerText

    public init(transport: any OFFSearchTransport, locale: LedgerText,
                clock: any LedgerClock = SystemLedgerClock(), ids: any LedgerIDGenerating = RandomLedgerIDGenerator()) {
        self.transport = transport
        self.locale = locale
        self.clock = clock
        self.ids = ids
    }

    public func enrich(_ query: FoodSearchRemoteQuery) async throws -> GenericFoodSearchOutcome {
        try Task.checkCancellation()
        let parsed = query.interpretation.parsedQuery
        guard query.interpretation.allowsDiscovery, let food = parsed.food else { throw FoodSearchEnrichmentError.invalidQuery }
        let terms = GenericFoodSearchTerms.tokens([parsed.attributes["brand"], FoodQueryPreparationPolicy.foodTerms(for: parsed)].compactMap { $0 }.joined(separator: " "))
        guard !terms.isEmpty else { throw FoodSearchEnrichmentError.invalidQuery }
        let response = try await transport.search(foodTerms: Self.retrievalText(parsed, food: food))
        try Task.checkCancellation()
        if response.status == 429 { throw FoodSearchEnrichmentError.quotaExceeded }
        guard response.status == 200 else { throw FoodSearchEnrichmentError.unavailable }
        guard response.body.count <= OFFHTTPSearchTransport.maximumBytes,
              let document = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let products = document["products"] as? [[String: Any]],
              products.count <= OFFHTTPSearchTransport.productLimit else { throw FoodSearchEnrichmentError.invalidResponse }
        let now = clock.now()
        let evidence = try CaptureEvidence(evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch,
            capturedAt: now, locale: locale, captureMethod: LedgerText("off_text_search"),
            captureMethodVersion: LedgerText("off-search-candidates-v6"), originalPayload: .text(LedgerText(query.foodTerms)))
        var result: GenericFoodSearchOutcome = .noResult(GenericFoodNoResultRoute(evidence: evidence))
        var seen: [String: Data] = [:]
        for product in products {
            try Task.checkCancellation()
            guard let code = product["code"] as? String,
                  let identity = Self.identity(code), case let .gtin(gtin) = identity else { continue }
            let artifact = try JSONSerialization.data(withJSONObject: product, options: [.sortedKeys])
            if let previous = seen[gtin.value] {
                guard previous == artifact else { throw FoodSearchEnrichmentError.invalidResponse }
                continue
            }
            seen[gtin.value] = artifact
            guard let name = product["product_name"] as? String,
                  GenericFoodSearchTerms.acceptsFoodForm(name: name, query: terms) else { continue }
            let candidateTerms = GenericFoodSearchTerms.tokens(name + " " + (product["brands"] as? String ?? ""))
            if let literal = parsed.attributes["unspecified_percent"] {
                let named = FoodQueryParser.parse(name)
                guard named.allowsCandidateDiscovery,
                      (named.attributes["unspecified_percent"] ?? named.attributes["fat_percent"]) == literal else { continue }
            }
            let missing = terms.subtracting(candidateTerms)
            var category: String?
            if !missing.isEmpty {
                let brand = GenericFoodSearchTerms.tokens(product["brands"] as? String ?? "")
                guard !brand.isEmpty, brand.isSubset(of: terms),
                      let tag = (product["categories_tags"] as? [String] ?? []).sorted().first(where: {
                          $0.hasPrefix("en:") && Set(missing.map(Self.categoryTerm)).isSubset(of: Set(GenericFoodSearchTerms.tokens(String($0.dropFirst(3))).map(Self.categoryTerm)))
                      }) else { continue }
                category = String(tag.dropFirst(3)).replacingOccurrences(of: "-", with: " ")
            }
            let score = Double(terms.intersection(candidateTerms).count) / Double(max(1, terms.union(candidateTerms).count))
            guard case let .candidate(input) = try OpenFoodFactsLookup.project(product: product,
                artifact: artifact, gtin: gtin, evidence: evidence, retrievedAt: now, searchScore: score,
                searchCategory: category) else { continue }
            let matches = input.candidates.map { GenericFoodMatch(candidate: $0,
                isExactName: GenericFoodSearchTerms.tokens(name) == GenericFoodSearchTerms.tokens(query.foodTerms)) }
            result = try FoodSearchResultMerger.merge(result, .confirmation(GenericFoodConfirmationRoute(confirmation: input, matches: matches)))
        }
        try Task.checkCancellation()
        return result
    }

    /// Intake mass/volume/count must never become a provider discovery keyword.
    /// Reattach parsed descriptors so removing quantity
    /// does not silently broaden a branded, prepared or fat-specific search.
    /// These are retrieval hints only; source identity and original evidence remain unchanged.
    private static func retrievalText(_ parsed: ParsedFoodQuery, food: String) -> String {
        var parts = [parsed.attributes["brand"], food].compactMap { $0 }
        for key in parsed.attributes.keys.sorted() where key != "brand" {
            guard let value = parsed.attributes[key] else { continue }
            let descriptor: String
            switch key {
            case "fat_percent": descriptor = "\(value)% fat"
            case "cocoa_percent": descriptor = "\(value)% cocoa"
            case "ingredient_percent", "unspecified_percent": descriptor = "\(value)%"
            case "lactose": descriptor = "lactose-\(value)"
            case "skin": descriptor = "\(value) skin"
            default: descriptor = value
            }
            if !parts.contains(descriptor) { parts.append(descriptor) }
        }
        return parts.joined(separator: " ")
    }

    /// Grammatical equivalence only; original source labels remain visible.
    private static func categoryTerm(_ term: String) -> String { term == "drinks" ? "drink" : term }

    static func identity(_ code: String) -> BarcodeIdentity? {
        guard [8, 12, 13, 14].contains(code.count), code.allSatisfy({ $0 >= "0" && $0 <= "9" }),
              let text = try? LedgerText(code) else { return nil }
        if code.count == 8 { return try? BarcodeClassifier.classify(code: text, symbology: .ean8) }
        // The existing identity contract admits consumer EAN/UPC codes, not case-level GTIN-14.
        guard code.count != 14 || code.first == "0" else { return nil }
        let ean = code.count == 12 ? "0" + code : code.count == 14 ? String(code.dropFirst()) : code
        return try? BarcodeClassifier.classify(code: LedgerText(ean), symbology: .ean13)
    }
}
