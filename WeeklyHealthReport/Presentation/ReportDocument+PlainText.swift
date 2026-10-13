import Foundation

extension ReportDocument {
    /// The Copy all text (README "What gets copied"). Labels, values and order are
    /// the document's own; only a failed read is reworded to
    /// "Could not read Apple Health." so no technical message reaches the
    /// clipboard. Developer tools keeps each read's message
    /// (`ReportPresentationSnapshot.readFailures`).
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
                let value = row.style == .failure ? Self.readFailedMessage : row.value
                if let label = row.label {
                    return "\(label): \(value)"
                }
                return value
            }
            if let footer = section.footer {
                lines.append(footer)
            }
            return lines.joined(separator: "\n")
        }

        return ([preamble] + sectionText).joined(separator: "\n\n")
    }
}
