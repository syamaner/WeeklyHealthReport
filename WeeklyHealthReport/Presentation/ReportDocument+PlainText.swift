import Foundation

extension ReportDocument {
    /// The Copy all text (README "What gets copied", docs/health-copy-all-v2.md).
    /// Since v2 (#308) it is the screen's own wording: the display document's
    /// section titles, row labels and footers (`forDisplay()`), so Copy all and
    /// the Health screen never name a metric two ways. Values and order are the
    /// document's, with one capitalised heading line before each group
    /// (`groupedSections`, #216, contract v1.1); a failed read reads
    /// "Could not read Apple Health." (or, for the food log, "Could not read
    /// the food log.") so no technical message reaches the clipboard.
    /// Developer tools keeps each read's message
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

        let groupText = forDisplay().groupedSections.flatMap { grouped in
            [Self.copyAllGroupHeading(grouped.heading)] + grouped.sections.map(Self.copyAllBlock)
        }

        return ([preamble] + groupText).joined(separator: "\n\n")
    }

    /// A group's Copy all heading: capitals, as its own block
    /// (contract decision 3), for example "DAILY ACTIVITY".
    static func copyAllGroupHeading(_ heading: String) -> String {
        heading.uppercased(with: Locale(identifier: "en_GB"))
    }

    private static func copyAllBlock(_ section: Section) -> String {
        var lines = [section.title]
        lines += section.rows.map { row in
            let value = row.style == .failure ? failureValue(row) : row.value
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
}
