import FoodConfirmEnrichment
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// Request goldens per route (docs/confirm-enrichment-openrouter-v1.md section 7 and test 2; phase gate
/// sections 3.2 and 7): the exact A and B body bytes for synthetic foods, built through
/// `ConfirmEnrichmentPolicy` with the `ConfirmEnrichmentRoutes` constants, under
/// docs/fixtures/confirm-enrichment-v1/requests/. Set CE1_REGENERATE_GOLDENS=1 to rewrite them.
final class ConfirmEnrichmentRequestGoldenTests: XCTestCase {
    enum Case: String, CaseIterable {
        case cofid, usda, tfda, ciqual
        case openFoodFactsSearch = "open-food-facts-search"
        case openFoodFactsBarcode = "open-food-facts-barcode"
        case yourFoodDatabase = "your-food-database"

        var route: ConfirmEnrichmentPolicy.SourceRoute {
            switch self {
            case .cofid: .compositionTable(sendsVariant: true)
            case .usda, .tfda, .ciqual: .compositionTable(sendsVariant: false)
            case .openFoodFactsSearch, .openFoodFactsBarcode: .openFoodFacts
            case .yourFoodDatabase: .yourFoodDatabase
            }
        }

        /// Only Open Food Facts and Your food database raise missing food details (CE1 section 2).
        var asksDetails: Bool { route == .openFoodFacts || route == .yourFoodDatabase }

        /// Synthetic name, brand and the variant text each source carries.
        var names: (name: String, brand: String?, variant: String?) {
            switch self {
            case .cofid: ("Synthetic oats, rolled, raw", nil, "Synthetic CoFID variant text")
            case .usda: ("Synthetic beans, kidney, canned", nil, "USDA · per 100 g")
            case .tfda: ("Synthetic tofu, firm", nil, "TFDA · per 100 g")
            case .ciqual: ("Synthetic lentils, green, boiled", nil, "Ciqual · per 100 g")
            case .openFoodFactsSearch: ("Synthetic oat crunch cereal", "Example Mills", "Open Food Facts · per 100 g")
            case .openFoodFactsBarcode: ("Synthetic tomato soup", "Example Kitchen", "Open Food Facts · per 100 ml")
            case .yourFoodDatabase: ("Synthetic Greek style yoghurt 500g", "Example Dairy", nil)
            }
        }

        var basis: ConfirmNutrientBasis { self == .openFoodFactsBarcode ? .per100Millilitres : .per100Grams }

        var phrase: String {
            switch route {
            case .openFoodFacts: "from the product's Open Food Facts record"
            case .yourFoodDatabase: "from your food database"
            case .compositionTable: "from a food composition table"
            }
        }
    }

    static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/fixtures/confirm-enrichment-v1/requests", isDirectory: true)
    }

    static func description(_ golden: Case) throws -> ConfirmEnrichmentDescription {
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown, skin: .unknown,
                                            drained: .unknown, packingMedium: .unknown, fortification: .unknown,
                                            servingBasis: golden.basis == .per100Grams ? .per100Grams : .per100Millilitres)
        let candidate = try PopulatedFoodCandidate(
            candidate: ProviderNeutralCandidate(sourceReleaseID: ExternalIdentifier("synthetic:release"), recordID: ExternalIdentifier("synthetic:1"),
                                                identity: identity, edibleQuantity: .unknown,
                                                nutrients: NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: .unknown(.notDeclared)) }),
                                                evidenceIDs: []),
            name: LedgerText(golden.names.name), brand: golden.names.brand.map { try LedgerText($0) },
            variant: golden.names.variant.map { try LedgerText($0) }, itemClass: .food)
        let database = golden == .yourFoodDatabase
            ? PersonalFoodDescriptionFields(category: "dairy", productType: "packaged_single_ingredient", state: nil, hasCatalogueFacts: false)
            : nil
        return ConfirmEnrichmentPolicy.description(golden.route, candidate: candidate, database: database)
    }

    static func detailsRequest(_ golden: Case) throws -> ConfirmEnrichmentPolicy.DetailsRequest {
        let known: [String: String] = golden == .yourFoodDatabase ? ["fortification": "unfortified"] : [:]
        let asked: [ConfirmDetailsFact] = golden == .yourFoodDatabase
            ? [.preparation, .bone, .skin, .drained, .packingMedium] : [.preparation, .bone, .skin, .drained, .packingMedium, .fortification]
        let inputs = try ConfirmDetailsRequestInputs(description: description(golden), knownDetails: known, asked: asked)
        return try ConfirmEnrichmentPolicy.detailsRequest(inputs, route: ConfirmEnrichmentRoutes.details,
                                                          encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
    }

    static func nutrientRequest(_ golden: Case) throws -> ConfirmEnrichmentPolicy.NutrientRequest {
        let known: [ConfirmNutrientRequestInputs.Known] = [
            try .init(nutrient: .energyConsumed, value: golden.basis == .per100Grams ? 380 : 45, source: golden.phrase),
            try .init(nutrient: .protein, value: 9.5, source: golden.phrase),
            try .init(nutrient: .carbohydrates, value: golden.basis == .per100Grams ? 62 : 7.1, source: golden.phrase),
            try .init(nutrient: .fatTotal, value: 6.4, source: golden.phrase),
        ]
        let identity = golden.asksDetails ? ["preparation": "as_sold", "fortification": "unfortified"] : [:]
        let inputs = try ConfirmNutrientRequestInputs(description: description(golden), identity: identity, basis: golden.basis,
                                                      known: known, eligible: [.fiber, .sodium, .sugar, .fatSaturated])
        return try ConfirmEnrichmentPolicy.nutrientRequest(inputs, route: ConfirmEnrichmentRoutes.nutrients,
                                                           encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
    }

    /// Every measured key either known or eligible: the split with the largest body is the worst case.
    static func worstCaseRequests() throws -> [ConfirmEnrichmentPolicy.NutrientRequest] {
        let keys = NutrientKey.allCases.filter { !ConfirmNutrientRequestInputs.unmeasuredKeys.contains($0) }
        // A long but ordinary receipt title. A much longer name with every food detail known passes the
        // ceiling and is refused before sending (gate section 2.6), so it is not the golden.
        let longName = "Synthetic long product title with pack size 500g"
        // Your food database sends the most fields; it never sends a variant (CE1 section 7).
        let description = ConfirmEnrichmentDescription(name: longName, brand: "Example Brand Name", variant: nil,
                                                       category: "ready_meal", productType: "packaged_composite", state: "cooked",
                                                       source: .yourFoodDatabase)
        return try (1...keys.count).map { eligibleCount in
            let eligible = Array(keys.prefix(eligibleCount))
            let known = try keys.dropFirst(eligibleCount).map {
                try ConfirmNutrientRequestInputs.Known(nutrient: $0, value: 123.456789, source: "estimated in your food database")
            }
            let inputs = try ConfirmNutrientRequestInputs(
                description: description,
                identity: ["preparation": "cooked", "bone": "not_applicable", "skin": "not_applicable", "drained": "not_applicable",
                           "packing_medium": "not applicable", "fortification": "unfortified"],
                basis: .per100Grams, known: known, eligible: eligible)
            // Built without the refusal, so the test can state the size; the assertion is the ceiling.
            return try ConfirmEnrichmentPolicy.nutrientRequest(inputs, route: unbounded, encoder: FoundationCanonicalJSONEncoder(),
                                                               digester: SHA256Digester())
        }
    }

    /// The nutrient route with no prompt ceiling: every other route value is the route version's.
    static var unbounded: ConfirmEnrichmentRoute {
        let route = ConfirmEnrichmentRoutes.nutrients
        return ConfirmEnrichmentRoute(part: route.part, version: route.version, model: route.model, acceptedModels: route.acceptedModels,
                                      provider: route.provider, providerEndpoint: route.providerEndpoint, endpoint: route.endpoint,
                                      promptCeilingTokens: .max, completionCeilingTokens: route.completionCeilingTokens,
                                      reasoningLimitTokens: route.reasoningLimitTokens,
                                      reasoningBilledSeparately: route.reasoningBilledSeparately, sendsMaxTokens: route.sendsMaxTokens)
    }

    func check(_ body: Data, named name: String) throws {
        let url = Self.fixtures.appendingPathComponent(name)
        if ProcessInfo.processInfo.environment["CE1_REGENERATE_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(at: Self.fixtures, withIntermediateDirectories: true)
            try body.write(to: url)
        }
        let golden = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), String(decoding: golden, as: UTF8.self), name)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("openrouter.ai"), "\(name) holds an address")
    }

    func testEachRouteMatchesItsGolden() throws {
        for golden in Case.allCases {
            if golden.asksDetails {
                let request = try Self.detailsRequest(golden)
                try check(request.body, named: "\(golden.rawValue)-details.json")
                XCTAssertEqual(ConfirmDetailsRequestInputs.decode(requestBody: String(decoding: request.body, as: UTF8.self)), request.inputs)
            }
            let request = try Self.nutrientRequest(golden)
            try check(request.body, named: "\(golden.rawValue)-nutrients.json")
            XCTAssertEqual(ConfirmNutrientRequestInputs.decode(requestBody: String(decoding: request.body, as: UTF8.self)), request.inputs)
        }
    }

    func testTheDescriptionSendsOnlyEachSourcesOwnFields() throws {
        XCTAssertEqual(try Self.description(.cofid).variant, "Synthetic CoFID variant text")
        for golden in [Case.usda, .tfda, .ciqual, .openFoodFactsSearch, .openFoodFactsBarcode, .yourFoodDatabase] {
            XCTAssertNil(try Self.description(golden).variant, golden.rawValue)
        }
        let database = try Self.description(.yourFoodDatabase)
        XCTAssertEqual(database.category, "dairy")
        XCTAssertEqual(database.productType, "packaged_single_ingredient")
        XCTAssertNil(database.state)
        // A pack size written in the title travels inside the name, as stored.
        XCTAssertEqual(database.name, "Synthetic Greek style yoghurt 500g")
        XCTAssertNil(try Self.description(.openFoodFactsSearch).category)
    }

    func testTheWorstCaseBodyFitsThePromptCeiling() throws {
        let requests = try Self.worstCaseRequests()
        let largest = try XCTUnwrap(requests.max { $0.body.count < $1.body.count })
        for request in requests {
            XCTAssertLessThanOrEqual(request.body.count, ConfirmEnrichmentRoutes.nutrients.promptCeilingTokens,
                                     "a worst-case B body of \(request.body.count) bytes passes the 6,000-token ceiling")
        }
        try check(largest.body, named: "worst-case-nutrients.json")
    }

    func testTheADetailsBodyFitsItsCeiling() throws {
        for golden in Case.allCases where golden.asksDetails {
            XCTAssertLessThanOrEqual(try Self.detailsRequest(golden).body.count, ConfirmEnrichmentRoutes.details.promptCeilingTokens)
        }
    }
}
