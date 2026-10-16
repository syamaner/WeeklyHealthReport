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

/// A heading over a group of Health sections (#216, contract v1.1). It is a
/// plain row rather than a section header, so list header styling (grey,
/// small) cannot override it and it stays distinct from the section headers
/// below it. It holds no rows and collapses nothing; each section keeps its
/// own disclosure.
struct ReportGroupHeading: View {
    let heading: String

    var body: some View {
        Section {
            Text(heading)
                .font(.title2.bold())
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 16, leading: 4, bottom: 0, trailing: 4))
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
