import SwiftUI

struct ReportDocumentSectionView: View {
    let section: ReportDocument.Section

    var body: some View {
        Section {
            ForEach(section.rows) { row in
                ReportDocumentRowView(row: row)
            }
        } header: {
            Text(section.title)
        } footer: {
            if let footer = section.footer {
                Text(footer)
            }
        }
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
