import Foundation

/// The Food and water section (docs/health-food-and-water-v1.md, #214). Built
/// from the local food log for the period's completed days and labelled
/// "logged": never intake, never netted against active energy, and HealthKit
/// dietary data is never read for it.
extension ReportDocument {
    static let foodLogFooter = "Logged in this app; not a measure of everything eaten or drunk."
    /// The section's read failure wording. It is distinct from the Apple Health
    /// wording, and Copy all and the screen keep it; the technical message
    /// stays in Developer tools.
    static let foodLogReadFailedMessage = "Could not read the food log."
    static let foodLogFailedRowID = "food-failed"

    static func foodLogSection(
        _ state: MetricState<FoodLogPeriodSummary>,
        locale: Locale
    ) -> Section {
        let rows: [Row]
        switch state {
        case .idle, .loading:
            rows = [Row("food-loading", value: "Reading the food log…", style: .loading)]
        case .available(let summary) where summary.reportingDayCount == 0:
            rows = [Row(
                "food-no-completed-days",
                value: "There are no completed days in this period yet.",
                style: .secondary
            )]
        case .available(let summary) where summary.loggedDayCount == 0:
            // Plain water alone is not logged food (v1.1), but its average still shows.
            var stateRows = [Row(
                "food-no-data",
                value: "No food logged in this period.",
                style: .secondary
            )]
            if summary.completeWaterDayCount + summary.incompleteWaterDayCount > 0 {
                stateRows.append(plainWaterRow(summary, locale: locale))
            }
            rows = stateRows
        case .available(let summary):
            rows = foodLogRows(summary, locale: locale)
        case .noDataOrAccess, .healthUnavailable:
            // The port never reports these; the food log is not Apple Health.
            rows = [Row(
                "food-no-data",
                value: "No food logged in this period.",
                style: .secondary
            )]
        case .failed:
            rows = [Row(foodLogFailedRowID, value: foodLogReadFailedMessage, style: .failure)]
        }
        return Section(id: .foodLog, title: "Food and water", rows: rows, footer: foodLogFooter)
    }

    private static func foodLogRows(_ summary: FoodLogPeriodSummary, locale: Locale) -> [Row] {
        var rows = [
            Row(
                "food-days-logged",
                label: "Days Logged",
                value: HealthReportFormatter.dayCoverage(
                    summary.loggedDayCount,
                    of: summary.reportingDayCount,
                    locale: locale
                )
            ),
            Row.optional(
                id: "food-energy-average",
                label: "Logged Energy",
                value: summary.averageEnergyKilocalories,
                missing: .insufficientHistory,
                format: {
                    HealthReportFormatter.loggedEnergyAverage(
                        $0,
                        completeDays: summary.completeEnergyDayCount,
                        includesEstimates: summary.energyIncludesEstimates,
                        locale: locale
                    )
                }
            )
        ]
        if summary.incompleteEnergyDayCount > 0 {
            rows.append(Row(
                "food-energy-incomplete",
                label: "Incomplete Energy Days",
                value: HealthReportFormatter.count(summary.incompleteEnergyDayCount, locale: locale)
            ))
        }
        rows.append(plainWaterRow(summary, locale: locale))
        return rows
    }

    private static func plainWaterRow(_ summary: FoodLogPeriodSummary, locale: Locale) -> Row {
        let id = "food-plain-water-average"
        let label = "Plain Water"
        let incomplete = summary.incompleteWaterDayCount
        if let average = summary.averagePlainWaterMillilitres {
            return Row(id, label: label, value: HealthReportFormatter.plainWaterAverage(
                average,
                days: summary.completeWaterDayCount,
                incompleteDays: incomplete,
                includesEstimates: summary.waterIncludesEstimates,
                locale: locale
            ))
        }
        guard incomplete > 0 else {
            return Row(id, label: label, value: MetricRowVocabulary.noData, style: .secondary)
        }
        // Plain water was logged but no day could be counted in full.
        return Row(
            id,
            label: label,
            value: "\(MetricRowVocabulary.insufficientHistory) (\(HealthReportFormatter.incompleteDays(incomplete, locale: locale)) left out)",
            style: .secondary
        )
    }

    /// The value Copy all and the screen show for a failed row: the food log
    /// keeps its own sentence; every other failure is an Apple Health read.
    static func failureValue(_ row: Row) -> String {
        row.id == foodLogFailedRowID ? foodLogReadFailedMessage : readFailedMessage
    }
}

/// Developer tools' "Food log (Health report)" lines: each reporting date's
/// inputs and classification, unrounded. Never copied or shown on the report.
enum FoodLogReportDiagnostics {
    struct Line: Equatable {
        let title: String
        let detail: String
    }

    static func lines(_ state: MetricState<FoodLogPeriodSummary>) -> [Line] {
        switch state {
        case .idle:
            return [Line(title: "State", detail: "Not read yet")]
        case .loading:
            return [Line(title: "State", detail: "Reading")]
        case .noDataOrAccess, .healthUnavailable:
            return [Line(title: "State", detail: "No data")]
        case .failed(let message):
            return [Line(title: "Read failed", detail: message)]
        case .available(let summary):
            var lines = [
                Line(title: "Policy", detail: FoodLogPeriodSummary.policy),
                Line(
                    title: "Days",
                    detail: "\(summary.loggedDayCount) logged of \(summary.reportingDayCount); energy \(summary.completeEnergyDayCount) complete, \(summary.incompleteEnergyDayCount) incomplete; plain water \(summary.completeWaterDayCount) complete, \(summary.incompleteWaterDayCount) incomplete"
                ),
                Line(
                    title: "Energy mean",
                    detail: summary.averageEnergyKilocalories.map { "\(number($0)) kcal, estimates \(yesNo(summary.energyIncludesEstimates))" } ?? "none"
                ),
                Line(
                    title: "Plain water mean",
                    detail: summary.averagePlainWaterMillilitres.map { "\(number($0)) mL, estimates \(yesNo(summary.waterIncludesEstimates))" } ?? "none"
                )
            ]
            lines += summary.days.map { day in
                Line(title: day.reportingDate, detail: dayDetail(day))
            }
            return lines
        }
    }

    private static func dayDetail(_ day: FoodLogPeriodSummary.Day) -> String {
        let facts = day.facts
        let entries = facts?.entryCount ?? 0
        let food = facts?.foodEntryCount ?? 0
        let energy = facts?.energy.map { total in
            "energy \(total.knownAmount.map { "\(number($0)) kcal" } ?? "unknown"), \(total.incompleteContributions) incomplete, estimates \(yesNo(total.includesEstimates))"
        } ?? "energy none"
        let water = facts?.plainWater.map { total in
            "plain water \(total.knownAmount.map { "\(number($0)) mL" } ?? "unknown"), \(total.incompleteContributions) incomplete, estimates \(yesNo(total.includesEstimates))"
        } ?? "plain water none"
        return "\(entries) \(entries == 1 ? "entry" : "entries") (\(food) food); \(energy); \(water); \(energyClass(day.energy)), \(waterClass(day.water))"
    }

    private static func energyClass(_ day: FoodLogPeriodSummary.EnergyDay) -> String {
        switch day {
        case .notLogged: "not logged"
        case .complete: "energy complete"
        case .incomplete: "energy incomplete"
        }
    }

    private static func waterClass(_ day: FoodLogPeriodSummary.WaterDay) -> String {
        switch day {
        case .noPlainWater: "no plain water"
        case .complete: "water complete"
        case .incomplete: "water incomplete"
        }
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...3)))
    }

    private static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
}
