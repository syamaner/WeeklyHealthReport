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
        XCTAssertEqual(FoodHomeCardContent.make(itemCount: 0, totals: [], plainWater: nil), .empty)
        XCTAssertEqual(FoodHomeCardContent.emptyMessage, "Nothing logged yet today")
    }

    func testLoggedFoodShowsKnownMinimumFootnoteAndPlainWater() throws {
        let gb = Locale(identifier: "en_GB")
        let totals = [
            total(.energyConsumed, 1240.4), total(.protein, 68), total(.carbohydrates, 150.5),
            total(.fatTotal, 41, incomplete: 1)
        ]
        let water = FoodIntakeTotal(key: .water, knownAmount: 730, incompleteContributions: 0, includesEstimates: false)
        guard case .logged(let logged) = FoodHomeCardContent.make(itemCount: 3, totals: totals, plainWater: water, locale: gb) else {
            return XCTFail("Expected a logged card")
        }
        XCTAssertEqual(logged.energy.value, "1,240 kcal")
        XCTAssertEqual(logged.entryCount, "3 entries")
        XCTAssertEqual(logged.nutrients.map(\.value), ["68 g", "150.5 g", "41 g+"])
        XCTAssertEqual(logged.footnote, "Fat unknown for 1 entry, so 41 g is a known minimum.")
        XCTAssertEqual(logged.water.label, "Plain water logged")
        XCTAssertEqual(logged.water.value, "730 mL")
        XCTAssertEqual(logged.energy.accessibilityLabel, "Energy, 1,240 kilocalories")
        XCTAssertEqual(logged.nutrients[2].accessibilityLabel, "Fat, at least 41 grams")
        XCTAssertEqual(logged.water.accessibilityLabel, "Plain water logged, 730 millilitres")

        guard case .logged(let noWater) = FoodHomeCardContent.make(itemCount: 1, totals: [total(.energyConsumed, 200)],
                                                                    plainWater: nil, locale: gb) else { return XCTFail("logged") }
        XCTAssertEqual(noWater.water.value, "No data", "no plain water is No data, never 0 mL")
        XCTAssertNil(noWater.footnote)
        XCTAssertEqual(noWater.nutrients.map(\.value), ["Unknown", "Unknown", "Unknown"])
    }

    /// Review fix: the Food Log's "Includes estimates" caption also shows on Home.
    func testEstimatedTotalsKeepTheirCaption() throws {
        let gb = Locale(identifier: "en_GB")
        let totals = [
            FoodIntakeTotal(key: .energyConsumed, knownAmount: 300, incompleteContributions: 0, includesEstimates: true),
            FoodIntakeTotal(key: .protein, knownAmount: 12, incompleteContributions: 0, includesEstimates: true),
            total(.carbohydrates, 40), total(.fatTotal, 9)
        ]
        guard case .logged(let logged) = FoodHomeCardContent.make(itemCount: 2, totals: totals, plainWater: nil, locale: gb) else {
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
        let states: [(String, TodaySoFarHealthInputs?)] = [
            ("loading", nil), ("available", available), ("partial", partial), ("unavailable", .healthUnavailable)
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
