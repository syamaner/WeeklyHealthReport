import Foundation

struct WeightMeasurement: Equatable {
    let date: Date
    let kilograms: Double

    static func latest(in measurements: [WeightMeasurement]) -> WeightMeasurement? {
        measurements.max { lhs, rhs in lhs.date < rhs.date }
    }
}
