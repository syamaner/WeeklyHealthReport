import Foundation

/// One row of Home's "Health · today so far" card, ready to render. Foundation
/// only (Tools/check-app-boundaries.sh); nothing absent ever reads as 0.
struct TodaySoFarHealthRow: Equatable, Identifiable {
    enum Kind: String, CaseIterable {
        case steps, activeEnergy, sleep, weight, bloodPressure
    }

    enum Status: Equatable {
        case loading, available, noData, failed
    }

    let kind: Kind
    let title: String
    let value: String
    let accessibilityLabel: String
    let status: Status

    var id: Kind { kind }
}

/// The whole card: "Apple Health is not available", one "Could not read Apple
/// Health." when every read failed (said once, not on every row), or five rows.
struct TodaySoFarHealthCard: Equatable {
    enum Content: Equatable {
        case unavailable(String)
        case failed(String)
        case rows([TodaySoFarHealthRow])
    }

    let content: Content
    let footer: String
    /// "As of 14:32" once a refresh has completed.
    let asOf: String?

    static func make(
        projection: TodaySoFarHealthProjection?,
        windowFailed: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) -> TodaySoFarHealthCard {
        let footer = HealthReportFormatter.todaySoFarFooter
        // No value for today yet: loading (including while authorisation is
        // requested), or failed when the window itself could not be computed.
        guard let projection else {
            if windowFailed {
                return TodaySoFarHealthCard(
                    content: .failed(HealthReportFormatter.todaySoFarFailed), footer: footer, asOf: nil)
            }
            return TodaySoFarHealthCard(
                content: .rows(TodaySoFarHealthRow.Kind.allCases.map { placeholder($0, status: .loading) }),
                footer: footer,
                asOf: nil
            )
        }
        let asOf = HealthReportFormatter.todaySoFarAsOf(
            projection.window.asOf, calendar: projection.window.calendar, locale: locale)
        if projection.isHealthUnavailable {
            return TodaySoFarHealthCard(
                content: .unavailable(HealthReportFormatter.todaySoFarUnavailable), footer: footer, asOf: asOf)
        }
        let window = projection.window
        let calendar = window.calendar
        let rows = [
            row(.steps, projection.steps) { steps in
                let value = HealthReportFormatter.todaySoFarSteps(steps.count, locale: locale)
                return (value, value)
            },
            row(.activeEnergy, projection.activeEnergyKilocalories) { kilocalories in
                (HealthReportFormatter.todaySoFarActiveEnergy(kilocalories, locale: locale),
                 HealthReportFormatter.todaySoFarActiveEnergySpoken(kilocalories, locale: locale))
            },
            row(.sleep, projection.sleep, noData: HealthReportFormatter.todaySoFarSleepNoData) { sleep in
                (HealthReportFormatter.todaySoFarSleep(seconds: sleep.asleepSeconds, isComplete: sleep.isComplete),
                 HealthReportFormatter.todaySoFarSleepSpoken(seconds: sleep.asleepSeconds, isComplete: sleep.isComplete))
            },
            row(.weight, projection.latestWeight) { weight in
                let time = HealthReportFormatter.todaySoFarTime(
                    weight.date, asOf: window.asOf, calendar: calendar, locale: locale)
                let kilograms = HealthReportFormatter.weightKilograms(weight.kilograms, locale: locale)
                    .replacingOccurrences(of: " kg", with: " kilograms")
                return (HealthReportFormatter.todaySoFarWeight(
                    weight, asOf: window.asOf, calendar: calendar, locale: locale), "\(kilograms), \(time)")
            },
            row(.bloodPressure, projection.latestBloodPressure) { reading in
                let time = HealthReportFormatter.todaySoFarTime(
                    reading.date, asOf: window.asOf, calendar: calendar, locale: locale)
                let format = FloatingPointFormatStyle<Double>.number.locale(locale).precision(.fractionLength(0...1))
                let spoken = "\(reading.systolicMillimetresOfMercury.formatted(format)) over "
                    + "\(reading.diastolicMillimetresOfMercury.formatted(format)) millimetres of mercury, \(time)"
                return (HealthReportFormatter.todaySoFarBloodPressure(
                    reading, asOf: window.asOf, calendar: calendar, locale: locale), spoken)
            }
        ]
        if rows.allSatisfy({ $0.status == .failed }) {
            return TodaySoFarHealthCard(
                content: .failed(HealthReportFormatter.todaySoFarFailed), footer: footer, asOf: asOf)
        }
        return TodaySoFarHealthCard(content: .rows(rows), footer: footer, asOf: asOf)
    }

    static func title(_ kind: TodaySoFarHealthRow.Kind) -> String {
        switch kind {
        case .steps: "Steps"
        case .activeEnergy: "Active energy"
        case .sleep: "Sleep"
        case .weight: "Weight"
        case .bloodPressure: "Blood pressure"
        }
    }

    private static func placeholder(_ kind: TodaySoFarHealthRow.Kind, status: TodaySoFarHealthRow.Status) -> TodaySoFarHealthRow {
        let title = title(kind)
        return TodaySoFarHealthRow(kind: kind, title: title, value: "", accessibilityLabel: "\(title), loading", status: .loading)
    }

    private static func failedRow(_ kind: TodaySoFarHealthRow.Kind) -> TodaySoFarHealthRow {
        let title = title(kind)
        return TodaySoFarHealthRow(
            kind: kind, title: title, value: HealthReportFormatter.todaySoFarFailed,
            accessibilityLabel: "\(title), \(spoken(HealthReportFormatter.todaySoFarFailed))", status: .failed)
    }

    /// Lower-cases the first letter so a message reads as one sentence after the title.
    private static func spoken(_ message: String) -> String {
        message.prefix(1).lowercased() + message.dropFirst()
    }

    private static func row<Value>(
        _ kind: TodaySoFarHealthRow.Kind,
        _ read: TodaySoFarRead<Value>,
        noData: String = HealthReportFormatter.todaySoFarNoData,
        available: (Value) -> (value: String, spoken: String)
    ) -> TodaySoFarHealthRow {
        let title = title(kind)
        switch read {
        case .value(let value):
            let text = available(value)
            return TodaySoFarHealthRow(
                kind: kind, title: title, value: text.value,
                accessibilityLabel: "\(title), \(text.spoken)", status: .available)
        case .noData:
            let spoken = noData == HealthReportFormatter.todaySoFarNoData
                ? HealthReportFormatter.todaySoFarNoDataDetail : noData
            return TodaySoFarHealthRow(
                kind: kind, title: title, value: noData,
                accessibilityLabel: "\(title), \(Self.spoken(spoken))", status: .noData)
        case .failed, .healthUnavailable:
            return failedRow(kind)
        }
    }
}
