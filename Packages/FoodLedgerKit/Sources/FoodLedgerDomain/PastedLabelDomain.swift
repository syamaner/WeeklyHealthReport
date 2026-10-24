import Foundation

/// The one definition of a calculated nutrient value (`docs/pasted-nutrition-label-v1.md`
/// section 3.5): a value whose provenance carries an allow-listed `(transformID,
/// transformVersion)` pair of `pasted-label-conversions-v1`. A unit transform that is not a
/// calculation, such as `mass-g-to-mg`, is never calculated.
public enum NutrientDerivation {
    public struct CalculatedTransformPair: Hashable, Sendable {
        public let transformID: String
        public let transformVersion: String
        public init(transformID: String, transformVersion: String) {
            self.transformID = transformID; self.transformVersion = transformVersion
        }
    }

    /// Append-only: entries are never removed or rekeyed. v1 holds the two pasted-label rules.
    public static let calculatedTransforms: [CalculatedTransformPair] = [
        CalculatedTransformPair(transformID: "kj_to_kcal_v1", transformVersion: "pasted-label-conversions-v1"),
        CalculatedTransformPair(transformID: "salt_to_sodium_v1", transformVersion: "pasted-label-conversions-v1")
    ]

    /// True only for an allow-listed pair. A transform that also names a quantity conversion is
    /// not one of the approved shapes, so it is not calculated either.
    public static func calculatedTransform(_ transform: NutrientTransform) -> Bool {
        transform.quantityConversionVersionID == nil
            && calculatedTransforms.contains(CalculatedTransformPair(
                transformID: transform.transformID.value, transformVersion: transform.transformVersion.value))
    }

    /// Whether any provenance of the value carries a calculated transform.
    public static func isCalculated(_ value: NutrientValue) -> Bool {
        value.provenance.contains { $0.transforms.contains(where: calculatedTransform) }
    }
}

/// Identity mapping `pasted-label-identity-v1` (owner-approved, 18 October 2026; contract
/// section 6.5). A pasted label is the user's named food as sold.
public enum PastedLabelIdentity {
    public static let version = "pasted-label-identity-v1"
    /// The packing medium is named "as sold".
    public static let packingMediumName = "as sold"
    /// Hard-decline code for a table whose header or basis is as prepared or drained (for
    /// example 沖泡 or 瀝乾). Defined here; the reading route (PR 3) emits it.
    public static let basisStateNotSupported = "basis_state_not_supported"

    /// The fortification answer, given on Confirm (pasted label Confirm v1, #306). Not stated is
    /// stored as `unanswered` with a typed `not_sure` decision on the confirming assertion.
    public enum FortificationAnswer: String, Codable, CaseIterable, Sendable {
        case yes
        case no
        case unanswered
    }

    /// Yes is fortified, No is unfortified; unanswered is unknown. Unknown raises the existing
    /// `sourceIdentityMissing` requirement, except on a new pasted-label Confirm (or a
    /// reopened Not stated entry), where it is an inline decision (pasted label Confirm v1, C4).
    public static func fortification(_ answer: FortificationAnswer) -> FortificationState {
        switch answer {
        case .yes: .fortified
        case .no: .unfortified
        case .unanswered: .unknown
        }
    }

    /// `fortifiedFood` only when the user answered Yes; otherwise `food`.
    public static func itemClass(_ answer: FortificationAnswer) -> ItemClass {
        answer == .yes ? .fortifiedFood : .food
    }

    /// As sold; bone, skin and drained not applicable; packing medium named "as sold";
    /// fortification from the answer; serving basis is the stored column's basis.
    public static func identity(fortification answer: FortificationAnswer, servingBasis: ResolutionBasis) throws -> DecisiveIdentity {
        try DecisiveIdentity(
            preparation: PreparationState(kind: .asSold),
            bone: .notApplicable,
            skin: .notApplicable,
            drained: .notApplicable,
            packingMedium: .named(LedgerText(packingMediumName)),
            fortification: fortification(answer),
            servingBasis: servingBasis
        )
    }
}
