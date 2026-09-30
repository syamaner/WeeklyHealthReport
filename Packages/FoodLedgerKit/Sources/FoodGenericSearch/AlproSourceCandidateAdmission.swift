import CryptoKit
import Foundation
import SwiftSoup
import FoodLedgerApplication
import FoodLedgerDomain

/// Closed support for Alpro UK's observed product-fragment/table relationship.
/// Other hosts/layouts require their own admission contract, not a generic heading guess.
public struct AlproSourceCandidateAdmission: FoodSourceCandidateAdmitting {
    public static let version = "alpro-uk-source-candidate-v1"
    public init() { }

    public func admit(_ source: FoodReviewedSource, query: FoodSearchRemoteQuery,
                      evidence: CaptureEvidence) throws -> GenericFoodConfirmationRoute? {
        let page = source.page
        let policy = try FoodSourceURLPolicy(allowedHosts: ["www.alpro.com", "alpro.com"])
        guard (try? policy.canonicalURL(page.finalURL)) == page.finalURL,
              page.finalURL.query == nil, page.finalURL.path.hasPrefix("/en-gb/products/"),
              page.requestedURL == source.citation.url,
              page.retrievedAt.timeIntervalSince1970.isFinite,
              !page.html.isEmpty, page.html.count <= HTTPSFoodSourcePageAcquirer.maximumBytes,
              page.sha256 == SHA256.hash(data: page.html).map({ String(format: "%02x", $0) }).joined(),
              let html = String(data: page.html, encoding: .utf8) else { return nil }
        try Task.checkCancellation()
        // Recompute the bound document before trusting a review supplied by another adapter.
        let projection = try HTMLFoodSourceTableProjector.project(page.html)
        let panels = try FoodSourceDocumentPanelReader.panels(projection,
            documentID: "sha256:" + page.sha256, recordID: page.finalURL.absoluteString)
        guard panels == source.panels, panels.count == 1, let panel = panels.first,
              panel.hasFourMacros, panel.source.basisCell?.table == 1 else { return nil }
        let document = try SwiftSoup.parseHTML(html)
        let headings = try document.select(".cmp-product-salsify-header h1").array()
        let tables = try document.select(".cmp-product-salsify-analyticalComposition table").array()
        guard headings.count == 1, tables.count == 1,
              try document.getElementsByTag("table").count == 1,
              let product = try Self.productMarker(headings[0]),
              try Self.productMarker(tables[0]) == product else { return nil }
        let names = try document.select("script[type=application/ld+json]").array().compactMap { script -> String? in
            guard let data = script.data().data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  value["@type"] as? String == "WebPage" else { return nil }
            guard value["url"] as? String == page.finalURL.absoluteString,
                  value["@id"] as? String == page.finalURL.absoluteString + "#webpage",
                  let name = value["name"] as? String, !name.isEmpty, name.count <= 300 else {
                throw FoodSourceAcquisitionError.invalidResponse
            }
            return name
        }
        guard names.count == 1, let name = names.first else { return nil }
        let nameTerms = GenericFoodSearchTerms.tokens(name)
        let headingTerms = GenericFoodSearchTerms.tokens(try headings[0].text())
        guard nameTerms.contains("alpro"), headingTerms.count >= 2,
              headingTerms.isSubset(of: nameTerms) else { return nil }
        let parsed = FoodQueryParser.parse(query.foodTerms)
        guard parsed.allowsCandidateDiscovery, let food = parsed.food,
              Set(parsed.attributes.keys).isSubset(of: ["brand"]) else { return nil }
        let terms = GenericFoodSearchTerms.tokens([parsed.attributes["brand"], food].compactMap { $0 }.joined(separator: " "))
        guard !terms.isEmpty, terms.isSubset(of: nameTerms) else { return nil }
        try Task.checkCancellation()
        return try ManufacturerSourceCandidateBuilder.make(name: name, panel: panel, page: page, evidence: evidence,
            lexicalScore: Double(terms.count) / Double(max(1, nameTerms.count)),
            namespace: "alpro", label: "Alpro UK", version: Self.version, legacyCells: true)
    }

    private static func productMarker(_ element: Element) throws -> String? {
        var current: Element? = element
        while let node = current {
            if node.tagName() == "article" {
                let markers = try node.className().split(whereSeparator: \.isWhitespace)
                    .filter { $0.hasPrefix("cmp-contentfragment--") }
                guard markers.count == 1, markers[0].count > "cmp-contentfragment--".count else { return nil }
                return String(markers[0])
            }
            current = node.parent()
        }
        return nil
    }

}
