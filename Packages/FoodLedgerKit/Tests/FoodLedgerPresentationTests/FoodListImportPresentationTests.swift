import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import SwiftUI
import XCTest

@MainActor
final class FoodListImportPresentationTests: XCTestCase {
    /// #222: a pasted numeral that could mean two amounts in the reader's locale is never
    /// proposed as a number; the line has no amount, says why, and the needs-amount rule applies.
    /// Under food-list-lexical-v4 (and v5) the parse itself reads the locale's convention.
    func testPastedAmountsFollowTheReadersDecimalConvention() throws {
        let cases: [(String, String, String, Bool)] = [
            ("de_DE", "1.500 g rice", "", true),      // German grouping for 1500, or 1.5
            ("fr_FR", "1 500 g rice", "", true),      // space grouping
            ("fr_FR", "1\u{202F}500 g rice", "", true),
            ("en_GB", "1,5 g rice", "", true),        // a decimal comma is not English
            ("de_DE", "1,5 g rice", "1.5", false),
            ("en_GB", "1.500 g rice", "1.5", false),
            ("en_GB", "1,500 g rice", "1500.0", false), // Q1: English grouping
            ("de_DE", "1,500 g rice", "1.5", false),    // a German decimal comma
            ("de_DE", "1.500 kg rice", "", true),
            ("de_DE", "rice 1.500 g", "", true),
            ("de_DE", "10 g rice", "10.0", false),
            ("de_DE", "half pepper", "0.5", false),
            ("de_DE", "½ pepper", "0.5", false),
            ("de_DE", "1/2 orange pepper", "0.5", false),
            ("de_DE", ".5 l milk", "500.0", false),
            ("de_DE", "0.5 bell pepper", "0.5", false)
        ]
        for (identifier, text, quantityText, explained) in cases {
            let (model, _) = try listModel(locale: Locale(identifier: identifier))
            model.input = text
            model.prepare()
            let draft = try XCTUnwrap(model.rows.first?.draft, text)
            XCTAssertEqual(draft.quantityText, quantityText, "\(identifier) \(text)")
            let says = draft.parsed.notices.contains(.ambiguousNumber)
                || FoodListAmountText.showsAmbiguousNumeral(draft, locale: model.amountLocale)
            XCTAssertEqual(says, explained, "\(identifier) \(text)")
            let convention = NumeralConvention(locale: Locale(identifier: identifier))
            XCTAssertEqual(try FoodListParser.parse(text, convention: convention).first, draft.parsed)
            XCTAssertEqual(draft.parsed.grammarVersion, "food-list-lexical-v6")
            XCTAssertEqual(draft.parsed.numeralConvention, convention)
        }
        // Once the user types an amount, it is theirs; the explanation goes.
        let (model, _) = try listModel(locale: Locale(identifier: "de_DE"))
        model.input = "1.500 g rice"
        model.prepare()
        var draft = try XCTUnwrap(model.selectedRow?.draft)
        draft.quantityText = "1500"
        model.edit(draft)
        XCTAssertFalse(FoodListAmountText.showsAmbiguousNumeral(try XCTUnwrap(model.selectedRow?.draft), locale: model.amountLocale))
    }

    /// A queue saved before #222, or in another locale, gets the same check on restore for lines
    /// never edited; an edited amount is the user's. The explanation survives a relaunch, even
    /// in a locale where the numeral would not have been ambiguous.
    func testRestoredQueueWithholdsUntouchedAmbiguousAmountsAndKeepsTheNotice() throws {
        let checkpoint = MemoryCheckpoint()
        let make = { (identifier: String) in
            FoodListImportViewModel(service: FoodListImportService(searcher: ListSearch()), locale: try LedgerText(identifier),
                                    ids: ListIDs(), checkpointStore: checkpoint,
                                    amountLocale: Locale(identifier: identifier)) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        }
        let english = try make("en_GB")
        english.input = "1.500 g rice\n1.500 g oats\n10 g fixture"
        english.prepare()
        XCTAssertEqual(english.rows.map(\.draft.quantityText), ["1.5", "1.5", "10.0"], "unambiguous in English")
        var edited = english.rows[1].draft
        edited.quantityText = "2"
        english.edit(edited)

        let german = try make("de_DE")
        XCTAssertEqual(german.rows.map(\.draft.quantityText), ["", "2", "10.0"])
        XCTAssertTrue(FoodListAmountText.showsAmbiguousNumeral(german.rows[0].draft, locale: german.amountLocale))
        XCTAssertFalse(FoodListAmountText.showsAmbiguousNumeral(german.rows[1].draft, locale: german.amountLocale))
        german.retryCheckpoint() // persists the restored queue

        let relaunched = try make("en_GB")
        XCTAssertEqual(relaunched.rows.map(\.draft.quantityText), ["", "2", "10.0"])
        XCTAssertTrue(FoodListAmountText.showsAmbiguousNumeral(relaunched.rows[0].draft, locale: relaunched.amountLocale),
                      "the withheld line still says why after a relaunch")
    }

    /// A withheld amount reaches Confirm as no amount, never as 1.5.
    func testWithheldAmbiguousAmountReachesConfirmWithoutAValue() throws {
        let (model, search) = try listModel(locale: Locale(identifier: "de_DE"))
        model.input = "1.500 g fixture"
        model.prepare()
        model.search()
        XCTAssertEqual(search.calls, 1)
        model.review(candidate: 0)
        let confirmation = try XCTUnwrap(model.confirmation)
        XCTAssertNil(confirmation.state.quantity.value)
        XCTAssertEqual(confirmation.state.quantity.unit, .grams)
    }

    /// food-list-lexical-v5 (#140, B3) and v6 (#353): a vague portion or container is never a count. The line has no amount
    /// and says why, and Confirm opens empty with the needs-amount rule blocking Log, in every
    /// numeral convention.
    func testVaguePortionLinesReachConfirmWithoutAnAmount() throws {
        for identifier in ["en_GB", "de_DE", "fr_FR", "ar_SA"] {
            // food-list-lexical-v6 (#353): a household container behaves the same way.
            for text in ["a handful of fixture", "2 pinches of fixture", "a few fixture", "a bit of fixture",
                         "2 mugs of fixture", "a pot of fixture", "250 ml mug of fixture", "glasses of fixture"] {
                let label = "\(identifier) \(text)"
                let (model, search) = try listModel(locale: Locale(identifier: identifier))
                model.input = text
                model.prepare()
                let draft = try XCTUnwrap(model.selectedRow?.draft, label)
                XCTAssertEqual(draft.quantityText, "", label)
                XCTAssertEqual(draft.query, "fixture", label)
                XCTAssertEqual(draft.parsed.notices, [.householdMeasure], label)
                XCTAssertEqual(draft.parsed.grammarVersion, "food-list-lexical-v6", label)
                model.search()
                XCTAssertEqual(search.lastEvidence?.captureMethodVersion.value, "food-list-lexical-v6", label)
                model.review(candidate: 0)
                let confirmation = try XCTUnwrap(model.confirmation, label)
                XCTAssertNil(confirmation.state.quantity.value, label)
                XCTAssertTrue(confirmation.requirements.contains(.amountMissing), label)
                XCTAssertFalse(confirmation.canLog, label)
            }
        }
    }

    /// A common food whose saved name starts with a vague portion word keeps its whole name as
    /// the search query (no brand words lost); without a usual portion it still has no amount.
    func testCommonFoodNamesStartingWithVagueWordsKeepTheirName() throws {
        for name in ["Pinch of Nom Lasagne", "Splash orange", "Bits & Bobs crisps", "A few cheeky peanuts"] {
            let (model, search) = try listModel(locale: Locale(identifier: "en_GB"))
            try model.addCommonFood(name: name, portion: nil)
            let draft = try XCTUnwrap(model.selectedRow?.draft, name)
            XCTAssertEqual(draft.query, name)
            XCTAssertEqual(draft.quantityText, "", name)
            XCTAssertEqual(draft.parsed.notices, [.householdMeasure], name)
            model.search()
            guard case let .descriptor(payload) = search.lastEvidence?.originalPayload else { return XCTFail("Missing descriptor") }
            XCTAssertTrue(payload.value.contains(#""query":"\#(name)""#), payload.value)
            XCTAssertEqual(search.lastEvidence?.captureMethodVersion.value, "food-list-lexical-v6", name)
        }
        let (model, _) = try listModel(locale: Locale(identifier: "en_GB"))
        try model.addCommonFood(name: "Pinch of Nom Lasagne", portion: InventoryAmount(value: 250, unit: .grams))
        let draft = try XCTUnwrap(model.selectedRow?.draft)
        XCTAssertEqual(draft.query, "Pinch of Nom Lasagne")
        XCTAssertEqual(draft.parsed.quantity, 250)
        XCTAssertEqual(draft.parsed.notices, [])
    }

    /// food-list-lexical-v6 (#353): a saved name that starts with a container is a food name. It
    /// keeps its whole name as the query. A usual mass or volume portion is withheld by the parse,
    /// as "250 ml mug of milk" is, and becomes the editable amount as if typed; a count portion and
    /// a name without a container parse as before; without a portion it has no amount.
    func testCommonFoodNamesStartingWithContainersKeepTheirNameAndPortion() throws {
        for (name, portion, written) in try [
            ("Mug Shot pasta", InventoryAmount(value: 68, unit: .grams), "68 g Mug Shot pasta"),
            ("Glass of milk", InventoryAmount(value: 200, unit: .millilitres), "200 ml Glass of milk")
        ] {
            let (model, search) = try listModel(locale: Locale(identifier: "en_GB"))
            try model.addCommonFood(name: name, portion: portion)
            let draft = try XCTUnwrap(model.selectedRow?.draft, name)
            XCTAssertEqual(draft.parsed.original, written, name)
            XCTAssertNil(draft.parsed.quantity, name)
            XCTAssertEqual(draft.parsed.notices, [.householdMeasure], name)
            XCTAssertEqual(draft.query, name, name)
            XCTAssertEqual(draft.amountValue, portion.value, name)
            XCTAssertEqual(draft.unit, portion.unit, name)
            XCTAssertEqual(draft.evidenceQuantityText, FoodAmountTextParser.editableText(portion.value), name)
            model.search()
            XCTAssertEqual(search.lastEvidence?.captureMethodVersion.value, "food-list-lexical-v6", name)
            model.review(candidate: 0)
            XCTAssertEqual(model.confirmation?.state.quantity.value, portion.value, name)
        }
        for (name, portion, written) in try [
            ("Pot of yoghurt", InventoryAmount(value: 1, unit: .count), "1 piece Pot of yoghurt"),
            ("Pot Noodle", InventoryAmount(value: 90, unit: .grams), "90 g Pot Noodle")
        ] {
            let (model, _) = try listModel(locale: Locale(identifier: "en_GB"))
            try model.addCommonFood(name: name, portion: portion)
            let draft = try XCTUnwrap(model.selectedRow?.draft, name)
            XCTAssertEqual(draft.parsed.original, written, name)
            XCTAssertEqual(draft.query, name, name)
            XCTAssertEqual(draft.parsed.quantity, portion.value, name)
            XCTAssertEqual(draft.parsed.unit, portion.unit, name)
            XCTAssertEqual(draft.parsed.notices, [], name)
            XCTAssertEqual(draft.parsed.grammarVersion, "food-list-lexical-v6", name)
        }
        for name in ["Mug Shot pasta", "Glass of milk", "Cup of tea"] {
            let (model, _) = try listModel(locale: Locale(identifier: "en_GB"))
            try model.addCommonFood(name: name, portion: nil)
            let draft = try XCTUnwrap(model.selectedRow?.draft, name)
            XCTAssertEqual(draft.query, name, name)
            XCTAssertEqual(draft.quantityText, "", name)
            XCTAssertNil(draft.parsed.quantity, name)
            XCTAssertEqual(draft.parsed.notices, [.householdMeasure], name)
        }
    }

    /// A queue saved by a v4 build restores with its v4 lines intact, never re-parsed under v5:
    /// a stored "a handful of fixture" keeps its v4 count proposal and v4 label.
    func testRestoredV4LinesKeepTheirParseAndLabel() throws {
        let checkpoint = MemoryCheckpoint()
        let ids = ListIDs()
        let stored = try FoodListParser.parseV4("a handful of fixture\n1,500 g fixture", convention: .fullStopDecimal).map {
            FoodListLineDraft(parsed: $0, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
        }
        let encoded = try JSONEncoder().encode(FoodListCheckpoint(
            input: "a handful of fixture\n1,500 g fixture", inputMethod: .pastedOrTyped, drafts: stored,
            dispositions: ["pending", "pending"], savedIDs: [nil, nil], selectedID: stored[0].id
        ))
        try checkpoint.save(try JSONDecoder().decode(FoodListCheckpoint.self, from: encoded))

        let search = ListSearch()
        let model = FoodListImportViewModel(
            service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ids,
            checkpointStore: checkpoint, amountLocale: Locale(identifier: "en_GB")
        ) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        XCTAssertEqual(model.rows.map(\.draft.parsed), stored.map(\.parsed), "v4 parses are kept, not re-parsed")
        XCTAssertEqual(model.rows.map(\.draft.parsed.grammarVersion), ["food-list-lexical-v4", "food-list-lexical-v4"])
        XCTAssertEqual(model.rows.map(\.draft.quantityText), ["1.0", "1500.0"])
        model.search()
        XCTAssertEqual(search.lastEvidence?.captureMethodVersion.value, "food-list-lexical-v4")
        guard case let .descriptor(payload) = search.lastEvidence?.originalPayload else { return XCTFail("Missing descriptor") }
        XCTAssertEqual(payload.value, #"{"lineNumber":1,"notices":[],"numeralConvention":"full_stop_decimal","original":"a handful of fixture","quantity":"1","query":"handful of fixture","unit":"count"}"#)
    }

    /// Q1 and Q6 end to end: an English "1,500 g" reaches Confirm as 1500 g, and a typed German
    /// "2,5" as 2.5; new lines are stamped v6 with the line's convention.
    func testV4AmountsReachConfirmAndEvidenceByTheLinesConvention() throws {
        let (english, englishSearch) = try listModel(locale: Locale(identifier: "en_GB"))
        english.input = "1,500 g fixture"
        english.prepare()
        english.search()
        english.review(candidate: 0)
        XCTAssertEqual(english.confirmation?.state.quantity.value, 1500)
        XCTAssertEqual(englishSearch.lastEvidence?.captureMethodVersion.value, "food-list-lexical-v6")
        guard case let .descriptor(payload) = englishSearch.lastEvidence?.originalPayload else { return XCTFail("Missing descriptor") }
        XCTAssertTrue(payload.value.contains(#""numeralConvention":"full_stop_decimal""#))
        XCTAssertTrue(payload.value.contains(#""quantity":"1500""#))

        let (german, _) = try listModel(locale: Locale(identifier: "de_DE"))
        german.input = "1.500 g fixture"
        german.prepare()
        var draft = try XCTUnwrap(german.selectedRow?.draft)
        draft.quantityText = FoodListAmountText.stored("2,5", current: draft.quantityText, parsed: draft.parsed.quantity, locale: german.amountLocale)
        german.edit(draft)
        german.search()
        german.review(candidate: 0)
        XCTAssertEqual(german.confirmation?.state.quantity.value, 2.5)
    }

    /// A queue saved by a v3 build restores with its v3 lines intact: they are not re-parsed,
    /// keep the #225 withholding and are searched with the v3 label; new lines are v6.
    func testRestoredV3LinesKeepTheirParseAndLabel() throws {
        let checkpoint = MemoryCheckpoint()
        let ids = ListIDs()
        let legacy = try FoodListParser.parse("1.500 g rice\n10 g fixture").map {
            FoodListLineDraft(parsed: $0, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
        }
        // The checkpoint as a v3 build wrote it: no v4 keys anywhere.
        let encoded = try JSONEncoder().encode(FoodListCheckpoint(
            input: "1.500 g rice\n10 g fixture", inputMethod: .pastedOrTyped, drafts: legacy,
            dispositions: ["pending", "pending"], savedIDs: [nil, nil], selectedID: legacy[1].id
        ))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("grammarVersion"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("numeralConvention"))
        try checkpoint.save(try JSONDecoder().decode(FoodListCheckpoint.self, from: encoded))

        let search = ListSearch()
        let model = FoodListImportViewModel(
            service: FoodListImportService(searcher: search), locale: try LedgerText("de_DE"), ids: ids,
            checkpointStore: checkpoint, amountLocale: Locale(identifier: "de_DE")
        ) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        XCTAssertEqual(model.rows.map(\.draft.parsed.grammarVersion), [nil, nil])
        XCTAssertEqual(model.rows.map(\.draft.parsed.quantity), [1.5, 10], "v3 parses are kept, not re-parsed")
        XCTAssertEqual(model.rows.map(\.draft.quantityText), ["", "10.0"], "the #225 safety net still withholds")
        model.search()
        XCTAssertEqual(search.lastEvidence?.captureMethodVersion.value, "food-list-lexical-v3")
        guard case let .descriptor(payload) = search.lastEvidence?.originalPayload else { return XCTFail("Missing descriptor") }
        XCTAssertEqual(payload.value, #"{"lineNumber":2,"notices":[],"original":"10 g fixture","quantity":"10.0","query":"fixture","unit":"g"}"#)

        try model.addCommonFood(name: "fixture", portion: InventoryAmount(value: 0.125, unit: .grams))
        let added = try XCTUnwrap(model.selectedRow?.draft)
        XCTAssertEqual(added.parsed.original, "0.125 g fixture", "the app writes canonical text")
        XCTAssertEqual(added.parsed.grammarVersion, "food-list-lexical-v6")
        XCTAssertEqual(added.parsed.numeralConvention, .fullStopDecimal, "the convention it was written in")
        XCTAssertEqual(added.parsed.quantity, 0.125)
    }

    /// Review finding (MEDIUM): an en_GB v4 queue restored under de_DE reads typed amounts with
    /// the field's locale, the rule the field showed and validated, never the line's stored
    /// convention. The untouched English proposal keeps its own parse.
    func testTypedAmountsFollowTheFieldLocaleAfterARegionChange() throws {
        let checkpoint = MemoryCheckpoint()
        let make = { (identifier: String) -> (FoodListImportViewModel, ListSearch) in
            let search = ListSearch()
            return (FoodListImportViewModel(service: FoodListImportService(searcher: search), locale: try LedgerText(identifier),
                                            ids: ListIDs(), checkpointStore: checkpoint,
                                            amountLocale: Locale(identifier: identifier)) { _, _ in throw FoodLedgerValidationError.invalidProvenance }, search)
        }
        let (english, _) = try make("en_GB")
        english.input = "1,500 g fixture"
        english.prepare()
        XCTAssertEqual(english.rows[0].draft.parsed.numeralConvention, .fullStopDecimal)

        let (german, search) = try make("de_DE")
        german.search()
        german.review(candidate: 0)
        XCTAssertEqual(german.confirmation?.state.quantity.value, 1500, "the untouched parse keeps its convention")
        german.finishReview()
        let locale = german.amountLocale
        for (typed, expected, canonical) in [("1,250", 1.25, "1.25"), ("1,5", 1.5, "1.5")] {
            var draft = try XCTUnwrap(german.selectedRow?.draft)
            draft.quantityText = FoodListAmountText.stored(typed, current: draft.quantityText, parsed: draft.parsed.quantity, locale: locale)
            german.edit(draft)
            XCTAssertFalse(FoodListAmountText.isRefused(typed, locale: locale), typed)
            XCTAssertEqual(german.selectedRow?.draft.quantityText, typed, "the field keeps the text as typed")
            german.search()
            guard case let .descriptor(payload) = search.lastEvidence?.originalPayload else { return XCTFail("Missing descriptor") }
            XCTAssertTrue(payload.value.contains(#""quantity":"\#(canonical)""#), payload.value)
            german.review(candidate: 0)
            XCTAssertEqual(german.confirmation?.state.quantity.value, expected, typed)
            german.finishReview()
        }
        // A refused German "1.500" never reaches search or Confirm.
        var draft = try XCTUnwrap(german.selectedRow?.draft)
        draft.quantityText = "1.500"
        german.edit(draft)
        let calls = search.calls
        german.search()
        XCTAssertEqual(search.calls, calls)
    }

    /// Review finding (LOW): a common-food portion is exact under an unrecognised decimal
    /// separator too, because the app writes and reads it in one canonical convention.
    func testCommonFoodPortionIsExactUnderAnUnspecifiedConvention() throws {
        let locale = Locale(identifier: "ar_SA")
        XCTAssertEqual(NumeralConvention(locale: locale), .unspecified, locale.decimalSeparator ?? "nil")
        let (model, _) = try listModel(locale: locale)
        try model.addCommonFood(name: "fixture", portion: InventoryAmount(value: 0.125, unit: .grams))
        let draft = try XCTUnwrap(model.selectedRow?.draft)
        XCTAssertEqual(draft.parsed.quantity, 0.125)
        XCTAssertTrue(draft.isAmountUntouched)
        XCTAssertEqual(draft.amountValue, 0.125)
        XCTAssertFalse(draft.parsed.notices.contains(.ambiguousNumber))
        model.search()
        model.review(candidate: 0)
        XCTAssertEqual(model.confirmation?.state.quantity.value, 0.125)
        // Pasted text under the same locale still follows the unspecified rule.
        XCTAssertNil(try FoodListParser.parse("0.125 g fixture", convention: NumeralConvention(locale: locale)).first?.quantity)
    }

    /// The presentation mapping from the device locale to the domain convention.
    func testNumeralConventionFollowsTheLocaleDecimalSeparator() {
        XCTAssertEqual(NumeralConvention(locale: Locale(identifier: "en_GB")), .fullStopDecimal)
        XCTAssertEqual(NumeralConvention(locale: Locale(identifier: "en_US")), .fullStopDecimal)
        XCTAssertEqual(NumeralConvention(locale: Locale(identifier: "de_DE")), .commaDecimal)
        XCTAssertEqual(NumeralConvention(locale: Locale(identifier: "fr_FR")), .commaDecimal)
    }

    /// The parser and the amount field share one rule: for every numeral in the v4 golden table,
    /// the list parse under a locale's convention has the value the Confirm field reads.
    func testV4GrammarAgreesWithTheAmountField() {
        let numerals = ["150", "1.5", "0.25", ".5", "1.500", "0.175", "1.5000", "1,5", "1,50", "1,500", "12,345", "1,5000",
                        "1,000,000", "1,000.5", "12,34,567", "1.000.000", "1.500,5", "1 500", "1\u{00A0}500", "1\u{202F}500"]
        for identifier in ["en_GB", "de_DE", "fr_FR"] {
            let locale = Locale(identifier: identifier)
            for numeral in numerals {
                XCTAssertEqual(FoodListParser.number(numeral, convention: NumeralConvention(locale: locale)),
                               FoodAmountFieldText.parse(numeral, locale: locale), "\(identifier) \(numeral)")
            }
        }
    }

    func testCommonFoodAddsToExistingReviewWithoutSavingOrSearching() throws {
        let (model, store, search) = try fixture()
        model.input = "10 g fixture"
        model.prepare()
        let original = model.rows[0].id
        model.deferLine()
        try model.addCommonFood(name: "fixture", portion: InventoryAmount(value: 25, unit: .grams))
        XCTAssertEqual(model.rows.count, 2)
        XCTAssertEqual(model.rows[0].id, original)
        XCTAssertEqual(model.rows[0].status, .deferred)
        XCTAssertEqual(model.selectedRow?.draft.quantityText, "25.0")
        XCTAssertEqual(model.selectedRow?.draft.unit, .grams)
        XCTAssertEqual(search.calls, 0)
        XCTAssertEqual(try store.counts().operations, 0)
        XCTAssertThrowsError(try model.addCommonFood(name: "oats\nmilk", portion: nil))
    }

    func testResumeRestoresQueueAndReconcilesCommittedSave() throws {
        let checkpointStore = MemoryCheckpoint()
        let (fixture, _, search) = try fixture()
        let ids = ListIDs()
        let model = FoodListImportViewModel(service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ids,
            checkpointStore: checkpointStore) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        model.input = "10 g fixture\n20 g fixture"
        model.prepare()
        let first = model.rows[0].id
        let second = model.rows[1].id
        model.deferLine()
        var draft = try XCTUnwrap(model.selectedRow?.draft)
        draft.quantityText = "30"
        model.edit(draft)
        let logID = try LogItemID("00000000-0000-0000-0000-000000000999")
        let resumed = FoodListImportViewModel(service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ids,
            checkpointStore: checkpointStore, recoveredLogItemID: { $0 == second ? logID : nil }) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        XCTAssertEqual(resumed.rows[0].id, first)
        XCTAssertEqual(resumed.rows[0].status, .deferred)
        XCTAssertEqual(resumed.rows[1].status, .saved(logID))
        XCTAssertEqual(resumed.rows[1].draft.quantityText, "30")
        XCTAssertEqual(resumed.selectedID, second)
        resumed.search()
        XCTAssertEqual(search.calls, 0)
        _ = fixture
    }

    func testCheckpointFailureKeepsQuickAddVisibleAndRetriesSameRow() throws {
        let checkpointStore = MemoryCheckpoint()
        let (_, _, search) = try fixture()
        let model = FoodListImportViewModel(service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ListIDs(),
            checkpointStore: checkpointStore) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        checkpointStore.failWrites = true
        try model.addCommonFood(name: "fixture", portion: InventoryAmount(value: 25, unit: .grams))
        let rowID = try XCTUnwrap(model.selectedID)
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertNotNil(model.checkpointErrorMessage)
        XCTAssertNil(try checkpointStore.load())
        checkpointStore.failWrites = false
        model.retryCheckpoint()
        XCTAssertNil(model.checkpointErrorMessage)
        XCTAssertEqual(try checkpointStore.load()?.drafts.map(\.id), [rowID])
    }

    func testUnavailableCheckpointCanResumeAfterRetryWithoutOverwriting() throws {
        let checkpoint = MemoryCheckpoint()
        let (_, _, search) = try fixture()
        let ids = ListIDs()
        let make = {
            FoodListImportViewModel(service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ids,
                checkpointStore: checkpoint) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        }
        let original = try make()
        original.input = "25 g fixture"; original.prepare()
        let rowID = original.rows.first?.id
        checkpoint.failReads = true
        let resumed = try make()
        XCTAssertNotNil(resumed.checkpointErrorMessage)
        resumed.input = "Must not overwrite saved queue"
        checkpoint.failReads = false
        resumed.retryCheckpoint()
        XCTAssertNil(resumed.checkpointErrorMessage)
        XCTAssertEqual(resumed.input, "25 g fixture")
        XCTAssertEqual(resumed.rows.first?.id, rowID)
    }

    func testDuplicateLinesSaveIndependentlyAndRetryDoesNotDuplicate() throws {
        let (model, store, search) = try fixture()
        model.input = "25 g fixture\n\n25 g fixture\nunknown product"
        model.prepare()
        XCTAssertEqual(model.rows.count, 3)
        XCTAssertEqual(model.rows.map { $0.draft.parsed.lineNumber }, [1, 3, 4])
        XCTAssertNotEqual(model.rows[0].id, model.rows[1].id)
        let firstID = model.rows[0].id
        model.search()
        model.review(candidate: 0)
        let review = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(review.state.decision, .undecided)
        review.save()
        XCTAssertEqual(model.savedCount, 0)
        guard case .failed = model.rows[0].status else { return XCTFail("Missing failed row") }
        review.send(.accept)
        review.save()
        review.save()
        XCTAssertEqual(model.savedCount, 1)
        XCTAssertEqual(try store.counts().logItemVersions, 1)
        model.finishReview()
        XCTAssertEqual(model.selectedID, model.rows[1].id)
        model.search()
        model.review(candidate: 0)
        model.confirmation?.send(.accept)
        model.confirmation?.save()
        model.finishReview()
        XCTAssertEqual(model.savedCount, 2)
        XCTAssertEqual(try store.counts().logItemVersions, 2)
        XCTAssertEqual(model.progress, "2 of 3 saved · 1 not saved")
        model.deferLine()
        XCTAssertFalse(model.progress.contains("All"))
        model.select(firstID)
        let callCount = search.calls
        model.search()
        model.review(candidate: 0)
        XCTAssertNil(model.confirmation)
        XCTAssertEqual(search.calls, callCount)
        XCTAssertEqual(try store.counts().logItemVersions, 2)
    }

    func testEditsInvalidateCandidatesAndNoResultAndDeclineRemainVisible() throws {
        let (model, store, search) = try fixture()
        model.input = "fixture\n40 g fixture"
        model.prepare()
        model.search()
        model.review(candidate: 0)
        XCTAssertNil(model.confirmation?.state.quantity.value)
        model.finishReview()
        var draft = try XCTUnwrap(model.selectedRow?.draft)
        draft.query = "corrected food"
        model.edit(draft)
        XCTAssertNil(model.selectedRow?.route)
        model.review(candidate: 0)
        XCTAssertNil(model.confirmation)
        search.returnsNoResult = true
        model.search()
        guard case .unresolved = model.selectedRow?.status else { return XCTFail("Missing unresolved row") }
        model.declineLine()
        XCTAssertEqual(model.rows[0].status, .declined)
        XCTAssertEqual(model.selectedID, model.rows[1].id)
        XCTAssertEqual(try store.counts().operations, 0)
        let originalRows = model.rows.map(\.id)
        model.input = "new list"
        model.prepare()
        XCTAssertEqual(model.rows.map(\.id), originalRows)
        model.startNewList()
        XCTAssertTrue(model.rows.isEmpty)
    }

    func testEmptyAndOversizedInputAreRecoverableAndViewSupportsLargeText() throws {
        let (model, _, _) = try fixture()
        model.prepare()
        XCTAssertNotNil(model.errorMessage)
        model.input = String(repeating: "x", count: 30_001)
        model.prepare()
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.input.count, 30_001)
        let view = FoodListImportView(model: model).environment(\.dynamicTypeSize, .accessibility5)
        XCTAssertFalse(String(describing: view).isEmpty)
    }

    func testContextIsVisibleExcludedFromFoodCountAndCanBeCorrected() throws {
        let (model, _, _) = try fixture()
        model.input = "Lunch:\n13:45\n40 g fixture\n£8.70"
        model.prepare()
        XCTAssertEqual(model.rows.count, 4)
        XCTAssertEqual(model.selectedID, model.rows[2].id)
        XCTAssertEqual(model.progress, "0 of 1 saved · 1 not saved · 3 context lines")
        model.select(model.rows[0].id)
        model.reviewContextAsFood()
        XCTAssertEqual(model.rows[0].status, .pending)
        XCTAssertEqual(model.progress, "0 of 2 saved · 2 not saved · 2 context lines")
    }

    func testReviewedSpeechAppendsWithoutParsingSearchingOrSaving() throws {
        let (model, store, search) = try fixture()
        model.input = "25 g fixture"
        XCTAssertTrue(model.appendReviewedSpeech("125 ml milk"))
        XCTAssertEqual(model.input, "25 g fixture\n125 ml milk")
        XCTAssertEqual(model.inputMethod, .reviewedSpeechText)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(search.calls, 0)
        XCTAssertEqual(try store.counts().operations, 0)
        XCTAssertFalse(model.appendReviewedSpeech(String(repeating: "x", count: 30_001)))
        model.prepare()
        XCTAssertEqual(model.rows.map(\.draft.inputMethod), [.reviewedSpeechText, .reviewedSpeechText])
        model.search()
        XCTAssertEqual(search.lastEvidence?.captureMethod.value, "reviewed_food_text_with_on_device_speech")
        XCTAssertEqual(search.lastEvidence?.kind, .manual)
        XCTAssertEqual(try store.counts().operations, 0)
        XCTAssertFalse(model.appendReviewedSpeech("late text"))
        model.startNewList()
        XCTAssertEqual(model.inputMethod, .pastedOrTyped)
    }

    private func listModel(locale: Locale) throws -> (FoodListImportViewModel, ListSearch) {
        let search = ListSearch()
        let model = FoodListImportViewModel(
            service: FoodListImportService(searcher: search), locale: try LedgerText(locale.identifier), ids: ListIDs(),
            amountLocale: locale
        ) { _, _ in throw FoodLedgerValidationError.invalidProvenance }
        return (model, search)
    }

    private func fixture() throws -> (FoodListImportViewModel, InMemoryFoodLedgerStore, ListSearch) {
        let ids = ListIDs()
        let store = InMemoryFoodLedgerStore()
        let ledger = FoodLedgerService(
            actorID: try ids.makeID(ActorTag.self), committer: store, clock: ListClock(),
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()
        )
        let confirmations = FoodConfirmationService(ledger: ledger, reader: store, clock: ListClock(), ids: ids, digester: SHA256Digester())
        let search = ListSearch()
        return (FoodListImportViewModel(
            service: FoodListImportService(searcher: search), locale: try LedgerText("en_GB"), ids: ids,
            now: { ListClock().now() }
        ) { state, operationID in
            try confirmations.save(state, operationID: operationID, idempotencyKey: LedgerText(operationID.rawValue))
        }, store, search)
    }
}

private final class MemoryCheckpoint: FoodListCheckpointStoring, @unchecked Sendable {
    private var value: FoodListCheckpoint?
    var failWrites = false
    var failReads = false
    func load() throws -> FoodListCheckpoint? {
        if failReads { throw FoodLedgerValidationError.invalidProvenance }
        return value
    }
    func save(_ checkpoint: FoodListCheckpoint) throws {
        if failWrites { throw FoodLedgerValidationError.invalidProvenance }
        try checkpoint.validate(); value = checkpoint
    }
}

private struct ListClock: LedgerClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }
}

private final class ListIDs: LedgerIDGenerating, @unchecked Sendable {
    private var counter = 0
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        counter += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", counter))
    }
}

private final class ListSearch: GenericFoodSearching, @unchecked Sendable {
    var calls = 0
    var lastEvidence: CaptureEvidence?
    var returnsNoResult = false
    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        calls += 1
        let evidence = try XCTUnwrap(request.captureEvidence)
        lastEvidence = evidence
        if returnsNoResult { return .noResult(GenericFoodNoResultRoute(evidence: evidence)) }
        let release = SourceRelease(
            sourceReleaseID: try ExternalIdentifier("fixture"), sourceID: try ExternalIdentifier("fixture"),
            releasedAt: ListClock().now(), artifactHash: try SHA256Digest(String(repeating: "a", count: 64)),
            schemaVersion: try LedgerText("1"), pipelineVersion: try LedgerText("1"),
            licence: try LedgerText("synthetic"), attribution: try LedgerText("synthetic"),
            manifestHash: try SHA256Digest(String(repeating: "b", count: 64))
        )
        let identity = try DecisiveIdentity(
            preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")),
            fortification: .unfortified, servingBasis: .per100Grams
        )
        let candidate = try PopulatedFoodCandidate(
            candidate: ProviderNeutralCandidate(
                sourceReleaseID: release.sourceReleaseID, recordID: ExternalIdentifier("fixture"),
                identity: identity, edibleQuantity: .known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil),
                nutrients: NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: .unknown(.notDeclared)) }),
                evidenceIDs: [evidence.evidenceID]
            ), name: LedgerText("fixture"), itemClass: .food
        )
        return .confirmation(GenericFoodConfirmationRoute(
            confirmation: try PopulatedFoodConfirmation(
                evidence: [evidence], sourceReleases: [release], candidates: [candidate],
                expectedIdentity: identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity
            ), matches: [GenericFoodMatch(candidate: candidate, isExactName: true)]
        ))
    }
}
