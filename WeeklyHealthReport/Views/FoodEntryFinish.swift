import FoodLedgerApplication

/// How an Add food journey ends after Log (#197, F4). Passed explicitly from the Add food route
/// to every nested Confirm host (search, web lookup, barcode, recent), because environment values
/// do not reach destinations pushed from inside those hosts. Hosts outside Add food have none and
/// keep their own back behaviour.
struct FoodEntryFinish {
    let finish: (_ reportingDay: String?) -> Void
    func callAsFunction(_ reportingDay: String?) { finish(reportingDay) }

    /// The single leave rule for a Confirm host: after a save inside Add food, finish through the
    /// coordinator and return true; otherwise return false so the host pops itself.
    @discardableResult
    static func complete(_ finish: FoodEntryFinish?, saved: StoredFoodConfirmation?) -> Bool {
        guard let finish, let saved else { return false }
        finish(saved.logItemVersion.reportingDate.value)
        return true
    }
}
