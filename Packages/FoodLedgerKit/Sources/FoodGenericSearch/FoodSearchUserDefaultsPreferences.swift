import Foundation
import FoodLedgerApplication

@MainActor
public final class FoodSearchUserDefaultsPreferences: FoodSearchPreferences {
    private let defaults: UserDefaults
    private let key = "foodSearch.openFoodFacts.automatic.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var geminiEnabled: Bool {
        get { defaults.bool(forKey: "foodSearch.gemini.automatic.v1") }
        set { defaults.set(newValue, forKey: "foodSearch.gemini.automatic.v1") }
    }

    public var onlineDatabaseEnabled: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
