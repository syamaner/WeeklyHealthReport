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

    /// Separators that could mean two amounts are refused, never guessed: a pasted German
    /// "1.500" is not 1.5 g, a French "1 500" is not 1 or 500, an English "1,5" is not 15.
    func testAmbiguousSeparatorsAreRefusedNotGuessed() {
        let narrowSpace = "1\u{202F}500", noBreakSpace = "1\u{00A0}500"
        XCTAssertNil(FoodAmountFieldText.canonical("1.500", locale: german))
        XCTAssertNil(FoodAmountFieldText.parse("1.500", locale: german))
        XCTAssertNil(FoodAmountFieldText.parse("12.345.678", locale: german))
        XCTAssertNil(FoodAmountFieldText.parse("1.500,5", locale: german), "both separators")
        for text in ["1 500", narrowSpace, noBreakSpace] {
            XCTAssertNil(FoodAmountFieldText.parse(text, locale: french), text)
            XCTAssertNil(FoodAmountFieldText.parse(text, locale: english), text)
        }
        XCTAssertNil(FoodAmountFieldText.parse("1,5", locale: english))
        XCTAssertNil(FoodAmountFieldText.parse("1,50", locale: english))
        XCTAssertEqual(FoodAmountFieldText.parse("0.5", locale: german), 0.5, "a full stop not followed by three digits is a decimal")
        XCTAssertEqual(FoodAmountFieldText.parse("1.25", locale: german), 1.25)
        XCTAssertEqual(FoodAmountFieldText.parse("1,500", locale: german), 1.5, "a comma is the German decimal")
        XCTAssertEqual(FoodAmountFieldText.parse("1 1/2", locale: english), 1.5, "a mixed fraction is not grouping")
    }

    /// Refused text reaches the Confirm reducer as non-empty text that never parses, so the
    /// existing invalid-amount message blocks saving; empty text stays empty.
    func testRefusedTextIsInvalidForTheReducer() {
        XCTAssertEqual(FoodAmountFieldText.reducerText("1,5", locale: german), "1.5")
        XCTAssertEqual(FoodAmountFieldText.reducerText("", locale: german), "")
        let refused = FoodAmountFieldText.reducerText("1.500", locale: german)
        XCTAssertFalse(refused.isEmpty)
        XCTAssertNil(FoodAmountTextParser.parse(refused))
        XCTAssertEqual(FoodAmountFieldText.keyboardDoneTitle, "Done")
    }

    /// The saved, read-only plate row shows the method as plain text, matching the picker, and
    /// keeps the empty plate weight visible.
    func testWeighingMethodTitlesMatchThePicker() {
        XCTAssertEqual(FoodConfirmationView.weighingMethodTitle(usesPlate: false), "Food only / tared")
        XCTAssertEqual(FoodConfirmationView.weighingMethodTitle(usesPlate: true), "Total minus empty plate")
        XCTAssertEqual(FoodConfirmationView.savedPlateRowValue(usesPlate: true, emptyPlateGrams: 330, locale: english),
                       "Total minus empty plate · plate 330 g")
        XCTAssertEqual(FoodConfirmationView.savedPlateRowValue(usesPlate: true, emptyPlateGrams: 330.5, locale: german),
                       "Total minus empty plate · plate 330,5 g")
        XCTAssertEqual(FoodConfirmationView.savedPlateRowValue(usesPlate: true, emptyPlateGrams: nil, locale: english),
                       "Total minus empty plate")
        XCTAssertEqual(FoodConfirmationView.savedPlateRowValue(usesPlate: false, emptyPlateGrams: nil, locale: english),
                       "Food only / tared")
    }

    /// Confirm's nutrient names are the same sentence-case names as the Food Log's.
    @MainActor
    func testConfirmNutrientNamesAgreeWithTheSharedNames() {
        for key in NutrientKey.allCases {
            XCTAssertEqual(FoodConfirmationViewModel.nutrientLabel(key), FoodNutritionReviewPresentation.label(key), key.rawValue)
        }
        XCTAssertEqual(FoodConfirmationViewModel.nutrientLabel(.fiber), "Fibre")
        XCTAssertEqual(FoodConfirmationViewModel.nutrientLabel(.fatSaturated), "Saturated fat")
    }

    // MARK: List review amount

    /// The parsed amount shows as "150", not "150.0"; an untouched line keeps its parsed text,
    /// and an edit is stored as typed.
    func testListAmountShowsLocaleTextAndKeepsUntouchedLines() {
        XCTAssertEqual(FoodListAmountText.display("150.0", parsed: 150, locale: english), "150")
        XCTAssertEqual(FoodListAmountText.display("0.5", parsed: 0.5, locale: german), "0,5")
        XCTAssertEqual(FoodListAmountText.display("15", parsed: 150, locale: english), "15", "an edit shows as typed")
        XCTAssertEqual(FoodListAmountText.display("", parsed: nil, locale: english), "")
        XCTAssertEqual(FoodListAmountText.stored("150", current: "150.0", parsed: 150, locale: english), "150.0")
        XCTAssertEqual(FoodListAmountText.stored("1505", current: "150.0", parsed: 150, locale: english), "1505")
    }

    /// A German "1.500" typed into a list line stays visible but blocks matching and review (the
    /// domain list parser would read it as 1.5, #222); "1,5" still works; an untouched line keeps
    /// its parsed evidence text and is never refused.
    func testListAmountRefusesAmbiguousSeparatorsAndKeepsUntouchedLines() {
        let typed = FoodListAmountText.stored("1.500", current: "150.0", parsed: 150, locale: german)
        XCTAssertEqual(typed, "1.500", "the typed text is kept as typed")
        let shown = FoodListAmountText.display(typed, parsed: 150, locale: german)
        XCTAssertEqual(shown, "1.500")
        XCTAssertTrue(FoodListAmountText.isRefused(shown, locale: german))
        XCTAssertEqual(FoodListAmountText.refusedText, "Enter the amount as a number greater than zero, or clear it.")
        XCTAssertFalse(FoodListAmountText.isRefused("1,5", locale: german))
        XCTAssertTrue(FoodListAmountText.isRefused("1 500", locale: french))
        XCTAssertTrue(FoodListAmountText.isRefused("1,5", locale: english))
        XCTAssertFalse(FoodListAmountText.isRefused("", locale: german), "empty is left to the unit rules")
        // Untouched: the parsed text "1.125" would look like German grouping, but the field shows
        // the locale form "1,125" and the stored evidence text is unchanged.
        let untouched = FoodListAmountText.display("1.125", parsed: 1.125, locale: german)
        XCTAssertEqual(untouched, "1,125")
        XCTAssertFalse(FoodListAmountText.isRefused(untouched, locale: german))
        XCTAssertEqual(FoodListAmountText.stored(untouched, current: "1.125", parsed: 1.125, locale: german), "1.125")
    }

    /// Each amount field has its own focus value, so "Done" clears whichever is focused, and the
    /// keyboard "Done" shows only while an amount field is focused.
    func testAmountFocusIsPerFieldAndDoneShowsOnlyForAmounts() {
        let fields: [AmountFieldFocus] = [.confirmQuantity, .confirmDirectWeight, .confirmConversion, .confirmEmptyPlate,
                                          .quickAddOther, .favouriteDefault, .listLine("a"), .listLine("b")]
        XCTAssertEqual(Set(fields).count, fields.count, "no two amount fields share a focus value")
        for field in fields { XCTAssertTrue(AmountFieldFocus.showsDone(field)) }
        XCTAssertFalse(AmountFieldFocus.showsDone(nil), "a text field focused, or none: no Done")
    }

    /// The favourite editor owns its amount focus (sheet content does not see the presenter's
    /// focus state), so its "Done" shows while the default amount is focused; it rides above the
    /// keyboard because Save already holds the navigation bar and the sheet has no pinned bar.
    func testFavouriteEditorOwnsItsAmountFocusAndDone() {
        XCTAssertEqual(FavouriteEditor.amountField, .favouriteDefault)
        XCTAssertTrue(AmountFieldFocus.showsDone(FavouriteEditor.amountField))
        XCTAssertEqual(FavouriteEditor.donePlacement, .keyboard)
        XCTAssertNotEqual(AmountDonePlacement.navigationBar, .keyboard)
    }

    /// Match details rows are identified by their line, so a new list never inherits an open one.
    func testMatchDetailsIdentityFollowsTheLine() {
        XCTAssertNotEqual(FoodListMatchRowText.rowID(line: "a", index: 0), FoodListMatchRowText.rowID(line: "b", index: 0))
        XCTAssertNotEqual(FoodListMatchRowText.rowID(line: "a", index: 0), FoodListMatchRowText.rowID(line: "a", index: 1))
        XCTAssertEqual(FoodListMatchRowText.rowID(line: "a", index: 1), FoodListMatchRowText.rowID(line: "a", index: 1))
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
