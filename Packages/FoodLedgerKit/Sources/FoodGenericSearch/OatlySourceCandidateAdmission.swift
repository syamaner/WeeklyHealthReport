import Foundation
import SwiftSoup
import FoodLedgerApplication
import FoodLedgerDomain

/// Oatly's fetched UK canonical page owns a heading/table scope tied to the root Product SKU.
/// Its catalogue URL alias is checked explicitly, never fetched or treated as formulation evidence.
public struct OatlySourceCandidateAdmission: FoodSourceCandidateAdmitting {
    public static let version = "oatly-uk-source-candidate-v1"
    public init() { }
    public func admit(_ source: FoodReviewedSource, query: FoodSearchRemoteQuery, evidence: CaptureEvidence) throws -> GenericFoodConfirmationRoute? {
        guard let (document, panel) = try ManufacturerSourcePageIdentity.reviewed(source, hosts: ["www.oatly.com"], pathPrefix: "/en-gb/products/"),
              panel.source.basisLocation == .caption(table: 1, index: 1),
              let scope = try ManufacturerSourcePageIdentity.one(document, "main [data-product-sku]"),
              let heading = try ManufacturerSourcePageIdentity.one(scope, "h1"),
              try scope.select("table").count == 1,
              let product = try ManufacturerSourcePageIdentity.product(document),
              let sku = product["sku"] as? String, !sku.isEmpty, sku.count <= 64,
              try scope.attr("data-product-sku") == sku,
              let productName = product["name"] as? String,
              let productURL = product["url"] as? String,
              let title = try ManufacturerSourcePageIdentity.one(document, "meta[property=og:title]") else { return nil }
        let catalogueURL = "https://www.oatly.com" + String(source.page.finalURL.path.dropFirst("/en-gb".count))
        guard productURL == source.page.finalURL.absoluteString || productURL == catalogueURL else { return nil }
        let name = try title.attr("content")
        let titleTerms = GenericFoodSearchTerms.tokens(name)
        let headingTerms = GenericFoodSearchTerms.tokens(try heading.text())
        guard headingTerms.count >= 2, headingTerms == GenericFoodSearchTerms.tokens(productName),
              headingTerms.isSubset(of: titleTerms), ["oatly", "united", "kingdom"].allSatisfy(titleTerms.contains),
              let score = ManufacturerSourcePageIdentity.score(query: query, name: "Oatly " + (try heading.text())) else { return nil }
        return try ManufacturerSourceCandidateBuilder.make(name: name, panel: panel, page: source.page,
            evidence: evidence, lexicalScore: score, namespace: "oatly", label: "Oatly UK", version: Self.version)
    }
}
