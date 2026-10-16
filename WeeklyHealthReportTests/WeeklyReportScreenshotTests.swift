import CoreGraphics
import HealthKit
import PDFKit
import XCTest
import SwiftUI
import UIKit
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerPresentation
import FoodGenericSearch
@testable import DriveExportKit
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
@MainActor
final class WeeklyReportScreenshotTests: XCTestCase {
    func testIntakeScreensRenderWithIsolatedSyntheticLedger() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "intake-render-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let root = try FoodLedgerCompositionRoot(
            fileManager: IntakeRenderFileManager(directory: directory), userDefaults: defaults
        )
        XCTAssertEqual(try root.intakeProjection(for: Date()).summary.itemCount, 0)
        let emptyHome = FoodHomeModel(root: root)
        emptyHome.reload()
        XCTAssertEqual(emptyHome.state, .empty)
        renderFoodView(NavigationStack { Form { FoodHomeCard(model: emptyHome) } }, name: "Today - empty log")
        let navigation = AppNavigationCoordinator(defaults: defaults)
        renderFoodView(NavigationStack { FoodLogView(root: root, navigation: navigation) }, name: "Food Log - empty log")

        let search = try root.genericFoodSearchModel(locale: Locale(identifier: "en_GB"))
        search.query = "clementine"
        search.search()
        guard case let .results(route) = search.phase else { return XCTFail("Expected offline fruit candidates") }
        let candidate = try XCTUnwrap(route.confirmation.candidates.first)
        let input = try PopulatedFoodConfirmation(
            evidence: route.confirmation.evidence, sourceReleases: route.confirmation.sourceReleases,
            candidates: [candidate], expectedIdentity: candidate.candidate.identity,
            expectedEdibleQuantity: candidate.candidate.edibleQuantity
        )
        let confirmation = root.model(for: input)
        // Explicit synthetic user assertions resolve the source's unknown identity;
        // production candidates retain their original unknown fields.
        let assertedIdentity = try DecisiveIdentity(
            preparation: PreparationState(kind: .raw), bone: .notApplicable,
            skin: .skinless, drained: .notApplicable,
            packingMedium: .named(LedgerText("none — synthetic fixture")),
            fortification: .unfortified, servingBasis: candidate.candidate.identity.servingBasis
        )
        confirmation.send(.applyCorrection(FoodCorrection(
            name: try LedgerText("Synthetic clementine flesh"), brand: nil, variant: nil,
            identity: assertedIdentity, nutrients: candidate.candidate.nutrients,
            reason: try LedgerText("Explicit identity assertions for an isolated visual fixture")
        )))
        confirmation.send(.setQuantity(100, .grams))
        confirmation.save()
        XCTAssertNotNil(confirmation.savedResult, "Synthetic confirmation must save before rendering: \(confirmation.state.phase)")
        let populated = try root.intakeProjection(for: Date())
        XCTAssertEqual(populated.summary.itemCount, 1)
        let populatedHome = FoodHomeModel(root: root)
        populatedHome.reload()
        guard case .logged = populatedHome.state else { return XCTFail("Expected a logged food card") }
        for size in [DynamicTypeSize.large, .accessibility3] {
            renderFoodView(NavigationStack {
                Form { FoodHomeCard(model: populatedHome) }.environment(\.dynamicTypeSize, size)
            }, name: "Today - populated - \(size)")
            renderFoodView(NavigationStack {
                FoodLogView(root: root, navigation: navigation).environment(\.dynamicTypeSize, size)
            }, name: "Food Log - populated - \(size)")
        }
        let row = try XCTUnwrap(populated.rows.first)
        XCTAssertEqual(root.foodLogService.remove(row.logItemID, expected: row.logItemVersionID), .applied)
        let removed = try root.intakeProjection(for: Date())
        XCTAssertEqual(removed.summary.itemCount, 0)
        XCTAssertEqual(removed.removedRows.count, 1)
        renderFoodView(NavigationStack {
            FoodLogView(root: root, navigation: navigation).environment(\.dynamicTypeSize, .accessibility3)
        }, name: "Food Log - retained removed entry - large text")
        let removedRow = try XCTUnwrap(removed.removedRows.first)
        XCTAssertEqual(root.foodLogService.restore(removedRow.logItemID, expected: removedRow.logItemVersionID), .applied)
        XCTAssertEqual(try root.intakeProjection(for: Date()).summary.itemCount, 1)
    }

    func testHistoricalExportAndNotesRenderWithSyntheticData() throws {
        let calendar = testCalendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 15))!
        let store = EmptyDailyNotesStore()
        let notes = DailyNotesController(store: store, calendar: calendar, now: { now })
        let session = DailyDriveSessionController(
            keychain: ScreenshotMemoryDailySessionStore(), drive: DailyDriveAPI(),
            exportService: DailyHealthExportService(healthData: UnusedDailyHealthDataProvider(), notesStore: store, calendar: calendar, now: { now }),
            identityStore: ControllerMemoryDailyIdentityStore(),
            nutritionSourceSelection: EmptyNutritionSourceSelectionStore(), notes: notes
        )
        session.selectReportDay(session.availableReportDays[5])
        XCTAssertEqual(notes.currentDayID.reportDate, "2026-09-05")
        renderFoodView(NavigationStack { DailyExportView(session: session) }, name: "Historical export - date selection")
        renderFoodView(NavigationStack { DailyNotesView(controller: notes, openEditor: {}) }, name: "Historical notes - selected date")
    }
    /// #199 (D11): with the export on a past day, Home's notes row counts today and
    /// opens today; leaving restores the export's day, and Export re-asserts it.
    func testHomeTodayNotesKeepTheExportsSelectedDay() throws {
        let calendar = testCalendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 15))!
        let store = EmptyDailyNotesStore()
        let notes = DailyNotesController(store: store, calendar: calendar, now: { now })
        let session = DailyDriveSessionController(
            keychain: ScreenshotMemoryDailySessionStore(), drive: DailyDriveAPI(),
            exportService: DailyHealthExportService(healthData: UnusedDailyHealthDataProvider(), notesStore: store, calendar: calendar, now: { now }),
            identityStore: ControllerMemoryDailyIdentityStore(),
            nutritionSourceSelection: EmptyNutritionSourceSelectionStore(), notes: notes
        )
        XCTAssertTrue(notes.beginNewDraft()); XCTAssertTrue(notes.updateDraftText("Synthetic today note")); XCTAssertTrue(notes.saveDraft())
        let past = session.availableReportDays[5]
        session.selectReportDay(past)
        XCTAssertEqual(notes.currentDayID.reportDate, "2026-09-05")
        XCTAssertEqual(NotesHomeCard.countLabel(notes.todayNoteCount), "1 note")

        notes.pinToday()
        XCTAssertEqual(notes.currentDayID.reportDate, "2026-09-10")
        renderFoodView(NavigationStack { DailyNotesView(controller: notes, openEditor: {}) }, name: "Home today notes - export on a past day")
        notes.unpinToday()
        XCTAssertEqual(notes.currentDayID, past)
        XCTAssertEqual(session.selectedReportDay, past)
        session.reassertReportDay()
        XCTAssertEqual(notes.currentDayID, past)
    }

    func testFoodRecoveryAndCommonFoodsRenderWithSyntheticData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ids = RandomLedgerIDGenerator()
        let inventory = try LocalInventoryGRDBStore(databaseURL: directory.appendingPathComponent("inventory.sqlite"))
        let model = try LocalInventoryViewModel(
            service: LocalInventoryService(store: inventory, digester: SHA256Digester(), clock: SystemLedgerClock()),
            ids: ids, clock: SystemLedgerClock()
        )
        XCTAssertTrue(model.saveCommonFood(name: "Rolled oats", aliases: "breakfast oats", portion: "25", unit: .grams, favourite: true))
        XCTAssertTrue(model.saveCommonFood(name: "Whole milk", aliases: "milk", portion: "200", unit: .millilitres, favourite: false))
        renderFoodView(NavigationStack { CommonFoodsView(model: model) { _ in } }, name: "Common foods - standard")
        renderFoodView(NavigationStack { CommonFoodsView(model: model) { _ in }.environment(\.dynamicTypeSize, .accessibility3) }, name: "Common foods - large text")
        model.paste = "Meadow oats 500 g £1.00"
        model.importPaste()
        renderFoodView(NavigationStack { LocalInventoryView(model: model, chooseFile: {}) { _ in } }, name: "Receipt review - saved source")
        let library = try FoodLedgerGRDBStore(databaseURL: directory.appendingPathComponent("food.sqlite"))
        let search = try CoFIDGenericFoodSearch(library: PersonalLibraryGenericFoodSearch(reader: library), ids: ids)
        let searchModel = GenericFoodSearchViewModel(searcher: search, locale: try LedgerText("en_GB"))
        // Use the published lexical query; modifiers can legitimately fall below
        // the frozen threshold until a user has confirmed an exact saved alias.
        searchModel.query = "oats"
        searchModel.search()
        guard case .results = searchModel.phase else { return XCTFail("Expected bundled public food candidates") }
        renderFoodView(NavigationStack { GenericFoodSearchView(model: searchModel) { _ in } }, name: "Search - public CoFID candidates")
        renderFoodView(FoodVoiceInputView(vocabulary: ["grams", "millilitres"], vocabularyUnavailable: false) { _ in false }, name: "Food dictation - idle without recording")
        let queue = FoodListImportViewModel(service: FoodListImportService(searcher: ScreenshotNoFoodSearch()), locale: try LedgerText("en_GB"), ids: ids,
            checkpointStore: try FoodListCheckpointGRDBStore(databaseURL: directory.appendingPathComponent("draft.sqlite"))) { _, _ in
                throw FoodLedgerValidationError.invalidProvenance
            }
        queue.input = "25 g rolled oats\n200 ml whole milk"
        queue.prepare()
        queue.search()
        renderFoodView(NavigationStack { FoodListImportView(model: queue) }, name: "Food list - unresolved review")
        queue.deferLine()
        let resumed = FoodListImportViewModel(service: FoodListImportService(searcher: ScreenshotNoFoodSearch()), locale: try LedgerText("en_GB"), ids: ids,
            checkpointStore: try FoodListCheckpointGRDBStore(databaseURL: directory.appendingPathComponent("draft.sqlite"))) { _, _ in
                throw FoodLedgerValidationError.invalidProvenance
            }
        XCTAssertEqual(resumed.rows.first?.status, .deferred)
        XCTAssertEqual(resumed.selectedRow?.draft.query, "whole milk")
        renderFoodView(NavigationStack { FoodListImportView(model: resumed) }, name: "Food list - resumed review")
    }

    private func renderFoodView<V: View>(_ content: V, name: String) {
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

    func testReportViewCanBeConstructedWithFakeHealthData() {
        let calendar = testCalendar()
        let viewModel = WeeklyReportViewModel(
            healthData: FakeHealthDataProvider(),
            calendar: calendar,
            now: Date.init
        )
        let notesStore = EmptyDailyNotesStore()
        let notes = DailyNotesController(store: notesStore, calendar: calendar)
        let keychain = ScreenshotMemoryDailySessionStore()
        let dailyExport = DailyDriveSessionController(
            keychain: keychain,
            drive: DailyDriveAPI(),
            exportService: DailyHealthExportService(
                healthData: UnusedDailyHealthDataProvider(),
                notesStore: notesStore,
                calendar: calendar
            ),
            identityStore: ControllerMemoryDailyIdentityStore(),
            nutritionSourceSelection: EmptyNutritionSourceSelectionStore(),
            notes: notes
        )
        let store = HKHealthStore()

        let view = AppShellView(
            viewModel: viewModel,
            dailyExport: dailyExport,
            navigation: AppNavigationCoordinator(defaults: UserDefaults(suiteName: "shell-construction-" + UUID().uuidString)!),
            todaySoFar: TodaySoFarHealthModel(reader: FakeTodaySoFarReader(), authorizer: FakeReadAuthorizer()),
            foodHome: FoodHomeModel(root: nil),
            medicationAccess: MedicationAccessRequest(store: store),
            foodLedger: nil,
            settings: WeeklyHealthReportApp.makeSettings(
                foodLedger: nil, defaults: UserDefaults(suiteName: "shell-construction-" + UUID().uuidString)!,
                medicationAccessAvailable: false
            )
        )

        XCTAssertTrue(view.viewModel === viewModel)
        XCTAssertTrue(view.medicationAccess.store === store)
    }

    func testDocumentUsesCompleteDeterministicSectionOrdering() {
        let document = makeDocument(includesMedicationSection: true)

        // Group order (#216); every section is present exactly once.
        XCTAssertEqual(
            document.sections.map(\.id),
            [.steps, .activity, .foodLog, .weight, .bodyComposition, .heart, .bloodPressure, .sleep,
             .cardiorespiratory, .glucose, .medications]
        )
        XCTAssertEqual(Set(document.sections.map(\.id)), Set(ReportDocument.SectionID.allCases))
        XCTAssertEqual(document.title, "Weekly Health Report")
        XCTAssertEqual(document.selection, "Last 7 Completed Days")
    }

    func testDocumentGoldenRowsForFullFixture() {
        let document = ReportDocument(
            snapshot: makeFullFixtureSnapshot(),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        )

        let lines = document.sections.flatMap { section in
            ["section|\(section.id.rawValue)|\(section.title)"]
                + section.rows.map {
                    "\(section.id.rawValue)|\($0.id)|\($0.label ?? "")|\($0.value)|\(String(describing: $0.style))"
                }
                + ["footer|\(section.id.rawValue)|\(section.footer ?? "")"]
        }

        XCTAssertEqual(lines.joined(separator: "\n"), """
        section|steps|Steps
        steps|steps-average|Average Daily Steps|7,000|standard
        steps|steps-coverage|Data Coverage|7 / 7 days|standard
        steps|steps-trend|Steps Trend|+6% vs previous 7d|standard
        steps|steps-total|Weekly Total|49,000|standard
        footer|steps|
        section|activity|Activity
        activity|active-energy|Active Energy|1,974 kcal|standard
        activity|exercise|Exercise|89 min|standard
        activity|workouts|Workouts|1|standard
        activity|workout-time|Workout Time|30m|standard
        activity|workout-0|Walking|30m — 09/09/26 - 08:00|standard
        footer|activity|
        section|foodLog|Food and water
        foodLog|food-days-logged|Days Logged|6 / 7 days|standard
        foodLog|food-energy-average|Logged Energy|2,010 kcal per day (5 complete days)|standard
        foodLog|food-energy-incomplete|Incomplete Energy Days|1|standard
        foodLog|food-plain-water-average|Plain Water|1,750 mL per day (4 days)|standard
        footer|foodLog|Logged in this app; not a measure of everything eaten or drunk.
        section|weight|Weight
        weight|weight-latest|Latest Weight|100.6 kg|standard
        weight|weight-measured|Measured|09/09/26 - 08:00|standard
        weight|weight-average|7-day Average|100.8 kg|standard
        weight|weight-trend|Weight Trend|-0.4 kg vs previous 7d|standard
        footer|weight|
        section|bodyComposition|Body Composition
        bodyComposition|body-fat-latest|Body Fat|26.5% latest|standard
        bodyComposition|body-fat-seven-day|7-day Average|26.6%|standard
        bodyComposition|body-fat-28-day|28-day Average|26.7%|standard
        bodyComposition|body-fat-trend|Body Fat Trend|↓ 0.9 pp vs previous 28d|standard
        bodyComposition|waist|Waist Circumference|101.4 cm|standard
        bodyComposition|waist-measured|Waist Measured|09/09/26 - 08:00|standard
        bodyComposition|waist-trend|4-week Waist Trend|-1.7 cm vs ~4 weeks earlier|standard
        footer|bodyComposition|
        section|heart|Heart
        heart|resting-heart-rate-average|Resting HR Average|73 bpm|standard
        heart|resting-heart-rate-trend|Resting HR Trend|+3.0 bpm vs previous 7d|standard
        heart|hrv-average|HRV Average|42 ms|standard
        heart|hrv-trend|HRV Trend|-5.0 ms vs previous 7d|standard
        heart|watch-coverage|Watch Data Coverage|4 / 7 days|standard
        footer|heart|
        section|bloodPressure|Blood Pressure
        bloodPressure|blood-pressure-latest|Latest reading|120/75 mmHg|standard
        bloodPressure|blood-pressure-recorded|Recorded|09/09/26 - 08:00|secondary
        bloodPressure|blood-pressure-morning-average|Morning average|120/75 mmHg|standard
        bloodPressure|blood-pressure-morning-latest-batch|Latest batch|120/75 mmHg|standard
        bloodPressure|blood-pressure-morning-recorded|Recorded|09/09/26 - 08:00 · 1 reading|standard
        bloodPressure|blood-pressure-morning-coverage|Coverage|1/7 days · 1 readings|standard
        bloodPressure|blood-pressure-evening-average|Evening average|120/75 mmHg|standard
        bloodPressure|blood-pressure-evening-latest-batch|Latest batch|120/75 mmHg|standard
        bloodPressure|blood-pressure-evening-recorded|Recorded|09/09/26 - 08:00 · 1 reading|standard
        bloodPressure|blood-pressure-evening-coverage|Coverage|1/7 days · 1 readings|standard
        footer|bloodPressure|Period averages use completed days. Morning is before 14:00; evening is from 17:00. Mid-afternoon readings are excluded from both slot summaries.
        section|sleep|Sleep
        sleep|sleep-average|Average Sleep|6h 48m|standard
        footer|sleep|
        section|cardiorespiratory|Cardiorespiratory
        cardiorespiratory|vo2-max-latest|Latest VO₂ Max|32.1 mL/kg/min|standard
        cardiorespiratory|vo2-max-measured|VO₂ Max Measured|09/09/26 - 08:00|standard
        cardiorespiratory|vo2-max-four-week|4-Week Average|31.8 mL/kg/min (8 days)|standard
        cardiorespiratory|vo2-max-three-month|3-Month Average|30.9 mL/kg/min (24 days)|standard
        cardiorespiratory|vo2-max-six-month|6-Month Average|29.7 mL/kg/min (51 days)|standard
        cardiorespiratory|blood-oxygen-latest|Latest Blood Oxygen|97%|standard
        cardiorespiratory|blood-oxygen-measured|Blood Oxygen Measured|09/09/26 - 08:00|standard
        cardiorespiratory|blood-oxygen-typical|Period Typical|97%|standard
        cardiorespiratory|blood-oxygen-range|Daily Median Range|96–98%|standard
        cardiorespiratory|blood-oxygen-coverage|Blood Oxygen Coverage|7 / 7 days|standard
        cardiorespiratory|blood-oxygen-note||Apple Watch blood-oxygen measurements are wellness estimates, not medical measurements.|note
        footer|cardiorespiratory|
        section|glucose|Glucose
        glucose|glucose-average|Daily Average|5.8 mmol/L|standard
        glucose|glucose-range|Observed Range|3.9–8.7 mmol/L|standard
        glucose|glucose-coverage|Data Coverage|7 / 7 days|standard
        footer|glucose|
        section|medications|Medications Taken
        medications|medication-0|SyntheticMed 20 mg|1 dose at 09/09/26 - 08:00; 1 taken event|standard
        footer|medications|
        """)
    }

    func testDocumentStateRowsPerSection() throws {
        for stateCase in SyntheticDocumentStateCase.allCases {
            let document = ReportDocument(
                snapshot: makeSnapshot(
                    steps: stateCase.stepsState,
                    weight: stateCase.metricState(),
                    bodyFat: stateCase.metricState(),
                    waist: stateCase.metricState(),
                    glucose: stateCase.metricState(),
                    vo2Max: stateCase.metricState(),
                    bloodOxygen: stateCase.metricState(),
                    bloodPressure: stateCase.metricState(),
                    restingHeartRate: stateCase.metricState(),
                    hrv: stateCase.metricState(),
                    watchCoverage: stateCase.metricState(),
                    exercise: stateCase.metricState(),
                    activeEnergy: stateCase.metricState(),
                    workouts: stateCase.metricState(),
                    sleep: stateCase.metricState(),
                    medications: stateCase.metricState(),
                    foodLog: stateCase.metricState(),
                    includesMedicationSection: true
                ),
                calendar: testCalendar(),
                locale: Locale(identifier: "en_GB")
            )

            for sectionID in ReportDocument.SectionID.allCases {
                let section = try XCTUnwrap(
                    document.sections.first { $0.id == sectionID },
                    "Missing \(sectionID) for \(stateCase)"
                )
                let expected = stateRowExpectation(for: sectionID, stateCase: stateCase)
                let row = try XCTUnwrap(
                    section.rows.first { $0.id == expected.id },
                    "Missing \(expected.id) for \(stateCase)"
                )
                XCTAssertEqual(row.label, expected.label, "\(sectionID), \(stateCase)")
                XCTAssertEqual(row.value, expected.value, "\(sectionID), \(stateCase)")
                XCTAssertEqual(row.style, expected.style, "\(sectionID), \(stateCase)")

                for target in additionalGenericStateRows(for: sectionID) {
                    let expected = stateCase.genericExpectation(
                        id: target.id,
                        label: target.label
                    )
                    let row = try XCTUnwrap(
                        section.rows.first { $0.id == target.id },
                        "Missing \(target.id) for \(stateCase)"
                    )
                    XCTAssertEqual(row.label, expected.label, "\(target.id), \(stateCase)")
                    XCTAssertEqual(row.value, expected.value, "\(target.id), \(stateCase)")
                    XCTAssertEqual(row.style, expected.style, "\(target.id), \(stateCase)")
                }
            }
        }
    }

    func testSharedMetricRowMappingPreservesEveryStateAndInsufficientHistory() {
        let cases: [(MetricState<Double>, String, ReportDocument.RowStyle)] = [
            (.idle, "Loading…", .loading),
            (.loading, "Loading…", .loading),
            (.available(12.5), "12.5 units", .standard),
            (.noDataOrAccess, "No data", .secondary),
            (.healthUnavailable, "Unavailable", .secondary),
            (.failed("Synthetic failure"), "Query failed", .failure)
        ]

        for (state, expectedValue, expectedStyle) in cases {
            let row = ReportDocument.Row.metric(
                id: "metric",
                label: "Metric",
                state: state,
                format: { "\($0) units" }
            )
            XCTAssertEqual(row.id, "metric")
            XCTAssertEqual(row.label, "Metric")
            XCTAssertEqual(row.value, expectedValue)
            XCTAssertEqual(row.style, expectedStyle)
        }

        let insufficient = ReportDocument.Row.metric(
            id: "trend",
            label: "Trend",
            state: MetricState<Double>.available(12.5),
            format: { _ in nil }
        )
        XCTAssertEqual(insufficient.value, "Insufficient history")
        XCTAssertEqual(insufficient.style, .secondary)
    }

    func testSharedOptionalRowMappingPreservesAvailableAndMissingVocabulary() {
        let available = ReportDocument.Row.optional(
            id: "available",
            label: "Available",
            value: 3,
            missing: .noData,
            format: String.init
        )
        XCTAssertEqual(available.value, "3")
        XCTAssertEqual(available.style, .standard)

        let noData = ReportDocument.Row.optional(
            id: "no-data",
            label: "No data",
            value: Optional<Int>.none,
            missing: .noData,
            format: String.init
        )
        XCTAssertEqual(noData.value, "No data")
        XCTAssertEqual(noData.style, .secondary)

        let noPeriodData = ReportDocument.Row.optional(
            id: "no-period-data",
            label: "No period data",
            value: Optional<Int>.none,
            missing: .noPeriodData,
            format: String.init
        )
        XCTAssertEqual(noPeriodData.value, "No period data")
        XCTAssertEqual(noPeriodData.style, .secondary)
    }

    func testDocumentPreservesMissingUnavailableAndFailedStates() {
        let document = ReportDocument(snapshot: makeSnapshot(
            steps: .noDataOrAccess,
            weight: .healthUnavailable,
            bodyFat: .failed("Synthetic body-fat failure"),
            waist: .noDataOrAccess,
            glucose: .failed("Synthetic glucose failure")
        ), calendar: testCalendar(), locale: Locale(identifier: "en_GB"))

        XCTAssertTrue(document.searchableText.contains(
            "No step data is visible, or Health access was not granted."
        ))
        XCTAssertTrue(document.searchableText.contains(
            "Health data is unavailable on this device."
        ))
        XCTAssertTrue(document.searchableText.contains(
            "Body-fat query failed: Synthetic body-fat failure"
        ))
        XCTAssertTrue(document.searchableText.contains("Waist Circumference\nNo data"))
        XCTAssertTrue(document.searchableText.contains("Daily Average\nQuery failed"))
    }

    func testDocumentShowsSampledDayStepAverageAndCoverage() throws {
        let summary = try XCTUnwrap(StepSummary.aggregate([
            DailyStepTotal(
                day: DateInterval(start: Date(timeIntervalSinceReferenceDate: 0), duration: 86_400),
                steps: 10_000,
                sourceNames: ["Invented Watch"]
            ),
            DailyStepTotal(
                day: DateInterval(start: Date(timeIntervalSinceReferenceDate: 86_400), duration: 86_400),
                steps: nil,
                sourceNames: []
            ),
            DailyStepTotal(
                day: DateInterval(start: Date(timeIntervalSinceReferenceDate: 172_800), duration: 86_400),
                steps: 4_000,
                sourceNames: ["Invented Phone"]
            )
        ]))
        let document = ReportDocument(
            snapshot: makeSnapshot(steps: .loaded(summary)),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        )
        let section = try XCTUnwrap(document.sections.first { $0.id == .steps })

        XCTAssertEqual(section.rows.first { $0.id == "steps-average" }?.value, "7,000")
        XCTAssertEqual(section.rows.first { $0.id == "steps-coverage" }?.value, "2 / 3 days")
    }

    func testStepsTrendRowForTrendInsufficientHistoryZeroPreviousAndFailedPreviousRead() throws {
        func day(_ offset: Int, _ steps: Double?) -> DailyStepTotal {
            DailyStepTotal(
                day: DateInterval(start: Date(timeIntervalSinceReferenceDate: Double(offset) * 86_400), duration: 86_400),
                steps: steps,
                sourceNames: []
            )
        }
        let current = (0 ..< 7).map { day($0, 10_600) }
        let summary = try XCTUnwrap(StepSummary.aggregate(current))
        func rows(_ trend: StepTrendRead) throws -> [ReportDocument.Row] {
            let document = ReportDocument(
                snapshot: makeSnapshot(steps: .loaded(summary, trend: trend)),
                calendar: testCalendar(),
                locale: Locale(identifier: "en_GB")
            )
            return try XCTUnwrap(document.sections.first { $0.id == .steps }).rows
        }
        func calculated(_ previous: [Double?]) throws -> StepTrendRead {
            .calculated(try XCTUnwrap(StepTrendSummary.calculate(
                current: current,
                previous: previous.enumerated().map { day($0.offset - 7, $0.element) },
                completedDayCount: 7
            )))
        }

        let withTrend = try rows(try calculated(Array(repeating: 10_000, count: 7)))
        let shortHistory = try rows(try calculated([10_000, 10_000, 10_000, 10_000, nil, nil, nil]))
        let zeroPrevious = try rows(try calculated(Array(repeating: 0, count: 7)))
        let failedPrevious = try rows(.previousFailed("Synthetic previous failure"))

        XCTAssertEqual(withTrend.map(\.id), ["steps-average", "steps-coverage", "steps-trend", "steps-total"])
        XCTAssertEqual(withTrend[2], ReportDocument.Row("steps-trend", label: "Steps Trend", value: "+6% vs previous 7d"))
        for trendRows in [shortHistory, zeroPrevious, failedPrevious] {
            XCTAssertEqual(trendRows[2], ReportDocument.Row(
                "steps-trend", label: "Steps Trend", value: "Insufficient history", style: .secondary
            ))
            // The current rows are byte-identical whatever the previous side did.
            XCTAssertEqual(trendRows.filter { $0.id != "steps-trend" }, withTrend.filter { $0.id != "steps-trend" })
        }
        XCTAssertFalse(failedPrevious.contains { $0.value.contains("Synthetic") })
        let failures = makeSnapshot(steps: .loaded(summary, trend: .previousFailed("Synthetic previous failure")))
            .readFailures
        XCTAssertEqual(failures, [ReportReadFailure(
            metric: "Steps trend (previous period)", message: "Synthetic previous failure"
        )])

        let display = ReportDocument(
            snapshot: makeSnapshot(steps: .loaded(summary, trend: try calculated(Array(repeating: 10_000, count: 7)))),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        ).forDisplay()
        let displayRow = try XCTUnwrap(display.sections.first { $0.id == .steps }?.rows.first { $0.id == "steps-trend" })
        XCTAssertEqual(displayRow.label, "Steps trend")
        XCTAssertEqual(displayRow.value, "+6% vs previous 7d")
    }

    func testStepsTrendRowIsAbsentWhenStepsHaveNoCurrentValues() throws {
        for state in [StepsState.loading, .noDataOrAccess, .healthUnavailable, .noCompletedDays, .failed("x")] {
            let document = ReportDocument(
                snapshot: makeSnapshot(steps: state),
                calendar: testCalendar(),
                locale: Locale(identifier: "en_GB")
            )
            let section = try XCTUnwrap(document.sections.first { $0.id == .steps })
            XCTAssertEqual(section.rows.count, 1, "\(state)")
            XCTAssertFalse(section.rows.contains { $0.id == "steps-trend" }, "\(state)")
        }
    }

    func testDocumentPreservesUnavailableAndFailedStepStates() {
        let unavailable = ReportDocument(
            snapshot: makeSnapshot(steps: .healthUnavailable),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        )
        let failed = ReportDocument(
            snapshot: makeSnapshot(steps: .failed("Synthetic step failure")),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        )

        XCTAssertTrue(unavailable.searchableText.contains("Health data is unavailable"))
        XCTAssertTrue(failed.searchableText.contains("Step query failed: Synthetic step failure"))
    }

    func testDocumentPreservesExpandedAndCollapsedBloodPressureDetails() throws {
        let summary = syntheticBloodPressureSummary()
        let document = makeDocument(
            bloodPressure: .available(summary),
            showsMorningDetails: true,
            showsEveningDetails: false
        )
        let section = try XCTUnwrap(document.sections.first { $0.id == .bloodPressure })
        let rowIDsLG = section.rows.map(\.id)

        XCTAssertTrue(rowIDsLG.contains("blood-pressure-morning-latest-batch"))
        XCTAssertTrue(rowIDsLG.contains("blood-pressure-morning-recorded"))
        XCTAssertTrue(rowIDsLG.contains("blood-pressure-morning-coverage"))
        XCTAssertFalse(rowIDsLG.contains("blood-pressure-evening-latest-batch"))
        XCTAssertTrue(rowIDsLG.contains("blood-pressure-evening-average"))
        XCTAssertEqual(
            section.footer,
            "Period averages use completed days. Morning is before 14:00; evening is from 17:00. Mid-afternoon readings are excluded from both slot summaries."
        )
    }

    func testOnlyVisibleHealthReportOrTodayWithoutTransientPresentationIsEligible() {
        var paths: [[AppRoute]] = [[]]
        paths += AppRoute.allCases.map { [$0] }
        paths += [
            [.settings, .medicationAccess],
            [.healthReport, .diagnostics],
            [.foodLog, .healthReport],
            [.settings, .developerTools, .diagnostics],
            [.dailyExport, .notes, .noteEditor]
        ]
        for path in paths {
            for transient in [false, true] {
                for todayOnScreen in [true, false] {
                    let expected: FullPageScreen? = transient ? nil
                        : path == [.healthReport] ? .healthReport
                        : path.isEmpty && todayOnScreen ? .today
                        : nil
                    XCTAssertEqual(
                        WeeklyReportScreenshotEligibility.screen(
                            navigationPath: path, isTransientUIPresented: transient,
                            isTodayOnScreen: todayOnScreen),
                        expected,
                        "\(path) transient: \(transient) today on screen: \(todayOnScreen)"
                    )
                    XCTAssertEqual(
                        WeeklyReportScreenshotEligibility.isEligible(
                            navigationPath: path, isTransientUIPresented: transient,
                            isTodayOnScreen: todayOnScreen),
                        expected != nil
                    )
                }
            }
        }
    }

    /// Health's rule is exactly as before: Home's visibility never affects it.
    func testHealthReportEligibilityIgnoresTodayVisibility() {
        for todayOnScreen in [true, false] {
            XCTAssertEqual(WeeklyReportScreenshotEligibility.screen(
                navigationPath: [.healthReport], isTransientUIPresented: false, isTodayOnScreen: todayOnScreen),
                .healthReport)
            XCTAssertNil(WeeklyReportScreenshotEligibility.screen(
                navigationPath: [.healthReport], isTransientUIPresented: true, isTodayOnScreen: todayOnScreen))
        }
        XCTAssertEqual(WeeklyReportScreenshotEligibility.screen(navigationPath: [], isTransientUIPresented: false), .today)
        XCTAssertNil(WeeklyReportScreenshotEligibility.screen(
            navigationPath: [], isTransientUIPresented: false, isTodayOnScreen: false),
            "a sheet or pushed confirmation over Home is not eligible")
    }

    func testDelegateRendersTodayDocumentThroughTheSameRenderer() {
        let renderer = FakePDFRenderer(result: Data("pdf".utf8))
        let delegate = WeeklyReportScreenshotDelegate(renderer: renderer)
        let today = TodayFullPageDocument(date: "Monday 12 October", sections: [
            .init(title: "Today\u{2019}s notes", rows: [.init(value: "None yet")])
        ])
        delegate.setRequestProvider { .today(today) }

        XCTAssertEqual(delegate.representationForCurrentRequest(), Data("pdf".utf8))
        XCTAssertEqual(renderer.documents, [.today(today)])
    }

    func testMedicationAuthorizationRequestIsAnExcludingTransientPresentation() {
        let presentationState = WeeklyReportPresentationState()

        XCTAssertFalse(presentationState.isTransientUIPresented)
        presentationState.beginMedicationAuthorizationRequest()
        XCTAssertTrue(presentationState.isTransientUIPresented)
        XCTAssertFalse(WeeklyReportScreenshotEligibility.isEligible(
            navigationPath: [],
            isTransientUIPresented: presentationState.isTransientUIPresented
        ))

        presentationState.finishMedicationAuthorizationRequest()
        XCTAssertFalse(presentationState.isTransientUIPresented)
        presentationState.showsMedicationAccessHelp = true
        XCTAssertTrue(presentationState.isTransientUIPresented)
    }

    func testControllerStronglyRetainsDelegateAndRegistersWithOneSceneService() {
        let firstService = FakeScreenshotService()
        let secondService = FakeScreenshotService()
        var controller: WeeklyReportScreenshotController? = WeeklyReportScreenshotController(
            renderer: FakePDFRenderer(result: Data("pdf".utf8))
        )
        let retainedDelegate = WeakBox(controller?.delegate)

        controller?.register(with: firstService)
        XCTAssertTrue(firstService.delegate === retainedDelegate.value)

        controller?.register(with: secondService)
        XCTAssertNil(firstService.delegate)
        XCTAssertTrue(secondService.delegate === retainedDelegate.value)

        controller?.unregister()
        XCTAssertNil(secondService.delegate)
        XCTAssertNotNil(retainedDelegate.value)

        controller = nil
        XCTAssertNil(retainedDelegate.value)
    }

    func testDocumentExcludesNavigationActionsExportAndDiagnostics() {
        let text = makeDocument(includesMedicationSection: true).searchableText
        let excludedContent = [
            "Daily JSON Export",
            "Copy Report",
            "Copy all",
            "Export a day",
            "Summary",
            "Refresh",
            "Last refreshed",
            "Developer Diagnostics",
            "Medication Access",
            "Medication access",
            "Export prepared snapshot"
        ]

        for excluded in excludedContent {
            XCTAssertFalse(text.contains(excluded), "Unexpected PDF content: \(excluded)")
        }
    }

    func testDelegateFailsClosedWithoutARequestOrWhenRenderingFails() {
        let renderer = FakePDFRenderer(result: nil)
        let delegate = WeeklyReportScreenshotDelegate(renderer: renderer)

        XCTAssertNil(delegate.representationForCurrentRequest())
        XCTAssertEqual(renderer.documents.count, 0)

        delegate.setRequestProvider { .healthReport(self.makeDocument()) }
        XCTAssertNil(delegate.representationForCurrentRequest())
        XCTAssertEqual(renderer.documents.count, 1)
    }

    /// Device regression: the fully expanded, fully populated report goes through
    /// the real renderer and the real delegate method and yields a usable PDF.
    func testFullyExpandedPopulatedReportProducesFullPagePDF() throws {
        let document = ReportDocument.expanded(
            snapshot: makeFullFixtureSnapshot(), calendar: testCalendar(), locale: Locale(identifier: "en_GB"))
        let delegate = WeeklyReportScreenshotDelegate()
        delegate.setRequestProvider { .healthReport(document) }
        let data = try XCTUnwrap(delegate.representationForCurrentRequest(), "Full Page returned no PDF")
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let box = page.bounds(for: .mediaBox)
        // Measured at 612 x 2,519 pt for 50 rows on 13 October 2026; far below the
        // 14,400 pt PDF page-dimension limit.
        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertEqual(box.width, 612)
        XCTAssertGreaterThan(box.height, 1_000)
        XCTAssertLessThan(box.height, 14_400)
    }

    /// Device regression: registration no longer depends on a view reaching a
    /// window. The registry resolves the scene itself, registers even when the
    /// scene appears only after the shell, and restores a cleared delegate on
    /// every scene activation.
    func testSceneRegistryRegistersOnAttachAndEveryActivation() {
        let center = NotificationCenter()
        let service = FakeScreenshotService()
        var target: FullPageSceneRegistry.Target?
        let registry = FullPageSceneRegistry(notificationCenter: center) { target }
        let controller = WeeklyReportScreenshotController(renderer: FakePDFRenderer(result: Data("pdf".utf8)))

        registry.attach(controller)
        XCTAssertNil(service.delegate)
        XCTAssertFalse(controller.isRegistered, "no scene yet")

        target = .init(service: service, window: nil)
        center.post(name: UIScene.didActivateNotification, object: nil)
        XCTAssertTrue(service.delegate === controller.delegate, "registered once the scene activates")
        XCTAssertTrue(controller.isRegistered)

        service.delegate = nil
        center.post(name: UIScene.willEnterForegroundNotification, object: nil)
        XCTAssertTrue(service.delegate === controller.delegate, "same service: delegate restored, not skipped")

        service.delegate = nil
        registry.refresh()
        XCTAssertTrue(service.delegate === controller.delegate)
    }

    /// Device regression: pushing Health took Home's registration view out of
    /// the window and cleared the delegate, so iOS never asked on Health. Home
    /// disappearing, or a scene or window lookup that finds nothing mid-transition,
    /// must leave the delegate registered and Health eligible.
    func testPushingHealthKeepsTheDelegateRegistered() {
        let service = FakeScreenshotService()
        var target: FullPageSceneRegistry.Target? = .init(service: service, window: nil)
        let registry = FullPageSceneRegistry(notificationCenter: NotificationCenter()) { target }
        let controller = WeeklyReportScreenshotController(renderer: FakePDFRenderer(result: Data("pdf".utf8)))
        var path: [AppRoute] = []
        controller.setRequestProvider { [weak controller] in
            WeeklyReportScreenshotEligibility.screen(navigationPath: path, isTransientUIPresented: false,
                                                     isTodayOnScreen: controller?.isTodayOnScreen ?? false) == nil
                ? nil : .healthReport(self.makeDocument())
        }
        registry.attach(controller)
        controller.isTodayOnScreen = true
        XCTAssertNotNil(controller.delegate.representationForCurrentRequest())

        // Push Health: the path changes, then Home disappears.
        path = [.healthReport]
        registry.refresh()
        controller.isTodayOnScreen = false
        target = .init(service: nil, window: nil)
        registry.refresh()
        target = nil
        registry.refresh()

        XCTAssertTrue(service.delegate === controller.delegate, "still registered on Health")
        XCTAssertNotNil(controller.delegate.representationForCurrentRequest(), "Health still produces a PDF")
    }

    func testSceneRegistryKeepsTheControllerAliveForTheWeakService() throws {
        let service = FakeScreenshotService()
        let registry = FullPageSceneRegistry(notificationCenter: NotificationCenter()) {
            .init(service: service, window: nil)
        }
        var controller: WeeklyReportScreenshotController? = WeeklyReportScreenshotController(
            renderer: FakePDFRenderer(result: Data("pdf".utf8)))
        registry.attach(try XCTUnwrap(controller))
        controller = nil
        XCTAssertNotNil(service.delegate, "the service holds its delegate weakly; the registry keeps it alive")
    }

    /// Path, scene registration and the provider together: Health pushed from
    /// Home's link is `[.healthReport]`, and a controller registered with a
    /// service hands it the delegate that returns the PDF.
    func testRegisteredControllerServesHealthAndTodayFullPage() throws {
        let service = FakeScreenshotService()
        let controller = WeeklyReportScreenshotController()
        controller.register(with: service)
        let report = ReportDocument.expanded(
            snapshot: makeFullFixtureSnapshot(), calendar: testCalendar(), locale: Locale(identifier: "en_GB"))
        let today = TodayFullPageDocument(date: "Monday 12 October", sections: [
            .init(title: "Today\u{2019}s notes", rows: [.init(value: "None yet")])
        ])
        var path: [AppRoute] = [.healthReport]
        controller.setRequestProvider {
            switch WeeklyReportScreenshotEligibility.screen(navigationPath: path, isTransientUIPresented: false) {
            case .healthReport: .healthReport(report)
            case .today: .today(today)
            case nil: nil
            }
        }
        let delegate = try XCTUnwrap(service.delegate as? WeeklyReportScreenshotDelegate)
        XCTAssertNotNil(delegate.representationForCurrentRequest())
        path = []
        XCTAssertNotNil(delegate.representationForCurrentRequest())
        path = [.foodLog]
        XCTAssertNil(delegate.representationForCurrentRequest())
    }

    func testRendererCreatesOnePageInMemoryPDF() throws {
        let data = try XCTUnwrap(WeeklyReportPDFRenderer().pdfData(for: makeDocument()))
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(pdf.page(at: 1))

        XCTAssertEqual(pdf.numberOfPages, 1)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertGreaterThan(page.getBoxRect(.mediaBox).height, 1_000)
    }

    func testRendererPlacesDocumentTitleAtVisualTopOfPDF() throws {
        let data = try XCTUnwrap(WeeklyReportPDFRenderer().pdfData(for: makeDocument()))
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        let pageText = try XCTUnwrap(page.string)
        let titleRange = (pageText as NSString).range(of: "Weekly Health Report")
        let titleSelection = try XCTUnwrap(page.selection(for: titleRange))
        let titleBounds = titleSelection.bounds(for: page)

        XCTAssertNotEqual(titleRange.location, NSNotFound)
        XCTAssertGreaterThan(titleBounds.midY, page.bounds(for: .mediaBox).midY)
    }

    private func makeDocument(
        includesMedicationSection: Bool = false,
        bloodPressure: MetricState<BloodPressureSummary> = .noDataOrAccess,
        showsMorningDetails: Bool = true,
        showsEveningDetails: Bool = false
    ) -> ReportDocument {
        ReportDocument(
            snapshot: makeSnapshot(
                bloodPressure: bloodPressure,
                includesMedicationSection: includesMedicationSection,
                showsMorningDetails: showsMorningDetails,
                showsEveningDetails: showsEveningDetails
            ),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        )
    }

    private func makeSnapshot(
        steps: StepsState = .noDataOrAccess,
        weight: WeeklyReportViewModel.WeightState = .noDataOrAccess,
        bodyFat: WeeklyReportViewModel.BodyFatState = .noDataOrAccess,
        waist: MetricState<WaistSummary> = .noDataOrAccess,
        glucose: MetricState<GlucoseSummary> = .noDataOrAccess,
        vo2Max: MetricState<VO2MaxSummary> = .noDataOrAccess,
        bloodOxygen: MetricState<BloodOxygenSummary> = .noDataOrAccess,
        bloodPressure: MetricState<BloodPressureSummary> = .noDataOrAccess,
        restingHeartRate: MetricState<HeartMetricTrendSummary> = .noDataOrAccess,
        hrv: MetricState<HeartMetricTrendSummary> = .noDataOrAccess,
        watchCoverage: MetricState<WatchCoverageSummary> = .noDataOrAccess,
        exercise: MetricState<Double> = .noDataOrAccess,
        activeEnergy: MetricState<Double> = .noDataOrAccess,
        workouts: MetricState<WorkoutSummary> = .noDataOrAccess,
        sleep: MetricState<SleepSummary> = .noDataOrAccess,
        medications: MetricState<MedicationSummary> = .noDataOrAccess,
        foodLog: MetricState<FoodLogPeriodSummary> = .noDataOrAccess,
        includesMedicationSection: Bool = false,
        showsMorningDetails: Bool = true,
        showsEveningDetails: Bool = false
    ) -> ReportPresentationSnapshot {
        let calendar = testCalendar()
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 10,
            hour: 12
        ))!
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: now,
            calendar: calendar
        )
        return ReportPresentationSnapshot(
            period: period,
            steps: steps,
            weight: weight,
            bodyFat: bodyFat,
            waist: waist,
            glucose: glucose,
            vo2Max: vo2Max,
            bloodOxygen: bloodOxygen,
            bloodPressure: bloodPressure,
            restingHeartRate: restingHeartRate,
            hrv: hrv,
            watchCoverage: watchCoverage,
            exercise: exercise,
            activeEnergy: activeEnergy,
            workouts: workouts,
            sleep: sleep,
            medications: medications,
            foodLog: foodLog,
            includesMedicationSection: includesMedicationSection,
            showsMorningBloodPressureDetails: showsMorningDetails,
            showsEveningBloodPressureDetails: showsEveningDetails
        )
    }

    private func makeFullFixtureSnapshot() -> ReportPresentationSnapshot {
        let calendar = testCalendar()
        let now = date(2026, 9, 10, hour: 12, calendar: calendar)
        let measured = date(2026, 9, 9, hour: 8, calendar: calendar)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: now,
            calendar: calendar
        )
        let dailyGlucose = period.completedDays.map {
            DailyGlucoseValue(
                day: $0,
                averageMillimolesPerLiter: 5.8,
                minimumMillimolesPerLiter: 3.9,
                maximumMillimolesPerLiter: 8.7,
                sourceNames: ["Synthetic Sensor"]
            )
        }
        let dailyOxygen = period.completedDays.map {
            DailyOxygenSaturationValue(
                day: $0,
                medianPercentage: 97,
                sampleCount: 4,
                sourceNames: ["Synthetic Watch"]
            )
        }
        let heartCurrent = HeartMetricSummary(dailyValues: [], average: 73)
        let hrvCurrent = HeartMetricSummary(dailyValues: [], average: 42)
        let medication = MedicationSummary.aggregate([
            MedicationDoseRecord(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000055")!,
                medicationKey: "synthetic-20",
                medicationName: "SyntheticMed 20 mg",
                date: measured,
                quantity: 1,
                unitLabel: "dose"
            )
        ])!

        return ReportPresentationSnapshot(
            period: period,
            steps: .loaded(
                StepSummary(
                    dailyTotals: [], totalSteps: 49_000, averageDailySteps: 7_000,
                    reportingDayCount: 7, daysWithVisibleData: 7
                ),
                trend: .calculated(StepTrendSummary(
                    current: StepSummary(
                        dailyTotals: [], totalSteps: 49_000, averageDailySteps: 7_000,
                        reportingDayCount: 7, daysWithVisibleData: 7
                    ),
                    previous: StepSummary(
                        dailyTotals: [], totalSteps: 46_200, averageDailySteps: 6_600,
                        reportingDayCount: 7, daysWithVisibleData: 7
                    ),
                    previousDailyTotals: [],
                    completedDayCount: 7,
                    requiredSampledDays: 5,
                    change: (7_000 - 6_600) / 6_600 * 100
                ))
            ),
            weight: .available(WeightTrendSummary(
                latest: WeightMeasurement(date: measured, kilograms: 100.6),
                currentSevenDayAverage: 100.8,
                previousSevenDayAverage: 101.2,
                trendKilograms: -0.4,
                dailyValues: []
            )),
            bodyFat: .available(BodyFatTrendSummary(
                latest: BodyFatMeasurement(date: measured, percentage: 26.5),
                sevenDayAverage: 26.6,
                current28DayAverage: 26.7,
                previous28DayAverage: 27.6,
                trendPercentagePoints: -0.9,
                dailyValues: [],
                measurements: []
            )),
            waist: .available(WaistSummary(
                latest: WaistMeasurement(date: measured, centimetres: 101.4),
                comparison: WaistMeasurement(date: measured, centimetres: 103.1),
                fourWeekChangeCentimetres: -1.7,
                measurements: []
            )),
            glucose: .available(GlucoseSummary(
                dailyValues: dailyGlucose,
                averageMillimolesPerLiter: 5.8,
                minimumMillimolesPerLiter: 3.9,
                maximumMillimolesPerLiter: 8.7
            )),
            vo2Max: .available(VO2MaxSummary(
                latest: VO2MaxMeasurement(
                    date: measured,
                    millilitresPerKilogramMinute: 32.1,
                    sourceName: "Synthetic Watch"
                ),
                fourWeek: VO2MaxWindowSummary(average: 31.8, sampledDayCount: 8),
                threeMonth: VO2MaxWindowSummary(average: 30.9, sampledDayCount: 24),
                sixMonth: VO2MaxWindowSummary(average: 29.7, sampledDayCount: 51),
                dailyValues: [],
                measurements: []
            )),
            bloodOxygen: .available(BloodOxygenSummary(
                latest: OxygenSaturationMeasurement(
                    date: measured,
                    percentage: 97,
                    sourceName: "Synthetic Watch"
                ),
                dailyValues: dailyOxygen,
                typicalPercentage: 97,
                minimumDailyMedian: 96,
                maximumDailyMedian: 98,
                measurements: []
            )),
            bloodPressure: .available(syntheticBloodPressureSummary()),
            restingHeartRate: .available(HeartMetricTrendSummary(
                current: heartCurrent,
                previous: HeartMetricSummary(dailyValues: [], average: 70),
                trend: 3
            )),
            hrv: .available(HeartMetricTrendSummary(
                current: hrvCurrent,
                previous: HeartMetricSummary(dailyValues: [], average: 47),
                trend: -5
            )),
            watchCoverage: .available(WatchCoverageSummary(
                reportingDayCount: 7,
                coveredDays: Array(period.completedDays.prefix(4))
            )),
            exercise: .available(89),
            activeEnergy: .available(1_974),
            workouts: .available(WorkoutSummary(workouts: [
                WorkoutRecord(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000056")!,
                    startDate: measured,
                    duration: 1_800,
                    activityName: "Walking"
                )
            ])),
            sleep: .available(SleepSummary(nights: [], averageDuration: 6 * 3_600 + 48 * 60)),
            medications: .available(medication),
            foodLog: .available(FoodLogFixtures.normalWeek(period: period, calendar: calendar)),
            includesMedicationSection: true,
            showsMorningBloodPressureDetails: true,
            showsEveningBloodPressureDetails: true
        )
    }

    private func syntheticBloodPressureSummary() -> BloodPressureSummary {
        let calendar = testCalendar()
        let date = calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 9,
            hour: 8
        ))!
        let reading = BloodPressureReading(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000033")!,
            date: date,
            systolicMillimetresOfMercury: 120,
            diastolicMillimetresOfMercury: 75,
            sourceName: "Synthetic Monitor"
        )
        let batch = BloodPressureBatchSummary(
            averageSystolic: 120,
            averageDiastolic: 75,
            readingCount: 1,
            firstReadingDate: date,
            latestReadingDate: date,
            sourceNames: ["Synthetic Monitor"]
        )
        let slot = BloodPressurePeriodSlotSummary(
            averageSystolic: 120,
            averageDiastolic: 75,
            sampledDayCount: 1,
            reportingDayCount: 7,
            readingCount: 1
        )
        return BloodPressureSummary(
            latest: reading,
            latestMorningBatch: batch,
            latestEveningBatch: batch,
            morning: slot,
            evening: slot,
            dailyValues: [],
            readings: [reading]
        )
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func stateRowExpectation(
        for sectionID: ReportDocument.SectionID,
        stateCase: SyntheticDocumentStateCase
    ) -> DocumentStateRowExpectation {
        switch sectionID {
        case .steps:
            return stateCase.specialisedExpectation(
                idPrefix: "steps",
                label: nil,
                loading: "Reading Apple Health…",
                noData: "No step data is visible, or Health access was not granted.",
                failed: "Step query failed: Synthetic failure"
            )
        case .weight:
            return stateCase.specialisedExpectation(
                idPrefix: "weight",
                label: nil,
                loading: "Reading latest weight…",
                noData: "No weight data is visible, or Health access was not granted.",
                failed: "Weight query failed: Synthetic failure"
            )
        case .bodyComposition:
            return stateCase.specialisedExpectation(
                idPrefix: "body-fat",
                label: nil,
                loading: "Reading body-fat history…",
                noData: "No body-fat data is visible, or Health access was not granted.",
                failed: "Body-fat query failed: Synthetic failure"
            )
        case .bloodPressure:
            return stateCase.specialisedExpectation(
                idPrefix: "blood-pressure",
                label: nil,
                loading: "Reading blood pressure…",
                noData: "No complete blood-pressure readings are visible, or Health access was not granted.",
                failed: "Blood-pressure query failed: Synthetic failure"
            )
        case .medications:
            return stateCase.specialisedExpectation(
                idPrefix: "medications",
                label: nil,
                loading: "Reading authorised medication events…",
                noData: "No taken medication events are visible for this period.",
                failed: "Medication query failed: Synthetic failure"
            )
        case .heart:
            return stateCase.genericExpectation(
                id: "resting-heart-rate-average",
                label: "Resting HR Average"
            )
        case .cardiorespiratory:
            return stateCase.genericExpectation(id: "vo2-max-latest", label: "Latest VO₂ Max")
        case .glucose:
            return stateCase.genericExpectation(id: "glucose-average", label: "Daily Average")
        case .activity:
            return stateCase.genericExpectation(id: "active-energy", label: "Active Energy")
        case .sleep:
            return stateCase.genericExpectation(id: "sleep-average", label: "Average Sleep")
        case .foodLog:
            // The food log is not Apple Health: its own sentences, no technical message.
            switch stateCase {
            case .idle, .loading:
                return DocumentStateRowExpectation(
                    id: "food-loading", label: nil, value: "Reading the food log…", style: .loading
                )
            case .noDataOrAccess, .healthUnavailable:
                return DocumentStateRowExpectation(
                    id: "food-no-data", label: nil, value: "No food logged in this period.", style: .secondary
                )
            case .failed:
                return DocumentStateRowExpectation(
                    id: "food-failed", label: nil, value: "Could not read the food log.", style: .failure
                )
            }
        }
    }

    private func additionalGenericStateRows(
        for sectionID: ReportDocument.SectionID
    ) -> [DocumentStateRowTarget] {
        switch sectionID {
        case .steps, .weight, .bloodPressure, .medications, .foodLog:
            []
        case .bodyComposition:
            [DocumentStateRowTarget(id: "waist", label: "Waist Circumference")]
        case .heart:
            [
                DocumentStateRowTarget(id: "resting-heart-rate-trend", label: "Resting HR Trend"),
                DocumentStateRowTarget(id: "hrv-average", label: "HRV Average"),
                DocumentStateRowTarget(id: "hrv-trend", label: "HRV Trend"),
                DocumentStateRowTarget(id: "watch-coverage", label: "Watch Data Coverage")
            ]
        case .cardiorespiratory:
            [DocumentStateRowTarget(id: "blood-oxygen-latest", label: "Latest Blood Oxygen")]
        case .glucose:
            [
                DocumentStateRowTarget(id: "glucose-range", label: "Observed Range"),
                DocumentStateRowTarget(id: "glucose-coverage", label: "Data Coverage")
            ]
        case .activity:
            [
                DocumentStateRowTarget(id: "exercise", label: "Exercise"),
                DocumentStateRowTarget(id: "workouts", label: "Workouts")
            ]
        case .sleep:
            []
        }
    }
}

private struct ScreenshotNoFoodSearch: GenericFoodSearching {
    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        guard let evidence = request.captureEvidence else { throw FoodLedgerValidationError.invalidProvenance }
        return .noResult(GenericFoodNoResultRoute(evidence: evidence))
    }
}

private final class ScreenshotMemoryDailySessionStore: DailyDriveSecurePersisting, @unchecked Sendable {
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        values[account] = data
    }

    func load(account: String) throws -> Data? {
        values[account]
    }

    func delete(account: String) throws {
        values.removeValue(forKey: account)
    }
}

private enum SyntheticDocumentStateCase: CaseIterable {
    case idle
    case loading
    case noDataOrAccess
    case healthUnavailable
    case failed

    var stepsState: StepsState {
        switch self {
        case .idle: .idle
        case .loading: .loading
        case .noDataOrAccess: .noDataOrAccess
        case .healthUnavailable: .healthUnavailable
        case .failed: .failed("Synthetic failure")
        }
    }

    func metricState<Value: Equatable>() -> MetricState<Value> {
        switch self {
        case .idle: .idle
        case .loading: .loading
        case .noDataOrAccess: .noDataOrAccess
        case .healthUnavailable: .healthUnavailable
        case .failed: .failed("Synthetic failure")
        }
    }

    func genericExpectation(
        id: String,
        label: String
    ) -> DocumentStateRowExpectation {
        switch self {
        case .idle, .loading:
            DocumentStateRowExpectation(id: id, label: label, value: "Loading…", style: .loading)
        case .noDataOrAccess:
            DocumentStateRowExpectation(id: id, label: label, value: "No data", style: .secondary)
        case .healthUnavailable:
            DocumentStateRowExpectation(id: id, label: label, value: "Unavailable", style: .secondary)
        case .failed:
            DocumentStateRowExpectation(id: id, label: label, value: "Query failed", style: .failure)
        }
    }

    func specialisedExpectation(
        idPrefix: String,
        label: String?,
        loading: String,
        noData: String,
        failed: String
    ) -> DocumentStateRowExpectation {
        switch self {
        case .idle, .loading:
            DocumentStateRowExpectation(
                id: "\(idPrefix)-loading", label: label, value: loading, style: .loading
            )
        case .noDataOrAccess:
            DocumentStateRowExpectation(
                id: "\(idPrefix)-no-data", label: label, value: noData, style: .secondary
            )
        case .healthUnavailable:
            DocumentStateRowExpectation(
                id: "\(idPrefix)-unavailable",
                label: label,
                value: "Health data is unavailable on this device.",
                style: .secondary
            )
        case .failed:
            DocumentStateRowExpectation(
                id: "\(idPrefix)-failed", label: label, value: failed, style: .failure
            )
        }
    }
}

private struct DocumentStateRowExpectation {
    let id: String
    let label: String?
    let value: String
    let style: ReportDocument.RowStyle
}

private struct DocumentStateRowTarget {
    let id: String
    let label: String
}


@MainActor
private final class FakeScreenshotService: ScreenshotServiceRegistering {
    weak var delegate: (any UIScreenshotServiceDelegate)?
}

@MainActor
private final class FakePDFRenderer: WeeklyReportPDFRendering {
    private(set) var documents: [FullPageDocument] = []
    private let result: Data?

    init(result: Data?) {
        self.result = result
    }

    func pdfData(for document: FullPageDocument) -> Data? {
        documents.append(document)
        return result
    }
}

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

private struct EmptyNutritionSourceSelectionStore: NutritionSourceSelectionPersisting {
    func loadBundleIdentifier() -> String? { nil }
    func saveBundleIdentifier(_ bundleIdentifier: String?) {}
}

private struct UnusedDailyHealthDataProvider: DailyHealthExportDataProviding {
    var isHealthDataAvailable: Bool { false }

    func requestReadAuthorization() async throws {}
    func requestNutritionReadAuthorization() async throws {}
    func fetchVisibleNutritionSources() async throws -> [NutritionSource] { [] }

    func fetchDailyHealthExportInputs(
        for window: DailyExportWindow,
        nutritionSourceBundleIdentifier: String,
        includeWorkoutEnrichment: Bool
    ) async throws -> DailyHealthExportInputs {
        throw HealthDataError.unavailable
    }
}

// MARK: #200 Health summary tiles

extension WeeklyReportScreenshotTests {
    func testTilePinsNameRowsThatExistInTheExpandedFullFixture() throws {
        let document = ReportDocument.expanded(
            snapshot: makeFullFixtureSnapshot(),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        )
        XCTAssertEqual(HealthSummaryTiles.pins.map(\.kind), HealthSummaryTile.Kind.allCases)
        XCTAssertEqual(HealthSummaryTiles.pins.map(\.primaryRowID), [
            "steps-average", "sleep-average", "resting-heart-rate-average",
            "weight-average", "blood-pressure-morning-average", "food-energy-average"
        ])
        XCTAssertEqual(HealthSummaryTiles.pins.map(\.detailRowID), [
            "steps-coverage", nil, "resting-heart-rate-trend",
            "weight-trend", "blood-pressure-morning-coverage", "food-days-logged"
        ])
        XCTAssertEqual(HealthSummaryTiles.pins.map(\.trendRowID), [
            "steps-trend", nil, nil, nil, nil
        ])
        let tiles = HealthSummaryTiles.make(from: document)
        XCTAssertEqual(tiles.map(\.kind), HealthSummaryTile.Kind.allCases)
        for (tile, pin) in zip(tiles, HealthSummaryTiles.pins) {
            let section = try XCTUnwrap(document.sections.first { $0.id == pin.section })
            // Byte for byte: label, value and style copied from the row.
            XCTAssertEqual(tile.primary, section.rows.first { $0.id == pin.primaryRowID }, "\(pin.kind)")
            if let detailID = pin.detailRowID {
                XCTAssertNotNil(tile.detail, "\(pin.kind)")
                XCTAssertEqual(tile.detail, section.rows.first { $0.id == detailID }, "\(pin.kind)")
            } else {
                XCTAssertNil(tile.detail)
            }
            if let trendID = pin.trendRowID {
                XCTAssertNotNil(tile.trend, "\(pin.kind)")
                XCTAssertEqual(tile.trend, section.rows.first { $0.id == trendID }, "\(pin.kind)")
            } else {
                XCTAssertNil(tile.trend)
            }
        }
        let stepsTile = try XCTUnwrap(tiles.first { $0.kind == .steps })
        XCTAssertEqual(stepsTile.trend?.value, "+6% vs previous 7d")
        let weight = try XCTUnwrap(tiles.first { $0.kind == .weight })
        XCTAssertEqual(weight.primary.label, "7-day Average")
    }

    func testTilesCopyStateRowsAndMapStepsToSharedVocabulary() throws {
        let expectedSteps: [(SyntheticDocumentStateCase, String, ReportDocument.RowStyle)] = [
            (.idle, "Loading…", .loading),
            (.loading, "Loading…", .loading),
            (.noDataOrAccess, "No data", .secondary),
            (.healthUnavailable, "Unavailable", .secondary),
            (.failed, "Could not read", .failure)
        ]
        for (stateCase, stepsValue, stepsStyle) in expectedSteps {
            let document = ReportDocument.expanded(
                snapshot: makeSnapshot(
                    steps: stateCase.stepsState,
                    weight: stateCase.metricState(),
                    bloodPressure: stateCase.metricState(),
                    restingHeartRate: stateCase.metricState(),
                    sleep: stateCase.metricState()
                ),
                calendar: testCalendar(),
                locale: Locale(identifier: "en_GB")
            )
            let tiles = HealthSummaryTiles.make(from: document)
            XCTAssertEqual(tiles.map(\.kind), HealthSummaryTile.Kind.allCases, "\(stateCase)")
            let steps = try XCTUnwrap(tiles.first { $0.kind == .steps })
            XCTAssertEqual(steps.primary.value, stepsValue, "\(stateCase)")
            XCTAssertEqual(steps.primary.style, stepsStyle, "\(stateCase)")
            XCTAssertNil(steps.detail)
            XCTAssertNil(steps.trend)

            for tile in tiles where tile.kind != .steps {
                let pin = try XCTUnwrap(HealthSummaryTiles.pins.first { $0.kind == tile.kind })
                let section = try XCTUnwrap(document.sections.first { $0.id == pin.section })
                let source = try XCTUnwrap(section.rows.first { $0.id == pin.primaryRowID } ?? section.rows.first)
                // Verbatim, except that failures use the short shared term.
                let expected = source.style == .failure
                    ? ReportDocument.Row(source.id, label: source.label, value: "Could not read", style: .failure)
                    : source
                XCTAssertEqual(tile.primary, expected, "\(tile.kind), \(stateCase)")
            }
        }

        // The long failure message stays in the section row (and Copy all).
        let failedDocument = ReportDocument.expanded(
            snapshot: makeSnapshot(weight: .failed("com.apple.developer.healthkit entitlement missing")),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        )
        let weightTile = try XCTUnwrap(HealthSummaryTiles.make(from: failedDocument).first { $0.kind == .weight })
        XCTAssertEqual(weightTile.primary.value, "Could not read")
        XCTAssertEqual(weightTile.primary.style, .failure)
        XCTAssertTrue(failedDocument.searchableText.contains("com.apple.developer.healthkit entitlement missing"))

        let noCompletedDays = HealthSummaryTiles.make(from: ReportDocument.expanded(
            snapshot: makeSnapshot(steps: .noCompletedDays),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        ))
        XCTAssertEqual(noCompletedDays.first?.primary.value, "No completed days")
        XCTAssertNotEqual(MetricRowVocabulary.noCompletedDays, MetricRowVocabulary.unavailable)
    }

    // MARK: Screen copy (UX copy pass, #140)

    /// The screen, tiles and Full Page reword a failed read and Title Case labels; Copy all
    /// (the README's text contract) keeps its labels and says "Could not read Apple Health."
    /// for a failed read, with the technical message only in Developer tools.
    func testDisplayDocumentRewordsFailuresAndLabelsWhileCopyAllKeepsLabels() throws {
        let calendar = testCalendar()
        let locale = Locale(identifier: "en_GB")
        let entitlement = "Missing com.apple.developer.healthkit entitlement."
        let snapshot = makeSnapshot(
            steps: .failed(entitlement),
            bloodPressure: .failed(entitlement),
            restingHeartRate: .failed(entitlement),
            medications: .failed(entitlement),
            includesMedicationSection: true
        )
        let document = ReportDocument.expanded(snapshot: snapshot, calendar: calendar, locale: locale)
        let display = document.forDisplay()
        let generatedAt = date(2026, 9, 10, hour: 12, calendar: calendar)

        // Copy all keeps its Title Case labels; a failed read is plain wording, no message.
        let copied = document.plainText(generatedAt: generatedAt, calendar: calendar, locale: locale)
        XCTAssertTrue(copied.contains("\nSteps\nCould not read Apple Health.\n"))
        XCTAssertTrue(copied.contains("Resting HR Average: Could not read Apple Health."))
        XCTAssertTrue(copied.contains("\nBlood Pressure\n"))
        for diagnostic in ["entitlement", "com.apple", "query failed", "Query failed"] {
            XCTAssertFalse(copied.contains(diagnostic), diagnostic)
        }

        // Same rows, ids, styles and order; only wording differs.
        XCTAssertEqual(display.sections.map(\.id), document.sections.map(\.id))
        for (shown, source) in zip(display.sections, document.sections) {
            XCTAssertEqual(shown.rows.map(\.id), source.rows.map(\.id))
            XCTAssertEqual(shown.rows.map(\.style), source.rows.map(\.style))
            for (row, original) in zip(shown.rows, source.rows) where original.style != .failure {
                XCTAssertEqual(row.value, original.value, row.id)
            }
        }
        let shownText = display.searchableText
        for diagnostic in ["entitlement", "com.apple", "query failed", "Query failed"] {
            XCTAssertFalse(shownText.contains(diagnostic), diagnostic)
        }
        let failedRows = display.sections.flatMap(\.rows).filter { $0.style == .failure }
        XCTAssertFalse(failedRows.isEmpty)
        XCTAssertTrue(failedRows.allSatisfy { $0.value == "Could not read Apple Health." })

        // Sentence case on screen; README's Copy all labels stay as they are.
        XCTAssertEqual(display.sections.first { $0.id == .bloodPressure }?.title, "Blood pressure")
        XCTAssertEqual(display.sections.first { $0.id == .medications }?.title, "Medications taken")
        let heart = try XCTUnwrap(display.sections.first { $0.id == .heart })
        XCTAssertEqual(heart.rows.first { $0.id == "resting-heart-rate-average" }?.label, "Resting heart rate average")
        XCTAssertEqual(heart.rows.first { $0.id == "watch-coverage" }?.label, "Days with Apple Watch data")

        // Developer tools gets each read's own message, including metric rows whose Copy all
        // text is only "Query failed".
        XCTAssertEqual(snapshot.readFailures, [
            ReportReadFailure(metric: "Steps", message: entitlement),
            ReportReadFailure(metric: "Resting heart rate", message: entitlement),
            ReportReadFailure(metric: "Blood pressure", message: entitlement),
            ReportReadFailure(metric: "Medications", message: entitlement)
        ])
        XCTAssertTrue(makeSnapshot(medications: .failed("x"), includesMedicationSection: false).readFailures.isEmpty)

        // Idempotent: the display of a display document is the same document.
        XCTAssertEqual(display.forDisplay(), display)

        // Tiles from the display document use the short plain term.
        let tiles = HealthSummaryTiles.make(from: display)
        XCTAssertEqual(tiles.first { $0.kind == .steps }?.primary.value, "Could not read")
        XCTAssertEqual(tiles.first { $0.kind == .restingHeartRate }?.primary.value, "Could not read")
    }

    /// Golden Copy all text for a report with section-level and metric-row failures
    /// (owner decision on #140): every failure reads "Could not read Apple Health.";
    /// labels, other values, no-data wording and order are unchanged.
    func testCopyAllGoldenTextWithFailedReads() throws {
        let calendar = testCalendar()
        let locale = Locale(identifier: "en_GB")
        let entitlement = "Missing com.apple.developer.healthkit entitlement."
        let generatedAt = date(2026, 9, 10, hour: 12, calendar: calendar)
        let snapshot = makeSnapshot(
            steps: .failed(entitlement),
            bodyFat: .failed(entitlement),
            glucose: .failed("Synthetic glucose failure"),
            bloodPressure: .failed(entitlement),
            restingHeartRate: .failed(entitlement),
            activeEnergy: .failed("Synthetic failure"),
            medications: .failed(entitlement),
            includesMedicationSection: true
        )
        let document = ReportDocument.expanded(snapshot: snapshot, calendar: calendar, locale: locale)
        let copied = document.plainText(generatedAt: generatedAt, calendar: calendar, locale: locale)

        XCTAssertEqual(copied, Self.copyAllGoldenWithFailures)

        // Only the failure rows differ from the rendering before this change.
        let before = Self.legacyPlainText(document, generatedAt: generatedAt, calendar: calendar, locale: locale)
        let beforeLines = before.components(separatedBy: "\n")
        let copiedLines = copied.components(separatedBy: "\n")
        XCTAssertEqual(beforeLines.count, copiedLines.count)
        let failureValues = document.sections.flatMap(\.rows).filter { $0.style == .failure }.map(\.value)
        let changed = zip(beforeLines, copiedLines).filter { $0 != $1 }
        XCTAssertEqual(changed.count, failureValues.count)
        for (old, new) in changed {
            XCTAssertTrue(failureValues.contains { old.hasSuffix($0) }, old)
            XCTAssertTrue(new.hasSuffix("Could not read Apple Health."), new)
        }

        // Developer tools still lists each read's technical message.
        XCTAssertTrue(snapshot.readFailures.contains(ReportReadFailure(metric: "Steps", message: entitlement)))
        XCTAssertTrue(snapshot.readFailures.contains(ReportReadFailure(metric: "Glucose", message: "Synthetic glucose failure")))
        XCTAssertEqual(snapshot.readFailures.count, 7)
    }

    /// Without failures, Copy all is byte-identical to the rendering before the
    /// failure-wording change.
    func testCopyAllWithoutFailuresIsByteIdenticalToBefore() throws {
        let calendar = testCalendar()
        let locale = Locale(identifier: "en_GB")
        let generatedAt = date(2026, 9, 10, hour: 12, calendar: calendar)
        for snapshot in [makeFullFixtureSnapshot(), makeSnapshot(), makeSnapshot(includesMedicationSection: true)] {
            let document = ReportDocument.expanded(snapshot: snapshot, calendar: calendar, locale: locale)
            XCTAssertFalse(document.sections.flatMap(\.rows).contains { $0.style == .failure })
            XCTAssertEqual(
                document.plainText(generatedAt: generatedAt, calendar: calendar, locale: locale),
                Self.legacyPlainText(document, generatedAt: generatedAt, calendar: calendar, locale: locale)
            )
        }
    }

    /// The Copy all renderer as it was before failures were reworded: every row value verbatim.
    /// It keeps the #216 group headings so only the failure wording is compared.
    private static func legacyPlainText(
        _ document: ReportDocument,
        generatedAt: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let generated = HealthReportFormatter.dateAndTime(generatedAt, calendar: calendar, locale: locale)
        let preamble = [document.title, document.selection, document.period, "Generated: \(generated)"]
            .joined(separator: "\n")
        let sectionText = document.groupedSections.flatMap { grouped in
            [ReportDocument.copyAllGroupHeading(grouped.heading)]
                + grouped.sections.map { section in
                    var lines = [section.title]
                    lines += section.rows.map { row in
                        row.label.map { "\($0): \(row.value)" } ?? row.value
                    }
                    if let footer = section.footer { lines.append(footer) }
                    return lines.joined(separator: "\n")
                }
        }
        return ([preamble] + sectionText).joined(separator: "\n\n")
    }

    private static let copyAllGoldenWithFailures = """
    Weekly Health Report
    Last 7 Completed Days
    3–9 Sep 2026
    Generated: 10/09/26 - 12:00

    DAILY ACTIVITY

    Steps
    Could not read Apple Health.

    Activity
    Active Energy: Could not read Apple Health.
    Exercise: No data
    Workouts: No data

    FOOD AND WATER

    Food and water
    No food logged in this period.
    Logged in this app; not a measure of everything eaten or drunk.

    BODY

    Weight
    No weight data is visible, or Health access was not granted.

    Body Composition
    Could not read Apple Health.
    Waist Circumference: No data

    HEART AND SLEEP

    Heart
    Resting HR Average: Could not read Apple Health.
    Resting HR Trend: Could not read Apple Health.
    HRV Average: No data
    HRV Trend: No data
    Watch Data Coverage: No data

    Blood Pressure
    Could not read Apple Health.
    Period averages use completed days. Morning is before 14:00; evening is from 17:00. Mid-afternoon readings are excluded from both slot summaries.

    Sleep
    Average Sleep: No data

    FITNESS AND BLOOD OXYGEN

    Cardiorespiratory
    Latest VO₂ Max: No data
    Latest Blood Oxygen: No data
    Apple Watch blood-oxygen measurements are wellness estimates, not medical measurements.

    GLUCOSE

    Glucose
    Daily Average: Could not read Apple Health.
    Observed Range: Could not read Apple Health.
    Data Coverage: Could not read Apple Health.

    MEDICATIONS

    Medications Taken
    Could not read Apple Health.
    """

    /// Latest weight may be today; the average and trend use the last seven completed days.
    /// The screen says so; values and Copy all are unchanged.
    func testDisplayWeightSeparatesLatestFromCompletedDayAverage() throws {
        let calendar = testCalendar()
        let locale = Locale(identifier: "en_GB")
        let document = ReportDocument.expanded(snapshot: makeFullFixtureSnapshot(), calendar: calendar, locale: locale)
        let display = document.forDisplay()
        let weight = try XCTUnwrap(display.sections.first { $0.id == .weight })
        let source = try XCTUnwrap(document.sections.first { $0.id == .weight })
        XCTAssertEqual(weight.rows.map(\.value), source.rows.map(\.value))
        XCTAssertEqual(weight.rows.first { $0.id == "weight-latest" }?.label, "Latest weight")
        XCTAssertEqual(weight.rows.first { $0.id == "weight-measured" }?.label, "Measured")
        XCTAssertEqual(weight.rows.first { $0.id == "weight-average" }?.label, "Average, last 7 completed days")
        XCTAssertEqual(weight.footer, ReportDocument.weightDisplayFooter)
        XCTAssertTrue(weight.footer?.contains("the trend compares them with the 7 days before") == true)
        XCTAssertEqual(display.forDisplay(), display, "the weight note is never appended twice")
        XCTAssertNil(source.footer, "Copy all gains no footer")
        XCTAssertEqual(source.rows.first { $0.id == "weight-average" }?.label, "7-day Average")

        let tile = try XCTUnwrap(HealthSummaryTiles.make(from: display).first { $0.kind == .weight })
        XCTAssertEqual(tile.primary.label, "Average, last 7 completed days")
        XCTAssertEqual(tile.primary.value, source.rows.first { $0.id == "weight-average" }?.value)

        // A failed weight read has no average row, so no note about one.
        let failed = ReportDocument.expanded(snapshot: makeSnapshot(weight: .failed("x")), calendar: calendar, locale: locale)
        XCTAssertNil(failed.forDisplay().sections.first { $0.id == .weight }?.footer)
    }

    /// Full Page renders the screen's wording, not Copy all's technical failure text.
    @MainActor
    func testFullPagePDFUsesDisplayWording() throws {
        let entitlement = "Missing com.apple.developer.healthkit entitlement."
        let document = ReportDocument.expanded(
            snapshot: makeSnapshot(steps: .failed(entitlement), restingHeartRate: .failed(entitlement)),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        )
        let data = try XCTUnwrap(WeeklyReportPDFRenderer().pdfData(for: .healthReport(document)))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        XCTAssertTrue(text.contains("Could not read Apple Health."))
        XCTAssertTrue(text.contains("Resting heart rate average"))
        for diagnostic in ["entitlement", "query failed", "Query failed", "Resting HR"] {
            XCTAssertFalse(text.contains(diagnostic), diagnostic)
        }
    }

    func testTilesDoNotDependOnOnScreenBloodPressureExpansion() throws {
        let summary = syntheticBloodPressureSummary()
        var results: [[HealthSummaryTile]] = []
        for morning in [false, true] {
            for evening in [false, true] {
                results.append(HealthSummaryTiles.make(from: ReportDocument.expanded(
                    snapshot: makeSnapshot(
                        bloodPressure: .available(summary),
                        showsMorningDetails: morning,
                        showsEveningDetails: evening
                    ),
                    calendar: testCalendar(),
                    locale: Locale(identifier: "en_GB")
                )))
            }
        }
        XCTAssertTrue(results.allSatisfy { $0 == results[0] })
        let bloodPressure = try XCTUnwrap(results[0].first { $0.kind == .morningBloodPressure })
        XCTAssertEqual(bloodPressure.detail?.id, "blood-pressure-morning-coverage")

        // The on-screen collapsed document lacks the row, which is why tiles
        // must never be built from it.
        let collapsed = makeDocument(bloodPressure: .available(summary), showsMorningDetails: false)
        XCTAssertFalse(collapsed.sections.flatMap(\.rows).contains { $0.id == "blood-pressure-morning-coverage" })
    }

    func testHealthAndExportRenderAtDefaultAndAccessibilitySizes() async throws {
        let calendar = testCalendar()
        let viewModel = WeeklyReportViewModel(healthData: FakeHealthDataProvider(), calendar: calendar, now: Date.init)
        await viewModel.refresh()
        let state = WeeklyReportPresentationState()
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 15))!
        let store = EmptyDailyNotesStore()
        let notes = DailyNotesController(store: store, calendar: calendar, now: { now })
        let session = DailyDriveSessionController(
            keychain: ScreenshotMemoryDailySessionStore(), drive: DailyDriveAPI(),
            exportService: DailyHealthExportService(healthData: UnusedDailyHealthDataProvider(), notesStore: store, calendar: calendar, now: { now }),
            identityStore: ControllerMemoryDailyIdentityStore(),
            nutritionSourceSelection: EmptyNutritionSourceSelectionStore(), notes: notes
        )
        for scheme in [ColorScheme.light, .dark] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                renderFoodView(NavigationStack {
                    HealthReportView(viewModel: viewModel, presentationState: state)
                        .environment(\.dynamicTypeSize, size)
                        .environment(\.colorScheme, scheme)
                }, name: "Health - \(scheme) - \(size)")
                renderFoodView(NavigationStack {
                    DailyExportView(session: session)
                        .environment(\.dynamicTypeSize, size)
                        .environment(\.colorScheme, scheme)
                }, name: "Export - \(scheme) - \(size)")
                renderFoodView(NavigationStack {
                    DriveDestinationSettingsView(session: session)
                        .environment(\.dynamicTypeSize, size)
                        .environment(\.colorScheme, scheme)
                }, name: "Settings Google Drive - \(scheme) - \(size)")
            }
        }
    }
}
