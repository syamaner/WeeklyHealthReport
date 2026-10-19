import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// Pasted nutrition label PR 4 (#93): the label text screen, Confirm's source section, origins,
/// corrections, amount options, the misread report and the privacy wording
/// (`docs/pasted-nutrition-label-v1.md` section 8.4, tests 20 to 22, 27, 33 to 37 and 39 to 44).
/// Synthetic data only.
@MainActor
final class PastedLabelPresentationTests: XCTestCase {
    private typealias F = LabelFixtures

    // MARK: Test 20: label text screen

    func testReadLabelIsDisabledUntilNameAndTextAndWithinTheScalarLimit() {
        let model = F.textModel(F.StubReader(F.reading()))
        XCTAssertFalse(model.canRead)
        XCTAssertEqual(model.readBlockedReason, "Enter a name and paste the label text.")
        model.name = "  "
        model.text = F.pastedText
        XCTAssertEqual(model.readBlockedReason, "Enter a name for this food.")
        model.name = "Synthetic oat crackers"
        model.text = " \n"
        XCTAssertEqual(model.readBlockedReason, "Paste the label text.")
        // Test 37: the limit counts Unicode scalars, not grapheme clusters or UTF-16 units.
        model.text = String(repeating: "e\u{301}", count: 4_000)
        XCTAssertEqual(model.text.unicodeScalars.count, 8_000)
        XCTAssertEqual(model.text.count, 4_000)
        XCTAssertTrue(model.canRead, "8,000 scalars are accepted")
        model.text += "a"
        XCTAssertFalse(model.canRead, "8,001 scalars are declined before reading")
        XCTAssertEqual(model.readBlockedReason, "This text is too long to be one nutrition table. Paste the table only.")
        XCTAssertNil(model.readLabel())
        model.text = F.pastedText
        XCTAssertTrue(model.canRead)
        XCTAssertNil(model.readBlockedReason)
    }

    func testADeclineKeepsTheTextAndNameAndShowsItsReason() throws {
        let stub = F.StubReader(F.declined(["count_mismatch"]))
        var lines: [[String]] = []
        let model = F.textModel(stub) { lines.append($0) }
        model.name = "Synthetic oat crackers"
        model.text = F.pastedText
        XCTAssertNil(model.readLabel(), "a hard decline never opens Confirm")
        XCTAssertEqual(model.text, F.pastedText)
        XCTAssertEqual(model.name, "Synthetic oat crackers")
        XCTAssertEqual(model.declineMessages, ["The app could not match the values in this text to their rows and columns. Check that it is one table with each value on its row, then try again."])
        XCTAssertNil(model.confirm)
        XCTAssertEqual(lines.last, ["Pasted label declined: count_mismatch", "Format: taiwan_nutrition_labelling"],
                       "codes go to Developer tools only")
        XCTAssertFalse(model.declineMessages.joined().contains("count_mismatch"), "no code in the on-screen copy")
        // Edit and read again: the decline clears and Confirm opens.
        stub.set(F.reading(text: F.pastedText + " "))
        model.text = F.pastedText + " "
        let source = try XCTUnwrap(model.readLabel())
        XCTAssertTrue(model.declineMessages.isEmpty)
        XCTAssertEqual(source.pastedText, F.pastedText + " ", "the text is read exactly as typed")
        // Edit label text returns with the text and name kept; Back to Confirm needs the same text.
        XCTAssertTrue(model.canReturnToConfirm)
        model.text += "x"
        XCTAssertFalse(model.canReturnToConfirm)
    }

    func testEveryCodeMapsToCopyAndUnknownCodesFallBackToUnreadable() {
        // Test 27: every mapped code has copy; hard declines are exactly the section 3.1 set.
        for (code, classification) in PastedLabelCodes.mapping {
            switch classification.kind {
            case .hardDecline:
                let copy = PastedLabelText.declineMessages([code])
                XCTAssertEqual(copy, [PastedLabelText.declineMessage(classification.copy)], code)
                XCTAssertFalse(copy[0].contains(code), code)
            case .flag:
                let message = PastedLabelText.flagMessage(.init(code: code, concerns: code == "required_serving_declaration_missing" ? "serving_size" : "sodium"), headers: [])
                XCTAssertTrue(message.hasPrefix("Not read") || message.hasPrefix("No per 100"), "\(code): \(message)")
            }
        }
        XCTAssertEqual(PastedLabelText.declineMessages(["a_code_nobody_mapped"]),
                       ["The app could not read this table. Check that it is one nutrition table, then try again."])
        XCTAssertEqual(PastedLabelText.declineMessages(["layout_not_supported"]),
                       ["The app cannot read this label layout yet. It reads Traditional Chinese (Taiwan layout) labels."])
        XCTAssertEqual(PastedLabelText.declineMessages(["unsupported_script"]),
                       ["This label is in a language the app cannot read yet. It reads Traditional Chinese (Taiwan layout) labels."])
        XCTAssertEqual(PastedLabelText.declineMessages(["count_mismatch", "duplicate_basis"]).count, 1, "one sentence per distinct copy")
        // Each copy key that is a hard decline has its own sentence.
        let declineKeys = Set(PastedLabelCodes.mapping.values.filter { $0.kind == .hardDecline }.map(\.copy))
        XCTAssertEqual(Set(declineKeys.map(PastedLabelText.declineMessage)).count, declineKeys.count)
    }

    // MARK: Tests 21, 33 and 42: Confirm rows and the one origin formatter

    func testConfirmShowsEachValueBesideItsPrintedSourceWithOneOrigin() throws {
        let source = try F.source()
        let rows = Dictionary(uniqueKeysWithValues: source.rows.map { ($0.id, $0) })
        XCTAssertEqual(source.rows.map(\.id), PastedLabelSourceModel.rowOrder)
        XCTAssertEqual(source.sourceLine, "From pasted label · per 100 g · Traditional Chinese, Taiwan layout")

        let energy = try XCTUnwrap(rows["energy_kcal"])
        XCTAssertEqual(energy.origin, .calculated(rule: "kj_to_kcal_v1"))
        XCTAssertEqual(energy.value, "about 371 kcal", "display rounds kcal to a whole number; the stored value keeps 370.5")
        XCTAssertEqual(energy.originText, "Calculated from 1550 kJ (printed), kcal = kJ ÷ 4.184")
        XCTAssertEqual(energy.source, "Printed: 熱量 · 1550 kJ")
        XCTAssertNil(energy.flag, "the calculated value satisfies the kcal row's flag")
        XCTAssertTrue(energy.accessibilityLabel.contains("Calculated"), "VoiceOver reads calculated as a word")

        let sodium = try XCTUnwrap(rows["sodium"])
        XCTAssertEqual(sodium.value, "about 240 mg")
        XCTAssertEqual(sodium.originText, "Calculated from 0.6 g salt (printed), sodium = salt ÷ 2.5")

        let protein = try XCTUnwrap(rows["protein"])
        XCTAssertEqual(protein.origin, .printed)
        XCTAssertEqual(protein.value, "5.2 g")
        XCTAssertEqual(protein.source, "Printed: 蛋白質 · 5.2公克")

        XCTAssertEqual(rows["fat"]?.value, "Less than 0.5 g", "bounds read as printed")
        XCTAssertEqual(rows["saturates"]?.origin, .unknown(.notRead))
        XCTAssertEqual(rows["saturates"]?.flag, "Not read: saturated fat. Add it, or leave it unknown.")
        XCTAssertEqual(rows["fibre"]?.origin, .unknown(.notStated))
        XCTAssertEqual(rows["fibre"]?.value, "Not stated", "unknown, never zero")
        XCTAssertEqual(rows["fibre"]?.actions, [.add])
        XCTAssertEqual(rows["protein"]?.actions, [.correct])

        // Serving lines, read-but-not-used rows and the other column.
        XCTAssertEqual(source.servingLines.map(\.value), ["30 g (printed: 每一份量30公克)", "10 (printed: 本包裝含10份)"])
        XCTAssertEqual(source.readButNotUsed.map(\.printedText), [], "kJ and salt feed calculated values")
        XCTAssertEqual(source.otherColumns.first?.title, "Other column: per serving (每份)")
        XCTAssertEqual(source.otherColumns.first?.cells.count, 5)
        XCTAssertFalse(source.otherNutrients.isEmpty)
        XCTAssertEqual(PastedLabelText.disclaimer, "Read automatically from your text. Check each value against the label.")

        // Exactly one origin per value, and no confidence or "checked" wording anywhere.
        for row in source.rows {
            let tags = ["Printed", "Calculated", "Corrected by you", "Entered by you", "Not read", "Not stated"]
            XCTAssertEqual(tags.filter { row.originText.hasPrefix($0) }.count, 1, row.id)
        }
        let copy = ([PastedLabelText.disclaimer] + source.rows.flatMap { [$0.value, $0.originText, $0.source ?? "", $0.flag ?? ""] })
            .joined(separator: " ").lowercased()
        for banned in ["confidence", "checked", "verified", "score"] { XCTAssertFalse(copy.contains(banned), banned) }
    }

    func testTheCalculatedProjectionIsIdenticalOnConfirmTheSavedEntryAndTheReport() throws {
        // Test 33: one fixture, one projection, one formatter.
        let source = try F.source()
        let (confirm, store) = try F.confirm(source)
        confirm.send(.setQuantity(50, .grams))
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult, confirm.state.phase.debugDescription)
        let detail = SavedFoodEntryDetail(stored: saved, isEstimate: false, history: [])
        XCTAssertNotNil(detail.pastedLabel)
        let confirmOrigins = Dictionary(uniqueKeysWithValues: source.rows.map { ($0.key, $0.origin) })
        for (key, origin) in confirmOrigins { XCTAssertEqual(detail.valueOrigins[key], origin, key.rawValue) }
        let stored = try XCTUnwrap(PastedLabelSourceModel.stored(FoodConfirmationState(input: confirm.state.input)))
        func shown(_ rows: [PastedLabelSourceModel.Row]) -> [String] {
            rows.map { "\($0.id)|\($0.value)|\($0.originText)|\($0.source ?? "")|\($0.flag ?? "")|\($0.accessibilityLabel)" }
        }
        XCTAssertEqual(shown(stored.rows), shown(source.rows), "a stored label shows the same rows")
        XCTAssertTrue(stored.rows.allSatisfy(\.actions.isEmpty), "read-only")
        XCTAssertFalse(stored.isEditable)
        XCTAssertEqual(PastedLabelSavedEntryText.originLines(detail).first,
                       "Energy: Calculated from 1550 kJ (printed), kcal = kJ ÷ 4.184")
        let energy = try XCTUnwrap({ () -> FoodIntakeTotal? in
            if case let .calculated(totals) = detail.nutrition { return totals.first { $0.key == .energyConsumed } }
            return nil
        }())
        XCTAssertTrue(PastedLabelSavedEntryText.value(energy, detail: detail).hasPrefix("about "))
        XCTAssertTrue(PastedLabelSavedEntryText.value(energy, detail: detail).hasSuffix(" · Calculated"))
        XCTAssertTrue(energy.includesEstimates, "a calculated contribution sets includesEstimates (food-intake-summary-v3)")
        // QA D2: a printed bound is shown as a bound on the saved entry, never "Unknown".
        let fat = try XCTUnwrap({ () -> FoodIntakeTotal? in
            if case let .calculated(totals) = detail.nutrition { return totals.first { $0.key == .fatTotal } }
            return nil
        }())
        XCTAssertNil(fat.knownAmount)
        XCTAssertEqual(PastedLabelSavedEntryText.value(fat, detail: detail), "Less than 0.5 g per 100 g · Printed")
        let report = try XCTUnwrap(PastedLabelSavedEntryText.reportText(detail))
        XCTAssertTrue(report.contains("Calculated from 1550 kJ (printed), kcal = kJ ÷ 4.184"))
        XCTAssertEqual(try store.archiveState().records.evidence.count, 1)
    }

    // MARK: Tests 39, 40, 41 and 44: corrections, entries, partial tables and totals

    func testACorrectedValueIsSavedAsCorrectedWithTheRecognisedValueKept() throws {
        let source = try F.source()
        let (confirm, _) = try F.confirm(source)
        XCTAssertNil(source.setValue("protein", text: "5.4", unit: "g"))
        let protein = try XCTUnwrap(source.rows.first { $0.id == "protein" })
        XCTAssertEqual(protein.origin, .correctedByYou)
        XCTAssertEqual(protein.value, "5.4 g")
        XCTAssertEqual(protein.source, "Read as: 蛋白質 · 5.2公克")
        XCTAssertEqual(protein.actions, [.correct, .remove])
        confirm.send(.setQuantity(100, .grams))
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult)
        let value = try XCTUnwrap(saved.resolutionVersion.nutrients.entries.first { $0.key == .protein }?.value)
        XCTAssertEqual(value.provenance.first?.sourceKind, .manualDeclaration)
        let manifest = try XCTUnwrap(PastedLabelValueOrigins.manifest(evidence: saved.evidence,
                                                                       evidenceIDs: saved.candidateDecision.candidate.evidenceIDs))
        XCTAssertEqual(manifest.corrections.count, 1)
        XCTAssertEqual(manifest.corrections[0].recognised?.decimalText, "5.2")
        XCTAssertEqual(manifest.corrections[0].corrected.decimalText, "5.4")
        XCTAssertEqual(manifest.corrections[0].at, F.now, "stamped by the injected clock")
        XCTAssertEqual(manifest.pastedText, F.pastedText, "the pasted text is unchanged")
        XCTAssertEqual(manifest.candidate.cells.first { $0.headerID == "h2" && $0.nutrient == "protein" }?.decimalText, "5.2")
        let consumed = confirm.consumedNutrition.first { $0.key == .protein }
        XCTAssertEqual(consumed?.includesEstimates, false, "decision 13: corrected values do not set includesEstimates")
    }

    func testAnEnteredValueAndAPartialTableSaveWithUntouchedRowsUnknown() throws {
        let source = try F.source()
        let (confirm, _) = try F.confirm(source)
        XCTAssertEqual(source.setValue("fibre", text: "abc", unit: "g"), PastedLabelSourceModel.invalidNumber)
        XCTAssertNil(source.setValue("fibre", text: "2.0", unit: "g"))
        let fibre = try XCTUnwrap(source.rows.first { $0.id == "fibre" })
        XCTAssertEqual(fibre.origin, .enteredByYou)
        XCTAssertEqual(fibre.source, "Not read from the label")
        XCTAssertEqual(source.corrections.first?.recognised, nil)
        // Saturated fat stays flagged and unknown; Log is not blocked by the flag.
        XCTAssertEqual(source.manifest.flagsShown.map(\.concerns), ["saturates"])
        confirm.send(.setQuantity(100, .grams))
        XCTAssertTrue(confirm.canLog)
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult)
        let saturates = saved.resolutionVersion.nutrients.entries.first { $0.key == .fatSaturated }?.value
        XCTAssertEqual(saturates, .unknown(.notDeclared), "never zero")
        let total = confirm.consumedNutrition.first { $0.key == .fatSaturated }
        XCTAssertNil(total?.knownAmount)
        XCTAssertEqual(total?.incompleteContributions, 1, "the day total is incomplete for it")
        // Removing a value shows the recognised value (or unknown) again.
        let other = try F.source()
        XCTAssertNil(other.setValue("fibre", text: "2.0", unit: "g"))
        other.removeValue("fibre")
        XCTAssertEqual(other.rows.first { $0.id == "fibre" }?.origin, .unknown(.notStated))
        XCTAssertTrue(other.corrections.isEmpty)
    }

    func testCorrectingACalculatedValueMakesItCorrectedByYou() throws {
        let source = try F.source()
        XCTAssertNil(source.setValue("energy_kcal", text: "380", unit: "kcal"))
        let energy = try XCTUnwrap(source.rows.first { $0.id == "energy_kcal" })
        XCTAssertEqual(energy.origin, .correctedByYou)
        XCTAssertEqual(energy.value, "380 kcal", "no longer calculated, so no \"about\"")
        XCTAssertEqual(energy.source, "Read as: 熱量 · 1550 kJ. Calculated from 1550 kJ (printed), kcal = kJ ÷ 4.184")
        XCTAssertEqual(source.manifest.conversions.count, 2, "the conversion record stays as evidence")
    }

    func testReadingAgainAfterCorrectionsAsksFirst() throws {
        // Test 43.
        let stub = F.StubReader(F.reading())
        let model = F.textModel(stub)
        model.name = "Synthetic oat crackers"
        model.text = F.pastedText
        let first = try XCTUnwrap(model.readLabel())
        XCTAssertNotNil(model.readLabel(), "with no corrections it re-reads without asking")
        XCTAssertFalse(model.asksToReplaceCorrections)
        let current = try XCTUnwrap(model.confirm)
        XCTAssertFalse(first === current)
        XCTAssertNil(current.setValue("protein", text: "5.4", unit: "g"))
        XCTAssertNil(model.readLabel())
        XCTAssertTrue(model.asksToReplaceCorrections)
        XCTAssertEqual(PastedLabelText.readAgainTitle, "Reading the text again replaces your corrections.")
        model.cancelReadAgain()
        XCTAssertEqual(model.confirm?.corrections.count, 1, "Cancel keeps every correction")
        XCTAssertTrue(model.returnToConfirm() === current)
        let reread = try XCTUnwrap(model.confirmReadAgain())
        XCTAssertTrue(reread.corrections.isEmpty, "Read again clears them and re-reads")
        XCTAssertEqual(stub.texts.count, 3)
    }

    // MARK: Warnings (test 13 at view-model level)

    func testAFailedCheckIsAWarningThatNeverChangesLog() throws {
        let failing = LabelReading.Check(name: "energy", basis: "per_100g", nutrient: nil, child: nil, status: .fail)
        let warned = try F.source(F.reading(checks: [failing]))
        let quiet = try F.source(F.reading(checks: [.init(name: "energy", basis: "per_100g", nutrient: nil, child: nil, status: .pass)]))
        XCTAssertEqual(warned.warnings, ["Energy does not match the fat, carbohydrate and protein shown. Check the label text."])
        XCTAssertEqual(quiet.warnings, [], "a pass shows nothing")
        let (a, _) = try F.confirm(warned), (b, _) = try F.confirm(quiet)
        a.send(.setQuantity(100, .grams)); b.send(.setQuantity(100, .grams))
        XCTAssertEqual(a.canLog, b.canLog)
        XCTAssertEqual(a.requirements, b.requirements)
        XCTAssertEqual(PastedLabelText.warningMessage("subrow_not_above_parent:per_100g:sugars"),
                       "Sugars is more than carbohydrate. Check the label text.")
    }

    // MARK: Amount options (section 2.3; owner defaults for PR 4)

    func testWholePackIsOfferedOnlyWithAServingSizeInGramsOrMillilitresAndAnExactCount() throws {
        // pasted-label-serving-v2 (owner, 19 October 2026): a per 100 g label with a printed
        // serving size in grams offers servings and whole pack; see the per 100 g test below.
        let noSize = try F.confirm(try F.source(F.reading(servingSize: nil))).0
        XCTAssertNil(noSize.pastedLabelWholePack, "no serving size: no servings and no whole pack")
        XCTAssertFalse(noSize.countsPastedLabelServings)
        let mlOn100g = try F.confirm(try F.source(F.reading(servingSize: .init(printedText: "每一份量250毫升", decimalText: "250",
                                                                                 unit: "毫升", canonicalUnit: "ml")))).0
        XCTAssertNil(mlOn100g.pastedLabelWholePack, "a serving in ml never converts against per 100 g")
        XCTAssertFalse(mlOn100g.countsPastedLabelServings)

        let printed = try F.source(F.perServingReading())
        let (confirm, _) = try F.confirm(printed)
        XCTAssertTrue(confirm.countsPastedLabelServings)
        XCTAssertEqual(confirm.pastedLabelWholePack, PastedLabelWholePack(servings: 10, origin: .printed))
        confirm.chooseWholePack()
        XCTAssertEqual(confirm.state.quantity.value, 10)
        XCTAssertEqual(confirm.state.quantity.unit, .count)
        XCTAssertTrue(confirm.canLog, confirm.blockedReason ?? "")
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult)
        XCTAssertEqual(saved.quantityConversion?.convertedQuantity.value, 300, "10 servings × 30 g")

        let about = try F.confirm(try F.source(F.perServingReading(pack: .init(printedText: "本包裝含約8份", decimalText: "8", approximate: true)))).0
        XCTAssertNil(about.pastedLabelWholePack, "\"about\" is never a whole pack")
    }

    func testAPer100GramLabelWithAPrintedServingSizeOffersServingsAndWholePack() throws {
        let source = try F.source()
        XCTAssertEqual(source.sourceLine, "From pasted label · per 100 g · Traditional Chinese, Taiwan layout")
        let (confirm, _) = try F.confirm(source)
        XCTAssertTrue(confirm.countsPastedLabelServings, "the count unit reads as servings")
        XCTAssertFalse(confirm.pastedLabelServingsOnly, "grams stay available")
        XCTAssertEqual(confirm.pastedLabelWholePack, PastedLabelWholePack(servings: 10, origin: .printed))
        XCTAssertEqual(PastedLabelText.wholePackNote(servingSize: confirm.pastedLabelServingSizeOrigin),
                       "Logged as that many servings, through the printed serving size.")
        XCTAssertEqual(source.servingLines.first?.actions, [.correct], "the printed serving size can be corrected")

        confirm.send(.setQuantity(2, .count))
        XCTAssertTrue(confirm.canLog, confirm.blockedReason ?? "")
        confirm.chooseWholePack()
        XCTAssertEqual(confirm.state.quantity.value, 10)
        XCTAssertEqual(confirm.state.quantity.unit, .count)
        XCTAssertTrue(confirm.canLog, confirm.blockedReason ?? "")
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult)
        XCTAssertEqual(saved.quantityConversion?.methodVersion.value, "pasted-label-serving-v2")
        XCTAssertEqual(saved.quantityConversion?.convertedQuantity, try PositiveQuantity(value: 300, unit: .grams), "10 servings × 30 g")
        XCTAssertEqual(saved.productVersion.identity.servingBasis, .per100Grams)
    }

    func testAPer100GramLabelWithACorrectedServingSizeSaysSo() throws {
        let source = try F.source()
        let (confirm, _) = try F.confirm(source)
        XCTAssertNil(source.setValue("serving_size", text: "35", unit: "g"))
        XCTAssertEqual(source.servingLines.first?.value, "35 g · Corrected by you (read as: 每一份量30公克)")
        XCTAssertEqual(confirm.state.selectedCandidate.candidate.identity.servingBasis, .per100Grams, "the basis is unchanged")
        XCTAssertEqual(confirm.pastedLabelServingSizeOrigin, .correctedByYou)
        XCTAssertEqual(PastedLabelText.wholePackNote(servingSize: confirm.pastedLabelServingSizeOrigin),
                       "Logged as that many servings, through the serving size you corrected.")
        confirm.chooseWholePack()
        confirm.log()
        XCTAssertEqual(try XCTUnwrap(confirm.savedResult).quantityConversion?.convertedQuantity.value, 350, "10 servings × 35 g")
    }

    func testAPer100GramLabelWithNoServingSizeCanHaveOneEntered() throws {
        let source = try F.source(F.reading(servingSize: nil))
        let (confirm, _) = try F.confirm(source)
        XCTAssertFalse(confirm.countsPastedLabelServings)
        XCTAssertEqual(source.servingLines.first?.actions, [.add])
        XCTAssertNil(source.setValue("serving_size", text: "40", unit: "g"))
        XCTAssertEqual(source.servingLines.first?.value, "40 g · Entered by you")
        XCTAssertTrue(confirm.countsPastedLabelServings)
        XCTAssertEqual(confirm.pastedLabelServingSizeOrigin, .enteredByYou)
        XCTAssertEqual(confirm.pastedLabelWholePack, PastedLabelWholePack(servings: 10, origin: .printed))
        XCTAssertNil(source.setValue("serving_size", text: "40", unit: "ml"))
        XCTAssertFalse(confirm.countsPastedLabelServings, "an entered size in ml offers no servings on per 100 g")
        XCTAssertNil(confirm.pastedLabelWholePack)
    }

    func testAnEnteredServingsPerPackFeedsWholePackShownEnteredByYou() throws {
        let source = try F.source(F.perServingReading(pack: nil))
        let (confirm, _) = try F.confirm(source)
        XCTAssertNil(confirm.pastedLabelWholePack)
        let line = try XCTUnwrap(source.servingLines.last)
        XCTAssertEqual(line.flag, "Not read: servings per pack. Add it, or leave it unknown.")
        XCTAssertEqual(line.actions, [.add])
        XCTAssertEqual(source.setValue("servings_per_pack", text: "0", unit: "count"), PastedLabelSourceModel.invalidNumber)
        XCTAssertNil(source.setValue("servings_per_pack", text: "4", unit: "count"))
        XCTAssertEqual(source.servingLines.last?.value, "4 · Entered by you")
        XCTAssertNil(source.servingLines.last?.flag, "the entry resolves its flag")
        XCTAssertEqual(confirm.pastedLabelWholePack, PastedLabelWholePack(servings: 4, origin: .enteredByYou(correctionIndex: 0)))
        XCTAssertNil(source.nutrients.entries.first { $0.key == .energyConsumed }.flatMap { entry -> String? in
            if case .unknown = entry.value { return "unknown" } else { return nil }
        }, "it sets no nutrient")
    }

    func testAnEnteredServingSizeIsShownAndSetsTheBasis() throws {
        // Owner default: a user-entered serving size in g or ml, shown "Entered by you".
        let source = try F.source(F.perServingReading(servingSize: false))
        let (confirm, _) = try F.confirm(source)
        XCTAssertTrue(confirm.pastedLabelServingsOnly, "case 3: servings only until a size is entered")
        XCTAssertNil(confirm.pastedLabelWholePack, "no serving weight or volume: no whole pack yet")
        XCTAssertEqual(source.servingLines.first?.flag, "Not read: serving size. Add it, or leave it unknown.")
        confirm.send(.setQuantity(2, .count))
        XCTAssertNil(source.setValue("serving_size", text: "25", unit: "ml"))
        XCTAssertEqual(source.servingLines.first?.value, "25 mL · Entered by you")
        XCTAssertFalse(confirm.pastedLabelServingsOnly)
        XCTAssertEqual(confirm.state.selectedCandidate.candidate.identity.servingBasis, .perServing(try PositiveQuantity(value: 25, unit: .millilitres)))
        XCTAssertEqual(confirm.state.quantity.value, 2, "the amount is kept across a correction")
        XCTAssertEqual(confirm.pastedLabelWholePack, PastedLabelWholePack(servings: 10, origin: .printed),
                       "an entered size in ml makes the printed exact pack a whole-pack option")
        // Review R1: the caption names the serving size's own origin.
        XCTAssertEqual(confirm.pastedLabelServingSizeOrigin, .enteredByYou)
        XCTAssertEqual(PastedLabelText.wholePackNote(servingSize: confirm.pastedLabelServingSizeOrigin),
                       "Logged as that many servings, through the serving size you entered.")
        confirm.chooseWholePack()
        confirm.log()
        XCTAssertEqual(try XCTUnwrap(confirm.savedResult).quantityConversion?.convertedQuantity.value, 250, "10 servings × 25 ml")
    }

    func testWholePackWithACorrectedServingSizeSaysSo() throws {
        // Review R1: a printed serving size the user corrected.
        let source = try F.source(F.perServingReading())
        let (confirm, _) = try F.confirm(source)
        XCTAssertEqual(PastedLabelText.wholePackNote(servingSize: confirm.pastedLabelServingSizeOrigin),
                       "Logged as that many servings, through the printed serving size.")
        XCTAssertNil(source.setValue("serving_size", text: "35", unit: "g"))
        XCTAssertEqual(source.servingLines.first?.value, "35 g · Corrected by you (read as: 每一份量30公克)")
        XCTAssertEqual(confirm.pastedLabelServingSizeOrigin, .correctedByYou)
        XCTAssertEqual(PastedLabelText.wholePackNote(servingSize: confirm.pastedLabelServingSizeOrigin),
                       "Logged as that many servings, through the serving size you corrected.")
        XCTAssertEqual(confirm.pastedLabelWholePack, PastedLabelWholePack(servings: 10, origin: .printed))
        confirm.chooseWholePack()
        confirm.log()
        XCTAssertEqual(try XCTUnwrap(confirm.savedResult).quantityConversion?.convertedQuantity.value, 350, "10 servings × 35 g")
    }

    // MARK: Review R4 and R5: "about" and the calculated tag wherever a calculated value is shown

    func testCalculatedValuesAreMarkedInEveryConfirmSummary() throws {
        let (confirm, _) = try F.confirm(try F.source())
        confirm.send(.setQuantity(100, .grams))
        XCTAssertTrue(confirm.energyIsCalculated)
        XCTAssertTrue(confirm.logButtonTitle.hasPrefix("Log about "), confirm.logButtonTitle)
        XCTAssertEqual(confirm.markingCalculated(.energyConsumed, "371 kcal"), "about 371 kcal · Calculated")
        XCTAssertEqual(confirm.markingCalculated(.sodium, "240 mg"), "about 240 mg · Calculated")
        XCTAssertEqual(confirm.markingCalculated(.protein, "5.2 g"), "5.2 g", "printed values are unchanged")
        let printedOnly = try F.confirm(try F.source(F.perServingReading())).0
        printedOnly.send(.setQuantity(1, .count))
        XCTAssertFalse(printedOnly.energyIsCalculated)
        XCTAssertFalse(printedOnly.logButtonTitle.contains("about"))
        // Calculated bounds: "Less than 40 mg · Calculated", rounded outward.
        XCTAssertEqual(NutrientOriginText.calculatedAmount(40.0, unit: "mg", comparator: "<"), "Less than 40 mg · Calculated")
        XCTAssertEqual(NutrientOriginText.calculatedAmount(4.3, unit: "mg", comparator: "<"), "Less than 5 mg · Calculated")
        XCTAssertEqual(NutrientOriginText.calculatedAmount(4.0, unit: "mg", comparator: "<="), "4 mg or less · Calculated")
        XCTAssertEqual(NutrientOriginText.calculatedAmount(370.5, unit: "kcal", comparator: "="), "about 371 kcal")
    }

    // MARK: Tests 22 and 34: Report a misread

    func testTheReportPreviewSharesOnlyThePreviewedTextAndHoldsNoNameOrBrand() throws {
        let source = try F.source()
        XCTAssertNil(source.setValue("protein", text: "5.4", unit: "g"))
        let report = source.reportText
        XCTAssertTrue(report.contains(F.pastedText))
        // Rounded exactly as on Confirm (review R3): whole kcal and mg, "about".
        XCTAssertTrue(report.contains("Energy (kcal) (熱量) per 100 g: about 371 kcal · Calculated from 1550 kJ (printed), kcal = kJ ÷ 4.184"))
        XCTAssertTrue(report.contains("Sodium (鹽) per 100 g: about 240 mg · Calculated from 0.6 g salt (printed), sodium = salt ÷ 2.5"))
        XCTAssertFalse(report.contains("370.5"))
        XCTAssertTrue(report.contains("Protein (蛋白質) per 100 g: 5.2公克 · Printed"), "the values as read, not the correction")
        XCTAssertTrue(report.contains("Serving size: 每一份量30公克"))
        XCTAssertTrue(report.contains("nutrition-label-text-parser-v2, label-capture-decline-gate-v2, label-arithmetic-checks-v1, pasted-label-conversions-v1"))
        for withheld in ["Synthetic oat crackers", "Synthetic Mill", "5.4"] { XCTAssertFalse(report.contains(withheld), withheld) }
        XCTAssertEqual(report, try F.source().reportText, "deterministic")
        let preview = PastedLabelMisreadPreviewModel(report: report)
        preview.text = "Trimmed by the user"
        XCTAssertEqual(preview.shareItem, "Trimmed by the user", "Share passes only the previewed, edited text")
        // A decline report: the text, the reasons with codes and the versions.
        let stub = F.StubReader(F.declined(["no_basis_header"]))
        let model = F.textModel(stub)
        model.name = "Synthetic oat crackers"; model.text = F.pastedText
        model.readLabel()
        let declined = try XCTUnwrap(model.declineReportText)
        XCTAssertTrue(declined.contains("(no_basis_header)"))
        XCTAssertFalse(declined.contains("Synthetic oat crackers"))
        // Review R6: a decline shows no warnings, so its report lists none, even when the
        // reading had a failed check (here a UK table the launch scope declines).
        let usable = F.reading(checks: [.init(name: "energy", basis: "per_100g", nutrient: nil, child: nil, status: .fail)])
        stub.set(LabelReading(origin: .pastedText, textSHA256: usable.textSHA256, candidate: usable.candidate,
            format: "uk_nutrition_declaration", gate: .init(format: "uk_nutrition_declaration", skipped: nil, hardDeclines: [], flags: []),
            checks: usable.checks, conversions: usable.conversions, storedHeaderID: usable.storedHeaderID, versions: usable.versions))
        model.readLabel()
        let scoped = try XCTUnwrap(model.declineReportText)
        XCTAssertTrue(scoped.contains("(layout_not_supported)"))
        XCTAssertFalse(scoped.contains("Warnings shown"))
        XCTAssertFalse(scoped.contains("energy:per_100g"))
    }

    func testTheReportBuilderAndPresentationUseNoNetworkingOrStoredText() throws {
        // Tests 34 and 36: no networking API in the builder's target; no scene or app storage,
        // and no pasteboard read, on the pasted-label screens.
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let application = try FileManager.default.contentsOfDirectory(at: sources.appendingPathComponent("FoodLedgerApplication"),
                                                                      includingPropertiesForKeys: nil)
        for file in application where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for banned in ["URLSession", "URLRequest", "import Network"] { XCTAssertFalse(text.contains(banned), "\(file.lastPathComponent): \(banned)") }
        }
        let presentation = try FileManager.default.contentsOfDirectory(at: sources.appendingPathComponent("FoodLedgerPresentation"),
                                                                       includingPropertiesForKeys: nil)
        let pasted = presentation.filter { $0.lastPathComponent.hasPrefix("PastedLabel") }
        XCTAssertEqual(pasted.count, 4)
        for file in pasted {
            let text = try String(contentsOf: file, encoding: .utf8)
            for banned in ["@SceneStorage", "@AppStorage", "UIPasteboard", "NSPasteboard", "UserDefaults", "URLSession"] {
                XCTAssertFalse(text.contains(banned), "\(file.lastPathComponent): \(banned)")
            }
        }
    }

    // MARK: Test 36: decline retention

    func testADismissedScreenKeepsNothingAndClearsTheDeveloperToolsLines() throws {
        let stub = F.StubReader(F.declined(["multiple_panels"]))
        var lines: [String] = ["stale"]
        let model = F.textModel(stub) { lines = $0 }
        model.name = "Synthetic oat crackers"; model.text = F.pastedText
        model.readLabel()
        XCTAssertFalse(lines.isEmpty)
        model.dismissed()
        XCTAssertEqual(lines, [], "Developer tools codes are cleared")
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(model.name, "")
        XCTAssertNil(model.confirm)
        XCTAssertNil(model.declineReportText)
        // Paste again clears the text but keeps the name.
        model.name = "Synthetic oat crackers"; model.text = F.pastedText
        model.readLabel()
        model.clearText()
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(model.name, "Synthetic oat crackers")
        XCTAssertTrue(model.declineMessages.isEmpty)
    }

    // MARK: Test 37: hashing is byte exact

    func testNFCAndNFDTextHashDifferentlyAndAreReadAsTyped() {
        let stub = F.StubReader(F.reading())
        let reader = PastedLabelReader(reader: stub, digester: SHA256Digester())
        let nfc = "營養標示 caf\u{E9}", nfd = "營養標示 cafe\u{301}"
        _ = reader.read(nfc)
        _ = reader.read(nfd)
        XCTAssertEqual(stub.texts, [nfc, nfd])
        XCTAssertTrue(stub.texts[0].unicodeScalars.elementsEqual(nfc.unicodeScalars))
        XCTAssertTrue(stub.texts[1].unicodeScalars.elementsEqual(nfd.unicodeScalars), "never normalised")
        XCTAssertNotEqual(stub.hashes[0], stub.hashes[1])
    }

    // MARK: Test 35: privacy wording, verbatim

    func testThePrivacyDocumentsCarryTheApprovedWordingAndANewEffectiveDate() throws {
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs")
        let egress = try String(contentsOf: docs.appendingPathComponent("privacy-and-egress.md"), encoding: .utf8)
        let policy = try String(contentsOf: docs.appendingPathComponent("privacy-policy.txt"), encoding: .utf8)
        XCTAssertTrue(egress.contains("| Clipboard, share sheet or the iOS screenshot editor | The report text, or a Full Page PDF of Health (the report) or Today (today's food totals, quick-add favourite names and amounts, today's note count and today-so-far Health values), created in memory; or a misread report for a pasted nutrition label (the pasted label text, the values read from it, and the parser, gate, check and conversion versions), as previewed and edited by the user | Only when the user chooses Copy all, Share, a screenshot's Full Page, or Report a misread, and then saves or shares it; the user picks the destination in the system share sheet and can cancel; the app has no destination of its own and nothing is sent automatically | [README.md](../README.md), [pasted-nutrition-label-v1.md](pasted-nutrition-label-v1.md) |"))
        XCTAssertTrue(policy.contains("today's note count and today-so-far Health values. If you choose Report a misread for a pasted nutrition label, the app shows a report containing the pasted label text, the values it read and the reader versions; you can edit it, and it goes only to the destination you pick in the share sheet, or nowhere if you cancel."))
        XCTAssertTrue(policy.contains("Receipt text you paste and text extracted from a PDF you select can be retained as evidence. Nutrition-label text you paste and then log is kept locally, unchanged, as the evidence for that food; it is read on your device and is not sent to any service."))
        XCTAssertFalse(policy.contains("Effective 4 October 2026"))
        XCTAssertTrue(policy.split(separator: "\n")[1].hasPrefix("Effective "))
        let section = egress.components(separatedBy: "## Allowed egress")[1].components(separatedBy: "\n## ")[0]
        XCTAssertEqual(section.split(separator: "\n").filter { $0.hasPrefix("| ") }.count, 8,
                       "header, separator and six destinations: no row and no destination is added")
    }
}

private extension FoodConfirmationPhase {
    var debugDescription: String { "\(self)" }
}
