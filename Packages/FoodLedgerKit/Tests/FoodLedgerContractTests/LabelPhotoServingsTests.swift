import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import XCTest

/// Photo entries count servings exactly as pasted labels do (docs/label-photo-ai-prefill-v1.md 4.2
/// item 3 and 17.20): `label-photo-serving-v1` through the label serving composite, on Confirm, at
/// save, in the Food Log and at reopen. The fixture stores the per 100 g column with a printed
/// serving of 30 g.
final class LabelPhotoServingsTests: XCTestCase {
    typealias F = LabelPhotoFixtures

    var directory: URL!
    var store: FoodLedgerGRDBStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("photo-servings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try FoodLedgerGRDBStore.temporary(directory: directory, encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func service() throws -> FoodConfirmationService {
        try FoodConfirmationService(ledger: LedgerFixtures.service(store), reader: store, clock: LedgerFixtures.clock,
            ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester, pastedLabelConversions: GoldenPastedLabelConversions())
    }

    func input() throws -> PopulatedFoodConfirmation { try F.input(try F.manifest()) }

    func servingsState(_ servings: Double) throws -> FoodConfirmationState {
        var state = FoodConfirmationState(input: try input(), prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(servings, .count))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return state
    }

    func testAPhotoEntryOffersAndDefaultsToServings() throws {
        let input = try input()
        let candidate = input.candidates[0]
        XCTAssertNil(PastedLabelServingPolicy.serving(input, candidate: candidate), "the frozen pasted policy never claims a photo")
        XCTAssertEqual(LabelServingPolicy.serving(input, candidate: candidate), try PositiveQuantity(value: 30, unit: .grams))
        XCTAssertEqual(LabelServingPolicy.method(input, candidate: candidate), "label-photo-serving-v1")
        let state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        XCTAssertEqual(state.quantity.unit, .count, "servings by default, as on the pasted route (C8)")
        XCTAssertEqual(state.labelServing, try PositiveQuantity(value: 30, unit: .grams))
    }

    func testServingsSaveThroughThePhotoMethodAndReopen() throws {
        let saved = try service().saveLabelPhoto(try servingsState(2), imageBytes: F.imageBytes, attachmentStore: store,
                                                 operationID: LedgerFixtures.operationID(9_980))
        let conversion = try XCTUnwrap(saved.quantityConversion)
        XCTAssertEqual(conversion.methodVersion.value, "label-photo-serving-v1")
        XCTAssertEqual(conversion.convertedQuantity, try PositiveQuantity(value: 60, unit: .grams))
        XCTAssertEqual(saved.logItemVersion.edibleQuantity, try PositiveQuantity(value: 60, unit: .grams))
        XCTAssertTrue(FoodAmountServings.isServings(enteredUnit: .count, conversion: conversion, sourceID: LabelPhotoSource.sourceID,
                                                    basis: saved.resolution.basis))
        XCTAssertEqual(FoodQuantityMethod.of(conversion), .direct, "the label's own serving, not a user method")
        XCTAssertNotNil(try service().reopen(logItemID: saved.logItem.logItemID), "reopen verifies the stored conversion")
    }

    func testAnotherLabelMethodIsRefusedOnAPhotoEntry() throws {
        var state = try servingsState(2)
        state.quantity.conversion = QuantityConversionDraft(convertedQuantity: try PositiveQuantity(value: 60, unit: .grams),
            methodVersion: try LedgerText(PastedLabelServingPolicy.version), sourceReleaseID: state.selectedCandidate.candidate.sourceReleaseID,
            evidenceID: state.selectedCandidate.candidate.evidenceIDs.first)
        XCTAssertThrowsError(try service().saveLabelPhoto(state, imageBytes: F.imageBytes, attachmentStore: store,
                                                          operationID: LedgerFixtures.operationID(9_981)))
    }

    func testPastedLabelsAreUnchanged() throws {
        let pasted = try PastedLabelFixtures.input(try PastedLabelFixtures.manifest())
        let candidate = pasted.candidates[0]
        XCTAssertEqual(LabelServingPolicy.serving(pasted, candidate: candidate), PastedLabelServingPolicy.serving(pasted, candidate: candidate))
        XCTAssertEqual(LabelServingPolicy.method(pasted, candidate: candidate), PastedLabelServingPolicy.method(pasted, candidate: candidate))
        XCTAssertEqual(LabelServingPolicy.admittedVersions, PastedLabelServingPolicy.admittedVersions + ["label-photo-serving-v1"])
    }
}
