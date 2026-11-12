import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// The Open Food Facts forms of the estimate copy (docs/off-label-estimate-v1.md rules 3 and 6):
/// Confirm, the saved entry, the Food Log row, Developer tools and the re-log notice. A synthetic
/// Open Food Facts product; the candidate rows are the bundled CoFID and USDA rows.
@MainActor
final class OpenFoodFactsEstimatePresentationTests: XCTestCase {
    private typealias F = LabelFixtures

    private static let pool: LabelEstimateCandidatePool = {
        let ids = RandomLedgerIDGenerator()
        let search = CompositeGenericFoodSearch(sources: [try! CoFIDGenericFoodSearch(ids: ids), try! USDAGenericFoodSearch(ids: ids)], ids: ids)
        return LabelEstimateCandidatePool(searcher: search, ids: ids)
    }()

    private static let releaseID = "off:snapshot:sha256:synthetic:projection:off-product-projection-v5:schema:synthetic:retrieved:1"
    private static let recordID = "off:gtin:04006381333931"

    /// An Open Food Facts search candidate: energy, protein and a zero sugars stated, fibre in a
    /// unit the reader cannot convert, everything else not declared. Identity resolved, so it logs
    /// without a correction.
    private static func input(name: String = "90% Cocoa Dark Chocolate", unknownDetails: Bool = false) throws -> PopulatedFoodConfirmation {
        let evidence = try CaptureEvidence(evidenceID: LedgerID("00000000-0000-0000-0000-0000000f0001"), kind: .genericSearch, capturedAt: F.now,
            locale: LedgerText("en_GB"), captureMethod: LedgerText("off_text_search"), captureMethodVersion: LedgerText("off-search-candidates-v6"),
            originalPayload: .text(LedgerText("dark chocolate 90%")))
        let provenance = [NutrientProvenance(sourceKind: .exactProductDataset, sourceID: try ExternalIdentifier("open-food-facts"),
                                             sourceReleaseID: try ExternalIdentifier(releaseID), recordID: try ExternalIdentifier(recordID))]
        let stated: [NutrientKey: Double] = [.energyConsumed: 598, .protein: 9, .sugar: 0]
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            if key == .fiber { return try NutrientEntry(key: key, value: .unknown(.missingConversion)) }
            guard let amount = stated[key] else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            return try NutrientEntry(key: key, value: .augmented(ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: provenance)))
        })
        let identity = unknownDetails
            // As the Open Food Facts projection gives them: every food detail unknown.
            ? try DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown, skin: .unknown,
                                   drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams)
            : try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
                                   drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified,
                                   servingBasis: .per100Grams)
        let quantity = try EdibleQuantityIdentity.known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil)
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: ExternalIdentifier(releaseID),
            recordID: ExternalIdentifier(recordID), identity: identity, edibleQuantity: quantity, nutrients: nutrients,
            evidenceIDs: [evidence.evidenceID]), name: LedgerText(name), brand: LedgerText("Synthetic Chocolatier"),
            variant: LedgerText("Open Food Facts · source estimate · per 100 g"), itemClass: .food, packFacts: PackFacts())
        let release = SourceRelease(sourceReleaseID: try ExternalIdentifier(releaseID), sourceID: try ExternalIdentifier("open-food-facts"),
            releasedAt: F.now, artifactHash: try SHA256Digest(String(repeating: "a", count: 64)), schemaVersion: try LedgerText("synthetic"),
            pipelineVersion: try LedgerText("synthetic"), licence: try LedgerText("synthetic"), attribution: try LedgerText("synthetic"),
            manifestHash: try SHA256Digest(String(repeating: "b", count: 64)))
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [candidate],
                                             expectedIdentity: identity, expectedEdibleQuantity: quantity)
    }

    private static func service(_ store: InMemoryFoodLedgerStore) throws -> FoodConfirmationService {
        let ledger = FoodLedgerService(actorID: try LedgerID("00000000-0000-0000-0000-00000000a000"), committer: store,
            clock: F.Clock(value: F.now), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        return FoodConfirmationService(ledger: ledger, reader: store, clock: F.Clock(value: F.now), ids: RandomLedgerIDGenerator(),
            digester: SHA256Digester())
    }

    /// Confirm as the composition root wires the Open Food Facts routes: with the estimate section.
    private func confirm(unknownDetails: Bool = false) throws -> (FoodConfirmationViewModel, LabelEstimateModel, InMemoryFoodLedgerStore) {
        let store = InMemoryFoodLedgerStore()
        let service = try Self.service(store)
        let estimate = LabelEstimateModel { try Self.pool.options(cocoaPercent: $0, capturedAt: F.now, locale: LedgerText("en_GB")) }
        let model = FoodConfirmationViewModel(state: FoodConfirmationState(input: try Self.input(unknownDetails: unknownDetails), prefillSourceQuantity: false), now: { F.now },
            labelEstimate: estimate, estimateSaveAction: { state, choice in
                try service.save(state, operationID: RandomLedgerIDGenerator().makeID(OperationTag.self), idempotencyKey: nil, estimate: choice)
            }) { state in
            try service.save(state, operationID: RandomLedgerIDGenerator().makeID(OperationTag.self), idempotencyKey: nil)
        }
        return (model, estimate, store)
    }

    private func layeredEntry() throws -> (StoredFoodConfirmation, InMemoryFoodLedgerStore, LabelEstimateModel, FoodConfirmationViewModel) {
        let (model, estimate, store) = try confirm()
        model.send(.setQuantity(25, .grams))
        estimate.confirmPercent()
        estimate.choose(LabelEstimateCompatibility.nearestBandRecordID)
        model.log()
        return (try XCTUnwrap(model.savedResult, model.blockedReason ?? ""), store, estimate, model)
    }

    func testConfirmUsesTheProductFormsAndTheNamePrefill() throws {
        let (model, estimate, _) = try confirm()
        XCTAssertTrue(model.offersLabelEstimate)
        XCTAssertEqual(LabelEstimateOffer.route(model.state), .openFoodFacts)
        XCTAssertEqual(estimate.percentText, "90")
        XCTAssertEqual(estimate.suggestion?.origin, .name)
        XCTAssertEqual(LabelEstimateText.sectionTitle(.openFoodFacts), "Estimate missing nutrients")
        XCTAssertEqual(LabelEstimateText.sectionTitle(.label), "Estimate unprinted nutrients", "label copy unchanged")
        XCTAssertEqual(LabelEstimateText.footer(.label), LabelEstimateText.footer)
        XCTAssertFalse(LabelEstimateText.footer(.openFoodFacts).contains("label"))
        estimate.confirmPercent()
        estimate.choose(LabelEstimateCompatibility.nearestBandRecordID)
        let preview = try XCTUnwrap(estimate.preview(for: model.state))
        XCTAssertEqual(preview.unchanged, "Unchanged from the product: Energy, Protein, Sugar.")
        XCTAssertTrue(preview.lines.contains { $0.key == .fiber }, "fibre in an unconverted unit is estimated")
        for line in preview.lines {
            XCTAssertTrue(line.text.contains(" · estimate · "), line.text)
            XCTAssertTrue(line.accessibilityLabel.contains("estimate from"), "VoiceOver names the estimate and its source")
        }
    }

    func testTheSavedEntryFoodLogRowAndDeveloperToolsUseTheProductForms() throws {
        let (saved, store, _, _) = try layeredEntry()
        let detail = SavedFoodEntryDetail(stored: saved, isEstimate: false, history: [])
        let layer = try XCTUnwrap(detail.labelEstimate)
        XCTAssertEqual(layer.route, .openFoodFacts)
        XCTAssertEqual(FoodLogText.headerEstimate(detail),
                       "Partly estimated · Open Food Facts values, with missing nutrients estimated from US reference")
        XCTAssertEqual(layer.originalReasons[.fiber], .missingConversion)
        let fibre = FoodNutritionReviewPresentation.label(.fiber)
        XCTAssertTrue(LabelEstimateSavedEntryText.stateLines(layer).contains("\(fibre): Not read from Open Food Facts · Estimated"))
        XCTAssertEqual(LabelEstimateSavedEntryText.estimatedState(.openFoodFacts), "Not read from Open Food Facts · Estimated")
        XCTAssertEqual(LabelEstimateSavedEntryText.estimatedState(.label), "Not on the label · Estimated", "label copy unchanged")
        let developer = LabelEstimateSavedEntryText.developerLines(layer)
        XCTAssertTrue(developer.contains("Original reason, \(fibre): missing_conversion"), developer.joined(separator: "\n"))
        XCTAssertTrue(developer.contains { $0.hasPrefix("Original reason, \(FoodNutritionReviewPresentation.label(.iron)): not_declared") })
        let day = saved.logItemVersion.reportingDate.value
        let content = FoodLogDayContent(projection: try FoodIntakeProjection(records: try store.archiveState().records, reportingDate: day),
                                        reportingDate: day, estimates: [], partlyEstimated: [saved.logItem.logItemID])
        XCTAssertTrue(FoodLogText.flags(try XCTUnwrap(content.entries.first)).hasPrefix("Partly estimated"))
    }

    func testReloggingOrQuickAddingALayeredProductLogsTheProductValuesAndSaysSo() throws {
        let (saved, store, _, _) = try layeredEntry()
        let service = try Self.service(store)
        let state = try XCTUnwrap(try service.relogState(logItemID: saved.logItem.logItemID))
        // Re-log and quick add wire no estimate: no section, the product notice.
        let relog = FoodConfirmationViewModel(state: state, now: { F.now }, labelEstimateNotCarried: true) { state in
            try service.save(state, operationID: RandomLedgerIDGenerator().makeID(OperationTag.self), idempotencyKey: nil)
        }
        XCTAssertTrue(relog.labelEstimateNotCarried)
        XCTAssertFalse(relog.offersLabelEstimate)
        XCTAssertNil(relog.labelEstimate)
        XCTAssertEqual(relog.estimateNotCarriedNotice,
            "Logs the Open Food Facts values only. The estimated nutrients saved with the earlier entry are not logged again; missing nutrients stay unknown.")
        relog.log()
        let again = try XCTUnwrap(relog.savedResult, relog.blockedReason ?? "")
        XCTAssertNil(again.estimate)
        XCTAssertEqual(again.resolutionVersion.nutrients, try Self.input().candidates[0].candidate.nutrients, "the product values only")
        XCTAssertEqual(QuickAddPolicy.eligibility(pinned: saved, pinnedIsEstimate: false, rebuilt: state, now: F.now, calendar: .current),
                       .confirm(.labelEstimateNotCarried))
    }

    /// Decision 6: filling in the food details keeps the section, the confirmed percentage and the
    /// chosen row; renaming the product withdraws them with the unavailable note.
    func testAnIdentityOnlyCorrectionKeepsTheSectionAndARenameWithdrawsIt() throws {
        let (model, estimate, _) = try confirm(unknownDetails: true)
        model.send(.setQuantity(25, .grams))
        estimate.confirmPercent()
        estimate.choose(LabelEstimateCompatibility.nearestBandRecordID)
        let selected = model.state.selectedCandidate
        let details = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Grams)
        func correction(name: LedgerText) throws -> FoodCorrection {
            try FoodCorrection(name: name, brand: selected.brand, variant: selected.variant, identity: details, itemClass: selected.itemClass,
                               nutrients: selected.candidate.nutrients, reason: LedgerText("Filled in the food details"))
        }
        XCTAssertNotNil(model.blockedReason, "the food details are needed to log")
        model.send(.applyCorrection(try correction(name: selected.name)))
        XCTAssertTrue(model.offersLabelEstimate)
        XCTAssertFalse(estimate.isUnavailableAfterCorrection, "no unavailable note after food details only")
        XCTAssertEqual(estimate.chosenID, LabelEstimateCompatibility.nearestBandRecordID)
        XCTAssertEqual(estimate.confirmed?.value, 90)
        XCTAssertNotNil(model.pendingLabelEstimate)
        model.log()
        let saved = try XCTUnwrap(model.savedResult, model.blockedReason ?? "")
        XCTAssertNotNil(saved.estimate)
        XCTAssertEqual(saved.productVersion.identity, details)

        let (renamed, renamedEstimate, _) = try confirm(unknownDetails: true)
        renamedEstimate.confirmPercent()
        renamedEstimate.choose(LabelEstimateCompatibility.nearestBandRecordID)
        renamed.send(.applyCorrection(try correction(name: LedgerText("90% Cocoa Dark Chocolate Bar"))))
        XCTAssertTrue(renamedEstimate.isUnavailableAfterCorrection)
        XCTAssertEqual(LabelEstimateText.unavailableAfterCorrection(.openFoodFacts),
                       "Estimates are not available after the name, brand or values are changed, or the product is marked fortified or as something other than a food. Missing nutrients stay unknown.")
        XCTAssertEqual(LabelEstimateText.unavailableAfterCorrection(.label),
                       "Estimates are not available after food details are corrected. Missing nutrients stay unknown.", "label copy unchanged")
        XCTAssertNil(renamedEstimate.chosenID)
        XCTAssertNil(renamed.pendingLabelEstimate)
    }
}

/// Confirm rules review v1 (docs/confirm-rules-review-v1.md, #470): the one tap and the sheet.
extension OpenFoodFactsEstimatePresentationTests {
    func testTheOneTapRecordsThePackagedAnswerAndShowsIt() throws {
        let (model, estimate, _) = try confirm(unknownDetails: true)
        XCTAssertTrue(model.offersPackagedAsSold)
        XCTAssertTrue(model.applyPackagedAsSold(fortified: false))
        XCTAssertFalse(model.offersPackagedAsSold, "answered once")
        XCTAssertTrue(model.missingSourceDetails.isEmpty)
        XCTAssertEqual(model.foodDetailsSummary, "Food details: packaged, as sold, not fortified.")
        XCTAssertEqual(model.foodDetailsActionTitle, FoodConfirmationViewModel.correctFoodDetailsTitle, "Change stays available")
        XCTAssertFalse(estimate.isUnavailableAfterCorrection, "No keeps the estimate")
    }

    func testTheSheetNeedsNoReasonWhenItOnlyFillsInBlanks() throws {
        let (model, _, _) = try confirm(unknownDetails: true)
        var draft = FoodDetailsDraft(model: model)
        XCTAssertFalse(draft.canApply(in: model.state), "nothing filled in yet")
        draft.preparation = PreparationKind.asSold.rawValue
        draft.bone = BoneState.notApplicable.rawValue
        draft.skin = SkinState.notApplicable.rawValue
        draft.drained = DrainedState.notApplicable.rawValue
        draft.packingChoice = .asSold
        draft.fortification = FortificationState.unfortified.rawValue
        XCTAssertEqual(draft.packingMedium, "as sold")
        XCTAssertTrue(draft.canApply(in: model.state), "a fill needs no reason")
        XCTAssertTrue(model.applyFoodDetails(draft))
        XCTAssertEqual(model.state.correction?.reason.value, "Food details added")
        XCTAssertNil(model.foodDetailsSummary, "a typed sheet fill keeps the ordinary correction notice")
        XCTAssertTrue(model.missingSourceDetails.isEmpty)

        var renamed = FoodDetailsDraft(model: model)
        renamed.name = "Another chocolate"
        XCTAssertFalse(renamed.canApply(in: model.state), "a changed name needs a reason")
        renamed.packingChoice = .notApplicable
        XCTAssertEqual(renamed.packingMedium, "not applicable")
        renamed.packingChoice = .other
        XCTAssertEqual(renamed.packingMedium, "")
        XCTAssertEqual(renamed.packingChoice, .other, "Other stays chosen while its text is empty")
        renamed.packingMedium = "as sold"
        XCTAssertEqual(renamed.packingChoice, .other, "typing a frozen value under Other keeps its field (Qodo, #473)")
    }
}
