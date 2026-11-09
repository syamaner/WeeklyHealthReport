import Foundation

/// The launch scope (section 5, decisions 3 and 4): the gate formats the product reads. It is
/// applied after the faithful gate; a UK table that passes the gate is still declined
/// `layout_not_supported` here. Adding UK after its release gate changes only this constant
/// and the copy it feeds. The scope in force is recorded in the manifest (`launch_scope`).
/// Moved unchanged out of `LabelReading.swift` (#371 P2b, `docs/pasted-nutrition-label-uk-english-v1-p2b.md`).
public enum PastedLabelLaunchScope {
    public static let enabledFormats: [String] = ["taiwan_nutrition_labelling"]

    public static func admits(_ format: String) -> Bool { enabledFormats.contains(format) }
}

/// The reading policy (`docs/pasted-nutrition-label-uk-english-v1-p2b.md` section 1, plan
/// decision 8): the launch scope and the identity mapping, changed together. A closed set with
/// no public initialiser, so a scope admitting UK always reads with identity v2 (UK as-prepared
/// headers are never the food as sold). `.product` is today's behaviour byte for byte.
public struct PastedLabelReadingPolicy: Equatable, Sendable {
    public enum Identity: String, Equatable, Sendable {
        case v1 = "pasted-label-identity-v1"
        case v2 = "pasted-label-identity-v2"
        case v3 = "pasted-label-identity-v3"
    }

    public let launchScope: [String]
    public let identity: Identity

    private init(launchScope: [String], identity: Identity) {
        self.launchScope = launchScope; self.identity = identity
    }

    /// The shipped policy: `PastedLabelLaunchScope.enabledFormats` and identity v1.
    public static let product = PastedLabelReadingPolicy(launchScope: PastedLabelLaunchScope.enabledFormats, identity: .v1)
    /// The UK development harness and, from P4, the debug-only device step: Taiwan and UK. Identity
    /// v3 from UK reader v2 (`docs/pasted-nutrition-label-uk-english-v2-p1.md` section 2).
    public static let ukDevelopment = PastedLabelReadingPolicy(
        launchScope: ["taiwan_nutrition_labelling", "uk_nutrition_declaration"], identity: .v3)
    /// Every member, for the closure test (a UK scope reads with identity v2 or later); add any new member here.
    public static let all: [PastedLabelReadingPolicy] = [.product, .ukDevelopment]

    public func admits(_ format: String) -> Bool { launchScope.contains(format) }

    public func isAsSold(_ candidate: PastedLabelManifest.Candidate) -> Bool {
        switch identity {
        case .v1: PastedLabelBasisState.isAsSold(candidate)
        case .v2: PastedLabelBasisStateV2.isAsSold(candidate)
        case .v3: PastedLabelBasisStateV3.isAsSold(candidate)
        }
    }
}
