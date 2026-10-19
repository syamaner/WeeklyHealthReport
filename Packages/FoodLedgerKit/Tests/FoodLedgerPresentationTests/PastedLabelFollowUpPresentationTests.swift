import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// PR #271 follow-ups at view-model level (#93): L2 the details notice, L3 and Q-D2 calculated
/// rounding in Confirm's nutrition summaries, L4 the flow's lifecycle, Q-D1 servings wording and
/// the serving size origin, Q-D3 a calculated energy bound on the Food Log row. Synthetic only.
@MainActor
final class PastedLabelFollowUpPresentationTests: XCTestCase {
    private typealias F = LabelFixtures

    // MARK: L2

    func testTheDetailsNoticeClearsWhenDetailsAreAddedAgain() throws {
        let (confirm, _) = try F.confirm(try F.source())
        confirm.sourceDetailsNotice = FoodConfirmationViewModel.sourceDetailsNotCarried
        let candidate = confirm.state.selectedCandidate
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("as sold")), fortification: .unfortified,
            servingBasis: candidate.candidate.identity.servingBasis)
        confirm.send(.setQuantity(100, .grams))
        XCTAssertNotNil(confirm.sourceDetailsNotice, "other actions keep it")
        confirm.send(.applyCorrection(FoodCorrection(name: candidate.name, brand: candidate.brand, variant: nil, identity: identity,
            nutrients: candidate.candidate.nutrients, reason: try LedgerText("Synthetic details answer"))))
        XCTAssertNil(confirm.sourceDetailsNotice)
    }

    // MARK: L3 and Q-D2

    func testCalculatedValuesUseTheOneRoundingInEveryNutritionSummary() throws {
        let (confirm, _) = try F.confirm(try F.source())
        // Before an amount: the source value, 370.5 kcal per 100 g.
        let before = confirm.nutritionReview
        XCTAssertFalse(before.isConsumed)
        let sourceRow = try XCTUnwrap(before.mainRows.first { $0.key == .energyConsumed })
        XCTAssertEqual(confirm.displayValue(.energyConsumed, sourceRow.value, consumed: confirm.consumedAmount(.energyConsumed, before),
                                            source: !before.isConsumed), "about 371 kcal · Calculated")
        XCTAssertEqual(confirm.displayValue(.energyConsumed, "370.5 kcal", source: true), "about 371 kcal · Calculated",
                       "the full nutrition reference section")
        // For 60 g eaten: 222.3 kcal, shown whole, never with a decimal or "measured".
        confirm.send(.setQuantity(60, .grams))
        let after = confirm.nutritionReview
        XCTAssertTrue(after.isConsumed)
        let row = try XCTUnwrap(after.mainRows.first { $0.key == .energyConsumed })
        let shown = confirm.displayValue(.energyConsumed, row.value, consumed: confirm.consumedAmount(.energyConsumed, after),
                                         source: !after.isConsumed)
        XCTAssertEqual(shown, "about 222 kcal · Calculated")
        XCTAssertEqual(confirm.displayValue(.energyConsumed, "222.3 kcal estimated", consumed: 222.3), "about 222 kcal · Calculated",
                       "the consumed nutrition section")
        XCTAssertEqual(confirm.displayValue(.protein, "3.12 g"), "3.12 g", "printed values are unchanged")
        XCTAssertEqual(confirm.displayValue(.sodium, "144 mg", consumed: 144), "about 144 mg · Calculated")
    }

    // MARK: L4

    func testSwipingAddFoodAwayFromConfirmClearsTheLinesAndBackKeepsTheText() throws {
        var lines: [[String]] = []
        let model = F.textModel(F.StubReader(F.reading()), diagnostics: { lines.append($0) })
        model.name = "Synthetic oat crackers"
        model.text = F.pastedText
        XCTAssertNotNil(model.readLabel())
        XCTAssertFalse(lines.last?.isEmpty ?? true, "Developer tools show the reading")
        // Back (or Edit label text) from Confirm: Confirm is no longer pushed.
        model.confirmDisappeared(stillPushed: false)
        XCTAssertEqual(model.text, F.pastedText, "Back keeps the label text")
        XCTAssertEqual(model.name, "Synthetic oat crackers")
        XCTAssertFalse(lines.last?.isEmpty ?? true, "and the lines, while the screen is open")
        model.labelScreenDisappeared(covered: true)
        XCTAssertEqual(model.text, F.pastedText, "covered by Confirm, Search or Barcode: still open")
        // Add food swiped away while Confirm is still pushed: the flow ended.
        model.confirmDisappeared(stillPushed: true)
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(lines.last, [], "the pasted-label Developer tools lines are cleared")
        // The label screen closing on its own ends the flow too (dismissal cleared the name).
        model.name = "Synthetic oat crackers"
        model.text = F.pastedText
        XCTAssertNotNil(model.readLabel())
        model.labelScreenDisappeared(covered: false)
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(lines.last, [])
    }

    // MARK: Q-D1

    func testAServingsAmountReadsServingsOnRecentAndTheSavedEntryWithItsServingSizeOrigin() throws {
        let item = FoodRecentItem(logItemID: try RandomLedgerIDGenerator().makeID(LogItemTag.self),
            sourceReleaseID: try ExternalIdentifier("pasted-label:synthetic"), recordID: try ExternalIdentifier("pasted-label:synthetic#header=h2"),
            occurredAt: F.now, lastAmount: try PositiveQuantity(value: 2, unit: .count), energyKcal: 222.3, lastAmountIsServings: true)
        let calendar = Calendar(identifier: .gregorian)
        XCTAssertEqual(AddFoodRecentRowText(FoodRecentRelogItem(item: item, name: "Synthetic oat crackers", isEstimate: true),
                                            now: F.now, calendar: calendar).detail, "Estimate · Last: 2 servings · today")
        let pieces = FoodRecentItem(logItemID: item.logItemID, sourceReleaseID: item.sourceReleaseID, recordID: item.recordID,
            occurredAt: F.now, lastAmount: item.lastAmount, energyKcal: nil)
        XCTAssertEqual(AddFoodRecentRowText(FoodRecentRelogItem(item: pieces, name: "x", isEstimate: false), now: F.now, calendar: calendar).detail,
                       "Last: 2 pieces · today", "other counts are unchanged")

        // Printed serving size, whole pack.
        let (printed, _) = try F.confirm(try F.source())
        printed.chooseWholePack()
        printed.log()
        let saved = try XCTUnwrap(printed.savedResult)
        let detail = SavedFoodEntryDetail(stored: saved, isEstimate: false, history: [])
        XCTAssertEqual(FoodLogText.savedAmount(detail, locale: Locale(identifier: "en_GB")), "10 servings · 300 g")
        XCTAssertEqual(PastedLabelSavedEntryText.servingSizeLine(detail), "Serving size 30 g · Printed")

        // Corrected serving size.
        let source = try F.source()
        let (corrected, _) = try F.confirm(source)
        XCTAssertNil(source.setValue("serving_size", text: "35", unit: "g"))
        corrected.send(.setQuantity(1, .count))
        corrected.log()
        let one = SavedFoodEntryDetail(stored: try XCTUnwrap(corrected.savedResult), isEstimate: false, history: [])
        XCTAssertEqual(FoodLogText.savedAmount(one, locale: Locale(identifier: "en_GB")), "1 serving · 35 g")
        XCTAssertEqual(PastedLabelSavedEntryText.servingSizeLine(one), "Serving size 35 g · Corrected by you")

        // Grams: no servings wording and no serving size line.
        let (grams, _) = try F.confirm(try F.source())
        grams.send(.setQuantity(45, .grams))
        grams.log()
        let gramsDetail = SavedFoodEntryDetail(stored: try XCTUnwrap(grams.savedResult), isEstimate: false, history: [])
        XCTAssertEqual(FoodLogText.savedAmount(gramsDetail, locale: Locale(identifier: "en_GB")), "45 g")
        XCTAssertNil(PastedLabelSavedEntryText.servingSizeLine(gramsDetail))
    }

    // MARK: Q-D3

    /// The per 100 g reading with its stored column, serving size or energy changed.
    private func variant(basis: String = "per_100g", servingSize: PastedLabelManifest.Candidate.ServingSize?? = .none,
                         boundedEnergy: Bool = false) -> LabelReading {
        let reading = F.reading()
        let bound = PastedLabelManifest.Conversion(nutrient: "energy_kcal", rule: "kj_to_kcal_v1", ruleVersion: "pasted-label-conversions-v1",
            sourceHeaderID: "h2", sourceRowID: "熱量", operandText: "17", operandUnit: "kJ", factorText: "4.184",
            intermediateText: "4.063098", storedText: "4.1", comparator: "<", rounding: "outward")
        let cells = reading.candidate.cells.map { cell in
            boundedEnergy && cell.headerID == "h2" && cell.nutrient == "energy_kj"
                ? F.cell("熱量", "energy_kj", "h2", "<17 kJ", "17", "kJ", comparator: "<") : cell
        }
        let headers = reading.candidate.headers.map { header in
            header.headerID == "h2" ? .init(headerID: "h2", printedText: basis == "per_100ml" ? "每100毫升" : "每100公克", basis: basis,
                                            servingConversion: nil) : header
        }
        let candidate = PastedLabelManifest.Candidate(route: "A", inputSHA256: reading.candidate.inputSHA256, declined: false, declineReasons: [],
            wouldMarkReady: true, language: "zh-Hant", servingSize: servingSize ?? reading.candidate.servingSize,
            servingsPerPack: reading.candidate.servingsPerPack, headers: headers, cells: cells, warnings: [])
        return LabelReading(origin: .pastedText, textSHA256: reading.textSHA256, candidate: candidate, format: reading.format,
            gate: reading.gate, checks: [], conversions: [boundedEnergy ? bound : F.kcal, F.sodium], storedHeaderID: "h2", versions: F.versions)
    }

    // MARK: QA D1

    func testWholePackSaysServingForOne() {
        XCTAssertEqual(PastedLabelText.wholePackTitle(1), "Whole pack (1 serving)")
        XCTAssertEqual(PastedLabelText.wholePackTitle(10), "Whole pack (10 servings)")
        XCTAssertEqual(PastedLabelText.wholePackTitle(2.5), "Whole pack (2.5 servings)")
    }

    // MARK: QA D2

    func testTheServingSizeEditDefaultsToThePrintedOrBasisUnit() throws {
        XCTAssertEqual(try F.source().servingSizeUnits, ["g", "ml"], "printed 30 g")
        XCTAssertEqual(try F.source(variant(servingSize: .some(nil))).servingSizeUnits.first, "g", "per 100 g, none printed")
        XCTAssertEqual(try F.source(variant(servingSize: .some(.init(printedText: "每一份量250毫升", decimalText: "250", unit: "毫升",
                                                                      canonicalUnit: "ml")))).servingSizeUnits.first, "ml", "printed in ml")
        let ml = try F.source(variant(basis: "per_100ml", servingSize: .some(nil)))
        XCTAssertEqual(ml.servingSizeUnits, ["ml", "g"], "per 100 ml, none printed")
        XCTAssertEqual(ml.servingLines.first?.units, ["ml", "g"], "the sheet opens on the line's first unit")

        // Entered in ml on a per 100 ml label: servings are offered under v2.
        let (confirm, _) = try F.confirm(ml)
        XCTAssertFalse(confirm.countsPastedLabelServings)
        // QA L2: the amount opens on the label's basis unit, with a hint in that unit.
        XCTAssertEqual(confirm.state.quantity.unit, .millilitres)
        XCTAssertEqual(confirm.originalAmountRequirement, "Enter the amount you had in mL, greater than zero.")
        XCTAssertNil(ml.setValue("serving_size", text: "250", unit: "ml"))
        XCTAssertEqual(ml.servingSizeUnits.first, "ml")
        // QA L3: shown as "mL"; the stored unit code stays "ml".
        XCTAssertEqual(ml.servingLines.first?.value, "250 mL · Entered by you")
        XCTAssertEqual(PastedLabelText.unitLabel("ml"), "mL")
        XCTAssertEqual(PastedLabelText.unitLabel("g"), "g")
        XCTAssertEqual(ml.manifest.corrections.first?.corrected.unit, "ml")
        XCTAssertTrue(confirm.countsPastedLabelServings)
        confirm.send(.setQuantity(2, .count))
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult, confirm.blockedReason ?? "")
        XCTAssertEqual(saved.quantityConversion?.methodVersion.value, "pasted-label-serving-v2")
        XCTAssertEqual(saved.logItemVersion.edibleQuantity, try PositiveQuantity(value: 500, unit: .millilitres))
    }

    // MARK: QA D3

    func testACalculatedEnergyBoundShowsAsABoundForTheAmountOnConfirm() throws {
        let source = try F.source(variant(boundedEnergy: true), conversions: BoundConversions())
        let (confirm, _) = try F.confirm(source, conversions: BoundConversions())
        confirm.send(.setQuantity(150, .grams))
        let review = confirm.nutritionReview
        XCTAssertTrue(review.isConsumed)
        let row = try XCTUnwrap(review.mainRows.first { $0.key == .energyConsumed })
        XCTAssertEqual(confirm.displayValue(.energyConsumed, row.value, consumed: confirm.consumedAmount(.energyConsumed, review),
                                            source: false), "Less than 7 kcal · Calculated", "4.1 kcal per 100 g × 150 g, rounded up")
        XCTAssertEqual(confirm.displayValue(.energyConsumed, "Unavailable"), "Less than 7 kcal · Calculated", "the consumed nutrition section")
        XCTAssertEqual(confirm.displayValue(.energyConsumed, "Less than 4.1 kcal", source: true), "Less than 5 kcal · Calculated",
                       "the source reference value")
        XCTAssertEqual(confirm.logButtonTitle, "Log", "the Log button states only a complete, exact energy")
        // An amount that cannot scale keeps its own wording and the tag; never zero.
        confirm.send(.setQuantity(150, .millilitres))
        XCTAssertEqual(confirm.displayValue(.energyConsumed, "Unavailable"), "Unavailable · Calculated")
    }

    func testACalculatedEnergyBoundShowsAsABoundWithEstimateOnTheFoodLogRow() throws {
        // Energy printed only as "<17 kJ" per 100 g: kcal is a calculated bound, < 4.1 kcal.
        let bound = PastedLabelManifest.Conversion(nutrient: "energy_kcal", rule: "kj_to_kcal_v1", ruleVersion: "pasted-label-conversions-v1",
            sourceHeaderID: "h2", sourceRowID: "熱量", operandText: "17", operandUnit: "kJ", factorText: "4.184",
            intermediateText: "4.063098", storedText: "4.1", comparator: "<", rounding: "outward")
        let reading = F.reading()
        let cells = reading.candidate.cells.map { cell in
            cell.headerID == "h2" && cell.nutrient == "energy_kj"
                ? F.cell("熱量", "energy_kj", "h2", "<17 kJ", "17", "kJ", comparator: "<") : cell
        }
        let candidate = PastedLabelManifest.Candidate(route: "A", inputSHA256: reading.candidate.inputSHA256, declined: false, declineReasons: [],
            wouldMarkReady: true, language: "zh-Hant", servingSize: reading.candidate.servingSize, servingsPerPack: reading.candidate.servingsPerPack,
            headers: reading.candidate.headers, cells: cells, warnings: [])
        let bounded = LabelReading(origin: .pastedText, textSHA256: reading.textSHA256, candidate: candidate, format: reading.format,
            gate: reading.gate, checks: [], conversions: [bound, F.sodium], storedHeaderID: "h2", versions: F.versions)
        let (confirm, store) = try F.confirm(try F.source(bounded, conversions: BoundConversions()), conversions: BoundConversions())
        confirm.send(.setQuantity(150, .grams))
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult, confirm.blockedReason ?? "")
        let records = try store.archiveState().records
        let content = FoodLogDayContent(projection: try FoodIntakeProjection(records: records, reportingDate: saved.logItemVersion.reportingDate.value),
                                        reportingDate: saved.logItemVersion.reportingDate.value, estimates: [])
        let entry = try XCTUnwrap(content.entries.first)
        XCTAssertNil(entry.energyKcal, "a bound is never an exact amount")
        XCTAssertEqual(try XCTUnwrap(entry.energyUpperBound?.kcal), 6.15, accuracy: 0.000_001, "4.1 kcal per 100 g × 150 g")
        XCTAssertTrue(entry.isEstimate, "a calculated bound is an estimate")
        XCTAssertEqual(FoodLogText.entryEnergy(entry, locale: Locale(identifier: "en_GB")), "Less than 7 kcal")
        XCTAssertTrue(FoodLogText.flags(entry).hasPrefix("Estimate"), FoodLogText.flags(entry))
        let total = try XCTUnwrap(content.totals?.first { $0.key == .energyConsumed })
        XCTAssertNil(total.knownAmount, "the day total is unchanged: the bound is not added")
        XCTAssertEqual(total.incompleteContributions, 1)

        // QA L1: the Recent row shows the same bound, an estimate because it is calculated.
        let recent = try XCTUnwrap(FoodRecentItemsProjection.items(records: records, now: F.now.addingTimeInterval(60),
                                                                   calendar: Calendar(identifier: .gregorian)).first)
        XCTAssertNil(recent.energyKcal)
        XCTAssertEqual(try XCTUnwrap(recent.energyUpperBound?.kcal), 6.15, accuracy: 0.000_001)
        let ledger = FoodLedgerService(actorID: try LedgerID("00000000-0000-0000-0000-00000000a000"), committer: store,
            clock: F.Clock(value: F.now), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let confirmations = FoodConfirmationService(ledger: ledger, reader: store, clock: F.Clock(value: F.now), ids: RandomLedgerIDGenerator(),
            digester: SHA256Digester(), pastedLabelConversions: BoundConversions())
        let relog = try XCTUnwrap(FoodRecentItemsService(reader: store, confirmations: confirmations)
            .items(records: records, now: F.now.addingTimeInterval(60), calendar: Calendar(identifier: .gregorian)).first)
        XCTAssertTrue(relog.isEstimate)
        let row = AddFoodRecentRowText(relog, now: F.now, calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(row.energy, "Less than 7 kcal")
        XCTAssertTrue(row.detail.hasPrefix("Estimate · "), row.detail)
        // Other sources: an upper-bound-only energy shows as a bound with no Estimate; nothing else changes.
        let other = FoodRecentItem(logItemID: recent.logItemID, sourceReleaseID: recent.sourceReleaseID, recordID: recent.recordID,
            occurredAt: F.now, lastAmount: try PositiveQuantity(value: 250, unit: .millilitres), energyKcal: nil,
            energyUpperBound: FoodEnergyUpperBound(kcal: 5, closed: true, isCalculated: false))
        let otherRow = AddFoodRecentRowText(FoodRecentRelogItem(item: other, name: "Synthetic tea", isEstimate: false),
                                            now: F.now, calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(otherRow.energy, "5 kcal or less")
        XCTAssertFalse(otherRow.detail.hasPrefix("Estimate"))
        let none = FoodRecentItem(logItemID: recent.logItemID, sourceReleaseID: recent.sourceReleaseID, recordID: recent.recordID,
            occurredAt: F.now, lastAmount: other.lastAmount, energyKcal: nil)
        XCTAssertNil(AddFoodRecentRowText(FoodRecentRelogItem(item: none, name: "x", isEstimate: false), now: F.now,
                                          calendar: Calendar(identifier: .gregorian)).energy)
    }

    /// The Food Log row's energy for bounds from any source (the formatter is shared): a closed
    /// upper bound that is not calculated reads "N kcal or less" with no Estimate; a lower-only
    /// bound, an open bound of 0 and an unscalable basis stay "Energy unknown".
    func testEnergyBoundsFromOtherSourcesOnTheFoodLogRow() throws {
        func entry(_ bounds: (lower: Double?, upper: Double?, closed: Bool), basis: ResolutionBasis = .per100Grams,
                   quantity: PositiveQuantity) throws -> FoodLogDayContent.Entry {
            let provenance = NutrientProvenance(sourceKind: .manualDeclaration, sourceID: try ExternalIdentifier("physical_package"),
                sourceReleaseID: try ExternalIdentifier("package:fixture-v1"), evidenceID: try RandomLedgerIDGenerator().makeID(EvidenceTag.self),
                capturedAt: F.now)
            let value = try NutrientBounds(lower: bounds.lower, upper: bounds.upper, lowerClosed: bounds.lower != nil, upperClosed: bounds.closed,
                origin: .measured, unit: .kilocalories, sourceValue: .bounded(SourceBoundedNutrientValue(lower: bounds.lower, upper: bounds.upper,
                    lowerClosed: bounds.lower != nil, upperClosed: bounds.closed, unit: LedgerText("kcal"), basis: .per100Grams)), provenance: [provenance])
            let nutrients = try NutrientSet(entries: NutrientKey.allCases.map {
                try NutrientEntry(key: $0, value: $0 == .energyConsumed ? .bounded(value) : .unknown(.notDeclared))
            })
            let contribution = FoodIntakeContribution(quantity: quantity, basis: basis, nutrients: nutrients)
            let bound = FoodEnergyUpperBound.of(contribution)
            return FoodLogDayContent.Entry(logItemID: try RandomLedgerIDGenerator().makeID(LogItemTag.self),
                logItemVersionID: try RandomLedgerIDGenerator().makeID(LogItemVersionTag.self), occurredAt: F.now, name: "Synthetic tea",
                quantity: quantity, energyKcal: nil, isEstimate: bound?.isCalculated == true, unknownKeys: [.energyConsumed],
                energyUpperBound: bound)
        }
        let en = Locale(identifier: "en_GB")
        let grams = try PositiveQuantity(value: 250, unit: .grams)
        let closed = try entry((nil, 2, true), quantity: grams)
        XCTAssertEqual(FoodLogText.entryEnergy(closed, locale: en), "5 kcal or less", "2 kcal per 100 g × 250 g")
        XCTAssertEqual(closed.energyUpperBound?.isCalculated, false)
        XCTAssertEqual(FoodLogText.flags(closed), "", "not calculated: no Estimate")
        XCTAssertEqual(FoodLogText.entryEnergy(try entry((nil, 2, false), quantity: grams), locale: en), "Less than 5 kcal")
        XCTAssertEqual(FoodLogText.entryEnergy(try entry((1, nil, false), quantity: grams), locale: en), "Energy unknown", "lower-only bound")
        XCTAssertEqual(FoodLogText.entryEnergy(try entry((nil, 0, false), quantity: grams), locale: en), "Energy unknown", "less than 0")
        XCTAssertEqual(FoodLogText.entryEnergy(try entry((nil, 2, false), quantity: PositiveQuantity(value: 250, unit: .millilitres)),
                                               locale: en), "Energy unknown", "per 100 g against millilitres cannot scale")
        XCTAssertEqual(FoodLogText.entryEnergy(try entry((nil, 2, false), basis: .unknown, quantity: grams), locale: en), "Energy unknown",
                       "unknown basis")
    }

    /// The presentation fixture's golden conversions plus the `<17 kJ` bound (17 ÷ 4.184 rounded up to 4.1).
    private struct BoundConversions: PastedLabelConversionChecking {
        func storedTextMatches(_ record: PastedLabelManifest.Conversion) -> Bool {
            if record.rule == "kj_to_kcal_v1" && record.operandText == "17" && record.comparator == "<" { return record.storedText == "4.1" }
            return F.Conversions().storedTextMatches(record)
        }
    }
}
