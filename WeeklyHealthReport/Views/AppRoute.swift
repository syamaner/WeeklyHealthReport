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
    case favourites
    /// Home's notes row (#199, D11): today's notes, pinned to today.
    case todayNotes
    case todayNoteEditor

    /// Settings children that exist only when their feature is composed.
    static let composedSettingsRoutes: Set<AppRoute> = [
        .webLookupKey, .foodMarket, .dataBackup, .medicationAccess, .developerTools
    ]

    /// Google Drive export screens. They always have a destination, but a build
    /// without Drive configuration shows them as unavailable, so they are never
    /// restored there (#305).
    static let driveExportRoutes: Set<AppRoute> = [.dailyExport, .exportDestination]

    /// Routes that always have a destination, possibly an unavailable screen.
    static let fixedRoutes: Set<AppRoute> = Set(allCases).subtracting(composedSettingsRoutes)

    /// True while a path shows Home's today notes, so the shared notes
    /// controller is pinned to today instead of the export's selected day.
    static func pinsNotesToToday(_ path: [AppRoute]) -> Bool {
        path.contains(.todayNotes) || path.contains(.todayNoteEditor)
    }

    /// Rebuilds a navigation path from the last stored destination.
    /// Unknown values restore Home. Settings children that are not composed
    /// restore Settings itself. A destination missing from `availableRoutes`
    /// is never the landing screen: Export restores Home and Drive setup
    /// restores Settings (#305).
    static func restoredPath(
        from storedDestination: String,
        hasDraft: Bool,
        availableRoutes: Set<AppRoute>
    ) -> [AppRoute] {
        guard let destination = AppRoute(rawValue: storedDestination) else {
            return []
        }

        switch destination {
        case .dailyExport:
            return availableRoutes.contains(.dailyExport) ? [.dailyExport] : []
        case .foodLog, .healthReport, .genericFoodSearch,
             .foodListImport, .barcodeFoodCapture, .commonFoods, .addFood, .favourites:
            return [destination]
        case .todayNotes:
            return [.todayNotes]
        case .todayNoteEditor:
            return hasDraft ? [.todayNotes, .todayNoteEditor] : [.todayNotes]
        case .notes:
            return [.dailyExport, .notes]
        case .noteEditor:
            return hasDraft ? [.dailyExport, .notes, .noteEditor] : [.dailyExport, .notes]
        case .diagnostics:
            return []
        case .settings:
            return [.settings]
        case .exportDestination:
            return availableRoutes.contains(.exportDestination) ? [.settings, .exportDestination] : [.settings]
        case .privacy, .inventoryReview, .foodReresolution, .webLookupKey,
             .foodMarket, .dataBackup, .medicationAccess, .developerTools:
            return availableRoutes.contains(destination) ? [.settings, destination] : [.settings]
        }
    }
}
