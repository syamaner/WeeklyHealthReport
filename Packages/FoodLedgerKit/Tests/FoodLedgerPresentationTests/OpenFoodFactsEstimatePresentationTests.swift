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
    private static func input(name: String = "90% Cocoa Dark Chocolate", unknownDetails: Bool = false,
                              bounds: [NutrientKey: (modifier: String, amount: Double)] = [:]) throws -> PopulatedFoodConfirmation {
        let evidence = try CaptureEvidence(evidenceID: LedgerID("00000000-0000-0000-0000-0000000f0001"), kind: .genericSearch, capturedAt: F.now,
            locale: LedgerText("en_GB"), captureMethod: LedgerText("off_text_search"), captureMethodVersion: LedgerText("off-search-candidates-v6"),
            originalPayload: .text(LedgerText("dark chocolate 90%")))
        let provenance = [NutrientProvenance(sourceKind: .exactProductDataset, sourceID: try ExternalIdentifier("open-food-facts"),
                                             sourceReleaseID: try ExternalIdentifier(releaseID), recordID: try ExternalIdentifier(recordID))]
        let stated: [NutrientKey: Double] = [.energyConsumed: 598, .protein: 9, .sugar: 0]
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            if let bound = bounds[key] {
                // As OpenFoodFactsLookup stores a modifier ("<0.5"): an augmented bound, per 100 g.
                let upper = bound.modifier.hasPrefix("<"), closed = bound.modifier.hasSuffix("=")
                let source = try SourceBoundedNutrientValue(lower: upper ? nil : bound.amount, upper: upper ? bound.amount : nil,
                    lowerClosed: !upper && closed, upperClosed: upper && closed, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)
                return try NutrientEntry(key: key, value: .bounded(NutrientBounds(lower: source.lower, upper: source.upper,
                    lowerClosed: source.lowerClosed, upperClosed: source.upperClosed, origin: .augmented, unit: key.canonicalUnit,
                    sourceValue: .bounded(source), provenance: provenance)))
            }
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

    // MARK: docs/off-values-label-v1.md, the Open Food Facts values label

    private func plainEntry(bounds: [NutrientKey: (modifier: String, amount: Double)] = [:])
        throws -> (StoredFoodConfirmation, InMemoryFoodLedgerStore, FoodConfirmationService) {
        let store = InMemoryFoodLedgerStore()
        let service = try Self.service(store)
        let model = FoodConfirmationViewModel(state: FoodConfirmationState(input: try Self.input(bounds: bounds), prefillSourceQuantity: false),
                                              now: { F.now }) { state in
            try service.save(state, operationID: RandomLedgerIDGenerator().makeID(OperationTag.self), idempotencyKey: nil)
        }
        model.send(.setQuantity(25, .grams))
        model.log()
        return (try XCTUnwrap(model.savedResult, model.blockedReason ?? ""), store, service)
    }

    private static func total(_ key: NutrientKey, _ detail: SavedFoodEntryDetail) throws -> FoodIntakeTotal {
        guard case let .calculated(totals) = detail.nutrition else { throw XCTSkip("no totals") }
        return try XCTUnwrap(totals.first { $0.key == key })
    }

    /// Rule 1: only an augmented value or bound naming Open Food Facts alone is one.
    func testOnlyOpenFoodFactsAugmentedValuesQualify() throws {
        let off = NutrientProvenance(sourceKind: .exactProductDataset, sourceID: try ExternalIdentifier("open-food-facts"),
                                     sourceReleaseID: try ExternalIdentifier(Self.releaseID), recordID: try ExternalIdentifier(Self.recordID))
        let generic = NutrientProvenance(sourceKind: .genericCompositionDataset, sourceID: try ExternalIdentifier("cofid"),
                                         sourceReleaseID: try ExternalIdentifier("cofid:2021"), recordID: try ExternalIdentifier("cofid:1"))
        func exact(_ provenance: [NutrientProvenance]) throws -> ExactNutrientValue {
            try ExactNutrientValue(amount: 3, unit: .grams,
                sourceValue: .exact(SourceExactNutrientValue(amount: 3, unit: LedgerText("g"), basis: .per100Grams)), provenance: provenance)
        }
        XCTAssertTrue(OpenFoodFactsValues.isProductValue(.augmented(try exact([off]))))
        XCTAssertFalse(OpenFoodFactsValues.isProductValue(.augmented(try exact([generic]))), "a generic estimate")
        XCTAssertFalse(OpenFoodFactsValues.isProductValue(.augmented(try exact([off, generic]))), "mixed provenance")
        XCTAssertFalse(OpenFoodFactsValues.isProductValue(.measured(try exact([off]))), "measured is not an estimate")
        XCTAssertFalse(OpenFoodFactsValues.isProductValue(.unknown(.notDeclared)))
        let bound = try NutrientBounds(lower: nil, upper: 0.5, lowerClosed: false, upperClosed: false, origin: .augmented, unit: .grams,
            sourceValue: .bounded(SourceBoundedNutrientValue(lower: nil, upper: 0.5, lowerClosed: false, upperClosed: false,
                                                            unit: LedgerText("g"), basis: .per100Grams)), provenance: [off])
        XCTAssertTrue(OpenFoodFactsValues.isProductValue(.bounded(bound)), "an Open Food Facts bound")
        XCTAssertThrowsError(try exact([]), "a value with no provenance cannot exist, so it never qualifies")

        // The entry rule: any other estimated or calculated value keeps "Estimate".
        func set(_ values: [NutrientKey: NutrientValue]) throws -> NutrientSet {
            try NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: values[$0] ?? .unknown(.notDeclared)) })
        }
        XCTAssertTrue(OpenFoodFactsValues.areTheOnlyEstimates(try set([.protein: .augmented(try exact([off]))])))
        XCTAssertFalse(OpenFoodFactsValues.areTheOnlyEstimates(try set([.protein: .augmented(try exact([off])),
                                                                        .fiber: .augmented(try exact([generic]))])), "mixed entry")
        XCTAssertFalse(OpenFoodFactsValues.areTheOnlyEstimates(try set([.protein: .measured(try exact([off]))])), "nothing estimated")
        let calculated = NutrientProvenance(sourceKind: .exactProductDataset, sourceID: try ExternalIdentifier("open-food-facts"),
            sourceReleaseID: try ExternalIdentifier(Self.releaseID), recordID: try ExternalIdentifier(Self.recordID),
            transforms: [try NutrientTransform(transformID: LedgerText("salt_to_sodium_v1"), transformVersion: LedgerText("pasted-label-conversions-v1"))])
        XCTAssertFalse(OpenFoodFactsValues.areTheOnlyEstimates(try set([.carbohydrates: .augmented(try exact([off])),
                                                                        .protein: .measured(try exact([calculated]))])), "a calculated value")
        XCTAssertFalse(OpenFoodFactsValues.namesSource(valuesAreOnlyEstimates: true, isEstimate: false, quantityIsEstimate: true,
                                                       energyBoundIsCalculated: false), "an estimated amount")
        XCTAssertFalse(OpenFoodFactsValues.namesSource(valuesAreOnlyEstimates: true, isEstimate: false, quantityIsEstimate: false,
                                                       energyBoundIsCalculated: true), "a calculated energy bound")
    }

    /// Rule 2: the row and Recent foods name the source only when nothing else makes it an estimate.
    func testTheRowAndRecentFoodsNameOpenFoodFactsValues() throws {
        let (saved, store, service) = try plainEntry()
        XCTAssertTrue(OpenFoodFactsValues.areTheOnlyEstimates(saved.resolutionVersion.nutrients))
        let id = saved.logItem.logItemID
        let day = saved.logItemVersion.reportingDate.value
        func flags(estimates: Set<LogItemID> = [], partly: Set<LogItemID> = [], off: Set<LogItemID> = [id]) throws -> String {
            let content = FoodLogDayContent(projection: try FoodIntakeProjection(records: try store.archiveState().records, reportingDate: day),
                                            reportingDate: day, estimates: estimates, partlyEstimated: partly, openFoodFactsValues: off)
            let entry = try XCTUnwrap(content.entries.first)
            XCTAssertTrue(entry.isEstimate, "the values stay estimates")
            return FoodLogText.flags(entry)
        }
        let named = try flags()
        XCTAssertTrue(named.hasPrefix("Open Food Facts estimate"), named)
        XCTAssertFalse(named.contains("Estimate"), "no second, bare Estimate")
        XCTAssertTrue(try flags(estimates: [id]).hasPrefix("Estimate"), "a decided or generic estimate wins")
        XCTAssertTrue(try flags(partly: [id]).hasPrefix("Partly estimated"), "a layer wins")
        XCTAssertTrue(try flags(off: []).hasPrefix("Estimate"), "other estimated values")

        let recent = try XCTUnwrap(FoodRecentItemsService(reader: store, confirmations: service)
            .items(records: try store.archiveState().records, now: F.now, calendar: .current).first)
        XCTAssertTrue(recent.isEstimate)
        XCTAssertTrue(recent.namesOpenFoodFacts, "Recent foods follows the row")
    }

    /// Rule 3: each product value names its source; a layer's estimates keep "Estimated".
    func testTheSavedEntryNamesEachOpenFoodFactsValue() throws {
        let (plain, _, _) = try plainEntry()
        let detail = SavedFoodEntryDetail(stored: plain, isEstimate: false, history: [])
        XCTAssertTrue(PastedLabelSavedEntryText.value(try Self.total(.protein, detail), detail: detail).hasSuffix(" · Open Food Facts estimate"))
        XCTAssertEqual(PastedLabelSavedEntryText.value(try Self.total(.fiber, detail), detail: detail), "Unknown")

        let (layered, _, _, _) = try layeredEntry()
        XCTAssertFalse(OpenFoodFactsValues.areTheOnlyEstimates(layered.resolutionVersion.nutrients), "a layer adds generic estimates")
        let layeredDetail = SavedFoodEntryDetail(stored: layered, isEstimate: false, history: [])
        XCTAssertTrue(PastedLabelSavedEntryText.value(try Self.total(.protein, layeredDetail), detail: layeredDetail).hasSuffix(" · Open Food Facts estimate"))
        XCTAssertTrue(PastedLabelSavedEntryText.value(try Self.total(.fiber, layeredDetail), detail: layeredDetail).hasSuffix(" · Estimated"),
                      "a layer's estimate keeps its marking")
    }

    /// Bounds stay bounds: an Open Food Facts bound reads as the bound for the stored basis with the
    /// product's estimate marking, never "Unknown" or zero. Presentation only; the stored bound is unchanged.
    func testTheSavedEntryStatesOpenFoodFactsBoundsForTheStoredBasis() throws {
        let (saved, _, _) = try plainEntry(bounds: [.sugar: ("<", 0.5), .fatSaturated: ("<=", 0.1), .fiber: (">", 3), .sodium: (">=", 120)])
        let detail = SavedFoodEntryDetail(stored: saved, isEstimate: false, history: [])
        func shown(_ key: NutrientKey) throws -> String { PastedLabelSavedEntryText.value(try Self.total(key, detail), detail: detail) }
        XCTAssertEqual(try shown(.sugar), "Less than 0.5 g per 100 g · Open Food Facts estimate")
        XCTAssertEqual(try shown(.fatSaturated), "0.1 g or less per 100 g · Open Food Facts estimate")
        XCTAssertEqual(try shown(.fiber), "More than 3 g per 100 g · Open Food Facts estimate")
        XCTAssertEqual(try shown(.sodium), "120 mg or more per 100 g · Open Food Facts estimate")
        XCTAssertTrue(try shown(.protein).hasSuffix(" · Open Food Facts estimate"), "exact values unchanged")

        let sugar = try XCTUnwrap(saved.resolutionVersion.nutrients.entries.first { $0.key == .sugar }?.value)
        guard case let .bounded(stored) = sugar else { return XCTFail("the bound is stored as a bound") }
        XCTAssertEqual(stored.upper, 0.5)
        XCTAssertNil(stored.lower)
        XCTAssertEqual(stored.origin, .augmented)
        XCTAssertNil(try Self.total(.sugar, detail).knownAmount, "no consumed amount is invented")
    }
}
