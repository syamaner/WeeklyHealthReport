import CoreGraphics
import PDFKit
import XCTest
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
@MainActor
final class WeeklyReportScreenshotTests: XCTestCase {
    func testDocumentUsesCompleteDeterministicSectionOrdering() {
        let document = makeDocument(includesMedicationSection: true)

        XCTAssertEqual(
            document.sections.map(\.id),
            WeeklyReportPDFDocument.SectionID.allCases
        )
        XCTAssertEqual(document.title, "Weekly Health Report")
        XCTAssertEqual(document.selection, "Last 7 Completed Days")
    }

    func testDocumentPreservesMissingUnavailableAndFailedStates() {
        let document = WeeklyReportPDFDocument(snapshot: makeSnapshot(
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
        let document = WeeklyReportPDFDocument(
            snapshot: makeSnapshot(steps: .loaded(summary)),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        )
        let section = try XCTUnwrap(document.sections.first { $0.id == .steps })

        XCTAssertEqual(section.rows.first { $0.id == "steps-average" }?.value, "7,000")
        XCTAssertEqual(section.rows.first { $0.id == "steps-coverage" }?.value, "2 / 3 days")
    }

    func testDocumentPreservesUnavailableAndFailedStepStates() {
        let unavailable = WeeklyReportPDFDocument(
            snapshot: makeSnapshot(steps: .healthUnavailable),
            calendar: testCalendar(),
            locale: Locale(identifier: "en_GB")
        )
        let failed = WeeklyReportPDFDocument(
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
    ) -> WeeklyReportPDFDocument {
        WeeklyReportPDFDocument(
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
        steps: WeeklyReportViewModel.State = .noDataOrAccess,
        weight: WeeklyReportViewModel.WeightState = .noDataOrAccess,
        bodyFat: WeeklyReportViewModel.BodyFatState = .noDataOrAccess,
        waist: MetricState<WaistSummary> = .noDataOrAccess,
        glucose: MetricState<GlucoseSummary> = .noDataOrAccess,
        bloodPressure: MetricState<BloodPressureSummary> = .noDataOrAccess,
        includesMedicationSection: Bool = false,
        showsMorningDetails: Bool = true,
        showsEveningDetails: Bool = false
    ) -> WeeklyReportScreenshotSnapshot {
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
        return WeeklyReportScreenshotSnapshot(
            period: period,
            steps: steps,
            weight: weight,
            bodyFat: bodyFat,
            waist: waist,
            glucose: glucose,
            vo2Max: .noDataOrAccess,
            bloodOxygen: .noDataOrAccess,
            bloodPressure: bloodPressure,
            restingHeartRate: .noDataOrAccess,
            hrv: .noDataOrAccess,
            watchCoverage: .noDataOrAccess,
            exercise: .noDataOrAccess,
            activeEnergy: .noDataOrAccess,
            workouts: .noDataOrAccess,
            sleep: .noDataOrAccess,
            medications: .noDataOrAccess,
            includesMedicationSection: includesMedicationSection,
            showsMorningBloodPressureDetails: showsMorningDetails,
            showsEveningBloodPressureDetails: showsEveningDetails
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
    private(set) var documents: [WeeklyReportPDFDocument] = []
    private let result: Data?

    init(result: Data?) {
        self.result = result
    }

    func pdfData(for document: WeeklyReportPDFDocument) -> Data? {
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
