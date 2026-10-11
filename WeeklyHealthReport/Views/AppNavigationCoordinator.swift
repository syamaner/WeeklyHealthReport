import Combine
import Foundation

/// Owns the app's single navigation path and its persisted destination.
/// Lifecycle notifications are observed by the shell, which calls the
/// matching methods here, so this type stays free of UIKit.
@MainActor
final class AppNavigationCoordinator: ObservableObject {
    static let destinationKey = "weeklyReport.navigationDestination.v1"

    @Published private(set) var path: [AppRoute] = []
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
