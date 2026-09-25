import Foundation

public struct NutrientResolutionChange: Equatable, Sendable {
    public let before: NutrientEntry
    public let after: NutrientEntry
    public var key: NutrientKey { before.key }
    public var changed: Bool { before != after }
}

/// Compare complete entries, including state, bounds, conflict and provenance.
/// A changed source with the same scalar is still a material provenance change.
public struct NutritionResolutionDiff: Equatable, Sendable {
    public let entries: [NutrientResolutionChange]
    public var changes: [NutrientResolutionChange] { entries.filter(\.changed) }
    public var isUnchanged: Bool { changes.isEmpty }

    public init(before: NutrientSet, after: NutrientSet) {
        entries = zip(before.entries, after.entries).map { NutrientResolutionChange(before: $0, after: $1) }
    }
}
