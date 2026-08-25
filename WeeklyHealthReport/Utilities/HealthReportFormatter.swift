import Foundation

enum HealthReportFormatter {
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

    static func bmi(
        _ value: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        value.formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(1))
        )
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
}
