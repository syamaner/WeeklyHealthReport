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
        typealias P = PastedLabelFixtures
        let size = PastedLabelManifest.Candidate.ServingSize(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g")
        let pack = PastedLabelManifest.Candidate.ServingsPerPack(printedText: "本包裝含10份", decimalText: "10", approximate: false)
        // Per serving with a weight (case 2) and without one (case 3), the printed per 100 g label,
        // and per 100 g and per 100 ml under parser v2 and v3, with and without a serving size.
        var manifests: [(String, PastedLabelManifest)] = [
            ("per serving, 30 g", try P.perServingManifest(readableServingSize: true)),
            ("per serving, no weight", try P.perServingManifest(readableServingSize: false)),
            ("per 100 g printed", try P.manifest()),
        ]
        for parser in [PastedLabelSource.parserVersionV2, PastedLabelSource.parserVersionV3] {
            for basis in ["per_100g", "per_100ml"] {
                manifests.append(("\(basis) \(parser) with size", try P.per100Manifest(servingSize: size, servingsPerPack: pack, basis: basis,
                                                                                    parserVersion: parser)))
                manifests.append(("\(basis) \(parser) no size", try P.per100Manifest(servingSize: nil, basis: basis, parserVersion: parser)))
            }
        }
        for (name, manifest) in manifests {
            let pasted = try P.input(manifest)
            let candidate = pasted.candidates[0]
            XCTAssertEqual(LabelServingPolicy.serving(pasted, candidate: candidate), PastedLabelServingPolicy.serving(pasted, candidate: candidate), name)
            XCTAssertEqual(LabelServingPolicy.method(pasted, candidate: candidate), PastedLabelServingPolicy.method(pasted, candidate: candidate), name)
            XCTAssertEqual(LabelServingPolicy.servingsOnly(pasted, candidate: candidate),
                           PastedLabelServingPolicy.servingsOnly(pasted, candidate: candidate), name)
            XCTAssertEqual(LabelServingPolicy.wholePack(pasted, candidate: candidate), PastedLabelServingPolicy.wholePack(pasted, candidate: candidate), name)
        }
        XCTAssertEqual(LabelServingPolicy.admittedVersions, PastedLabelServingPolicy.admittedVersions + ["label-photo-serving-v1"])
    }

    func testAPhotoFavouriteInServingsSaysServings() throws {
        let service = try service()
        let inServings = try service.saveLabelPhoto(try servingsState(1), imageBytes: F.imageBytes, attachmentStore: store,
                                                    operationID: LedgerFixtures.operationID(9_982))
        var grams = FoodConfirmationState(input: try input(), prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &grams, action: .setQuantity(45, .grams))
        grams.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &grams, action: .accept)
        let inGrams = try service.saveLabelPhoto(grams, imageBytes: F.imageBytes, attachmentStore: store,
                                                 operationID: LedgerFixtures.operationID(9_983))
        let favourites = try FavouritesService(ledger: LedgerFixtures.service(store), reader: store, confirmations: service,
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
        let servingsFavourite = try favourites.saveFavourite(logItemVersionID: inServings.logItemVersion.logItemVersionID)
        let gramsFavourite = try favourites.saveFavourite(logItemVersionID: inGrams.logItemVersion.logItemVersionID)
        XCTAssertEqual(servingsFavourite.defaultAmount.unit, .count)
        XCTAssertTrue(favourites.amountIsServings(servingsFavourite), "Home chips, Add food and Favourites say servings")
        XCTAssertFalse(favourites.amountIsServings(gramsFavourite))
        let prepared = try favourites.prepare(.favourite(servingsFavourite))
        XCTAssertNotNil(prepared.state.labelServing, "the sheet's count is servings")
    }

    func testTheSavedPhotoEntryShowsItsServingSize() throws {
        let saved = try service().saveLabelPhoto(try servingsState(2), imageBytes: F.imageBytes, attachmentStore: store,
                                                 operationID: LedgerFixtures.operationID(9_984))
        let detail = SavedFoodEntryDetail(stored: saved, isEstimate: false, history: [])
        XCTAssertTrue(detail.amountIsServings)
        XCTAssertEqual(detail.servingSize?.quantity, try PositiveQuantity(value: 30, unit: .grams))
        XCTAssertEqual(detail.servingSize?.origin, .printed)
    }
}
