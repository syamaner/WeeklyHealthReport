import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// The moved Open Food Facts projection (docs/confirm-enrichment-openrouter-v1-phase.md section 3.3 item
/// 5): a product record read from a downloaded export becomes exactly the candidate the barcode route
/// builds from the same record, through the one public function both use. Synthetic records only.
final class OpenFoodFactsProductMappingTests: XCTestCase {
    private struct FixedClock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } }

    private actor OneResponse: OFFProductTransport {
        let body: Data
        init(body: Data) { self.body = body }
        func product(code: String) async throws -> OFFProductResponse { OFFProductResponse(status: 200, body: body) }
    }

    private let clock = FixedClock()

    private func evidence(_ code: String) throws -> CaptureEvidence {
        try CaptureEvidence(evidenceID: LedgerID("00000000-0000-4000-8000-000000000001"), kind: .barcode,
            capturedAt: clock.now(), locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"),
            captureMethodVersion: LedgerText("v1"), originalPayload: .barcode(value: LedgerText(code), symbology: LedgerText("ean-13")))
    }

    private func document(_ product: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": "success", "product": product], options: .sortedKeys)
    }

    private let records: [[String: Any]] = [
        ["code": "3274080005003", "product_name": "Synthetic food", "brands": "Synthetic", "quantity": "500 g",
         "nutrition_data_per": "100g", "nutriments": ["energy-kcal_100g": 120, "energy-kcal_unit": "kcal", "proteins_100g": 8,
                                                     "proteins_unit": "g", "fat_100g": 0, "fat_unit": "g"]],
        ["code": "3274080005003", "product_name": "Synthetic drink", "quantity": "330 ml",
         "nutrition": ["input_sets": [["source": "packaging", "per": "100ml", "preparation": "as_sold",
                                       "nutrients": ["energy-kcal": ["value": 42, "unit": "kcal"], "sugars": ["value": 10.6, "unit": "g"]]]]]],
    ]

    func testTheMappingGivesExactlyTheBarcodeRoutesCandidateForTheSameRecord() async throws {
        for record in records {
            let body = try document(record)
            let code = "3274080005003"
            let gtin = try LedgerText("0" + code)
            let request = try PackagedFoodLookupRequest(identity: BarcodeClassifier.classify(code: LedgerText(code), symbology: .ean13),
                                                        evidence: evidence(code))
            let barcode = try await OpenFoodFactsLookup(transport: OneResponse(body: body), clock: clock).lookup(request)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let product = try XCTUnwrap(root["product"] as? [String: Any])
            let mapped = try OpenFoodFactsProductMapping.project(product: product, artifact: body, gtin: gtin,
                                                                 evidence: request.evidence, retrievedAt: clock.now())
            XCTAssertEqual(mapped, barcode, "\(record["product_name"] ?? "")")
            guard case .candidate = mapped else { return XCTFail("the synthetic record is admitted") }
        }
    }

    func testARecordTheLookupDeclinesIsDeclinedTheSameWay() throws {
        let product: [String: Any] = ["code": "3274080005003", "product_name": "Synthetic supplement", "quantity": "60 g",
                                      "categories_tags": ["en:dietary-supplements"], "nutrition_data_per": "100g",
                                      "nutriments": ["energy-kcal_100g": 1, "energy-kcal_unit": "kcal"]]
        let body = try document(product)
        let outcome = try OpenFoodFactsProductMapping.project(product: product, artifact: body, gtin: LedgerText("03274080005003"),
                                                              evidence: evidence("3274080005003"), retrievedAt: clock.now())
        XCTAssertEqual(outcome, .insufficientData)
    }
}
