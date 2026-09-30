import Foundation
import SwiftSoup
import FoodLedgerApplication
import FoodLedgerDomain

/// Arla UK ProductDetails scope plus exact canonical/Product/EAN correspondence.
public struct ArlaSourceCandidateAdmission: FoodSourceCandidateAdmitting {
    public static let version = "arla-uk-source-candidate-v1"
    public init() { }
    public func admit(_ source: FoodReviewedSource, query: FoodSearchRemoteQuery, evidence: CaptureEvidence) throws -> GenericFoodConfirmationRoute? {
        guard let (document, panel) = try ManufacturerSourcePageIdentity.reviewed(source, hosts: ["www.arlafoods.co.uk"], pathPrefix: "/brands/"),
              panel.source.basisLocation == .inline(.init(table: 1, row: 1, cell: 1, segment: 2)),
              let scope = try ManufacturerSourcePageIdentity.one(document, "main > .c-product"),
              let heading = try ManufacturerSourcePageIdentity.one(scope, ".c-product__header h1"),
              let details = try ManufacturerSourcePageIdentity.one(scope, "[data-vue=ProductDetails]"),
              try details.select("table.c-product-tab__nutrition-table").count == 1,
              let product = try ManufacturerSourcePageIdentity.product(document),
              product["url"] as? String == source.page.finalURL.absoluteString,
              product["@id"] as? String == source.page.finalURL.absoluteString,
              let ogURL = try ManufacturerSourcePageIdentity.one(document, "meta[property=og:url]"),
              try ogURL.attr("content") == source.page.finalURL.absoluteString,
              let title = try ManufacturerSourcePageIdentity.one(document, "meta[property=og:title]"),
              let name = product["name"] as? String,
              let brand = (product["brand"] as? [String: Any])?["name"] as? String,
              let ean = product["gtin13"] as? String, ean.count == 13, ean.allSatisfy({ $0.isASCII && $0.isNumber }),
              let modelBytes = try details.attr("data-model").data(using: .utf8),
              let model = try? JSONSerialization.jsonObject(with: modelBytes) as? [String: Any],
              (model["additionalInformation"] as? [String: Any])?["ean"] as? String == ean else { return nil }
        let displayName = try heading.text()
        let headingTerms = GenericFoodSearchTerms.tokens(displayName)
        guard headingTerms.contains("arla"),
              headingTerms == GenericFoodSearchTerms.tokens(brand + " " + name),
              headingTerms == GenericFoodSearchTerms.tokens(try title.attr("content")),
              let score = ManufacturerSourcePageIdentity.score(query: query, name: displayName) else { return nil }
        return try ManufacturerSourceCandidateBuilder.make(name: displayName, panel: panel, page: source.page,
            evidence: evidence, lexicalScore: score, namespace: "arla", label: "Arla UK", version: Self.version)
    }
}
