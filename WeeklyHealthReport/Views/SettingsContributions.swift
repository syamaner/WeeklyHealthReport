import Foundation
import FoodLedgerPresentation

/// Drive setup stays on the export screen until #200. The factory takes no
/// session, so building Settings cannot prepare an export or reach the network.
enum ExportSettingsContribution {
    static func section() -> SettingsSection {
        SettingsSection(
            id: .export,
            title: "Export",
            footer: nil,
            rows: [.link("Google Drive account and folder", route: .dailyExport)]
        )
    }
}

enum AppleHealthSettingsContribution {
    /// Medication access is managed in Health from iOS 26 onwards.
    static func section(medicationAccessAvailable: Bool) -> SettingsSection? {
        guard medicationAccessAvailable else { return nil }
        return SettingsSection(
            id: .appleHealth,
            title: "Apple Health",
            footer: nil,
            rows: [.link("Medication access", route: .medicationAccess)]
        )
    }
}

@MainActor
enum AboutSettingsContribution {
    static func section() -> SettingsSection {
        SettingsSection(
            id: .about,
            title: "About",
            footer: nil,
            rows: [
                .link("Privacy policy", route: .privacy),
                .link("Developer tools", route: .developerTools)
            ]
        )
    }

    /// Writes the same key, in the same store, that the food search screen reads.
    static func developerToolsToggle(defaults: UserDefaults) -> SettingsToggle {
        SettingsToggle(
            title: "Search developer tools",
            caption: "Shows search diagnostics, such as lexical scores and source record identifiers, below food search results.",
            read: { defaults.bool(forKey: FoodSearchDeveloperTools.storageKey) },
            write: { defaults.set($0, forKey: FoodSearchDeveloperTools.storageKey) }
        )
    }
}
