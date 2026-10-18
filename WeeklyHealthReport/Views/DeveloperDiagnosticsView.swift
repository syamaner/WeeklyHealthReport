import SwiftUI

struct DeveloperDiagnosticsView: View {
    @ObservedObject var viewModel: WeeklyReportViewModel
    @ObservedObject var todaySoFar: TodaySoFarHealthModel

    var body: some View {
        Form {
            TodaySoFarDiagnosticsSection(model: todaySoFar)
            ReportReadFailuresDiagnosticsSection(
                failures: viewModel.presentationSnapshot(
                    includesMedicationSection: HealthReportView.includesMedicationSection,
                    showsMorningBloodPressureDetails: true,
                    showsEveningBloodPressureDetails: true
                ).readFailures
            )
            QueryDiagnosticsSection(period: viewModel.period)
            StepsDiagnosticsSection(state: viewModel.state)
            DailyBucketDiagnosticsSection(
                title: "Daily buckets",
                records: viewModel.dailyBucketReads
            )
            DailyBucketDiagnosticsSection(
                title: "Daily buckets, Daily JSON export",
                records: viewModel.otherDailyBucketReads
            )
            BodyMeasurementsDiagnosticsSections(
                weightState: viewModel.weightState,
                bodyFatState: viewModel.bodyFatState,
                waistState: viewModel.waistState
            )
            GlucoseDiagnosticsSection(state: viewModel.glucoseState)
            CardiorespiratoryDiagnosticsSections(
                vo2MaxState: viewModel.vo2MaxState,
                bloodOxygenState: viewModel.bloodOxygenState
            )
            BloodPressureDiagnosticsSection(state: viewModel.bloodPressureState)
            HeartDiagnosticsSections(
                restingHeartRateState: viewModel.restingHeartRateState,
                hrvState: viewModel.hrvState,
                watchCoverageState: viewModel.watchCoverageState
            )
            ActivityDiagnosticsSection(
                activeEnergyState: viewModel.activeEnergyState,
                exerciseState: viewModel.exerciseState,
                workoutState: viewModel.workoutState
            )
            SleepDiagnosticsSection(state: viewModel.sleepState)
            MedicationDiagnosticsSection(state: viewModel.medicationState)
            FoodLogReportDiagnosticsSection(state: viewModel.foodLogState)
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The technical message behind each Health report row that reads "Could not
/// read Apple Health." (or "Could not read the food log.") on screen. Shown only
/// when a read failed.
struct ReportReadFailuresDiagnosticsSection: View {
    let failures: [ReportReadFailure]

    @ViewBuilder
    var body: some View {
        if !failures.isEmpty {
            Section("Health report read failures") {
                ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.metric)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(failure.message)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

/// Food and water inputs (#214): each reporting date's entry count, unrounded
/// energy and plain water with their flags, and the day's classification.
struct FoodLogReportDiagnosticsSection: View {
    let state: MetricState<FoodLogPeriodSummary>

    var body: some View {
        Section("Food log (Health report)") {
            ForEach(Array(FoodLogReportDiagnostics.lines(state).enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(line.detail)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
