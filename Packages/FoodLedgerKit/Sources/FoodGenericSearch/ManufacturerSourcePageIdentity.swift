import CryptoKit
import Foundation
import SwiftSoup
import FoodLedgerApplication

/// Common acquisition checks only. Product identity remains each manufacturer's closed policy.
enum ManufacturerSourcePageIdentity {
    static func reviewed(_ source: FoodReviewedSource, hosts: Set<String>, pathPrefix: String) throws -> (Document, FoodSourceNutritionPanel)? {
        let page = source.page
        let policy = try FoodSourceURLPolicy(allowedHosts: hosts)
        guard (try? policy.canonicalURL(page.finalURL)) == page.finalURL,
              page.finalURL.query == nil, page.finalURL.fragment == nil, page.finalURL.path.hasPrefix(pathPrefix),
              page.requestedURL == source.citation.url, page.retrievedAt.timeIntervalSince1970.isFinite,
              !page.html.isEmpty, page.html.count <= HTTPSFoodSourcePageAcquirer.maximumBytes,
              page.sha256 == SHA256.hash(data: page.html).map({ String(format: "%02x", $0) }).joined(),
              let html = String(data: page.html, encoding: .utf8) else { return nil }
        try Task.checkCancellation()
        let projection = try HTMLFoodSourceTableProjector.project(page.html)
        let panels = try FoodSourceDocumentPanelReader.panels(projection, documentID: "sha256:" + page.sha256, recordID: page.finalURL.absoluteString)
        guard panels == source.panels, panels.count == 1, let panel = panels.first, panel.hasFourMacros else { return nil }
        let document = try SwiftSoup.parseHTML(html)
        guard try document.select("table").count == 1, try document.select("h1").count == 1,
              try document.select("html").attr("lang").lowercased() == "en-gb",
              let canonical = try one(document, "link[rel=canonical]"), try canonical.attr("href") == page.finalURL.absoluteString else { return nil }
        return (document, panel)
    }

    static func one(_ element: Element, _ selector: String) throws -> Element? {
        let elements = try element.select(selector).array()
        return elements.count == 1 ? elements[0] : nil
    }

    /// Only root Product objects qualify; related/recommended nested products are not traversed.
    static func product(_ document: Document) throws -> [String: Any]? {
        var products: [[String: Any]] = []
        for script in try document.select("script[type=application/ld+json]").array() {
            guard let bytes = script.data().data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: bytes) else { return nil }
            let roots: [[String: Any]]
            if let object = json as? [String: Any] { roots = [object] }
            else if let objects = json as? [[String: Any]] { roots = objects }
            else { return nil }
            products += roots.filter { $0["@type"] as? String == "Product" }
        }
        return products.count == 1 ? products[0] : nil
    }

    static func score(query: FoodSearchRemoteQuery, name: String) -> Double? {
        let parsed = FoodQueryParser.parse(query.foodTerms)
        guard name.count <= 300, parsed.allowsCandidateDiscovery, let food = parsed.food,
              Set(parsed.attributes.keys).isSubset(of: ["brand", "fat_descriptor"]) else { return nil }
        let wanted = GenericFoodSearchTerms.tokens([parsed.attributes["brand"], parsed.attributes["fat_descriptor"], food].compactMap { $0 }.joined(separator: " "))
        let actual = GenericFoodSearchTerms.tokens(name)
        guard !wanted.isEmpty, wanted.isSubset(of: actual) else { return nil }
        return Double(wanted.count) / Double(max(1, actual.count))
    }
}
