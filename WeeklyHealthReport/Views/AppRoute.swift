import Foundation

/// Every pushed destination in the app. Raw values are persisted as the
/// last visited destination, so existing values must never be renamed.
enum AppRoute: String, Codable, Hashable, CaseIterable {
    case foodLog
    case healthReport
    case dailyExport
    case genericFoodSearch
    case foodListImport
    case barcodeFoodCapture
    case inventoryReview
    case commonFoods
    case foodReresolution
    case notes
    case noteEditor
    case diagnostics
    case privacy
    case settings
    case webLookupKey
    case foodMarket
    case dataBackup
    case medicationAccess
    case developerTools
    case addFood
    case exportDestination

    /// Settings children that exist only when their feature is composed.
    static let composedSettingsRoutes: Set<AppRoute> = [
        .webLookupKey, .foodMarket, .dataBackup, .medicationAccess, .developerTools
    ]

    /// Routes that always have a destination, possibly an unavailable screen.
    static let fixedRoutes: Set<AppRoute> = Set(allCases).subtracting(composedSettingsRoutes)

    /// Rebuilds a navigation path from the last stored destination.
    /// Unknown values restore Home. Settings children that are not composed
    /// restore Settings itself.
    static func restoredPath(
        from storedDestination: String,
        hasDraft: Bool,
        availableRoutes: Set<AppRoute>
    ) -> [AppRoute] {
        guard let destination = AppRoute(rawValue: storedDestination) else {
            return []
        }

        switch destination {
        case .foodLog, .healthReport, .dailyExport, .genericFoodSearch,
             .foodListImport, .barcodeFoodCapture, .commonFoods, .addFood:
            return [destination]
        case .notes:
            return [.dailyExport, .notes]
        case .noteEditor:
            return hasDraft ? [.dailyExport, .notes, .noteEditor] : [.dailyExport, .notes]
        case .diagnostics:
            return []
        case .settings:
            return [.settings]
        case .exportDestination:
            return [.settings, .exportDestination]
        case .privacy, .inventoryReview, .foodReresolution, .webLookupKey,
             .foodMarket, .dataBackup, .medicationAccess, .developerTools:
            return availableRoutes.contains(destination) ? [.settings, destination] : [.settings]
        }
    }
}
