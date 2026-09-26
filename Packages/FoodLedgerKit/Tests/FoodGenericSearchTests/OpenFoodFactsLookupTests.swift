import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

final class OpenFoodFactsLookupTests: XCTestCase {
    private let clock = OFFFixedClock()
    private func request() throws -> PackagedFoodLookupRequest {
        let barcode = try LedgerText("3274080005003")
        let evidence = try CaptureEvidence(evidenceID: OFFIDs().makeID(EvidenceTag.self), kind: .barcode,
            capturedAt: clock.now(), locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"),
            captureMethodVersion: LedgerText("v1"), originalPayload: .barcode(value: barcode, symbology: LedgerText("ean-13")))
        return try PackagedFoodLookupRequest(identity: BarcodeClassifier.classify(code: barcode, symbology: .ean13), evidence: evidence)
    }
    private func response(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var product: [String: Any] = ["code": "3274080005003", "product_name": "Synthetic food", "brands": "Synthetic",
            "quantity": "500 g", "nutrition_data_per": "100g", "nutriments": ["energy-kcal_100g": 120, "energy-kcal_unit": "kcal",
                "proteins_100g": 8, "proteins_unit": "g", "fat_100g": 0, "fat_unit": "g"]]
        change(&product)
        return try JSONSerialization.data(withJSONObject: ["status": "success", "product": product], options: .sortedKeys)
    }

    func testWholeRecordCandidatePreservesScanUnknownsAndSourceNotices() async throws {
        let transport = OFFFixtureTransport(response: OFFProductResponse(status: 200, body: try response()))
        let request = try request()
        guard case let .candidate(input) = try await OpenFoodFactsLookup(transport: transport, clock: clock).lookup(request) else { return XCTFail("Expected candidate") }
        XCTAssertEqual(input.evidence, [request.evidence])
        let candidate = try XCTUnwrap(input.candidates.first)
        XCTAssertEqual(candidate.barcode?.value, "03274080005003")
        XCTAssertEqual(candidate.candidate.identity.preparation.kind, .unknown)
        XCTAssertEqual(candidate.candidate.nutrients.entries.count, 39)
        guard case let .augmented(energy) = candidate.candidate.nutrients.entries.first(where: { $0.key == .energyConsumed })?.value else { return XCTFail("Source estimate required") }
        XCTAssertEqual(energy.amount, 120)
        XCTAssertEqual(candidate.candidate.nutrients.entries.first(where: { $0.key == .sodium })?.value, .unknown(.notDeclared))
        XCTAssertTrue(input.sourceReleases[0].licence.value.contains("dbcl"))
        XCTAssertTrue(input.sourceReleases[0].attribution.value.contains("/product/3274080005003"))
        let codes = await transport.codes
        XCTAssertEqual(codes, ["3274080005003"])
    }

    func testMissingAmbiguousLiquidAndUnsupportedUnitsNeverOpenBlankConfirmation() async throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0.removeValue(forKey: "nutrition_data_per") }, { $0["nutrition_data_per"] = "serving" },
            { $0["quantity"] = "500 ml" }, { $0.removeValue(forKey: "quantity") },
            { $0["nutriments"] = [:] }, { $0["product_name"] = " " },
            { $0["nutriments"] = ["proteins_100g": true, "proteins_unit": "g"] },
            { $0["nutriments"] = ["proteins_100g": 8, "proteins_unit": "mg"] },
            { $0["categories_tags"] = ["en:dietary-supplements"] }
        ]
        for change in changes {
            let source = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: OFFProductResponse(status: 200, body: try response(change))), clock: clock)
            let outcome = try await source.lookup(request())
            XCTAssertEqual(outcome, .insufficientData)
        }
    }

    func testUnavailableRateLimitMismatchMalformedAndOversizeFailClosed() async throws {
        let cases: [(OFFProductResponse, OFFLookupError)] = [
            (OFFProductResponse(status: 503, body: Data()), .unavailable),
            (OFFProductResponse(status: 429, body: Data()), .rateLimited),
            (OFFProductResponse(status: 200, body: try response { $0["code"] = "4006381333931" }), .codeMismatch),
            (OFFProductResponse(status: 200, body: Data("{}".utf8)), .malformedResponse),
            (OFFProductResponse(status: 200, body: Data(repeating: 0, count: 500_001)), .oversizedResponse)
        ]
        for (response, expected) in cases {
            let transport = OFFFixtureTransport(response: response)
            do { _ = try await OpenFoodFactsLookup(transport: transport, clock: clock).lookup(request()); XCTFail("Expected error") }
            catch { XCTAssertEqual(error as? OFFLookupError, expected) }
            let calls = await transport.codes.count
            XCTAssertEqual(calls, 1) // No adapter retry.
        }
        let missing = try JSONSerialization.data(withJSONObject: ["status": "failure", "result": ["id": "product_not_found"]])
        let outcome = try await OpenFoodFactsLookup(transport: OFFFixtureTransport(response: OFFProductResponse(status: 200, body: missing)), clock: clock).lookup(request())
        XCTAssertEqual(outcome, .notFound)
    }

    func testCancellationBeforeLookupDoesNotReachTransport() async throws {
        let transport = OFFFixtureTransport(response: OFFProductResponse(status: 200, body: try response()))
        let source = OpenFoodFactsLookup(transport: transport, clock: clock)
        let input = try request()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await source.lookup(input)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let calls = await transport.codes.count
        XCTAssertEqual(calls, 0)
    }

    func testInvalidAndLocalIdentitiesNeverReachTransport() async throws {
        let transport = OFFFixtureTransport(response: OFFProductResponse(status: 200, body: try response()))
        let evidence = try request().evidence
        for identity in [try BarcodeIdentity.gtin(LedgerText("garbage")), try .local(namespace: LedgerText("store"), code: LedgerText("123"))] {
            do { _ = try await OpenFoodFactsLookup(transport: transport, clock: clock).lookup(PackagedFoodLookupRequest(identity: identity, evidence: evidence)); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? OFFLookupError, .unsupportedCode) }
        }
        let calls = await transport.codes.count
        XCTAssertEqual(calls, 0)
    }

    func testConfirmedCandidateSavesNoticesAndReusesOfflineWithoutProvider() async throws {
        let request = try request()
        let source = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: OFFProductResponse(status: 200, body: try response())), clock: clock)
        guard case let .candidate(input) = try await source.lookup(request) else { return XCTFail("Expected candidate") }
        var state = FoodConfirmationState(input: input)
        let candidate = state.selectedCandidate
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable,
            skin: .notApplicable, drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Grams)
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(FoodCorrection(name: candidate.name, brand: candidate.brand,
            variant: candidate.variant, identity: identity, nutrients: candidate.candidate.nutrients, reason: try LedgerText("Synthetic explicit package review"))))
        let ids = OFFIDs(start: 100)
        let store = InMemoryFoodLedgerStore()
        let ledger = FoodLedgerService(actorID: try ids.makeID(ActorTag.self), committer: store, clock: clock,
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let saved = try FoodConfirmationService(ledger: ledger, reader: store, clock: clock, ids: ids).save(state, operationID: ids.makeID(OperationTag.self))
        let projection = try CanonicalFoodProjection(records: store.archiveState().records)
        let bytes = try FoundationCanonicalJSONEncoder().encode(projection)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let restored = try decoder.decode(CanonicalFoodProjection.self, from: bytes)
        XCTAssertEqual(restored.records.sourceReleases, input.sourceReleases)
        XCTAssertEqual(restored.records.evidence, [request.evidence])
        let scan = try BarcodeScan(code: LedgerText("3274080005003"), symbology: .ean13, originalSymbology: LedgerText("ean-13"),
            capturedAt: clock.now(), locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"), captureMethodVersion: LedgerText("v1"))
        let reuse = try BarcodeCaptureCoordinator(search: PersonalLibraryBarcodeSearch(reader: store), ids: ids).route(scan: scan)
        guard case let .confirmation(route) = reuse else { return XCTFail("Expected offline exact reuse") }
        XCTAssertEqual(route.reuse.productVersionID, saved.productVersion.productVersionID)
        XCTAssertEqual(route.confirmation.sourceReleases, input.sourceReleases)
    }
}

private struct OFFFixedClock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } }
private actor OFFFixtureTransport: OFFProductTransport {
    let response: OFFProductResponse
    private(set) var codes: [String] = []
    init(response: OFFProductResponse) { self.response = response }
    func product(code: String) async throws -> OFFProductResponse { codes.append(code); return response }
}
private final class OFFIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value: Int
    init(start: Int = 1) { value = start }
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
