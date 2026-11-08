import FoodLedgerApplication
import XCTest

/// Contract tests 1, 18 and 27 of docs/pasted-label-ai-text-v1.md (11.5): one vector for every
/// shape in the 4.3 list, whole-token boundaries, scalar offsets, and byte-identical output on
/// repeated runs. Synthetic text only.
final class PastedLabelTextLocatorTests: XCTestCase {
    typealias Locator = PastedLabelTextLocator

    static let per100 = Locator.Header(id: "h1", printedText: "Per 100g", basis: "per_100g")
    static let perServing = Locator.Header(id: "h2", printedText: "Per serving", basis: "per_serving")
    static let referenceIntake = Locator.Header(id: "h3", printedText: "%RI", basis: "reference_intake")

    static func row(_ label: String, _ values: [(String, String)]) -> Locator.Row {
        Locator.Row(printedLabel: label, values: values.map { Locator.Value(headerID: $0.0, printedText: $0.1) })
    }

    /// The scalar range of the `nth` (1-based) occurrence of `needle` in `text`.
    static func scalars(_ needle: String, in text: String, nth: Int = 1) -> Range<Int> {
        let haystack = Array(text.unicodeScalars), pattern = Array(needle.unicodeScalars)
        var seen = 0
        for start in 0...(haystack.count - pattern.count) where Array(haystack[start..<(start + pattern.count)]) == pattern {
            seen += 1
            if seen == nth { return start..<(start + pattern.count) }
        }
        XCTFail("\(needle) not in text")
        return 0..<0
    }

    func statuses(_ result: Locator.Result) -> [Locator.Status] { result.values.map(\.status) }

    // MARK: Layouts

    func testOneValuePerLine() {
        let text = "Typical values\nPer 100g\nPer serving\nEnergy\n1046kJ\n523kJ\nFat\n5g\n2.5g\n"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing],
                                    rows: [Self.row("Energy", [("h1", "1046kJ"), ("h2", "523kJ")]), Self.row("Fat", [("h1", "5g"), ("h2", "2.5g")])])
        XCTAssertEqual(statuses(result), [.found(Self.scalars("1046kJ", in: text)), .found(Self.scalars("523kJ", in: text)),
                                          .found(Self.scalars("5g", in: text)), .found(Self.scalars("2.5g", in: text))])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention })
        XCTAssertEqual(result.headers.map(\.status), [.found(Self.scalars("Per 100g", in: text)), .found(Self.scalars("Per serving", in: text))])
    }

    func testOneRowPerLine() {
        let text = "Per 100g Per serving\nFat 5g 2.5g\nSalt 0.5g 0.25g"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing],
                                    rows: [Self.row("Fat", [("h1", "5g"), ("h2", "2.5g")]), Self.row("Salt", [("h1", "0.5g"), ("h2", "0.25g")])])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention })
        XCTAssertEqual(result.rows.map(\.block), [Self.scalars("Fat", in: text).upperBound..<Self.scalars("Salt", in: text).lowerBound,
                                                  Self.scalars("Salt", in: text).upperBound..<text.unicodeScalars.count])
    }

    func testMisalignedColumnsFewerValuesThanHeadersIsAlwaysAttention() {
        let text = "Per 100g Per serving\nFat 5g\nSalt 0.5g 0.25g"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing],
                                    rows: [Self.row("Fat", [("h1", "5g"), ("h2", "2.5g")]), Self.row("Salt", [("h1", "0.5g"), ("h2", "0.25g")])])
        XCTAssertEqual(result.rows[0].attention, [.fewerCellsThanHeaders])
        XCTAssertEqual(result.values[0].status, .found(Self.scalars("5g", in: text)))
        XCTAssertTrue(result.values[0].needsAttention, "a found value in a short block is still attention")
        XCTAssertEqual(result.values[1].status, .notFound)
        XCTAssertFalse(result.values[2].needsAttention)
    }

    func testMoreValuesThanHeadersIsAttention() {
        let text = "Per 100g Per serving\nFat 5g 2.5g 1g"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing], rows: [Self.row("Fat", [("h1", "5g"), ("h2", "2.5g")])])
        XCTAssertEqual(result.rows[0].attention, [.moreCellsThanHeaders])
        XCTAssertTrue(result.values.allSatisfy(\.needsAttention))
    }

    func testPercentColumnMatchesReferenceIntake() {
        let text = "Per 100g Per serving %RI\nFat 5g 2.5g 4%\nSalt 0.5g 0.25g 4%"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing, Self.referenceIntake],
                                    rows: [Self.row("Fat", [("h1", "5g"), ("h2", "2.5g"), ("h3", "4%")]),
                                           Self.row("Salt", [("h1", "0.5g"), ("h2", "0.25g"), ("h3", "4%")])])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention })
        XCTAssertEqual(result.values[2].status, .found(Self.scalars("4%", in: text)))
        XCTAssertEqual(result.values[5].status, .found(Self.scalars("4%", in: text, nth: 2)))
    }

    func testPercentWithTooFewOtherCellsIsAttention() {
        let text = "Per 100g Per serving %RI\nFat 5g 8%"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing, Self.referenceIntake],
                                    rows: [Self.row("Fat", [("h1", "5g"), ("h2", "2.5g"), ("h3", "8%")])])
        XCTAssertEqual(result.rows[0].attention, [.fewerCellsThanHeaders])
        XCTAssertTrue(result.values.allSatisfy(\.needsAttention))
    }

    // MARK: Energy

    func testKilojouleAndKilocaloriePairsAreOneCellEachTwoPairsOnOneLine() {
        let text = "Per 100g Per serving\nEnergy 1046kJ/250kcal 523kJ/125kcal"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing],
                                    rows: [Self.row("Energy", [("h1", "1046kJ"), ("h2", "523kJ")]),
                                           Self.row("Energy", [("h1", "250kcal"), ("h2", "125kcal")])])
        XCTAssertEqual(result.rows.map(\.attention), [[], []], "two pairs are two cells, matching two headers")
        XCTAssertEqual(statuses(result), ["1046kJ", "523kJ", "250kcal", "125kcal"].map { .found(Self.scalars($0, in: text)) })
    }

    func testKilocalorieFirstPairIsOneCell() {
        let text = "Per 100g\nEnergy 250kcal (1046kJ)"
        let result = Locator.locate(text: text, headers: [Self.per100],
                                    rows: [Self.row("Energy", [("h1", "1046kJ")]), Self.row("Energy", [("h1", "250kcal")])])
        XCTAssertEqual(result.rows[0].attention, [])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention })
    }

    // MARK: Tokens and words

    func testRepeatedValuesAreMatchedByOrdinal() {
        let text = "Per 100g Per serving\nTrans fat 0g 0g"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing], rows: [Self.row("Trans fat", [("h1", "0g"), ("h2", "0g")])])
        // The first `0g` of the text is inside the header `Per 100g`.
        XCTAssertEqual(statuses(result), [.found(Self.scalars("0g", in: text, nth: 2)), .found(Self.scalars("0g", in: text, nth: 3))])
    }

    func testSubstringsNeverMatch() {
        let text = "Per 100g Per serving\nFibre 11g 0.1g\nFat 5g 2g\nSaturated fat 1g 0.5g"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing],
                                    rows: [Self.row("Fibre", [("h1", "1g"), ("h2", "1g")]), Self.row("Fat", [("h1", "5g"), ("h2", "2g")]),
                                           Self.row("Saturated fat", [("h1", "1g"), ("h2", "0.5g")])])
        XCTAssertEqual(result.values[0].status, .notFound, "1g is not found inside 11g")
        XCTAssertEqual(result.values[1].status, .notFound, "1g is not found inside 0.1g")
        XCTAssertEqual(result.rows[1].label, .found(Self.scalars("Fat", in: text)), "Fat is taken outside Saturated fat")
        XCTAssertEqual(result.rows[2].label, .found(Self.scalars("Saturated fat", in: text)))
        XCTAssertTrue(result.values[2...].allSatisfy { !$0.needsAttention })
    }

    func testRecurringRowLabelIsAmbiguous() {
        let text = "Per 100g Per serving\nEnergy 1046kJ 523kJ\nEnergy 250kcal 125kcal"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing],
                                    rows: [Self.row("Energy", [("h1", "1046kJ"), ("h2", "523kJ")]),
                                           Self.row("Energy", [("h1", "250kcal"), ("h2", "125kcal")])])
        XCTAssertEqual(result.rows.map(\.label), [.ambiguous, .ambiguous])
        XCTAssertEqual(statuses(result), Array(repeating: .ambiguous, count: 4))
        XCTAssertTrue(result.values.allSatisfy { $0.attention == [.rowLabelAmbiguous] })
    }

    func testLastBlockEndsAtFirstBlankLineAfterAValue() {
        let text = "Per 100g Per serving\nSalt\n0.5g\n0.25g\n\nPack contains 4 servings"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing], rows: [Self.row("Salt", [("h1", "0.5g"), ("h2", "0.25g")])])
        XCTAssertEqual(result.rows[0].attention, [])
        XCTAssertEqual(result.rows[0].block?.upperBound, Self.scalars("\n\n", in: text).lowerBound + 1)
    }

    func testLastBlockFollowedByFooterWithNoBlankLineIsAttention() {
        let text = "Per 100g Per serving\nSalt 0.5g 0.25g\nPack contains 4 servings"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing], rows: [Self.row("Salt", [("h1", "0.5g"), ("h2", "0.25g")])])
        XCTAssertEqual(result.rows[0].attention, [.moreCellsThanHeaders])
        XCTAssertTrue(result.values.allSatisfy(\.needsAttention))
    }

    func testHundredGramHeaderTokenIsNotACellAndAHeaderInsideABlockIsAttention() {
        let header = Locator.Header(id: "h1", printedText: "100g", basis: "per_100g")
        let text = "Energy 1046kJ\n100g\nFat 5g\n1100g"
        let result = Locator.locate(text: text, headers: [header],
                                    rows: [Self.row("Energy", [("h1", "1046kJ")]), Self.row("Fat", [("h1", "5g")])])
        XCTAssertEqual(result.headers[0].status, .found(Self.scalars("100g", in: text)), "100g is not a whole word inside 1100g")
        XCTAssertEqual(result.rows[0].attention, [.headerInsideBlock],
                       "the header's own token is not a cell, but a header inside a block is attention (F1)")
        XCTAssertEqual(result.rows[1].attention, [.moreCellsThanHeaders], "1100g is a cell of the last block")
    }

    func testDecimalCommaNextToBoundaryComma() {
        let text = "Per 100g Per serving\nFat 0,5g, 2g\nEnergy 1,046kJ 1,046.5kJ"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing],
                                    rows: [Self.row("Fat", [("h1", "0,5g"), ("h2", "2g")]), Self.row("Energy", [("h1", "1,046kJ"), ("h2", "1,046.5kJ")])])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention })
        let scan = PastedLabelTextScan(text)
        XCTAssertEqual(scan.tokens.map(\.decimalText), ["100", "0.5", "2", "1046", "1046.5"])
        XCTAssertEqual(scan.tokens.map(\.canonicalUnit), ["g", "g", "g", "kJ", "kJ"])
    }

    func testTaiwanComparatorsWithCJKUnits() {
        let text = "每100公克 每份\n鈉 少於5毫克 ＜1毫克"
        let headers = [Locator.Header(id: "h1", printedText: "每100公克", basis: "per_100g"), Locator.Header(id: "h2", printedText: "每份", basis: "per_serving")]
        let result = Locator.locate(text: text, headers: headers, rows: [Self.row("鈉", [("h1", "少於5毫克"), ("h2", "＜1毫克")])])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention })
        let tokens = PastedLabelTextScan(text).tokens.filter { $0.start > Self.scalars("鈉", in: text).lowerBound }
        XCTAssertEqual(tokens.map(\.comparator), ["<", "<"])
        XCTAssertEqual(tokens.map(\.canonicalUnit), ["mg", "mg"])
    }

    func testCJKWholeWordHeaderAndRowLabelLocation() {
        let text = "每100公克 每份\n脂肪 5公克 2公克\n飽和脂肪 1公克 0.5公克"
        let headers = [Locator.Header(id: "h1", printedText: "每100公克", basis: "per_100g"), Locator.Header(id: "h2", printedText: "份", basis: "per_serving")]
        let result = Locator.locate(text: text, headers: headers,
                                    rows: [Self.row("脂肪", [("h1", "5公克")]), Self.row("飽和脂肪", [("h1", "1公克")])])
        XCTAssertEqual(result.headers[1].status, .notFound, "份 inside 每份 is not a whole word")
        XCTAssertEqual(result.rows[0].label, .found(Self.scalars("脂肪", in: text)))
        XCTAssertEqual(result.rows[1].label, .found(Self.scalars("飽和脂肪", in: text)))
        XCTAssertEqual(result.values[0].status, .found(Self.scalars("5公克", in: text)))
        XCTAssertEqual(result.values[0].attention, [.moreCellsThanHeaders], "two cells against one located amount header")
    }

    func testCJKWordNextToAValueTokenIsWhole() {
        let text = "每份\n鈉少於5毫克"
        let result = Locator.locate(text: text, headers: [Locator.Header(id: "h1", printedText: "每份", basis: "per_serving")],
                                    rows: [Self.row("鈉", [("h1", "少於5毫克")])])
        XCTAssertEqual(result.rows[0].label, .found(Self.scalars("鈉", in: text)), "a CJK word may touch a value token")
        XCTAssertEqual(result.values[0].status, .notFound, "the token itself does not start at a boundary")
    }

    func testFullWidthPunctuationBoundsATokenAndACJKLetterDoesNot() {
        let perServing = [Locator.Header(id: "h1", printedText: "每份", basis: "per_serving")]
        let colon = "每份\n熱量：250大卡"
        XCTAssertEqual(Locator.locate(text: colon, headers: perServing, rows: [Self.row("熱量", [("h1", "250大卡")])]).values[0].status,
                       .found(Self.scalars("250大卡", in: colon)))
        let brackets = "每份\n脂肪（0.5公克）"
        XCTAssertEqual(Locator.locate(text: brackets, headers: perServing, rows: [Self.row("脂肪", [("h1", "0.5公克")])]).values[0].status,
                       .found(Self.scalars("0.5公克", in: brackets)))
        let glued = "每份\n鈉5毫克"
        let gluedResult = Locator.locate(text: glued, headers: perServing, rows: [Self.row("鈉", [("h1", "5毫克")])])
        XCTAssertEqual(gluedResult.rows[0].label, .found(Self.scalars("鈉", in: glued)))
        XCTAssertEqual(gluedResult.values[0].status, .notFound, "a value glued to a CJK letter is not a whole token")
        let separated = PastedLabelTextScan("糖 1公克／2公克，3公克、4公克。［5公克］｜6公克；7公克")
        XCTAssertEqual(separated.tokens.map(\.decimalText), ["1", "2", "3", "4", "5", "6", "7"])
        XCTAssertEqual(PastedLabelTextScan("糖 1，5公克").tokens.map(\.decimalText), [],
                       "a full-width comma between two digits is neither a decimal mark nor a boundary")
    }

    // MARK: Review fixes (F2, F4, F7, F8, F10)

    func testBoundsOutsideTheTokenAreAttention() {
        for (line, printed) in [("Salt Less than 0.5g", "0.5g"), ("Salt LESS THAN 0.5g", "0.5g"), ("Salt \u{2266} 0.5g", "0.5g"), ("Salt ~ 5g", "5g")] {
            let text = "Per 100g\n" + line
            let result = Locator.locate(text: text, headers: [Self.per100], rows: [Self.row("Salt", [("h1", printed)])])
            XCTAssertEqual(result.values[0].status, .found(Self.scalars(printed, in: text)), line)
            XCTAssertEqual(result.values[0].attention, [.comparatorOutsideToken], line)
        }
        let absorbed = Locator.locate(text: "Per 100g\nSalt less than 0.5g", headers: [Self.per100], rows: [Self.row("Salt", [("h1", "less than 0.5g")])])
        XCTAssertFalse(absorbed.values[0].needsAttention, "a listed comparator inside the token is the token's own bound")
        let word = Locator.locate(text: "Per 100g\nSalt Regardless than 0.5g", headers: [Self.per100], rows: [Self.row("Salt", [("h1", "0.5g")])])
        XCTAssertFalse(word.values[0].needsAttention, "less must start a word")
    }

    func testShortLabelInsideALongerVocabularyLabelIsAmbiguous() {
        let text = "Per 100g\nFat 5g\nSaturated fat 1g\nCarbohydrate 30g"
        let result = Locator.locate(text: text, headers: [Self.per100], rows: [Self.row("fat", [("h1", "1g")]), Self.row("Carbohydrate", [("h1", "30g")])])
        XCTAssertEqual(result.rows[0].label, .ambiguous)
        XCTAssertTrue(result.values[0].needsAttention)
        XCTAssertFalse(result.values[1].needsAttention)
    }

    func testTwoReferenceIntakeHeadersPutPercentValuesUnderAttention() {
        let second = Locator.Header(id: "h4", printedText: "%RI per serving", basis: "reference_intake")
        let text = "Per 100g %RI %RI per serving\nFat 5g 7% 3%"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.referenceIntake, second],
                                    rows: [Self.row("Fat", [("h1", "5g"), ("h3", "7%"), ("h4", "3%")])])
        XCTAssertFalse(result.values[0].needsAttention)
        XCTAssertTrue(result.values[1].attention.contains(.multipleReferenceIntakeHeaders))
        XCTAssertTrue(result.values[2].attention.contains(.multipleReferenceIntakeHeaders))
    }

    func testTwoLineUKEnergyLayoutIsAttention() {
        // The pairing crosses the line break (523kJ with 250kcal), so the block holds three cells.
        let text = "Per 100g Per serving\nEnergy 1046kJ 523kJ\n250kcal 125kcal\nFat 5g 2.5g"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing],
                                    rows: [Self.row("Energy", [("h1", "1046kJ"), ("h2", "523kJ")]), Self.row("Energy", [("h1", "250kcal"), ("h2", "125kcal")]),
                                           Self.row("Fat", [("h1", "5g"), ("h2", "2.5g")])])
        XCTAssertEqual(result.rows[0].attention, [.moreCellsThanHeaders])
        XCTAssertTrue(result.values[0..<4].allSatisfy(\.needsAttention))
        XCTAssertFalse(result.values[4].needsAttention)
    }

    func testLeadingZeroThousandsGroupIsPinned() {
        let token = PastedLabelTextScan("Fat 0,500g").tokens[0]
        XCTAssertEqual(token.numberText, "0,500")
        XCTAssertEqual(token.decimalText, "0500", "the thousands rule reads it as 500; A2's mapping must treat it as attention")
        XCTAssertEqual(token.canonicalUnit, "g")
    }

    // MARK: Qodo findings on #421

    func testTwoHeaderIDsOnOneSpanAreAttention() {
        let a = Locator.Header(id: "h1", printedText: "Per 100g", basis: "per_100g")
        let b = Locator.Header(id: "h2", printedText: "Per 100g", basis: "per_serving")
        let result = Locator.locate(text: "Per 100g\nFat 5g 2g", headers: [a, b], rows: [Self.row("Fat", [("h1", "5g"), ("h2", "2g")])])
        XCTAssertTrue(result.values.allSatisfy { $0.attention.contains(.headerSpanShared) })
    }

    func testOmittedPrintedRowEndsTheBlockAbove() {
        let text = "Per 100g Per serving\nFat 1g\nSalt 2g"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing], rows: [Self.row("Fat", [("h1", "1g"), ("h2", "2g")])])
        XCTAssertEqual(result.rows[0].block, Self.scalars("Fat", in: text).upperBound..<Self.scalars("Salt", in: text).lowerBound)
        XCTAssertEqual(result.rows[0].attention, [.fewerCellsThanHeaders])
        XCTAssertEqual(result.values[1].status, .notFound, "Salt's 2g belongs to no model row")
        XCTAssertTrue(result.values[1].needsAttention)
        // `of which` before an omitted label still starts a row; a label inside a word run does not.
        let ofWhich = Locator.locate(text: "Per 100g\nFat 5g\n- of which saturates 1g", headers: [Self.per100], rows: [Self.row("Fat", [("h1", "5g")])])
        XCTAssertFalse(ofWhich.values[0].needsAttention)
        XCTAssertEqual(ofWhich.rows[0].attention, [])
    }

    func testComparatorPastPunctuationIsAttention() {
        let english = "Per 100g\nSalt less than: 0.5g"
        let en = Locator.locate(text: english, headers: [Self.per100], rows: [Self.row("Salt", [("h1", "0.5g")])])
        XCTAssertEqual(en.values[0].status, .found(Self.scalars("0.5g", in: english)))
        XCTAssertEqual(en.values[0].attention, [.comparatorOutsideToken])
        let taiwan = "每份\n鈉 少於：5毫克"
        let tw = Locator.locate(text: taiwan, headers: [Locator.Header(id: "h1", printedText: "每份", basis: "per_serving")],
                                rows: [Self.row("鈉", [("h1", "5毫克")])])
        XCTAssertEqual(tw.values[0].status, .found(Self.scalars("5毫克", in: taiwan)))
        XCTAssertEqual(tw.values[0].attention, [.comparatorOutsideToken])
        let plain = Locator.locate(text: "Per 100g\nSalt: 0.5g", headers: [Self.per100], rows: [Self.row("Salt", [("h1", "0.5g")])])
        XCTAssertFalse(plain.values[0].needsAttention, "a label's colon is not a bound")
    }

    func testBoundWordsOnEitherSideAreAttention() {
        let perServing = [Locator.Header(id: "h1", printedText: "每份", basis: "per_serving")]
        for (line, printed) in [("鈉 未滿 0.5 公克", "0.5 公克"), ("鈉 0.5 公克 以下", "0.5 公克"), ("鈉 低於 0.5公克", "0.5公克"),
                                ("鈉 不到：0.5公克", "0.5公克"), ("鈉 0.5公克（以內）", "0.5公克")] {
            let text = "每份\n" + line
            let result = Locator.locate(text: text, headers: perServing, rows: [Self.row("鈉", [("h1", printed)])])
            XCTAssertEqual(result.values[0].status, .found(Self.scalars(printed, in: text)), line)
            XCTAssertEqual(result.values[0].attention, [.comparatorOutsideToken], line)
        }
        for (line, printed) in [("Salt 0.5g or less", "0.5g"), ("Salt 0.5g, max", "0.5g"), ("Salt Max 0.5g", "0.5g"), ("Salt UNDER 0.5g", "0.5g")] {
            let text = "Per 100g\n" + line
            let result = Locator.locate(text: text, headers: [Self.per100], rows: [Self.row("Salt", [("h1", printed)])])
            XCTAssertEqual(result.values[0].attention, [.comparatorOutsideToken], line)
        }
        let clean = "每份\n鈉 0.5 公克"
        XCTAssertFalse(Locator.locate(text: clean, headers: perServing, rows: [Self.row("鈉", [("h1", "0.5 公克")])]).values[0].needsAttention)
        let maximal = Locator.locate(text: "Per 100g\nSalt 0.5g maximal", headers: [Self.per100], rows: [Self.row("Salt", [("h1", "0.5g")])])
        XCTAssertFalse(maximal.values[0].needsAttention, "max must end a word")
    }

    /// A token that prints its own comparator keeps its bound, so a redundant bound word beside it is
    /// not an extra attention item (A1 finding carried to A2 of #416). The bare token still is.
    func testATokenWithItsOwnComparatorIgnoresARedundantBoundWord() {
        for (line, printed) in [("Salt <= 0.5g or less", "<= 0.5g"), ("Salt less than 0.5g max", "less than 0.5g"), ("Salt ≤0.5g, maximum", "≤0.5g")] {
            let text = "Per 100g\n" + line
            let result = Locator.locate(text: text, headers: [Self.per100], rows: [Self.row("Salt", [("h1", printed)])])
            XCTAssertEqual(result.values[0].status, .found(Self.scalars(printed, in: text)), line)
            XCTAssertEqual(result.values[0].attention, [], line)
        }
        let taiwan = "每份\n鈉 少於5毫克 以下"
        let tw = Locator.locate(text: taiwan, headers: [Locator.Header(id: "h1", printedText: "每份", basis: "per_serving")],
                                rows: [Self.row("鈉", [("h1", "少於5毫克")])])
        XCTAssertEqual(tw.values[0].attention, [])
        let bare = Locator.locate(text: "Per 100g\nSalt 0.5g or less", headers: [Self.per100], rows: [Self.row("Salt", [("h1", "0.5g")])])
        XCTAssertEqual(bare.values[0].attention, [.comparatorOutsideToken], "a bare token is still under attention")
    }

    /// A2 gate finding 4: only a bound that agrees with the token's own comparator is suppressed; a
    /// contradicting bound word or symbol stays under attention, and a lower bound beside a bare
    /// token is attention too.
    func testAContradictingBoundStaysUnderAttention() {
        for (line, printed) in [("Salt <5g or more", "<5g"), ("Salt at least <5g", "<5g"), ("Salt ≥ <5g", "<5g"), ("Salt <=5g minimum", "<=5g"),
                                ("Salt 5g or more", "5g"), ("Salt at least 5g", "5g"), ("Salt over 5g", "5g")] {
            let text = "Per 100g\n" + line
            let result = Locator.locate(text: text, headers: [Self.per100], rows: [Self.row("Salt", [("h1", printed)])])
            XCTAssertEqual(result.values[0].attention, [.comparatorOutsideToken], line)
        }
        let perServing = [Locator.Header(id: "h1", printedText: "每份", basis: "per_serving")]
        for (line, printed, attention) in [("鈉 少於5毫克 以上", "少於5毫克", true), ("鈉 少於5毫克，以上", "少於5毫克", true), ("鈉 至少 5毫克", "5毫克", true),
                                           ("鈉 少於5毫克 以下", "少於5毫克", false), ("鈉 ＜5毫克 以內", "＜5毫克", false)] {
            let text = "每份\n" + line
            let result = Locator.locate(text: text, headers: perServing, rows: [Self.row("鈉", [("h1", printed)])])
            XCTAssertEqual(result.values[0].attention == [.comparatorOutsideToken], attention, line)
        }
        // Glued to the CJK bound word, the value is not a whole token, so it is not found (attention either way).
        let glued = Locator.locate(text: "每份\n鈉 少於5毫克以上", headers: perServing, rows: [Self.row("鈉", [("h1", "少於5毫克")])])
        XCTAssertTrue(glued.values[0].needsAttention)
        let agreeing = Locator.locate(text: "Per 100g\nSalt ≤ <0.5g", headers: [Self.per100], rows: [Self.row("Salt", [("h1", "<0.5g")])])
        XCTAssertEqual(agreeing.values[0].attention, [], "an upper-bound symbol agrees with an upper-bound token")
    }

    func testPercentWithoutAReferenceIntakeHeaderIsAttention() {
        let text = "Per 100g %RI\nFat 1g 5%"
        let result = Locator.locate(text: text, headers: [Self.per100], rows: [Self.row("Fat", [("h1", "1g")])])
        XCTAssertEqual(result.values[0].status, .found(Self.scalars("1g", in: text)))
        XCTAssertEqual(result.rows[0].attention, [.percentWithoutReferenceIntakeHeader])
        XCTAssertTrue(result.values[0].needsAttention)
    }

    func testSpacedTokensAreOneTokenEach() {
        let text = "Per 100g Per serving\nSalt less than 0.5 g 5\u{00A0}g"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing],
                                    rows: [Self.row("Salt", [("h1", "less than 0.5 g"), ("h2", "5\u{00A0}g")])])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention })
        let tokens = PastedLabelTextScan(text).tokens.dropFirst()
        XCTAssertEqual(tokens.map(\.comparator), ["<", "="])
        XCTAssertEqual(Locator.locate(text: text, headers: [Self.per100, Self.perServing],
                                      rows: [Self.row("Salt", [("h1", "0.5 g"), ("h2", "5 g")])]).values.map(\.status), [.notFound, .notFound],
                       "a part of a token, or a token with a different space, is not the token")
    }

    func testDigitsOutsideASCIIAndFullWidth() {
        let text = "Per 100g Per serving\nFat \u{0665}g \u{FF15}g"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing],
                                    rows: [Self.row("Fat", [("h1", "\u{0665}g"), ("h2", "\u{FF15}g")])])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention })
        XCTAssertEqual(PastedLabelTextScan(text).tokens.suffix(2).map(\.decimalText), ["\u{0665}", "\u{FF15}"], "digits are kept as printed")
    }

    func testFootnoteMarksAreKeptAndIgnoredForMatching() {
        let text = "Per 100g\nSugars 5g*"
        let result = Locator.locate(text: text, headers: [Self.per100], rows: [Self.row("Sugars", [("h1", "5g")])])
        XCTAssertEqual(result.values[0].status, .found(Self.scalars("5g*", in: text)))
    }

    func testNotFoundAndSeveralMatches() {
        let text = "Per 100g %RI\nFat 5g 5% 5%"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.referenceIntake],
                                    rows: [Self.row("Fat", [("h1", "7g"), ("h3", "5%")])])
        XCTAssertEqual(statuses(result), [.notFound, .ambiguous])
        XCTAssertTrue(result.values.allSatisfy(\.needsAttention))
    }

    func testHeaderLocatedTwiceOrNotAtAllPutsItsColumnUnderAttention() {
        let text = "Per 100g Per 100g\nFat 5g 2g"
        let result = Locator.locate(text: text, headers: [Self.per100, Locator.Header(id: "h2", printedText: "Per portion", basis: "per_serving")],
                                    rows: [Self.row("Fat", [("h1", "5g"), ("h2", "2g"), ("h9", "2g")])])
        XCTAssertEqual(result.headers.map(\.status), [.ambiguous, .notFound])
        XCTAssertEqual(result.values.map(\.attention), [[.headerNotLocated, .moreCellsThanHeaders], [.headerNotLocated, .moreCellsThanHeaders],
                                                         [.headerUnknown, .moreCellsThanHeaders]])
    }

    func testRowLabelNotFound() {
        let result = Locator.locate(text: "Per 100g\nFat 5g", headers: [Self.per100], rows: [Self.row("Salt", [("h1", "5g")])])
        XCTAssertEqual(result.values[0].status, .notFound)
        XCTAssertEqual(result.values[0].attention, [.rowLabelNotFound])
    }

    // MARK: Offsets and determinism

    func testOffsetsAreUnicodeScalars() {
        // `e` + U+0301 is one Character and two scalars; U+1F600 is one scalar.
        let text = "Caf\u{0065}\u{0301} \u{1F600}\nPer 100g\nFat 5g"
        let result = Locator.locate(text: text, headers: [Self.per100], rows: [Self.row("Fat", [("h1", "5g")])])
        XCTAssertEqual(result.values[0].status, .found(21..<23))
        XCTAssertEqual(Self.scalars("5g", in: text), 21..<23)
    }

    func testRepeatedRunsAreByteIdentical() throws {
        let text = "Per 100g Per serving %RI\nEnergy 1046kJ/250kcal 523kJ/125kcal 6%\nFat 5g 2.5g 4%\nof which saturates 1g\nSalt 0,5g 0.25g"
        let rows = [Self.row("Energy", [("h1", "1046kJ"), ("h2", "523kJ"), ("h3", "6%")]), Self.row("Energy", [("h1", "250kcal"), ("h2", "125kcal")]),
                    Self.row("Fat", [("h1", "5g"), ("h2", "2.5g"), ("h3", "4%")]), Self.row("of which saturates", [("h1", "1g"), ("h2", "0.5g")]),
                    Self.row("Salt", [("h1", "0,5g"), ("h2", "0.25g")])]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let headers = [Self.per100, Self.perServing, Self.referenceIntake]
        let first = try encoder.encode(Locator.locate(text: text, headers: headers, rows: rows))
        for _ in 0..<20 {
            XCTAssertEqual(try encoder.encode(Locator.locate(text: text, headers: headers, rows: rows)), first)
        }
        let decoded = try JSONDecoder().decode(Locator.Result.self, from: first)
        XCTAssertEqual(decoded, Locator.locate(text: text, headers: headers, rows: rows))
        XCTAssertEqual(decoded.version, "pasted-label-text-locate-v2")
    }

    // MARK: Revision 10 (locator v2)

    /// A value the model copied with the label's own brackets is found only where the text prints
    /// those brackets beside the token.
    func testABracketedValueIsFoundWhereTheTextPrintsTheBrackets() {
        let text = "Per 100g\nFat 12.0g\n(of which saturates) (3.5g)\nSalt 0.40g"
        let result = Locator.locate(text: text, headers: [Self.per100],
                                    rows: [Self.row("Fat", [("h1", "12.0g")]), Self.row("(of which saturates)", [("h1", "(3.5g)")]),
                                           Self.row("Salt", [("h1", "0.40g")])])
        XCTAssertEqual(statuses(result), [.found(Self.scalars("12.0g", in: text)), .found(Self.scalars("3.5g", in: text)),
                                          .found(Self.scalars("0.40g", in: text))])
        XCTAssertTrue(result.values.allSatisfy { !$0.needsAttention })
    }

    func testAValueWithOnlyTheRowsClosingBracketIsFound() {
        let text = "Per 100g Per pack\nFat 4.0g 16.0g\n(of which saturates 1.2g 4.8g)\nSalt 0.5g 2.0g"
        let result = Locator.locate(text: text, headers: [Self.per100, Self.perServing.withText("Per pack")],
                                    rows: [Self.row("Fat", [("h1", "4.0g"), ("h2", "16.0g")]),
                                           Self.row("(of which saturates", [("h1", "1.2g"), ("h2", "4.8g)")]),
                                           Self.row("Salt", [("h1", "0.5g"), ("h2", "2.0g")])])
        XCTAssertEqual(result.values[3].status, .found(Self.scalars("4.8g", in: text)))
        XCTAssertEqual(result.values[2].status, .found(Self.scalars("1.2g", in: text)))
    }

    /// The unsafe neighbours: brackets the text does not print there are not found.
    func testBracketsTheTextDoesNotPrintBesideTheTokenAreNotFound() {
        let text = "Per 100g\nFat 12.0g\nof which saturates 3.5g (high)\nSalt 0.40g"
        let result = Locator.locate(text: text, headers: [Self.per100],
                                    rows: [Self.row("Fat", [("h1", "(12.0g)")]), Self.row("of which saturates", [("h1", "(3.5g)")]),
                                           Self.row("Salt", [("h1", "0.40g)")])])
        XCTAssertEqual(statuses(result), [.notFound, .notFound, .notFound])
        let closingOnly = "Per 100g\nof which saturates 3.5g)\nSalt 0.40g"
        let opened = Locator.locate(text: closingOnly, headers: [Self.per100], rows: [Self.row("of which saturates", [("h1", "(3.5g)")])])
        XCTAssertEqual(statuses(opened), [.notFound], "an opener the text does not print before the token")
    }

    /// The text-only kcal spellings form an energy pair (`kCal`, `Kcal`); `Cal` stays outside.
    func testTextOnlyKcalSpellingsFormAnEnergyPair() {
        let text = "Per 100g\nEnergy 1500kJ / 360kCal\nFat 10g\nSalt 1.0g"
        let result = Locator.locate(text: text, headers: [Self.per100],
                                    rows: [Self.row("Energy", [("h1", "1500kJ")]), Self.row("Energy", [("h1", "360kCal")]),
                                           Self.row("Fat", [("h1", "10g")]), Self.row("Salt", [("h1", "1.0g")])])
        XCTAssertEqual(statuses(result), [.found(Self.scalars("1500kJ", in: text)), .found(Self.scalars("360kCal", in: text)),
                                          .found(Self.scalars("10g", in: text)), .found(Self.scalars("1.0g", in: text))])
        let capitals = "Per 100g\nEnergy 1500KJ / 360Kcal\nSalt 1.0g"
        XCTAssertEqual(statuses(Locator.locate(text: capitals, headers: [Self.per100],
                                               rows: [Self.row("Energy", [("h1", "1500KJ")]), Self.row("Energy", [("h1", "360Kcal")])])),
                       [.found(Self.scalars("1500KJ", in: capitals)), .found(Self.scalars("360Kcal", in: capitals))])
        let cal = "Per 100ml\nEnergy 30Cal\nSalt 0.1g"
        let header = Locator.Header(id: "h1", printedText: "Per 100ml", basis: "per_100ml")
        XCTAssertEqual(Locator.locate(text: cal, headers: [header], rows: [Self.row("Energy", [("h1", "30Cal")])]).values[0].status, .notFound,
                       "`Cal` is not a unit of the closed table, so `30Cal` is no token")
    }
}

extension PastedLabelTextLocator.Header {
    func withText(_ printed: String) -> Self { .init(id: id, printedText: printed, basis: basis) }
}
