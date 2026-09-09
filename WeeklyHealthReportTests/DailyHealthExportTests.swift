import HealthKit
import XCTest
@testable import WeeklyHealthReport

// Every health value in this file is invented. These tests never access HealthKit.
final class DailyHealthExportTests: XCTestCase {
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
        let keychain = DailyDriveKeychainStore(service: "WeeklyHealthReportTests.\(UUID())")
        let session = DailyDriveSessionController(
            keychain: keychain,
            drive: DailyDriveAPI(),
            exportService: DailyHealthExportService(
                healthData: provider,
                notesStore: notesStore,
                calendar: calendar,
                now: { cutoff }
            ),
            identityStore: KeychainDailyDriveExportIdentityStore(keychain: keychain),
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
        XCTAssertEqual(Set(NutritionCatalogue.all.map(\.identifier)).count, 39)
        XCTAssertEqual(NutritionCatalogue.all.map(\.key), expected.map(\.0))
        XCTAssertEqual(NutritionCatalogue.all.map(\.identifier), expected.map(\.1))
        XCTAssertEqual(NutritionCatalogue.all.map(\.unit), expected.map(\.2))
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
        for definition in NutritionCatalogue.all {
            let type = try XCTUnwrap(
                HKObjectType.quantityType(forIdentifier: definition.identifier)
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

    @MainActor
    private func makePreparationSession(
        drive: any DailyDriveSessionTransporting,
        secureStore: any DailyDriveSecurePersisting = MemoryDailySessionStore()
    ) -> DailyDriveSessionController {
        let identityKeychain = DailyDriveKeychainStore(
            service: "WeeklyHealthReportTests.PreparationIdentity.\(UUID())"
        )
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
            identityStore: KeychainDailyDriveExportIdentityStore(keychain: identityKeychain),
            nutritionSourceSelection: FixedNutritionSourceSelection(bundleIdentifier: nil),
            notes: DailyNotesController(store: notesStore)
        )
    }

    private func londonCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
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

    private func emptyInputs(window: DailyExportWindow) -> DailyHealthExportInputs {
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
            todayWorkouts: [],
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
            contextSteps: value.contextSteps,
            contextGlucose: value.contextGlucose,
            contextRestingHeartRate: value.contextRestingHeartRate,
            previousRestingHeartRate: value.previousRestingHeartRate,
            contextHRV: value.contextHRV,
            previousHRV: value.previousHRV,
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

private final class MemoryDailySessionStore: DailyDriveSecurePersisting {
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
    }

    private let accountValue = DailyDriveAccount(
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

    init(createOutcomes: [CreateOutcome]) {
        self.createOutcomes = createOutcomes
    }

    func fixtureAccount() -> DailyDriveAccount { accountValue }

    func snapshot() -> Snapshot {
        Snapshot(
            generatedCount: generatedCount,
            createIDs: createIDs,
            folderReadCount: folderReadCount,
            folderCount: folders.count,
            uploadCount: uploadCount
        )
    }

    func account(accessToken: String) async throws -> DailyDriveAccount { accountValue }

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

    func revoke(token: String) async throws -> Int { 200 }

    func createFile(
        _ descriptor: DailyDriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws {
        uploadCount += 1
        throw URLError(.unsupportedURL)
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
        throw DailyDriveAPI.Failure.httpStatus(404, nil)
    }

    func fileContent(id: String, accessToken: String) async throws -> Data {
        throw DailyDriveAPI.Failure.httpStatus(404, nil)
    }
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
        nutritionSourceBundleIdentifier: String
    ) async throws -> DailyHealthExportInputs {
        fetchCount += 1
        throw ProbeError.queryFailed
    }
}

private final class RecordingDailyProvider: DailyHealthExportDataProviding {
    let isHealthDataAvailable = true
    private let sources: [NutritionSource]
    private let makeInputs: (DailyExportWindow, String) -> DailyHealthExportInputs
    private(set) var window: DailyExportWindow?
    private(set) var requestedSourceBundleIdentifier: String?
    private(set) var fetchCount = 0
    private(set) var readAuthorizationCount = 0
    private(set) var nutritionAuthorizationCount = 0

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
        NutritionSource.orderedUnique(sources)
    }

    func fetchDailyHealthExportInputs(
        for window: DailyExportWindow,
        nutritionSourceBundleIdentifier: String
    ) async throws -> DailyHealthExportInputs {
        self.window = window
        requestedSourceBundleIdentifier = nutritionSourceBundleIdentifier
        fetchCount += 1
        return makeInputs(window, nutritionSourceBundleIdentifier)
    }
}
