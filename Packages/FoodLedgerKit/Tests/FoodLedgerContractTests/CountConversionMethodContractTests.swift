import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// count-conversion-method-v1 (#299), on both stores: measured choices store their versioned code,
/// "Estimated by eye" is an estimated direct weight with no conversion, typed methods recorded
/// before v1 round-trip unchanged, and unknown codes fail closed.
final class CountConversionMethodContractTests: XCTestCase {
    func testMeasuredChoicesStoreTheirV1CodeAndReopenUnchanged() throws {
        try forEachStore { harness, ledger, service in
            for (index, method) in [CountConversionMethod.kitchenScale, .packageWeight].enumerated() {
                let code = try XCTUnwrap(method.storedCode)
                let saved = try service.save(try eggs(conversionMethod: code), operationID: LedgerFixtures.operationID(400 + index))
                XCTAssertEqual(saved.quantityConversion?.methodVersion, code, harness.name)
                XCTAssertEqual(saved.quantityConversion?.sourceQuantity, try PositiveQuantity(value: 3, unit: .count), harness.name)
                XCTAssertNil(saved.logItemVersion.weightDeclaration, harness.name)
                let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
                XCTAssertEqual(reopened.quantity.conversion?.methodVersion, code, harness.name)
                XCTAssertEqual(CountConversionMethod(storedCode: code), method)
            }
            _ = ledger
        }
    }

    func testEstimatedByEyeSavesAnEstimatedDeclarationAndNoConversion() throws {
        try forEachStore { harness, _, service in
            var state = try eggsInput()
            // What Confirm sends for "Estimated by eye" with 168 g typed.
            FoodConfirmationReducer.reduce(state: &state, action: .beginDirectWeight)
            FoodConfirmationReducer.reduce(state: &state, action: .setDirectWeight(168))
            FoodConfirmationReducer.reduce(state: &state, action: .setWeightBasis(.estimated))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(410))
            XCTAssertNil(saved.quantityConversion, harness.name)
            let declaration = try XCTUnwrap(saved.logItemVersion.weightDeclaration, harness.name)
            XCTAssertEqual(declaration.basis, .estimated, harness.name)
            XCTAssertEqual(declaration.total, try PositiveQuantity(value: 168, unit: .grams), harness.name)
            XCTAssertEqual(declaration.originalInput, try PositiveQuantity(value: 3, unit: .count), harness.name)
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let records = try archive.archiveState().records
            XCTAssertTrue(records.quantityConversions.isEmpty, harness.name)
            // The intake projection (Food Log, Home, export) marks the entry as an estimate.
            let projection = try FoodIntakeProjection(records: records, reportingDate: saved.logItemVersion.reportingDate.value)
            let energy = try XCTUnwrap(projection.summary.totals.first { $0.key == .energyConsumed }, harness.name)
            XCTAssertTrue(energy.includesEstimates, harness.name)
        }
    }

    func testTypedMethodRecordedBeforeV1RoundTripsUnchanged() throws {
        try forEachStore { harness, _, service in
            let typed = try LedgerText("weighed on the kitchen scale")
            let saved = try service.save(try eggs(conversionMethod: typed), operationID: LedgerFixtures.operationID(420))
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(reopened.quantity.conversion?.methodVersion, typed, harness.name)
            XCTAssertNil(CountConversionMethod(storedCode: typed))
            let record = try XCTUnwrap(saved.quantityConversion)
            let encoder = LedgerFixtures.encoder
            let bytes = try encoder.encode(record)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let decoded = try decoder.decode(QuantityConversionVersion.self, from: bytes)
            XCTAssertEqual(decoded, record, harness.name)
            XCTAssertEqual(try encoder.encode(decoded), bytes, "re-encodes to identical bytes (\(harness.name))")

            // Reopen, change the amount, keep "Recorded: ..." and save again: the typed text is kept.
            var edited = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &edited, action: .setConversion(QuantityConversionDraft(
                convertedQuantity: try PositiveQuantity(value: 170, unit: .grams), methodVersion: typed)))
            FoodConfirmationReducer.reduce(state: &edited, action: .accept)
            let resaved = try service.save(edited, operationID: LedgerFixtures.operationID(421))
            XCTAssertEqual(resaved.quantityConversion?.methodVersion, typed, harness.name)
            XCTAssertEqual(resaved.quantityConversion?.convertedQuantity, try PositiveQuantity(value: 170, unit: .grams), harness.name)
        }
    }

    func testUnknownCodesInTheMethodNamespaceAreRejectedAtSave() throws {
        try forEachStore { harness, _, service in
            for (index, text) in ["user_count_conversion_v1:estimated_by_eye", "user_count_conversion_v1:other",
                                  "user_count_conversion_v2:kitchen_scale"].enumerated() {
                XCTAssertThrowsError(try service.save(try eggs(conversionMethod: LedgerText(text)),
                                                      operationID: LedgerFixtures.operationID(430 + index))) { error in
                    XCTAssertEqual(error as? FoodConfirmationSaveError, .invalidQuantity, "\(text) (\(harness.name))")
                }
            }
        }
    }

    // MARK: - Fixtures

    private func eggsInput() throws -> FoodConfirmationState {
        let search = try CoFIDGenericFoodSearch(ids: MethodSequenceIDs())
        let request = GenericFoodSearchRequest(text: try LedgerText("egg"), identity: GenericFoodIdentityQuery(),
                                               capturedAt: LedgerFixtures.date, locale: try LedgerText("en_GB"))
        guard case let .confirmation(route) = try search.search(request), let egg = route.matches.first?.candidate else {
            throw XCTSkip("Expected a CoFID egg match")
        }
        let input = try PopulatedFoodConfirmation(evidence: route.confirmation.evidence,
            sourceReleases: route.confirmation.sourceReleases, candidates: [egg],
            expectedIdentity: egg.candidate.identity, expectedEdibleQuantity: egg.candidate.edibleQuantity)
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(3, .count))
        return state
    }

    private func eggs(conversionMethod: LedgerText) throws -> FoodConfirmationState {
        var state = try eggsInput()
        FoodConfirmationReducer.reduce(state: &state, action: .setConversion(QuantityConversionDraft(
            convertedQuantity: try PositiveQuantity(value: 168, unit: .grams), methodVersion: conversionMethod)))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return state
    }

    private func forEachStore(_ body: (TestHarness, FoodLedgerService, FoodConfirmationService) throws -> Void) throws {
        let harnesses = try LedgerFixtures.harnesses()
        defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            let ledger = try LedgerFixtures.service(harness.committer)
            let service = FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: LedgerFixtures.clock,
                                                  ids: MethodSequenceIDs(), digester: SHA256Digester())
            try body(harness, ledger, service)
        }
    }
}

private final class MethodSequenceIDs: LedgerIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 5_000

    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}

/// Food daily export contract v2 (#312), from real saves: a direct weight on a counted food
/// exports the method and the count entered, the amount the Food Log row shows.
extension CountConversionMethodContractTests {
    func testADirectWeightOnACountedFoodExportsItsMethodAndTheCountEntered() throws {
        for (basis, code, estimate) in [(UserWeightBasis.estimated, "estimated_by_eye", true), (.measured, "weighed", false)] {
            try forEachStore { harness, _, service in
                var state = try eggsInput()
                FoodConfirmationReducer.reduce(state: &state, action: .beginDirectWeight)
                FoodConfirmationReducer.reduce(state: &state, action: .setDirectWeight(168))
                FoodConfirmationReducer.reduce(state: &state, action: .setWeightBasis(basis))
                FoodConfirmationReducer.reduce(state: &state, action: .accept)
                let saved = try service.save(state, operationID: LedgerFixtures.operationID(430))
                let day = saved.logItemVersion.reportingDate.value
                let records = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess).archiveState().records
                let document = try FoodDailyExportBuilder.make(FoodDailyExportRequest(
                    records: records, reportDate: day, timeZone: TimeZone(identifier: "Europe/London")!,
                    dataAsOf: saved.logItemVersion.occurredAt.addingTimeInterval(86_400),
                    exportedAt: saved.logItemVersion.occurredAt.addingTimeInterval(86_400),
                    appContext: FoodDailyExportAppContext(appVersion: "0.0.0", appBuild: "0")))
                let quantity = try XCTUnwrap(document.entries.first, harness.name).quantity
                XCTAssertEqual(quantity.amount, 168, harness.name)
                XCTAssertEqual(quantity.amountMethod, FoodDailyExportAmountMethod(
                    code: code, isEstimate: estimate, entered: .init(amount: 3, unit: "count"), source: nil), "\(harness.name) \(code)")
                let row = try XCTUnwrap(FoodIntakeProjection(records: records, reportingDate: day).rows.first, harness.name)
                XCTAssertEqual(row.enteredAmount, try PositiveQuantity(value: 3, unit: .count), "the Food Log row's entered amount")
                // The eggs' own values are estimates (a generic food), so the day total is marked
                // either way; the entry-level flag is what tells the two amounts apart.
                XCTAssertEqual(document.summary.first { $0.key == NutrientKey.energyConsumed.rawValue }?.includesEstimates, true, harness.name)
            }
        }
    }
}
