import XCTest
import FoodLedgerDomain
@testable import NutritionLabelParsing

/// CE1.6 rule 3: the domain's own energy check constants and forms equal `LabelArithmeticChecks`,
/// which the domain cannot import (Confirm enrichment phase gate section 3.3 item 6).
final class EstimateEnergyCheckParityTests: XCTestCase {
    func testConstantsMatchTheLabelChecks() throws {
        for jurisdiction in ["uk", "taiwan"] {
            let tolerance = try XCTUnwrap(LabelArithmeticChecks.tolerances[jurisdiction])
            XCTAssertEqual(NSDecimalNumber(decimal: tolerance.absoluteKcal).doubleValue, EstimateEnergyCheck.absoluteToleranceKcal)
            XCTAssertEqual(NSDecimalNumber(decimal: tolerance.relative).doubleValue, EstimateEnergyCheck.relativeTolerance)
        }
    }

    /// Every case passes the domain check exactly when the label check passes it in one jurisdiction
    /// (UK or Taiwan), since a candidate's jurisdiction is not reliably known.
    func testFormsAgreeWithTheLabelChecks() {
        let cases: [(kcal: Double, p: Double, c: Double, f: Double, fibre: Double?)] = [
            (400, 10, 60, 12, nil), (400, 10, 60, 12, 8), (250, 5, 30, 10, 6), (100, 1, 1, 1, nil),
            (520, 6, 55, 30, 12), (380, 12, 50, 14, 20), (90, 2, 18, 0.5, 3), (15, 0, 0, 0, nil), (16, 0, 0, 0, 0),
            (300, 20, 20, 10, 10), (210, 4, 40, 3, 15)
        ]
        for item in cases {
            let label = ["uk", "taiwan"].contains { jurisdiction in
                LabelArithmeticChecks.energyCheck(table(jurisdiction, item), basis: "per_100g").status == .pass
            }
            let domain = EstimateEnergyCheck.passes(energy: item.kcal, protein: item.p, carbohydrate: item.c, fat: item.f, fibre: item.fibre)
            XCTAssertEqual(domain, label, "\(item)")
        }
    }

    private func table(_ jurisdiction: String, _ item: (kcal: Double, p: Double, c: Double, f: Double, fibre: Double?)) -> LabelArithmeticTable {
        func cell(_ nutrient: String, _ unit: String, _ value: Double) -> LabelArithmeticCell {
            LabelArithmeticCell(nutrient: nutrient, basis: "per_100g", canonicalUnit: unit, comparator: "=",
                                decimalText: "\(value)", parentRowID: nil, unit: unit, printedText: "\(value)")
        }
        var cells = [cell("energy_kcal", "kcal", item.kcal), cell("protein", "g", item.p), cell("carbohydrate", "g", item.c),
                     cell("fat", "g", item.f)]
        if let fibre = item.fibre { cells.append(cell("fibre", "g", fibre)) }
        return LabelArithmeticTable(jurisdiction: jurisdiction, declined: false, servingSize: nil, servingsPerPack: nil, cells: cells)
    }
}
