import SwiftUI

/// How an Add food journey ends after Log (#197, F4). Set by the shell on the Add food
/// destination; hosts outside it keep their own back behaviour.
struct FoodEntryFinish {
    let finish: (_ reportingDay: String?) -> Void
    func callAsFunction(_ reportingDay: String?) { finish(reportingDay) }
}

private struct FoodEntryFinishKey: EnvironmentKey {
    static let defaultValue: FoodEntryFinish? = nil
}

extension EnvironmentValues {
    var finishFoodEntry: FoodEntryFinish? {
        get { self[FoodEntryFinishKey.self] }
        set { self[FoodEntryFinishKey.self] = newValue }
    }
}
