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
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The technical message behind each Health report row that reads "Could not
/// read Apple Health." on screen. Shown only when a read failed.
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
