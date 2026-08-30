import XCTest
@testable import WeeklyHealthReport

// Medication names and doses in this file are entirely synthetic fixtures.
final class MedicationSummaryTests: XCTestCase {
    func testGroupsExactMedicationConceptsAndOrdersByLatestEvent() throws {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let records = [
            MedicationDoseRecord(
                id: UUID(), medicationKey: "tablet-20", medicationName: "ExampleMed 20 mg",
                date: older, quantity: 1, unitLabel: "dose"
            ),
            MedicationDoseRecord(
                id: UUID(), medicationKey: "tablet-40", medicationName: "ExampleMed 40 mg",
                date: newer, quantity: 1, unitLabel: "dose"
            ),
            MedicationDoseRecord(
                id: UUID(), medicationKey: "tablet-20", medicationName: "ExampleMed 20 mg",
                date: newer.addingTimeInterval(-100), quantity: 1, unitLabel: "dose"
            )
        ]

        let summary = try XCTUnwrap(MedicationSummary.aggregate(records))

        XCTAssertEqual(summary.groups.map(\.medicationName), ["ExampleMed 40 mg", "ExampleMed 20 mg"])
        XCTAssertEqual(summary.groups[1].count, 2)
        XCTAssertEqual(summary.groups[1].latestDose.date, newer.addingTimeInterval(-100))
        XCTAssertEqual(summary.allDoses.count, 3)
    }

    func testEmptyMedicationEventsProduceNoSummary() {
        XCTAssertNil(MedicationSummary.aggregate([]))
    }
}
