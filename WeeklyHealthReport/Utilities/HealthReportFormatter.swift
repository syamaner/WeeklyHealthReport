import Foundation

enum HealthReportFormatter {
    static func integer(
        _ value: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(0)))
    }

    static func stepCoverage(_ summary: StepSummary) -> String {
        "\(summary.daysWithVisibleData) / \(summary.reportingDayCount) days"
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

    static func vo2Max(
        _ millilitresPerKilogramMinute: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let value = millilitresPerKilogramMinute.formatted(
            .number.locale(locale).precision(.fractionLength(1))
        )
        return "\(value) mL/kg/min"
    }

    static func vo2MaxWindow(
        _ window: VO2MaxWindowSummary,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let days = "\(window.sampledDayCount) day\(window.sampledDayCount == 1 ? "" : "s")"
        guard let average = window.average else {
            return "Insufficient data (\(days))"
        }
        return "\(vo2Max(average, locale: locale)) (\(days))"
    }

    static func bloodOxygen(
        _ percentage: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let value = percentage.formatted(
            .number.locale(locale).precision(.fractionLength(0))
        )
        return "\(value)%"
    }

    static func bloodOxygenRange(
        minimum: Double,
        maximum: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let lower = minimum.formatted(
            .number.locale(locale).precision(.fractionLength(0))
        )
        let upper = maximum.formatted(
            .number.locale(locale).precision(.fractionLength(0))
        )
        return "\(lower)–\(upper)%"
    }

    static func bloodPressure(
        systolic: Double,
        diastolic: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let format = FloatingPointFormatStyle<Double>.number
            .locale(locale)
            .precision(.fractionLength(0...1))
        return "\(systolic.formatted(format))/\(diastolic.formatted(format)) mmHg"
    }

    static func bloodPressureBatch(
        _ batch: BloodPressureBatchSummary,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        // Retained until the final rendering-consolidation cleanup phase.
        let count = batch.readingCount == 1
            ? "1 reading"
            : "\(batch.readingCount) readings"
        return "\(bloodPressure(systolic: batch.averageSystolic, diastolic: batch.averageDiastolic, locale: locale)) (\(count), \(dateAndTime(batch.latestReadingDate, calendar: calendar, locale: locale)))"
    }

    static func bloodPressureCoverage(
        _ summary: BloodPressurePeriodSlotSummary
    ) -> String {
        // Retained until the final rendering-consolidation cleanup phase.
        let readings = summary.readingCount == 1
            ? "1 paired reading"
            : "\(summary.readingCount) paired readings"
        return "\(summary.sampledDayCount) / \(summary.reportingDayCount) days; \(readings)"
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

    static func medicationDose(
        quantity: Double?,
        unitLabel: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let quantity else { return "Dose logged" }
        let value = quantity.formatted(
            .number.locale(locale).precision(.fractionLength(0...2))
        )
        let displayedUnit: String
        if unitLabel == "dose" {
            displayedUnit = quantity == 1 ? "dose" : "doses"
        } else {
            // HealthKit symbols such as mg and mL are not pluralised.
            displayedUnit = unitLabel
        }
        return "\(value) \(displayedUnit)"
    }

    static func medicationGroupDetail(
        _ group: MedicationDoseGroup,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let latest = group.latestDose
        let dose = medicationDose(
            quantity: latest.quantity,
            unitLabel: latest.unitLabel,
            locale: locale
        )
        let countLabel = group.count == 1 ? "1 taken event" : "\(group.count) taken events"
        return "\(dose) at \(dateAndTime(latest.date, calendar: calendar, locale: locale)); \(countLabel)"
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

    static func dateAndTime(
        _ date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yy - HH:mm"
        return formatter.string(from: date)
    }

    static func workoutDateAndTime(
        _ date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        dateAndTime(date, calendar: calendar)
    }
}
