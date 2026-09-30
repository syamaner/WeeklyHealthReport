import CryptoKit
import Foundation
import XCTest
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain

final class AlproSourceCandidateAdmissionTests: XCTestCase {
    func testExactSourceValuesAndUnknownIdentityRemainVisibleAndRequireSelection() throws {
        let route = try XCTUnwrap(SourceAdmissionFixtures.route())
        let candidate = try XCTUnwrap(route.matches.first?.candidate)
        let nutrients = candidate.candidate.nutrients
        XCTAssertEqual(candidate.name.value, "Alpro Soya Original Drink 1L | Alpro UK")
        XCTAssertEqual(candidate.candidate.identity.servingBasis, .per100Millilitres)
        XCTAssertEqual(candidate.candidate.identity.preparation.kind, .unknown)
        XCTAssertNil(candidate.barcode); XCTAssertNil(candidate.brand)
        XCTAssertEqual(nutrients.entries.first { $0.key == .sodium }?.value, .unknown(.notDeclared))
        guard case let .augmented(fat) = nutrients.entries.first(where: { $0.key == .fatTotal })?.value else { return XCTFail() }
        XCTAssertEqual(fat.amount, 1.9)
        XCTAssertTrue(fat.provenance.first?.manifestReference?.value.contains("literal=1.90;") == true)
        XCTAssertEqual(fat.sourceValue, .exact(try SourceExactNutrientValue(amount: 1.9, unit: LedgerText("g"), basis: .per100Millilitres)))
        XCTAssertEqual(fat.provenance.first?.sourceKind, .exactProductDataset)
        XCTAssertEqual(route.confirmation.sourceReleases.first?.manifestHash.value, try SourceAdmissionFixtures.source().panels[0].source.sha256)
        XCTAssertTrue(route.confirmation.sourceReleases[0].licence.value.contains("Not specified"))
        let state = FoodConfirmationState(input: route.confirmation)
        XCTAssertEqual(state.decision, .undecided); XCTAssertFalse(state.isGenericEstimate)
        XCTAssertEqual(state.unresolvedIdentity.count, 6)
        XCTAssertFalse(route.matches[0].isExactName)
    }

    func testWrongHostPathOrDeclaredURLCannotAcquireProductIdentity() throws {
        for raw in ["https://other.example.com/en-gb/products/drinks/soya-original", "https://www.alpro.com/blog/soya-original",
                    "https://www.alpro.com/en-us/products/drinks/soya-original", "http://www.alpro.com/en-gb/products/drinks/soya-original"] {
            let source = try SourceAdmissionFixtures.source(url: URL(string: raw)!)
            XCTAssertNil(try AlproSourceCandidateAdmission().admit(source, query: SourceAdmissionFixtures.query(), evidence: SourceAdmissionFixtures.evidence()))
        }
        let changed = SourceAdmissionFixtures.html.replacingOccurrences(of: "\"url\":\"https://www.alpro.com/en-gb/products/drinks/soya-original\"", with: "\"url\":\"https://www.alpro.com/en-gb/products/drinks/different\"")
        XCTAssertThrowsError(try SourceAdmissionFixtures.route(html: changed))
    }

    func testMismatchedProductFragmentsHeadingsAndDuplicateIdentityAreNotAdmitted() throws {
        let html = SourceAdmissionFixtures.html
        let variants = [
            html.replacingOccurrences(of: "<article class='cmp-contentfragment--drink-soya-original-1l'><div class='cmp-product-salsify-analyticalComposition'>", with: "<article class='cmp-contentfragment--different-product'><div class='cmp-product-salsify-analyticalComposition'>"),
            html.replacingOccurrences(of: "<h1>Soya Original</h1>", with: "<h1>Almond Unsweetened</h1>"),
            html.replacingOccurrences(of: "<h1>Soya Original</h1>", with: "<h1>Soya Original</h1><h1>Soya Original</h1>"),
            html + SourceAdmissionFixtures.identity,
            html.replacingOccurrences(of: "class='cmp-contentfragment--drink-soya-original-1l'", with: "class='unknown-fragment'"),
            html.replacingOccurrences(of: "<script type='application/ld+json'>", with: "<script type='text/plain'>")
        ]
        for variant in variants { XCTAssertNil(try SourceAdmissionFixtures.route(html: variant)) }
    }

    func testMultipleIncompleteOrSubstitutedPanelsCannotBecomeOneCandidate() throws {
        let html = SourceAdmissionFixtures.html
        XCTAssertNil(try SourceAdmissionFixtures.route(html: html + "<table><tr><td>Other product</td></tr></table>"))
        XCTAssertNil(try SourceAdmissionFixtures.route(html: html.replacingOccurrences(of: "<tr><th>Protein</th><td>3.3 g</td></tr>", with: "")))
        let original = try SourceAdmissionFixtures.source()
        let changed = try SourceAdmissionFixtures.source(html: html.replacingOccurrences(of: "1.90 g", with: "99.9 g"))
        let substituted = FoodReviewedSource(citation: original.citation, page: original.page, panels: changed.panels)
        XCTAssertNil(try AlproSourceCandidateAdmission().admit(substituted, query: SourceAdmissionFixtures.query(), evidence: SourceAdmissionFixtures.evidence()))
        let badPage = AcquiredFoodSourcePage(requestedURL: original.page.requestedURL, finalURL: original.page.finalURL,
            hops: original.page.hops, html: original.page.html, sha256: String(repeating: "0", count: 64), retrievedAt: original.page.retrievedAt)
        XCTAssertNil(try AlproSourceCandidateAdmission().admit(.init(citation: original.citation, page: badPage, panels: original.panels),
            query: SourceAdmissionFixtures.query(), evidence: SourceAdmissionFixtures.evidence()))
    }

    func testQueryCoverageAndDescriptorsAreNotInferredFromTheSource() throws {
        for terms in ["Alpro almond drink", "Oatly Original soya drink", "Alpro Original soya drink chocolate", "Alpro Original soya drink 10% fat", "250g cooked sirloin"] {
            XCTAssertNil(try SourceAdmissionFixtures.route(terms: terms), terms)
        }
        let route = try XCTUnwrap(SourceAdmissionFixtures.route(terms: "250ml Alpro Original soya drink"))
        XCTAssertEqual(route.confirmation.evidence[0].originalPayload, .text(try LedgerText("250ml Alpro Original soya drink")))
        XCTAssertEqual(route.matches[0].candidate.candidate.edibleQuantity,
            .known(try PositiveQuantity(value: 100, unit: .millilitres), conversionVersionID: nil))
    }

    func testConfirmationEncodingRetainsOriginalSourceAndNoUnrequestedNutrients() throws {
        let input = try XCTUnwrap(SourceAdmissionFixtures.route()).confirmation
        let restored = try JSONDecoder().decode(PopulatedFoodConfirmation.self, from: JSONEncoder().encode(input))
        XCTAssertEqual(restored, input)
        XCTAssertEqual(restored.candidates[0].candidate.nutrients.entries.filter { if case .augmented = $0.value { return true }; return false }.count, 4)
    }
}

enum SourceAdmissionFixtures {
    static let url = URL(string: "https://www.alpro.com/en-gb/products/drinks/soya-original")!
    static let identity = """
    <script type='application/ld+json'>{"@type":"WebPage","url":"https://www.alpro.com/en-gb/products/drinks/soya-original","@id":"https://www.alpro.com/en-gb/products/drinks/soya-original#webpage","name":"Alpro Soya Original Drink 1L | Alpro UK"}</script>
    """
    static let html = identity + """
    <article class='cmp-contentfragment--drink-soya-original-1l'><div class='cmp-product-salsify-header'><h1>Soya Original</h1></div></article>
    <article class='cmp-contentfragment--drink-soya-original-1l'><div class='cmp-product-salsify-analyticalComposition'><table>
    <tr><th>Typical values</th><td>per 100 ml</td></tr><tr><th>Energy</th><td>175 kJ / 42 kcal</td></tr>
    <tr><th>Fat</th><td>1.90 g</td></tr><tr><th>Carbohydrate</th><td>2.7 g</td></tr><tr><th>Protein</th><td>3.3 g</td></tr>
    </table></div></article><h1>Choose your country</h1>
    """
    static func query(_ terms: String = "Alpro Original soya drink") throws -> FoodSearchRemoteQuery { try .init(foodTerms: terms) }
    static func evidence(_ terms: String = "Alpro Original soya drink") throws -> CaptureEvidence {
        try CaptureEvidence(evidenceID: LedgerFixtures.id(500, EvidenceTag.self), kind: .genericSearch,
            capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB"), captureMethod: LedgerText("grounded_source_search"),
            captureMethodVersion: LedgerText("v1"), originalPayload: .text(LedgerText(terms)))
    }
    static func source(html: String = html, url: URL = url) throws -> FoodReviewedSource {
        let raw = Data(html.utf8); let hash = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        let page = AcquiredFoodSourcePage(requestedURL: url, finalURL: url, hops: [.init(url: url, status: 200)], html: raw, sha256: hash, retrievedAt: LedgerFixtures.date)
        let panels = try FoodSourceDocumentPanelReader.panels(HTMLFoodSourceTableProjector.project(raw), documentID: "sha256:" + hash, recordID: url.absoluteString)
        return .init(citation: .init(title: "Untrusted model title", url: url), page: page, panels: panels)
    }
    static func route(html: String = html, terms: String = "Alpro Original soya drink") throws -> GenericFoodConfirmationRoute? {
        try AlproSourceCandidateAdmission().admit(source(html: html), query: query(terms), evidence: evidence(terms))
    }
}
