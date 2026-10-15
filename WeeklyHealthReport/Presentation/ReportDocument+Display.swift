import Foundation

/// Screen copy for the Health report: the on-screen sections, the summary tiles
/// and Full Page (UX copy pass, #140).
///
/// `ReportDocument` itself is the Copy all text, whose titles and labels the
/// README specifies ("What gets copied"), so it is never reworded here. This
/// projection changes wording only: section titles and fixed row labels in
/// sentence case, plain copy for a failed read (as Copy all also says; the
/// technical message stays in Developer tools), and a note that the weight average uses the
/// last seven completed days. Values, row ids, styles and order are unchanged;
/// names that come from Apple Health (workouts, medications) are never touched.
extension ReportDocument {
    /// The same words Home uses for a failed read.
    static let readFailedMessage = "Could not read Apple Health."

    /// Weight's average covers the last seven completed days and its trend compares
    /// them with the seven before, whatever period is selected; the latest weight may be today.
    static let weightDisplayFooter =
        "Latest weight can include today. The average uses the last 7 completed days, and the trend compares them with the 7 days before, whichever period is selected."

    static let displaySectionTitles: [SectionID: String] = [
        .steps: "Steps",
        .weight: "Weight",
        .bodyComposition: "Body composition",
        .heart: "Heart",
        .bloodPressure: "Blood pressure",
        .cardiorespiratory: "Fitness and blood oxygen",
        .glucose: "Glucose",
        .activity: "Activity",
        .sleep: "Sleep",
        .medications: "Medications taken"
    ]

    /// Display labels by row id. Only rows with a fixed label are listed, so a
    /// workout or medication name is never reworded.
    static let displayRowLabels: [String: String] = [
        "steps-average": "Average daily steps",
        "steps-coverage": "Data coverage",
        "steps-trend": "Steps trend",
        "steps-total": "Weekly total",
        "weight-latest": "Latest weight",
        "weight-average": "Average, last 7 completed days",
        "weight-trend": "Weight trend",
        "body-fat-latest": "Body fat",
        "body-fat-seven-day": "7-day average",
        "body-fat-28-day": "28-day average",
        "body-fat-trend": "Body fat trend",
        "waist": "Waist circumference",
        "waist-measured": "Waist measured",
        "waist-trend": "4-week waist trend",
        "resting-heart-rate-average": "Resting heart rate average",
        "resting-heart-rate-trend": "Resting heart rate trend",
        "hrv-average": "HRV average",
        "hrv-trend": "HRV trend",
        "watch-coverage": "Days with Apple Watch data",
        "vo2-max-latest": "Latest VO₂ max",
        "vo2-max-measured": "VO₂ max measured",
        "vo2-max-four-week": "4-week average",
        "vo2-max-three-month": "3-month average",
        "vo2-max-six-month": "6-month average",
        "blood-oxygen-latest": "Latest blood oxygen",
        "blood-oxygen-measured": "Blood oxygen measured",
        "blood-oxygen-typical": "Period typical",
        "blood-oxygen-range": "Daily median range",
        "blood-oxygen-coverage": "Blood oxygen coverage",
        "glucose-average": "Daily average",
        "glucose-range": "Observed range",
        "glucose-coverage": "Data coverage",
        "active-energy": "Active energy",
        "workout-time": "Workout time",
        "sleep-average": "Average sleep"
    ]

    /// The document as the Health screen, its tiles and Full Page show it.
    /// Idempotent: applying it to a display document changes nothing.
    func forDisplay() -> ReportDocument {
        ReportDocument(
            title: title,
            selection: selection,
            period: period,
            sections: sections.map { section in
                Section(
                    id: section.id,
                    title: Self.displaySectionTitles[section.id] ?? section.title,
                    rows: section.rows.map(Self.displayRow),
                    footer: Self.displayFooter(section)
                )
            }
        )
    }

    private static func displayRow(_ row: Row) -> Row {
        let label = row.label.map { displayRowLabels[row.id] ?? $0 }
        let value = row.style == .failure ? readFailedMessage : row.value
        return Row(row.id, label: label, value: value, style: row.style)
    }

    private static func displayFooter(_ section: Section) -> String? {
        guard section.id == .weight,
              section.rows.contains(where: { $0.id == "weight-average" }),
              section.footer?.contains(weightDisplayFooter) != true else { return section.footer }
        return [section.footer, weightDisplayFooter].compactMap { $0 }.joined(separator: "\n")
    }

    private init(title: String, selection: String, period: String, sections: [Section]) {
        self.title = title
        self.selection = selection
        self.period = period
        self.sections = sections
    }
}

/// One failed Health read with its technical message, for Developer tools only.
struct ReportReadFailure: Equatable {
    let metric: String
    let message: String
}

extension ReportPresentationSnapshot {
    /// Every failed read with the message the read returned. Taken from the metric
    /// states rather than the document, because a metric row keeps only "Query failed"
    /// and drops the message, and no screen or copied text shows either.
    var readFailures: [ReportReadFailure] {
        func message<Value>(_ state: MetricState<Value>) -> String? {
            if case .failed(let message) = state { return message }
            return nil
        }
        var stepsMessage: String?
        var stepsPreviousMessage: String?
        switch steps {
        case .failed(let message): stepsMessage = message
        case .loaded(_, .previousFailed(let message)): stepsPreviousMessage = message
        default: break
        }
        let candidates: [(String, String?)] = [
            ("Steps", stepsMessage),
            ("Steps trend (previous period)", stepsPreviousMessage),
            ("Weight", message(weight)),
            ("Body fat", message(bodyFat)),
            ("Waist circumference", message(waist)),
            ("Resting heart rate", message(restingHeartRate)),
            ("HRV", message(hrv)),
            ("Days with Apple Watch data", message(watchCoverage)),
            ("Blood pressure", message(bloodPressure)),
            ("VO₂ max", message(vo2Max)),
            ("Blood oxygen", message(bloodOxygen)),
            ("Glucose", message(glucose)),
            ("Active energy", message(activeEnergy)),
            ("Exercise", message(exercise)),
            ("Workouts", message(workouts)),
            ("Sleep", message(sleep)),
            ("Medications", includesMedicationSection ? message(medications) : nil)
        ]
        return candidates.compactMap { metric, message in
            message.map { ReportReadFailure(metric: metric, message: $0) }
        }
    }
}
