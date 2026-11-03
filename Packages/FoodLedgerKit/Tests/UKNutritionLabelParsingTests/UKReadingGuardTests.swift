import NutritionLabelParsing
import UKNutritionLabelParsing
import XCTest

/// Synthetic texts for the guard (`docs/pasted-nutrition-label-uk-english-v1-p2.md` section 3).
enum UKGuardCases {
    static let rows = "Fat\t12g\t3.6g\nof which saturates\t5g\t1.5g\nCarbohydrate\t50g\t15g\nof which sugars\t20g\t6g\n"
        + "Fibre\t3g\t0.9g\nProtein\t8g\t2.4g\nSalt\t0.5g\t0.15g"

    static func table(_ header: String, energy: String = "Energy\t1520kJ\t456kJ\n\t362kcal\t109kcal") -> String {
        "\(header)\n\(energy)\n\(rows)"
    }

    static let g1 = ["Typical values\tPer 100\tPer 30g serving", "Typical values\tPer 100  g\tPer 30g", "Typical values\tper 100 kcal\tPer 30g",
                     "Typical values\tper 100 oz\tPer 30g", "Typical values\tper 100 pieces\tPer 30g", "Typical values\tper 100 portions\tPer 30g",
                     "Typical values\tPer serving (100 pieces)\tPer 30g"].map { table($0) }
    static let g2 = [
        "Energy (kJ) 1520 (kcal) 362", "Energy (kJ) 1520 kcal 362", "Energy kJ (kcal) 1520 362", "Energy (kJ) (kcal) 1520 362",
        "Energy (kJ) 1520/362", "Energy kJ 1520/362", "Energy (kJ) 1520\n362 (kcal)",
    ].map { table("Typical values\tPer 100g\tPer serving", energy: $0) }
    static let g3 = [
        table("Typical values\tPer 100g\tPer 30g serving  with 125ml milk"), table("Typical values as prepared\tPer 100g\tPer 30g"),
        table("Typical values\tPer 100g\tPer 30g serving") + "\nValues are for the product as prepared",
        table("Typical values\tPer 100g*\tPer 30g") + "\n*when made up with water", table("Per 100g\tPer 30g\nwith semi-skimmed milk"),
        table("Typical values\tPer 100g\tPer 30g + 125ml"),
    ]
    static let all = g1 + g2 + g3
}

/// Contract tests 3 to 5 of the P2a spec: the guard returns its input or declines, and every
/// listed shape declines with its code.
final class UKReadingGuardTests: XCTestCase {
    private let v3 = NutritionLabelTextParserV3()
    private let uk = NutritionLabelTextParserUK()

    func testG1DeclinesEveryHeaderThatNames100ButIsBoundPerServing() {
        for text in UKGuardCases.g1 {
            XCTAssertEqual(uk.parse(text, inputSHA256: "x").declineReasons, [UKReadingGuard.headerBasisUnrecognised], text)
        }
    }

    func testG1KeepsPer100AndPerServingHeadersThatNameTheirBasis() {
        for (header, expected) in [("per 100gm", LabelBasis.per100g), ("per 100gms", .per100g), ("per 100 grams", .per100g),
                                   ("per 100 g", .per100g), ("Per 100mls", .per100ml)] {
            let read = uk.parse(UKGuardCases.table("Typical values\t\(header)\tPer 30g serving"), inputSHA256: "x")
            XCTAssertEqual(read.headers.first?.basis, expected, "\(header) \(read.declineReasons)")
        }
        for header in ["Per 30g serving", "Per serving (100g)", "Per serving (100 g)"] {
            let read = uk.parse(UKGuardCases.table("Typical values\tPer 100g\t\(header)"), inputSHA256: "x")
            XCTAssertEqual(read.headers.map(\.basis), [.per100g, .perServing], "\(header) \(read.declineReasons)")
        }
    }

    func testG1IgnoresAStrayClosingBracket() {
        let read = uk.parse(UKGuardCases.table("Typical values)\tPer 100g\tPer serving) (100g)"), inputSHA256: "x")
        XCTAssertFalse(read.declineReasons.contains(UKReadingGuard.headerBasisUnrecognised), "\(read.declineReasons)")
    }

    func testG2DeclinesEveryConflictingUnitShape() {
        for text in UKGuardCases.g2 {
            let read = uk.parse(text, inputSHA256: "x")
            XCTAssertEqual(read.declineReasons, [UKReadingGuard.conflictingUnits], text)
            XCTAssertTrue(read.cells.isEmpty)
        }
        // `per 100g/ml` is one basis, not two units.
        XCTAssertFalse(uk.parse(UKGuardCases.table("Nutritional information per 100g/ml", energy: "Energy\t1520kJ\n\t362kcal")
            .replacingOccurrences(of: #"\t[0-9.]+g$"#, with: "", options: .regularExpression), inputSHA256: "x").declineReasons
            .contains(UKReadingGuard.conflictingUnits))
    }

    func testG3DeclinesAnIdentityMarkerOnAnyLine() {
        for text in UKGuardCases.g3 {
            XCTAssertEqual(uk.parse(text, inputSHA256: "x").declineReasons, [UKReadingGuard.basisStateNotSupported], text)
        }
        for word in ["unprepared", "undrained", "uncooked", "as sold", "serving"] {
            XCTAssertFalse(uk.parse(UKGuardCases.table("Typical values (\(word))\tPer 100g\tPer 30g"), inputSHA256: "x").declineReasons
                .contains(UKReadingGuard.basisStateNotSupported), word)
        }
    }

    func testTheGuardReturnsItsInputOrADecline() {
        for text in UKGuardCases.all + [UKGuardCases.table("Typical values\tPer 100g\tPer 30g")] {
            let normalised = UKTextNormalisation.normalise(text)
            let parsed = v3.parse(normalised, inputSHA256: "x")
            let guarded = UKReadingGuard.apply(parsed, normalisedLines: normalised.components(separatedBy: "\n"))
            XCTAssertTrue(guarded == parsed || (guarded.declined && guarded.cells.isEmpty), text)
            XCTAssertEqual(guarded.inputSHA256, "x")
        }
    }

    func testMarkersAndReferenceIntakeNeverBindAsAmounts() {
        let text = "Typical values\tPer 100g\t%RI*\nEnergy\t1520kJ\t\n\t362kcal\t18%\nFat\t12g\t17%\nof which saturates\tTrace\t\n"
            + "Carbohydrate\t50g\t19%\nof which sugars\t<0.5g\t\nFibre\tTr\t\nProtein\t8g\t16%\nSalt\tless than 0.5g\t\n"
            + "Reference intake of an average adult (8400kJ / 2000kcal)"
        let read = uk.parse(text, inputSHA256: "x")
        XCTAssertFalse(read.cells.contains { $0.decimalText == "0" })
        XCTAssertFalse(read.cells.contains { ($0.decimalText == "8400" || $0.decimalText == "2000") && $0.basis != .referenceIntake })
        for cell in read.cells where cell.basis != .referenceIntake {
            XCTAssertNotEqual(cell.unit, "%", "\(cell)")
        }
        if let sugars = read.cells.first(where: { $0.nutrient == "sugars" }) { XCTAssertEqual(sugars.comparator, .less) }
        if let salt = read.cells.first(where: { $0.nutrient == "salt" }) { XCTAssertEqual(salt.comparator, .less) }
    }
}
