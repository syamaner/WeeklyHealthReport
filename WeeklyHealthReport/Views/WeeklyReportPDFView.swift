import SwiftUI

struct WeeklyReportPDFView: View {
    let document: WeeklyReportPDFDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(document.title)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.black)
                .padding(.bottom, 8)

            Text(document.selection)
                .font(.headline)
                .foregroundStyle(Color.black)
            Text(document.period)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .padding(.bottom, 24)

            ForEach(document.sections) { section in
                reportSection(section)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func reportSection(_ section: WeeklyReportPDFDocument.Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.title2.bold())
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)

            Divider()
                .overlay(Color.black.opacity(0.35))

            ForEach(section.rows) { row in
                reportRow(row)
                    .padding(.vertical, 6)
                Divider()
                    .overlay(Color.black.opacity(0.12))
            }

            if let footer = section.footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func reportRow(_ row: WeeklyReportPDFDocument.Row) -> some View {
        if let label = row.label {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(label)
                    .font(.body)
                    .foregroundStyle(rowColor(row.style))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text(row.value)
                    .font(.body)
                    .foregroundStyle(rowColor(row.style))
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(row.value)
                .font(row.style == .note ? .footnote : .body)
                .foregroundStyle(rowColor(row.style))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rowColor(_ style: WeeklyReportPDFDocument.RowStyle) -> Color {
        switch style {
        case .standard:
            .black
        case .secondary, .note:
            Color(white: 0.28)
        case .failure:
            Color(red: 0.65, green: 0, blue: 0)
        }
    }
}
