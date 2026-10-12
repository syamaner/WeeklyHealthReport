import XCTest
@testable import WeeklyHealthReport

/// #200: the Export screen's phase and day labels are pure functions of plain inputs.
final class DailyExportPhaseTests: XCTestCase {
    private func record(_ kind: DailyExportOutcomeRecord.Kind) -> DailyExportOutcomeRecord {
        DailyExportOutcomeRecord(reportDate: "2026-09-06", dataAsOf: "2026-09-06T08:00:00+01:00", kind: kind)
    }

    func testOutcomeKindsMapExhaustively() {
        let expected: [(DailyExportOutcomeRecord.Kind, DailyExportPhase)] = [
            (.verified, .verified),
            (.unchangedVerified, .verified),
            (.cancelledAfterSubmissionVerified, .verified),
            (.cancelledBeforeSubmission, .cancelledBeforeSending),
            (.failed, .attemptedNotVerified)
        ]
        for (kind, phase) in expected {
            for hasPreview in [false, true] {
                XCTAssertEqual(
                    DailyExportPhase.resolve(setup: .ready, exporting: false, hasPreview: hasPreview, lastExportOutcome: record(kind)),
                    phase, "\(kind), preview \(hasPreview)"
                )
            }
        }
    }

    func testVerifiedSurvivesTheDiscardedPreview() {
        XCTAssertEqual(
            DailyExportPhase.resolve(setup: .ready, exporting: false, hasPreview: false, lastExportOutcome: record(.verified)),
            .verified
        )
    }

    func testVerifiedNeverAppearsWithoutAVerifiedOutcome() {
        let setups: [DailyExportPhase.Setup] = [.preparing, .notSetUp, .needsNutritionSource, .ready, .needsAttention]
        let outcomes: [DailyExportOutcomeRecord?] = [nil, record(.cancelledBeforeSubmission), record(.failed)]
        for setup in setups {
            for exporting in [false, true] {
                for hasPreview in [false, true] {
                    for outcome in outcomes {
                        XCTAssertNotEqual(
                            DailyExportPhase.resolve(setup: setup, exporting: exporting, hasPreview: hasPreview, lastExportOutcome: outcome),
                            .verified
                        )
                    }
                }
            }
        }
    }

    func testSetupAndInFlightStates() {
        XCTAssertEqual(DailyExportPhase.resolve(setup: .preparing, exporting: false, hasPreview: false, lastExportOutcome: nil), .preparing)
        XCTAssertEqual(DailyExportPhase.resolve(setup: .notSetUp, exporting: false, hasPreview: false, lastExportOutcome: nil), .notSetUp)
        XCTAssertEqual(DailyExportPhase.resolve(setup: .needsNutritionSource, exporting: false, hasPreview: false, lastExportOutcome: nil), .needsAttention)
        XCTAssertEqual(DailyExportPhase.resolve(setup: .needsAttention, exporting: false, hasPreview: true, lastExportOutcome: nil), .needsAttention)
        XCTAssertEqual(DailyExportPhase.resolve(setup: .ready, exporting: false, hasPreview: true, lastExportOutcome: nil), .prepared)
        XCTAssertEqual(DailyExportPhase.resolve(setup: .ready, exporting: true, hasPreview: true, lastExportOutcome: nil), .attempting)
        XCTAssertEqual(DailyExportPhase.resolve(setup: .ready, exporting: true, hasPreview: true, lastExportOutcome: record(.verified)), .attempting)
        // A later problem is not hidden behind an earlier verified export.
        XCTAssertEqual(DailyExportPhase.resolve(setup: .needsAttention, exporting: false, hasPreview: false, lastExportOutcome: record(.verified)), .needsAttention)
        XCTAssertEqual(DailyExportPhase.resolve(setup: .notSetUp, exporting: false, hasPreview: false, lastExportOutcome: record(.verified)), .notSetUp)
        // A failed attempt is reported even when the failure moved the screen to needs attention.
        XCTAssertEqual(DailyExportPhase.resolve(setup: .needsAttention, exporting: false, hasPreview: true, lastExportOutcome: record(.failed)), .attemptedNotVerified)
    }

    func testPresentationStatesMapToPlainSetup() {
        XCTAssertEqual(DailyExportPresentationState.preparing.phaseSetup, .preparing)
        XCTAssertEqual(DailyExportPresentationState.needsGoogleConnection.phaseSetup, .notSetUp)
        XCTAssertEqual(DailyExportPresentationState.needsAttention(.configurationUnavailable).phaseSetup, .notSetUp)
        XCTAssertEqual(DailyExportPresentationState.needsNutritionSource.phaseSetup, .needsNutritionSource)
        XCTAssertEqual(DailyExportPresentationState.readyToExport.phaseSetup, .ready)
        for attention in [DailyExportAttention.googleUnavailable, .destinationRequired, .destinationTrashed, .notesChanged, .canonicalRecovery, .unexpected] {
            XCTAssertEqual(DailyExportPresentationState.needsAttention(attention).phaseSetup, .needsAttention, "\(attention)")
        }
    }

    func testTodayLabelUsesOnlyAPreparedCutoffForToday() {
        XCTAssertEqual(DailyExportDayLabel.today(todayReportDate: "2026-09-06", previewDataAsOf: nil), "Today")
        XCTAssertEqual(DailyExportDayLabel.today(todayReportDate: "2026-09-06", previewDataAsOf: "2026-09-06T08:05:00+01:00"), "Today, up to 08:05")
        XCTAssertEqual(DailyExportDayLabel.today(todayReportDate: "2026-09-06", previewDataAsOf: "2026-09-05T23:59:00+01:00"), "Today")
        XCTAssertEqual(DailyExportDayLabel.today(todayReportDate: "2026-09-06", previewDataAsOf: "not a timestamp"), "Today")
        XCTAssertEqual(DailyExportDayLabel.today(todayReportDate: "2026-09-06", previewDataAsOf: "2026-09-06"), "Today")
    }

    func testCutoffIsReadableForTimestampsAndOrderingTokens() {
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(DailyExportDayLabel.cutoff("2026-09-06T08:00:00+01:00", locale: locale), "Sunday 6 September, 08:00")
        XCTAssertEqual(
            DailyExportDayLabel.cutoff("v2|2026-09-06T00:00:00+01:00|2026-09-07T09:15:00+01:00", locale: locale),
            "Sunday 6 September, 00:00"
        )
        XCTAssertEqual(DailyExportDayLabel.cutoff("unparseable", locale: locale), "unparseable")
    }

    /// The Included "Health data" row reads like the day picker, never a raw ISO timestamp.
    func testHealthDataAsOfIsReadableAndUsesOnlyTheSnapshot() {
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(DailyExportDayLabel.dataAsOf("2026-10-12T09:41:00+01:00", reportDate: "2026-10-12",
                                                    todayReportDate: "2026-10-12", locale: locale), "Today, 09:41")
        XCTAssertEqual(DailyExportDayLabel.dataAsOf("2026-10-12T00:00:00+01:00", reportDate: "2026-10-11",
                                                    todayReportDate: "2026-10-12", locale: locale),
                       "Monday 12 October, 00:00", "yesterday's full day is not 'Today'")
        XCTAssertEqual(DailyExportDayLabel.dataAsOf("2026-10-12T09:41:00+01:00", reportDate: "2026-10-12",
                                                    todayReportDate: nil, locale: locale), "Monday 12 October, 09:41")
        XCTAssertEqual(DailyExportDayLabel.dataAsOf("historical-v2|2026-10-11T00:00:00+01:00|2026-10-12T09:15:00+01:00",
                                                    reportDate: "2026-10-10", todayReportDate: "2026-10-12", locale: locale),
                       "Sunday 11 October, 00:00")
        XCTAssertEqual(DailyExportDayLabel.dataAsOf("unparseable", reportDate: "2026-10-12",
                                                    todayReportDate: "2026-10-12", locale: locale), "unparseable")
    }

    func testPreviousDaysUseWeekdayNames() {
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(DailyExportDayLabel.previousDay(reportDate: "2026-09-05", locale: locale), "Saturday 5 September")
        XCTAssertEqual(DailyExportDayLabel.previousDay(reportDate: "2026-03-29", locale: locale), "Sunday 29 March")
        XCTAssertEqual(DailyExportDayLabel.previousDay(reportDate: "invalid", locale: locale), "invalid")
    }
}
