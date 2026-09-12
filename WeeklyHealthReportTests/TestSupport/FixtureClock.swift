import Foundation

let fixtureID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

final class FixtureClock {
    private let dates: [Date]
    private var index = 0

    init(dates: [Date]) {
        precondition(!dates.isEmpty)
        self.dates = dates
    }

    func now() -> Date {
        defer { index += 1 }
        return dates[min(index, dates.count - 1)]
    }
}
