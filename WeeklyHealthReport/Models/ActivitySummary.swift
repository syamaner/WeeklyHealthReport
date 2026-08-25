import Foundation

struct WorkoutRecord: Equatable, Identifiable {
    let id: UUID
    let startDate: Date
    let duration: TimeInterval
    let activityName: String
}

struct WorkoutSummary: Equatable {
    let workouts: [WorkoutRecord]

    var count: Int { workouts.count }
    var totalDuration: TimeInterval { workouts.reduce(0) { $0 + $1.duration } }
}
