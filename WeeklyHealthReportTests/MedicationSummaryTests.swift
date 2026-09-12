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

    func testDuplicateDisplayNamesRemainSeparateMedicationConcepts() throws {
        let records = [
            MedicationDoseRecord(
                id: UUID(), medicationKey: "concept-a", medicationName: "ExampleMed",
                date: Date(timeIntervalSince1970: 1_000), quantity: 1, unitLabel: "dose"
            ),
            MedicationDoseRecord(
                id: UUID(), medicationKey: "concept-b", medicationName: "ExampleMed",
                date: Date(timeIntervalSince1970: 2_000), quantity: 2, unitLabel: "dose"
            )
        ]

        let summary = try XCTUnwrap(MedicationSummary.aggregate(records))

        XCTAssertEqual(summary.groups.count, 2)
        XCTAssertEqual(summary.groups.map(\.count), [1, 1])
    }

    func testStableIdentityKeysDoNotDependOnDiscoveryOrder() {
        let registry = StableIdentityKeyRegistry<String>(prefix: "medication")

        let firstPass = ["concept-a", "concept-b"].map { registry.key(for: $0) }
        let secondPass = ["concept-b", "concept-a"].map { registry.key(for: $0) }

        XCTAssertEqual(secondPass, [firstPass[1], firstPass[0]])
    }
}

final class AtomicSnapshotCacheTests: XCTestCase {
    func testReadersSeePreviousCompleteSnapshotUntilReplacementCompletes() async throws {
        let cache = AtomicSnapshotCache(["old": 1])
        let gate = SyntheticLoadGate()
        let replacement = Task {
            try await cache.replaceAfterSuccessfulLoad {
                await gate.pause()
                return ["new": 2]
            }
        }

        await gate.waitUntilPaused()
        XCTAssertEqual(cache.value(for: "old"), 1)
        XCTAssertNil(cache.value(for: "new"))

        await gate.resume()
        _ = try await replacement.value

        XCTAssertNil(cache.value(for: "old"))
        XCTAssertEqual(cache.value(for: "new"), 2)
    }

    func testFailedLoadPreservesPreviousCompleteSnapshot() async {
        let cache = AtomicSnapshotCache(["old": 1])

        do {
            try await cache.replaceAfterSuccessfulLoad {
                throw SyntheticLoadError.failed
            }
            XCTFail("Expected the synthetic load to fail")
        } catch {
            XCTAssertEqual(error as? SyntheticLoadError, .failed)
        }

        XCTAssertEqual(cache.value(for: "old"), 1)
        XCTAssertNil(cache.value(for: "new"))
    }

    func testCancelledLoadPreservesPreviousCompleteSnapshot() async throws {
        let cache = AtomicSnapshotCache(["old": 1])
        let gate = SyntheticLoadGate()
        let replacement = Task {
            try await cache.replaceAfterSuccessfulLoad {
                await gate.pause()
                return ["new": 2]
            }
        }

        await gate.waitUntilPaused()
        replacement.cancel()
        await gate.resume()

        do {
            _ = try await replacement.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation is checked before the new snapshot is published.
        }

        XCTAssertEqual(cache.value(for: "old"), 1)
        XCTAssertNil(cache.value(for: "new"))
    }
}

private enum SyntheticLoadError: Error {
    case failed
}

private actor SyntheticLoadGate {
    private var pausedLoad: CheckedContinuation<Void, Never>?
    private var pauseObserver: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation { continuation in
            pausedLoad = continuation
            pauseObserver?.resume()
            pauseObserver = nil
        }
    }

    func waitUntilPaused() async {
        guard pausedLoad == nil else { return }
        await withCheckedContinuation { continuation in
            pauseObserver = continuation
        }
    }

    func resume() {
        precondition(pausedLoad != nil)
        pausedLoad?.resume()
        pausedLoad = nil
    }
}
