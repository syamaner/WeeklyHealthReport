import AppAuth
import DriveExportOAuth
import FoodLedgerApplication
import FoodLedgerDomain
import HealthKit
import SwiftUI
import UIKit
import XCTest
@testable import DriveExportKit
@testable import WeeklyHealthReport

// Every health value in this file is invented. These tests never access HealthKit.
final class DailyHealthExportTests: XCTestCase {
    func testSchemaEightPreservesIndividualReadingsAndSubmillisecondDates() throws {
        let calendar = londonCalendar()
        let now = date(2026, 9, 10, 15, calendar: calendar)
        let window = try DailyExportWindow.capture(at: now, calendar: calendar)
        let start = window.day.start.addingTimeInterval(3600.000123)
        var enrichment = WorkoutEnrichmentReader.read(.init(start: start, end: start.addingTimeInterval(60),
            activity: "walking", metadata: [:], statistics: .init(provenance: "healthKitWorkoutStatistics"),
            distanceMetres: nil, activities: []))
        let point = start.addingTimeInterval(0.000234)
        let sample = WorkoutHeartRateReadings.Entry(sampleID: UUID(), entryIndex: 0,
            startedAt: point, endedAt: point, beatsPerMinute: 93.25, sourceBundleIdentifier: "synthetic.test")
        enrichment.enrichmentVersion = 3
        enrichment.heartRateReadings = .project([sample], into: enrichment)
        let record = WorkoutRecord(id: UUID(), startDate: start, duration: 60, activityName: "Walking", enrichment: enrichment)
        let inputs = emptyInputs(window: window, workouts: [record])
        let envelope = try DailyHealthExportBuilder.make(window: window, exportedAt: now, inputs: inputs, includeWorkoutEnrichment: true)
        XCTAssertEqual(envelope.schemaVersion, 8)
        let bytes = try DailyHealthExportSerializer.encode(envelope)
        XCTAssertNoThrow(try DailyHealthExportIdentityPolicy().validate(payload: bytes, reportDate: window.reportDate))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { Date(timeIntervalSinceReferenceDate: try $0.singleValueContainer().decode(Double.self)) }
        let decoded = try decoder.decode(DailyHealthExportEnvelope.self, from: bytes)
        XCTAssertEqual(decoded.today.workouts.data?.first?.enrichment?.heartRateReadings?.entries.first?.startedAt, point)
        XCTAssertEqual(decoded.today.workouts.data?.first?.enrichment?.startedAt, start)
        XCTAssertEqual(try DailyHealthExportSerializer.encode(decoded), bytes)
        var forged = enrichment
        forged.heartRateReadings = .init(schemaVersion: 1, state: "available",
            provenance: "healthKitWorkoutAssociatedQuantitySeries", entries: [
                .init(sampleID: sample.sampleID, entryIndex: 999, startedAt: point, endedAt: point,
                      beatsPerMinute: sample.beatsPerMinute, sourceBundleIdentifier: sample.sourceBundleIdentifier)])
        let bad = WorkoutRecord(id: record.id, startDate: start, duration: 60, activityName: "Walking", enrichment: forged)
        let forgedEnvelope = try DailyHealthExportBuilder.make(window: window, exportedAt: now,
            inputs: emptyInputs(window: window, workouts: [bad]), includeWorkoutEnrichment: true)
        XCTAssertThrowsError(try DailyHealthExportIdentityPolicy().validate(
            payload: DailyHealthExportSerializer.encode(forgedEnvelope), reportDate: window.reportDate))
        let basic = try DailyHealthExportBuilder.make(window: window, exportedAt: now, inputs: inputs)
        XCTAssertEqual(basic.schemaVersion, 3)
        XCTAssertNil(basic.today.workouts.data?.first?.enrichment)
    }

    func testSchemaSevenEnrichmentRoundTripsWithLocalDatesAndIndependentDailyTotals() throws {
        let calendar = londonCalendar()
        let now = date(2026, 9, 10, 15, calendar: calendar)
        let selected = DailyExportWindow.availableDays(at: now, calendar: calendar)[1]
        let window = try DailyExportWindow.capture(at: now, calendar: calendar, selectedDay: selected)
        let start = window.day.start.addingTimeInterval(3600.125)
        let stats = WorkoutStatistics(provenance: "healthKitWorkoutStatistics", average: 110, energy: 5)
        let enrichment = WorkoutEnrichmentReader.read(.init(start: start, end: start.addingTimeInterval(60), activity: "walking", metadata: [:], statistics: stats, distanceMetres: nil, activities: []))
        let record = WorkoutRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, startDate: start, duration: 60, activityName: "Walking", enrichment: enrichment)
        let outside = WorkoutRecord(id: UUID(), startDate: window.day.end, duration: 60, activityName: "Walking", enrichment: enrichment)
        let inputs = emptyInputs(window: window, workouts: [outside, record])
        let envelope = try DailyHealthExportBuilder.make(window: window, exportedAt: now, inputs: inputs, includeWorkoutEnrichment: true)
        XCTAssertEqual(envelope.schemaVersion, 7)
        XCTAssertEqual(envelope.today.workouts.data?.count, 1)
        XCTAssertEqual(envelope.today.workouts.data?.first?.enrichment?.statistics.activeEnergyKilocalories, 5)
        XCTAssertNil(envelope.today.activity.activeEnergy.data)
        let bytes = try DailyHealthExportSerializer.encode(envelope)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertTrue(text.contains("2026-09-09T01:01:00.125+01:00"))
        XCTAssertTrue(text.contains("heart_rate_average_bpm"))
        let identity = try DailyHealthExportIdentityPolicy().validate(payload: bytes, reportDate: window.reportDate)
        XCTAssertTrue(identity.orderingToken.hasPrefix("historical-v2|"))
        let badZones = text.replacingOccurrences(of: "\"heart_rate_zones\":{\"state\":\"unsupported\",\"zones\":[]}", with: "\"heart_rate_zones\":{\"state\":\"future\",\"zones\":[]}")
        XCTAssertNotEqual(badZones, text)
        XCTAssertThrowsError(try DailyHealthExportIdentityPolicy().validate(payload: Data(badZones.utf8), reportDate: window.reportDate))
        let legacy = try DailyHealthExportBuilder.make(window: window, exportedAt: now, inputs: inputs)
        XCTAssertEqual(legacy.schemaVersion, 3)
        XCTAssertNil(legacy.today.workouts.data?.first?.enrichment)
    }

    func testSchemaSevenNestedWorkoutDatesRetainDSTOffsetChange() throws {
        let calendar = londonCalendar()
        let now = date(2026, 10, 26, 12, calendar: calendar)
        let selected = DailyExportWindow.availableDays(at: now, calendar: calendar)[1]
        let window = try DailyExportWindow.capture(at: now, calendar: calendar, selectedDay: selected)
        let start = window.day.start.addingTimeInterval(3600)
        let end = window.day.start.addingTimeInterval(10800)
        let statistics = WorkoutStatistics(provenance: "healthKitWorkoutStatistics")
        let activity = WorkoutActivityInput(id: UUID(), start: start, end: end, duration: 7200, activity: "walking", indoor: true, metadata: [:], statistics: .init(provenance: "healthKitActivityStatistics"))
        let enrichment = WorkoutEnrichmentReader.read(.init(start: start, end: end, activity: "walking", metadata: [:], statistics: statistics, distanceMetres: nil, activities: [activity]))
        let record = WorkoutRecord(id: UUID(), startDate: start, duration: 7200, activityName: "Walking", enrichment: enrichment)
        let envelope = try DailyHealthExportBuilder.make(window: window, exportedAt: now, inputs: emptyInputs(window: window, workouts: [record]), includeWorkoutEnrichment: true)
        let bytes = try DailyHealthExportSerializer.encode(envelope)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertTrue(text.contains("2026-10-25T01:00:00.000+01:00"))
        XCTAssertTrue(text.contains("2026-10-25T02:00:00.000Z"))
        XCTAssertNoThrow(try DailyHealthExportIdentityPolicy().validate(payload: bytes, reportDate: window.reportDate))
    }

    func testCancelledSnapshotNeverPublishesSchemaSevenBytes() async throws {
        let calendar = londonCalendar()
        let now = date(2026, 9, 10, 15, calendar: calendar)
        let provider = RecordingDailyProvider { window in
            withUnsafeCurrentTask { $0?.cancel() }
            return self.emptyInputs(window: window)
        }
        let service = DailyHealthExportService(healthData: provider, calendar: calendar, now: { now })
        let operation = Task { try await service.refresh(nutritionSourceBundleIdentifier: fixtureNutritionSource.bundleIdentifier) }
        do {
            _ = try await operation.value
            XCTFail("Cancelled coherent snapshot must not be published")
        } catch is CancellationError {}
    }

    func testRetrospectiveWindowUsesSelectedDayAndHistoricalCutoff() throws {
        let calendar = londonCalendar()
        let now = date(2026, 9, 10, 15, calendar: calendar)
        let choices = DailyExportWindow.availableDays(at: now, calendar: calendar)
        XCTAssertEqual(choices.count, 8)
        XCTAssertEqual(choices.last?.reportDate, "2026-09-03")
        let window = try DailyExportWindow.capture(at: now, calendar: calendar, selectedDay: choices[5])
        XCTAssertEqual(window.reportDate, "2026-09-05")
        XCTAssertEqual(window.day.start, date(2026, 9, 5, 0, calendar: calendar))
        XCTAssertEqual(window.cutoff, date(2026, 9, 6, 0, calendar: calendar))
        XCTAssertEqual(window.context.interval.end, window.cutoff)
        XCTAssertEqual(window.sleep.end, date(2026, 9, 5, 12, calendar: calendar))
        XCTAssertEqual(window.glucoseHours.count, 24)
        XCTAssertEqual(try DailyExportWindow.capture(at: now, calendar: calendar, selectedDay: choices[0]).cutoff, now)
        for invalid in [
            DailyNoteDayID(reportDate: "2026-09-02", timeZoneIdentifier: "Europe/London"),
            DailyNoteDayID(reportDate: "2026-09-11", timeZoneIdentifier: "Europe/London"),
            DailyNoteDayID(reportDate: "2026-09-05", timeZoneIdentifier: "UTC")
        ] {
            XCTAssertThrowsError(try DailyExportWindow.capture(at: now, calendar: calendar, selectedDay: invalid))
        }
        let nextWeek = date(2026, 9, 13, 0, calendar: calendar)
        XCTAssertThrowsError(try DailyExportWindow.capture(at: nextWeek, calendar: calendar, selectedDay: choices[5]))
    }

    func testRetrospectiveDSTHasActualCalendarHours() throws {
        let calendar = londonCalendar()
        for (month, day, expected) in [(3, 29, 23), (10, 25, 25)] {
            let now = date(2026, month, day + 1, 10, calendar: calendar)
            let selected = DailyExportWindow.availableDays(at: now, calendar: calendar)[1]
            let window = try DailyExportWindow.capture(at: now, calendar: calendar, selectedDay: selected)
            XCTAssertEqual(window.glucoseHours.count, expected)
            XCTAssertEqual(window.day.duration, Double(expected) * 3600)
            XCTAssertEqual(window.glucoseHours.first?.start, window.day.start)
            XCTAssertEqual(window.glucoseHours.last?.end, window.cutoff)
        }
    }

    func testRetrospectiveServiceExportsFiveDatesInAnyOrderWithoutMovingNotes() async throws {
        let calendar = londonCalendar()
        let now = date(2026, 9, 10, 15, calendar: calendar)
        let choices = DailyExportWindow.availableDays(at: now, calendar: calendar)
        let store = MutableDailyNotesStore()
        var document = DailyNotesDocument()
        for day in choices {
            try document.beginDraft(for: day, now: now)
            try document.updateDraft(text: "Invented note for \(day.reportDate)", now: now)
            _ = try document.saveDraft(now: now)
        }
        store.document = document
        let original = store.document
        let provider = RecordingDailyProvider { self.emptyInputs(window: $0) }
        let service = DailyHealthExportService(healthData: provider, notesStore: store, calendar: calendar, now: { now })
        for offset in [5, 1, 7, 3, 0] {
            let result = try await service.refresh(nutritionSourceBundleIdentifier: fixtureNutritionSource.bundleIdentifier, selectedDay: choices[offset])
            XCTAssertEqual(result.envelope.reportDate, choices[offset].reportDate)
            XCTAssertEqual(result.envelope.schemaVersion, 7)
            XCTAssertEqual(result.notesSnapshot.notes, ["Invented note for \(choices[offset].reportDate)"])
            XCTAssertEqual(result.envelope.exportedAt, "2026-09-10T15:00:00+01:00")
            XCTAssertEqual(store.document, original)
        }
        XCTAssertEqual(provider.readAuthorizationCount, 0)
    }

    func testHistoricalRefreshRejectsOnlyMatchingDateNoteMutation() async throws {
        let calendar = londonCalendar()
        let now = date(2026, 9, 10, 15, calendar: calendar)
        let selected = DailyExportWindow.availableDays(at: now, calendar: calendar)[5]
        var first = DailyNotesDocument()
        try first.beginDraft(for: selected, now: now)
        try first.updateDraft(text: "Selected historical note", now: now)
        _ = try first.saveDraft(now: now)
        for changesSelectedDate in [false, true] {
            var changed = first
            let owner = changesSelectedDate ? selected : DailyExportWindow.availableDays(at: now, calendar: calendar)[0]
            try changed.beginDraft(for: owner, now: now)
            try changed.updateDraft(text: "Changed note", now: now)
            _ = try changed.saveDraft(now: now)
            let store = SequencedDailyNotesStore(documents: [first, changed])
            let service = DailyHealthExportService(healthData: RecordingDailyProvider { self.emptyInputs(window: $0) }, notesStore: store, calendar: calendar, now: { now })
            do {
                let result = try await service.refresh(nutritionSourceBundleIdentifier: fixtureNutritionSource.bundleIdentifier, selectedDay: selected)
                XCTAssertFalse(changesSelectedDate)
                XCTAssertEqual(result.notesSnapshot.notes, ["Selected historical note"])
            } catch DailyHealthExportError.notesChanged {
                XCTAssertTrue(changesSelectedDate)
            }
        }
    }

    @MainActor
    func testDateSelectionInvalidatesPreviewAndBindsNotesWithoutQuery() async throws {
        let (session, _) = await makePreviewLifecycleSession()
        XCTAssertNotNil(session.preview)
        let day = session.availableReportDays[3]
        session.selectReportDay(day)
        XCTAssertNil(session.preview)
        XCTAssertFalse(session.canExport)
        XCTAssertEqual(session.notes.currentDayID, day)
        session.notes.activate()
        XCTAssertEqual(session.notes.currentDayID, day)
        await session.refreshPreview()
        XCTAssertEqual(session.preview?.envelope.reportDate, day.reportDate)
        session.selectReportDay(nil)
        XCTAssertNil(session.preview)
        XCTAssertEqual(session.notes.currentDayID, session.availableReportDays.first)
    }

    func testProductionCredentialClassifierUsesOnlySupportedAppAuthEvidence() {
        XCTAssertEqual(
            AppAuthDriveSession.classify(nil),
            .missing
        )
        XCTAssertEqual(
            AppAuthDriveSession.classify(
                NSError(domain: OIDGeneralErrorDomain, code: -11)
            ),
            .expired
        )
        XCTAssertEqual(
            AppAuthDriveSession.classify(
                NSError(domain: OIDOAuthAuthorizationErrorDomain, code: -4)
            ),
            .denied
        )
    }

    func testProductionCredentialClassifierKeepsAmbiguousAndUnknownErrorsIndeterminate() {
        XCTAssertEqual(
            AppAuthDriveSession.classify(
                NSError(domain: OIDOAuthTokenErrorDomain, code: -10)
            ),
            .indeterminate
        )
        XCTAssertEqual(
            AppAuthDriveSession.classify(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            ),
            .indeterminate
        )
    }

    func testProductionCredentialClassifierPreservesExplicitTypedFailure() {
        for failure in [
            DailyDriveCredentialFailure.expired,
            .denied,
            .revoked,
            .missing,
            .indeterminate
        ] {
            XCTAssertEqual(
                AppAuthDriveSession.classify(failure),
                failure
            )
        }
    }

    func testProductionTokenResolutionNeverConvertsAnErrorIntoSuccess() throws {
        XCTAssertEqual(
            try AppAuthDriveSession.resolveAccessToken("token", error: nil),
            "token"
        )

        for (token, error, expected) in [
            (nil, nil, DailyDriveCredentialFailure.missing),
            (
                "token",
                NSError(domain: OIDOAuthTokenErrorDomain, code: -10),
                .indeterminate
            )
        ] {
            XCTAssertThrowsError(
                try AppAuthDriveSession.resolveAccessToken(token, error: error)
            ) { observed in
                XCTAssertEqual(observed as? DailyDriveCredentialFailure, expected)
            }
        }
    }

    func testSerializerOutputMatchesGoldenForPopulatedFixture() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: populatedInputs(window: window),
            notes: ["Invented note"]
        )

        try assertGolden(
            try DailyHealthExportSerializer.encode(envelope),
            equals: DailyHealthExportGoldenSnapshots.populated
        )
    }

    func testSerializerOmitsNilNotesAndNutritionAndMatchesGolden() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let populated = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: populatedInputs(window: window),
            notes: ["Invented note"]
        )
        let envelope = withoutNotesAndNutrition(populated)
        let bytes = try DailyHealthExportSerializer.encode(envelope)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))

        XCTAssertFalse(text.contains("\"notes\":"))
        XCTAssertFalse(text.contains("\"nutrition\":"))
        XCTAssertFalse(text.contains(":null"))
        try assertGolden(
            bytes,
            equals: DailyHealthExportGoldenSnapshots.nilNotesAndNutrition
        )
    }

    /// docs/healthkit-day-bucketing-v1.md section 4: in the normal case every
    /// bucket matches, so re-reading the fixture's daily values through the
    /// alignment check must reproduce the golden bytes exactly.
    func testAlignedDailyBucketReadsReproduceGoldenBytes() async throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let previous = try XCTUnwrap(window.context.precedingEquivalent(calendar: calendar))
        let fixture = populatedInputs(window: window)

        func reread<Value>(
            _ days: [DateInterval],
            interval: DateInterval,
            _ values: [Value?]
        ) async throws -> [Value?] {
            let plan = try XCTUnwrap(DailyBucketPlan(interval: interval, days: days, calendar: calendar))
            let buckets = zip(plan.days.indices, values).compactMap { index, value in
                value.map {
                    DailyBucket(
                        start: calendar.date(byAdding: .day, value: index, to: plan.anchorDate)!,
                        end: calendar.date(byAdding: .day, value: index + 1, to: plan.anchorDate)!,
                        value: $0
                    )
                }
            }
            let result = try await DailyBucketReader.read(
                days: plan.days,
                plan: plan,
                collection: { _ in buckets },
                perDay: { _ in XCTFail("aligned buckets need no fallback"); return nil }
            )
            XCTAssertEqual(result.outcome, .aligned)
            return result.values
        }
        func rereadPeriod<Value>(_ period: ReportPeriod, _ values: [Value?]) async throws -> [Value?] {
            try await reread(period.completedDays, interval: period.interval, values)
        }

        let steps = try await rereadPeriod(window.context, fixture.contextSteps.map { total in
            total.steps.map { (steps: $0, sources: total.sourceNames) }
        })
        let glucose = try await rereadPeriod(window.context, fixture.contextGlucose.map {
            $0.averageMillimolesPerLiter == nil ? nil : $0
        })
        func heart(_ period: ReportPeriod, _ values: [DailyHeartMetricValue]) async throws
            -> [DailyHeartMetricValue] {
            let read = try await rereadPeriod(period, values.map { daily in
                daily.value.map { (value: $0, sources: daily.sourceNames) }
            })
            return zip(period.completedDays, read).map {
                DailyHeartMetricValue(day: $0, value: $1?.value, sourceNames: $1?.sources ?? [])
            }
        }
        let rereadInputs = replacing(
            fixture,
            contextSteps: zip(window.context.completedDays, steps).map {
                DailyStepTotal(day: $0, steps: $1?.steps, sourceNames: $1?.sources ?? [])
            },
            contextGlucose: zip(window.context.completedDays, glucose).map { day, value in
                DailyGlucoseValue(
                    day: day,
                    averageMillimolesPerLiter: value?.averageMillimolesPerLiter,
                    minimumMillimolesPerLiter: value?.minimumMillimolesPerLiter,
                    maximumMillimolesPerLiter: value?.maximumMillimolesPerLiter,
                    sourceNames: value?.sourceNames ?? []
                )
            },
            contextRestingHeartRate: try await heart(window.context, fixture.contextRestingHeartRate),
            previousRestingHeartRate: try await heart(previous, fixture.previousRestingHeartRate),
            contextHRV: try await heart(window.context, fixture.contextHRV),
            previousHRV: try await heart(previous, fixture.previousHRV)
        )
        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: rereadInputs,
            notes: ["Invented note"]
        )
        try assertGolden(
            try DailyHealthExportSerializer.encode(envelope),
            equals: DailyHealthExportGoldenSnapshots.populated
        )

        // Nutrition: values read through the aligned check equal the totals the
        // previous start-of-day keying produced, and the bytes match the
        // checked-in populated-nutrition golden.
        let expected = nutrition(
            window: window,
            key: "energy_consumed",
            today: 1_750,
            current: [1_400, nil, 1_600, 1_700, 1_800, 1_900, 2_000],
            previous: [1_300, 1_400, 1_500, nil, 1_700, 1_800, 1_900]
        )
        let days = NutritionNutrientTotals.collectionDays(window: window, previous: previous)
        let queryInterval = DateInterval(start: previous.interval.start, end: window.cutoff)
        var nutrients: [NutritionNutrientTotals] = []
        for totals in expected.nutrients {
            let values = totals.previousDays.map(\.value) + totals.currentDays.map(\.value)
                + [totals.today]
            nutrients.append(NutritionNutrientTotals(
                key: totals.key,
                window: window,
                previous: previous,
                days: days,
                values: try await reread(days, interval: queryInterval, values)
            ))
        }
        let rebuilt = NutritionExportInput(source: expected.source, nutrients: nutrients)
        XCTAssertEqual(rebuilt, expected)
        func bytes(_ input: NutritionExportInput) throws -> Data {
            try DailyHealthExportSerializer.encode(DailyHealthExportBuilder.make(
                window: window,
                exportedAt: cutoff,
                inputs: replacing(fixture, nutrition: input),
                notes: ["Invented note"]
            ))
        }
        XCTAssertEqual(try bytes(rebuilt), try bytes(expected))
        try assertGolden(try bytes(rebuilt), equals: DailyHealthExportGoldenSnapshots.populatedNutrition)
    }

    func testEnvelopePreservesDailySemanticsAndExplicitAvailability() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let tiedDate = date(2026, 9, 6, 8, calendar: calendar)
        var inputs = emptyInputs(window: window)
        inputs = replacing(
            inputs,
            weight: historicalWeights(window: window) + [
                WeightMeasurement(
                    id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
                    date: tiedDate,
                    kilograms: 91
                ),
                WeightMeasurement(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    date: tiedDate,
                    kilograms: 81
                )
            ],
            bodyFat: [
                BodyFatMeasurement(date: tiedDate, percentage: 20),
                BodyFatMeasurement(
                    date: date(2026, 9, 6, 9, calendar: calendar),
                    percentage: 22
                )
            ],
            bloodOxygen: [
                OxygenSaturationMeasurement(date: tiedDate, percentage: 95, sourceName: "Watch"),
                OxygenSaturationMeasurement(
                    date: date(2026, 9, 6, 9, calendar: calendar),
                    percentage: 99,
                    sourceName: "Watch"
                )
            ],
            bloodPressure: [
                pressure(1, at: date(2026, 9, 6, 8, calendar: calendar), 120, 80),
                pressure(2, at: date(2026, 9, 6, 15, calendar: calendar), 130, 85),
                pressure(3, at: date(2026, 9, 6, 18, calendar: calendar), 140, 90)
            ],
            todayGlucose: glucose(window.day, average: 5.5, minimum: 4.0, maximum: 7.0),
            hourlyGlucose: window.glucoseHours.enumerated().map { index, hour in
                index == 8
                    ? glucose(hour, average: 5.2, minimum: 4.8, maximum: 5.7)
                    : glucose(hour)
            },
            todaySteps: DailyStepTotal(
                day: window.day,
                steps: 1_234,
                sourceNames: ["Phone", "Watch"]
            ),
            supportsMedicationData: false
        )

        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff.addingTimeInterval(5),
            inputs: inputs
        )

        XCTAssertEqual(envelope.schemaVersion, 3)
        XCTAssertEqual(envelope.reportDate, "2026-09-06")
        XCTAssertEqual(envelope.timeZone, "Europe/London")
        XCTAssertEqual(envelope.today.weight.data?.value, 81)
        XCTAssertEqual(envelope.today.bodyFat.data?.dailyAverage.value, 21)
        XCTAssertEqual(envelope.today.bloodOxygen.data?.dailyMedian.value, 97)
        XCTAssertEqual(envelope.today.bloodPressure.data?.readings.map(\.slot), [
            "morning", nil, "evening"
        ])
        XCTAssertEqual(envelope.today.bloodPressure.data?.morning.data?.readingCount, 1)
        XCTAssertEqual(envelope.today.bloodPressure.data?.evening.data?.readingCount, 1)
        XCTAssertEqual(envelope.today.glucose.data?.hours.count, window.glucoseHours.count)
        XCTAssertEqual(envelope.today.glucose.data?.hours[8].statistics.availability, .available)
        XCTAssertEqual(envelope.today.glucose.data?.hours[9].statistics.availability, .noDataOrAccess)
        XCTAssertEqual(envelope.today.activity.steps.data?.value, 1_234)
        XCTAssertEqual(envelope.appContext.policyID, "last_7_completed_days_v1")
        XCTAssertEqual(envelope.appContext.window.end, "2026-09-06T00:00:00+01:00")
        XCTAssertEqual(envelope.today.medications.availability, .unsupported)
        XCTAssertNil(envelope.today.medications.data)
        XCTAssertEqual(envelope.today.nutrition?.source, fixtureNutritionSource)
        XCTAssertEqual(envelope.today.notes, [])
        XCTAssertEqual(envelope.today.nutrition?.nutrients.count, 39)
        XCTAssertEqual(envelope.appContext.nutrition?.nutrients.count, 39)

        let bytes = try DailyHealthExportSerializer.encode(envelope)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertTrue(text.contains("\"schema_version\":3"))
        XCTAssertTrue(text.contains("\"notes\":["))
        XCTAssertTrue(text.contains("\"no_data_or_access\""))
        XCTAssertFalse(text.contains(":null"))
        XCTAssertFalse(text.contains("\n"))
        XCTAssertTrue(text.hasPrefix("{\"app_context\":"))
        XCTAssertEqual(bytes, try DailyHealthExportSerializer.encode(envelope))
    }

    /// D7 (#195): food entries are not exported yet (#97), so schema-4 food admission stays
    /// pinned to food contract 3 even though the current food contract is 4.
    func testSchemaV4FoodAdmissionIsPinnedToFoodContractThree() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let schemaV3 = try DailyHealthExportBuilder.make(
            window: window, exportedAt: cutoff, inputs: populatedInputs(window: window), notes: [])
        let nutrientSet = try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: .unknown(.notDeclared))
        })
        let summary = CanonicalFoodNutritionSummary(
            summaryVersionID: try LedgerText("summary-fixture-v1"), reportingDate: try LedgerText("2026-09-06"),
            nutrients: nutrientSet, inputLogItemVersionIDs: [], hasUnknownContribution: true)
        XCTAssertEqual(CanonicalFoodProjection.foodContractVersion, 7)
        XCTAssertEqual(DailyHealthExportBuilder.maximumExportedFoodContractVersion, 3)
        let three = try CanonicalFoodDocument(projection: CanonicalFoodProjection(
            records: LedgerMutation(), summaries: [summary], foodContractVersion: 3))
        XCTAssertNoThrow(try DailyHealthExportBuilder.addingFoodProjection(three, summary: summary, to: schemaV3))
        // Contracts 4 (decisions), 5 (review manifest v2), 6 (favourites, #198) and 7 (pasted label, #93) are rejected; the
        // pin stays literal 3.
        for contract in [4, 5, 6, 7] {
            let document = try CanonicalFoodDocument(projection: CanonicalFoodProjection(
                records: LedgerMutation(), summaries: [summary], foodContractVersion: contract))
            XCTAssertThrowsError(try DailyHealthExportBuilder.addingFoodProjection(document, summary: summary, to: schemaV3), "contract \(contract)")
        }
        // A document claiming contract 3 while carrying favourite records is rejected: admission
        // checks the whole projection, favourites included (#198).
        let favourites = FavouriteMutation(favourites: [FavouriteEntry(
            favouriteID: try FavouriteID("00000000-0000-0000-0000-000000000001"), createdAt: Date(timeIntervalSince1970: 0))])
        let six = try CanonicalFoodDocument(projection: CanonicalFoodProjection(
            records: LedgerMutation(), summaries: [summary], favourites: favourites, foodContractVersion: 6))
        let encoder = FoundationCanonicalJSONEncoder()
        let relabelled = try XCTUnwrap(String(data: try encoder.encode(six), encoding: .utf8))
            .replacingOccurrences(of: #""foodContractVersion":6"#, with: #""foodContractVersion":3"#)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let mislabelled = try decoder.decode(CanonicalFoodDocument.self, from: Data(relabelled.utf8))
        XCTAssertEqual(mislabelled.projection.foodContractVersion, 3)
        XCTAssertFalse(mislabelled.projection.favourites.isEmpty)
        XCTAssertThrowsError(try DailyHealthExportBuilder.addingFoodProjection(mislabelled, summary: summary, to: schemaV3))
    }

    func testSchemaV4AddsCanonicalFoodProjectionWithoutChangingV3FixtureMeaning() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let schemaV3 = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: populatedInputs(window: window),
            notes: ["Invented note"]
        )
        let nutrientSet = try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: .unknown(.notDeclared))
        })
        let summary = CanonicalFoodNutritionSummary(
            summaryVersionID: try LedgerText("summary-fixture-v1"),
            reportingDate: try LedgerText("2026-09-06"),
            nutrients: nutrientSet,
            inputLogItemVersionIDs: [],
            hasUnknownContribution: true
        )
        for version in [1, 2] {
            let projection = try CanonicalFoodProjection(
                records: LedgerMutation(),
                summaries: [summary],
                foodContractVersion: version
            )
            let document = try CanonicalFoodDocument(projection: projection)
            let schemaV4 = try DailyHealthExportBuilder.addingFoodProjection(
                document,
                summary: summary,
                to: schemaV3
            )

            XCTAssertEqual(schemaV3.schemaVersion, 3)
            XCTAssertNil(schemaV3.today.foodLog)
            XCTAssertNil(schemaV3.today.foodNutritionSummary)
            XCTAssertEqual(schemaV4.schemaVersion, 4)
            XCTAssertEqual(schemaV4.today.foodLog, document)
            XCTAssertEqual(schemaV4.today.foodNutritionSummary?.nutrients.entries.count, 39)
            let schemaV4Bytes = try DailyHealthExportSerializer.encode(schemaV4)
            let text = try XCTUnwrap(String(data: schemaV4Bytes, encoding: .utf8))
            let forbiddenV6 = Data(text.replacingOccurrences(of: "\"schema_version\":4", with: "\"schema_version\":6").utf8)
            XCTAssertThrowsError(try DailyHealthExportIdentityPolicy().validate(payload: forbiddenV6, reportDate: "2026-09-06"))
            XCTAssertTrue(text.contains("\"schema_version\":4"))
            XCTAssertTrue(text.contains("\"food_contract_version\":\(version)"))
            XCTAssertTrue(text.contains("\"food_log\":"))
            XCTAssertTrue(text.contains("\"food_nutrition_summary\":"))
            XCTAssertThrowsError(
                try DailyHealthExportIdentityPolicy().validate(
                    payload: schemaV4Bytes,
                    reportDate: "2026-09-06"
                )
            ) { error in
                XCTAssertEqual(error as? DailyDriveExportFailure, .invalidPayload)
            }
        }
        try assertGolden(
            try DailyHealthExportSerializer.encode(schemaV3),
            equals: DailyHealthExportGoldenSnapshots.populated
        )
    }

    func testMorningEveningAndBedtimeRemainOneReportingDateWithFreshSnapshots() throws {
        let calendar = londonCalendar()
        let times = [8, 18, 23]
        let weights = [80.1, 80.2, 80.3]

        for (hour, kilograms) in zip(times, weights) {
            let cutoff = date(2026, 9, 6, hour, calendar: calendar)
            let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
            let inputs = replacing(
                emptyInputs(window: window),
                weight: [WeightMeasurement(
                    date: cutoff.addingTimeInterval(-60),
                    kilograms: kilograms
                )]
            )
            let envelope = try DailyHealthExportBuilder.make(
                window: window,
                exportedAt: cutoff,
                inputs: inputs
            )

            XCTAssertEqual(envelope.reportDate, "2026-09-06")
            XCTAssertEqual(envelope.today.weight.data?.value, kilograms)
            XCTAssertEqual(envelope.dataAsOf, String(format: "2026-09-06T%02d:00:00+01:00", hour))
            XCTAssertEqual(
                envelope.appContext.weight.data?.currentSevenDayAverage.availability,
                .insufficientData
            )
        }
    }

    func testWindowHandlesMidnightAndDSTWithoutAssumingTwentyFourHours() throws {
        let calendar = londonCalendar()
        let midnight = try DailyExportWindow.capture(
            at: date(2026, 9, 7, 0, calendar: calendar),
            calendar: calendar
        )
        XCTAssertEqual(midnight.reportDate, "2026-09-07")
        XCTAssertTrue(midnight.glucoseHours.isEmpty)
        XCTAssertEqual(midnight.day.start, midnight.day.end)

        let spring = try DailyExportWindow.capture(
            at: date(2026, 3, 29, 23, calendar: calendar),
            calendar: calendar
        )
        let autumn = try DailyExportWindow.capture(
            at: date(2026, 10, 25, 23, calendar: calendar),
            calendar: calendar
        )
        XCTAssertEqual(spring.glucoseHours.count, 22)
        XCTAssertEqual(autumn.glucoseHours.count, 24)
        XCTAssertTrue(autumn.glucoseHours.contains {
            $0.start.timeIntervalSince1970 != $0.end.timeIntervalSince1970
        })
    }

    func testLaterCorrectionCanRemoveEarlierTodayValueWithoutReusingSnapshot() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 18, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let earlier = replacing(
            emptyInputs(window: window),
            weight: [WeightMeasurement(date: cutoff.addingTimeInterval(-3_600), kilograms: 82)]
        )
        let corrected = emptyInputs(window: window)

        let first = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: earlier
        )
        let second = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff.addingTimeInterval(60),
            inputs: corrected
        )

        XCTAssertEqual(first.today.weight.availability, .available)
        XCTAssertEqual(second.today.weight.availability, .noDataOrAccess)
        XCTAssertNil(second.today.weight.data)
    }

    func testAppContextMapsExistingPureCalculationsWithoutUsingUISelection() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let inputs = populatedInputs(window: window)
        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: inputs
        )

        let expectedWeight = try XCTUnwrap(WeightTrendSummary.calculate(
            measurements: inputs.weight,
            asOf: cutoff,
            calendar: calendar
        ))
        XCTAssertEqual(
            envelope.appContext.weight.data?.currentSevenDayAverage.data?.value,
            expectedWeight.currentSevenDayAverage
        )
        XCTAssertEqual(
            envelope.appContext.weight.data?.trend.data?.change,
            expectedWeight.trendKilograms
        )

        let expectedGlucose = try XCTUnwrap(GlucoseSummary.aggregate(inputs.contextGlucose))
        XCTAssertEqual(
            envelope.appContext.glucose.data?.statistics.average,
            expectedGlucose.averageMillimolesPerLiter
        )
        let expectedSteps = try XCTUnwrap(StepSummary.aggregate(inputs.contextSteps))
        XCTAssertEqual(envelope.appContext.steps.data?.total.value, expectedSteps.totalSteps)
        XCTAssertEqual(
            envelope.appContext.steps.data?.dailyAverage.value,
            expectedSteps.averageDailySteps
        )

        let expectedRHR = try XCTUnwrap(HeartMetricTrendSummary.calculate(
            currentValues: inputs.contextRestingHeartRate,
            previousValues: inputs.previousRestingHeartRate
        ))
        XCTAssertEqual(
            envelope.appContext.restingHeartRate.data?.currentAverage.value,
            expectedRHR.current.average
        )
        XCTAssertEqual(
            envelope.appContext.restingHeartRate.data?.trend.data?.change,
            expectedRHR.trend
        )

        let expectedSleep = try XCTUnwrap(SleepSummary.calculate(
            asleepIntervals: inputs.contextAsleepIntervals,
            period: window.context,
            calendar: calendar
        ))
        XCTAssertEqual(
            envelope.appContext.sleep.data?.averageDurationSeconds,
            expectedSleep.averageDuration
        )
        XCTAssertEqual(envelope.appContext.workouts.data?.count, inputs.contextWorkouts.count)
        XCTAssertEqual(envelope.appContext.medications.data?.takenEventCount, 1)
        XCTAssertEqual(envelope.appContext.policyID, "last_7_completed_days_v1")
        XCTAssertEqual(
            envelope.appContext.window.start,
            "2026-08-30T00:00:00+01:00"
        )
    }

    func testAppContextUsesHalfOpenWeightCoverageAndCompletedBodyFatWindows() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let day = { offset in
            calendar.date(byAdding: .day, value: offset, to: window.day.start)!
        }
        let weights = (-14 ... -1).map { offset in
            WeightMeasurement(
                date: calendar.date(byAdding: .hour, value: 8, to: day(offset))!,
                kilograms: 80 + Double(offset) / 10
            )
        }
        let bodyFat = [
            BodyFatMeasurement(date: day(-40), percentage: 26),
            BodyFatMeasurement(date: day(-30), percentage: 24),
            BodyFatMeasurement(date: day(-2), percentage: 22),
            BodyFatMeasurement(date: day(-1), percentage: 20),
            BodyFatMeasurement(date: day(0), percentage: 90)
        ]
        let inputs = replacing(
            emptyInputs(window: window),
            weight: weights,
            bodyFat: bodyFat
        )

        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: inputs
        )

        XCTAssertEqual(envelope.schemaVersion, 3)
        XCTAssertEqual(
            envelope.appContext.weight.data?.currentSevenDayAverage.data?.coverage.sampledDays,
            7
        )
        XCTAssertEqual(
            envelope.appContext.weight.data?.previousSevenDayAverage.data?.coverage.sampledDays,
            7
        )
        XCTAssertEqual(
            envelope.appContext.bodyFat.data?.sevenDayAverage.data?.value,
            21
        )
        XCTAssertEqual(
            envelope.appContext.bodyFat.data?.sevenDayAverage.data?.window.end,
            "2026-09-06T00:00:00+01:00"
        )
        XCTAssertEqual(
            envelope.appContext.bodyFat.data?.current28DayAverage.data?.window.end,
            "2026-09-06T00:00:00+01:00"
        )
        XCTAssertEqual(envelope.appContext.bodyFat.data?.latest.value, 90)
    }

    func testAppContextStepAverageAndCoverageUseVisibleDaysOnly() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let contextSteps = window.context.completedDays.enumerated().map { index, day in
            DailyStepTotal(
                day: day,
                steps: index == 1 ? 10_000 : index == 5 ? 4_000 : nil,
                sourceNames: index == 1 || index == 5 ? ["Invented resolver"] : []
            )
        }
        let inputs = replacing(
            emptyInputs(window: window),
            contextSteps: contextSteps
        )

        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: inputs
        )

        XCTAssertEqual(envelope.appContext.steps.data?.dailyAverage.value, 7_000)
        XCTAssertEqual(envelope.appContext.steps.data?.coverage.sampledDays, 2)
        XCTAssertEqual(envelope.appContext.steps.data?.coverage.reportingDays, 7)
    }

    func testQueryFailureBlocksSerialization() async throws {
        let calendar = londonCalendar()
        let provider = FailingDailyProvider()
        let service = DailyHealthExportService(
            healthData: provider,
            calendar: calendar,
            now: { self.date(2026, 9, 6, 8, calendar: calendar) }
        )

        do {
            _ = try await service.refresh(
                nutritionSourceBundleIdentifier: fixtureNutritionSource.bundleIdentifier
            )
            XCTFail("Expected the invented query failure to block JSON creation")
        } catch ProbeError.queryFailed {
            XCTAssertEqual(provider.fetchCount, 1)
        }
    }

    func testServiceFreezesCutoffBeforeQueryAndRecordsLaterExportTime() async throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 8, calendar: calendar)
        let exportedAt = cutoff.addingTimeInterval(30)
        let provider = RecordingDailyProvider { window in
            self.emptyInputs(window: window)
        }
        var times = [cutoff, exportedAt].makeIterator()
        let service = DailyHealthExportService(
            healthData: provider,
            calendar: calendar,
            now: { times.next()! }
        )

        let result = try await service.refresh(
            nutritionSourceBundleIdentifier: fixtureNutritionSource.bundleIdentifier
        )

        XCTAssertEqual(provider.window?.cutoff, cutoff)
        XCTAssertEqual(result.envelope.dataAsOf, "2026-09-06T08:00:00+01:00")
        XCTAssertEqual(result.envelope.exportedAt, "2026-09-06T08:00:30+01:00")
        XCTAssertEqual(result.envelope.appContext.policyID, "last_7_completed_days_v1")
    }

    func testServiceFreezesNotesWithTheHealthWindowAndSerializesExactStrings() async throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 8, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        var notes = DailyNotesDocument()
        try notes.beginDraft(for: DailyNoteDayID(window: window), now: cutoff)
        try notes.updateDraft(text: "Energy good 🌤️\nEasy run.", now: cutoff)
        try notes.saveDraft(now: cutoff)
        try notes.beginDraft(for: DailyNoteDayID(window: window), now: cutoff)
        try notes.updateDraft(text: "Unfinished private draft", now: cutoff)
        let store = SequencedDailyNotesStore(documents: [notes, notes])
        let provider = RecordingDailyProvider { self.emptyInputs(window: $0) }
        var times = [cutoff, cutoff.addingTimeInterval(1)].makeIterator()
        let service = DailyHealthExportService(
            healthData: provider,
            notesStore: store,
            calendar: calendar,
            now: { times.next()! }
        )

        let result = try await service.refresh(
            nutritionSourceBundleIdentifier: fixtureNutritionSource.bundleIdentifier
        )

        XCTAssertEqual(result.notesSnapshot.dayID, DailyNoteDayID(window: window))
        XCTAssertEqual(result.envelope.today.notes, ["Energy good 🌤️\nEasy run."])
        let text = try XCTUnwrap(String(data: result.bytes, encoding: .utf8))
        XCTAssertTrue(text.contains("\"notes\":["))
        XCTAssertTrue(text.contains("Energy good 🌤️\\nEasy run."))
        XCTAssertFalse(text.contains("Unfinished private draft"))
        XCTAssertFalse(text.contains("\"audio\""))
    }

    func testProtectedNotesBlockPreviewBeforeHealthQueries() async throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 8, calendar: calendar)
        let store = FileDailyNotesStore(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: "locked-notes-\(UUID().uuidString).json"),
            isProtectedDataAvailable: { false }
        )
        let provider = RecordingDailyProvider { self.emptyInputs(window: $0) }
        let service = DailyHealthExportService(
            healthData: provider,
            notesStore: store,
            calendar: calendar,
            now: { cutoff }
        )

        do {
            _ = try await service.refresh(
                nutritionSourceBundleIdentifier: fixtureNutritionSource.bundleIdentifier
            )
            XCTFail("Protected notes must block preview preparation")
        } catch DailyHealthExportError.notesUnavailable {}
        XCTAssertNil(provider.window)
    }

    func testServiceRejectsNoteMutationDuringHealthRefresh() async throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 8, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        var first = DailyNotesDocument()
        try first.beginDraft(for: DailyNoteDayID(window: window), now: cutoff)
        try first.updateDraft(text: "First", now: cutoff)
        try first.saveDraft(now: cutoff)
        var changed = first
        try changed.beginDraft(for: DailyNoteDayID(window: window), now: cutoff)
        try changed.updateDraft(text: "Changed", now: cutoff)
        try changed.saveDraft(now: cutoff)
        let store = SequencedDailyNotesStore(documents: [first, changed])
        let provider = RecordingDailyProvider { self.emptyInputs(window: $0) }
        let service = DailyHealthExportService(
            healthData: provider,
            notesStore: store,
            calendar: calendar,
            now: { cutoff }
        )

        do {
            _ = try await service.refresh(
                nutritionSourceBundleIdentifier: fixtureNutritionSource.bundleIdentifier
            )
            XCTFail("A preview with a stale saved-note revision must not be published")
        } catch DailyHealthExportError.notesChanged {}
    }

    @MainActor
    func testSessionInvalidatesPublishedPreviewAfterSavedNoteMutation() async throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 8, calendar: calendar)
        let notesStore = MutableDailyNotesStore()
        let notes = DailyNotesController(
            store: notesStore,
            calendar: calendar,
            now: { cutoff }
        )
        let provider = RecordingDailyProvider { self.emptyInputs(window: $0) }
        let keychain = MemoryDailySessionStore()
        let session = DailyDriveSessionController(
            keychain: keychain,
            drive: DailyDriveAPI(),
            exportService: DailyHealthExportService(
                healthData: provider,
                notesStore: notesStore,
                calendar: calendar,
                now: { cutoff }
            ),
            identityStore: ControllerMemoryDailyIdentityStore(),
            nutritionSourceSelection: FixedNutritionSourceSelection(
                bundleIdentifier: fixtureNutritionSource.bundleIdentifier
            ),
            notes: notes
        )

        await session.refreshPreview()
        XCTAssertNotNil(session.preview)
        XCTAssertEqual(session.preview?.envelope.today.notes, [])
        let reviewedBytes = try XCTUnwrap(session.preview?.bytes)
        let summary = try XCTUnwrap(session.previewSummary)
        XCTAssertEqual(summary.encodedByteCount, reviewedBytes.count)
        XCTAssertEqual(summary.savedNoteCount, 0)
        XCTAssertEqual(session.exactJSONConstructionCount, 0)
        XCTAssertEqual(session.makeExactPreviewText(), String(data: reviewedBytes, encoding: .utf8))
        XCTAssertEqual(session.exactJSONConstructionCount, 1)

        notesStore.failSaves = true
        XCTAssertFalse(notes.beginNewDraft())
        XCTAssertEqual(session.preview?.bytes, reviewedBytes)
        notesStore.failSaves = false

        XCTAssertTrue(notes.beginNewDraft())
        notes.updateDraftText("New context")
        XCTAssertTrue(notes.saveDraft())

        XCTAssertNil(session.preview)
        XCTAssertFalse(session.canExport)
        XCTAssertTrue(session.status.contains("Saved notes changed"))
    }

    @MainActor
    func testSessionDiscardsPreviewOnlyForUncancelledVerifiedResults() async throws {
        for result in [
            DailyDriveExportResult.verified(
                dataAsOf: "2026-09-06T08:00:00+01:00",
                created: true
            ),
            .unchangedVerified(dataAsOf: "2026-09-06T08:00:00+01:00")
        ] {
            let (session, _) = await makePreviewLifecycleSession()
            let exportedPreview = try XCTUnwrap(session.preview)

            try session.applyExportOutcome(.success(result), exportedPreview: exportedPreview)

            XCTAssertNil(session.preview)
            XCTAssertFalse(session.canExport)
            XCTAssertTrue(session.lastVerifiedLabel.contains("2026-09-06T08:00:00+01:00"))
            XCTAssertTrue(session.status.contains("verified"))
        }
    }

    @MainActor
    func testSessionPreservesPreviewForCancellationResults() async throws {
        for result in [
            DailyDriveExportResult.cancelledBeforeSubmission,
            .cancelledAfterSubmissionVerified(
                dataAsOf: "2026-09-06T08:00:00+01:00",
                created: true
            )
        ] {
            let (session, _) = await makePreviewLifecycleSession()
            let exportedPreview = try XCTUnwrap(session.preview)

            try session.applyExportOutcome(.success(result), exportedPreview: exportedPreview)

            XCTAssertEqual(session.preview, exportedPreview)
            XCTAssertTrue(session.status.contains("Cancelled") || session.status.contains("Cancellation"))
        }
    }

    @MainActor
    func testSessionPreservesPreviewForFailedUncertainAndStaleOutcomes() async throws {
        for failure in [
            DailyDriveExportFailure.transportFailure,
            .unresolvedRequest,
            .staleCompletion
        ] {
            let (session, _) = await makePreviewLifecycleSession()
            let exportedPreview = try XCTUnwrap(session.preview)

            XCTAssertThrowsError(
                try session.applyExportOutcome(
                    .failure(failure),
                    exportedPreview: exportedPreview
                )
            ) { error in
                XCTAssertEqual(error as? DailyDriveExportFailure, failure)
            }
            XCTAssertEqual(session.preview, exportedPreview)
        }
    }

    @MainActor
    func testSessionDoesNotDiscardANewerPreviewForAnOlderVerifiedCompletion() async throws {
        let (session, _) = await makePreviewLifecycleSession()
        let currentPreview = try XCTUnwrap(session.preview)
        let olderPreview = DailyHealthExportResult(
            envelope: currentPreview.envelope,
            bytes: currentPreview.bytes + Data([0]),
            notesSnapshot: currentPreview.notesSnapshot
        )

        try session.applyExportOutcome(
            .success(.verified(
                dataAsOf: "2026-09-06T08:00:00+01:00",
                created: false
            )),
            exportedPreview: olderPreview
        )

        XCTAssertEqual(session.preview, currentPreview)
        XCTAssertTrue(session.lastVerifiedLabel.contains("2026-09-06T08:00:00+01:00"))
    }

    @MainActor
    func testSessionDiscardsVerifiedPreviewAfterFailedNoteMarkerDecision() async throws {
        let (session, notesStore) = await makePreviewLifecycleSession()
        let exportedPreview = try XCTUnwrap(session.preview)
        notesStore.failSaves = true

        try session.applyExportOutcome(
            .success(.verified(
                dataAsOf: "2026-09-06T08:00:00+01:00",
                created: false
            )),
            exportedPreview: exportedPreview
        )

        XCTAssertNil(session.preview)
        XCTAssertTrue(session.status.contains("Current notes were retained"))
        XCTAssertTrue(session.lastVerifiedLabel.contains("2026-09-06T08:00:00+01:00"))
    }

    func testNutritionCatalogueIsCompleteOrderedUniqueAndUnitCompatible() throws {
        let expected: [(String, HKQuantityTypeIdentifier, NutritionExportUnit)] = [
            ("energy_consumed", .dietaryEnergyConsumed, .kilocalories),
            ("carbohydrates", .dietaryCarbohydrates, .grams),
            ("protein", .dietaryProtein, .grams),
            ("fat_total", .dietaryFatTotal, .grams),
            ("fat_saturated", .dietaryFatSaturated, .grams),
            ("fat_monounsaturated", .dietaryFatMonounsaturated, .grams),
            ("fat_polyunsaturated", .dietaryFatPolyunsaturated, .grams),
            ("fiber", .dietaryFiber, .grams),
            ("sugar", .dietarySugar, .grams),
            ("cholesterol", .dietaryCholesterol, .milligrams),
            ("vitamin_a", .dietaryVitaminA, .micrograms),
            ("thiamin_b1", .dietaryThiamin, .milligrams),
            ("riboflavin_b2", .dietaryRiboflavin, .milligrams),
            ("niacin_b3", .dietaryNiacin, .milligrams),
            ("pantothenic_acid_b5", .dietaryPantothenicAcid, .milligrams),
            ("vitamin_b6", .dietaryVitaminB6, .milligrams),
            ("biotin_b7", .dietaryBiotin, .micrograms),
            ("folate_b9", .dietaryFolate, .micrograms),
            ("vitamin_b12", .dietaryVitaminB12, .micrograms),
            ("vitamin_c", .dietaryVitaminC, .milligrams),
            ("vitamin_d", .dietaryVitaminD, .micrograms),
            ("vitamin_e", .dietaryVitaminE, .milligrams),
            ("vitamin_k", .dietaryVitaminK, .micrograms),
            ("calcium", .dietaryCalcium, .milligrams),
            ("chloride", .dietaryChloride, .milligrams),
            ("iron", .dietaryIron, .milligrams),
            ("magnesium", .dietaryMagnesium, .milligrams),
            ("phosphorus", .dietaryPhosphorus, .milligrams),
            ("potassium", .dietaryPotassium, .milligrams),
            ("sodium", .dietarySodium, .milligrams),
            ("zinc", .dietaryZinc, .milligrams),
            ("chromium", .dietaryChromium, .micrograms),
            ("copper", .dietaryCopper, .milligrams),
            ("iodine", .dietaryIodine, .micrograms),
            ("manganese", .dietaryManganese, .milligrams),
            ("molybdenum", .dietaryMolybdenum, .micrograms),
            ("selenium", .dietarySelenium, .micrograms),
            ("water", .dietaryWater, .millilitres),
            ("caffeine", .dietaryCaffeine, .milligrams)
        ]

        XCTAssertEqual(NutritionCatalogue.all.count, 39)
        XCTAssertEqual(Set(NutritionCatalogue.all.map(\.key)).count, 39)
        XCTAssertEqual(NutritionCatalogue.all.map(\.key), expected.map(\.0))
        XCTAssertEqual(NutritionCatalogue.all.map(\.unit), expected.map(\.2))
        XCTAssertEqual(NutritionQueryCatalogue.quantityTypeIdentifiers.count, 39)
        XCTAssertEqual(
            Set(NutritionQueryCatalogue.quantityTypeIdentifiers.keys),
            Set(NutritionCatalogue.all.map(\.key))
        )
        XCTAssertEqual(
            Set(NutritionQueryCatalogue.quantityTypeIdentifiers.values).count,
            39
        )
        XCTAssertEqual(NutritionCatalogue.all.map(\.label), [
            "Energy Consumed", "Carbohydrates", "Protein", "Total Fat",
            "Saturated Fat", "Monounsaturated Fat", "Polyunsaturated Fat", "Fibre",
            "Sugar", "Cholesterol", "Vitamin A", "Thiamin (B1)",
            "Riboflavin (B2)", "Niacin (B3)", "Pantothenic Acid (B5)", "Vitamin B6",
            "Biotin (B7)", "Folate (B9)", "Vitamin B12", "Vitamin C", "Vitamin D",
            "Vitamin E", "Vitamin K", "Calcium", "Chloride", "Iron", "Magnesium",
            "Phosphorus", "Potassium", "Sodium", "Zinc", "Chromium", "Copper",
            "Iodine", "Manganese", "Molybdenum", "Selenium", "Water", "Caffeine"
        ])
        XCTAssertEqual(NutritionCatalogue.all.map(\.category), [
            .energy,
            .macronutrient, .macronutrient, .macronutrient, .macronutrient,
            .macronutrient, .macronutrient, .macronutrient, .macronutrient,
            .macronutrient,
            .vitamin, .vitamin, .vitamin, .vitamin, .vitamin, .vitamin, .vitamin,
            .vitamin, .vitamin, .vitamin, .vitamin, .vitamin, .vitamin,
            .mineral, .mineral, .mineral, .mineral, .mineral, .mineral, .mineral,
            .mineral,
            .ultratraceMineral, .ultratraceMineral, .ultratraceMineral,
            .ultratraceMineral, .ultratraceMineral, .ultratraceMineral,
            .hydration, .caffeination
        ])
        for (definition, (_, expectedIdentifier, _)) in zip(
            NutritionCatalogue.all,
            expected
        ) {
            let identifier = try XCTUnwrap(
                NutritionQueryCatalogue.quantityTypeIdentifiers[definition.key]
            )
            XCTAssertEqual(identifier, expectedIdentifier)
            let type = try XCTUnwrap(
                HKObjectType.quantityType(forIdentifier: identifier)
            )
            XCTAssertTrue(type.is(compatibleWith: definition.unit.healthKitUnit))
        }
    }

    func testNutritionCompleteWindowsProduceDailyValuesAveragesAndSignedTrend() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 23, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let input = nutrition(
            window: window,
            key: "energy_consumed",
            today: 1_750,
            current: [1_400, 1_500, 1_600, 1_700, 1_800, 1_900, 2_000],
            previous: [1_300, 1_400, 1_500, 1_600, 1_700, 1_800, 1_900]
        )
        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: replacing(emptyInputs(window: window), nutrition: input)
        )

        let today = try XCTUnwrap(envelope.today.nutrition?.nutrients.first)
        let context = try XCTUnwrap(envelope.appContext.nutrition?.nutrients.first)
        XCTAssertEqual(today.key, "energy_consumed")
        XCTAssertEqual(today.value.data, ExportScalar(value: 1_750, unit: "kcal"))
        XCTAssertEqual(context.days.count, 7)
        XCTAssertEqual(context.days.map(\.date), [
            "2026-08-30", "2026-08-31", "2026-09-01", "2026-09-02",
            "2026-09-03", "2026-09-04", "2026-09-05"
        ])
        XCTAssertEqual(context.average.data?.value, 1_700)
        XCTAssertEqual(context.average.data?.sampledDays, 7)
        XCTAssertEqual(context.average.data?.reportingDays, 7)
        XCTAssertEqual(context.previousAverage.data?.value, 1_600)
        XCTAssertEqual(context.trend.data?.change, 100)
        XCTAssertEqual(context.trend.data?.unit, "kcal")
        XCTAssertEqual(
            envelope.appContext.nutrition?.policyID,
            NutritionCatalogue.reportingPolicyID
        )
    }

    func testNutritionSparseAndEmptyDaysPreserveCoverageAndAvailability() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 12, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let sparse = nutrition(
            window: window,
            key: "protein",
            today: nil,
            current: [60, nil, 80, nil, nil, nil, nil],
            previous: [50, 60, 70, 80, 90, 100, 110]
        )
        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: replacing(emptyInputs(window: window), nutrition: sparse)
        )
        let protein = try XCTUnwrap(
            envelope.appContext.nutrition?.nutrients.first { $0.key == "protein" }
        )
        let calcium = try XCTUnwrap(
            envelope.appContext.nutrition?.nutrients.first { $0.key == "calcium" }
        )

        XCTAssertEqual(protein.days.map(\.value.availability), [
            .available, .noDataOrAccess, .available, .noDataOrAccess,
            .noDataOrAccess, .noDataOrAccess, .noDataOrAccess
        ])
        XCTAssertEqual(protein.average.data?.value, 70)
        XCTAssertEqual(protein.average.data?.sampledDays, 2)
        XCTAssertEqual(protein.average.data?.reportingDays, 7)
        XCTAssertEqual(protein.previousAverage.data?.sampledDays, 7)
        XCTAssertEqual(protein.trend.availability, .insufficientData)
        XCTAssertEqual(
            envelope.today.nutrition?.nutrients.first { $0.key == "protein" }?
                .value.availability,
            .noDataOrAccess
        )
        XCTAssertEqual(
            envelope.today.nutrition?.nutrients.first { $0.key == "protein" }?.unit,
            "g"
        )
        XCTAssertEqual(calcium.average.availability, .noDataOrAccess)
        XCTAssertEqual(calcium.previousAverage.availability, .noDataOrAccess)
        XCTAssertEqual(calcium.trend.availability, .insufficientData)
    }

    func testNutritionRejectsNonFiniteValuesAndWrongCatalogueOrder() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 12, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let nonFinite = nutrition(
            window: window,
            key: "water",
            today: .infinity,
            current: Array(repeating: nil, count: 7),
            previous: Array(repeating: nil, count: 7)
        )
        XCTAssertThrowsError(try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: replacing(emptyInputs(window: window), nutrition: nonFinite)
        )) { error in
            XCTAssertEqual(error as? DailyHealthExportError, .invalidMetricValue)
        }

        let reversed = NutritionExportInput(
            source: nonFinite.source,
            nutrients: nonFinite.nutrients.reversed()
        )
        XCTAssertThrowsError(try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: replacing(emptyInputs(window: window), nutrition: reversed)
        )) { error in
            XCTAssertEqual(error as? DailyHealthExportError, .invalidWindow)
        }
    }

    func testNutritionUsesSevenCalendarDaysAcrossDST() throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 4, 1, 8, calendar: calendar)
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff,
            inputs: emptyInputs(window: window)
        )
        let nutrition = try XCTUnwrap(envelope.appContext.nutrition)

        XCTAssertEqual(nutrition.nutrients.first?.days.count, 7)
        XCTAssertEqual(nutrition.currentWindow.start, "2026-03-25T00:00:00Z")
        XCTAssertEqual(nutrition.currentWindow.end, "2026-04-01T00:00:00+01:00")
    }

    func testServiceKeepsSameNameSourcesDistinctAndNeverFallsBack() async throws {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 8, calendar: calendar)
        let first = NutritionSource(bundleIdentifier: "example.source.a", name: "Same Name")
        let selected = NutritionSource(bundleIdentifier: "example.source.b", name: "Same Name")
        let provider = RecordingDailyProvider(sources: [
            selected,
            NutritionSource(bundleIdentifier: first.bundleIdentifier, name: "Same Name Z"),
            first
        ]) { window, bundleID in
            self.replacing(
                self.emptyInputs(window: window),
                nutrition: self.nutrition(
                    window: window,
                    key: "protein",
                    today: bundleID == selected.bundleIdentifier ? 75 : 999,
                    current: Array(repeating: nil, count: 7),
                    previous: Array(repeating: nil, count: 7),
                    source: selected
                )
            )
        }
        let service = DailyHealthExportService(
            healthData: provider,
            calendar: calendar,
            now: { cutoff }
        )

        do {
            _ = try await service.refresh(nutritionSourceBundleIdentifier: nil)
            XCTFail("A missing selection must fail before querying health data")
        } catch DailyHealthExportError.nutritionSourceRequired {}
        XCTAssertEqual(provider.fetchCount, 0)

        let sources = try await service.discoverNutritionSources()
        XCTAssertEqual(sources, [first, selected])
        XCTAssertEqual(provider.nutritionAuthorizationCount, 1)
        XCTAssertEqual(provider.readAuthorizationCount, 0)
        let restoredSources = try await service.resolveNutritionSourcesWithoutAuthorization()
        XCTAssertEqual(restoredSources, [first, selected])
        XCTAssertEqual(provider.nutritionAuthorizationCount, 1)
        XCTAssertEqual(provider.readAuthorizationCount, 0)
        let result = try await service.refresh(
            nutritionSourceBundleIdentifier: selected.bundleIdentifier
        )
        XCTAssertEqual(provider.nutritionAuthorizationCount, 1)
        XCTAssertEqual(provider.readAuthorizationCount, 0)
        XCTAssertEqual(provider.requestedSourceBundleIdentifier, selected.bundleIdentifier)
        XCTAssertEqual(
            result.envelope.today.nutrition?.nutrients.first { $0.key == "protein" }?
                .value.data?.value,
            75
        )

        do {
            _ = try await service.refresh(
                nutritionSourceBundleIdentifier: "example.source.missing"
            )
            XCTFail("An unresolved source must fail before any unfiltered query")
        } catch DailyHealthExportError.nutritionSourceUnavailable {}
        XCTAssertEqual(provider.fetchCount, 1)

        let contaminatedProvider = RecordingDailyProvider(sources: [first, selected]) {
            window, _ in
            self.replacing(
                self.emptyInputs(window: window),
                nutrition: self.nutrition(
                    window: window,
                    key: "protein",
                    today: 999,
                    current: Array(repeating: nil, count: 7),
                    previous: Array(repeating: nil, count: 7),
                    source: first
                )
            )
        }
        let contaminatedService = DailyHealthExportService(
            healthData: contaminatedProvider,
            calendar: calendar,
            now: { cutoff }
        )
        do {
            _ = try await contaminatedService.refresh(
                nutritionSourceBundleIdentifier: selected.bundleIdentifier
            )
            XCTFail("Data labelled with another source must not be serialized")
        } catch DailyHealthExportError.nutritionSourceUnavailable {}
    }

    func testNutritionSourceSelectionPersistsOnlyBundleIdentifier() throws {
        let suiteName = "WeeklyHealthReportTests.NutritionSourceSelection"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsNutritionSourceSelectionStore(defaults: defaults)

        store.saveBundleIdentifier("example.same-name.second")
        XCTAssertEqual(store.loadBundleIdentifier(), "example.same-name.second")
        store.saveBundleIdentifier(nil)
        XCTAssertNil(store.loadBundleIdentifier())
    }

    @MainActor
    func testPreparationWithNoStoredSessionStopsBeforeDriveHealthOrUpload() async {
        let driver = PreparationDriverFixture(hasStoredGoogleSession: false)
        let orchestrator = DailyExportPreparationOrchestrator()

        let state = await orchestrator.prepare(using: driver)

        XCTAssertEqual(state, .needsGoogleConnection)
        XCTAssertEqual(driver.restoreCount, 0)
        XCTAssertEqual(driver.resolveCount, 0)
        XCTAssertEqual(driver.refreshCount, 0)
        XCTAssertEqual(driver.authorizationRequestCount, 0)
        XCTAssertEqual(driver.uploadCount, 0)
    }

    @MainActor
    func testHealthyStoredPreparationValidatesDestinationAndRefreshesAutomatically() async {
        let driver = PreparationDriverFixture()
        driver.destination = driver.fixtureDestination
        let orchestrator = DailyExportPreparationOrchestrator()

        let state = await orchestrator.prepare(using: driver)

        XCTAssertEqual(state, .readyToExport)
        XCTAssertEqual(driver.restoreCount, 1)
        XCTAssertEqual(driver.validateCount, 1)
        XCTAssertEqual(driver.createCount, 0)
        XCTAssertEqual(driver.resolvedBundleIdentifiers, [driver.savedBundleIdentifier])
        XCTAssertEqual(driver.refreshedBundleIdentifiers, [driver.savedBundleIdentifier])
        XCTAssertEqual(driver.authorizationRequestCount, 0)
        XCTAssertEqual(driver.uploadCount, 0)
    }

    @MainActor
    func testPreparationRequiringFreshConsentReturnsOnlyConnectionState() async {
        let driver = PreparationDriverFixture()
        driver.restoreFailure = .freshGoogleConsentRequired

        let state = await DailyExportPreparationOrchestrator().prepare(using: driver)

        XCTAssertEqual(state, .needsGoogleConnection)
        XCTAssertEqual(driver.createCount, 0)
        XCTAssertEqual(driver.resolveCount, 0)
        XCTAssertEqual(driver.refreshCount, 0)
    }

    @MainActor
    func testDestinationRestorationRequiresExplicitChoiceWhenDefinitivelyUnbound() async {
        let driver = PreparationDriverFixture()
        let orchestrator = DailyExportPreparationOrchestrator()

        let first = await orchestrator.prepare(using: driver)
        let second = await orchestrator.prepare(using: driver)

        XCTAssertEqual(first, .needsAttention(.destinationRequired))
        XCTAssertEqual(second, .needsAttention(.destinationRequired))
        XCTAssertEqual(driver.createCount, 0)
        XCTAssertEqual(driver.validateCount, 0)
        XCTAssertEqual(driver.refreshCount, 0)

        let inaccessible = PreparationDriverFixture()
        inaccessible.destination = inaccessible.fixtureDestination
        inaccessible.validationFailure = .destinationMissingOrInaccessible
        let inaccessibleState = await DailyExportPreparationOrchestrator()
            .prepare(using: inaccessible)
        XCTAssertEqual(
            inaccessibleState,
            .needsAttention(.destinationMissingOrInaccessible)
        )
        XCTAssertEqual(inaccessible.createCount, 0)

        let ambiguousLocalState = PreparationDriverFixture()
        ambiguousLocalState.destinationLookupFailure = .destinationSetupFailed
        let ambiguousState = await DailyExportPreparationOrchestrator()
            .prepare(using: ambiguousLocalState)
        XCTAssertEqual(ambiguousState, .needsAttention(.destinationSetupFailed))
        XCTAssertEqual(ambiguousLocalState.createCount, 0)

        let trashed = PreparationDriverFixture()
        trashed.destination = trashed.fixtureDestination
        trashed.validationFailure = .destinationTrashed
        let trashedState = await DailyExportPreparationOrchestrator().prepare(using: trashed)
        XCTAssertEqual(trashedState, .needsAttention(.destinationTrashed))
        XCTAssertEqual(trashed.createCount, 0)
    }

    @MainActor
    func testReservedDefaultFolderReconcilesLostSuccessWithoutDuplicateCreation() async throws {
        let drive = PreparationDriveTransportFixture(createOutcomes: [.transientAfterCommit])
        let session = makePreparationSession(drive: drive)
        let context = DailyExportGoogleContext(
            account: await drive.fixtureAccount(),
            accessToken: "invented-token"
        )

        try await session.createDefaultDestination(context: context)
        try await session.createDefaultDestination(context: context)

        let snapshot = await drive.snapshot()
        XCTAssertEqual(snapshot.generatedCount, 1)
        XCTAssertEqual(snapshot.createIDs, ["reserved-folder-1"])
        XCTAssertEqual(snapshot.folderCount, 1)
        XCTAssertGreaterThanOrEqual(snapshot.folderReadCount, 2)
        XCTAssertEqual(snapshot.uploadCount, 0)
        XCTAssertEqual(
            try session.storedDestination(for: context.account.id)?.folderName,
            DailyDriveConsentPolicy.defaultExportFolderName
        )
        XCTAssertEqual(
            DailyDriveConsentPolicy.defaultExportFolderName,
            "WeeklyHealthReport Exports"
        )
    }

    @MainActor
    func testReservedDefaultFolderRetriesSameIDAfterDefinitivePreCommitFailure() async throws {
        let drive = PreparationDriveTransportFixture(
            createOutcomes: [.transientBeforeCommit, .success]
        )
        let secureStore = MemoryDailySessionStore()
        let session = makePreparationSession(drive: drive, secureStore: secureStore)
        let context = DailyExportGoogleContext(
            account: await drive.fixtureAccount(),
            accessToken: "invented-token"
        )

        do {
            try await session.createDefaultDestination(context: context)
            XCTFail("The first pre-commit failure should remain retryable by reserved ID")
        } catch DailyExportPreparationFailure.destinationSetupFailed {}
        let relaunched = makePreparationSession(drive: drive, secureStore: secureStore)
        try await relaunched.createDefaultDestination(context: context)

        let snapshot = await drive.snapshot()
        XCTAssertEqual(snapshot.generatedCount, 1)
        XCTAssertEqual(snapshot.createIDs, ["reserved-folder-1", "reserved-folder-1"])
        XCTAssertEqual(snapshot.folderCount, 1)
        XCTAssertEqual(snapshot.uploadCount, 0)
    }

    @MainActor
    func testDestinationCoordinatorRejectsMismatchedPickerWithoutChangingPartitions() throws {
        let store = MemoryDailySessionStore()
        let coordinator = DailyDestinationCoordinator(
            drive: PreparationDriveTransportFixture(createOutcomes: []),
            secureStore: store,
            destinationsKey: "destinations"
        )
        let folder = DailyDriveFolder(
            id: "folder-b",
            accountID: "account-b",
            name: "Invented",
            mimeType: DailyDriveConsentPolicy.folderMIMEType,
            trashed: false,
            driveID: nil,
            isAppAuthorized: true,
            canAddChildren: true
        )

        XCTAssertThrowsError(try coordinator.acceptPickedFolder(folder, accountID: "account-a")) {
            XCTAssertEqual($0 as? DailyDriveConsentPolicy.Failure, .accountMismatch)
        }
        XCTAssertNil(try coordinator.storedDestination(for: "account-a"))
        XCTAssertNil(store.snapshot(account: "destinations"))
    }

    @MainActor
    func testDestinationCoordinatorPublishesPickerBindingOnlyAfterPersistence() throws {
        let store = MemoryDailySessionStore()
        store.failSaves = true
        let coordinator = DailyDestinationCoordinator(
            drive: PreparationDriveTransportFixture(createOutcomes: []),
            secureStore: store,
            destinationsKey: "destinations"
        )
        let folder = DailyDriveFolder(
            id: "folder-a",
            accountID: "account-a",
            name: "Invented",
            mimeType: DailyDriveConsentPolicy.folderMIMEType,
            trashed: false,
            driveID: nil,
            isAppAuthorized: true,
            canAddChildren: true
        )

        XCTAssertThrowsError(try coordinator.acceptPickedFolder(folder, accountID: "account-a"))
        XCTAssertNil(try coordinator.storedDestination(for: "account-a"))

        store.failSaves = false
        try coordinator.acceptPickedFolder(folder, accountID: "account-a")
        XCTAssertEqual(try coordinator.storedDestination(for: "account-a")?.folderID, "folder-a")
        XCTAssertEqual(store.savedAccounts, ["destinations"])
    }

    @MainActor
    func testDestinationCoordinatorTracksAndForgetsOnlyExactTrashedDestination() async throws {
        let store = MemoryDailySessionStore()
        let drive = PreparationDriveTransportFixture(createOutcomes: [])
        let coordinator = DailyDestinationCoordinator(
            drive: drive,
            secureStore: store,
            destinationsKey: "destinations"
        )
        let account = await drive.fixtureAccount()
        let binding = DailyDestinationBinding(
            accountID: account.id,
            folderID: "folder-a",
            folderName: "Invented",
            origin: .picker
        )
        try store.save(try JSONEncoder().encode(partitions(containing: binding)), account: "destinations")
        try coordinator.restoreWithoutNetwork()
        await drive.seedFolder(DailyDriveFolder(
            id: binding.folderID,
            accountID: account.id,
            name: binding.folderName,
            mimeType: DailyDriveConsentPolicy.folderMIMEType,
            trashed: true,
            driveID: nil,
            isAppAuthorized: true,
            canAddChildren: true
        ))
        let context = DailyExportGoogleContext(account: account, accessToken: "invented-token")

        do {
            try await coordinator.validateStoredDestination(binding, context: context)
            XCTFail("A trashed destination must fail closed")
        } catch DailyExportPreparationFailure.destinationTrashed {}
        XCTAssertTrue(coordinator.canForgetTrashedDestination)
        XCTAssertNil(coordinator.trashedDestination(for: "other-account"))

        let candidate = try XCTUnwrap(coordinator.trashedDestination(for: account.id))
        try coordinator.forgetTrashedDestination(candidate)
        XCTAssertFalse(coordinator.canForgetTrashedDestination)
        XCTAssertNil(try coordinator.storedDestination(for: account.id))
    }

    @MainActor
    func testDestinationCoordinatorClearsFileCandidateOnlyForExactTriple() {
        let coordinator = DailyDestinationCoordinator(
            drive: PreparationDriveTransportFixture(createOutcomes: []),
            secureStore: MemoryDailySessionStore(),
            destinationsKey: "destinations"
        )
        coordinator.markFileForReplacement(
            accountID: "account-a",
            folderID: "folder-a",
            reportDate: "2026-09-15",
            reason: .trashed
        )

        coordinator.clearFileReplacementCandidate(
            accountID: "account-a",
            folderID: "folder-a",
            reportDate: "2026-09-14"
        )
        XCTAssertNotNil(coordinator.fileReplacementReason)
        coordinator.clearFileReplacementCandidate(
            accountID: "account-a",
            folderID: "folder-a",
            reportDate: "2026-09-15"
        )
        XCTAssertNil(coordinator.fileReplacementReason)
    }

    @MainActor
    func testDestinationCoordinatorBlocksCreationAfterCorruptRestore() async throws {
        let store = MemoryDailySessionStore()
        try store.save(Data("not-json".utf8), account: "destinations")
        let drive = PreparationDriveTransportFixture(createOutcomes: [])
        let coordinator = DailyDestinationCoordinator(
            drive: drive,
            secureStore: store,
            destinationsKey: "destinations"
        )
        XCTAssertThrowsError(try coordinator.restoreWithoutNetwork())
        let context = DailyExportGoogleContext(
            account: await drive.fixtureAccount(),
            accessToken: "invented-token"
        )

        do {
            try await coordinator.createDefaultDestination(context: context)
            XCTFail("Corrupt destination state must block creation")
        } catch DailyExportPreparationFailure.destinationSetupFailed {}
        let snapshot = await drive.snapshot()
        XCTAssertEqual(snapshot.generatedCount, 0)
    }

    @MainActor
    func testSessionRestoreRefreshFailureRequiresFreshGoogleConnection() async {
        let oauth = FakeDriveOAuthSession()
        oauth.accessTokenFailure = .expired
        let session = makePreparationSession(
            drive: PreparationDriveTransportFixture(createOutcomes: []),
            oauthSession: oauth
        )

        do {
            _ = try await session.restoreGoogleSession()
            XCTFail("A failed refresh must require fresh consent")
        } catch DailyExportPreparationFailure.freshGoogleConsentRequired {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testSessionRestoresLatestVerifiedLabelFromInjectedIdentityStore() async throws {
        let secureStore = MemoryDailySessionStore()
        let binding = DailyDestinationBinding(
            accountID: "invented-account",
            folderID: "folder-a",
            folderName: "Invented",
            origin: .picker
        )
        try secureStore.save(
            try JSONEncoder().encode(partitions(containing: binding)),
            account: "google.drive.daily-export-destinations.v1"
        )
        let identityStore = ControllerMemoryDailyIdentityStore(registry: DailyDriveExportRegistry(
            installationID: "invented-installation",
            identities: [
                identity(
                    accountID: binding.accountID,
                    folderID: binding.folderID,
                    dataAsOf: "2026-09-14T08:00:00+01:00",
                    verifiedAt: Date(timeIntervalSince1970: 1)
                ),
                identity(
                    accountID: binding.accountID,
                    folderID: binding.folderID,
                    dataAsOf: "2026-09-15T08:00:00+01:00",
                    verifiedAt: Date(timeIntervalSince1970: 2)
                ),
                identity(
                    accountID: binding.accountID,
                    folderID: "other-folder",
                    dataAsOf: "2026-09-16T08:00:00+01:00",
                    verifiedAt: Date(timeIntervalSince1970: 3)
                )
            ]
        ))
        let session = makePreparationSession(
            drive: PreparationDriveTransportFixture(createOutcomes: []),
            secureStore: secureStore,
            identityStore: identityStore,
            oauthSession: FakeDriveOAuthSession()
        )

        _ = try await session.restoreGoogleSession()

        XCTAssertEqual(
            session.lastVerifiedLabel,
            "Persisted verification through 2026-09-15T08:00:00+01:00"
        )
        XCTAssertEqual(identityStore.loadCount, 1)
    }

    // MARK: - Included summary and last export of the day (#217)

    @MainActor
    func testPreviewSummaryCountsComeFromThePreparedEnvelope() async throws {
        let (session, _) = await makePreviewLifecycleSession()
        let preview = try XCTUnwrap(session.preview)
        let summary = try XCTUnwrap(session.previewSummary)

        XCTAssertEqual(summary.included, DailyExportIncludedSummary.make(today: preview.envelope.today))
        XCTAssertEqual(
            summary.included.metricsApplicable,
            DailyExportIncludedSummary.metricAvailabilities(preview.envelope.today)
                .filter { $0 != .unsupported }.count
        )
        XCTAssertFalse(summary.included.line.contains("0 workouts"))
        XCTAssertTrue(summary.included.line.hasSuffix("no workouts visible"))
        XCTAssertEqual(session.exactJSONConstructionCount, 0)

        session.selectReportDay(session.availableReportDays.last)
        XCTAssertNil(session.previewSummary)
    }

    @MainActor
    func testLastExportOfSelectedDayShowsOnlyTheVerifiedRecordForThisDestination() async throws {
        let verifiedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let today = "2026-09-06"
        let (session, drive, oauth) = try await restoredLastExportSession(identities: [
            lastExportIdentity(reportDate: today, verifiedAt: verifiedAt),
            lastExportIdentity(reportDate: "2026-09-05", verifiedAt: verifiedAt.addingTimeInterval(60)),
            lastExportIdentity(folderID: "other-folder", reportDate: today, verifiedAt: verifiedAt.addingTimeInterval(120)),
            lastExportIdentity(accountID: "other-account", reportDate: today, verifiedAt: verifiedAt.addingTimeInterval(180))
        ])

        XCTAssertEqual(session.lastExportOfSelectedDay, DailyExportLastExportLookup(
            reportDate: today,
            state: .verified(verifiedAt: verifiedAt, dataAsOf: "2026-09-06T08:00:00+01:00"),
            hasPendingOperation: false
        ))

        // Lookups are local reads: no Drive, network or token request.
        let before = await drive.snapshot()
        let tokenCount = oauth.accessTokenCount
        XCTAssertEqual(session.lastVerifiedExport(for: "2026-09-05")?.state, .verified(
            verifiedAt: verifiedAt.addingTimeInterval(60),
            dataAsOf: "2026-09-06T08:00:00+01:00"
        ))
        XCTAssertEqual(session.lastVerifiedExport(for: "2026-09-04")?.state, DailyExportLastExport.none)
        session.selectReportDay(session.availableReportDays.first { $0.reportDate == "2026-09-04" })
        XCTAssertEqual(session.lastExportOfSelectedDay?.reportDate, "2026-09-04")
        XCTAssertEqual(session.lastExportOfSelectedDay?.state, DailyExportLastExport.none)
        let after = await drive.snapshot()
        XCTAssertEqual(after.accountCount, before.accountCount)
        XCTAssertEqual(after.folderReadCount, before.folderReadCount)
        XCTAssertEqual(after.uploadCount, before.uploadCount)
        XCTAssertEqual(oauth.accessTokenCount, tokenCount)
    }

    @MainActor
    func testLastExportOfSelectedDayOtherFolderOrAccountIsNone() async throws {
        let (session, _, _) = try await restoredLastExportSession(identities: [
            lastExportIdentity(folderID: "other-folder", reportDate: "2026-09-06", verifiedAt: Date(timeIntervalSince1970: 1)),
            lastExportIdentity(accountID: "other-account", reportDate: "2026-09-06", verifiedAt: Date(timeIntervalSince1970: 2))
        ])

        XCTAssertEqual(session.lastExportOfSelectedDay?.state, DailyExportLastExport.none)
        XCTAssertEqual(
            DailyExportLastExportFormatter.line(try XCTUnwrap(session.lastExportOfSelectedDay).state),
            "Last export of this day from this iPhone: none"
        )
    }

    @MainActor
    func testPendingOnlyOperationIsNeverShownAsAnExport() async throws {
        let pending = PendingDailyDriveOperation(
            operationID: "invented-operation",
            dataAsOf: "2026-09-06T08:00:00+01:00",
            payloadSHA256: "invented-hash",
            kind: .create,
            phase: .uncertain
        )
        let (session, _, _) = try await restoredLastExportSession(identities: [
            lastExportIdentity(reportDate: "2026-09-06", verifiedAt: nil, pending: pending)
        ])

        XCTAssertEqual(session.lastExportOfSelectedDay, DailyExportLastExportLookup(
            reportDate: "2026-09-06",
            state: .none,
            hasPendingOperation: true
        ))
    }

    @MainActor
    func testUnreadableRegistryShowsUnknownLastExport() async throws {
        let store = MemoryDailySessionStore()
        try store.save(
            try JSONEncoder().encode(partitions(containing: lastExportBinding)),
            account: "google.drive.daily-export-destinations.v1"
        )
        let identityStore = ControllerMemoryDailyIdentityStore(loadFailure: ProbeError.queryFailed)
        let (session, _) = await makePreviewLifecycleSession(
            drive: PreparationDriveTransportFixture(createOutcomes: []),
            secureStore: store,
            identityStore: identityStore,
            oauthSession: FakeDriveOAuthSession()
        )
        _ = try await session.restoreGoogleSession()

        XCTAssertEqual(session.lastExportOfSelectedDay?.state, .unknown)
        XCTAssertEqual(
            DailyExportLastExportFormatter.line(.unknown),
            "Last export of this day from this iPhone: unknown"
        )
        // Developer tools keeps the session label.
        XCTAssertEqual(session.lastVerifiedLabel, "Stored identity is ambiguous; explicit recovery required")
    }

    @MainActor
    func testDuplicateRegistryEntriesForTheSameDayAreUnknown() async throws {
        let (session, _, _) = try await restoredLastExportSession(identities: [
            lastExportIdentity(reportDate: "2026-09-06", verifiedAt: Date(timeIntervalSince1970: 1)),
            lastExportIdentity(reportDate: "2026-09-06", verifiedAt: Date(timeIntervalSince1970: 2))
        ])

        XCTAssertEqual(session.lastExportOfSelectedDay, DailyExportLastExportLookup(
            reportDate: "2026-09-06",
            state: .unknown,
            hasPendingOperation: false
        ))
    }

    @MainActor
    func testNoAccountOrNoFolderHidesTheLastExportLine() async throws {
        let identityStore = ControllerMemoryDailyIdentityStore(registry: DailyDriveExportRegistry(
            installationID: "invented-installation",
            identities: [lastExportIdentity(reportDate: "2026-09-06", verifiedAt: Date(timeIntervalSince1970: 1))]
        ))
        let (session, _) = await makePreviewLifecycleSession(
            drive: PreparationDriveTransportFixture(createOutcomes: []),
            identityStore: identityStore,
            oauthSession: FakeDriveOAuthSession()
        )
        XCTAssertNil(session.lastExportOfSelectedDay)
        XCTAssertNil(session.lastVerifiedExport(for: "2026-09-06"))

        // Account restored but no folder bound.
        _ = try await session.restoreGoogleSession()
        XCTAssertNil(session.lastExportOfSelectedDay)
    }

    @MainActor
    func testSignOutClearsTheLastExportLine() async throws {
        let (session, _, _) = try await restoredLastExportSession(identities: [
            lastExportIdentity(reportDate: "2026-09-06", verifiedAt: Date(timeIntervalSince1970: 1))
        ])
        XCTAssertNotNil(session.lastExportOfSelectedDay)

        session.signOut()

        XCTAssertNil(session.lastExportOfSelectedDay)
    }

    private var lastExportBinding: DailyDestinationBinding {
        DailyDestinationBinding(
            accountID: "invented-account",
            folderID: "folder-a",
            folderName: "Invented",
            origin: .picker
        )
    }

    @MainActor
    private func restoredLastExportSession(
        identities: [DailyDriveExportIdentity]
    ) async throws -> (DailyDriveSessionController, PreparationDriveTransportFixture, FakeDriveOAuthSession) {
        let store = MemoryDailySessionStore()
        try store.save(
            try JSONEncoder().encode(partitions(containing: lastExportBinding)),
            account: "google.drive.daily-export-destinations.v1"
        )
        let identityStore = ControllerMemoryDailyIdentityStore(registry: DailyDriveExportRegistry(
            installationID: "invented-installation",
            identities: identities
        ))
        let drive = PreparationDriveTransportFixture(createOutcomes: [])
        let oauth = FakeDriveOAuthSession()
        let (session, _) = await makePreviewLifecycleSession(
            drive: drive,
            secureStore: store,
            identityStore: identityStore,
            oauthSession: oauth
        )
        _ = try await session.restoreGoogleSession()
        return (session, drive, oauth)
    }

    private func lastExportIdentity(
        accountID: String = "invented-account",
        folderID: String = "folder-a",
        reportDate: String,
        verifiedAt: Date?,
        pending: PendingDailyDriveOperation? = nil
    ) -> DailyDriveExportIdentity {
        DailyDriveExportIdentity(
            accountID: accountID,
            folderID: folderID,
            reportDate: reportDate,
            fileID: "invented-file-\(accountID)-\(folderID)-\(reportDate)",
            installationID: "invented-installation",
            lastVerified: verifiedAt.map {
                VerifiedDailyDriveSnapshot(
                    dataAsOf: "2026-09-06T08:00:00+01:00",
                    payloadSHA256: "invented-hash",
                    verifiedAt: $0
                )
            },
            pending: pending
        )
    }

    @MainActor
    func testSessionKeepsAmbiguousIdentityRestorationFailClosedWithInjectedStore() async throws {
        let identityStore = ControllerMemoryDailyIdentityStore(loadFailure: ProbeError.queryFailed)
        let session = makePreparationSession(
            drive: PreparationDriveTransportFixture(createOutcomes: []),
            identityStore: identityStore,
            oauthSession: FakeDriveOAuthSession()
        )

        _ = try await session.restoreGoogleSession()

        XCTAssertEqual(
            session.lastVerifiedLabel,
            "Stored identity is ambiguous; explicit recovery required"
        )
        XCTAssertEqual(identityStore.loadCount, 1)
    }

    @MainActor
    func testSessionSignOutClearsCredentialsButPreservesDestinationPartitions() throws {
        let store = MemoryDailySessionStore()
        let binding = DailyDestinationBinding(
            accountID: "invented-account",
            folderID: "folder-a",
            folderName: "Invented",
            origin: .picker
        )
        try store.save(
            try JSONEncoder().encode(partitions(containing: binding)),
            account: "google.drive.daily-export-destinations.v1"
        )
        let oauth = FakeDriveOAuthSession()
        let session = makePreparationSession(
            drive: PreparationDriveTransportFixture(createOutcomes: []),
            secureStore: store,
            oauthSession: oauth
        )

        session.signOut()

        XCTAssertEqual(oauth.clearCount, 1)
        let saved = try XCTUnwrap(store.snapshot(account: "google.drive.daily-export-destinations.v1"))
        let restored = try JSONDecoder().decode(DailyDestinationPartitions.self, from: saved)
        XCTAssertEqual(restored.destination(for: binding.accountID), binding)
        XCTAssertEqual(session.presentationState, .needsGoogleConnection)
    }

    @MainActor
    func testSessionDisconnectClearsCredentialsOnlyAfterSuccessfulRevocation() async {
        let successfulOAuth = FakeDriveOAuthSession()
        let successful = makePreparationSession(
            drive: PreparationDriveTransportFixture(createOutcomes: [], revokeStatus: 200),
            oauthSession: successfulOAuth
        )
        await successful.disconnect()
        XCTAssertEqual(successfulOAuth.clearCount, 1)
        XCTAssertEqual(successful.presentationState, .needsGoogleConnection)

        let failedOAuth = FakeDriveOAuthSession()
        let failed = makePreparationSession(
            drive: PreparationDriveTransportFixture(createOutcomes: [], revokeStatus: 503),
            oauthSession: failedOAuth
        )
        await failed.disconnect()
        XCTAssertEqual(failedOAuth.clearCount, 0)
        XCTAssertTrue(failedOAuth.hasStoredSession)
    }

    @MainActor
    func testRestoredDestinationLossAndAccountChangeDoNotCreateOrAdoptAFolder() async throws {
        let store = MemoryDailySessionStore()
        let binding = DailyDestinationBinding(
            accountID: "invented-account",
            folderID: "missing-folder",
            folderName: "Invented",
            origin: .picker
        )
        try store.save(
            try JSONEncoder().encode(partitions(containing: binding)),
            account: "google.drive.daily-export-destinations.v1"
        )
        let drive = PreparationDriveTransportFixture(createOutcomes: [])
        let session = makePreparationSession(
            drive: drive,
            secureStore: store,
            oauthSession: FakeDriveOAuthSession()
        )
        let context = try await session.restoreGoogleSession()
        XCTAssertEqual(try session.storedDestination(for: context.account.id), binding)
        do {
            try await session.validateStoredDestination(binding, context: context)
            XCTFail("The missing saved folder must not be accepted")
        } catch DailyExportPreparationFailure.destinationMissingOrInaccessible {}

        await drive.setAccountID("other-account")
        let changed = try await session.restoreGoogleSession()
        XCTAssertEqual(changed.account.id, "other-account")
        XCTAssertNil(try session.storedDestination(for: changed.account.id))
        XCTAssertEqual(session.destinationLabel, "Choose or create a destination")
        let snapshot = await drive.snapshot()
        XCTAssertEqual(snapshot.generatedCount, 0)
        XCTAssertEqual(snapshot.uploadCount, 0)
        XCTAssertEqual(
            try JSONDecoder().decode(
                DailyDestinationPartitions.self,
                from: XCTUnwrap(store.snapshot(account: "google.drive.daily-export-destinations.v1"))
            ).destination(for: binding.accountID),
            binding
        )
    }

    @MainActor
    func testUncertainControllerUploadRetainsPreviewAndDisconnectDoesNotRetry() async throws {
        let store = MemoryDailySessionStore()
        let binding = DailyDestinationBinding(
            accountID: "invented-account",
            folderID: "invented-folder",
            folderName: "Invented",
            origin: .picker
        )
        try store.save(
            try JSONEncoder().encode(partitions(containing: binding)),
            account: "google.drive.daily-export-destinations.v1"
        )
        let drive = PreparationDriveTransportFixture(createOutcomes: [], revokeStatus: 503)
        let oauth = FakeDriveOAuthSession()
        let (session, _) = await makePreviewLifecycleSession(
            drive: drive,
            secureStore: store,
            oauthSession: oauth
        )
        let context = try await session.restoreGoogleSession()
        let preview = try XCTUnwrap(session.preview)
        XCTAssertEqual(try session.storedDestination(for: context.account.id), binding)

        await session.exportPreview()
        XCTAssertEqual(session.preview, preview)
        let afterExport = await drive.snapshot()
        XCTAssertEqual(afterExport.uploadCount, 2) // One immediate same-ID retry, never a queued retry.
        await session.disconnect()
        XCTAssertEqual(oauth.clearCount, 0)
        XCTAssertTrue(oauth.hasStoredSession)
        XCTAssertEqual(session.preview, preview)
        let afterDisconnect = await drive.snapshot()
        XCTAssertEqual(afterDisconnect.uploadCount, afterExport.uploadCount)
    }

    @MainActor
    func testSessionAuthorizationErrorInvalidatesPreviewAndRequiresConnection() {
        let oauth = FakeDriveOAuthSession()
        let session = makePreparationSession(
            drive: PreparationDriveTransportFixture(createOutcomes: []),
            oauthSession: oauth
        )

        oauth.onAuthorizationError?(.revoked)

        XCTAssertNil(session.preview)
        XCTAssertEqual(session.presentationState, .needsGoogleConnection)
        XCTAssertTrue(session.status.contains("revoked"))
    }

    @MainActor
    func testPreparationRestoresOnlyExactSavedNutritionSource() async {
        let missing = PreparationDriverFixture(savedBundleIdentifier: nil)
        missing.destination = missing.fixtureDestination
        let missingState = await DailyExportPreparationOrchestrator().prepare(using: missing)
        XCTAssertEqual(missingState, .needsNutritionSource)
        XCTAssertEqual(missing.resolveCount, 0)
        XCTAssertEqual(missing.refreshCount, 0)

        let unavailable = PreparationDriverFixture(savedBundleIdentifier: "invented.missing")
        unavailable.destination = unavailable.fixtureDestination
        unavailable.resolveFailure = .nutritionSourceUnavailable
        let unavailableState = await DailyExportPreparationOrchestrator()
            .prepare(using: unavailable)
        XCTAssertEqual(unavailableState, .needsAttention(.nutritionSourceUnavailable))
        XCTAssertEqual(unavailable.resolvedBundleIdentifiers, ["invented.missing"])
        XCTAssertEqual(unavailable.refreshCount, 0)
    }

    @MainActor
    func testRepeatedConcurrentPreparationIsSerialAndDoesNotDuplicateFolderOrUpload() async {
        let driver = PreparationDriverFixture()
        driver.destination = driver.fixtureDestination
        driver.suspendRestore = true
        let orchestrator = DailyExportPreparationOrchestrator()
        let first = Task { @MainActor in await orchestrator.prepare(using: driver) }
        for _ in 0..<100 where !driver.restoreIsSuspended {
            await Task.yield()
        }
        XCTAssertTrue(driver.restoreIsSuspended)

        let overlapping = await orchestrator.prepare(using: driver)
        XCTAssertEqual(overlapping, .preparing)
        XCTAssertEqual(driver.restoreCount, 1)
        driver.resumeRestore()
        let completed = await first.value

        XCTAssertEqual(completed, .readyToExport)
        XCTAssertEqual(driver.createCount, 0)
        XCTAssertEqual(driver.refreshCount, 1)
        XCTAssertEqual(driver.uploadCount, 0)
    }

    @MainActor
    func testAutomaticPreparationRejectsNoteMutationDuringRefresh() async {
        let driver = PreparationDriverFixture()
        driver.destination = driver.fixtureDestination
        driver.refreshFailure = .notesChanged

        let state = await DailyExportPreparationOrchestrator().prepare(using: driver)

        XCTAssertEqual(state, .needsAttention(.notesChanged))
        XCTAssertEqual(driver.refreshCount, 1)
        XCTAssertEqual(driver.uploadCount, 0)
    }

    func testPresentationActionsKeepRoutineAndRecoveryControlsContextual() {
        let ready = DailyExportPresentationState.readyToExport.actions
        XCTAssertTrue(ready.contains(.export))
        XCTAssertTrue(ready.contains(.refreshPreview))
        XCTAssertTrue(ready.contains(.inspectExactJSON))
        XCTAssertTrue(ready.contains(.manageAccount))
        XCTAssertFalse(ready.contains(.connect))
        XCTAssertTrue(ready.contains(.recoverCanonicalFile))
        XCTAssertFalse(ready.contains(.forgetTrashedDestination))

        XCTAssertEqual(DailyExportPresentationState.needsGoogleConnection.actions, [.connect])
        XCTAssertEqual(
            DailyExportPresentationState.needsAttention(.destinationRequired).actions,
            [.createDestination, .chooseDestination, .manageAccount]
        )
        XCTAssertTrue(
            DailyExportPresentationState.needsAttention(.destinationTrashed).actions
                .contains(.forgetTrashedDestination)
        )
        XCTAssertFalse(
            DailyExportPresentationState.needsAttention(.destinationTrashed).actions
                .contains(.chooseDestination)
        )
        XCTAssertTrue(
            DailyExportPresentationState.needsAttention(.canonicalRecovery).actions
                .contains(.recoverCanonicalFile)
        )
    }

    func testStatusCatalogueProvidesOneNonEmptyStatusForEveryAttention() {
        let attentions: [DailyExportAttention] = [
            .configurationUnavailable,
            .googleUnavailable,
            .destinationRequired,
            .destinationMissingOrInaccessible,
            .destinationTrashed,
            .destinationSetupFailed,
            .nutritionSourceUnavailable,
            .healthDataUnavailable,
            .notesUnavailable,
            .notesChanged,
            .canonicalRecovery,
            .unexpected
        ]

        for attention in attentions {
            let status = DailyExportStatusCatalogue.status(
                for: .needsAttention(attention),
                hasStoredSession: false
            )
            XCTAssertFalse(status.isEmpty, "Missing status for \(attention)")
        }
    }

    func testStatusCatalogueUsesExplicitStoredSessionAvailability() {
        XCTAssertEqual(
            DailyExportStatusCatalogue.status(
                for: .needsGoogleConnection,
                hasStoredSession: false
            ),
            "Connect Google to continue. No Health or Drive request ran."
        )
        XCTAssertEqual(
            DailyExportStatusCatalogue.status(
                for: .needsGoogleConnection,
                hasStoredSession: true
            ),
            "The stored Google session needs fresh consent before export can continue."
        )
    }

    func testPreparationFailuresResolveThroughSharedAttentionStatuses() throws {
        let cases: [(DailyExportPreparationFailure, DailyExportPresentationState)] = [
            (.freshGoogleConsentRequired, .needsGoogleConnection),
            (.googleUnavailable, .needsAttention(.googleUnavailable)),
            (.destinationRequired, .needsAttention(.destinationRequired)),
            (
                .destinationMissingOrInaccessible,
                .needsAttention(.destinationMissingOrInaccessible)
            ),
            (.destinationTrashed, .needsAttention(.destinationTrashed)),
            (.destinationSetupFailed, .needsAttention(.destinationSetupFailed)),
            (
                .nutritionSourceUnavailable,
                .needsAttention(.nutritionSourceUnavailable)
            ),
            (.healthDataUnavailable, .needsAttention(.healthDataUnavailable)),
            (.notesUnavailable, .needsAttention(.notesUnavailable)),
            (.notesChanged, .needsAttention(.notesChanged))
        ]

        for (failure, expectedState) in cases {
            let resolution = DailyExportStatusCatalogue.resolve(failure)
            let state = try XCTUnwrap(resolution.presentationState)
            XCTAssertEqual(state, expectedState)
            XCTAssertNil(resolution.statusOverride)

            let runStatus = resolution.statusOverride ?? DailyExportStatusCatalogue.status(
                for: state,
                hasStoredSession: true
            )
            let presentationStatus = DailyExportStatusCatalogue.status(
                for: expectedState,
                hasStoredSession: true
            )
            XCTAssertEqual(runStatus, presentationStatus)
        }
    }

    func testFailureResolutionPreservesPreviewInvalidationAndFailsClosed() throws {
        for failure in [
            DailyExportPreparationFailure.nutritionSourceUnavailable,
            .notesUnavailable,
            .notesChanged
        ] {
            XCTAssertTrue(DailyExportStatusCatalogue.resolve(failure).invalidatesPreview)
        }

        let resolution = DailyExportStatusCatalogue.resolve(ProbeError.queryFailed)
        XCTAssertEqual(
            try XCTUnwrap(resolution.presentationState),
            .needsAttention(.unexpected)
        )
        XCTAssertNil(resolution.statusOverride)
        XCTAssertFalse(resolution.invalidatesPreview)
        XCTAssertEqual(
            DailyExportStatusCatalogue.status(
                for: .needsAttention(.unexpected),
                hasStoredSession: false
            ),
            "Operation failed. No background retry was queued."
        )
    }

    func testFailureResolutionPreservesTypedSafetyDetail() throws {
        let policy = DailyExportStatusCatalogue.resolve(
            DailyDriveConsentPolicy.Failure.trashed
        )
        XCTAssertEqual(
            try XCTUnwrap(policy.presentationState),
            .needsAttention(.destinationTrashed)
        )
        XCTAssertEqual(
            policy.statusOverride,
            "Rejected by consent/destination policy: the folder is trashed."
        )

        let credentials = DailyExportStatusCatalogue.resolve(
            DailyDriveExportFailure.credentials(.revoked)
        )
        XCTAssertEqual(
            try XCTUnwrap(credentials.presentationState),
            .needsGoogleConnection
        )
        XCTAssertEqual(
            credentials.statusOverride,
            "Google credentials are revoked. Reconnect before exporting."
        )

        let canonicalRecovery = DailyExportStatusCatalogue.resolve(
            DailyDriveExportFailure.remoteMissing
        )
        XCTAssertEqual(
            try XCTUnwrap(canonicalRecovery.presentationState),
            .needsAttention(.canonicalRecovery)
        )
        XCTAssertTrue(canonicalRecovery.statusOverride?.contains("explicit override") == true)

        let sourceRequired = DailyExportStatusCatalogue.resolve(
            DailyHealthExportError.nutritionSourceRequired
        )
        XCTAssertEqual(
            try XCTUnwrap(sourceRequired.presentationState),
            .needsNutritionSource
        )
        XCTAssertEqual(
            sourceRequired.statusOverride,
            "Choose a visible nutrition source before refreshing the preview."
        )
    }

    func testConsolidatedAttentionWordingRetainsExistingAssurances() {
        XCTAssertEqual(
            DailyExportStatusCatalogue.status(
                for: .needsAttention(.configurationUnavailable),
                hasStoredSession: false
            ),
            "Google Drive export is not set up in this version of the app, so nothing can be sent."
        )
        XCTAssertEqual(
            DailyExportStatusCatalogue.status(
                for: .needsAttention(.nutritionSourceUnavailable),
                hasStoredSession: false
            ),
            "The selected nutrition source is unavailable. Refresh sources and choose again; no unfiltered nutrition was used."
        )
    }

    @MainActor
    private func makePreparationSession(
        drive: any DailyDriveSessionTransporting,
        secureStore: any DailyDriveSecurePersisting = MemoryDailySessionStore(),
        identityStore: any DailyDriveExportIdentityPersisting = ControllerMemoryDailyIdentityStore(),
        oauthSession: (any DriveOAuthSessionProviding)? = nil
    ) -> DailyDriveSessionController {
        let notesStore = MutableDailyNotesStore()
        return DailyDriveSessionController(
            keychain: secureStore,
            drive: drive,
            exportService: DailyHealthExportService(
                healthData: RecordingDailyProvider { _ in
                    fatalError("Folder preparation must not query HealthKit")
                },
                notesStore: notesStore
            ),
            identityStore: identityStore,
            nutritionSourceSelection: FixedNutritionSourceSelection(bundleIdentifier: nil),
            notes: DailyNotesController(store: notesStore),
            oauthSession: oauthSession
        )
    }

    private func partitions(
        containing binding: DailyDestinationBinding
    ) -> DailyDestinationPartitions {
        var partitions = DailyDestinationPartitions()
        partitions.bind(binding)
        return partitions
    }

    @MainActor
    private func makePreviewLifecycleSession(
        drive: any DailyDriveSessionTransporting = DailyDriveAPI(),
        secureStore: any DailyDriveSecurePersisting = MemoryDailySessionStore(),
        identityStore: any DailyDriveExportIdentityPersisting = ControllerMemoryDailyIdentityStore(),
        oauthSession: (any DriveOAuthSessionProviding)? = nil
    ) async -> (
        session: DailyDriveSessionController,
        notesStore: MutableDailyNotesStore
    ) {
        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 8, calendar: calendar)
        let notesStore = MutableDailyNotesStore()
        let notes = DailyNotesController(
            store: notesStore,
            calendar: calendar,
            now: { cutoff }
        )
        let provider = RecordingDailyProvider { self.emptyInputs(window: $0) }
        let session = DailyDriveSessionController(
            keychain: secureStore,
            drive: drive,
            exportService: DailyHealthExportService(
                healthData: provider,
                notesStore: notesStore,
                calendar: calendar,
                now: { cutoff }
            ),
            identityStore: identityStore,
            nutritionSourceSelection: FixedNutritionSourceSelection(
                bundleIdentifier: fixtureNutritionSource.bundleIdentifier
            ),
            notes: notes,
            oauthSession: oauthSession
        )
        await session.refreshPreview()
        return (session, notesStore)
    }

    private func londonCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func identity(
        accountID: String,
        folderID: String,
        dataAsOf: String,
        verifiedAt: Date
    ) -> DailyDriveExportIdentity {
        DailyDriveExportIdentity(
            accountID: accountID,
            folderID: folderID,
            reportDate: "2026-09-15",
            fileID: "invented-file-\(dataAsOf)",
            installationID: "invented-installation",
            lastVerified: VerifiedDailyDriveSnapshot(
                dataAsOf: dataAsOf,
                payloadSHA256: "invented-hash",
                verifiedAt: verifiedAt
            ),
            pending: nil
        )
    }

    private func withoutNotesAndNutrition(
        _ envelope: DailyHealthExportEnvelope
    ) -> DailyHealthExportEnvelope {
        let today = envelope.today
        let appContext = envelope.appContext
        return DailyHealthExportEnvelope(
            schemaVersion: envelope.schemaVersion,
            reportDate: envelope.reportDate,
            timeZone: envelope.timeZone,
            dataAsOf: envelope.dataAsOf,
            exportedAt: envelope.exportedAt,
            dayWindow: envelope.dayWindow,
            today: DailyHealthMetrics(
                notes: nil,
                weight: today.weight,
                bodyFat: today.bodyFat,
                waist: today.waist,
                bloodPressure: today.bloodPressure,
                glucose: today.glucose,
                restingHeartRate: today.restingHeartRate,
                hrv: today.hrv,
                bloodOxygen: today.bloodOxygen,
                vo2Max: today.vo2Max,
                sleep: today.sleep,
                activity: today.activity,
                workouts: today.workouts,
                watchCoverage: today.watchCoverage,
                medications: today.medications,
                nutrition: nil
            ),
            appContext: DailyAppContext(
                policyID: appContext.policyID,
                window: appContext.window,
                weight: appContext.weight,
                bodyFat: appContext.bodyFat,
                waist: appContext.waist,
                glucose: appContext.glucose,
                vo2Max: appContext.vo2Max,
                bloodOxygen: appContext.bloodOxygen,
                bloodPressure: appContext.bloodPressure,
                steps: appContext.steps,
                restingHeartRate: appContext.restingHeartRate,
                hrv: appContext.hrv,
                watchCoverage: appContext.watchCoverage,
                sleep: appContext.sleep,
                activeEnergy: appContext.activeEnergy,
                exercise: appContext.exercise,
                workouts: appContext.workouts,
                medications: appContext.medications,
                nutrition: nil
            )
        )
    }

    private func assertGolden(
        _ bytes: Data,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actual = try XCTUnwrap(String(data: bytes, encoding: .utf8), file: file, line: line)
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func pressure(
        _ suffix: UInt8,
        at date: Date,
        _ systolic: Double,
        _ diastolic: Double
    ) -> BloodPressureReading {
        return BloodPressureReading(
            id: UUID(uuidString: String(
                format: "00000000-0000-0000-0000-0000000000%02X",
                suffix
            ))!,
            date: date,
            systolicMillimetresOfMercury: systolic,
            diastolicMillimetresOfMercury: diastolic,
            sourceName: "Invented monitor"
        )
    }

    private func glucose(
        _ interval: DateInterval,
        average: Double? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> DailyGlucoseValue {
        DailyGlucoseValue(
            day: interval,
            averageMillimolesPerLiter: average,
            minimumMillimolesPerLiter: minimum,
            maximumMillimolesPerLiter: maximum,
            sourceNames: average == nil ? [] : ["Invented sensor"]
        )
    }

    private func historicalWeights(window: DailyExportWindow) -> [WeightMeasurement] {
        (1...10).map { offset in
            WeightMeasurement(
                date: window.calendar.date(
                    byAdding: .day,
                    value: -offset,
                    to: window.day.start
                )!.addingTimeInterval(8 * 3_600),
                kilograms: 80 + Double(offset) / 10
            )
        }
    }

    private func emptyInputs(window: DailyExportWindow, workouts: [WorkoutRecord] = []) -> DailyHealthExportInputs {
        let emptyTodayHeart = DailyHeartMetricValue(
            day: window.day,
            value: nil,
            sourceNames: []
        )
        let contextHearts = window.context.completedDays.map {
            DailyHeartMetricValue(day: $0, value: nil, sourceNames: [])
        }
        let previous = window.context.precedingEquivalent(calendar: window.calendar)!
        let previousHearts = previous.completedDays.map {
            DailyHeartMetricValue(day: $0, value: nil, sourceNames: [])
        }
        return DailyHealthExportInputs(
            weight: [],
            bodyFat: [],
            waist: [],
            vo2Max: [],
            bloodOxygen: [],
            bloodPressure: [],
            todaySteps: DailyStepTotal(day: window.day, steps: nil, sourceNames: []),
            todayGlucose: glucose(window.day),
            hourlyGlucose: window.glucoseHours.map { glucose($0) },
            todayRestingHeartRate: emptyTodayHeart,
            todayHRV: emptyTodayHeart,
            todayWatchSampleDates: [],
            todayActiveEnergyKilocalories: nil,
            todayExerciseMinutes: nil,
            todayWorkouts: workouts,
            todayAsleepIntervals: [],
            todayMedicationDoses: [],
            supportsMedicationData: true,
            contextSteps: window.context.completedDays.map {
                DailyStepTotal(day: $0, steps: nil, sourceNames: [])
            },
            contextGlucose: window.context.completedDays.map { glucose($0) },
            contextRestingHeartRate: contextHearts,
            previousRestingHeartRate: previousHearts,
            contextHRV: contextHearts,
            previousHRV: previousHearts,
            contextWatchSampleDates: [],
            contextActiveEnergyKilocalories: nil,
            contextExerciseMinutes: nil,
            contextWorkouts: [],
            contextAsleepIntervals: [],
            contextMedicationDoses: [],
            nutrition: emptyNutrition(window: window)
        )
    }

    private func populatedInputs(window: DailyExportWindow) -> DailyHealthExportInputs {
        let calendar = window.calendar
        func day(_ offset: Int, hour: Int = 8) -> Date {
            calendar.date(byAdding: .day, value: -offset, to: window.day.start)!
                .addingTimeInterval(Double(hour) * 3_600)
        }
        let weights = (0...14).map {
            WeightMeasurement(date: day($0), kilograms: 80 + Double($0) / 10)
        }
        let bodyFat = [
            BodyFatMeasurement(date: day(1), percentage: 20),
            BodyFatMeasurement(date: day(2), percentage: 22),
            BodyFatMeasurement(date: day(30), percentage: 24),
            BodyFatMeasurement(date: day(40), percentage: 26)
        ]
        let waist = [
            WaistMeasurement(date: day(0), centimetres: 90),
            WaistMeasurement(date: day(28), centimetres: 92)
        ]
        let vo2 = [1, 10, 20, 100].map {
            VO2MaxMeasurement(
                date: day($0),
                millilitresPerKilogramMinute: 40 + Double($0) / 100,
                sourceName: "Invented Watch"
            )
        }
        let oxygen = [0, 1, 2].map {
            OxygenSaturationMeasurement(
                date: day($0),
                percentage: 96 + Double($0),
                sourceName: "Invented Watch"
            )
        }
        let pressures = [
            pressure(10, at: day(0), 121, 81),
            pressure(11, at: day(1), 120, 80),
            pressure(12, at: day(2, hour: 18), 130, 85)
        ]
        let contextSteps = window.context.completedDays.enumerated().map { index, interval in
            DailyStepTotal(
                day: interval,
                steps: 1_000 + Double(index),
                sourceNames: ["Invented resolver"]
            )
        }
        let contextGlucose = window.context.completedDays.enumerated().map { index, interval in
            glucose(
                interval,
                average: 5 + Double(index) / 10,
                minimum: 4,
                maximum: 7
            )
        }
        let contextHeart = window.context.completedDays.enumerated().map { index, interval in
            DailyHeartMetricValue(
                day: interval,
                value: 60 + Double(index),
                sourceNames: ["Invented Watch"]
            )
        }
        let previous = window.context.precedingEquivalent(calendar: calendar)!
        let previousHeart = previous.completedDays.enumerated().map { index, interval in
            DailyHeartMetricValue(
                day: interval,
                value: 58 + Double(index),
                sourceNames: ["Invented Watch"]
            )
        }
        let sleeps = window.context.completedDays.map { interval in
            AsleepInterval(
                start: calendar.date(byAdding: .hour, value: -1, to: interval.start)!,
                end: calendar.date(byAdding: .hour, value: 7, to: interval.start)!
            )
        }
        let medication = MedicationDoseRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            medicationKey: "invented-medication",
            medicationName: "Invented medicine",
            date: day(1),
            quantity: 1,
            unitLabel: "dose"
        )
        let workout = WorkoutRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000088")!,
            startDate: day(1),
            duration: 1_800,
            activityName: "Invented workout"
        )
        return DailyHealthExportInputs(
            weight: weights,
            bodyFat: bodyFat,
            waist: waist,
            vo2Max: vo2,
            bloodOxygen: oxygen,
            bloodPressure: pressures,
            todaySteps: DailyStepTotal(day: window.day, steps: 2_000, sourceNames: []),
            todayGlucose: glucose(window.day, average: 5.4, minimum: 4, maximum: 7),
            hourlyGlucose: window.glucoseHours.map { glucose($0) },
            todayRestingHeartRate: DailyHeartMetricValue(
                day: window.day,
                value: 61,
                sourceNames: []
            ),
            todayHRV: DailyHeartMetricValue(day: window.day, value: 42, sourceNames: []),
            todayWatchSampleDates: [day(0)],
            todayActiveEnergyKilocalories: 500,
            todayExerciseMinutes: 45,
            todayWorkouts: [],
            todayAsleepIntervals: [],
            todayMedicationDoses: [],
            supportsMedicationData: true,
            contextSteps: contextSteps,
            contextGlucose: contextGlucose,
            contextRestingHeartRate: contextHeart,
            previousRestingHeartRate: previousHeart,
            contextHRV: contextHeart,
            previousHRV: previousHeart,
            contextWatchSampleDates: [day(1), day(2)],
            contextActiveEnergyKilocalories: 3_500,
            contextExerciseMinutes: 210,
            contextWorkouts: [workout],
            contextAsleepIntervals: sleeps,
            contextMedicationDoses: [medication],
            nutrition: emptyNutrition(window: window)
        )
    }

    private func replacing(
        _ value: DailyHealthExportInputs,
        weight: [WeightMeasurement]? = nil,
        bodyFat: [BodyFatMeasurement]? = nil,
        bloodOxygen: [OxygenSaturationMeasurement]? = nil,
        bloodPressure: [BloodPressureReading]? = nil,
        todayGlucose: DailyGlucoseValue? = nil,
        hourlyGlucose: [DailyGlucoseValue]? = nil,
        todaySteps: DailyStepTotal? = nil,
        contextSteps: [DailyStepTotal]? = nil,
        contextGlucose: [DailyGlucoseValue]? = nil,
        contextRestingHeartRate: [DailyHeartMetricValue]? = nil,
        previousRestingHeartRate: [DailyHeartMetricValue]? = nil,
        contextHRV: [DailyHeartMetricValue]? = nil,
        previousHRV: [DailyHeartMetricValue]? = nil,
        supportsMedicationData: Bool? = nil,
        nutrition: NutritionExportInput? = nil
    ) -> DailyHealthExportInputs {
        DailyHealthExportInputs(
            weight: weight ?? value.weight,
            bodyFat: bodyFat ?? value.bodyFat,
            waist: value.waist,
            vo2Max: value.vo2Max,
            bloodOxygen: bloodOxygen ?? value.bloodOxygen,
            bloodPressure: bloodPressure ?? value.bloodPressure,
            todaySteps: todaySteps ?? value.todaySteps,
            todayGlucose: todayGlucose ?? value.todayGlucose,
            hourlyGlucose: hourlyGlucose ?? value.hourlyGlucose,
            todayRestingHeartRate: value.todayRestingHeartRate,
            todayHRV: value.todayHRV,
            todayWatchSampleDates: value.todayWatchSampleDates,
            todayActiveEnergyKilocalories: value.todayActiveEnergyKilocalories,
            todayExerciseMinutes: value.todayExerciseMinutes,
            todayWorkouts: value.todayWorkouts,
            todayAsleepIntervals: value.todayAsleepIntervals,
            todayMedicationDoses: value.todayMedicationDoses,
            supportsMedicationData: supportsMedicationData ?? value.supportsMedicationData,
            contextSteps: contextSteps ?? value.contextSteps,
            contextGlucose: contextGlucose ?? value.contextGlucose,
            contextRestingHeartRate: contextRestingHeartRate ?? value.contextRestingHeartRate,
            previousRestingHeartRate: previousRestingHeartRate ?? value.previousRestingHeartRate,
            contextHRV: contextHRV ?? value.contextHRV,
            previousHRV: previousHRV ?? value.previousHRV,
            contextWatchSampleDates: value.contextWatchSampleDates,
            contextActiveEnergyKilocalories: value.contextActiveEnergyKilocalories,
            contextExerciseMinutes: value.contextExerciseMinutes,
            contextWorkouts: value.contextWorkouts,
            contextAsleepIntervals: value.contextAsleepIntervals,
            contextMedicationDoses: value.contextMedicationDoses,
            nutrition: nutrition ?? value.nutrition
        )
    }

    private var fixtureNutritionSource: NutritionSource {
        NutritionSource(
            bundleIdentifier: "example.fixture.nutrition",
            name: "Invented Nutrition Source"
        )
    }

    private func emptyNutrition(window: DailyExportWindow) -> NutritionExportInput {
        let previous = window.context.precedingEquivalent(calendar: window.calendar)!
        return NutritionExportInput(
            source: fixtureNutritionSource,
            nutrients: NutritionCatalogue.all.map { definition in
                NutritionNutrientTotals(
                    key: definition.key,
                    today: nil,
                    currentDays: window.context.completedDays.map {
                        NutritionDailyTotal(day: $0.start, value: nil)
                    },
                    previousDays: previous.completedDays.map {
                        NutritionDailyTotal(day: $0.start, value: nil)
                    }
                )
            }
        )
    }

    private func nutrition(
        window: DailyExportWindow,
        key: String,
        today: Double?,
        current: [Double?],
        previous: [Double?],
        source: NutritionSource? = nil
    ) -> NutritionExportInput {
        precondition(current.count == 7 && previous.count == 7)
        let previousPeriod = window.context.precedingEquivalent(calendar: window.calendar)!
        return NutritionExportInput(
            source: source ?? fixtureNutritionSource,
            nutrients: NutritionCatalogue.all.map { definition in
                let isSelected = definition.key == key
                return NutritionNutrientTotals(
                    key: definition.key,
                    today: isSelected ? today : nil,
                    currentDays: zip(window.context.completedDays, current).map {
                        NutritionDailyTotal(
                            day: $0.0.start,
                            value: isSelected ? $0.1 : nil
                        )
                    },
                    previousDays: zip(previousPeriod.completedDays, previous).map {
                        NutritionDailyTotal(
                            day: $0.0.start,
                            value: isSelected ? $0.1 : nil
                        )
                    }
                )
            }
        )
    }
}

@MainActor
private final class PreparationDriverFixture: DailyExportPreparationDriving {
    let account = DailyDriveAccount(
        id: "invented-account",
        displayName: "Invented Account",
        emailAddress: "invented@example.invalid"
    )
    let savedBundleIdentifier: String
    let fixtureDestination = DailyDestinationBinding(
        accountID: "invented-account",
        folderID: "invented-folder",
        folderName: "WeeklyHealthReport Exports",
        origin: .created
    )

    var hasStoredGoogleSession: Bool
    var storedNutritionSourceBundleIdentifier: String?
    var destination: DailyDestinationBinding?
    var destinationLookupFailure: DailyExportPreparationFailure?
    var restoreFailure: DailyExportPreparationFailure?
    var validationFailure: DailyExportPreparationFailure?
    var creationFailure: DailyExportPreparationFailure?
    var resolveFailure: DailyExportPreparationFailure?
    var refreshFailure: DailyExportPreparationFailure?
    var suspendRestore = false
    private(set) var restoreIsSuspended = false
    private var restoreContinuation: CheckedContinuation<Void, Never>?

    private(set) var restoreCount = 0
    private(set) var validateCount = 0
    private(set) var createCount = 0
    private(set) var resolveCount = 0
    private(set) var refreshCount = 0
    private(set) var authorizationRequestCount = 0
    private(set) var uploadCount = 0
    private(set) var resolvedBundleIdentifiers: [String] = []
    private(set) var refreshedBundleIdentifiers: [String] = []

    init(
        hasStoredGoogleSession: Bool = true,
        savedBundleIdentifier: String? = "invented.nutrition"
    ) {
        self.hasStoredGoogleSession = hasStoredGoogleSession
        storedNutritionSourceBundleIdentifier = savedBundleIdentifier
        self.savedBundleIdentifier = savedBundleIdentifier ?? ""
    }

    func restoreGoogleSession() async throws -> DailyExportGoogleContext {
        restoreCount += 1
        if suspendRestore {
            restoreIsSuspended = true
            await withCheckedContinuation { continuation in
                restoreContinuation = continuation
            }
            restoreIsSuspended = false
        }
        if let restoreFailure { throw restoreFailure }
        return DailyExportGoogleContext(account: account, accessToken: "invented-token")
    }

    func storedDestination(for accountID: String) throws -> DailyDestinationBinding? {
        if let destinationLookupFailure { throw destinationLookupFailure }
        guard accountID == account.id else { return nil }
        return destination
    }

    func validateStoredDestination(
        _ binding: DailyDestinationBinding,
        context: DailyExportGoogleContext
    ) async throws {
        validateCount += 1
        if let validationFailure { throw validationFailure }
    }

    func createDefaultDestination(context: DailyExportGoogleContext) async throws {
        createCount += 1
        if let creationFailure { throw creationFailure }
        destination = fixtureDestination
    }

    func resolveNutritionSourceWithoutAuthorization(bundleIdentifier: String) async throws {
        resolveCount += 1
        resolvedBundleIdentifiers.append(bundleIdentifier)
        if let resolveFailure { throw resolveFailure }
    }

    func refreshPreviewWithoutAuthorization(bundleIdentifier: String) async throws {
        refreshCount += 1
        refreshedBundleIdentifiers.append(bundleIdentifier)
        if let refreshFailure { throw refreshFailure }
    }

    func resumeRestore() {
        restoreContinuation?.resume()
        restoreContinuation = nil
    }
}

private final class MemoryDailySessionStore: DailyDriveSecurePersisting, @unchecked Sendable {
    private var values: [String: Data] = [:]
    var failSaves = false
    private(set) var savedAccounts: [String] = []

    func save(_ data: Data, account: String) throws {
        if failSaves { throw ProbeError.queryFailed }
        values[account] = data
        savedAccounts.append(account)
    }

    func load(account: String) throws -> Data? {
        values[account]
    }

    func delete(account: String) throws {
        values.removeValue(forKey: account)
    }

    func snapshot(account: String) -> Data? {
        values[account]
    }
}

final class ControllerMemoryDailyIdentityStore: DailyDriveExportIdentityPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var registry: DailyDriveExportRegistry?
    private var marker: String?
    private let loadFailure: Error?
    private(set) var loadCount = 0

    init(
        registry: DailyDriveExportRegistry? = nil,
        loadFailure: Error? = nil
    ) {
        self.registry = registry
        marker = registry?.installationID
        self.loadFailure = loadFailure
    }

    func load() throws -> DailyDriveExportRegistry? {
        try lock.withLock {
            loadCount += 1
            if let loadFailure { throw loadFailure }
            return registry
        }
    }

    func installationMarker() throws -> String? {
        lock.withLock { marker }
    }

    func save(_ registry: DailyDriveExportRegistry) throws {
        lock.withLock {
            marker = registry.installationID
            self.registry = registry
        }
    }
}

private actor PreparationDriveTransportFixture: DailyDriveSessionTransporting {
    enum CreateOutcome: Sendable {
        case success
        case transientBeforeCommit
        case transientAfterCommit
    }

    struct Snapshot: Sendable {
        let generatedCount: Int
        let createIDs: [String]
        let folderReadCount: Int
        let folderCount: Int
        let uploadCount: Int
        var accountCount = 0
        var revokeCount = 0
    }

    private var accountValue = DailyDriveAccount(
        id: "invented-account",
        displayName: "Invented Account",
        emailAddress: "invented@example.invalid"
    )
    private var createOutcomes: [CreateOutcome]
    private var folders: [String: DailyDriveFolder] = [:]
    private var generatedCount = 0
    private var createIDs: [String] = []
    private var folderReadCount = 0
    private var uploadCount = 0
    private var accountCount = 0
    private var revokeCount = 0
    private let revokeStatus: Int
    private let fileOutcome: FileOutcome

    /// How daily-file uploads behave. `.uncertain` is the original behaviour.
    enum FileOutcome: Sendable {
        case uncertain
        case notFound
        case acceptedThenTrashed
    }

    init(createOutcomes: [CreateOutcome], revokeStatus: Int = 200, fileOutcome: FileOutcome = .uncertain) {
        self.createOutcomes = createOutcomes
        self.revokeStatus = revokeStatus
        self.fileOutcome = fileOutcome
    }

    func fixtureAccount() -> DailyDriveAccount { accountValue }

    func setAccountID(_ id: String) {
        accountValue = DailyDriveAccount(
            id: id,
            displayName: "Invented Account",
            emailAddress: "invented@example.invalid"
        )
    }

    func seedFolder(_ folder: DailyDriveFolder) {
        folders[folder.id] = folder
    }

    func snapshot() -> Snapshot {
        Snapshot(
            generatedCount: generatedCount,
            createIDs: createIDs,
            folderReadCount: folderReadCount,
            folderCount: folders.count,
            uploadCount: uploadCount,
            accountCount: accountCount,
            revokeCount: revokeCount
        )
    }

    func account(accessToken: String) async throws -> DailyDriveAccount {
        accountCount += 1
        return accountValue
    }

    func generateFileID(accessToken: String) async throws -> String {
        generatedCount += 1
        return "reserved-folder-\(generatedCount)"
    }

    func createFolder(
        id: String,
        accessToken: String,
        accountID: String
    ) async throws -> DailyDriveFolder {
        createIDs.append(id)
        let folder = DailyDriveFolder(
            id: id,
            accountID: accountID,
            name: "WeeklyHealthReport Exports",
            mimeType: DailyDriveConsentPolicy.folderMIMEType,
            trashed: false,
            driveID: nil,
            isAppAuthorized: true,
            canAddChildren: true
        )
        let outcome = createOutcomes.isEmpty ? .success : createOutcomes.removeFirst()
        switch outcome {
        case .success:
            folders[id] = folder
            return folder
        case .transientBeforeCommit:
            throw URLError(.timedOut)
        case .transientAfterCommit:
            folders[id] = folder
            throw URLError(.networkConnectionLost)
        }
    }

    func folder(
        id: String,
        accessToken: String,
        accountID: String
    ) async throws -> DailyDriveFolder {
        folderReadCount += 1
        guard let folder = folders[id] else {
            throw DailyDriveAPI.Failure.httpStatus(404, nil)
        }
        return folder
    }

    func revoke(token: String) async throws -> Int {
        revokeCount += 1
        return revokeStatus
    }

    func createFile(
        _ descriptor: DailyDriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws {
        uploadCount += 1
        switch fileOutcome {
        case .uncertain: throw URLError(.unsupportedURL)
        case .notFound: throw DailyDriveAPI.Failure.httpStatus(404, nil)
        case .acceptedThenTrashed: return
        }
    }

    func updateFile(
        _ descriptor: DailyDriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws {
        uploadCount += 1
        throw URLError(.unsupportedURL)
    }

    func fileMetadata(
        id: String,
        accessToken: String
    ) async throws -> DailyDriveFileMetadata {
        guard fileOutcome == .acceptedThenTrashed else {
            throw DailyDriveAPI.Failure.httpStatus(404, nil)
        }
        return DailyDriveFileMetadata(
            id: id,
            name: "invented.json",
            mimeType: "application/json",
            parents: ["invented-folder"],
            trashed: true,
            driveID: nil,
            isAppAuthorized: true,
            canEdit: true,
            appProperties: [:]
        )
    }

    func fileContent(id: String, accessToken: String) async throws -> Data {
        guard fileOutcome == .acceptedThenTrashed else {
            throw DailyDriveAPI.Failure.httpStatus(404, nil)
        }
        return Data()
    }
}

@MainActor
private final class FakeDriveOAuthSession: DriveOAuthSessionProviding {
    var hasStoredSession = true
    var revocationToken: String? = "invented-revocation-token"
    var onAuthorizationError: (@MainActor (DailyDriveCredentialFailure) -> Void)?
    var accessTokenFailure: DailyDriveCredentialFailure?
    private(set) var clearCount = 0
    private(set) var authorizeCount = 0
    private(set) var accessTokenCount = 0

    func restoreWithoutNetwork() throws {}

    func authorize(
        _ request: DriveAuthorizationRequest,
        configuration: DriveOAuthClientConfiguration,
        userAgent: any OIDExternalUserAgent
    ) async throws -> DriveAuthorizationOutcome {
        authorizeCount += 1
        throw ProbeError.queryFailed
    }

    func acceptPendingAuthorization() throws {}
    func discardPendingAuthorization() {}

    func accessToken(forceRefresh: Bool) async throws -> String {
        accessTokenCount += 1
        if let accessTokenFailure { throw accessTokenFailure }
        return "invented-token"
    }

    func validateCurrentGrant() throws {}

    func clear() throws {
        clearCount += 1
        hasStoredSession = false
    }

    func resumeRedirect(_ url: URL) -> Bool { false }
}

private enum ProbeError: Error {
    case queryFailed
}

private final class SequencedDailyNotesStore: DailyNotesPersisting {
    private let documents: [DailyNotesDocument]
    private var index = 0

    init(documents: [DailyNotesDocument]) {
        self.documents = documents
    }

    func load() throws -> DailyNotesDocument? {
        defer { index += 1 }
        return documents[min(index, documents.count - 1)]
    }

    func save(_ document: DailyNotesDocument) throws {}
}

private final class MutableDailyNotesStore: DailyNotesPersisting {
    var document: DailyNotesDocument?
    var failSaves = false

    func load() throws -> DailyNotesDocument? { document }
    func save(_ document: DailyNotesDocument) throws {
        if failSaves { throw CocoaError(.fileWriteUnknown) }
        self.document = document
    }
}

private struct FixedNutritionSourceSelection: NutritionSourceSelectionPersisting {
    let bundleIdentifier: String?

    func loadBundleIdentifier() -> String? { bundleIdentifier }
    func saveBundleIdentifier(_ bundleIdentifier: String?) {}
}

private final class FailingDailyProvider: DailyHealthExportDataProviding {
    let isHealthDataAvailable = true
    private(set) var fetchCount = 0

    func requestReadAuthorization() async throws {}
    func requestNutritionReadAuthorization() async throws {}
    func fetchVisibleNutritionSources() async throws -> [NutritionSource] {
        [NutritionSource(
            bundleIdentifier: "example.fixture.nutrition",
            name: "Invented Nutrition Source"
        )]
    }

    func fetchDailyHealthExportInputs(
        for window: DailyExportWindow,
        nutritionSourceBundleIdentifier: String,
        includeWorkoutEnrichment: Bool
    ) async throws -> DailyHealthExportInputs {
        fetchCount += 1
        throw ProbeError.queryFailed
    }
}

/// Holds the task that called the controller so a fake read can cancel it.
private final class CallerTaskBox: @unchecked Sendable {
    var task: Task<Void, Never>?
}

private final class RecordingDailyProvider: DailyHealthExportDataProviding {
    let isHealthDataAvailable = true
    private let sources: [NutritionSource]
    private let makeInputs: (DailyExportWindow, String) -> DailyHealthExportInputs
    private(set) var window: DailyExportWindow?
    private(set) var requestedWorkoutEnrichment: Bool?
    private(set) var requestedSourceBundleIdentifier: String?
    private(set) var fetchCount = 0
    private(set) var readAuthorizationCount = 0
    private(set) var nutritionAuthorizationCount = 0
    private(set) var sourceFetchCount = 0

    init(makeInputs: @escaping (DailyExportWindow) -> DailyHealthExportInputs) {
        sources = [NutritionSource(
            bundleIdentifier: "example.fixture.nutrition",
            name: "Invented Nutrition Source"
        )]
        self.makeInputs = { window, _ in makeInputs(window) }
    }

    init(
        sources: [NutritionSource],
        makeInputs: @escaping (DailyExportWindow, String) -> DailyHealthExportInputs
    ) {
        self.sources = sources
        self.makeInputs = makeInputs
    }

    func requestReadAuthorization() async throws {
        readAuthorizationCount += 1
    }
    func requestNutritionReadAuthorization() async throws {
        nutritionAuthorizationCount += 1
    }
    func fetchVisibleNutritionSources() async throws -> [NutritionSource] {
        sourceFetchCount += 1
        return NutritionSource.orderedUnique(sources)
    }

    func fetchDailyHealthExportInputs(
        for window: DailyExportWindow,
        nutritionSourceBundleIdentifier: String,
        includeWorkoutEnrichment: Bool
    ) async throws -> DailyHealthExportInputs {
        self.window = window
        requestedWorkoutEnrichment = includeWorkoutEnrichment
        requestedSourceBundleIdentifier = nutritionSourceBundleIdentifier
        fetchCount += 1
        return makeInputs(window, nutritionSourceBundleIdentifier)
    }
}

extension DailyHealthExportTests {
    func testSchemaSevenAdmissionPreservesHistoricalSchemaSixAndRejectsCrossVersionShapes() throws {
        let calendar = londonCalendar()
        let now = date(2026, 9, 10, 15, calendar: calendar)
        let window = try DailyExportWindow.capture(at: now, calendar: calendar)
        let start = window.day.start.addingTimeInterval(3600)
        let enrichment = WorkoutEnrichmentReader.read(.init(start: start, end: start.addingTimeInterval(60), activity: "walking", metadata: [:], statistics: .init(provenance: "healthKitWorkoutStatistics"), distanceMetres: nil, activities: []))
        let record = WorkoutRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, startDate: start, duration: 60, activityName: "Walking", enrichment: enrichment)
        let envelope = try DailyHealthExportBuilder.make(window: window, exportedAt: now, inputs: emptyInputs(window: window, workouts: [record]), includeWorkoutEnrichment: true)
        let bytes = try DailyHealthExportSerializer.encode(envelope)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        let identity = DailyHealthExportIdentityPolicy()
        XCTAssertNoThrow(try identity.validate(payload: bytes, reportDate: window.reportDate))
        let old = text.replacingOccurrences(of: "\"schema_version\":7", with: "\"schema_version\":6")
            .replacingOccurrences(of: "\"enrichment_version\":2", with: "\"enrichment_version\":1")
            .replacingOccurrences(of: "\"accepted_distance\":{\"reason\":\"notPacePrompt\",\"schema_version\":1,\"state\":\"unavailable\"},", with: "")
        XCTAssertNotEqual(old, text)
        XCTAssertFalse(old.contains("accepted_distance"))
        XCTAssertNoThrow(try identity.validate(payload: Data(old.utf8), reportDate: window.reportDate))
        for forged in [text.replacingOccurrences(of: "\"schema_version\":7", with: "\"schema_version\":6"),
                       text.replacingOccurrences(of: "\"enrichment_version\":2", with: "\"enrichment_version\":1"),
                       text.replacingOccurrences(of: "\"reason\":\"notPacePrompt\"", with: "\"reason\":\"future\""),
                       text.replacingOccurrences(of: "\"schema_version\":7", with: "\"schema_version\":8")] {
            XCTAssertThrowsError(try identity.validate(payload: Data(forged.utf8), reportDate: window.reportDate))
        }
    }
}

extension DailyHealthExportTests {
    func testExportEnrichmentChoiceIsCarriedToProviderAndBuilder() async throws {
        let calendar = londonCalendar()
        let now = date(2026, 9, 10, 15, calendar: calendar)
        let provider = RecordingDailyProvider { self.emptyInputs(window: $0) }
        let service = DailyHealthExportService(healthData: provider, calendar: calendar, now: { now })
        let basic = try await service.refresh(nutritionSourceBundleIdentifier: fixtureNutritionSource.bundleIdentifier, includeWorkoutEnrichment: false)
        XCTAssertEqual(provider.requestedWorkoutEnrichment, false)
        XCTAssertEqual(basic.envelope.schemaVersion, 3)
        let enriched = try await service.refresh(nutritionSourceBundleIdentifier: fixtureNutritionSource.bundleIdentifier)
        XCTAssertEqual(provider.requestedWorkoutEnrichment, true)
        XCTAssertEqual(enriched.envelope.schemaVersion, 7)
    }
}

// MARK: #200 typed export outcome and Settings > Export

extension DailyHealthExportTests {
    @MainActor
    func testExportOutcomeRecordMapsEveryResultAndFailure() async throws {
        let verifiedAsOf = "2026-09-06T08:00:00+01:00"
        let cases: [(Result<DailyDriveExportResult, DailyDriveExportFailure>, DailyExportOutcomeRecord.Kind, Bool, DailyExportPhase)] = [
            (.success(.verified(dataAsOf: verifiedAsOf, created: true)), .verified, false, .verified),
            (.success(.unchangedVerified(dataAsOf: verifiedAsOf)), .unchangedVerified, false, .verified),
            (.success(.cancelledBeforeSubmission), .cancelledBeforeSubmission, true, .cancelledBeforeSending),
            (.success(.cancelledAfterSubmissionVerified(dataAsOf: verifiedAsOf, created: false)), .cancelledAfterSubmissionVerified, true, .verified),
            (.failure(.transportFailure), .failed, true, .attemptedNotVerified)
        ]
        for (outcome, kind, keepsPreview, phase) in cases {
            let (session, _) = await makePreviewLifecycleSession()
            let exportedPreview = try XCTUnwrap(session.preview)
            XCTAssertNil(session.lastExportOutcome)
            _ = try? session.applyExportOutcome(outcome, exportedPreview: exportedPreview)

            let record = try XCTUnwrap(session.lastExportOutcome, "\(kind)")
            XCTAssertEqual(record.kind, kind)
            XCTAssertEqual(record.reportDate, exportedPreview.envelope.reportDate)
            let expectedAsOf = (kind == .cancelledBeforeSubmission || kind == .failed)
                ? exportedPreview.envelope.dataAsOf : verifiedAsOf
            XCTAssertEqual(record.dataAsOf, expectedAsOf, "\(kind)")
            XCTAssertEqual(session.preview != nil, keepsPreview, "\(kind)")
            XCTAssertEqual(
                DailyExportPhase.resolve(
                    setup: .ready,
                    exporting: false,
                    hasPreview: session.preview != nil,
                    lastExportOutcome: session.lastExportOutcome
                ),
                phase,
                "\(kind)"
            )

            // A fresh exportable preview supersedes the recorded result.
            await session.refreshPreview()
            XCTAssertNotNil(session.preview)
            XCTAssertNil(session.lastExportOutcome, "\(kind)")
        }
    }

    /// Same failure mode as the report (#229): if the task that asked for a
    /// preview is cancelled while HealthKit is being read, the snapshot must
    /// still complete rather than surface the cancellation as a failed state.
    /// The exported bytes match an uncancelled refresh of the same inputs.
    @MainActor
    func testCallerCancellationMidReadStillProducesThePreview() async throws {
        let (control, _) = await makePreviewLifecycleSession()
        let expected = try XCTUnwrap(control.preview)

        let calendar = londonCalendar()
        let cutoff = date(2026, 9, 6, 8, calendar: calendar)
        let notesStore = MutableDailyNotesStore()
        let caller = CallerTaskBox()
        let provider = RecordingDailyProvider { window in
            caller.task?.cancel()
            return self.emptyInputs(window: window)
        }
        let session = DailyDriveSessionController(
            keychain: MemoryDailySessionStore(),
            drive: DailyDriveAPI(),
            exportService: DailyHealthExportService(
                healthData: provider,
                notesStore: notesStore,
                calendar: calendar,
                now: { cutoff }
            ),
            identityStore: ControllerMemoryDailyIdentityStore(),
            nutritionSourceSelection: FixedNutritionSourceSelection(
                bundleIdentifier: fixtureNutritionSource.bundleIdentifier
            ),
            notes: DailyNotesController(store: notesStore, calendar: calendar, now: { cutoff })
        )
        let task = Task { await session.refreshPreview() }
        caller.task = task
        await task.value

        XCTAssertTrue(task.isCancelled, "the caller was cancelled during the read")
        XCTAssertEqual(provider.fetchCount, 1)
        let preview = try XCTUnwrap(session.preview, "a caller cancellation must not discard the preview")
        XCTAssertEqual(preview.bytes, expected.bytes)
        XCTAssertEqual(session.presentationState, control.presentationState)
        XCTAssertEqual(session.status, control.status)
    }

    @MainActor
    func testExportOutcomeIsClearedOnDayChangeAndPreparation() async throws {
        let (session, _) = await makePreviewLifecycleSession()
        try session.applyExportOutcome(
            .success(.verified(dataAsOf: "2026-09-06T08:00:00+01:00", created: true)),
            exportedPreview: try XCTUnwrap(session.preview)
        )
        XCTAssertNotNil(session.lastExportOutcome)
        session.selectReportDay(session.availableReportDays[2])
        XCTAssertNil(session.lastExportOutcome)

        let (preparing, _) = await makePreviewLifecycleSession()
        try preparing.applyExportOutcome(
            .success(.verified(dataAsOf: "2026-09-06T08:00:00+01:00", created: true)),
            exportedPreview: try XCTUnwrap(preparing.preview)
        )
        await preparing.prepareForPresentation()
        XCTAssertNil(preparing.lastExportOutcome)
    }

    @MainActor
    func testExportOutcomeIsClearedOnSavedNoteInvalidation() async throws {
        let (session, _) = await makePreviewLifecycleSession()
        let preview = try XCTUnwrap(session.preview)
        try session.applyExportOutcome(.success(.cancelledBeforeSubmission), exportedPreview: preview)
        XCTAssertEqual(session.lastExportOutcome?.kind, .cancelledBeforeSubmission)

        XCTAssertTrue(session.notes.beginNewDraft())
        session.notes.updateDraftText("Invented context")
        XCTAssertTrue(session.notes.saveDraft())

        XCTAssertNil(session.preview)
        XCTAssertNil(session.lastExportOutcome)
    }

    @MainActor
    func testExportOutcomeIsClearedOnSignOutAndRevocation() async throws {
        let (signingOut, _) = await makePreviewLifecycleSession(oauthSession: FakeDriveOAuthSession())
        try signingOut.applyExportOutcome(
            .success(.unchangedVerified(dataAsOf: "2026-09-06T08:00:00+01:00")),
            exportedPreview: try XCTUnwrap(signingOut.preview)
        )
        signingOut.signOut()
        XCTAssertNil(signingOut.lastExportOutcome)

        let (revoking, _) = await makePreviewLifecycleSession(
            drive: PreparationDriveTransportFixture(createOutcomes: [], revokeStatus: 200),
            oauthSession: FakeDriveOAuthSession()
        )
        try revoking.applyExportOutcome(
            .success(.unchangedVerified(dataAsOf: "2026-09-06T08:00:00+01:00")),
            exportedPreview: try XCTUnwrap(revoking.preview)
        )
        await revoking.disconnect()
        XCTAssertEqual(revoking.presentationState, .needsGoogleConnection)
        XCTAssertNil(revoking.lastExportOutcome)
    }

    @MainActor
    func testDayPickerOffersTodayAndSevenPreviousDays() async {
        let (session, _) = await makePreviewLifecycleSession()
        XCTAssertEqual(session.availableReportDays.count, 8)
        XCTAssertEqual(session.availableReportDays.first?.reportDate, "2026-09-06")
        XCTAssertEqual(session.exactJSONConstructionCount, 0)
        let today = DailyExportDayLabel.today(
            todayReportDate: "2026-09-06",
            previewDataAsOf: session.previewSummary?.dataAsOf
        )
        XCTAssertEqual(today, "Today, up to 08:00")
    }

    /// Owner decision C: without OAuth configuration Export shows one line and plain Drive text,
    /// Settings shows a non-tappable row and Developer tools holds the detail; configured but not
    /// connected, the primary action is "Set up Google Drive". No transition changes.
    @MainActor
    func testExportPresentsGoogleDriveByAvailability() async throws {
        XCTAssertEqual(DriveExportAvailability.resolve(isConfigured: false, setup: .notSetUp), .unavailableInBuild)
        XCTAssertEqual(DriveExportAvailability.resolve(isConfigured: false, setup: .ready), .unavailableInBuild)
        XCTAssertEqual(DriveExportAvailability.resolve(isConfigured: true, setup: .notSetUp), .needsSetup)
        for setup in [DailyExportPhase.Setup.preparing, .needsNutritionSource, .ready, .needsAttention] {
            XCTAssertEqual(DriveExportAvailability.resolve(isConfigured: true, setup: setup), .available, "\(setup)")
        }
        XCTAssertEqual(
            [DailyExportPhase.Setup.preparing, .notSetUp, .needsNutritionSource, .ready, .needsAttention]
                .filter(DriveExportAvailability.setupReturnsToExport),
            [.needsNutritionSource, .ready]
        )
        XCTAssertEqual(DriveExportAvailability.unavailableLine, "Google Drive export isn’t available in this build")
        XCTAssertTrue(DriveExportAvailability.developerDetail(isConfigured: false).contains("GoogleOAuthClientID"))

        let notesStore = MutableDailyNotesStore()
        func makeSession(configured: Bool, drive: PreparationDriveTransportFixture) throws -> DailyDriveSessionController {
            let configuration = try DriveOAuthClientConfiguration(infoDictionary: [
                "GoogleOAuthClientID": "synthetic-c.apps.googleusercontent.com",
                "GoogleOAuthRedirectScheme": "com.googleusercontent.apps.synthetic-c"
            ])
            let oauth = FakeDriveOAuthSession()
            oauth.hasStoredSession = false
            return DailyDriveSessionController(
                keychain: MemoryDailySessionStore(),
                drive: drive,
                exportService: DailyHealthExportService(
                    healthData: RecordingDailyProvider { self.emptyInputs(window: $0) }, notesStore: notesStore),
                identityStore: ControllerMemoryDailyIdentityStore(),
                nutritionSourceSelection: FixedNutritionSourceSelection(bundleIdentifier: fixtureNutritionSource.bundleIdentifier),
                notes: DailyNotesController(store: notesStore),
                oauthSession: oauth,
                oauthConfiguration: {
                    guard configured else { throw DriveOAuthClientConfiguration.Failure.missingConfiguration }
                    return configuration
                }
            )
        }
        let drive = PreparationDriveTransportFixture(createOutcomes: [])
        let unconfigured = try makeSession(configured: false, drive: drive)
        let stateBefore = unconfigured.presentationState
        XCTAssertEqual(stateBefore, .needsAttention(.configurationUnavailable), "transitions unchanged")
        XCTAssertEqual(DriveExportAvailability.resolve(isConfigured: unconfigured.isConfigured,
                                                       setup: unconfigured.presentationState.phaseSetup), .unavailableInBuild)
        let configured = try makeSession(configured: true, drive: drive)
        XCTAssertEqual(configured.presentationState, .needsGoogleConnection)
        XCTAssertEqual(DriveExportAvailability.resolve(isConfigured: configured.isConfigured,
                                                       setup: configured.presentationState.phaseSetup), .needsSetup)
        var setUpTaps = 0
        for (name, view) in [
            ("Export without Drive", AnyView(DailyExportView(session: unconfigured))),
            ("Settings Google Drive without Drive", AnyView(DriveDestinationSettingsView(session: unconfigured))),
            ("Export set up Google Drive", AnyView(DailyExportView(session: configured) { setUpTaps += 1 })),
            ("Developer tools Drive detail", AnyView(DeveloperToolsSettingsView(
                toggle: SettingsToggle(title: "Synthetic", read: { false }, write: { _ in }), driveExportConfigured: false)))
        ] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let host = UIHostingController(rootView: NavigationStack { view }.environment(\.dynamicTypeSize, size))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
                window.rootViewController = host
                window.isHidden = false
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(name) - \(size)"; attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
        XCTAssertEqual(setUpTaps, 0, "rendering never opens setup")
        XCTAssertEqual(unconfigured.presentationState, stateBefore, "rendering Export changes no state")
        let snapshot = await drive.snapshot()
        XCTAssertEqual(snapshot.accountCount, 0)
        XCTAssertEqual(snapshot.uploadCount, 0)

        let settings = WeeklyHealthReportApp.makeSettings(
            foodLedger: nil,
            defaults: UserDefaults(suiteName: "drive-settings-" + UUID().uuidString)!,
            medicationAccessAvailable: false,
            driveExportAvailable: false
        )
        let export = try XCTUnwrap(settings.sections.first { $0.id == .export })
        XCTAssertEqual(export.rows.compactMap(\.route), [], "the row is not tappable")
        guard case let .text(detail) = try XCTUnwrap(export.rows.first).kind else { return XCTFail("Expected plain text") }
        XCTAssertEqual(detail, "Not available in this build")
    }

    /// Opening Settings > Export sends no HealthKit, OAuth or Drive request
    /// and never prepares an export.
    @MainActor
    func testOpeningDriveSettingsMakesNoHealthOAuthOrDriveCalls() async throws {
        let drive = PreparationDriveTransportFixture(createOutcomes: [])
        let oauth = FakeDriveOAuthSession()
        let provider = RecordingDailyProvider { self.emptyInputs(window: $0) }
        let notesStore = MutableDailyNotesStore()
        let session = DailyDriveSessionController(
            keychain: MemoryDailySessionStore(),
            drive: drive,
            exportService: DailyHealthExportService(healthData: provider, notesStore: notesStore),
            identityStore: ControllerMemoryDailyIdentityStore(),
            nutritionSourceSelection: FixedNutritionSourceSelection(
                bundleIdentifier: fixtureNutritionSource.bundleIdentifier
            ),
            notes: DailyNotesController(store: notesStore),
            oauthSession: oauth
        )
        let stateBefore = session.presentationState
        let statusBefore = session.status

        let settings = WeeklyHealthReportApp.makeSettings(
            foodLedger: nil,
            defaults: UserDefaults(suiteName: "drive-settings-" + UUID().uuidString)!,
            medicationAccessAvailable: false,
            driveExportAvailable: true
        )
        XCTAssertEqual(settings.sections.first { $0.id == .export }?.rows.compactMap(\.route), [.exportDestination])

        let host = UIHostingController(rootView: NavigationStack {
            DriveDestinationSettingsView(session: session)
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        window.isHidden = true

        let snapshot = await drive.snapshot()
        XCTAssertEqual(snapshot.accountCount, 0)
        XCTAssertEqual(snapshot.folderReadCount, 0)
        XCTAssertEqual(snapshot.generatedCount, 0)
        XCTAssertEqual(snapshot.uploadCount, 0)
        XCTAssertEqual(snapshot.revokeCount, 0)
        XCTAssertEqual(oauth.authorizeCount, 0)
        XCTAssertEqual(oauth.accessTokenCount, 0)
        XCTAssertEqual(oauth.clearCount, 0)
        XCTAssertEqual(provider.fetchCount, 0)
        XCTAssertEqual(provider.sourceFetchCount, 0)
        XCTAssertEqual(provider.readAuthorizationCount, 0)
        XCTAssertEqual(provider.nutritionAuthorizationCount, 0)
        XCTAssertNil(session.preview)
        XCTAssertFalse(session.busy)
        XCTAssertEqual(session.presentationState, stateBefore)
        XCTAssertEqual(session.status, statusBefore)
    }
}

// MARK: #200 review fixes

extension DailyHealthExportTests {
    @MainActor
    func testRefreshAfterVerifiedExportShowsPreparedNotVerified() async throws {
        let (session, _) = await makePreviewLifecycleSession()
        try session.applyExportOutcome(
            .success(.verified(dataAsOf: "2026-09-06T08:00:00+01:00", created: true)),
            exportedPreview: try XCTUnwrap(session.preview)
        )
        XCTAssertNil(session.preview)
        XCTAssertEqual(DailyExportPhase.resolve(
            setup: .ready, exporting: false, hasPreview: false,
            lastExportOutcome: session.lastExportOutcome
        ), .verified)

        await session.refreshPreview()

        XCTAssertNotNil(session.preview)
        XCTAssertNil(session.lastExportOutcome)
        XCTAssertEqual(DailyExportPhase.resolve(
            setup: .ready, exporting: false, hasPreview: true,
            lastExportOutcome: session.lastExportOutcome
        ), .prepared)
    }

    @MainActor
    func testAuthorizationErrorClearsExportOutcome() async throws {
        let oauth = FakeDriveOAuthSession()
        let (session, _) = await makePreviewLifecycleSession(oauthSession: oauth)
        try session.applyExportOutcome(
            .success(.unchangedVerified(dataAsOf: "2026-09-06T08:00:00+01:00")),
            exportedPreview: try XCTUnwrap(session.preview)
        )
        oauth.onAuthorizationError?(.revoked)
        XCTAssertNil(session.lastExportOutcome)
        XCTAssertEqual(session.presentationState, .needsGoogleConnection)
    }

    @MainActor
    func testDayChangeWhileNotConnectedStaysNotSetUp() async {
        let oauth = FakeDriveOAuthSession()
        oauth.hasStoredSession = false
        let session = makePreparationSession(
            drive: PreparationDriveTransportFixture(createOutcomes: []),
            oauthSession: oauth
        )
        let initial = session.presentationState
        session.selectReportDay(session.availableReportDays[2])
        XCTAssertEqual(session.presentationState, initial)
        XCTAssertNotEqual(session.presentationState.phaseSetup, .needsAttention)
        XCTAssertFalse(session.status.contains("Retry preparation"))
    }

    @MainActor
    func testDayChangeAfterPreparationNamesTheRetryButton() async {
        let (session, _) = await makePreviewLifecycleSession()
        session.selectReportDay(session.availableReportDays[2])
        XCTAssertEqual(session.presentationState, .needsAttention(.notesChanged))
        XCTAssertTrue(session.presentationState.actions.contains(.retry))
        XCTAssertTrue(session.status.contains("Retry preparation"))
    }

    @MainActor
    func testRemoteTrashedAndMissingExportsKeepBehaviourAndRecordFailure() async throws {
        let cases: [(PreparationDriveTransportFixture.FileOutcome, DailyDriveExportFailure, DailyDriveSessionController.FileReplacementReason)] = [
            (.acceptedThenTrashed, .remoteTrashed, .trashed),
            (.notFound, .remoteMissing, .missingOrInaccessible)
        ]
        for (fileOutcome, failure, reason) in cases {
            let store = MemoryDailySessionStore()
            let binding = DailyDestinationBinding(
                accountID: "invented-account",
                folderID: "invented-folder",
                folderName: "Invented",
                origin: .picker
            )
            try store.save(
                try JSONEncoder().encode(partitions(containing: binding)),
                account: "google.drive.daily-export-destinations.v1"
            )
            let drive = PreparationDriveTransportFixture(createOutcomes: [], fileOutcome: fileOutcome)
            let (session, _) = await makePreviewLifecycleSession(
                drive: drive,
                secureStore: store,
                oauthSession: FakeDriveOAuthSession()
            )
            _ = try await session.restoreGoogleSession()
            let preview = try XCTUnwrap(session.preview)

            await session.exportPreview()

            XCTAssertEqual(session.presentationState, .needsAttention(.canonicalRecovery), "\(failure)")
            XCTAssertEqual(session.status, failure.userFacingLabel, "\(failure)")
            XCTAssertEqual(session.fileReplacementReason, reason, "\(failure)")
            XCTAssertEqual(session.preview, preview, "\(failure)")
            XCTAssertEqual(session.lastExportOutcome?.kind, .failed, "\(failure)")
            XCTAssertEqual(session.lastExportOutcome?.reportDate, preview.envelope.reportDate)
            XCTAssertFalse(session.exporting)
        }
    }

    @MainActor
    func testSettingsDriveActionsReachTheMatchingControllerMethod() async {
        let expected: [DriveDestinationAction: String] = [
            .connect: "connect",
            .signOut: "signOut",
            .revoke: "disconnect",
            .chooseFolder: "chooseDestination",
            .createFolder: "createDestination"
        ]
        XCTAssertEqual(Set(expected.keys), Set(DriveDestinationAction.allCases))
        for action in DriveDestinationAction.allCases {
            let spy = DriveDestinationControllerSpy()
            await action.perform(on: spy)
            XCTAssertEqual(spy.calls, [expected[action]!], "\(action)")
        }
    }
}

@MainActor
private final class DriveDestinationControllerSpy: DriveDestinationControlling {
    private(set) var calls: [String] = []
    func connect() async { calls.append("connect") }
    func signOut() { calls.append("signOut") }
    func disconnect() async { calls.append("disconnect") }
    func chooseDestination() async { calls.append("chooseDestination") }
    func createDestination() async { calls.append("createDestination") }
}

// MARK: - README screenshot (#218)

extension DailyHealthExportTests {
    /// Renders the README's "Daily JSON review and export" image from synthetic
    /// fixtures only: an invented Drive account and folder, an invented nutrition
    /// source, invented health values and one invented note. The OAuth client
    /// configuration is a synthetic stand-in, so the screen reaches its prepared
    /// state without any build secret, network request or HealthKit query.
    ///
    /// The PNG is always attached to the test result. To refresh the README image,
    /// run this test with `TEST_RUNNER_README_SCREENSHOT_DIR=<absolute directory>`
    /// in the `xcodebuild test` environment and copy
    /// `weekly-health-report-daily-export-synthetic.png` into the README images.
    @MainActor
    func testReadmeExportScreenshotRendersPreparedSyntheticSnapshot() async throws {
        let calendar = londonCalendar()
        let cutoff = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9, minute: 41))!
        let secureStore = MemoryDailySessionStore()
        let binding = DailyDestinationBinding(
            accountID: "invented-account",
            folderID: "synthetic-readme-folder",
            folderName: "WeeklyHealthReport Exports",
            origin: .created
        )
        try secureStore.save(
            try JSONEncoder().encode(partitions(containing: binding)),
            account: "google.drive.daily-export-destinations.v1"
        )
        let drive = PreparationDriveTransportFixture(createOutcomes: [])
        await drive.seedFolder(DailyDriveFolder(
            id: binding.folderID,
            accountID: binding.accountID,
            name: binding.folderName,
            mimeType: DailyDriveConsentPolicy.folderMIMEType,
            trashed: false,
            driveID: nil,
            isAppAuthorized: true,
            canAddChildren: true
        ))
        let notesStore = MutableDailyNotesStore()
        let notes = DailyNotesController(store: notesStore, calendar: calendar, now: { cutoff })
        XCTAssertTrue(notes.beginNewDraft())
        XCTAssertTrue(notes.updateDraftText("Synthetic note invented for the README image"))
        XCTAssertTrue(notes.saveDraft())
        let syntheticConfiguration = try DriveOAuthClientConfiguration(infoDictionary: [
            "GoogleOAuthClientID": "synthetic-readme.apps.googleusercontent.com",
            "GoogleOAuthRedirectScheme": "com.googleusercontent.apps.synthetic-readme"
        ])
        let session = DailyDriveSessionController(
            keychain: secureStore,
            drive: drive,
            exportService: DailyHealthExportService(
                healthData: RecordingDailyProvider { self.populatedInputs(window: $0) },
                notesStore: notesStore,
                calendar: calendar,
                now: { cutoff }
            ),
            identityStore: ControllerMemoryDailyIdentityStore(),
            nutritionSourceSelection: FixedNutritionSourceSelection(
                bundleIdentifier: fixtureNutritionSource.bundleIdentifier
            ),
            notes: notes,
            oauthSession: FakeDriveOAuthSession(),
            oauthConfiguration: { syntheticConfiguration }
        )
        XCTAssertTrue(session.isConfigured)

        let host = UIHostingController(rootView: NavigationStack { DailyExportView(session: session) })
        // iPhone 17 Pro width; the height fits the whole prepared form so the
        // Export action and the Drive destination are both visible.
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 1500)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = bounds
        } else {
            window = UIWindow(frame: bounds)
        }
        window.overrideUserInterfaceStyle = .light
        host.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        // DailyExportView prepares on appear; wait for the synthetic fakes to settle.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              session.busy || session.presentationState != .readyToExport || session.preview == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(session.presentationState, .readyToExport, session.status)
        XCTAssertTrue(session.canExport)
        XCTAssertEqual(session.destinationLabel, "WeeklyHealthReport Exports")
        XCTAssertEqual(session.status, "Fresh preview created in memory. Review the snapshot, then choose Export.")
        let snapshot = await drive.snapshot()
        XCTAssertEqual(snapshot.uploadCount, 0, "Rendering must never export")
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 100_000_000)
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            CATransaction.flush()
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        XCTAssertEqual(image.size, bounds.size)
        let attachment = XCTAttachment(image: image)
        attachment.name = "README - Daily JSON export - prepared synthetic snapshot"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["README_SCREENSHOT_DIR"], !directory.isEmpty {
            let data = try XCTUnwrap(image.pngData())
            try data.write(to: URL(fileURLWithPath: directory)
                .appendingPathComponent("weekly-health-report-daily-export-synthetic.png"))
        }
    }
}
