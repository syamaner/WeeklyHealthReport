import XCTest
@testable import WeeklyHealthReport

// Contract tests for docs/health-report-section-groups-v1.md (#216).
// All values are synthetic fixtures.
final class ReportDocumentGroupsTests: XCTestCase {
    private typealias SectionID = ReportDocument.SectionID

    private static let expectedOrder: [SectionID] = [
        .steps, .activity,
        .foodLog,
        .weight, .bodyComposition,
        .heart, .bloodPressure, .sleep,
        .cardiorespiratory,
        .glucose,
        .medications
    ]

    func testEverySectionIsInExactlyOneGroup() {
        let placed = ReportDocument.groups.flatMap(\.sectionIDs)
        XCTAssertEqual(placed.count, Set(placed).count, "a section is in more than one group")
        XCTAssertEqual(Set(placed), Set(SectionID.allCases))
        for group in ReportDocument.groups {
            for section in group.sectionIDs {
                XCTAssertEqual(ReportDocument.group(for: section), group.id, "\(section)")
            }
        }
        XCTAssertEqual(ReportDocument.groups.map(\.id), ReportDocument.GroupID.allCases)
    }

    func testGroupTableOrderAndHeadings() {
        XCTAssertEqual(ReportDocument.groups.flatMap(\.sectionIDs), Self.expectedOrder)
        XCTAssertEqual(ReportDocument.groups.map(\.heading), [
            "Daily activity", "Food and water", "Body", "Heart and sleep", "Fitness and blood oxygen", "Glucose",
            "Medications"
        ])
        // Decision 2: the group never reads "Activity", so it cannot collide with the section.
        XCTAssertFalse(ReportDocument.groups.contains { $0.heading == "Activity" })
        XCTAssertEqual(
            ReportDocument.groups.map(\.heading).map(ReportDocument.copyAllGroupHeading),
            ["DAILY ACTIVITY", "FOOD AND WATER", "BODY", "HEART AND SLEEP", "FITNESS AND BLOOD OXYGEN", "GLUCOSE",
             "MEDICATIONS"]
        )
    }

    /// Decision 5: Food and water (#214) goes straight after Daily activity in its
    /// own standalone group, never inside it.
    func testFoodAndWaterSlotFollowsDailyActivity() {
        XCTAssertEqual(ReportDocument.GroupID.allCases.prefix(3), [.dailyActivity, .foodAndWater, .body])
        XCTAssertEqual(ReportDocument.groups[0].sectionIDs, [.steps, .activity])
        XCTAssertEqual(ReportDocument.groups[1].id, .foodAndWater)
        XCTAssertEqual(ReportDocument.groups[1].heading, "Food and water")
        XCTAssertEqual(ReportDocument.groups[1].sectionIDs, [.foodLog])
        XCTAssertEqual(ReportDocument.group(for: .foodLog), .foodAndWater)

        let copied = Self.document(includesMedicationSection: true)
            .plainText(generatedAt: Self.now, calendar: Self.calendar, locale: Self.locale)
        let firstLines = copied.components(separatedBy: "\n\n").dropFirst().map { $0.components(separatedBy: "\n")[0] }
        XCTAssertEqual(Array(firstLines.prefix(6)), [
            "DAILY ACTIVITY", "Steps", "Activity", "FOOD AND WATER", "Food and water", "BODY"
        ])
    }

    func testOrderedIsTheGroupOrderFromAnyInputOrder() {
        let shuffledInputs: [[SectionID]] = [
            SectionID.allCases,
            SectionID.allCases.reversed(),
            [.medications, .glucose, .sleep, .steps, .weight, .activity, .foodLog, .heart,
             .bloodPressure, .bodyComposition, .cardiorespiratory]
        ]
        for input in shuffledInputs {
            let ordered = ReportDocument.ordered(sections: input.map(Self.section))
            XCTAssertEqual(ordered.map(\.id), Self.expectedOrder)
        }
        let withoutMedications = ReportDocument.ordered(
            sections: SectionID.allCases.filter { $0 != .medications }.map(Self.section)
        )
        XCTAssertEqual(withoutMedications.map(\.id), Self.expectedOrder.filter { $0 != .medications })
    }

    /// Contract v1.1: every present group has a heading, single-section groups included.
    func testDocumentGroupsEveryGroupHasAHeading() {
        let document = Self.document(includesMedicationSection: true)
        XCTAssertEqual(document.sections.map(\.id), Self.expectedOrder)
        let grouped = document.groupedSections
        XCTAssertEqual(grouped.map(\.id), ReportDocument.GroupID.allCases)
        XCTAssertEqual(grouped.map(\.heading), [
            "Daily activity", "Food and water", "Body", "Heart and sleep", "Fitness and blood oxygen", "Glucose",
            "Medications"
        ])
        XCTAssertEqual(
            grouped.filter { $0.sections.count == 1 }.map(\.id),
            [.foodAndWater, .fitnessAndBloodOxygen, .glucose, .medications]
        )
        XCTAssertEqual(grouped.flatMap(\.sections), document.sections)
    }

    func testMedicationsAbsentLeavesNoEmptyGroup() {
        let document = Self.document(includesMedicationSection: false)
        let grouped = document.groupedSections
        XCTAssertFalse(grouped.contains { $0.sections.isEmpty })
        XCTAssertFalse(grouped.contains { $0.id == .medications })
        XCTAssertEqual(grouped.flatMap(\.sections).map(\.id), Self.expectedOrder.filter { $0 != .medications })

        let copied = document.plainText(generatedAt: Self.now, calendar: Self.calendar, locale: Self.locale)
        XCTAssertFalse(copied.contains("Medications"))
        XCTAssertFalse(copied.contains("MEDICATIONS"))
        XCTAssertFalse(copied.contains("\n\n\n"))
    }

    /// Full Page renders the display document's `groupedSections`; its order and
    /// headings are the screen's and Copy all's.
    func testFullPageOrderEqualsCopyAllOrder() {
        let document = Self.document(includesMedicationSection: true)
        let display = document.forDisplay()
        XCTAssertEqual(display.sections.map(\.id), document.sections.map(\.id))
        XCTAssertEqual(display.groupedSections.map(\.id), document.groupedSections.map(\.id))
        XCTAssertEqual(display.groupedSections.map(\.heading), document.groupedSections.map(\.heading))

        let copied = document.plainText(generatedAt: Self.now, calendar: Self.calendar, locale: Self.locale)
        let blocks = copied.components(separatedBy: "\n\n").dropFirst()
        let expected = document.groupedSections.flatMap { grouped in
            [ReportDocument.copyAllGroupHeading(grouped.heading)] + grouped.sections.map(\.title)
        }
        XCTAssertEqual(blocks.map { $0.components(separatedBy: "\n")[0] }, expected)
        XCTAssertEqual(expected.prefix(3), ["DAILY ACTIVITY", "Steps", "Activity"])
        XCTAssertEqual(expected.suffix(6), [
            "FITNESS AND BLOOD OXYGEN", "Cardiorespiratory", "GLUCOSE", "Glucose", "MEDICATIONS", "Medications Taken"
        ])
    }

    func testRowIdsAndTextAreUnchangedByGrouping() {
        let document = Self.document(includesMedicationSection: true)
        let rowsBySection = Dictionary(uniqueKeysWithValues: document.sections.map { ($0.id, $0.rows) })
        // The same rows reach every section as before; only the section order moved.
        let regrouped = ReportDocument.ordered(sections: SectionID.allCases.compactMap { id in
            document.sections.first { $0.id == id }
        })
        XCTAssertEqual(regrouped, document.sections)
        for section in regrouped {
            XCTAssertEqual(section.rows, rowsBySection[section.id])
        }
    }

    // MARK: - Fixtures

    private static let locale = Locale(identifier: "en_GB")

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    private static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12))!

    private static func section(_ id: SectionID) -> ReportDocument.Section {
        ReportDocument.Section(id: id, title: id.rawValue, rows: [], footer: nil)
    }

    private static func document(includesMedicationSection: Bool) -> ReportDocument {
        let period = ReportPeriod.make(selection: .lastSevenCompletedDays, now: now, calendar: calendar)
        let snapshot = ReportPresentationSnapshot(
            period: period,
            steps: .noDataOrAccess,
            weight: .noDataOrAccess,
            bodyFat: .noDataOrAccess,
            waist: .noDataOrAccess,
            glucose: .noDataOrAccess,
            vo2Max: .noDataOrAccess,
            bloodOxygen: .noDataOrAccess,
            bloodPressure: .noDataOrAccess,
            restingHeartRate: .noDataOrAccess,
            hrv: .noDataOrAccess,
            watchCoverage: .noDataOrAccess,
            exercise: .noDataOrAccess,
            activeEnergy: .noDataOrAccess,
            workouts: .noDataOrAccess,
            sleep: .noDataOrAccess,
            medications: .noDataOrAccess,
            foodLog: .available(FoodLogFixtures.normalWeek(period: period, calendar: calendar)),
            includesMedicationSection: includesMedicationSection,
            showsMorningBloodPressureDetails: true,
            showsEveningBloodPressureDetails: true
        )
        return ReportDocument.expanded(snapshot: snapshot, calendar: calendar, locale: locale)
    }
}
