/// Consent is independent of credentials and provider reachability.
/// Changing this preference never submits a query.
@MainActor
public protocol FoodSearchPreferences: AnyObject {
    var onlineDatabaseEnabled: Bool { get set }
    var geminiEnabled: Bool { get set }
}
