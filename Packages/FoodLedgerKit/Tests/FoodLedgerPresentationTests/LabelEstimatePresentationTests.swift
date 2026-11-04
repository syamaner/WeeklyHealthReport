import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// Confirm's "Estimate unprinted nutrients" section and the "Partly estimated" status
/// (docs/label-estimate-merge-v1.md rules 1, 2, 7 and section 8, #383 slice B3). Synthetic
/// pasted labels; the candidate rows are the bundled CoFID and USDA rows through the generic
/// search port, as the composition root wires them.
@MainActor
final class LabelEstimatePresentationTests: XCTestCase {
    private typealias F = LabelFixtures

    private static let pool: LabelEstimateCandidatePool = {
        let ids = RandomLedgerIDGenerator()
        let search = CompositeGenericFoodSearch(sources: [try! CoFIDGenericFoodSearch(ids: ids), try! USDAGenericFoodSearch(ids: ids)], ids: ids)
        return LabelEstimateCandidatePool(searcher: search, ids: ids)
    }()

    /// Counts lookups so a test can show nothing is searched before the user confirms.
    private final class Lookups { var percents: [Double] = []; var fails = false }

    private func estimateModel(_ lookups: Lookups = Lookups()) -> LabelEstimateModel {
        LabelEstimateModel { percent in
            lookups.percents.append(percent)
            if lookups.fails { throw FoodLedgerValidationError.empty("synthetic lookup failure") }
            return try Self.pool.options(cocoaPercent: percent, capturedAt: F.now, locale: LedgerText("en_GB"))
        }
    }

    private func source(name: String = "Synthetic dark chocolate 85% cocoa", text: String = F.pastedText) throws -> PastedLabelSourceModel {
        try PastedLabelSourceModel(review: F.review(F.reading(text: text), text: text),
                                   details: PastedLabelDetails(name: name, brand: "Synthetic Mill", fortification: .no),
                                   builder: F.builder(), locale: F.locale)
    }

    private func confirm(name: String = "Synthetic dark chocolate 85% cocoa", text: String = F.pastedText,
                         lookups: Lookups = Lookups()) throws -> (FoodConfirmationViewModel, LabelEstimateModel, InMemoryFoodLedgerStore) {
        let (model, estimate, store, _) = try confirmWithSource(name: name, text: text, lookups: lookups)
        return (model, estimate, store)
    }

    private func confirmWithSource(name: String = "Synthetic dark chocolate 85% cocoa", text: String = F.pastedText,
                                   lookups: Lookups = Lookups())
        throws -> (FoodConfirmationViewModel, LabelEstimateModel, InMemoryFoodLedgerStore, PastedLabelSourceModel) {
        let estimate = estimateModel(lookups)
        let label = try source(name: name, text: text)
        let (model, store) = try F.confirm(label, labelEstimate: estimate)
        return (model, estimate, store, label)
    }

    /// A layered entry saved through Confirm with its service, for the re-log and quick-add paths.
    private func layeredEntry() throws -> (StoredFoodConfirmation, InMemoryFoodLedgerStore) {
        let (model, estimate, store) = try confirm()
        model.send(.setQuantity(25, .grams))
        estimate.confirmPercent()
        estimate.choose(try XCTUnwrap(estimate.options.first).id)
        model.log()
        return (try XCTUnwrap(model.savedResult, model.blockedReason ?? ""), store)
    }

    private static func service(_ store: InMemoryFoodLedgerStore, ids: any LedgerIDGenerating = RandomLedgerIDGenerator()) throws -> FoodConfirmationService {
        let ledger = FoodLedgerService(actorID: try LedgerID("00000000-0000-0000-0000-00000000a000"), committer: store,
            clock: F.Clock(value: F.now), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        return FoodConfirmationService(ledger: ledger, reader: store, clock: F.Clock(value: F.now), ids: ids,
            digester: SHA256Digester(), pastedLabelConversions: F.Conversions())
    }

    private final class SequentialIDs: LedgerIDGenerating, @unchecked Sendable {
        private var value = 0x7000
        func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
            defer { value += 1 }
            return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
        }
    }

    // MARK: Pre-fill and confirmation (rule 2)

    func testThePrefillComesFromTheNameThenThePastedTextAndIsOnlyASuggestion() throws {
        let lookups = Lookups()
        let (named, estimate, _) = try confirm(lookups: lookups)
        XCTAssertTrue(named.offersLabelEstimate)
        XCTAssertEqual(estimate.percentText, "85")
        XCTAssertEqual(estimate.suggestion?.origin, .name)
        XCTAssertNil(estimate.confirmed, "a pre-fill is a suggestion until the user confirms it")
        XCTAssertEqual(estimate.rows, .awaitingPercent)
        XCTAssertEqual(lookups.percents, [], "nothing is searched before confirmation")

        let labelText = F.pastedText + "Cocoa solids: 72% minimum\n"
        let (_, fromText, _) = try confirm(name: "Synthetic dark chocolate", text: labelText)
        XCTAssertEqual(fromText.percentText, "72")
        XCTAssertEqual(fromText.suggestion?.origin, .pastedText)

        let (_, none, _) = try confirm(name: "Synthetic dark chocolate")
        XCTAssertEqual(none.percentText, "")
        XCTAssertNil(none.suggestion)
        XCTAssertFalse(none.canConfirmPercent, "empty means no list")
    }

    func testTheOriginIsTheSuggestionsOnlyWhenTheUnchangedPrefillIsConfirmed() throws {
        let (_, unchanged, _) = try confirm()
        unchanged.confirmPercent()
        XCTAssertEqual(unchanged.confirmed, .init(value: 85, origin: .name))

        let (_, edited, _) = try confirm()
        edited.editPercent("8"); edited.editPercent("85")
        edited.confirmPercent()
        XCTAssertEqual(edited.confirmed, .init(value: 85, origin: .typed), "an edited pre-fill is typed")

        let (_, typed, _) = try confirm(name: "Synthetic dark chocolate")
        typed.editPercent("90,0 %")
        typed.confirmPercent()
        XCTAssertEqual(typed.confirmed, .init(value: 90, origin: .typed))
    }

    func testAnInvalidPercentageGivesNoListAndEditingWithdrawsTheConfirmation() throws {
        let lookups = Lookups()
        let (_, estimate, _) = try confirm(lookups: lookups)
        for text in ["0", "101", "85.55", "abc"] {
            estimate.editPercent(text)
            estimate.confirmPercent()
            XCTAssertEqual(estimate.percentError, LabelEstimateText.invalidPercent, text)
            XCTAssertNil(estimate.confirmed, text)
            XCTAssertEqual(estimate.rows, .awaitingPercent, text)
        }
        XCTAssertEqual(lookups.percents, [])
        estimate.editPercent("90")
        estimate.confirmPercent()
        XCTAssertEqual(lookups.percents, [90])
        estimate.choose(try XCTUnwrap(estimate.options.first).id)
        estimate.editPercent("9")
        XCTAssertNil(estimate.confirmed)
        XCTAssertEqual(estimate.rows, .awaitingPercent, "no list until the new value is confirmed")
        XCTAssertNil(estimate.chosenID)
    }

    func testTypingTheSuggestedValueBackStillMakesItTypedAndHidesTheSuggestion() throws {
        let (_, estimate, _) = try confirm()
        XCTAssertTrue(estimate.showsSuggestion)
        estimate.editPercent("8")
        XCTAssertFalse(estimate.showsSuggestion)
        estimate.editPercent("85")
        XCTAssertFalse(estimate.showsSuggestion, "any edit makes the value the user's own")
        estimate.confirmPercent()
        XCTAssertEqual(estimate.confirmed?.origin, .typed)
    }

    func testANewPrefillWithdrawsAConfirmationTakenFromTheOldOneButNotATypedValue() throws {
        let (model, estimate, _, label) = try confirmWithSource()
        estimate.confirmPercent()
        estimate.choose(try XCTUnwrap(estimate.options.first).id)
        XCTAssertNotNil(model.pendingLabelEstimate)
        label.updateNameAndBrand(name: "Synthetic dark chocolate 90% cocoa", brand: "Synthetic Mill")
        XCTAssertEqual(model.state.selectedCandidate.name.value, "Synthetic dark chocolate 90% cocoa")
        XCTAssertNil(model.pendingLabelEstimate, "the renamed label no longer carries the old pre-fill's estimate")
        XCTAssertNil(estimate.confirmed)
        XCTAssertNil(estimate.chosenID)
        XCTAssertEqual(estimate.rows, .awaitingPercent)
        XCTAssertEqual(estimate.percentText, "90", "the new suggestion")

        let (typedModel, typed, _, typedLabel) = try confirmWithSource()
        typed.editPercent("80")
        typed.confirmPercent()
        typed.choose(try XCTUnwrap(typed.options.first).id)
        typedLabel.updateNameAndBrand(name: "Synthetic dark chocolate 90% cocoa", brand: "Synthetic Mill")
        XCTAssertEqual(typed.confirmed, .init(value: 80, origin: .typed), "a typed value is the user's and stays")
        XCTAssertNotNil(typedModel.pendingLabelEstimate)
    }

    func testACorrectionClearsTheChoiceAndTheModelStatesTheUnavailableNote() throws {
        let (model, estimate, _) = try confirm()
        estimate.confirmPercent()
        estimate.choose(try XCTUnwrap(estimate.options.first).id)
        XCTAssertFalse(estimate.isUnavailableAfterCorrection)
        var draft = FoodDetailsDraft(model: model)
        draft.name = "Synthetic dark chocolate bar 85% cocoa"
        draft.reason = "Synthetic correction"
        XCTAssertTrue(model.applyFoodDetails(draft))
        XCTAssertTrue(estimate.isUnavailableAfterCorrection)
        XCTAssertNil(estimate.chosenID, "no latent choice survives a correction")
    }

    // MARK: Rows, preview and Remove (rule 7)

    func testConfirmedRowsCarrySourceReleaseAndNoteWithNothingPreselected() throws {
        let (model, estimate, _) = try confirm(name: "Synthetic dark chocolate 90% cocoa")
        estimate.confirmPercent()
        let option = try XCTUnwrap(estimate.options.first)
        XCTAssertEqual(estimate.options.map(\.id), [LabelEstimateCompatibility.nearestBandRecordID])
        XCTAssertNil(estimate.chosenID, "nothing is preselected")
        XCTAssertNil(model.pendingLabelEstimate)
        XCTAssertNil(estimate.preview(for: model.state))
        XCTAssertEqual(LabelEstimateText.source(option), "US reference · USDA SR Legacy 2018-04-01")
        XCTAssertEqual(LabelEstimateText.note(option, cocoaPercent: 90),
                       "Source covers 70 to 85% cocoa; you asked for 90%. Estimate only.")
        let spoken = LabelEstimateText.rowAccessibility(option, cocoaPercent: 90, chosen: false)
        XCTAssertTrue(spoken.hasPrefix("Estimate from Chocolate, dark, 70-85% cacao solids, US reference · USDA SR Legacy 2018-04-01"), spoken)
    }

    func testThePreviewListsOnlyTheChangedKeysAndRemoveRestoresTheLabelSet() throws {
        let (model, estimate, _) = try confirm()
        estimate.confirmPercent()
        let option = try XCTUnwrap(estimate.options.first)
        estimate.choose(option.id)
        let preview = try XCTUnwrap(estimate.preview(for: model.state))
        let label = model.state.selectedCandidate.candidate.nutrients
        let result = try XCTUnwrap(LabelEstimateOffer.merge(model.state, option: option))
        XCTAssertEqual(preview.lines.map(\.key), result.filledKeys)
        XCTAssertFalse(preview.lines.isEmpty)
        for line in preview.lines {
            guard case .unknown = try XCTUnwrap(label.entries.first { $0.key == line.key }).value else {
                return XCTFail("\(line.key) is printed on the label and must not change")
            }
            XCTAssertTrue(line.text.hasSuffix(" · estimate · USDA SR Legacy 2018-04-01"), line.text)
            XCTAssertTrue(line.accessibilityLabel.contains("estimate from Chocolate, dark, 70-85% cacao solids"), line.accessibilityLabel)
        }
        XCTAssertTrue(preview.lines.contains { $0.text == "Iron 11.9 mg · estimate · USDA SR Legacy 2018-04-01" },
                      preview.lines.map(\.text).joined(separator: "\n"))
        XCTAssertEqual(preview.basis, "Per 100 g")
        XCTAssertTrue(try XCTUnwrap(preview.unchanged).contains("Protein"), "label values are listed as unchanged")
        XCTAssertNotNil(model.pendingLabelEstimate)

        estimate.removeEstimate()
        XCTAssertNil(estimate.chosenID)
        XCTAssertNil(estimate.preview(for: model.state))
        XCTAssertNil(model.pendingLabelEstimate, "Remove estimate restores the label-only state")
        XCTAssertEqual(model.state.selectedCandidate.candidate.nutrients, label, "the label set itself never changes")
    }

    func testNoCompatibleRowShowsTheNoMatchCopy() throws {
        let (model, estimate, _) = try confirm(name: "Synthetic dark chocolate 30% cocoa")
        estimate.confirmPercent()
        XCTAssertEqual(estimate.rows, .noMatch)
        XCTAssertTrue(LabelEstimateText.noMatch.hasPrefix("No estimate matches this cocoa percentage."))
        XCTAssertNil(model.pendingLabelEstimate)
    }

    // MARK: Log (one action, never blocked)

    func testLogIsNeverBlockedAndSavesTheEstimateOnlyWhenARowIsChosen() throws {
        // Confirmed but nothing chosen: the label-only save, with no layer and no cocoa assertion.
        let (plain, plainEstimate, _) = try confirm()
        plain.send(.setQuantity(25, .grams))
        let canLog = plain.canLog
        plainEstimate.confirmPercent()
        XCTAssertEqual(plain.canLog, canLog)
        plain.log()
        let labelOnly = try XCTUnwrap(plain.savedResult, plain.blockedReason ?? "")
        XCTAssertNil(labelOnly.estimate)
        XCTAssertTrue(labelOnly.assertions.allSatisfy { $0.labelEstimate == nil })

        // A failed lookup leaves Log as it was.
        let failing = Lookups(); failing.fails = true
        let (blocked, blockedEstimate, _) = try confirm(lookups: failing)
        blocked.send(.setQuantity(25, .grams))
        blockedEstimate.confirmPercent()
        XCTAssertEqual(blockedEstimate.rows, .failed)
        XCTAssertTrue(blocked.canLog)

        // A chosen row: one Log saves the label with its estimate layer.
        let (chosen, estimate, _) = try confirm()
        chosen.send(.setQuantity(25, .grams))
        estimate.confirmPercent()
        estimate.choose(try XCTUnwrap(estimate.options.first).id)
        XCTAssertEqual(chosen.canLog, canLog)
        chosen.log()
        let saved = try XCTUnwrap(chosen.savedResult, chosen.blockedReason ?? "")
        let layer = try XCTUnwrap(saved.estimate)
        XCTAssertEqual(layer.candidateDecision.candidate.recordID.value, LabelEstimateCompatibility.nearestBandRecordID)
        let asserted = try XCTUnwrap(saved.assertions.compactMap(\.labelEstimate).first)
        XCTAssertEqual(asserted.cocoaPercent, 85)
        XCTAssertEqual(asserted.cocoaPercentOrigin, .name)
        XCTAssertEqual(layer.evidence.map(\.captureMethod.value), [LabelEstimateCandidatePool.captureMethod])
    }

    func testACorrectionWithdrawsTheChoiceSoLogStillSaves() throws {
        let (model, estimate, _) = try confirm()
        estimate.confirmPercent()
        estimate.choose(try XCTUnwrap(estimate.options.first).id)
        var draft = FoodDetailsDraft(model: model)
        draft.name = "Synthetic dark chocolate bar 85% cocoa"
        draft.reason = "Synthetic correction"
        XCTAssertTrue(model.applyFoodDetails(draft))
        XCTAssertTrue(model.offersLabelEstimate, "the section stays, with its unavailable note")
        XCTAssertFalse(LabelEstimateOffer.admitsChoice(model.state))
        XCTAssertNil(model.pendingLabelEstimate, "the save refuses an estimate on a corrected entry, so none is passed")
    }

    func testAnUnchosenWiredSaveIsByteIdenticalToAnUnwiredSave() throws {
        let input = try XCTUnwrap(try source().input)
        func saved(wired: Bool) throws -> (Data, Data) {
            let store = InMemoryFoodLedgerStore()
            let ids = SequentialIDs()
            let service = try Self.service(store, ids: ids)
            let estimate = estimateModel()
            let operationID: OperationID = try LedgerID("00000000-0000-0000-0000-00000000f001")
            var saveEstimate: (@MainActor (FoodConfirmationState, LabelEstimateChoice) throws -> StoredFoodConfirmation)?
            if wired {
                saveEstimate = { (state: FoodConfirmationState, choice: LabelEstimateChoice) in
                    try service.save(state, operationID: operationID, idempotencyKey: nil, estimate: choice)
                }
            }
            let model = FoodConfirmationViewModel(state: FoodConfirmationState(input: input, prefillSourceQuantity: false), now: { F.now },
                                                  labelEstimate: wired ? estimate : nil, estimateSaveAction: saveEstimate) { state in
                try service.save(state, operationID: operationID, idempotencyKey: nil)
            }
            model.send(.setQuantity(25, .grams))
            if wired { estimate.confirmPercent(); XCTAssertFalse(estimate.options.isEmpty) }
            model.log()
            XCTAssertNotNil(model.savedResult, model.blockedReason ?? "")
            let encoder = FoundationCanonicalJSONEncoder()
            let operation = try XCTUnwrap(try store.operation(id: operationID))
            return (try encoder.encode(operation), try encoder.encode(try store.archiveState().records))
        }
        let unwired = try saved(wired: false), wired = try saved(wired: true)
        XCTAssertEqual(wired.0, unwired.0, "the encoded operation")
        XCTAssertEqual(wired.1, unwired.1, "every stored record")
    }

    // MARK: Logging a layered entry again (section 8)

    func testReloggingOrQuickAddingALayeredEntrySavesTheLabelOnlyAndConfirmSaysSo() throws {
        let (saved, store) = try layeredEntry()
        let service = try Self.service(store)
        // Re-log: Confirm rebuilt from the label, with the not-carried notice; Log saves label values only.
        let state = try XCTUnwrap(try service.relogState(logItemID: saved.logItem.logItemID))
        let relog = FoodConfirmationViewModel(state: state, now: { F.now }, labelEstimateNotCarried: true) { state in
            try service.save(state, operationID: RandomLedgerIDGenerator().makeID(OperationTag.self), idempotencyKey: nil)
        }
        XCTAssertTrue(relog.labelEstimateNotCarried)
        XCTAssertFalse(relog.offersLabelEstimate)
        XCTAssertTrue(FoodConfirmationViewModel.labelEstimateNotCarriedNotice.hasPrefix("Logs the label values only."))
        relog.log()
        let again = try XCTUnwrap(relog.savedResult, relog.blockedReason ?? "")
        XCTAssertNil(again.estimate, "re-estimation is out of scope: the label values only")
        XCTAssertTrue(again.assertions.allSatisfy { $0.labelEstimate == nil })
        // Quick add never logs it in one step: it opens Confirm, which carries the notice.
        XCTAssertEqual(QuickAddPolicy.eligibility(pinned: saved, pinnedIsEstimate: false, rebuilt: state, now: F.now, calendar: .current),
                       .confirm(.labelEstimateNotCarried))
        // An edit keeps the layer, so no notice there.
        let reopened = try XCTUnwrap(try service.reopen(logItemID: saved.logItem.logItemID))
        XCTAssertFalse(FoodConfirmationViewModel(state: reopened, labelEstimateNotCarried: true) { _ in throw FoodConfirmationSaveError.noAcceptedCandidate }
            .labelEstimateNotCarried)
    }

    func testRecentFoodsAndFavouritesMarkALayeredEntryPartlyEstimated() throws {
        let (saved, store) = try layeredEntry()
        let service = try Self.service(store)
        let recents = FoodRecentItemsService(reader: store, confirmations: service)
            .items(records: try store.archiveState().records, now: F.now, calendar: .current)
        let recent = try XCTUnwrap(recents.first { $0.item.logItemID == saved.logItem.logItemID })
        XCTAssertTrue(recent.isPartlyEstimated)
        XCTAssertEqual(FoodEntryEstimateStatus.showsPartlyEstimated(isPartlyEstimated: true, isEstimate: false, quantityIsEstimate: true), false,
                       "an estimated amount makes the whole entry an estimate")
        let amount = try FavouriteAmount(value: 25, unit: .grams)
        let favourite = try FavouriteVersion(favouriteVersionID: LedgerID("00000000-0000-0000-0000-00000000d001"),
            favouriteID: LedgerID("00000000-0000-0000-0000-00000000d002"), ordinal: VersionOrdinal(1),
            binding: .savedEntry(saved.logItemVersion.logItemVersionID), label: LedgerText("Synthetic bar"), defaultAmount: amount,
            state: .active, createdAt: F.now)
        XCTAssertEqual(QuickAddText.detail(.favourite(favourite), isEstimate: false, partlyEstimated: true, locale: Locale(identifier: "en_GB")),
                       "25 g · Partly estimated")
        XCTAssertEqual(QuickAddText.detail(.favourite(favourite), isEstimate: false, locale: Locale(identifier: "en_GB")), "25 g")
        XCTAssertEqual(QuickAddText.detail(.favourite(favourite), isEstimate: true, partlyEstimated: true, locale: Locale(identifier: "en_GB")),
                       "25 g · Estimate")
    }

    // MARK: Saved values (photo states and bounds)

    func testAnEstimatedPhotoValueReadsAsTheEstimateAndAnEstimatedBoundStaysABound() throws {
        XCTAssertEqual(LabelPhotoSavedEntryText.state(.leftUnknown, estimated: true), LabelEstimateSavedEntryText.estimatedState)
        XCTAssertEqual(LabelPhotoSavedEntryText.state(.leftUnknown, estimated: false), LabelPhotoText.leftUnknown)
        XCTAssertEqual(LabelPhotoSavedEntryText.state(.checked, estimated: true), LabelPhotoText.checkedByYou)
        let provenance = [NutrientProvenance(sourceKind: .genericCompositionDataset, sourceID: try ExternalIdentifier("usda-legacy"),
                                             sourceReleaseID: try ExternalIdentifier("usda-legacy:synthetic"),
                                             recordID: try ExternalIdentifier("usda-legacy:record:1"))]
        let bound = NutrientValue.bounded(try NutrientBounds(lower: nil, upper: 0.5, lowerClosed: false, upperClosed: false, origin: .augmented,
            unit: .grams, sourceValue: .bounded(SourceBoundedNutrientValue(lower: nil, upper: 0.5, lowerClosed: false, upperClosed: false,
                                                                           unit: LedgerText("g"), basis: .per100Grams)),
            provenance: provenance))
        XCTAssertEqual(LabelEstimateSavedEntryText.boundedValue(bound, basis: .per100Grams), "Less than 0.5 g per 100 g · Estimated")
        XCTAssertNil(LabelEstimateSavedEntryText.boundedValue(.unknown(.notDeclared), basis: .per100Grams))
    }

    // MARK: Routes (rule 1)

    func testOpenFoodFactsManufacturerAndGenericCandidatesDoNotOfferTheSection() throws {
        let label = try XCTUnwrap(try source().input)
        for sourceID in ["openfoodfacts", "reviewed-web-proposal", "usda-legacy"] {
            let input = try Self.relabelled(label, sourceID: sourceID)
            let state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
            XCTAssertFalse(LabelEstimateOffer.applies(state), sourceID)
            let model = FoodConfirmationViewModel(state: state, labelEstimate: estimateModel(),
                                                  estimateSaveAction: { _, _ in throw FoodConfirmationSaveError.invalidLabelEstimate },
                                                  saveAction: { _ in throw FoodConfirmationSaveError.noAcceptedCandidate })
            XCTAssertFalse(model.offersLabelEstimate, sourceID)
            XCTAssertNil(model.pendingLabelEstimate, sourceID)
        }
        let milk = FoodConfirmationState(input: try XCTUnwrap(try source(name: "Synthetic milk chocolate 40% cocoa").input), prefillSourceQuantity: false)
        XCTAssertFalse(LabelEstimateOffer.applies(milk), "milk chocolate offers no estimate")
        let withoutWiring = FoodConfirmationViewModel(state: FoodConfirmationState(input: label, prefillSourceQuantity: false),
                                                      saveAction: { _ in throw FoodConfirmationSaveError.noAcceptedCandidate })
        XCTAssertFalse(withoutWiring.offersLabelEstimate, "routes that do not wire the estimate never show it")
    }

    // MARK: "Partly estimated" (section 8)

    func testALayeredEntryIsPartlyEstimatedOnFoodLogAndItsDetailAndLabelOnlyEntriesAreUnchanged() throws {
        let (plain, _, plainStore) = try confirm()
        plain.send(.setQuantity(25, .grams))
        plain.log()
        let labelOnly = try XCTUnwrap(plain.savedResult)

        let (chosen, estimate, store) = try confirm()
        chosen.send(.setQuantity(25, .grams))
        estimate.confirmPercent()
        estimate.choose(try XCTUnwrap(estimate.options.first).id)
        chosen.log()
        let saved = try XCTUnwrap(chosen.savedResult)

        XCTAssertTrue(FoodEntryEstimateStatus.isPartlyEstimated(saved))
        XCTAssertFalse(FoodEntryEstimateStatus.isPartlyEstimated(labelOnly))

        let detail = SavedFoodEntryDetail(stored: saved, isEstimate: false, history: [])
        let layer = try XCTUnwrap(detail.labelEstimate)
        XCTAssertTrue(detail.isPartlyEstimated)
        XCTAssertEqual(FoodLogText.headerEstimate(detail), "Partly estimated · Label values, with unprinted nutrients estimated from US reference")
        XCTAssertTrue(layer.estimatedKeys.contains(.iron))
        for key in layer.estimatedKeys { XCTAssertNil(detail.valueOrigins[key], "an estimate is never Printed (\(key))") }
        XCTAssertEqual(LabelEstimateSavedEntryText.sourceLine(layer),
                       "Chocolate, dark, 70-85% cacao solids · US reference · USDA SR Legacy 2018-04-01")
        XCTAssertEqual(LabelEstimateSavedEntryText.cocoaLine(layer), "Cocoa % on the pack: 85%, from the product name, confirmed by you")
        let developer = LabelEstimateSavedEntryText.developerLines(layer)
        XCTAssertEqual(developer.filter { $0.hasPrefix("Release ") }.count, 2, "both releases")
        XCTAssertEqual(developer.filter { $0.hasPrefix("Decision ") }.count, 2, "both decisions")
        XCTAssertTrue(developer.contains { $0.hasPrefix("Decision 2:") && $0.contains("selected_for_estimate") })

        let plainDetail = SavedFoodEntryDetail(stored: labelOnly, isEstimate: false, history: [])
        XCTAssertNil(plainDetail.labelEstimate)
        XCTAssertFalse(FoodLogText.headerEstimate(plainDetail)?.contains("Partly") ?? false)

        func entry(_ store: InMemoryFoodLedgerStore, _ stored: StoredFoodConfirmation) throws -> FoodLogDayContent.Entry {
            let day = stored.logItemVersion.reportingDate.value
            let content = FoodLogDayContent(projection: try FoodIntakeProjection(records: try store.archiveState().records, reportingDate: day),
                                            reportingDate: day, estimates: [],
                                            partlyEstimated: FoodEntryEstimateStatus.isPartlyEstimated(stored) ? [stored.logItem.logItemID] : [])
            return try XCTUnwrap(content.entries.first)
        }
        let layered = try entry(store, saved)
        XCTAssertTrue(layered.isPartlyEstimated)
        XCTAssertTrue(layered.isEstimate, "isEstimate keeps its meaning: the entry includes estimated values")
        XCTAssertTrue(FoodLogText.flags(layered).hasPrefix("Partly estimated"), FoodLogText.flags(layered))
        let plainEntry = try entry(plainStore, labelOnly)
        XCTAssertFalse(plainEntry.isPartlyEstimated)
        XCTAssertFalse(FoodLogText.flags(plainEntry).contains("Partly"))
    }

    /// The label candidate under another source's release and provenance (an Open Food Facts
    /// product, a reviewed manufacturer page or a generic row): rule 1 never offers those.
    private static func relabelled(_ input: PopulatedFoodConfirmation, sourceID: String) throws -> PopulatedFoodConfirmation {
        let label = input.candidates[0]
        let releaseID = try ExternalIdentifier("\(sourceID):synthetic")
        let kind: ProvenanceSourceKind = switch sourceID {
        case "usda-legacy": .genericCompositionDataset
        case "reviewed-web-proposal": .reviewedWebProposal
        default: .exactProductDataset
        }
        let evidence = try CaptureEvidence(evidenceID: LedgerID("00000000-0000-0000-0000-0000000e0001"), kind: .genericSearch,
            capturedAt: F.now, locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"), captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("dark chocolate 85%")))
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard key == .energyConsumed || key == .protein else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            let amount = key == .protein ? 8.0 : 590
            let exact = try ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [NutrientProvenance(sourceKind: kind, sourceID: ExternalIdentifier(sourceID), sourceReleaseID: releaseID,
                                                recordID: ExternalIdentifier("\(sourceID):record:1"), evidenceID: evidence.evidenceID,
                                                responseHash: try SHA256Digest(String(repeating: "c", count: 64)),
                                                manifestReference: LedgerText("synthetic-manifest"))])
            return try NutrientEntry(key: key, value: kind == .exactProductDataset ? .measured(exact) : .augmented(exact))
        })
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: releaseID,
            recordID: ExternalIdentifier("\(sourceID):record:1"), identity: label.candidate.identity, edibleQuantity: label.candidate.edibleQuantity,
            nutrients: nutrients, evidenceIDs: [evidence.evidenceID]), name: label.name, brand: label.brand, itemClass: label.itemClass)
        let release = SourceRelease(sourceReleaseID: releaseID, sourceID: try ExternalIdentifier(sourceID), releasedAt: F.now,
            artifactHash: try SHA256Digest(String(repeating: "a", count: 64)), schemaVersion: try LedgerText("synthetic"),
            pipelineVersion: try LedgerText("synthetic"), licence: try LedgerText("synthetic"), attribution: try LedgerText("synthetic"),
            manifestHash: try SHA256Digest(String(repeating: "b", count: 64)))
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: candidate.candidate.identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity)
    }
}

