import Foundation

/// One food-log reporting date as plain facts (docs/health-food-and-water-v1.md,
/// section 6). Built by the composition root's adapter from the existing Food Log
/// read side (`FoodLogDayContent`); no FoodLedgerKit, store or SwiftUI type
/// appears here.
struct FoodLogDayFacts: Equatable, Sendable {
    /// A day total under the summary policy `food-intake-summary-v4` (v3 rules; the v4 overflow flag is not shown here).
    struct Total: Equatable, Sendable {
        /// The known amount; nil when no contribution could be scaled.
        let knownAmount: Double?
        /// Contributions that could not be counted. Above zero, `knownAmount`
        /// is only a known minimum.
        let incompleteContributions: Int
        let includesEstimates: Bool
    }

    /// `yyyy-MM-dd` in the report's calendar and time zone.
    let reportingDate: String
    /// Current entries on the date, plain water included. Superseded and
    /// removed versions are not counted.
    let entryCount: Int
    /// Current entries that are not plain water. A day with only plain water is
    /// not a logged food day (contract v1.1, owner decision 7).
    let foodEntryCount: Int
    /// Logged energy in kcal over the day's food entries (plain water entries
    /// excluded). Nil when the day has no current food entry (not logged;
    /// never zero).
    let energy: Total?
    /// Plain water in mL (plain water entries only, never water in foods). Nil
    /// when no plain water was logged (no data; never 0 mL).
    let plainWater: Total?
    /// Logged fibre in g over the day's food entries (contract v1.2, #288).
    /// Plain water contributes exactly 0 g, and an unscalable plain water
    /// entry is not an incomplete fibre contribution. Nil means no fibre total
    /// was read, which a logged day treats as unknown fibre (never 0 g).
    var fibre: Total? = nil
}

/// The Health report's Food and water figures for the selected completed days
/// (policy `health_food_log_period_v1`). Pure: the same day facts always give
/// the same summary.
struct FoodLogPeriodSummary: Equatable, Sendable {
    static let policy = "health_food_log_period_v1"

    /// Contract section 2, energy column.
    enum EnergyDay: Equatable, Sendable {
        /// No current food entry (nothing, or plain water only). Not zero, and
        /// not in the energy average or the incomplete count.
        case notLogged
        /// Every contribution counted; the day enters the average.
        case complete(kilocalories: Double)
        /// At least one unknown contribution. The known subtotal is only a
        /// minimum, so the day is left out of the average and counted.
        case incomplete
    }

    /// Contract section 2, water column.
    enum WaterDay: Equatable, Sendable {
        /// No plain water logged. Not 0 mL.
        case noPlainWater
        case complete(millilitres: Double)
        /// A plain water entry could not be scaled. Left out of the average and counted.
        case incomplete
    }

    /// Contract v1.2 (#288), fibre column: the energy rule applied to fibre
    /// (owner decision 9).
    enum FibreDay: Equatable, Sendable {
        /// No current food entry. Not 0 g, and not in the fibre average or the
        /// incomplete count (a water-only day stays outside, as in v1.1).
        case notLogged
        /// Every fibre contribution counted; the day enters the fibre average.
        case complete(grams: Double)
        /// Any unknown fibre contribution, or no known fibre at all. Left out
        /// of the average and counted.
        case incomplete
    }

    struct Day: Equatable, Sendable {
        let reportingDate: String
        /// Nil when the reader returned nothing for the date (treated as not logged).
        let facts: FoodLogDayFacts?
        let energy: EnergyDay
        let water: WaterDay
        let fibre: FibreDay
    }

    /// One entry per completed day in the period, in order.
    let days: [Day]
    /// Completed days in the period (today is never one).
    var reportingDayCount: Int { days.count }
    /// Days with at least one current food entry. Plain water alone does not
    /// make a logged day.
    let loggedDayCount: Int
    let completeEnergyDayCount: Int
    let incompleteEnergyDayCount: Int
    /// Mean of complete days' energy, each day weighted equally. Nil when no
    /// day is complete. Unrounded; presentation rounds.
    let averageEnergyKilocalories: Double?
    /// Any day in the energy average includes estimates.
    let energyIncludesEstimates: Bool
    let completeFibreDayCount: Int
    let incompleteFibreDayCount: Int
    /// Mean of complete fibre days' grams, each day weighted equally. Nil when
    /// no day is complete. Unrounded; presentation rounds.
    let averageFibreGrams: Double?
    /// Any day in the fibre average includes estimates.
    let fibreIncludesEstimates: Bool
    let completeWaterDayCount: Int
    let incompleteWaterDayCount: Int
    /// Mean over complete plain water days. Nil when there is none. Unrounded.
    let averagePlainWaterMillilitres: Double?
    /// Any day in the plain water average includes estimates.
    let waterIncludesEstimates: Bool

    /// Matches facts to `reportingDates` by stored reporting date. Facts for a
    /// date outside the period (for example today) are ignored; a date with no
    /// facts is not logged.
    static func make(days facts: [FoodLogDayFacts], reportingDates: [String]) -> FoodLogPeriodSummary {
        let byDate = Dictionary(facts.map { ($0.reportingDate, $0) }, uniquingKeysWith: { first, _ in first })
        let days = reportingDates.map { date in
            let fact = byDate[date]
            return Day(
                reportingDate: date,
                facts: fact,
                energy: energyDay(fact),
                water: waterDay(fact),
                fibre: fibreDay(fact)
            )
        }

        var energyValues: [Double] = []
        var energyEstimates = false
        var fibreValues: [Double] = []
        var fibreEstimates = false
        var waterValues: [Double] = []
        var waterEstimates = false
        for day in days {
            if case .complete(let kilocalories) = day.energy {
                energyValues.append(kilocalories)
                energyEstimates = energyEstimates || day.facts?.energy?.includesEstimates == true
            }
            if case .complete(let grams) = day.fibre {
                fibreValues.append(grams)
                fibreEstimates = fibreEstimates || day.facts?.fibre?.includesEstimates == true
            }
            if case .complete(let millilitres) = day.water {
                waterValues.append(millilitres)
                waterEstimates = waterEstimates || day.facts?.plainWater?.includesEstimates == true
            }
        }

        return FoodLogPeriodSummary(
            days: days,
            loggedDayCount: days.filter { $0.energy != .notLogged }.count,
            completeEnergyDayCount: energyValues.count,
            incompleteEnergyDayCount: days.filter { $0.energy == .incomplete }.count,
            averageEnergyKilocalories: mean(energyValues),
            energyIncludesEstimates: energyEstimates,
            completeFibreDayCount: fibreValues.count,
            incompleteFibreDayCount: days.filter { $0.fibre == .incomplete }.count,
            averageFibreGrams: mean(fibreValues),
            fibreIncludesEstimates: fibreEstimates,
            completeWaterDayCount: waterValues.count,
            incompleteWaterDayCount: days.filter { $0.water == .incomplete }.count,
            averagePlainWaterMillilitres: mean(waterValues),
            waterIncludesEstimates: waterEstimates
        )
    }

    /// The food-log reporting date of each completed day: `yyyy-MM-dd` of the
    /// day's start in `calendar`'s time zone, the same key the food log stores.
    /// One date per completed day, including across a daylight-saving change.
    static func reportingDates(for period: ReportPeriod, calendar: Calendar) -> [String] {
        period.completedDays.map { reportingDate(for: $0.start, calendar: calendar) }
    }

    static func reportingDate(for date: Date, calendar: Calendar) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func energyDay(_ facts: FoodLogDayFacts?) -> EnergyDay {
        guard let facts, facts.foodEntryCount > 0, let energy = facts.energy else { return .notLogged }
        guard let known = energy.knownAmount, energy.incompleteContributions == 0 else { return .incomplete }
        return .complete(kilocalories: known)
    }

    private static func fibreDay(_ facts: FoodLogDayFacts?) -> FibreDay {
        guard let facts, facts.foodEntryCount > 0 else { return .notLogged }
        guard let fibre = facts.fibre, let known = fibre.knownAmount, fibre.incompleteContributions == 0 else {
            return .incomplete
        }
        return .complete(grams: known)
    }

    private static func waterDay(_ facts: FoodLogDayFacts?) -> WaterDay {
        guard let water = facts?.plainWater else { return .noPlainWater }
        guard let known = water.knownAmount, water.incompleteContributions == 0 else { return .incomplete }
        return .complete(millilitres: known)
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
