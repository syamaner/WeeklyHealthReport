import SwiftUI
import UIKit

@MainActor
final class WeeklyReportPresentationState: ObservableObject {
    @Published var showsMorningBloodPressureDetails = true
    @Published var showsEveningBloodPressureDetails = false
    @Published var showsMedicationAccessHelp = false
    @Published private(set) var isMedicationAuthorizationRequestActive = false

    var isTransientUIPresented: Bool {
        showsMedicationAccessHelp || isMedicationAuthorizationRequestActive
    }

    func beginMedicationAuthorizationRequest() {
        isMedicationAuthorizationRequestActive = true
    }

    func finishMedicationAuthorizationRequest() {
        isMedicationAuthorizationRequestActive = false
    }
}

/// The completed-day Health report. The shell owns its presentation state so
/// screenshot eligibility and the medication help sheet keep one owner.
struct HealthReportView: View {
    @ObservedObject var viewModel: WeeklyReportViewModel
    @ObservedObject var presentationState: WeeklyReportPresentationState
    @State private var copied = false

    var body: some View {
        let document = Self.reportDocument(snapshot: viewModel.presentationSnapshot(
            includesMedicationSection: Self.includesMedicationSection,
            showsMorningBloodPressureDetails:
                presentationState.showsMorningBloodPressureDetails,
            showsEveningBloodPressureDetails:
                presentationState.showsEveningBloodPressureDetails
        ))
        return Form {
                Section("Export") {
                    NavigationLink("Daily JSON Export", value: AppRoute.dailyExport)
                    Text("Refresh, review and export are separate manual actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Reporting period", selection: $viewModel.selection) {
                        ForEach(ReportPeriodSelection.allCases) { selection in
                            Text(selection.rawValue).tag(selection)
                        }
                    }
                    .onChange(of: viewModel.selection) {
                        Task { await viewModel.refresh() }
                    }

                    LabeledContent("Period", value: periodText)
                }

                ForEach(document.sections) { section in
                    switch section.id {
                    case .bloodPressure:
                        BloodPressureReportSection(
                            section: section,
                            showsMorningDetails:
                                $presentationState.showsMorningBloodPressureDetails,
                            showsEveningDetails:
                                $presentationState.showsEveningBloodPressureDetails
                        )
                    case .medications:
                        if #available(iOS 26.0, *) {
                            MedicationReportSection(
                                section: section,
                                requestAccess: {
                                    presentationState.showsMedicationAccessHelp = true
                                }
                            )
                        }
                    default:
                        ReportDocumentSectionView(section: section)
                    }
                }

                Section {
                    Button {
                        let document = Self.reportDocument(
                            snapshot: viewModel.presentationSnapshot(
                                includesMedicationSection: Self.includesMedicationSection,
                                showsMorningBloodPressureDetails: true,
                                showsEveningBloodPressureDetails: true
                            )
                        )
                        UIPasteboard.general.string = document.plainText(generatedAt: Date())
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Label(
                            copied ? "Copied" : "Copy Report",
                            systemImage: copied ? "checkmark" : "doc.on.doc"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isRefreshing)
                }

                Section {
                    Button("Refresh") {
                        Task { await viewModel.refresh() }
                    }
                    .disabled(viewModel.state == .loading)

                    if let refreshed = viewModel.lastRefreshed {
                        LabeledContent(
                            "Last refreshed",
                            value: HealthReportFormatter.dateAndTime(refreshed)
                        )
                        .foregroundStyle(.secondary)
                    }
                }

            }
    }

    private var periodText: String {
        viewModel.period.completedDays.isEmpty
            ? "No completed days"
            : HealthReportFormatter.period(viewModel.period)
    }

    static func reportDocument(
        snapshot: ReportPresentationSnapshot
    ) -> ReportDocument {
        ReportDocument(snapshot: snapshot)
    }

    static var includesMedicationSection: Bool {
        if #available(iOS 26.0, *) {
            true
        } else {
            false
        }
    }
}
