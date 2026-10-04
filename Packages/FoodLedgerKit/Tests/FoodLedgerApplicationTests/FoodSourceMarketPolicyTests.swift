import Foundation
import FoodLedgerApplication
import XCTest

final class FoodSourceMarketPolicyTests: XCTestCase {
    func testExplicitConflictsAcrossCountryURLComponents() {
        for (query, address) in [
            ("FAGE Total 0% plain yoghurt UK", "https://ie.fage/yoghurts/fage-total-0"),
            ("Milk United Kingdom", "https://publisher.ie/milk"),
            ("Milk (UK)", "https://WWW.IE.publisher.com/milk"),
            ("UK milk", "https://publisher.com/tw/milk"),
            ("UK milk", "https://publisher.com/zh-TW/milk"),
            ("台灣豆漿", "https://publisher.co.uk/milk"),
            ("Taiwan milk", "https://publisher.com/uk/milk"),
            ("臺灣豆漿", "https://publisher.com/en-GB/milk"),
            ("Ireland milk", "https://publisher.com.tw/milk"),
            ("UK milk", "https://ie.publisher.co.uk/milk"),
            ("UK milk", "https://publisher.ie/uk/milk"),
            ("UK UK milk", "https://publisher.ie/milk")
        ] {
            XCTAssertTrue(conflicts(query, address), "\(query): \(address)")
        }
    }

    func testMatchingMarkersAndUnknownGeographyDoNotCertifyOrBlockMarket() {
        for (query, address) in [
            ("UK milk", "https://publisher.co.uk/milk"),
            ("UK milk", "https://gb.publisher.com/milk"),
            ("Taiwan milk", "https://publisher.com.tw/milk"),
            ("台湾豆浆", "https://publisher.com/zh-tw/milk"),
            ("Ireland milk", "https://ie.fage/yoghurt"),
            ("UK milk", "https://publisher.com/milk"),
            ("UK milk", "https://publisher.io/milk"),
            ("UK milk", "https://publisher.ai/milk"),
            ("UK milk", "https://publisher.co/milk"),
            ("UK milk", "https://publisher.tv/milk"),
            ("UK milk", "https://publisher.com/en/milk"),
            ("UK milk", "https://publisher.com/zh/milk"),
            ("UK milk", "https://publisher.com/zh-hant/milk"),
            ("UK milk", "https://publisher.com/milk?market=tw#ie"),
            ("Taiwan milk", "https://ukraine.publisher.com/milk"),
            ("Taiwan milk", "https://notuk.publisher.com/milk")
        ] {
            XCTAssertFalse(conflicts(query, address), "\(query): \(address)")
        }
    }

    func testUnstatedAmbiguousAndSubstringQueriesHaveNoUniqueMarket() {
        for query in ["milk", "UK Taiwan milk comparison", "Ireland and UK yoghurt",
                      "zukini", "Taiwanese style milk", "Ukraine milk"] {
            XCTAssertFalse(conflicts(query, "https://ie.publisher.com/milk"), query)
        }
    }

    private func conflicts(_ query: String, _ address: String) -> Bool {
        FoodSourceMarketPolicy.hasExplicitConflict(foodTerms: query, url: URL(string: address)!)
    }
}
