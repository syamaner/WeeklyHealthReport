import Foundation

/// The two owner-supplied manifests and version pins for the CE1 evaluation (phase gate section 9).
public enum EvalConfiguration {
    public static let version = "confirm-enrichment-eval-configuration-v1"
    public static let scorerVersion = "confirm-enrichment-eval-scorer-v1"
    public static let development = EvalHashes.Manifest(count: 100,
        sha256: "1c357f97866f1a5f62b078201e5217d9f814e00f93a59942099a948dcd619bfa")
    public static let sealed = EvalHashes.Manifest(count: 100,
        sha256: "a3396991fe7b42a9a5faeb027a5e74f891ef5eacbe539cc6385fbe0b6dcc495b")

    public struct Freeze: Sendable {
        public let firstDetailsRequestSHA256: String
        public let developmentDetailsRequests: Int
        public let developmentNutrientRequests: Int
        public let reviewedProducts: Int
        public let confirmedFortified: Int

        public init(firstDetailsRequestSHA256: String, developmentDetailsRequests: Int, developmentNutrientRequests: Int,
                    reviewedProducts: Int, confirmedFortified: Int) {
            self.firstDetailsRequestSHA256 = firstDetailsRequestSHA256
            self.developmentDetailsRequests = developmentDetailsRequests
            self.developmentNutrientRequests = developmentNutrientRequests
            self.reviewedProducts = reviewedProducts
            self.confirmedFortified = confirmedFortified
        }

        public var isComplete: Bool {
            let hash = firstDetailsRequestSHA256
            return hash.utf8.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
                && developmentDetailsRequests > 0 && developmentNutrientRequests > 0
                && reviewedProducts == 60 && (8...reviewedProducts).contains(confirmedFortified)
        }
    }

    // Recorded together from the owner's console-only evidence and aggregate review counts.
    public static let freeze: Freeze? = nil
}
