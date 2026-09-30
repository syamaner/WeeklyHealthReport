import FoodLedgerApplication
import Foundation
import XCTest

final class FoodWebCitationLinkPolicyTests: XCTestCase {
    func testModelWrittenSubdomainMatchesProviderCitationHost() {
        let lead = citation(title: "usda.gov", url: "https://vertexaisearch.cloud.google.com/redirect",
                            text: "[Whole milk](https://fdc.nal.usda.gov/food-details/123)")
        XCTAssertEqual(FoodWebCitationLinkPolicy.relationship(for: lead), .matchingHost)
    }

    func testDifferentWrittenHostIsFlaggedWithoutMakingItTheCitationLink() {
        let lead = citation(title: "rawpawiq.com", url: "https://vertexaisearch.cloud.google.com/redirect",
                            text: "[Egg](https://fdc.nal.usda.gov/food-details/123)")
        XCTAssertEqual(FoodWebCitationLinkPolicy.relationship(for: lead), .conflictingHost)
        XCTAssertEqual(lead.url.host, "vertexaisearch.cloud.google.com")
    }

    func testOpaqueRedirectAndBroadSpanRemainUnknown() {
        let opaque = citation(title: "tesco.com", url: "https://vertexaisearch.cloud.google.com/citation",
                              text: "[Whole milk](https://vertexaisearch.cloud.google.com/written)")
        XCTAssertEqual(FoodWebCitationLinkPolicy.relationship(for: opaque), .unknownDestination)

        let broad = citation(title: "tesco.com", url: "https://vertexaisearch.cloud.google.com/citation",
                             text: "[Milk](https://tesco.com/milk) and [eggs](https://fdc.nal.usda.gov/eggs)")
        XCTAssertEqual(FoodWebCitationLinkPolicy.relationship(for: broad), .multipleWrittenHosts)
    }

    func testNoWrittenLinkAndDirectCitationHostFallback() {
        let plain = citation(title: "US government record", url: "https://fdc.nal.usda.gov/food-details/123",
                             text: "A generic egg record")
        XCTAssertEqual(FoodWebCitationLinkPolicy.relationship(for: plain), .noWrittenLink)
        let linked = citation(title: "US government record", url: "https://fdc.nal.usda.gov/food-details/123",
                              text: "[Egg](https://fdc.nal.usda.gov/food-details/123)")
        XCTAssertEqual(FoodWebCitationLinkPolicy.relationship(for: linked), .matchingHost)
    }

    func testGenericCitationTitleCannotDisproveWrittenDestination() {
        let opaque = citation(title: "Manufacturer", url: "https://vertexaisearch.cloud.google.com/redirect",
                              text: "[Yogurt](https://example-food.com/yogurt)")
        XCTAssertEqual(FoodWebCitationLinkPolicy.relationship(for: opaque), .unknownDestination)
    }

    private func citation(title: String, url: String, text: String) -> FoodWebLead {
        FoodWebLead(title: title, url: URL(string: url)!, citedText: text)
    }
}
