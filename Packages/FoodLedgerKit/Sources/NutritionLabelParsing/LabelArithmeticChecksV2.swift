import Foundation

/// `label-arithmetic-checks-v2` (`docs/pasted-nutrition-label-reader-v3.md` section 8.4.4,
/// decision 5): `label-arithmetic-checks-v1` unchanged, then one check, `basis_plausibility`, for
/// each amount basis in column order, `macronutrients` then `energy`. It runs only on a read with
/// asserted bases (a user-chosen basis). Swift only: v1's Python parity is untouched.
///
/// A failure is a non-blocking warning; a pass shows nothing; a missing row is never zero.
public enum LabelArithmeticChecksV2 {
    public static let version = "label-arithmetic-checks-v2"
    public static let checkName = "basis_plausibility"

    static let macronutrientRows = ["protein", "fat", "carbohydrate"]
    static let kjPerKcal = LabelArithmeticChecks.decimal("4.184")
    static let relativeTolerance = LabelArithmeticChecks.decimal("0.02")
    static let gramFloor = LabelArithmeticChecks.decimal("0.5")
    static let kcalFloor: Decimal = 5

    /// v1's checks, then the plausibility checks for `amountBases` (the amount columns' bases in
    /// column order, each at most once).
    public static func check(_ table: LabelArithmeticTable, amountBases: [String]) -> LabelArithmeticReport {
        let v1 = LabelArithmeticChecks.check(table)
        var checks = v1.checks
        var seen: Set<String> = []
        for basis in amountBases where seen.insert(basis).inserted {
            checks.append(contentsOf: plausibility(table, basis: basis))
        }
        let statuses = Set(checks.map(\.status))
        let status: LabelCheckStatus = statuses.contains(.fail) ? .fail : statuses.contains(.pass) ? .pass : .notCheckable
        var warnings = v1.warnings
        if checks.contains(where: { $0.name == checkName && $0.status == .fail }) {
            warnings.append("the chosen basis gives values no food has")
        }
        return LabelArithmeticReport(status: status, checks: checks, warnings: warnings)
    }

    /// The macronutrient and energy limits of one basis, in grams and kcal; nil when the basis
    /// cannot be checked (per serving in millilitres or without a serving quantity).
    static func limits(_ table: LabelArithmeticTable, basis: String) -> (grams: Decimal, kcal: Decimal)? {
        switch basis {
        case "per_100g": return (100, 900)
        case "per_100ml": return (150, 900)
        case "per_serving":
            guard table.servingSize?.canonicalUnit == "g", let size = LabelArithmeticChecks.number(table.servingSize?.decimalText), size > 0 else {
                return nil
            }
            return (size, 9 * size)
        default: return nil
        }
    }

    static func tolerance(_ limit: Decimal, floor: Decimal) -> Decimal {
        max(limit * relativeTolerance, floor)
    }

    /// A row's value in the basis: its single cell in `unit`; `=` gives the number and `<` or
    /// `<=` its stated end (the largest it can be). Anything else is missing.
    static func value(_ table: LabelArithmeticTable, _ nutrient: String, unit: String, basis: String) -> Decimal? {
        let matching = table.cells.filter { $0.nutrient == nutrient && $0.basis == basis && $0.canonicalUnit == unit }
        guard matching.count == 1, ["=", "<", "<="].contains(matching[0].comparator) else { return nil }
        return LabelArithmeticChecks.number(matching[0].decimalText)
    }

    static func plausibility(_ table: LabelArithmeticTable, basis: String) -> [LabelCheckResult] {
        var macronutrients = LabelCheckResult(name: checkName, basis: basis, status: .notCheckable)
        macronutrients.nutrient = "macronutrients"
        var energy = LabelCheckResult(name: checkName, basis: basis, status: .notCheckable)
        energy.nutrient = "energy"
        guard !table.declined, let limits = limits(table, basis: basis) else { return [macronutrients, energy] }

        let present = macronutrientRows.compactMap { value(table, $0, unit: "g", basis: basis) }
        let sum = present.reduce(Decimal(0), +)
        let gramLimit = limits.grams + tolerance(limits.grams, floor: gramFloor)
        macronutrients.expected = limits.grams
        macronutrients.slack = tolerance(limits.grams, floor: gramFloor)
        // Over the limit on the rows present is a failure; otherwise a missing row is never a pass.
        macronutrients.status = sum > gramLimit ? .fail : (present.count == macronutrientRows.count ? .pass : .notCheckable)

        if let kcal = value(table, "energy_kcal", unit: "kcal", basis: basis) {
            let slack = tolerance(limits.kcal, floor: kcalFloor)
            energy.expected = limits.kcal
            energy.slack = slack
            energy.status = kcal > limits.kcal + slack ? .fail : .pass
        } else if let kj = value(table, "energy_kj", unit: "kJ", basis: basis) {
            let limit = limits.kcal * kjPerKcal
            let slack = tolerance(limit, floor: kcalFloor * kjPerKcal)
            energy.expected = limit
            energy.slack = slack
            energy.status = kj > limit + slack ? .fail : .pass
        }
        return [macronutrients, energy]
    }
}
