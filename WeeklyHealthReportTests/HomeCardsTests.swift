import PDFKit
import SwiftUI
import UIKit
import XCTest
import FoodLedgerApplication
import FoodLedgerDomain
@testable import WeeklyHealthReport

// UX revamp phase 6 (#199): Home composition, cards, VoiceOver labels and
// hosted native renders. Every value is a synthetic fixture.
@MainActor
final class HomeCardsTests: XCTestCase {
    // MARK: Composition

    func testCardsRenderInWireframeOrderWhateverTheFeatureOrder() {
        let features = [
            NotesHomeCard.feature(controller: DailyNotesController(store: EmptyDailyNotesStore(), calendar: calendar)),
            TodaySoFarHealthCardView.feature(model: healthModel(), readsHealthData: false),
            FoodHomeCards.feature(model: FoodHomeModel(root: nil))
        ]
        XCTAssertEqual(HomeView.orderedCards(features).map(\.id), [.food, .addFood, .quickAdd, .healthToday, .notes])
        XCTAssertEqual(HomeCardID.allCases, [.food, .addFood, .quickAdd, .healthToday, .notes])
    }

    /// A new health highlight is a contribution, not a Home edit: a stub card in
    /// the health slot renders through the unchanged `HomeView` and `HomeCardID`.
    func testStubHealthHighlightRendersWithoutChangingHome() {
        let stub = HomeFeature(cards: [
            HomeCard(id: .healthToday) { _ in AnyView(Section("Stub highlight") { Text("Synthetic value") }) }
        ])
        let features = [FoodHomeCards.feature(model: FoodHomeModel(root: nil)), stub]
        XCTAssertEqual(HomeView.orderedCards(features).map(\.id), [.food, .addFood, .quickAdd, .healthToday])
        render(NavigationStack { HomeView(features: features, now: { self.asOf }, calendar: self.calendar) },
               name: "Home - stub highlight")
    }

    func testHealthTriggerMapsEveryHomeTrigger() {
        XCTAssertEqual(TodaySoFarHealthCardView.trigger(for: .appeared), .homeAppeared)
        XCTAssertEqual(TodaySoFarHealthCardView.trigger(for: .becameActive), .becameActive)
        XCTAssertEqual(TodaySoFarHealthCardView.trigger(for: .calendarDayChanged), .calendarDayChanged)
        XCTAssertEqual(TodaySoFarHealthCardView.trigger(for: .significantTimeChange), .significantTimeChange)
        XCTAssertEqual(TodaySoFarHealthCardView.trigger(for: .pullToRefresh), .pullToRefresh)
    }

    /// Hosted unit tests skip the Health card's read entirely, as the shell skips
    /// its report refresh: no Health sheet and no HealthKit query (#218).
    func testHealthFeatureSkipsReadsAndAuthorisationWhenHealthDataIsNotRead() async {
        let reader = FakeTodaySoFarReader()
        let authorizer = FakeReadAuthorizer()
        let skipped = TodaySoFarHealthCardView.feature(model: healthModel(reader: reader, authorizer: authorizer), readsHealthData: false)
        for trigger in [HomeRefreshTrigger.appeared, .becameActive, .calendarDayChanged, .significantTimeChange, .pullToRefresh] {
            await skipped.refresh(trigger)
        }
        XCTAssertTrue(reader.windows.isEmpty)
        XCTAssertEqual(authorizer.requestCount, 0)

        let reading = TodaySoFarHealthCardView.feature(model: healthModel(reader: reader, authorizer: authorizer), readsHealthData: true)
        await reading.refresh(.appeared)
        XCTAssertEqual(reader.windows.count, 1)
        XCTAssertEqual(authorizer.requestCount, 1)
    }

    func testHeaderUsesTheInjectedCalendar() {
        XCTAssertEqual(HomeView.header(asOf, calendar: calendar, locale: Locale(identifier: "en_GB")), "Monday 12 October")
    }

    // MARK: Food card

    func testEmptyFoodLogIsNotZero() {
        XCTAssertEqual(FoodHomeCardContent.make(itemCount: 0, totals: [], plainWater: nil, incompleteEntries: 0), .empty)
        XCTAssertEqual(FoodHomeCardContent.emptyMessage, "Nothing logged yet today")
    }

    func testLoggedFoodShowsKnownMinimumFootnoteAndPlainWater() throws {
        let gb = Locale(identifier: "en_GB")
        let totals = [
            total(.energyConsumed, 1240.4), total(.protein, 68), total(.carbohydrates, 150.5),
            total(.fatTotal, 41, incomplete: 1)
        ]
        let water = FoodIntakeTotal(key: .water, knownAmount: 730, incompleteContributions: 0, includesEstimates: false)
        guard case .logged(let logged) = FoodHomeCardContent.make(itemCount: 3, totals: totals, plainWater: water, locale: gb, incompleteEntries: 1) else {
            return XCTFail("Expected a logged card")
        }
        XCTAssertEqual(logged.energy.value, "1,240 kcal")
        XCTAssertEqual(logged.entryCount, "3 entries")
        XCTAssertEqual(logged.nutrients.map(\.value), ["68 g", "150.5 g", "41 g+"])
        XCTAssertEqual(logged.footnote, "Some values are unknown for 1 entry, so totals marked + are known minimums.")
        XCTAssertEqual(logged.water.label, "Plain water logged")
        XCTAssertEqual(logged.water.value, "730 mL")
        XCTAssertEqual(logged.energy.accessibilityLabel, "Energy, 1,240 kilocalories")
        XCTAssertEqual(logged.nutrients[2].accessibilityLabel, "Fat, at least 41 grams")
        XCTAssertEqual(logged.water.accessibilityLabel, "Plain water logged, 730 millilitres")

        guard case .logged(let noWater) = FoodHomeCardContent.make(itemCount: 1, totals: [total(.energyConsumed, 200)],
                                                                    plainWater: nil, locale: gb, incompleteEntries: 0) else { return XCTFail("logged") }
        XCTAssertEqual(noWater.water.value, "No data", "no plain water is No data, never 0 mL")
        XCTAssertNil(noWater.footnote)
        XCTAssertEqual(noWater.nutrients.map(\.value), ["Unknown", "Unknown", "Unknown"])
    }

    /// Several known minimums still make one short line (owner decision F), not one sentence per
    /// nutrient; the count is of distinct entries when the rows are known.
    func testSeveralKnownMinimumsShareOneLine() throws {
        let gb = Locale(identifier: "en_GB")
        let totals = [
            total(.energyConsumed, 726, incomplete: 1), total(.protein, 30, incomplete: 1),
            total(.carbohydrates, 89.4, incomplete: 1), total(.fatTotal, 20, incomplete: 1)
        ]
        let water = FoodIntakeTotal(key: .water, knownAmount: 370.5, incompleteContributions: 1, includesEstimates: false)
        guard case .logged(let logged) = FoodHomeCardContent.make(itemCount: 5, totals: totals, plainWater: water, locale: gb,
                                                                  incompleteEntries: 1) else {
            return XCTFail("Expected a logged card")
        }
        XCTAssertEqual(logged.footnote, "Some values are unknown for 1 entry, so totals marked + are known minimums.")
        XCTAssertEqual(logged.footnote?.filter { $0 == "." }.count, 1, "one sentence")
        XCTAssertEqual(logged.energy.value, "726 kcal+", "values are unchanged")

        guard case .logged(let counted) = FoodHomeCardContent.make(itemCount: 5, totals: totals, plainWater: water, locale: gb,
                                                                   incompleteEntries: 2) else { return XCTFail("logged") }
        XCTAssertEqual(counted.footnote, "Some values are unknown for 2 entries, so totals marked + are known minimums.",
                       "the count is the distinct entries passed in, never the per-total maximum")

        let unknownOnly = [total(.energyConsumed, 200), FoodIntakeTotal(key: .fatTotal, knownAmount: nil, incompleteContributions: 1, includesEstimates: false)]
        guard case .logged(let none) = FoodHomeCardContent.make(itemCount: 1, totals: unknownOnly, plainWater: nil, locale: gb, incompleteEntries: 1) else {
            return XCTFail("logged")
        }
        XCTAssertEqual(none.footnote, "Some values are unknown for 1 entry.", "no total is marked +, so none is called a minimum")
    }

    /// Distinct entries: one entry missing fat and protein counts once; a second missing only
    /// energy makes two; complete rows never count.
    func testIncompleteEntriesCountsDistinctEntries() {
        let complete = [total(.energyConsumed, 100), total(.protein, 5), total(.carbohydrates, 10), total(.fatTotal, 3)]
        let missingTwo = [total(.energyConsumed, 100), total(.protein, 0, incomplete: 1), total(.carbohydrates, 10), total(.fatTotal, 0, incomplete: 1)]
        let missingEnergy = [total(.energyConsumed, 0, incomplete: 1), total(.protein, 5), total(.carbohydrates, 10), total(.fatTotal, 3)]
        let day = [total(.energyConsumed, 200, incomplete: 1), total(.protein, 10, incomplete: 1),
                   total(.carbohydrates, 30), total(.fatTotal, 6, incomplete: 1)]
        XCTAssertEqual(FoodHomeCardContent.incompleteEntries([complete, missingTwo, missingEnergy], dayTotals: day, plainWater: nil), 2)
        XCTAssertEqual(FoodHomeCardContent.incompleteEntries([complete, missingTwo], dayTotals: day, plainWater: nil), 1)
        let water = FoodIntakeTotal(key: .water, knownAmount: 250, incompleteContributions: 3, includesEstimates: false)
        XCTAssertEqual(FoodHomeCardContent.incompleteEntries([complete], dayTotals: day, plainWater: water), 3)
    }

    /// Review fix: the Food Log's "Includes estimates" caption also shows on Home.
    func testEstimatedTotalsKeepTheirCaption() throws {
        let gb = Locale(identifier: "en_GB")
        let totals = [
            FoodIntakeTotal(key: .energyConsumed, knownAmount: 300, incompleteContributions: 0, includesEstimates: true),
            FoodIntakeTotal(key: .protein, knownAmount: 12, incompleteContributions: 0, includesEstimates: true),
            total(.carbohydrates, 40), total(.fatTotal, 9)
        ]
        guard case .logged(let logged) = FoodHomeCardContent.make(itemCount: 2, totals: totals, plainWater: nil, locale: gb, incompleteEntries: 0) else {
            return XCTFail("Expected a logged card")
        }
        XCTAssertEqual(logged.energy.caption, "Includes estimates")
        XCTAssertEqual(logged.nutrients.map(\.caption), ["Includes estimates", nil, nil])
        XCTAssertEqual(logged.energy.accessibilityLabel, "Energy, 300 kilocalories, includes estimates")
        XCTAssertEqual(logged.nutrients[0].accessibilityLabel, "Protein, 12 grams, includes estimates")
        XCTAssertNil(logged.water.caption)
        let model = FoodHomeModel(root: nil)
        for size in [DynamicTypeSize.large, .accessibility3] {
            render(NavigationStack { Form { FoodHomeCard(model: model) }.environment(\.dynamicTypeSize, size) },
                   name: "Home food - unavailable - \(size)")
        }
    }

    func testFoodModelWithoutLedgerIsUnavailableNotEmpty() {
        let model = FoodHomeModel(root: nil)
        model.reload()
        XCTAssertEqual(model.state, .unavailable)
        guard case .unavailable = model.quickAdd else { return XCTFail("quick add hidden without a ledger") }
    }

    // MARK: Notes card

    func testNotesCountCopy() {
        XCTAssertEqual(NotesHomeCard.countLabel(0), "None yet")
        XCTAssertEqual(NotesHomeCard.countLabel(1), "1 note")
        XCTAssertEqual(NotesHomeCard.countLabel(4), "4 notes")
        XCTAssertEqual(NotesHomeCard.title, "Today\u{2019}s notes")
    }

    // MARK: Health link

    /// Owner decision F: a plain header and one "Health summaries" row with "Completed days".
    func testHealthCardLinksReadAsHealthSummaries() {
        XCTAssertEqual(TodaySoFarHealthCardView.title, "Health · today so far")
        XCTAssertEqual(TodaySoFarHealthCardView.linkTitle, "Health summaries")
        XCTAssertEqual(TodaySoFarHealthCardView.linkSubtitle, "Completed days")
        XCTAssertEqual(TodaySoFarHealthCardView.healthHint, "Opens the Health summaries for completed days")
    }

    // MARK: Today's Full Page

    func testTodayFullPageListsEveryCardWithContentInCardOrder() async throws {
        let notes = DailyNotesController(store: EmptyDailyNotesStore(), calendar: calendar, now: { self.asOf })
        XCTAssertTrue(notes.beginNewDraft())
        XCTAssertTrue(notes.updateDraftText("Synthetic note"))
        XCTAssertTrue(notes.saveDraft())
        let health = healthModel(inputs: TodaySoFarHealthInputs(
            steps: .value(DailyStepTotal(day: try XCTUnwrap(TodaySoFarWindow.capture(at: asOf, calendar: calendar)).day,
                                         steps: 6412, sourceNames: ["Synthetic phone"])),
            activeEnergyKilocalories: .noData, asleepIntervals: .noData, weights: .noData, bloodPressure: .noData))
        await health.handle(.pullToRefresh)
        let features = [
            NotesHomeCard.feature(controller: notes),
            TodaySoFarHealthCardView.feature(model: health, readsHealthData: false),
            FoodHomeCards.feature(model: FoodHomeModel(root: nil))
        ]

        let document = HomeView.fullPageDocument(features, today: asOf, calendar: calendar, locale: Locale(identifier: "en_GB"))

        XCTAssertEqual(document.date, "Monday 12 October")
        // Add food is only a control and quick add is hidden without a ledger.
        XCTAssertEqual(document.sections.map(\.title), ["Food logged", "Health · today so far", "Today\u{2019}s notes"])
        XCTAssertEqual(document.sections[0].rows, [.init(value: FoodHomeCardContent.unavailableMessage)])
        let healthSection = document.sections[1]
        XCTAssertEqual(healthSection.rows.map(\.label), ["Steps", "Active energy", "Sleep", "Weight", "Blood pressure"])
        // The card formats with the device locale; the rows and footer are the card's own strings.
        XCTAssertTrue(healthSection.rows[0].value.hasSuffix(" so far"), healthSection.rows[0].value)
        XCTAssertTrue(healthSection.footer?.contains(HealthReportFormatter.todaySoFarFooter) == true)
        XCTAssertTrue(healthSection.footer?.contains("As of ") == true, healthSection.footer ?? "")
        XCTAssertEqual(document.sections[2].rows, [.init(value: "1 note")])
    }

    /// Review fix: Today's Full Page is dated with the day of Home's last
    /// refresh (the header's day), not a later clock reading.
    func testHomeReportsItsRefreshedDayForTheFullPageDate() throws {
        var clock = asOf
        var reported: [Date] = []
        let controller = WeeklyReportScreenshotController()
        let view = NavigationStack {
            HomeView(features: [], now: { clock }, calendar: self.calendar, dayRefreshed: { day in
                reported.append(day)
                controller.todayRefreshedDay = day
            })
        }
        render(view, name: "Home - refreshed day")
        let deadline = Date().addingTimeInterval(2)
        while reported.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(reported.first, asOf)

        clock = date(13, 0, 5)  // after midnight, before Home refreshes again
        let day = try XCTUnwrap(controller.todayRefreshedDay)
        let document = HomeView.fullPageDocument([], today: day, calendar: calendar, locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(document.date, "Monday 12 October")
        XCTAssertEqual(document.date, HomeView.header(asOf, calendar: calendar, locale: Locale(identifier: "en_GB")))
    }

    /// The Full Page reads the cards' current content each time it is built.
    func testTodayFullPageFollowsTheCurrentCardContent() {
        let notes = DailyNotesController(store: EmptyDailyNotesStore(), calendar: calendar, now: { self.asOf })
        let features = [NotesHomeCard.feature(controller: notes)]
        XCTAssertEqual(HomeView.fullPageDocument(features, today: asOf, calendar: calendar).sections[0].rows,
                       [.init(value: "None yet")])
        XCTAssertTrue(notes.beginNewDraft())
        XCTAssertTrue(notes.updateDraftText("Synthetic note"))
        XCTAssertTrue(notes.saveDraft())
        XCTAssertEqual(HomeView.fullPageDocument(features, today: asOf, calendar: calendar).sections[0].rows,
                       [.init(value: "1 note")])
    }

    func testFoodAndQuickAddFullPageSectionsUseTheCardsWords() throws {
        let gb = Locale(identifier: "en_GB")
        let totals = [
            FoodIntakeTotal(key: .energyConsumed, knownAmount: 1240, incompleteContributions: 0, includesEstimates: true),
            total(.protein, 68), total(.carbohydrates, 150.5), total(.fatTotal, 41, incomplete: 1)
        ]
        let state = FoodHomeCardContent.make(itemCount: 3, totals: totals, plainWater: nil, locale: gb, incompleteEntries: 1)
        let section = FoodHomeCardContent.fullPageSection(state)
        XCTAssertEqual(section.title, "Food logged")
        XCTAssertEqual(section.rows.map(\.label), ["Energy", nil, "Protein", "Carbohydrates", "Fat", "Plain water logged"])
        XCTAssertEqual(section.rows.map(\.value), ["1,240 kcal", "3 entries", "68 g", "150.5 g", "41 g+", "No data"])
        XCTAssertEqual(section.rows[0].note, "Includes estimates")
        XCTAssertEqual(section.footer, "Some values are unknown for 1 entry, so totals marked + are known minimums.")
        XCTAssertEqual(FoodHomeCardContent.fullPageSection(.empty).rows, [.init(value: "Nothing logged yet today")])
        XCTAssertEqual(FoodHomeCardContent.fullPageSection(.loading).rows, [.init(value: "Loading food log")])

        XCTAssertNil(QuickAddHomeCard.fullPageSection(.unavailable))
        XCTAssertEqual(QuickAddHomeCard.fullPageSection(.items([]))?.rows, [.init(value: "No favourites yet")])
        let water = try XCTUnwrap(QuickAddHomeCard.fullPageSection(.items([.builtInWater])))
        XCTAssertEqual(water.title, "Quick add")
        XCTAssertEqual(water.rows.map(\.label), ["Water"])
        XCTAssertEqual(QuickAddHomeCard.fullPageSection(.unreadable)?.rows, [.init(value: "Favourites could not be read.")])
    }

    func testTodayFullPagePDFContainsEveryCardsText() throws {
        let document = TodayFullPageDocument(date: "Monday 12 October", sections: [
            .init(title: "Food logged", rows: [.init("Energy", value: "1,240 kcal", note: "Includes estimates"),
                                              .init(value: "3 entries")],
                  footer: "Some values are unknown for 1 entry, so totals marked + are known minimums."),
            .init(title: "Quick add", rows: [.init("Water", value: "250 mL")]),
            .init(title: "Health today so far", rows: [.init("Steps", value: "6,412")],
                  footer: "Today is still in progress.\nAs of 14:32"),
            .init(title: "Notes for today", rows: [.init(value: "1 note")])
        ])
        let data = try XCTUnwrap(WeeklyReportPDFRenderer().pdfData(for: .today(document)))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 1)
        let page = try XCTUnwrap(pdf.page(at: 0))
        let text = try XCTUnwrap(page.string)
        for expected in ["Today", "Monday 12 October", "Food logged", "Energy", "1,240 kcal", "Includes estimates",
                         "3 entries", "known minimums", "Quick add", "Water", "250 mL", "Health today so far",
                         "Steps", "6,412", "As of 14:32", "Notes for today", "1 note"] {
            XCTAssertTrue(text.contains(expected), "Missing from Today's Full Page: \(expected)")
        }
        let titleRange = (text as NSString).range(of: "Today")
        let titleBounds = try XCTUnwrap(page.selection(for: titleRange)).bounds(for: page)
        XCTAssertGreaterThan(titleBounds.midY, page.bounds(for: .mediaBox).midY)
    }

    // MARK: Native renders

    func testHealthCardRendersEveryStateAtDefaultAndAccessibilitySizes() async throws {
        let window = try XCTUnwrap(TodaySoFarWindow.capture(at: asOf, calendar: calendar))
        let available = TodaySoFarHealthInputs(
            steps: .value(DailyStepTotal(day: window.day, steps: 6412, sourceNames: ["Synthetic phone"])),
            activeEnergyKilocalories: .value(312),
            asleepIntervals: .value([AsleepInterval(start: date(11, 23, 0), end: date(12, 6, 12))]),
            weights: .value([WeightMeasurement(id: UUID(), date: date(12, 7, 5), kilograms: 72.4)]),
            bloodPressure: .value([BloodPressureReading(id: UUID(), date: date(12, 7, 10), systolicMillimetresOfMercury: 123,
                                                        diastolicMillimetresOfMercury: 78, sourceName: "Synthetic cuff")])
        )
        let partial = TodaySoFarHealthInputs(
            steps: .value(DailyStepTotal(day: window.day, steps: 0, sourceNames: [])), activeEnergyKilocalories: .noData,
            asleepIntervals: .noData, weights: .failed, bloodPressure: .noData)
        let failed = TodaySoFarHealthInputs(steps: .failed, activeEnergyKilocalories: .failed, asleepIntervals: .failed,
                                            weights: .failed, bloodPressure: .failed)
        let states: [(String, TodaySoFarHealthInputs?)] = [
            ("loading", nil), ("available", available), ("partial", partial), ("failed", failed),
            ("unavailable", .healthUnavailable)
        ]
        for (name, inputs) in states {
            let model = healthModel(inputs: inputs)
            if inputs != nil { await model.handle(.pullToRefresh) }
            for size in [DynamicTypeSize.large, .accessibility3] {
                render(NavigationStack { Form { TodaySoFarHealthCardView(model: model) }.environment(\.dynamicTypeSize, size) },
                       name: "Home health - \(name) - \(size)")
            }
        }
    }

    func testHomeRendersWithoutLedgerAndWithNotes() throws {
        let notes = DailyNotesController(store: EmptyDailyNotesStore(), calendar: calendar, now: { self.asOf })
        XCTAssertTrue(notes.beginNewDraft())
        XCTAssertTrue(notes.updateDraftText("Synthetic note"))
        XCTAssertTrue(notes.saveDraft())
        XCTAssertEqual(notes.todayNoteCount, 1)
        let features = [
            FoodHomeCards.feature(model: FoodHomeModel(root: nil)),
            TodaySoFarHealthCardView.feature(model: healthModel(), readsHealthData: false),
            NotesHomeCard.feature(controller: notes)
        ]
        for size in [DynamicTypeSize.large, .accessibility3] {
            render(NavigationStack {
                HomeView(features: features, now: { self.asOf }, calendar: self.calendar).environment(\.dynamicTypeSize, size)
            }, name: "Home - no ledger - \(size)")
        }
    }

    // MARK: Helpers

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private var asOf: Date { date(12, 14, 32) }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func total(_ key: NutrientKey, _ amount: Double, incomplete: Int = 0) -> FoodIntakeTotal {
        FoodIntakeTotal(key: key, knownAmount: amount, incompleteContributions: incomplete, includesEstimates: false)
    }

    private func healthModel(
        inputs: TodaySoFarHealthInputs? = nil,
        reader: FakeTodaySoFarReader? = nil,
        authorizer: FakeReadAuthorizer? = nil
    ) -> TodaySoFarHealthModel {
        let reader = reader ?? FakeTodaySoFarReader()
        let authorizer = authorizer ?? FakeReadAuthorizer()
        if let inputs { reader.inputs = inputs }
        let calendar = calendar
        let asOf = asOf
        return TodaySoFarHealthModel(reader: reader, authorizer: authorizer, now: { asOf }, calendar: { calendar })
    }

    private func render<V: View>(_ content: V, name: String) {
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(image.size.width, 390)
        window.isHidden = true
    }
}
