import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// count-portion-estimate-v1 (#307): Confirm pre-fills Large with a one-tap size choice, Change and
/// Use typical weight, "Log about", no save without Log; one count word; the method and estimate
/// after saving on the Food Log row, the saved entry and history.
@MainActor
final class CountPortionEstimatePresentationTests: XCTestCase {
    private static let boiledLarge = "count_portion_guide_v1:usda_sr_legacy_173424_92500"
    private static let boiledMedium = "count_portion_guide_v1:usda_sr_legacy_boiled_from_171287_88378"
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let locale = Locale(identifier: "en_GB")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    // MARK: Confirm

    func testConfirmPrefillsLargeAsALabelledEstimateAndNothingIsSavedWithoutLog() throws {
        let guides = try USDACountPortionGuides()
        var saves = 0
        let model = FoodConfirmationViewModel(state: try eggs(guides: guides), portionGuides: guides,
                                              now: { [now] in now }, calendar: calendar) { _ in
            saves += 1
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertTrue(model.showsPortionGuide)
        XCTAssertEqual(model.state.quantity.portionGuideCode?.value, Self.boiledLarge, "Large is pre-filled")
        XCTAssertEqual(model.portionGuideSet?.entries.map { FoodConfirmationView.portionGuideOption($0) },
                       ["Small, about 38 g each", "Medium, about 44 g each", "Large, about 50 g each", "Extra large, about 56 g each"])
        let total = try XCTUnwrap(model.portionGuideTotal)
        XCTAssertEqual(FoodConfirmationView.portionGuideTotal(total), "About 150 g")
        XCTAssertEqual(FoodConfirmationView.portionGuideSubtitle, "Typical weight · Estimate")
        XCTAssertTrue(model.requirements.isEmpty)
        XCTAssertTrue(model.canLog)
        XCTAssertTrue(model.quantityIsEstimate)
        XCTAssertTrue(model.logButtonTitle.hasPrefix("Log about "), model.logButtonTitle)
        XCTAssertEqual(saves, 0, "the pre-fill writes nothing (gate G4)")
        XCTAssertTrue(model.state.input.sourceReleases.contains { $0.sourceReleaseID == guides.sourceRelease.sourceReleaseID },
                      "the guide release is in the input whenever the size choice shows")

        model.selectPortionGuide(try LedgerText(Self.boiledMedium))
        XCTAssertEqual(model.portionGuideTotal, try PositiveQuantity(value: 132, unit: .grams))
        model.send(.setQuantity(4, .count))
        XCTAssertEqual(model.portionGuideTotal, try PositiveQuantity(value: 176, unit: .grams), "the total follows the count")
        XCTAssertEqual(saves, 0)
        model.log()
        XCTAssertEqual(saves, 1, "Log is the only save")
    }

    func testChangeOffersTheMeasuredFlowAndUseTypicalWeightRestoresTheLastSize() throws {
        let guides = try USDACountPortionGuides()
        let model = FoodConfirmationViewModel(state: try eggs(guides: guides), portionGuides: guides,
                                              now: { [now] in now }, calendar: calendar) { _ in throw CocoaError(.fileWriteUnknown) }
        model.selectPortionGuide(try LedgerText(Self.boiledMedium))
        model.changeTypicalWeight()
        XCTAssertFalse(model.showsPortionGuide)
        XCTAssertTrue(model.offersTypicalWeight)
        XCTAssertEqual(model.requirements, [.countNeedsMeasuredAmount])
        XCTAssertEqual(model.blockedReason, "Enter the total weight and choose how you got it, or change the unit to g or mL.")
        XCTAssertFalse(model.logButtonTitle.contains("about"), "no estimate while correcting")
        // Kitchen scale 120 g: measured, no "about".
        model.send(.setConversion(QuantityConversionDraft(convertedQuantity: try PositiveQuantity(value: 120, unit: .grams),
            methodVersion: try XCTUnwrap(CountConversionMethod.kitchenScale.storedCode))))
        XCTAssertTrue(model.requirements.isEmpty)
        XCTAssertTrue(model.showsCountMethodPicker, "the method shows once, in the picker, not also as a read-only row")
        XCTAssertFalse(model.quantityIsEstimate)
        XCTAssertFalse(model.logButtonTitle.contains("about"), model.logButtonTitle)
        model.useTypicalWeight()
        XCTAssertTrue(model.showsPortionGuide)
        XCTAssertEqual(model.state.quantity.portionGuideCode?.value, Self.boiledMedium, "back at the last size chosen")
        XCTAssertNil(model.state.quantity.conversion)
    }

    /// Journey QA D1 (PR #313): "2 eggs", the raw record, Change, 120 g, Kitchen scale. One layout:
    /// no "Enter measured weight" beside the count's weight row, and Log is enabled.
    func testChangeThenKitchenScaleOffersOneLayoutAndLogs() throws {
        let guides = try USDACountPortionGuides()
        var state = try eggs(name: "Eggs, chicken, whole, raw", guides: guides)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(2, .count))
        let model = FoodConfirmationViewModel(state: state, portionGuides: guides,
                                              now: { [now] in now }, calendar: calendar) { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertTrue(model.showsPortionGuide)
        XCTAssertFalse(model.offersEnterMeasuredWeight, "not beside the typical weight")
        model.changeTypicalWeight()
        XCTAssertFalse(model.offersEnterMeasuredWeight, "after Change the count's weight row is the one layout")
        let fields = FoodConfirmationView.ConversionFields(text: "120", unit: .grams, method: .choice(.kitchenScale))
        model.send(.setConversion(fields.draft(locale: locale)))
        XCTAssertFalse(model.offersEnterMeasuredWeight, "no second layout after Kitchen scale")
        XCTAssertTrue(model.showsCountMethodPicker)
        XCTAssertTrue(model.requirements.isEmpty, "\(model.requirements)")
        XCTAssertTrue(model.canLog)
        XCTAssertNil(model.blockedReason)
        XCTAssertFalse(model.logButtonTitle.contains("about"), model.logButtonTitle)
    }

    /// If the direct weight is entered another way while the count fields show 120 g, Kitchen scale,
    /// "Use original amount instead" applies those fields again (Log enabled); with empty fields the
    /// state is clearly blocked and says why. Visible state and requirements never disagree.
    func testUseOriginalAmountRestoresTheVisibleConversionOrBlocksClearly() throws {
        let guides = try USDACountPortionGuides()
        var state = try eggs(name: "Eggs, chicken, whole, raw", guides: guides)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(2, .count))
        let model = FoodConfirmationViewModel(state: state, portionGuides: guides,
                                              now: { [now] in now }, calendar: calendar) { _ in throw CocoaError(.fileWriteUnknown) }
        model.changeTypicalWeight()
        let fields = FoodConfirmationView.ConversionFields(text: "120", unit: .grams, method: .choice(.kitchenScale))
        model.send(.setConversion(fields.draft(locale: locale)))
        XCTAssertTrue(model.canLog)
        model.send(.beginDirectWeight)
        XCTAssertNil(model.state.quantity.conversion, "a direct weight replaces the conversion")
        XCTAssertFalse(model.canLog, "an empty direct weight is blocked")
        model.endDirectWeight(restoring: fields.draft(locale: locale))
        XCTAssertNil(model.state.quantity.directWeight)
        XCTAssertEqual(model.state.quantity.conversion?.convertedQuantity, try PositiveQuantity(value: 120, unit: .grams))
        XCTAssertEqual(model.state.quantity.conversion?.methodVersion, CountConversionMethod.kitchenScale.storedCode)
        XCTAssertEqual(model.state.quantity.value, 2, "the count is kept")
        XCTAssertTrue(model.requirements.isEmpty, "\(model.requirements)")
        XCTAssertTrue(model.canLog, "the 120 g and Kitchen scale shown are what Log saves")
        XCTAssertTrue(model.offersTypicalWeight)
        XCTAssertFalse(model.offersEnterMeasuredWeight)

        model.send(.beginDirectWeight)
        model.endDirectWeight(restoring: FoodConfirmationView.ConversionFields.cleared.draft(locale: locale))
        XCTAssertNil(model.state.quantity.conversion)
        XCTAssertFalse(model.canLog)
        XCTAssertEqual(model.blockedReason, "Enter the total weight and choose how you got it, or change the unit to g or mL.",
                       "empty fields: blocked, and the reason matches what is shown")
    }

    /// #318 item 1 and #303 item 4: after Change, a weight with no method. The Log bar names the
    /// missing method with the field's own sentence; with nothing entered it keeps the g or mL way out.
    func testLogBarNamesTheMissingCountFieldLikeTheField() throws {
        let guides = try USDACountPortionGuides()
        let model = FoodConfirmationViewModel(state: try eggs(guides: guides), portionGuides: guides,
                                              now: { [now] in now }, calendar: calendar) { _ in throw CocoaError(.fileWriteUnknown) }
        model.changeTypicalWeight()
        typealias Fields = FoodConfirmationView.ConversionFields
        let weightOnly = Fields(text: "168", unit: .grams, method: nil)
        XCTAssertEqual(model.requirements, [.countNeedsMeasuredAmount], "the rule is unchanged")
        XCTAssertEqual(model.blockedReason(countFields: weightOnly, locale: locale), "Choose how you got the weight.")
        XCTAssertEqual(model.blockedReason(countFields: weightOnly, locale: locale), weightOnly.requirementText(locale: locale),
                       "bar and field say the same thing")
        let methodOnly = Fields(text: "", unit: .grams, method: .choice(.kitchenScale))
        XCTAssertEqual(model.blockedReason(countFields: methodOnly, locale: locale), "Enter the total weight.")
        XCTAssertEqual(model.blockedReason(countFields: .cleared, locale: locale),
                       "Enter the total weight and choose how you got it, or change the unit to g or mL.")
        XCTAssertEqual(model.blockedReason(countFields: nil, locale: locale), model.blockedReason)
        XCTAssertFalse(model.canLog)
    }

    /// #318 items 2 and 3: a count with no guide (a fried egg, like a banana) shows one layout. No "Enter measured
    /// weight" beside the count's own weight fields; weighing on a plate opens the gram total with
    /// the count kept, and the direct weight's method uses the count picker's words.
    func testNoGuideCountShowsOneLayoutAndPlateOpensTheGramTotal() throws {
        let guides = try USDACountPortionGuides()
        var state = try eggs(name: "Eggs, chicken, whole, fried in sunflower oil", guides: guides)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(3, .count))
        let model = FoodConfirmationViewModel(state: state, portionGuides: guides,
                                              now: { [now] in now }, calendar: calendar) { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertFalse(model.showsPortionGuide)
        XCTAssertTrue(model.showsCountMethodPicker)
        XCTAssertFalse(model.offersEnterMeasuredWeight, "one layout: the count's weight fields")
        model.send(.setQuantity(nil, .count))
        XCTAssertEqual(model.originalAmountRequirement, "Enter an amount greater than zero.",
                       "the copy does not name a control that is not shown")
        model.send(.setQuantity(3, .count))

        model.beginCountPlateWeighing()
        XCTAssertNotNil(model.state.quantity.directWeight, "the plate needs a gram total")
        XCTAssertEqual(model.state.quantity.value, 3, "the count is kept as the original amount")
        XCTAssertFalse(model.showsCountMethodPicker)
        XCTAssertFalse(model.offersEnterMeasuredWeight, "journey QA D1 (PR #331): no disabled button on the plate path")
        model.send(.setPlateChoice(.missing))
        XCTAssertFalse(model.offersEnterMeasuredWeight, "still hidden once the plate is chosen")
        XCTAssertEqual(FoodConfirmationView.directWeightAccessibilityLabel(usesPlate: true), "Total food and plate weight in grams")
        XCTAssertEqual(FoodConfirmationView.directWeightAccessibilityLabel(usesPlate: false), "Total edible weight in grams")
        XCTAssertEqual(FoodConfirmationView.emptyPlateAccessibilityLabel, "Empty plate weight in grams")
        model.send(.setDirectWeight(500))
        XCTAssertEqual(model.blockedReason, "Choose how you got the weight.", "the same words as the count field")
        XCTAssertEqual(FoodConfirmationView.weightBasisLabel(.measured), "Kitchen scale")
        XCTAssertEqual(FoodConfirmationView.weightBasisLabel(.estimated), "Estimated by eye")
        model.send(.setWeightBasis(.measured))
        model.send(.setPlateChoice(.new(emptyWeight: try PositiveQuantity(value: 330, unit: .grams), superseding: nil)))
        XCTAssertTrue(model.requirements.isEmpty, "\(model.requirements)")
        XCTAssertTrue(model.canLog)

        // Not on a saved screen, and not for a gram amount.
        let grams = FoodConfirmationViewModel(state: try eggs(name: "Eggs, chicken, whole, fried in sunflower oil", guides: guides), portionGuides: guides,
                                              now: { [now] in now }, calendar: calendar) { _ in throw CocoaError(.fileWriteUnknown) }
        grams.chooseQuantityUnit(.grams)
        grams.beginCountPlateWeighing()
        XCTAssertNil(grams.state.quantity.directWeight)
        XCTAssertTrue(grams.offersEnterMeasuredWeight, "a gram amount keeps the measured weight route")
        grams.send(.beginDirectWeight)
        XCTAssertFalse(grams.offersEnterMeasuredWeight, "hidden while the direct weight it opens is on screen")
    }

    func testNoGuideOnGramsOrForAnotherFood() throws {
        let guides = try USDACountPortionGuides()
        var state = try eggs(guides: guides)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(150, .grams))
        let grams = FoodConfirmationViewModel(state: state, portionGuides: guides) { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertFalse(grams.showsPortionGuide)
        XCTAssertNil(grams.state.quantity.portionGuideCode)
        let fried = FoodConfirmationViewModel(state: try eggs(name: "Eggs, chicken, whole, fried in sunflower oil", guides: guides),
                                              portionGuides: guides) { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertNil(fried.portionGuideSet)
        XCTAssertFalse(fried.showsPortionGuide)
        XCTAssertEqual(fried.requirements, [.countNeedsMeasuredAmount])
        let none = FoodConfirmationViewModel(state: try eggs(guides: guides)) { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertFalse(none.showsPortionGuide, "no port, no guide")
    }

    func testAWithdrawnGuideKeepsAnUnchangedReopenedEntryAndAsksForAWeightAfterACountChange() throws {
        let guides = try USDACountPortionGuides()
        let (service, _) = try services(guides: guides)
        var state = try eggs(guides: guides)
        FoodConfirmationReducer.reduce(state: &state, action: .setPortionGuide(try LedgerText(Self.boiledLarge)))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: LedgerID("00000000-0000-0000-0000-000000000701"))
        let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
        let model = FoodConfirmationViewModel(state: reopened, portionGuides: NoGuides(release: guides.sourceRelease),
                                              now: { [now] in now }, calendar: calendar) { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertTrue(model.showsPortionGuide, "the stored size is kept while nothing changes")
        XCTAssertTrue(model.requirements.isEmpty)
        model.send(.setQuantity(4, .count))
        XCTAssertFalse(model.showsPortionGuide)
        XCTAssertEqual(model.requirements, [.countNeedsMeasuredAmount])
    }

    // MARK: One count word

    func testOneCountWordEverywhere() throws {
        XCTAssertEqual(FoodLogText.amount(try PositiveQuantity(value: 1, unit: .count), locale: locale), "1 piece")
        XCTAssertEqual(FoodLogText.amount(try PositiveQuantity(value: 3, unit: .count), locale: locale), "3 pieces")
        XCTAssertEqual(FoodAmountNoun.count(1), "piece")
        XCTAssertEqual(FoodAmountNoun.count(0.5), "pieces")
        XCTAssertEqual(FoodAmountNoun.servings(2), "servings")
        XCTAssertEqual(FoodAmountNoun.countUnitLabel, "pieces")
        XCTAssertEqual(FoodAmountNoun.unit(.count, value: 2), "pieces")
        XCTAssertEqual(FoodAmountNoun.unit(.millilitres, value: 2), "mL")
        XCTAssertEqual(FoodAmountNoun.unit(.grams, value: 2), "g")
    }

    /// Gate F5: no user-facing count word or raw quantity unit outside the one noun function.
    func testSourcesUseTheOneCountNoun() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let directories = ["Packages/FoodLedgerKit/Sources/FoodLedgerPresentation", "WeeklyHealthReport/FoodLedger"]
        var files = try directories.flatMap { directory in
            try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
        }
        files += try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Packages/FoodLedgerKit/Sources/FoodLedgerApplication"), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("Presentation") && $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 20)
        // Data, not copy: the parsed and stored `count`, named here.
        let dataUses = [#"units: ["count"]"#, #"== "count""#, #"["g", "ml", "count"]"#, #".tag("count")"#]
        let nutrientReceivers: Set<String> = ["value", "v", "exact", "bounds"]
        let literal = try NSRegularExpression(pattern: #""(count|unit|units)""#)
        let rawUnit = try NSRegularExpression(pattern: #"([A-Za-z_][A-Za-z0-9_]*)[!?]?\.unit\.rawValue"#)
        var offences: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if !literal.matches(in: line, range: range).isEmpty, !dataUses.contains(where: line.contains) {
                    offences.append("\(file.lastPathComponent):\(number + 1)")
                }
                for match in rawUnit.matches(in: line, range: range) {
                    let receiver = String(line[Range(match.range(at: 1), in: line)!])
                    if !nutrientReceivers.contains(receiver) { offences.append("\(file.lastPathComponent):\(number + 1) .unit.rawValue") }
                }
            }
        }
        XCTAssertEqual(offences, [])
    }

    // MARK: After saving

    func testAmountLinesMethodLabelsAndHistory() throws {
        let large = FoodQuantityMethod.typicalWeight(size: .large, gramsEach: 50)
        let three = try PositiveQuantity(value: 3, unit: .count), four = try PositiveQuantity(value: 4, unit: .count)
        let g150 = try PositiveQuantity(value: 150, unit: .grams), g120 = try PositiveQuantity(value: 120, unit: .grams)
        XCTAssertEqual(FoodLogText.amountLine(entered: three, edible: g150, isServings: false, method: large, locale: locale), "3 pieces · about 150 g")
        XCTAssertEqual(FoodLogText.amountLine(entered: three, edible: g150, isServings: false, method: .estimatedByEye, locale: locale), "3 pieces · about 150 g")
        XCTAssertEqual(FoodLogText.amountLine(entered: three, edible: g150, isServings: false, method: .kitchenScale, locale: locale), "3 pieces · 150 g")
        XCTAssertEqual(FoodLogText.amountLine(entered: g150, edible: g150, isServings: false, method: .direct, locale: locale), "150 g")
        XCTAssertEqual(FoodLogText.amountLine(entered: try PositiveQuantity(value: 200, unit: .millilitres),
                                              edible: try PositiveQuantity(value: 206, unit: .grams), isServings: false,
                                              method: .wholeMilkVolume, locale: locale), "200 mL · about 206 g")
        XCTAssertEqual(FoodLogText.amountLine(entered: try PositiveQuantity(value: 2, unit: .count),
                                              edible: try PositiveQuantity(value: 60, unit: .grams), isServings: true,
                                              method: .direct, locale: locale), "2 servings · 60 g")
        let labels: [(FoodQuantityMethod, String?)] = [(large, "Typical weight"), (.estimatedByEye, "Estimated by eye"),
            (.kitchenScale, "Kitchen scale"), (.packageWeight, "Package weight"), (.weighed, "Kitchen scale"),
            (.wholeMilkVolume, "Whole milk volume estimate"), (.recorded("on the scale"), "Recorded: on the scale"), (.direct, nil)]
        for (method, label) in labels { XCTAssertEqual(FoodLogText.methodLabel(method), label) }
        XCTAssertEqual(FoodLogText.methodDetail(large, locale: locale), "Typical weight, Large, about 50 g each")

        func history(_ change: FoodEntryHistoryEvent.AmountChange) -> String {
            FoodLogText.history(.changed(amount: change, time: nil), now: now, calendar: calendar, locale: locale)
        }
        XCTAssertEqual(history(.init(from: three, to: four, edibleFrom: g150, edibleTo: try PositiveQuantity(value: 200, unit: .grams),
                                     methodFrom: large, methodTo: large)),
                       "Amount changed 3 pieces to 4 pieces (about 150 g to about 200 g)")
        XCTAssertEqual(history(.init(from: three, to: three, edibleFrom: g150, edibleTo: try PositiveQuantity(value: 132, unit: .grams),
                                     methodFrom: large, methodTo: .typicalWeight(size: .medium, gramsEach: 44))),
                       "Weight changed about 150 g to about 132 g · now Medium")
        XCTAssertEqual(history(.init(from: three, to: three, edibleFrom: g150, edibleTo: g120, methodFrom: large, methodTo: .kitchenScale)),
                       "Weight changed about 150 g to 120 g · now Kitchen scale")
        XCTAssertEqual(history(.init(from: three, to: three, edibleFrom: g150, edibleTo: g120,
                                     methodFrom: .estimatedByEye, methodTo: .estimatedByEye)),
                       "Weight changed about 150 g to about 120 g")
        XCTAssertFalse(history(.init(from: three, to: three, edibleFrom: g150, edibleTo: g120)).contains("3 pieces to 3 pieces"))
        // #318: a direct weighed amount reads "Kitchen scale" too, so switching names no change.
        XCTAssertEqual(history(.init(from: three, to: three, edibleFrom: g150, edibleTo: g120,
                                     methodFrom: .kitchenScale, methodTo: .weighed)),
                       "Weight changed 150 g to 120 g")
        XCTAssertEqual(history(.init(from: three, to: three, edibleFrom: g150, edibleTo: g120,
                                     methodFrom: .weighed, methodTo: .estimatedByEye)),
                       "Weight changed 150 g to about 120 g · now Estimated by eye")
    }

    /// #303: a number never wraps away from its unit at accessibility sizes; nothing else changes.
    func testKeepingUnitsAttachedJoinsOnlyNumberAndUnit() {
        let nbsp = "\u{00A0}"
        XCTAssertEqual(FoodLogText.keepingUnitsAttached("3 pieces · about 168 g"), "3\(nbsp)pieces · about 168\(nbsp)g")
        XCTAssertEqual(FoodLogText.keepingUnitsAttached("1 piece · 200 mL · 1 serving · 2 servings · 215 kcal"),
                       "1\(nbsp)piece · 200\(nbsp)mL · 1\(nbsp)serving · 2\(nbsp)servings · 215\(nbsp)kcal")
        XCTAssertEqual(FoodLogText.keepingUnitsAttached("1,5 g and 12.5 g"), "1,5\(nbsp)g and 12.5\(nbsp)g")
        XCTAssertEqual(FoodLogText.keepingUnitsAttached("Less than 3 kcal"), "Less than 3\(nbsp)kcal")
        XCTAssertEqual(FoodLogText.keepingUnitsAttached("3 grapes, 2 go"), "3 grapes, 2 go", "only whole unit words")
        XCTAssertEqual(FoodLogText.keepingUnitsAttached("Eggs, boiled"), "Eggs, boiled")
    }

    func testSavedEntryAndFoodLogRowShowTheEstimateAndMethod() throws {
        let guides = try USDACountPortionGuides()
        let (service, store) = try services(guides: guides)
        var state = try eggs(guides: guides)
        FoodConfirmationReducer.reduce(state: &state, action: .setPortionGuide(try LedgerText(Self.boiledLarge)))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: LedgerID("00000000-0000-0000-0000-000000000702"))
        let detail = SavedFoodEntryDetail(stored: saved, isEstimate: try service.isEstimate(saved), history: [])
        XCTAssertEqual(FoodLogText.savedAmount(detail, locale: locale), "3 pieces · about 150 g")
        let header = try XCTUnwrap(FoodLogText.headerEstimate(detail, locale: locale))
        XCTAssertTrue(header.hasPrefix("Estimate · Typical weight, Large, about 50 g each"), header)
        let records = try store.archiveState().records
        let projection = try FoodIntakeProjection(records: records, reportingDate: saved.logItemVersion.reportingDate.value)
        let day = FoodLogDayContent(projection: projection, reportingDate: saved.logItemVersion.reportingDate.value, estimates: [])
        let entry = try XCTUnwrap(day.entries.first)
        XCTAssertEqual(FoodLogText.entryAmount(entry, locale: locale), "3 pieces · about 150 g")
        XCTAssertTrue(FoodLogText.flags(entry).hasPrefix("Estimate · Typical weight"), FoodLogText.flags(entry))
        XCTAssertTrue(day.totals?.first { $0.key == .energyConsumed }?.includesEstimates == true)
    }

    // MARK: Invariant review of 89ba348f

    func testServingsReadServingsWithOrWithoutAWeight() throws {
        let two = try PositiveQuantity(value: 2, unit: .count), three = try PositiveQuantity(value: 3, unit: .count)
        XCTAssertEqual(FoodLogText.amountLine(entered: two, edible: two, isServings: true, method: .direct, locale: locale), "2 servings")
        XCTAssertEqual(FoodLogText.amountLine(entered: two, edible: two, isServings: false, method: .direct, locale: locale), "2 pieces")
        let change = FoodEntryHistoryEvent.AmountChange(from: two, to: three, edibleFrom: nil, edibleTo: nil, isServings: true)
        XCTAssertEqual(FoodLogText.history(.changed(amount: change, time: nil), now: now, calendar: calendar, locale: locale),
                       "Amount changed 2 servings to 3 servings")
    }

    func testAReopenedCorrectedEggOffersUseTypicalWeight() throws {
        let guides = try USDACountPortionGuides()
        let (service, _) = try services(guides: guides)
        // Kitchen scale.
        var scale = try eggs(guides: guides)
        FoodConfirmationReducer.reduce(state: &scale, action: .setConversion(QuantityConversionDraft(
            convertedQuantity: try PositiveQuantity(value: 160, unit: .grams),
            methodVersion: try XCTUnwrap(CountConversionMethod.kitchenScale.storedCode))))
        FoodConfirmationReducer.reduce(state: &scale, action: .accept)
        let scaleSaved = try service.save(scale, operationID: LedgerID("00000000-0000-0000-0000-000000000711"))
        // Estimated by eye.
        var eye = try eggs(guides: guides)
        FoodConfirmationReducer.reduce(state: &eye, action: .beginDirectWeight)
        FoodConfirmationReducer.reduce(state: &eye, action: .setDirectWeight(140))
        FoodConfirmationReducer.reduce(state: &eye, action: .setWeightBasis(.estimated))
        FoodConfirmationReducer.reduce(state: &eye, action: .accept)
        let eyeSaved = try service.save(eye, operationID: LedgerID("00000000-0000-0000-0000-000000000712"))
        for (name, saved) in [("kitchen scale", scaleSaved), ("estimated by eye", eyeSaved)] {
            let model = FoodConfirmationViewModel(state: try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID)),
                                                  portionGuides: guides, now: { [now] in now }, calendar: calendar) { _ in
                throw CocoaError(.fileWriteUnknown)
            }
            XCTAssertFalse(model.showsPortionGuide, name)
            XCTAssertTrue(model.offersTypicalWeight, name)
            XCTAssertFalse(model.offersEnterMeasuredWeight, name)
            XCTAssertTrue(model.requirements.isEmpty, "\(name): \(model.requirements)")
            model.useTypicalWeight()
            XCTAssertTrue(model.showsPortionGuide, name)
        }
    }

    func testAMeasuredMethodIsNamedWhenOnlyTheSourceIsAnEstimate() throws {
        let guides = try USDACountPortionGuides()
        let (service, _) = try services(guides: guides)
        var state = try eggs(guides: guides)
        FoodConfirmationReducer.reduce(state: &state, action: .setConversion(QuantityConversionDraft(
            convertedQuantity: try PositiveQuantity(value: 160, unit: .grams),
            methodVersion: try XCTUnwrap(CountConversionMethod.kitchenScale.storedCode))))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: LedgerID("00000000-0000-0000-0000-000000000713"))
        let detail = SavedFoodEntryDetail(stored: saved, isEstimate: try service.isEstimate(saved), history: [])
        XCTAssertTrue(detail.isEstimate, "the CoFID egg is a generic estimate")
        XCTAssertEqual(FoodLogText.headerEstimate(detail, locale: locale), "Estimate · Unknown details stay unknown · Kitchen scale")
        XCTAssertEqual(FoodLogText.savedAmount(detail, locale: locale), "3 pieces · 160 g")
    }

    // MARK: Fixtures

    private func services(guides: USDACountPortionGuides) throws -> (FoodConfirmationService, InMemoryFoodLedgerStore) {
        struct Clock: LedgerClock { let value: Date; func now() -> Date { value } }
        let store = InMemoryFoodLedgerStore()
        let ledger = FoodLedgerService(actorID: try LedgerID("00000000-0000-0000-0000-000000000999"), committer: store,
            clock: Clock(value: now), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        return (FoodConfirmationService(ledger: ledger, reader: store, clock: Clock(value: now), ids: PortionIDs(),
                                        digester: SHA256Digester(), calendar: calendar, portionGuides: guides), store)
    }

    /// Three pieces of a CoFID egg record, with the guide release added as the composition root adds it.
    private func eggs(name: String = "Eggs, chicken, whole, boiled", guides: USDACountPortionGuides) throws -> FoodConfirmationState {
        let search = try CoFIDGenericFoodSearch(ids: PortionIDs(seed: 40_000))
        let words = name.replacingOccurrences(of: ",", with: "").split(separator: " ")
        for query in [words.joined(separator: " "), "\(words.last ?? "") egg", "fried egg", "boiled egg"] {
            let request = GenericFoodSearchRequest(text: try LedgerText(query), identity: GenericFoodIdentityQuery(),
                                                   capturedAt: now, locale: try LedgerText("en_GB"))
            guard case let .confirmation(route) = try search.search(request),
                  let egg = route.matches.first(where: { $0.candidate.name.value == name })?.candidate else { continue }
            let input = try PopulatedFoodConfirmation(evidence: route.confirmation.evidence,
                sourceReleases: route.confirmation.sourceReleases + [guides.sourceRelease], candidates: [egg],
                expectedIdentity: egg.candidate.identity, expectedEdibleQuantity: egg.candidate.edibleQuantity)
            var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(3, .count))
            return state
        }
        throw XCTSkip("Expected the CoFID record \(name)")
    }
}

private struct NoGuides: FoodEdibleWeightGuideProviding {
    let release: SourceRelease
    var sourceRelease: SourceRelease { release }
    func guide(for candidate: PopulatedFoodCandidate) throws -> FoodEdibleWeightGuideSet? { nil }
}

private final class PortionIDs: LedgerIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    init(seed: Int = 30_000) { value = seed }
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
