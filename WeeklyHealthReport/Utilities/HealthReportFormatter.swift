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
}
