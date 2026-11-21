import Foundation

/// The two owner-supplied manifests and version pins for the CE1 evaluation (phase gate section 9).
public enum EvalConfiguration {
    public static let version = "confirm-enrichment-eval-configuration-v1"
    public static let scorerVersion = "confirm-enrichment-eval-scorer-v1"
    public static let development = EvalHashes.Manifest(count: 100,
        sha256: "1c357f97866f1a5f62b078201e5217d9f814e00f93a59942099a948dcd619bfa")
    public static let sealed = EvalHashes.Manifest(count: 100,
        sha256: "a3396991fe7b42a9a5faeb027a5e74f891ef5eacbe539cc6385fbe0b6dcc495b")

    // Filled from the owner's first successful A request after the route is confirmed.
    public static let firstDetailsRequestSHA256: String? = nil
}
