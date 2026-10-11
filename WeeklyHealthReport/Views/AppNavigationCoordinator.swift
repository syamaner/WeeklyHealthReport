import Combine
import Foundation

/// Owns the app's single navigation path and its persisted destination.
/// Lifecycle notifications are observed by the shell, which calls the
/// matching methods here, so this type stays free of UIKit.
@MainActor
final class AppNavigationCoordinator: ObservableObject {
    static let destinationKey = "weeklyReport.navigationDestination.v1"

    @Published private(set) var path: [AppRoute] = []
    /// A reporting-day key the Food Log selects when it next appears (#197, F4). Never persisted.
    @Published private(set) var foodLogFocusDay: String?
    private var protectedPath: [AppRoute]?
    private(set) var hasRestored = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var storedDestination: String {
        defaults.string(forKey: Self.destinationKey) ?? ""
    }

    /// SwiftUI path changes are ignored while a lifecycle transition is protected.
    func acceptPathChange(_ proposedPath: [AppRoute]) {
        guard protectedPath == nil else { return }
        path = proposedPath
    }

    func replacePath(_ newPath: [AppRoute]) {
        path = newPath
    }

    func append(_ route: AppRoute) {
        path.append(route)
    }

    /// Done after Log from Add food. Opened from the Food Log, it returns there with the saved
    /// entry's reporting day selected; otherwise (Home or a restored Add food) it returns Home.
    func finishFoodEntry(reportingDay: String?) {
        if let index = path.lastIndex(of: .addFood), index > 0, path[index - 1] == .foodLog {
            foodLogFocusDay = reportingDay
            path = Array(path[..<index])
        } else {
            foodLogFocusDay = nil
            path = []
        }
    }

    /// Returns and clears the focus day.
    func takeFoodLogFocusDay() -> String? {
        defer { foodLogFocusDay = nil }
        return foodLogFocusDay
    }

    /// The gear entry point on Home.
    func openSettings() {
        append(.settings)
    }

    func protectCurrentPath() {
        guard protectedPath == nil, !path.isEmpty else { return }
        protectedPath = path
    }

    func restoreProtectedPath() {
        guard let protectedPath else { return }
        path = protectedPath
        self.protectedPath = nil
    }

    /// Restores the stored destination once per coordinator, even when it is unknown.
    func restoreIfNeeded(hasDraft: Bool, availableRoutes: Set<AppRoute>) {
        guard !hasRestored else { return }
        hasRestored = true
        replacePath(AppRoute.restoredPath(
            from: storedDestination,
            hasDraft: hasDraft,
            availableRoutes: availableRoutes
        ))
    }

    /// Called after every path change once restored. Popping to Home stores
    /// an empty value so the next activation stays at Home.
    func recordDestination() {
        guard hasRestored else { return }
        defaults.set(path.last?.rawValue ?? "", forKey: Self.destinationKey)
    }

    /// An empty path never overwrites the stored destination here.
    func willResignActive() {
        protectCurrentPath()
        if let destination = path.last?.rawValue {
            defaults.set(destination, forKey: Self.destinationKey)
        }
    }

    func didBecomeActive(hasDraft: Bool, availableRoutes: Set<AppRoute>) {
        restoreProtectedPath()
        if path.isEmpty {
            replacePath(AppRoute.restoredPath(
                from: storedDestination,
                hasDraft: hasDraft,
                availableRoutes: availableRoutes
            ))
        }
    }
}
