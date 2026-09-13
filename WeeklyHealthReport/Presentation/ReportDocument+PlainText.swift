import Foundation

extension ReportDocument {
    func plainText(
        generatedAt: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let generatedTimestamp = HealthReportFormatter.dateAndTime(
            generatedAt,
            calendar: calendar,
            locale: locale
        )
        let preamble = [
            title,
            selection,
            period,
            "Generated: \(generatedTimestamp)"
        ].joined(separator: "\n")

        let sectionText = sections.map { section in
            var lines = [section.title]
            lines += section.rows.map { row in
                if let label = row.label {
                    return "\(label): \(row.value)"
                }
                return row.value
            }
            if let footer = section.footer {
                lines.append(footer)
            }
            return lines.joined(separator: "\n")
        }

        return ([preamble] + sectionText).joined(separator: "\n\n")
    }
}
