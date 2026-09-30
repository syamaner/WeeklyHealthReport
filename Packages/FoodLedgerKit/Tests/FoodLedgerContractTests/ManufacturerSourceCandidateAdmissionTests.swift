import Foundation
import XCTest
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain

final class ManufacturerSourceCandidateAdmissionTests: XCTestCase {
    @MainActor
    func testManufacturerRuntimeCompositionReachesCoordinatorAndKeepsRequestedVolume() async throws {
        for kind in ManufacturerAdmissionFixtures.Kind.allCases {
            let source = try ManufacturerAdmissionFixtures.source(kind)
            let discovery = ManufacturerFixtureDiscovery(lead: source.citation)
            let acquisition = ManufacturerFixtureAcquisition(page: source.page)
            let review = try GeminiGroundedSourceReview(discovery: discovery, acquisition: acquisition,
                contentHosts: ManufacturerSourceCandidateAdmission.contentHosts)
            let remote = try GeminiFoodSearch(credentials: ManufacturerFixtureCredentials(), reviewer: review,
                admission: ManufacturerSourceCandidateAdmission(), locale: LedgerText("en_GB"))
            let coordinator = ProgressiveFoodSearchCoordinator(local: try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()),
                gemini: remote, services: .init(onlineDatabase: .disabled, gemini: .ready))
            let done = expectation(description: "source candidate appended")
            coordinator.onUpdate = { if $0.pending == nil { done.fulfill() } }
            let query = "230ml " + ManufacturerAdmissionFixtures.terms(kind)
            coordinator.search(try .init(text: LedgerText(query), capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB")))
            await fulfillment(of: [done], timeout: 5)
            XCTAssertTrue(coordinator.snapshot.failures.isEmpty)
            guard case let .confirmation(route) = coordinator.snapshot.outcome else { return XCTFail() }
            let match = try XCTUnwrap(route.matches.first { $0.candidate.candidate.recordID.value.hasPrefix(source.page.finalURL.absoluteString) })
            XCTAssertEqual(match.candidate.candidate.identity.servingBasis, kind == .arla ? .per100Grams : .per100Millilitres)
            XCTAssertEqual(route.sourceDiscovery?.leads, [source.citation])
            XCTAssertEqual(FoodQueryParser.parse(query).quantity?.value, 230)
            let queries = await discovery.queries; XCTAssertEqual(queries, [query])
            let urls = await acquisition.urls; XCTAssertEqual(urls, [source.page.requestedURL])
        }
    }

    func testSourceSpecificIdentityProducesExactProductCandidateWithUnknownsAndV2Locations() throws {
        for kind in ManufacturerAdmissionFixtures.Kind.allCases {
            let route = try XCTUnwrap(ManufacturerAdmissionFixtures.route(kind))
            let candidate = route.matches[0].candidate
            let state = FoodConfirmationState(input: route.confirmation)
            XCTAssertEqual(state.unresolvedIdentity.count, 6); XCTAssertFalse(state.isGenericEstimate)
            XCTAssertEqual(state.decision, .undecided); XCTAssertNil(candidate.barcode); XCTAssertNil(candidate.brand)
            XCTAssertEqual(candidate.candidate.identity.servingBasis, kind == .arla ? .per100Grams : .per100Millilitres)
            XCTAssertEqual(route.confirmation.sourceReleases[0].schemaVersion.value, "manufacturer-source-panel-v2")
            let known = candidate.candidate.nutrients.entries.compactMap { entry -> ExactNutrientValue? in
                if case let .augmented(value) = entry.value { return value }; return nil
            }
            XCTAssertEqual(known.count, 4)
            for value in known {
                let pointer = try XCTUnwrap(value.provenance.first?.manifestReference?.value)
                XCTAssertTrue(pointer.contains(kind == .arla ? ";basis=inline:1," : ";basis=caption:1,1"))
                XCTAssertTrue(pointer.contains("binding=food-source-explicit-basis-binding-v2"))
                XCTAssertEqual(value.provenance.first?.sourceKind, .exactProductDataset)
            }
        }
    }

    func testCanonicalLocaleAndProductURLCannotBeChangedOrInferred() throws {
        for kind in ManufacturerAdmissionFixtures.Kind.allCases {
            let html = ManufacturerAdmissionFixtures.html(kind)
            let variants = [html.replacingOccurrences(of: "rel='canonical' href='", with: "rel='canonical' href='https://wrong.example.com/"),
                html.replacingOccurrences(of: "lang='en-gb'", with: "lang='en-us'"),
                html.replacingOccurrences(of: "\"url\":\"https://", with: "\"url\":\"http://")]
            for variant in variants { XCTAssertNil(try ManufacturerAdmissionFixtures.route(kind, html: variant)) }
            let wrongHost = URL(string: "https://wrong.example.com" + ManufacturerAdmissionFixtures.url(kind).path)!
            XCTAssertNil(try ManufacturerAdmissionFixtures.route(kind, url: wrongHost))
        }
        let html = ManufacturerAdmissionFixtures.html(.oatly)
        XCTAssertNil(try ManufacturerAdmissionFixtures.route(.oatly, html: html.replacingOccurrences(of: "United Kingdom", with: "United States")))
        XCTAssertNil(try ManufacturerAdmissionFixtures.route(.oatly, html: html.replacingOccurrences(of: "www.oatly.com/products/", with: "www.oatly.com/en-us/products/")))
        // An exact canonical Product URL is also coherent; the explicit catalogue alias is not mandatory.
        XCTAssertNotNil(try ManufacturerAdmissionFixtures.route(.oatly, html: html.replacingOccurrences(of: "www.oatly.com/products/", with: "www.oatly.com/en-gb/products/")))
    }

    func testDifferentSKUOrEANAndDetachedOrDuplicatedTableAreRejected() throws {
        for kind in ManufacturerAdmissionFixtures.Kind.allCases {
            let html = ManufacturerAdmissionFixtures.html(kind)
            let mismatched = kind == .arla ? html.replacingOccurrences(of: "\"ean\":\"5000181024050\"", with: "\"ean\":\"5000181024067\"")
                : html.replacingOccurrences(of: "data-product-sku='61622'", with: "data-product-sku='other'")
            XCTAssertNil(try ManufacturerAdmissionFixtures.route(kind, html: mismatched))
            let table = ManufacturerAdmissionFixtures.table(kind)
            let detached = html.replacingOccurrences(of: table, with: "").replacingOccurrences(of: "</body>", with: table + "</body>")
            XCTAssertNil(try ManufacturerAdmissionFixtures.route(kind, html: detached))
            XCTAssertNil(try ManufacturerAdmissionFixtures.route(kind, html: html.replacingOccurrences(of: "</body>", with: table + "</body>")))
        }
    }

    func testDuplicateRootProductOrNestedRelatedProductCannotSupplyIdentity() throws {
        for kind in ManufacturerAdmissionFixtures.Kind.allCases {
            let html = ManufacturerAdmissionFixtures.html(kind), product = ManufacturerAdmissionFixtures.product(kind)
            XCTAssertNil(try ManufacturerAdmissionFixtures.route(kind, html: html.replacingOccurrences(of: "</body>", with: "<script type='application/ld+json'>" + product + "</script></body>")))
            XCTAssertNil(try ManufacturerAdmissionFixtures.route(kind, html: html.replacingOccurrences(of: product, with: "{\"@type\":\"WebPage\",\"isRelatedTo\":" + product + "}")))
            XCTAssertNil(try ManufacturerAdmissionFixtures.route(kind, html: html.replacingOccurrences(of: "<h1>", with: "<h1>Different product ")))
        }
        let html = ManufacturerAdmissionFixtures.html(.oatly)
        let withRelated = html.replacingOccurrences(of: "\"sku\":\"61622\"", with: "\"sku\":\"61622\",\"isRelatedTo\":[{\"@type\":\"Product\",\"name\":\"Chocolate\",\"sku\":\"999\"}]")
        XCTAssertNotNil(try ManufacturerAdmissionFixtures.route(.oatly, html: withRelated))
    }

    func testQueryPreparationPercentageAndVariantRemainUnresolved() throws {
        for kind in ManufacturerAdmissionFixtures.Kind.allCases {
            let terms = ManufacturerAdmissionFixtures.terms(kind)
            for suffix in [" chocolate", " cooked", " 10% fat"] { XCTAssertNil(try ManufacturerAdmissionFixtures.route(kind, terms: terms + suffix)) }
            XCTAssertNotNil(try ManufacturerAdmissionFixtures.route(kind, terms: "250ml " + terms))
        }
        XCTAssertNil(try ManufacturerAdmissionFixtures.route(.arla, terms: "Arla Cravendale skimmed milk"))
        XCTAssertNil(try ManufacturerAdmissionFixtures.route(.oatly, terms: "Oatly oat drink vanilla"))
        XCTAssertNil(try ManufacturerAdmissionFixtures.route(.oatly, terms: "United Kingdom"))
        XCTAssertNil(try ManufacturerAdmissionFixtures.route(.oatly, terms: "Oatly products"))
    }

    func testChangedHashOrSubstitutedPanelsCannotBindAnotherPage() throws {
        for kind in ManufacturerAdmissionFixtures.Kind.allCases {
            let source = try ManufacturerAdmissionFixtures.source(kind)
            let changed = try ManufacturerAdmissionFixtures.source(kind, html: ManufacturerAdmissionFixtures.html(kind).replacingOccurrences(of: kind == .arla ? "3.6 g" : "3.0g", with: "99g"))
            let substitute = FoodReviewedSource(citation: source.citation, page: source.page, panels: changed.panels)
            XCTAssertNil(try ManufacturerAdmissionFixtures.adapter(kind).admit(substitute, query: SourceAdmissionFixtures.query(ManufacturerAdmissionFixtures.terms(kind)), evidence: SourceAdmissionFixtures.evidence()))
            let page = AcquiredFoodSourcePage(requestedURL: source.page.requestedURL, finalURL: source.page.finalURL, hops: source.page.hops,
                html: source.page.html, sha256: String(repeating: "0", count: 64), retrievedAt: source.page.retrievedAt)
            XCTAssertNil(try ManufacturerAdmissionFixtures.adapter(kind).admit(.init(citation: source.citation, page: page, panels: source.panels), query: SourceAdmissionFixtures.query(ManufacturerAdmissionFixtures.terms(kind)), evidence: SourceAdmissionFixtures.evidence()))
        }
    }
}

enum ManufacturerAdmissionFixtures {
    enum Kind: CaseIterable { case arla, oatly }
    static func url(_ kind: Kind) -> URL { URL(string: kind == .arla ? "https://www.arlafoods.co.uk/brands/arla-cravendale/cravendale-whole-milk-2l/" : "https://www.oatly.com/en-gb/products/oat-drink/oat-drink-barista-edition-1l")! }
    static func terms(_ kind: Kind) -> String { kind == .arla ? "Arla Cravendale whole milk" : "Oatly oat drink barista edition" }
    static func adapter(_ kind: Kind) -> any FoodSourceCandidateAdmitting { kind == .arla ? ArlaSourceCandidateAdmission() : OatlySourceCandidateAdmission() }
    static func product(_ kind: Kind) -> String {
        if kind == .arla { return "{\"@type\":\"Product\",\"url\":\"\(url(kind).absoluteString)\",\"@id\":\"\(url(kind).absoluteString)\",\"name\":\"Whole Milk 2L\",\"brand\":{\"name\":\"Arla Cravendale®\"},\"gtin13\":\"5000181024050\"}" }
        return #"{"@type":"Product","url":"https://www.oatly.com/products/oat-drink/oat-drink-barista-edition-1l","name":"Oat Drink Barista Edition","sku":"61622"}"#
    }
    static func table(_ kind: Kind) -> String {
        if kind == .arla {
            return "<table class='c-product-tab__nutrition-table'>" + [("Energy", "271 kJ / 65 kcal"), ("Fat", "3.6 g"), ("Carbohydrate", "4.7 g"), ("Protein", "3.4 g")]
                .map { "<tr><td>\($0.0)<div>per 100 G \($0.1)</div></td></tr>" }.joined() + "</table>"
        }
        return "<table><caption>Nutrition information per 100ml:,</caption>" + [("Energy", "257kJ/61kcal"), ("Fat", "3.0g"), ("Carbohydrates", "7.1g"), ("Protein", "1.1g")]
            .map { "<tr><td>\($0.0)</td><td>\($0.1)</td></tr>" }.joined() + "</table>"
    }
    static func html(_ kind: Kind) -> String {
        let name = kind == .arla ? "Arla Cravendale® Whole Milk 2L" : "Oatly Oat Drink Barista Edition | Products | United Kingdom"
        let head = "<html lang='en-gb'><head><link rel='canonical' href='\(url(kind).absoluteString)'><meta property='og:url' content='\(url(kind).absoluteString)'><meta property='og:title' content='\(name)'><script type='application/ld+json'>\(product(kind))</script></head><body><main>"
        let body: String
        if kind == .arla {
            body = "<div class='c-product'><div class='c-product__header'><h1>\(name)</h1></div><div data-vue='ProductDetails' data-model='{\"additionalInformation\":{\"ean\":\"5000181024050\"}}'>\(table(kind))</div></div>"
        } else { body = "<div data-product-sku='61622'><h1>Oat Drink Barista Edition</h1>\(table(kind))</div>" }
        return head + body + "</main></body></html>"
    }
    static func source(_ kind: Kind, html: String? = nil, url: URL? = nil) throws -> FoodReviewedSource {
        try SourceAdmissionFixtures.source(html: html ?? self.html(kind), url: url ?? self.url(kind))
    }
    static func route(_ kind: Kind, html: String? = nil, url: URL? = nil, terms: String? = nil) throws -> GenericFoodConfirmationRoute? {
        try adapter(kind).admit(source(kind, html: html, url: url), query: SourceAdmissionFixtures.query(terms ?? self.terms(kind)), evidence: SourceAdmissionFixtures.evidence(terms ?? self.terms(kind)))
    }
}

@MainActor
private final class ManufacturerFixtureCredentials: FoodWebCredentialAuthorizing {
    func credentialForRequest() throws -> FoodWebRequestCredential { .init(key: "synthetic-manufacturer-contract-key", generation: 0) }
    func isCurrent(_ credential: FoodWebRequestCredential) -> Bool { credential.generation == 0 }
    func reject(_ credential: FoodWebRequestCredential) { XCTFail("Source review must not reject the Google key") }
}
private actor ManufacturerFixtureDiscovery: FoodWebDiscovering {
    let lead: FoodWebLead; var queries: [String] = []
    init(lead: FoodWebLead) { self.lead = lead }
    func validate(key: String) throws { throw FoodWebDiscoveryError.requestRejected }
    func discover(foodTerms: String, key: String) -> FoodWebDiscoveryResult {
        queries.append(foodTerms); return .init(leads: [lead], searchSuggestionsHTML: nil)
    }
}
private actor ManufacturerFixtureAcquisition: FoodSourcePageAcquiring {
    let page: AcquiredFoodSourcePage; var urls: [URL] = []
    init(page: AcquiredFoodSourcePage) { self.page = page }
    func acquire(_ url: URL) -> AcquiredFoodSourcePage { urls.append(url); return page }
}
