import SwiftUI

struct WeeklyReportPDFView: View {
    let document: ReportDocument

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

            ForEach(document.groupedSections) { grouped in
                if let heading = grouped.heading {
                    Text(heading)
                        .font(.title.bold())
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                }
                ForEach(grouped.sections) { section in
                    reportSection(section)
                }
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func reportSection(_ section: ReportDocument.Section) -> some View {
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
    private func reportRow(_ row: ReportDocument.Row) -> some View {
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

    private func rowColor(_ style: ReportDocument.RowStyle) -> Color {
        switch style {
        case .standard:
            .black
        case .loading, .secondary, .note:
            Color(white: 0.28)
        case .failure:
            Color(red: 0.65, green: 0, blue: 0)
        }
    }
}

/// Today's Full Page: Home's cards as plain text on a white page, in the same
/// visual style as the Health report's Full Page.
struct TodayFullPagePDFView: View {
    let document: TodayFullPageDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TodayFullPageDocument.title)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.black)
                .padding(.bottom, 8)

            Text(document.date)
                .font(.headline)
                .foregroundStyle(Color.black)
                .padding(.bottom, 24)

            ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                todaySection(section)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func todaySection(_ section: TodayFullPageDocument.Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.title2.bold())
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)

            Divider()
                .overlay(Color.black.opacity(0.35))

            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                todayRow(row)
                    .padding(.vertical, 6)
                Divider()
                    .overlay(Color.black.opacity(0.12))
            }

            if let footer = section.footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Color(white: 0.28))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func todayRow(_ row: TodayFullPageDocument.Row) -> some View {
        if let label = row.label {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.body)
                        .foregroundStyle(Color.black)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = row.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Color(white: 0.28))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                Text(row.value)
                    .font(.body)
                    .foregroundStyle(Color.black)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(row.value)
                .font(.body)
                .foregroundStyle(Color.black)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
