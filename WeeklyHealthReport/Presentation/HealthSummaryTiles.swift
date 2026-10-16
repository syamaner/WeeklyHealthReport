import Foundation

extension ReportPresentationSnapshot {
    /// The same snapshot with every optional detail shown. Copy all, Full Page
    /// and the Health summary tiles use this so their content never depends on
    /// what is expanded on screen.
    func withAllDetailsExpanded() -> ReportPresentationSnapshot {
        ReportPresentationSnapshot(
            period: period,
            steps: steps,
            weight: weight,
            bodyFat: bodyFat,
            waist: waist,
            glucose: glucose,
            vo2Max: vo2Max,
            bloodOxygen: bloodOxygen,
            bloodPressure: bloodPressure,
            restingHeartRate: restingHeartRate,
            hrv: hrv,
            watchCoverage: watchCoverage,
            exercise: exercise,
            activeEnergy: activeEnergy,
            workouts: workouts,
            sleep: sleep,
            medications: medications,
            foodLog: foodLog,
            includesMedicationSection: includesMedicationSection,
            showsMorningBloodPressureDetails: true,
            showsEveningBloodPressureDetails: true
        )
    }
}

extension ReportDocument {
    /// The one fully expanded document behind Copy all, Full Page and the
    /// summary tiles.
    static func expanded(
        snapshot: ReportPresentationSnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> ReportDocument {
        ReportDocument(
            snapshot: snapshot.withAllDetailsExpanded(),
            calendar: calendar,
            locale: locale
        )
    }
}

/// A Health summary tile. It repeats rows of the expanded display document
/// (`ReportDocument.expanded(...).forDisplay()`) verbatim (failures use the short
/// "Could not read" term): no new metric, query, threshold, colour coding or
/// interpretation, and it never appears in copied text or Full Page.
struct HealthSummaryTile: Equatable, Identifiable {
    enum Kind: String, CaseIterable {
        case steps
        case sleep
        case restingHeartRate
        case weight
        case morningBloodPressure
        case loggedEnergy
    }

    let kind: Kind
    let title: String
    let primary: ReportDocument.Row
    let detail: ReportDocument.Row?
    /// A trend line under the detail, copied verbatim from its row (steps only).
    let trend: ReportDocument.Row?

    init(
        kind: Kind,
        title: String,
        primary: ReportDocument.Row,
        detail: ReportDocument.Row?,
        trend: ReportDocument.Row? = nil
    ) {
        self.kind = kind
        self.title = title
        self.primary = primary
        self.detail = detail
        self.trend = trend
    }

    var id: Kind { kind }
}

enum HealthSummaryTiles {
    struct Pin: Equatable {
        let kind: HealthSummaryTile.Kind
        let title: String
        let section: ReportDocument.SectionID
        let primaryRowID: String
        let detailRowID: String?
        var trendRowID: String?
        /// A tile label for the primary row when the row's own label would only
        /// repeat the tile title (Logged energy).
        var primaryLabel: String?
    }

    /// Row ids are pinned so a renamed row fails the tile tests rather than
    /// silently disappearing from the summary.
    static let pins: [Pin] = [
        Pin(
            kind: .steps,
            title: "Steps",
            section: .steps,
            primaryRowID: "steps-average",
            detailRowID: "steps-coverage",
            trendRowID: "steps-trend"
        ),
        Pin(
            kind: .sleep,
            title: "Sleep",
            section: .sleep,
            primaryRowID: "sleep-average",
            detailRowID: nil
        ),
        Pin(
            kind: .restingHeartRate,
            title: "Resting heart rate",
            section: .heart,
            primaryRowID: "resting-heart-rate-average",
            detailRowID: "resting-heart-rate-trend"
        ),
        Pin(
            kind: .weight,
            title: "Weight",
            section: .weight,
            primaryRowID: "weight-average",
            detailRowID: "weight-trend"
        ),
        Pin(
            kind: .morningBloodPressure,
            title: "Morning blood pressure",
            section: .bloodPressure,
            primaryRowID: "blood-pressure-morning-average",
            detailRowID: "blood-pressure-morning-coverage"
        ),
        // Food and water (#214, decision 4): logged energy with days logged.
        Pin(
            kind: .loggedEnergy,
            title: "Logged energy",
            section: .foodLog,
            primaryRowID: "food-energy-average",
            detailRowID: "food-days-logged",
            primaryLabel: "Average per day"
        )
    ]

    /// Pass the expanded display document (`ReportDocument.expanded(...).forDisplay()`),
    /// never the on-screen one: some detail rows exist only when details are shown.
    static func make(from document: ReportDocument) -> [HealthSummaryTile] {
        pins.compactMap { pin in
            guard let section = document.sections.first(where: { $0.id == pin.section }) else {
                return nil
            }
            if let primary = section.rows.first(where: { $0.id == pin.primaryRowID }) {
                let detail = pin.detailRowID.flatMap { id in
                    section.rows.first { $0.id == id }
                }
                let trend = pin.trendRowID.flatMap { id in
                    section.rows.first { $0.id == id }
                }
                let labelled = pin.primaryLabel.map {
                    ReportDocument.Row(primary.id, label: $0, value: primary.value, style: primary.style)
                } ?? primary
                return HealthSummaryTile(
                    kind: pin.kind,
                    title: pin.title,
                    primary: shortFailure(labelled),
                    detail: detail.map(shortFailure),
                    trend: trend.map(shortFailure)
                )
            }
            // The section reports a state instead of values.
            guard let stateRow = section.rows.first else { return nil }
            return HealthSummaryTile(
                kind: pin.kind,
                title: pin.title,
                primary: pin.section == .steps || pin.section == .foodLog
                    ? stepsStateRow(stateRow)
                    : shortFailure(stateRow),
                detail: nil
            )
        }
    }

    /// A failure shows the shared short term in a tile; the section row says
    /// "Could not read Apple Health." (as Copy all does) and the technical message
    /// stays in Developer tools. Every other row is copied verbatim.
    private static func shortFailure(_ row: ReportDocument.Row) -> ReportDocument.Row {
        guard row.style == .failure else { return row }
        return ReportDocument.Row(
            row.id,
            label: row.label,
            value: MetricRowVocabulary.couldNotRead,
            style: row.style
        )
    }

    /// Steps (and Food and water) state rows are full sentences; the tile shows
    /// the shared short term for the same state, keeping each state distinct.
    private static func stepsStateRow(_ row: ReportDocument.Row) -> ReportDocument.Row {
        let value: String
        switch row.id {
        case "steps-loading": value = MetricRowVocabulary.loading
        case "steps-no-data": value = MetricRowVocabulary.noData
        case "steps-unavailable": value = MetricRowVocabulary.unavailable
        case "steps-no-completed-days": value = MetricRowVocabulary.noCompletedDays
        case "steps-failed": value = MetricRowVocabulary.couldNotRead
        // Food and water: the shared short terms for loading and no completed
        // days. "No food logged in this period." stays as it is, distinct from
        // "No data", and a failure uses "Could not read".
        case "food-loading": value = MetricRowVocabulary.loading
        case "food-no-completed-days": value = MetricRowVocabulary.noCompletedDays
        case ReportDocument.foodLogFailedRowID: value = MetricRowVocabulary.couldNotRead
        default: return row
        }
        return ReportDocument.Row(row.id, label: row.label, value: value, style: row.style)
    }
}
