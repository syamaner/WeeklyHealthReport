import SwiftUI

struct ReportDocumentSectionView: View {
    let section: ReportDocument.Section
    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            if isExpanded {
                ForEach(section.rows) { row in
                    ReportDocumentRowView(row: row)
                }
            }
        } header: {
            ReportSectionHeader(title: section.title, isExpanded: $isExpanded)
        } footer: {
            if isExpanded, let footer = section.footer {
                Text(footer)
            }
        }
    }
}

/// A heading over a multi-section group (#216). It is a heading only: it holds
/// no rows and collapses nothing; each section keeps its own disclosure.
struct ReportGroupHeading: View {
    let heading: String

    var body: some View {
        Section {
            EmptyView()
        } header: {
            Text(heading)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 8)
        }
    }
}

/// The one disclosure style for every Health section. Expansion changes only
/// the screen; copied text and Full Page always include every row.
struct ReportSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation { isExpanded.toggle() }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hides this section's rows" : "Shows this section's rows")
        .accessibilityAddTraits(.isHeader)
    }
}

struct ReportDocumentRowView: View {
    let row: ReportDocument.Row

    @ViewBuilder
    var body: some View {
        if let label = row.label {
            switch row.style {
            case .loading:
                LabeledContent(label) {
                    ProgressView()
                }
            case .standard:
                LabeledContent(label, value: row.value)
            case .secondary, .note:
                LabeledContent(label, value: row.value)
                    .foregroundStyle(.secondary)
            case .failure:
                LabeledContent(label, value: row.value)
                    .foregroundStyle(.red)
            }
        } else {
            switch row.style {
            case .loading:
                HStack {
                    ProgressView()
                    Text(row.value)
                }
            case .standard:
                Text(row.value)
            case .secondary:
                Text(row.value)
                    .foregroundStyle(.secondary)
            case .failure:
                Text(row.value)
                    .foregroundStyle(.red)
            case .note:
                Text(row.value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
