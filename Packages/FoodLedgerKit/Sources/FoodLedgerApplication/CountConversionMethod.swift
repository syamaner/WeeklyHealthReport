import FoodLedgerDomain

/// The closed set of ways a user obtained the edible weight or volume of a counted food
/// (count-conversion-method-v1). Measured choices are stored as a versioned code in the
/// conversion's `methodVersion`; an estimate is never a conversion, it is a direct weight
/// declaration with the estimated basis.
public enum CountConversionMethod: String, CaseIterable, Equatable, Sendable {
    case kitchenScale = "kitchen_scale"
    case packageWeight = "package_weight"
    case estimatedByEye = "estimated_by_eye"

    /// Prefix shared by every version of the stored code. A code under this prefix that is not
    /// an admitted v1 code fails closed at save.
    public static let codePrefix = "user_count_conversion_v"
    public static let v1Prefix = "user_count_conversion_v1:"

    /// The stored code for a measured choice; nil for an estimate, which is not a conversion.
    public var storedCode: LedgerText? {
        switch self {
        case .kitchenScale, .packageWeight: try? LedgerText(Self.v1Prefix + rawValue)
        case .estimatedByEye: nil
        }
    }

    /// The measured choice a stored conversion method names, or nil for any other text
    /// (a typed method recorded before v1, an offered volume estimate or a pasted-label method).
    public init?(storedCode: LedgerText) {
        guard storedCode.value.hasPrefix(Self.v1Prefix),
              let method = Self(rawValue: String(storedCode.value.dropFirst(Self.v1Prefix.count))),
              method.storedCode == storedCode else { return nil }
        self = method
    }

    /// Whether a conversion method text may be saved: any text outside this method's namespace
    /// (typed methods, admitted source methods), or exactly one of the measured v1 codes.
    public static func admits(_ methodVersion: LedgerText) -> Bool {
        !methodVersion.value.hasPrefix(codePrefix) || Self(storedCode: methodVersion) != nil
    }
}
