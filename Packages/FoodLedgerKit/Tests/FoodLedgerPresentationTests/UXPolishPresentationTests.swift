import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPresentation
import SwiftUI
import XCTest

/// UX polish (#212 and the phase 3 follow-ups): presentation rules only, synthetic values.
final class UXPolishPresentationTests: XCTestCase {
    private let english = Locale(identifier: "en_GB")
    private let german = Locale(identifier: "de_DE")
    private let french = Locale(identifier: "fr_FR")

    // MARK: Amount field (#212)

    /// The decimal pad types the locale's separator; whole grams never shrink (1500 g stays 1500 g,
    /// the phase 3 regression) and a comma decimal reads as a decimal only where it is one.
    func testAmountFieldParsesDecimalPadInputPerLocale() {
        for locale in [english, german, french] {
            XCTAssertEqual(FoodAmountFieldText.parse("1500", locale: locale), 1500, locale.identifier)
            XCTAssertEqual(FoodAmountFieldText.parse("150", locale: locale), 150, locale.identifier)
            XCTAssertNil(FoodAmountFieldText.parse("", locale: locale), locale.identifier)
            XCTAssertNil(FoodAmountFieldText.parse("0", locale: locale), locale.identifier)
        }
        XCTAssertEqual(FoodAmountFieldText.parse("0.5", locale: english), 0.5)
        XCTAssertEqual(FoodAmountFieldText.parse("1,500", locale: english), 1500, "grouping in a full-stop locale")
        XCTAssertEqual(FoodAmountFieldText.parse("1,5", locale: german), 1.5)
        XCTAssertEqual(FoodAmountFieldText.parse("0,25", locale: french), 0.25)
        XCTAssertEqual(FoodAmountFieldText.parse("0.5", locale: german), 0.5, "canonical prefill still reads")
        XCTAssertNil(FoodAmountFieldText.parse("1,5,5", locale: german))
    }

    /// Prefilled text uses the locale separator, never grouping, and reads back unchanged.
    func testAmountFieldTextRoundTripsPerLocale() {
        XCTAssertEqual(FoodAmountFieldText.text(1500, locale: english), "1500")
        XCTAssertEqual(FoodAmountFieldText.text(1500, locale: german), "1500")
        XCTAssertEqual(FoodAmountFieldText.text(0.5, locale: english), "0.5")
        XCTAssertEqual(FoodAmountFieldText.text(0.5, locale: german), "0,5")
        for locale in [english, german, french] {
            for value in [150.0, 1500, 0.5, 150.25, 12_345.5] {
                XCTAssertEqual(FoodAmountFieldText.parse(FoodAmountFieldText.text(value, locale: locale), locale: locale), value,
                               "\(value) in \(locale.identifier)")
            }
        }
    }

    /// The saved, read-only plate row shows the method as plain text, matching the picker.
    func testWeighingMethodTitlesMatchThePicker() {
        XCTAssertEqual(FoodConfirmationView.weighingMethodTitle(usesPlate: false), "Food only / tared")
        XCTAssertEqual(FoodConfirmationView.weighingMethodTitle(usesPlate: true), "Total minus empty plate")
    }

    // MARK: Paste or dictate match rows

    /// Diagnostics (closest candidate, search terms, token differences) move behind details; the
    /// row keeps only the saved-food or exact-name badge.
    func testListMatchRowKeepsDiagnosticsBehindDetails() {
        let closest = FoodListMatchRowText(isSavedFood: false, isExactName: false, materialDifferences: [
            "Search terms: chicken grilled; parsed food terms; requested attributes need review; original query retained.",
            "candidate_only_token:breast", "query_only_token:thigh"
        ])
        XCTAssertNil(closest.badge)
        XCTAssertEqual(closest.details, [
            "Closest candidate",
            "Search terms: chicken grilled; parsed food terms; requested attributes need review; original query retained.",
            "Candidate adds: breast", "Your entry adds: thigh"
        ])
        XCTAssertEqual(FoodListMatchRowText(isSavedFood: true, isExactName: false, materialDifferences: []),
                       FoodListMatchRowText(isSavedFood: true, isExactName: true, materialDifferences: []))
        XCTAssertEqual(FoodListMatchRowText(isSavedFood: true, isExactName: false, materialDifferences: []).badge, "Saved food")
        let exact = FoodListMatchRowText(isSavedFood: false, isExactName: true, materialDifferences: [])
        XCTAssertEqual(exact.badge, "Exact name")
        XCTAssertTrue(exact.details.isEmpty, "no empty details row")
    }

    // MARK: Recent rows

    func testRecentRowsStackOnlyAtAccessibilitySizes() {
        XCTAssertFalse(AddFoodRecentRowText.stacks(at: .large))
        XCTAssertFalse(AddFoodRecentRowText.stacks(at: .xxxLarge))
        XCTAssertTrue(AddFoodRecentRowText.stacks(at: .accessibility1))
        XCTAssertTrue(AddFoodRecentRowText.stacks(at: .accessibility3))
    }

    // MARK: Nutrient names

    /// Display names are sentence case ("Monounsaturated fat" beside "Saturated fat"); only
    /// vitamin letters and parenthesised B codes stay capitalised. Units are unchanged.
    func testNutrientDisplayNamesAreSentenceCase() {
        XCTAssertEqual(FoodLogText.label(.fatSaturated), "Saturated fat")
        XCTAssertEqual(FoodLogText.label(.fatMonounsaturated), "Monounsaturated fat")
        XCTAssertEqual(FoodLogText.label(.fatPolyunsaturated), "Polyunsaturated fat")
        XCTAssertEqual(FoodLogText.label(.pantothenicAcidB5), "Pantothenic acid (B5)")
        XCTAssertEqual(FoodLogText.label(.vitaminB12), "Vitamin B12")
        XCTAssertEqual(FoodLogText.label(.fiber), "Fibre")
        let code = try! NSRegularExpression(pattern: #"^\(?[A-Z]\d*\)?$"#)
        for key in NutrientKey.allCases {
            let words = FoodLogText.label(key).split(separator: " ").map(String.init)
            XCTAssertEqual(words.first?.first?.isUppercase, true, key.rawValue)
            XCTAssertFalse(FoodLogText.label(key).contains("_"), key.rawValue)
            for word in words.dropFirst() where word != word.lowercased() {
                XCTAssertNotNil(code.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)),
                                "\(key.rawValue): \(word) is not sentence case")
            }
        }
        XCTAssertEqual(NutrientKey.vitaminB12.canonicalUnit.rawValue, "mcg", "units are not part of this change")
    }
}
