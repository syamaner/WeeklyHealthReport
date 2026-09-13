import SwiftUI

struct BloodPressureReportSection: View {
    let section: ReportDocument.Section
    @Binding var showsMorningDetails: Bool
    @Binding var showsEveningDetails: Bool

    var body: some View {
        Section {
            if let latest = row("blood-pressure-latest"),
               let recorded = row("blood-pressure-recorded"),
               let morningAverage = row("blood-pressure-morning-average"),
               let eveningAverage = row("blood-pressure-evening-average") {
                VStack(alignment: .leading, spacing: 5) {
                    responsiveLabel(
                        latest.label ?? "",
                        value: latest.value
                    )
                    Text(recorded.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                disclosure(
                    id: "morning",
                    average: morningAverage,
                    isExpanded: $showsMorningDetails
                )
                disclosure(
                    id: "evening",
                    average: eveningAverage,
                    isExpanded: $showsEveningDetails
                )
            } else {
                ForEach(section.rows) { row in
                    ReportDocumentRowView(row: row)
                }
            }
        } header: {
            Text(section.title)
        } footer: {
            if let footer = section.footer {
                Text(footer)
            }
        }
    }

    @ViewBuilder
    private func responsiveLabel(_ label: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                Spacer(minLength: 8)
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func disclosure(
        id: String,
        average: ReportDocument.Row,
        isExpanded: Binding<Bool>
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            if let latestBatch = row("blood-pressure-\(id)-latest-batch") {
                responsiveLabel(
                    latestBatch.label ?? "",
                    value: latestBatch.value
                )
            }
            if let recorded = row("blood-pressure-\(id)-recorded") {
                responsiveLabel(recorded.label ?? "", value: recorded.value)
            }
            if let coverage = row("blood-pressure-\(id)-coverage") {
                responsiveLabel(coverage.label ?? "", value: coverage.value)
            }
        } label: {
            responsiveLabel(average.label ?? "", value: average.value)
        }
    }

    private func row(_ id: String) -> ReportDocument.Row? {
        section.rows.first { $0.id == id }
    }
}

struct MedicationReportSection: View {
    let section: ReportDocument.Section
    let requestAccess: () -> Void

    var body: some View {
        Section {
            ForEach(section.rows) { row in
                if let name = row.label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                        Text(row.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ReportDocumentRowView(row: row)
                }
            }

            Button("Medication Access", action: requestAccess)
        } header: {
            Text(section.title)
        } footer: {
            if let footer = section.footer {
                Text(footer)
            }
        }
    }
}
