import Foundation

enum HealthReportFormatter {
    static func integer(
        _ value: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(0)))
    }

    static func weightKilograms(
        _ kilograms: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let value = kilograms.formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(1))
        )
        return "\(value) kg"
    }

    static func percentage(
        _ percentage: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let value = percentage.formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(1))
        )
        return "\(value)%"
    }

    static func waistCentimetres(
        _ centimetres: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let value = centimetres.formatted(
            .number.locale(locale).precision(.fractionLength(1))
        )
        return "\(value) cm"
    }

    static func glucose(
        _ millimolesPerLiter: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let value = millimolesPerLiter.formatted(
            .number.locale(locale).precision(.fractionLength(1))
        )
        return "\(value) mmol/L"
    }

    static func glucoseRange(
        minimum: Double,
        maximum: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let lower = minimum.formatted(
            .number.locale(locale).precision(.fractionLength(1))
        )
        let upper = maximum.formatted(
            .number.locale(locale).precision(.fractionLength(1))
        )
        return "\(lower)–\(upper) mmol/L"
    }

    static func percentagePointTrend(
        _ value: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let magnitude = abs(value).formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(1))
        )
        if value < 0 {
            return "↓ \(magnitude) pp vs previous 28d"
        }
        if value > 0 {
            return "↑ \(magnitude) pp vs previous 28d"
        }
        return "No change vs previous 28d"
    }

    static func signedChange(
        _ value: Double,
        unit: String,
        comparison: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let magnitude = abs(value).formatted(
            .number.locale(locale).precision(.fractionLength(1))
        )
        let sign = value < 0 ? "-" : value > 0 ? "+" : ""
        return "\(sign)\(magnitude) \(unit) vs \(comparison)"
    }

    static func heartRate(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        "\(integer(value, locale: locale)) bpm"
    }

    static func hrvMilliseconds(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        "\(integer(value, locale: locale)) ms"
    }

    static func minutes(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        "\(integer(value, locale: locale)) min"
    }

    static func energyKilocalories(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        "\(integer(value, locale: locale)) kcal"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((interval / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    static func period(
        _ period: ReportPeriod,
        calendar suppliedCalendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let lastDay = suppliedCalendar.date(byAdding: .day, value: -1, to: period.interval.end)
        else { return "Unavailable" }
        let start = period.interval.start
        let sameYear = suppliedCalendar.component(.year, from: start) == suppliedCalendar.component(.year, from: lastDay)
        let sameMonth = sameYear && suppliedCalendar.component(.month, from: start) == suppliedCalendar.component(.month, from: lastDay)

        func formatted(_ date: Date, template: String) -> String {
            let formatter = DateFormatter()
            formatter.calendar = suppliedCalendar
            formatter.timeZone = suppliedCalendar.timeZone
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: date)
        }

        if sameMonth {
            return "\(formatted(start, template: "d"))–\(formatted(lastDay, template: "dMMMyyyy"))"
        }
        if sameYear {
            return "\(formatted(start, template: "dMMM"))–\(formatted(lastDay, template: "dMMMyyyy"))"
        }
        return "\(formatted(start, template: "dMMMyyyy"))–\(formatted(lastDay, template: "dMMMyyyy"))"
    }

    static func clipboardReport(
        _ report: WeeklyReportSnapshot,
        generatedAt: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let bodyFatTrend: String
        if let trend = report.bodyFat?.trendPercentagePoints {
            let magnitude = abs(trend).formatted(
                .number.locale(locale).precision(.fractionLength(1))
            )
            let sign = trend < 0 ? "-" : trend > 0 ? "+" : ""
            bodyFatTrend = "\(sign)\(magnitude) pp vs previous 28d"
        } else {
            bodyFatTrend = "Insufficient history"
        }
        let comparison = "previous \(report.period.completedDays.count)d"

        let lines = [
            "Weekly Health Report",
            period(report.period, calendar: calendar, locale: locale),
            "Generated: \(dateAndTime(generatedAt, calendar: calendar, locale: locale))",
            "",
            "Latest Weight: \(report.weight.map { weightKilograms($0.latest.kilograms, locale: locale) } ?? "No data")",
            "Weight Recorded: \(report.weight.map { dateAndTime($0.latest.date, calendar: calendar, locale: locale) } ?? "No data")",
            "Weight 7-day Avg: \(report.weight?.currentSevenDayAverage.map { weightKilograms($0, locale: locale) } ?? "Insufficient history")",
            "Weight Trend: \(report.weight?.trendKilograms.map { signedChange($0, unit: "kg", comparison: "previous 7d", locale: locale) } ?? "Insufficient history")",
            "Body Fat: \(report.bodyFat.map { percentage($0.latest.percentage, locale: locale) } ?? "No data")",
            "Body Fat 28-day Avg: \(report.bodyFat?.current28DayAverage.map { percentage($0, locale: locale) } ?? "Insufficient history")",
            "Body Fat Trend: \(bodyFatTrend)",
            "Waist Circumference: \(report.waist.map { waistCentimetres($0.latest.centimetres, locale: locale) } ?? "No data")",
            "Waist Recorded: \(report.waist.map { dateAndTime($0.latest.date, calendar: calendar, locale: locale) } ?? "No data")",
            "Glucose Daily Average: \(report.glucose.map { glucose($0.averageMillimolesPerLiter, locale: locale) } ?? "No data")",
            "Glucose Observed Range: \(report.glucose.map { glucoseRange(minimum: $0.minimumMillimolesPerLiter, maximum: $0.maximumMillimolesPerLiter, locale: locale) } ?? "No data")",
            "Glucose Data Coverage: \(report.glucose.map { "\($0.validDayCount) / \($0.reportingDayCount) days" } ?? "No data")",
            "Average Daily Steps: \(report.steps.map { integer($0.averageDailySteps, locale: locale) } ?? "No data")",
            "Resting HR Average: \(report.restingHeartRate.map { heartRate($0.current.average, locale: locale) } ?? "No data")",
            "Resting HR Trend: \(report.restingHeartRate?.trend.map { signedChange($0, unit: "bpm", comparison: comparison, locale: locale) } ?? "Insufficient history")",
            "HRV Average: \(report.hrv.map { hrvMilliseconds($0.current.average, locale: locale) } ?? "No data")",
            "HRV Trend: \(report.hrv?.trend.map { signedChange($0, unit: "ms", comparison: comparison, locale: locale) } ?? "Insufficient history")",
            "Watch Data Coverage: \(report.watchCoverage.map { "\($0.daysWithWatchData) / \($0.reportingDayCount) days" } ?? "No data")",
            "Average Sleep: \(report.sleep.map { duration($0.averageDuration) } ?? "No data")",
            "Active Energy: \(report.activeEnergyKilocalories.map { energyKilocalories($0, locale: locale) } ?? "No data")",
            "Exercise: \(report.exerciseMinutes.map { minutes($0, locale: locale) } ?? "No data")",
            "Workouts: \(report.workouts.map { String($0.count) } ?? "No data")"
        ]
        let workoutLines = report.workouts?.workouts.map {
            "Workout: \($0.activityName) — \(duration($0.duration))"
        } ?? ["Workout Details: No data"]
        return (lines + workoutLines).joined(separator: "\n")
    }

    static func dateAndTime(
        _ date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
