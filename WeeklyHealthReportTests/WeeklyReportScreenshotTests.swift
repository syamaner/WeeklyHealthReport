import CoreGraphics
import HealthKit
import PDFKit
import XCTest
@testable import DriveExportKit
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
@MainActor
final class WeeklyReportScreenshotTests: XCTestCase {
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

        let view = WeeklyReportView(
            viewModel: viewModel,
            dailyExport: dailyExport,
            navigation: WeeklyReportNavigationController(),
            medicationAccess: MedicationAccessRequest(store: store)
        )

        XCTAssertTrue(view.viewModel === viewModel)
        XCTAssertTrue(view.medicationAccess.store === store)
    }

    func testDocumentUsesCompleteDeterministicSectionOrdering() {
        let document = makeDocument(includesMedicationSection: true)

        XCTAssertEqual(
            document.sections.map(\.id),
            ReportDocument.SectionID.allCases
        )
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
        steps|steps-total|Weekly Total|49,000|standard
        footer|steps|
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
        section|activity|Activity
        activity|active-energy|Active Energy|1,974 kcal|standard
        activity|exercise|Exercise|89 min|standard
        activity|workouts|Workouts|1|standard
        activity|workout-time|Workout Time|30m|standard
        activity|workout-0|Walking|30m — 09/09/26 - 08:00|standard
        footer|activity|
        section|sleep|Sleep
        sleep|sleep-average|Average Sleep|6h 48m|standard
        footer|sleep|
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

    func testOnlyMainReportWithoutTransientUIPresentationIsEligible() {
        XCTAssertTrue(WeeklyReportScreenshotEligibility.isEligible(
            navigationPath: [],
            isTransientUIPresented: false
        ))
        XCTAssertFalse(WeeklyReportScreenshotEligibility.isEligible(
            navigationPath: [],
            isTransientUIPresented: true
        ))
        for route in WeeklyReportRoute.allCasesForScreenshotTesting {
            XCTAssertFalse(WeeklyReportScreenshotEligibility.isEligible(
                navigationPath: [route],
                isTransientUIPresented: false
            ))
        }
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
            "Refresh",
            "Last refreshed",
            "Developer Diagnostics",
            "Medication Access",
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

        delegate.setRequestProvider { self.makeDocument() }
        XCTAssertNil(delegate.representationForCurrentRequest())
        XCTAssertEqual(renderer.documents.count, 1)
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
            steps: .loaded(StepSummary(
                dailyTotals: [], totalSteps: 49_000, averageDailySteps: 7_000,
                reportingDayCount: 7, daysWithVisibleData: 7
            )),
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
        }
    }

    private func additionalGenericStateRows(
        for sectionID: ReportDocument.SectionID
    ) -> [DocumentStateRowTarget] {
        switch sectionID {
        case .steps, .weight, .bloodPressure, .medications:
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

private extension WeeklyReportRoute {
    static let allCasesForScreenshotTesting: [WeeklyReportRoute] = [
        .dailyExport,
        .notes,
        .noteEditor,
        .diagnostics
    ]
}

@MainActor
private final class FakeScreenshotService: ScreenshotServiceRegistering {
    weak var delegate: (any UIScreenshotServiceDelegate)?
}

@MainActor
private final class FakePDFRenderer: WeeklyReportPDFRendering {
    private(set) var documents: [ReportDocument] = []
    private let result: Data?

    init(result: Data?) {
        self.result = result
    }

    func pdfData(for document: ReportDocument) -> Data? {
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
        nutritionSourceBundleIdentifier: String
    ) async throws -> DailyHealthExportInputs {
        throw HealthDataError.unavailable
    }
}
