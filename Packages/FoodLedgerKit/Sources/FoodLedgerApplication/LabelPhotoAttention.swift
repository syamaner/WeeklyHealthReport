import Foundation

/// `label-photo-attention-v1` (docs/label-photo-ai-prefill-v1.md P12, 17.5 and 17.9): which values
/// of a label photo reading need the user's check before Log, and why. Pure: it reads only what
/// the manifest stores (each value's location on the photo, the gate's flagged rows and the failed
/// checks), so the verifier can recompute it and require equality.
///
/// Ported unchanged from the rules L0 measured (`Tools/NutritionLabelCaptureEvaluation/l0_locate.py`,
/// `table_result` and `arithmetic_attention`):
/// - a known value not found on the photo, or found ambiguously;
/// - a known value in a row the gate flagged (G3 or G4);
/// - a known value a failed check implicates: energy against its macronutrients (the energy,
///   protein, fat, carbohydrate and fibre values of that basis), kJ against kcal (the two energy
///   values of that basis), per serving against per 100 (that nutrient's values outside the
///   reference-intake column), a sub-row above its parent (both values of that basis);
/// - a printed serving line not found on the photo, or found ambiguously.
///
/// Other checks inform but create no attention item under v1. Unknown values are not items: they
/// are already shown as not read, and stay unknown. A change to any rule is a new version.
public enum LabelPhotoAttention {
    public static let version = "label-photo-attention-v1"

    public enum Location: String, Sendable, Codable, CaseIterable { case found, notFound = "not_found", ambiguous }

    /// Why an item needs attention, in the order they are listed on an item.
    public enum Reason: String, Sendable, Codable, CaseIterable {
        case notFound = "not_found", ambiguous, gateFlag = "gate_flag", checkFailed = "check_failed"
    }

    /// One pre-filled value: its stable cell id, nutrient key, basis (`per_serving`, `per_100g`,
    /// `per_100ml`, `reference_intake`), whether it holds a known value, and where it was found.
    public struct Cell: Equatable, Sendable {
        public let id: String, nutrient: String, basis: String, known: Bool, location: Location
        public init(id: String, nutrient: String, basis: String, known: Bool, location: Location) {
            self.id = id; self.nutrient = nutrient; self.basis = basis; self.known = known; self.location = location
        }
    }

    /// A printed serving line (`serving_size` or `servings_per_pack`) and where it was found.
    public struct ServingLine: Equatable, Sendable {
        public let id: String, location: Location
        public init(id: String, location: Location) { self.id = id; self.location = location }
    }

    /// A failed check as the arithmetic report names it (`energy`, `kj_kcal_ratio`,
    /// `serving_scaling`, `subrow_not_above_parent`, or any other name, which implicates nothing).
    public struct FailedCheck: Equatable, Hashable, Sendable {
        public let name: String, basis: String?, nutrient: String?, child: String?
        public init(name: String, basis: String? = nil, nutrient: String? = nil, child: String? = nil) {
            self.name = name; self.basis = basis; self.nutrient = nutrient; self.child = child
        }
    }

    public struct Item: Equatable, Sendable {
        public let id: String
        public let reasons: [Reason]
        public init(id: String, reasons: [Reason]) { self.id = id; self.reasons = reasons }
    }

    /// A failed check with the items it implicates, so Confirm can offer one "I've checked them".
    public struct CheckGroup: Equatable, Sendable {
        public let check: FailedCheck
        public let itemIDs: [String]
        public init(check: FailedCheck, itemIDs: [String]) { self.check = check; self.itemIDs = itemIDs }
    }

    public struct Findings: Equatable, Sendable {
        public let items: [Item]
        public let checks: [CheckGroup]
        public init(items: [Item], checks: [CheckGroup]) { self.items = items; self.checks = checks }
        public var isEmpty: Bool { items.isEmpty }
    }

    static let energyRows: Set<String> = ["energy_kcal", "protein", "fat", "carbohydrate", "fibre"]
    static let parents = ["saturates": "fat", "trans_fat": "fat", "sugars": "carbohydrate", "fibre": "carbohydrate"]

    /// The cells a failed check implicates (known values only, in cell order).
    public static func implicated(by check: FailedCheck, in cells: [Cell]) -> [String] {
        cells.filter { cell in
            guard cell.known else { return false }
            switch check.name {
            case "energy": return cell.basis == check.basis && energyRows.contains(cell.nutrient)
            case "kj_kcal_ratio": return cell.basis == check.basis && ["energy_kcal", "energy_kj"].contains(cell.nutrient)
            case "serving_scaling": return cell.nutrient == check.nutrient && cell.basis != "reference_intake"
            case "subrow_not_above_parent":
                guard let child = check.child else { return false }
                return cell.basis == check.basis && (cell.nutrient == child || cell.nutrient == parents[child])
            default: return false
            }
        }.map(\.id)
    }

    /// The attention set: one item per known value or serving line with at least one reason, in
    /// cell order then serving lines; one group per failed check that implicates any item.
    public static func items(cells: [Cell], servingLines: [ServingLine], gateFlaggedNutrients: Set<String>,
                             failedChecks: [FailedCheck]) -> Findings {
        let groups = failedChecks.map { CheckGroup(check: $0, itemIDs: implicated(by: $0, in: cells)) }.filter { !$0.itemIDs.isEmpty }
        let byCheck = Set(groups.flatMap(\.itemIDs))
        var items: [Item] = []
        for cell in cells where cell.known {
            var reasons: [Reason] = []
            if cell.location == .notFound { reasons.append(.notFound) }
            if cell.location == .ambiguous { reasons.append(.ambiguous) }
            if gateFlaggedNutrients.contains(cell.nutrient) { reasons.append(.gateFlag) }
            if byCheck.contains(cell.id) { reasons.append(.checkFailed) }
            if !reasons.isEmpty { items.append(Item(id: cell.id, reasons: reasons)) }
        }
        for line in servingLines {
            switch line.location {
            case .found: continue
            case .notFound: items.append(Item(id: line.id, reasons: [.notFound]))
            case .ambiguous: items.append(Item(id: line.id, reasons: [.ambiguous]))
            }
        }
        return Findings(items: items, checks: groups)
    }

    /// How the user resolved an item (manifest `attention[].resolution`).
    public enum Resolution: String, Sendable, Codable, CaseIterable {
        case checked, corrected, entered, leftUnknown = "left_unknown"
    }

    /// The items still needing the user, in order. Log is enabled only when this is empty (P12).
    public static func unresolved(_ findings: Findings, resolutions: [String: Resolution]) -> [String] {
        findings.items.map(\.id).filter { resolutions[$0] == nil }
    }

    /// "I've checked them" on a check group: every item it implicates that has no resolution yet
    /// becomes `checked`; a value already corrected or left unknown keeps its resolution.
    public static func checkGroup(_ group: CheckGroup, resolutions: [String: Resolution]) -> [String: Resolution] {
        var updated = resolutions
        for id in group.itemIDs where updated[id] == nil { updated[id] = .checked }
        return updated
    }
}
