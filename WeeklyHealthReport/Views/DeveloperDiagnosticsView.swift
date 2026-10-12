import SwiftUI

struct DeveloperDiagnosticsView: View {
    @ObservedObject var viewModel: WeeklyReportViewModel
    @ObservedObject var todaySoFar: TodaySoFarHealthModel

    var body: some View {
        Form {
            TodaySoFarDiagnosticsSection(model: todaySoFar)
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
