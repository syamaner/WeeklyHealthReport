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
        XCTAssertEqual(model.blockedReason, "Enter the total weight and how you got it, or change the unit to g or mL.")
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
            (.kitchenScale, "Kitchen scale"), (.packageWeight, "Package weight"), (.weighed, "Weighed"),
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
