import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// View-model tests for favourites and quick add (#198).
@MainActor
final class QuickAddPresentationTests: XCTestCase {
    private struct Clock: LedgerClock { let value: Date; func now() -> Date { value } }
    private final class IDs: LedgerIDGenerating, @unchecked Sendable {
        private var value = 0
        func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
            value += 1
            return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
        }
    }

    private let now = Date(timeIntervalSince1970: 1_791_800_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/London")!; return calendar
    }

    private func services() throws -> (InMemoryFoodLedgerStore, FoodConfirmationService, FavouritesService) {
        let store = InMemoryFoodLedgerStore()
        let ids = IDs()
        let ledger = FoodLedgerService(actorID: try LedgerID("00000000-0000-0000-0000-00000000a000"), committer: store,
            clock: Clock(value: now), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let confirmations = FoodConfirmationService(ledger: ledger, reader: store, clock: Clock(value: now), ids: ids,
                                                    digester: SHA256Digester(), calendar: calendar)
        let favourites = try FavouritesService(ledger: ledger, reader: store, confirmations: confirmations, clock: Clock(value: now),
                                               ids: ids, digester: SHA256Digester(), calendar: calendar)
        return (store, confirmations, favourites)
    }

    private func exactInput() throws -> PopulatedFoodConfirmation {
        let evidenceID: EvidenceID = try LedgerID("00000000-0000-0000-0000-0000000000e1")
        let evidence = try CaptureEvidence(evidenceID: evidenceID, kind: .synthetic, capturedAt: now, locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic_fixture"), captureMethodVersion: LedgerText("v1"), originalPayload: .text(LedgerText("yoghurt")))
        let release = SourceRelease(sourceReleaseID: try ExternalIdentifier("package:presentation-v1"), sourceID: try ExternalIdentifier("physical_package"),
            releasedAt: now, artifactHash: try SHA256Digest(String(repeating: "c", count: 64)), schemaVersion: try LedgerText("v1"),
            pipelineVersion: try LedgerText("v1"), licence: try LedgerText("user supplied evidence"), attribution: try LedgerText("synthetic"),
            manifestHash: try SHA256Digest(String(repeating: "d", count: 64)))
        let provenance = NutrientProvenance(sourceKind: .userVerifiedPanel, sourceID: release.sourceID, sourceReleaseID: release.sourceReleaseID, evidenceID: evidenceID)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard key == .protein else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(amount: 10, unit: .grams,
                sourceValue: .exact(SourceExactNutrientValue(amount: 10, unit: LedgerText("g"), basis: .per100Grams)), provenance: [provenance])))
        })
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Grams)
        let quantity = EdibleQuantityIdentity.known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil)
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: release.sourceReleaseID,
            recordID: ExternalIdentifier("fixture:yoghurt"), identity: identity, edibleQuantity: quantity, nutrients: nutrients,
            evidenceIDs: [evidenceID]), name: LedgerText("Greek yoghurt"), itemClass: .food)
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: identity, expectedEdibleQuantity: quantity)
    }

    private func sheet(_ preparation: QuickAddPreparation, _ confirmations: FoodConfirmationService) -> QuickAddSheetModel {
        let now = self.now
        return QuickAddSheetModel(preparation: preparation, now: { now }, calendar: calendar) { state in
            try confirmations.save(state, operationID: LedgerID(UUID().uuidString.lowercased()))
        }
    }

    func testOpeningTheSheetWritesNothingAndOneLogSavesOnce() throws {
        let (store, confirmations, favourites) = try services()
        let model = sheet(try favourites.prepare(.builtInWater), confirmations)
        XCTAssertEqual(try store.counts().operations, 0, "A chip tap only opens the sheet")
        XCTAssertEqual(model.presets, [150, 250, 330, 500])
        XCTAssertEqual(model.selectedPreset, 250)
        XCTAssertEqual(model.title, "Quick add Water")
        XCTAssertEqual(model.sourceLine, QuickAddText.waterSourceLine)
        model.choosePreset(330)
        XCTAssertEqual(model.logTitle, "Log 330 mL")
        var completions = 0
        model.onLogged = { _ in completions += 1 }
        XCTAssertNotNil(model.editState)
        model.log(); model.log()
        XCTAssertEqual(model.phase, .saved)
        XCTAssertEqual(completions, 1, "The completion runs exactly once")
        XCTAssertNil(model.editState, "Edit is unavailable once logged")
        XCTAssertEqual(try store.counts().operations, 1)
        XCTAssertEqual(model.savedResult?.logItemVersion.edibleQuantity.value, 330)
    }

    func testInvalidCustomAmountAndOutOfWindowTimeBlockLogInline() throws {
        let (store, confirmations, favourites) = try services()
        let model = sheet(try favourites.prepare(.builtInWater), confirmations)
        for text in ["0", "5000.0001", "abc", ""] {
            model.setCustomText(text)
            XCTAssertFalse(model.canLog, text)
            XCTAssertEqual(model.blockedReason, QuickAddText.waterBoundText, text)
        }
        model.setCustomText("5000")
        XCTAssertTrue(model.canLog)
        model.setOccurredAt(now.addingTimeInterval(3_600))
        XCTAssertEqual(model.requirements, [.occurredAtInFuture])
        model.setOccurredAt(now.addingTimeInterval(-9 * 86_400))
        XCTAssertEqual(model.requirements, [.occurredAtTooEarly])
        model.log()
        XCTAssertEqual(try store.counts().operations, 0)
        model.setOccurredAt(nil)
        model.log()
        XCTAssertEqual(model.phase, .saved)
    }

    func testIneligibleFavouriteRoutesToConfirm() throws {
        let (_, confirmations, favourites) = try services()
        let water = try PlainWaterReference(digester: SHA256Digester())
        // A logged water entry with an inline correction (a different identity) is a corrected entry.
        var corrected = water.state(millilitres: 250)
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Millilitres)
        let correction = FoodCorrection(name: try LedgerText("Tap water"), brand: nil, variant: nil, identity: identity,
            itemClass: .water, nutrients: water.candidate.candidate.nutrients, reason: try LedgerText("Renamed"))
        FoodConfirmationReducer.reduce(state: &corrected, action: .applyCorrection(correction))
        let saved = try confirmations.save(corrected, operationID: LedgerID("00000000-0000-0000-0000-0000000000f1"))
        let favourite = try favourites.saveFavourite(logItemVersionID: saved.logItemVersion.logItemVersionID)
        XCTAssertEqual(try favourites.prepare(.favourite(favourite)).eligibility, .confirm(.corrected))
        XCTAssertEqual(try favourites.prepare(.builtInWater).eligibility, .sheet)
    }

    func testConfirmFavouriteFailureKeepsTheEntryLoggedAndRetries() throws {
        let (store, confirmations, favourites) = try services()
        var failNext = true
        let water = try PlainWaterReference(digester: SHA256Digester())
        // Plain water never offers Save as favourite (QA D2); any other food does.
        XCTAssertFalse(FoodConfirmationViewModel(state: water.state(millilitres: 250), savesFavourite: true,
            favouriteAction: { _ in }) { _ in throw FoodConfirmationSaveError.noAcceptedCandidate }.offersFavourite)
        var food = FoodConfirmationState(input: try exactInput(), prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &food, action: .setQuantity(150, .grams))
        let model = FoodConfirmationViewModel(state: food, savesFavourite: true, favouriteAction: { id in
            if failNext { failNext = false; throw FoodLedgerStoreError.integrityFailure("synthetic") }
            _ = try favourites.saveFavourite(logItemVersionID: id)
        }) { state in
            try confirmations.save(state, operationID: LedgerID("00000000-0000-0000-0000-0000000000f2"))
        }
        XCTAssertEqual(model.logButtonTitle, "Log and save favourite")
        model.log()
        XCTAssertNotNil(model.savedResult, "The entry stays logged")
        XCTAssertEqual(model.favouriteOutcome, .failed)
        XCTAssertEqual(QuickAddText.favouriteNotSaved, "Logged. Favourite not saved")
        model.saveFavourite()
        XCTAssertEqual(model.favouriteOutcome, .saved)
        XCTAssertEqual(try store.favouriteRecords().favourites.count, 1)
        // Without a favourite writer the toggle is not offered.
        let plain = FoodConfirmationViewModel(state: water.state(millilitres: 250), savesFavourite: true) { _ in throw FoodConfirmationSaveError.noAcceptedCandidate }
        XCTAssertFalse(plain.offersFavourite)
        XCTAssertFalse(plain.savesFavourite)
    }

    func testFavouritesScreenReordersRenamesAndRemovesWithoutLogging() throws {
        let (store, confirmations, favourites) = try services()
        let water = try PlainWaterReference(digester: SHA256Digester())
        for amount in [250.0, 500] {
            var state = water.state(millilitres: amount)
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let saved = try confirmations.save(state, operationID: LedgerID(UUID().uuidString.lowercased()))
            _ = try favourites.saveFavourite(logItemVersionID: saved.logItemVersion.logItemVersionID)
        }
        let model = FavouritesViewModel(store: favourites)
        model.reload()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.today.map(\.title), ["Water", "Water", "Water"])
        XCTAssertEqual(model.today.first?.item, .builtInWater)
        XCTAssertEqual(model.today.last?.detail, "500 mL", "A favourite of a saved entry shows its default amount")
        let logs = try store.counts().logItemVersions
        model.move(model.today[2], by: -1)
        XCTAssertEqual(model.today.map(\.detail), ["250 mL · plain water", "500 mL", "250 mL"])
        model.rename(model.today[1], to: "Large glass")
        XCTAssertEqual(model.today[1].title, "Large glass")
        model.remove(model.today[1])
        XCTAssertEqual(model.today.count, 2)
        XCTAssertNil(model.changeFailure)
        XCTAssertEqual(try store.counts().logItemVersions, logs, "Favourite edits never touch log records")
        model.rename(model.today[0], to: "   ")
        XCTAssertEqual(model.changeFailure, FavouritesViewModel.notSavedMessage)
    }

    func testChipAndRowText() throws {
        XCTAssertEqual(QuickAddText.chip(.builtInWater), "Water 250 mL")
        XCTAssertEqual(QuickAddText.detail(.builtInWater, isEstimate: false), "250 mL · plain water")
        let version = try FavouriteVersion(favouriteVersionID: LedgerID("00000000-0000-0000-0000-000000000001"),
            favouriteID: LedgerID("00000000-0000-0000-0000-000000000001"), ordinal: VersionOrdinal(1),
            binding: .savedEntry(LedgerID("00000000-0000-0000-0000-000000000001")), label: LedgerText("Greek yoghurt"),
            defaultAmount: FavouriteAmount(value: 150, unit: .grams), state: .active, createdAt: now)
        XCTAssertEqual(QuickAddText.chip(.favourite(version)), "Greek yoghurt 150 g")
        XCTAssertEqual(QuickAddText.detail(.favourite(version), isEstimate: true), "150 g · Estimate")
        XCTAssertEqual(QuickAddText.detail(.favourite(version), isEstimate: nil), "150 g · Source can no longer be verified")
        XCTAssertEqual(FoodLogText.plainWater(nil), "No data")
        let complete = FoodIntakeTotal(key: .water, knownAmount: 730, incompleteContributions: 0, includesEstimates: false)
        let minimum = FoodIntakeTotal(key: .water, knownAmount: 730, incompleteContributions: 1, includesEstimates: false)
        XCTAssertEqual(FoodLogText.plainWater(complete, locale: Locale(identifier: "en_GB")), "730 mL")
        XCTAssertEqual(FoodLogText.plainWater(minimum, locale: Locale(identifier: "en_GB")), "730 mL+")
        XCTAssertEqual(FoodLogText.plainWaterAccessibility(minimum, locale: Locale(identifier: "en_GB")), "Plain water logged, at least 730 millilitres")
        XCTAssertEqual(FoodLogText.plainWaterAccessibility(nil), "Plain water logged, no data")
    }
}
