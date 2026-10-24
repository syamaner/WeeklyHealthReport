import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Pasted nutrition label v1, PR 3 (`docs/pasted-nutrition-label-v1.md` sections 2.4, 3, 5 and
/// 6; tests 10 to 16 and 19 of section 8.4): the `LabelTextReading` port, the reader's product
/// decisions, the confirmation builder, and save and reopen through PR 2's verification. The
/// reader is a stub behind the port; the real adapter is tested in `FoodLabelTextCaptureTests`.
/// Every fixture is synthetic.
final class PastedLabelApplicationContractTests: XCTestCase {
    private typealias F = PastedLabelFixtures
    private typealias R = PastedReadingFixtures

    // MARK: 10. Confirm input from a non-declined reading

    func test10EveryStoredValueCitesAStoredColumnCellAndCalculatedValuesCarryOneTransform() throws {
        let review = try R.review(R.reading())
        XCTAssertEqual(review.flags, [LabelReading.Flag(code: "required_row_missing", concerns: "saturates")],
                       "A calculated value satisfies its row's G3; saturates stays a flag")
        let input = try R.input(review)
        let candidate = input.candidates[0].candidate
        let manifest = try R.manifest(input)
        XCTAssertEqual(manifest.conversions, [F.kcal, F.sodium])
        XCTAssertEqual(manifest.storedHeaderID, "h2")
        XCTAssertEqual(manifest.launchScope, ["taiwan_nutrition_labelling"])
        XCTAssertEqual(manifest.flagsShown, [.init(code: "required_row_missing", concerns: "saturates")])
        XCTAssertEqual(manifest.pastedText, F.pastedText)
        XCTAssertEqual(manifest.candidate, try F.candidate())
        for entry in candidate.nutrients.entries {
            if case .unknown = entry.value { continue }
            for provenance in entry.value.provenance {
                XCTAssertEqual(provenance.sourceKind, .userVerifiedPanel, "\(entry.key)")
                XCTAssertTrue(provenance.manifestReference?.value.contains(";header=h2;row=") == true, "\(entry.key) cites a stored-column cell")
            }
        }
        // Calculated: measured, printed source value and unit, exactly one allow-listed transform.
        for (key, unit, source, stored) in [(NutrientKey.energyConsumed, "kJ", 1550.0, 370.5), (.sodium, "g_salt", 0.6, 240.0)] {
            let value = try XCTUnwrap(candidate.nutrients.entries.first { $0.key == key }?.value)
            guard case let .measured(exact) = value, case let .exact(sourceValue) = exact.sourceValue else { return XCTFail("\(key)") }
            XCTAssertEqual(exact.amount, stored); XCTAssertEqual(sourceValue.unit.value, unit); XCTAssertEqual(sourceValue.amount, source)
            XCTAssertEqual(exact.provenance.flatMap(\.transforms).count, 1, "\(key)")
            XCTAssertTrue(NutrientDerivation.isCalculated(value), "\(key)")
        }
        // No other-column fill: the per-serving column's 111 kcal is never used; rows the stored
        // column does not print stay unknown, never zero; a bound stays a bound.
        let byKey = Dictionary(uniqueKeysWithValues: candidate.nutrients.entries.map { ($0.key, $0.value) })
        XCTAssertNotEqual(byKey[.energyConsumed].flatMap { if case let .measured(v) = $0 { v.amount } else { nil } }, 111)
        for key in [NutrientKey.sugar, .fiber, .fatSaturated] {
            guard case .unknown(.notDeclared) = byKey[key] else { return XCTFail("\(key) must stay unknown") }
        }
        guard case let .bounded(fat) = byKey[.fatTotal] else { return XCTFail("fat bound") }
        XCTAssertEqual(fat.upper, 0.5); XCTAssertNil(fat.lower)
    }

    // MARK: 11. Conversion verification at save

    func test11SaveFailsWhenACalculatedAmountDiffersOrAConversionSitsBesideItsPrintedCounterpart() throws {
        struct Permissive: PastedLabelConversionChecking { func storedTextMatches(_: PastedLabelManifest.Conversion) -> Bool { true } }
        let wrong = PastedLabelManifest.Conversion(nutrient: "energy_kcal", rule: "kj_to_kcal_v1", ruleVersion: "pasted-label-conversions-v1",
            sourceHeaderID: "h2", sourceRowID: "熱量", operandText: "1550", operandUnit: "kJ", factorText: "4.184",
            intermediateText: "370.458891", storedText: "370.6")
        let review = try R.review(R.reading(conversions: [wrong, F.sodium]))
        // The builder itself verifies through the injected port, so a wrong amount never reaches Confirm…
        XCTAssertThrowsError(try R.input(review))
        // …and one built past a permissive port is refused at save before policy.
        let forged = try R.input(review, conversions: Permissive())
        // A conversion recorded where the stored column prints the counterpart is never built.
        let printedKcal = F.cell("熱量", "energy_kcal", "h2", "380大卡", "380", "大卡", canonical: "kcal")
        XCTAssertThrowsError(try R.input(R.review(R.reading(candidate: F.candidate(cells: [printedKcal]))), conversions: Permissive()))
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            XCTAssertThrowsError(try F.service(harness).save(F.state(forged), operationID: LedgerFixtures.operationID(9_900))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource, harness.name)
            }
            XCTAssertEqual(try harness.reader.counts().operations, 0, harness.name)
        }
    }

    // MARK: 12. Hard declines write nothing

    func test12HardDeclinedReadingsYieldNoConfirmationAndWriteNothing() throws {
        let parserDeclined = PastedLabelManifest.Candidate(route: "A", inputSHA256: try F.textHash(), declined: true,
            declineReasons: ["count_mismatch"], wouldMarkReady: false, language: "zh-Hant", servingSize: nil, servingsPerPack: nil,
            headers: [], cells: [], warnings: [])
        let declined: [(String, LabelReading, [String])] = [
            ("parser", try R.reading(candidate: parserDeclined, gate: nil, conversions: [], storedHeaderID: nil), ["count_mismatch"]),
            ("G2", try R.reading(gate: .init(format: "taiwan_nutrition_labelling", skipped: nil,
                                             hardDeclines: ["not_a_food_nutrition_panel"], flags: [])), ["not_a_food_nutrition_panel"]),
            ("failed candidate", try R.reading(gate: .init(format: "taiwan_nutrition_labelling", skipped: "failed_candidate",
                                                           hardDeclines: ["unreadable_table"], flags: [])), ["unreadable_table"]),
            ("UK after the gate", try R.reading(format: "uk_nutrition_declaration",
                gate: .init(format: "uk_nutrition_declaration", skipped: nil, hardDeclines: [], flags: [])), ["layout_not_supported"]),
            ("US", try R.reading(format: "us_nutrition_facts", gate: nil), ["layout_not_supported"]),
            ("ambiguous", try R.reading(format: "format_ambiguous", gate: nil), ["format_ambiguous"]),
            ("no table", try R.reading(storedHeaderID: nil), ["no_table"])
        ]
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let before = try harness.reader.counts()
            for (name, reading, codes) in declined {
                let stub = StubLabelTextReader(reading)
                let outcome = PastedLabelReader(reader: stub, digester: LedgerFixtures.digester).read(F.pastedText)
                XCTAssertEqual(outcome, .declined(codes: codes, reading: reading), name)
                if case .usable = outcome { XCTFail("\(name) must not reach Confirm") }
                for code in codes { XCTAssertEqual(PastedLabelCodes.classify(code).kind, .hardDecline, "\(name) \(code)") }
            }
            // Over the length limit: declined before hashing or reading.
            let stub = StubLabelTextReader(try R.reading())
            let long = String(repeating: "a", count: PastedLabelManifest.maximumTextScalars + 1)
            XCTAssertEqual(PastedLabelReader(reader: stub, digester: LedgerFixtures.digester).read(long), .declined(codes: ["text_too_long"], reading: nil))
            XCTAssertEqual(stub.calls, 0)
            XCTAssertEqual(try harness.reader.counts(), before, "A decline writes nothing (\(harness.name))")
        }
    }

    // MARK: 13. Warnings never block or enable Log

    func test13AFailedCheckIsAWarningOnlyAndLogEnablementIsUnchanged() throws {
        let failing = LabelReading.Check(name: "energy", basis: "per_100g", nutrient: nil, child: nil, status: .fail)
        let warned = try R.review(R.reading(checks: [failing]))
        let quiet = try R.review(R.reading())
        XCTAssertEqual(warned.warningCodes, ["energy:per_100g"])
        XCTAssertEqual(quiet.warningCodes, [], "A pass shows nothing")
        let warnedInput = try R.input(warned), quietInput = try R.input(quiet)
        XCTAssertEqual(try R.manifest(warnedInput).warningsShown, ["energy:per_100g"])
        XCTAssertEqual(try R.manifest(quietInput).warningsShown, [])
        func requirements(_ input: PopulatedFoodConfirmation, quantity: Double?) -> [FoodLogRequirement] {
            var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(quantity, .grams))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            return FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: .current)
        }
        for quantity in [nil, 40.0] {
            XCTAssertEqual(requirements(warnedInput, quantity: quantity), requirements(quietInput, quantity: quantity))
        }
        XCTAssertEqual(requirements(warnedInput, quantity: 40), [], "With an amount, Log is enabled with or without the warning")
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            XCTAssertNoThrow(try F.service(harness).save(F.state(warnedInput), operationID: LedgerFixtures.operationID(9_910)), harness.name)
        }
    }

    // MARK: 14. Save and reopen verification of builder output

    func test14AlteredValueUnitBoundBasisOrManifestByteFailsAtSaveAndReopen() throws {
        let input = try R.input(R.review(R.reading()))
        let provenance = try XCTUnwrap(input.candidates[0].candidate.nutrients.entries.first { $0.key == .carbohydrates }).value.provenance
        func exact(_ amount: Double, unit: String = "g", basis: ResolutionBasis = .per100Grams) throws -> NutrientValue {
            .measured(try ExactNutrientValue(amount: amount, unit: .grams,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(unit), basis: basis)), provenance: provenance))
        }
        guard case let .text(payload) = input.evidence[0].originalPayload else { return XCTFail() }
        let original = input.evidence[0]
        let alteredEvidence = try CaptureEvidence(evidenceID: original.evidenceID, kind: .labelText, capturedAt: original.capturedAt,
            locale: original.locale, captureMethod: original.captureMethod, captureMethodVersion: original.captureMethodVersion,
            originalPayload: .text(LedgerText(payload.value.replacingOccurrences(of: "60.1", with: "61.0"))), byteHash: original.byteHash)
        let tampered: [(String, PopulatedFoodConfirmation)] = [
            ("value", try F.replacing(input, .carbohydrates, with: exact(61))),
            ("unit", try F.replacing(input, .carbohydrates, with: .measured(ExactNutrientValue(amount: 60.1, unit: .grams,
                sourceValue: .exact(SourceExactNutrientValue(amount: 60.1, unit: LedgerText("公克"), basis: .per100Grams)),
                provenance: [NutrientProvenance(sourceKind: .userVerifiedPanel, sourceID: provenance[0].sourceID,
                    sourceReleaseID: provenance[0].sourceReleaseID, evidenceID: provenance[0].evidenceID, capturedAt: provenance[0].capturedAt,
                    manifestReference: provenance[0].manifestReference,
                    transforms: [NutrientTransform(transformID: LedgerText("unit"), transformVersion: LedgerText("v1"))])])))),
            ("bound", try F.replacing(input, .fatTotal, with: exact(0.5))),
            ("basis", try F.replacing(input, .carbohydrates, with: exact(60.1, basis: .per100Millilitres))),
            ("manifest byte", try PopulatedFoodConfirmation(evidence: [alteredEvidence], sourceReleases: input.sourceReleases,
                candidates: input.candidates, expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity))
        ]
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            for (index, (name, changed)) in tampered.enumerated() {
                XCTAssertThrowsError(try F.service(harness).save(F.state(changed), operationID: LedgerFixtures.operationID(9_920 + index))) {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource, "\(harness.name) \(name)")
                }
            }
            XCTAssertEqual(try harness.reader.counts().operations, 0, "Refused before policy (\(harness.name))")
            let saved = try F.service(harness).save(F.state(input), operationID: LedgerFixtures.operationID(9_930))
            XCTAssertNotNil(try F.service(harness).reopen(logItemID: saved.logItem.logItemID), harness.name)
            let rewritten = try PastedLabelContractTests.rewriteStored(saved, replacing: "60.1公克", with: "61.0公克")
            let service = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer),
                reader: SingleSavedReader(saved: rewritten), clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(),
                digester: LedgerFixtures.digester, pastedLabelConversions: GoldenPastedLabelConversions())
            XCTAssertThrowsError(try service.reopen(logItemID: saved.logItem.logItemID), harness.name) {
                guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\($0)") }
            }
        }
    }

    // MARK: 15. Cross-route isolation

    func test15ReviewedWebAndPastedLabelVerifiersRejectEachOthersEvidence() throws {
        let pasted = try R.input(R.review(R.reading()))
        let reviewed = try ReviewedWebFixtures.v1Fixture("representative-serving").input
        XCTAssertEqual(pasted.evidence[0].kind, .labelText)
        XCTAssertTrue(reviewed.evidence.contains { $0.kind == .labelText }, "Both routes use kind = .labelText")
        // The reviewed web verifier rejects pasted-label evidence…
        XCTAssertFalse(FoodReviewedWebProposalPolicy.applies(pasted, candidate: pasted.candidates[0]))
        XCTAssertNil(FoodReviewedWebProposalPolicy.scope(pasted, candidate: pasted.candidates[0]))
        // …and the pasted-label verifier rejects reviewed web evidence.
        XCTAssertFalse(PanelSourceAdmission.applies(reviewed, candidate: reviewed.candidates[0]))
        XCTAssertFalse(PastedLabelSource.verify(reviewed, candidate: reviewed.candidates[0], encoder: LedgerFixtures.encoder,
                                                digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions()))
        // Pasted-label evidence relabelled as the reviewed web route's capture is refused by both.
        let original = pasted.evidence[0]
        let relabelled = try CaptureEvidence(evidenceID: original.evidenceID, kind: .labelText, capturedAt: original.capturedAt,
            locale: original.locale, captureMethod: reviewed.evidence.first { $0.kind == .labelText }!.captureMethod,
            captureMethodVersion: reviewed.evidence.first { $0.kind == .labelText }!.captureMethodVersion,
            originalPayload: original.originalPayload, byteHash: original.byteHash)
        let swapped = try PopulatedFoodConfirmation(evidence: [relabelled], sourceReleases: pasted.sourceReleases,
            candidates: pasted.candidates, expectedIdentity: pasted.expectedIdentity, expectedEdibleQuantity: pasted.expectedEdibleQuantity)
        XCTAssertFalse(PanelSourceAdmission.verify(swapped, candidate: swapped.candidates[0], encoder: LedgerFixtures.encoder,
                                                   digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions()))
        XCTAssertNil(FoodReviewedWebProposalPolicy.scope(swapped, candidate: swapped.candidates[0]))
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            XCTAssertThrowsError(try F.service(harness).save(F.state(swapped), operationID: LedgerFixtures.operationID(9_940))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource, harness.name)
            }
        }
    }

    // MARK: 16. Plain exact save and the fortification answer

    func test16SaveWritesNoAssertionAndTheFortificationAnswerDecidesSourceIdentityMissing() throws {
        let review = try R.review(R.reading())
        func requirements(_ input: PopulatedFoodConfirmation) -> [FoodLogRequirement] {
            var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(40, .grams))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            return FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: .current)
        }
        for answer in [PastedLabelIdentity.FortificationAnswer.yes, .no] {
            let input = try R.input(review, details: .init(name: "Synthetic oat crackers", fortification: answer))
            XCTAssertEqual(requirements(input), [], "\(answer)")
        }
        let unanswered = try R.input(review, details: .init(name: "Synthetic oat crackers"))
        XCTAssertEqual(requirements(unanswered), [.decideDifference(.fortification)], "#306: an inline decision")
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let saved = try service.save(F.state(R.input(review)), operationID: LedgerFixtures.operationID(9_950))
            XCTAssertEqual(saved.assertions, [], "A pasted-label save writes no assertion (\(harness.name))")
            XCTAssertEqual(saved.resolutionVersion.methodVersion.value, "food_confirmation_v5", harness.name)
            // Unanswered: refused until fortification is answered (#306: inline, or through Food details).
            var state = FoodConfirmationState(input: unanswered, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(40, .grams))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(9_951))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .unmetRequirements([.decideDifference(.fortification)]), harness.name)
            }
            let source = unanswered.candidates[0]
            let identity = try PastedLabelIdentity.identity(fortification: .no, servingBasis: .per100Grams)
            FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(try FoodCorrection(name: source.name, brand: source.brand,
                variant: nil, identity: identity, itemClass: .food, nutrients: source.candidate.nutrients,
                reason: LedgerText("Synthetic: the pack does not say vitamins or minerals are added."))))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            XCTAssertNoThrow(try service.save(state, operationID: LedgerFixtures.operationID(9_952)), harness.name)
        }
    }

    // MARK: Flags, corrections and entries

    func testFlagsNeverBlockLogAndUserValuesAreRecordedWithTheInjectedClock() throws {
        let review = try R.review(R.reading())
        let clockTime = Date(timeIntervalSince1970: 1_700_000_500)
        let builder = R.builder(at: clockTime)
        let entered = try builder.correction("saturates", value: .init(decimalText: "0.2", unit: "g", comparator: "="), in: review)
        let corrected = try builder.correction("protein", value: .init(decimalText: "5.4", unit: "g", comparator: "="), in: review)
        let calculated = try builder.correction("energy_kcal", value: .init(decimalText: "371", unit: "kcal", comparator: "="), in: review)
        XCTAssertEqual(entered, .init(kind: .entered, nutrient: "saturates", rowID: nil, headerID: "h2", recognised: nil,
                                      corrected: .init(decimalText: "0.2", unit: "g", comparator: "="), at: clockTime))
        XCTAssertEqual(corrected.kind, .corrected); XCTAssertEqual(corrected.rowID, "蛋白質")
        XCTAssertEqual(corrected.recognised, .init(printedText: "5.2公克", decimalText: "5.2", unit: "公克", comparator: "="))
        XCTAssertEqual(calculated.recognised?.printedText, "1550 kJ", "A corrected calculated value names its printed source")
        XCTAssertThrowsError(try builder.correction("trans_fat", value: .init(decimalText: "0", unit: "g", comparator: "="), in: review))
        XCTAssertThrowsError(try builder.correction("protein", value: .init(decimalText: "5,4,1", unit: "g", comparator: "="), in: review))
        XCTAssertThrowsError(try builder.correction("protein", value: .init(decimalText: "5.4", unit: "mg", comparator: "="), in: review))

        // Untouched flags save with the row unknown; an entered row resolves its flag.
        let flagged = try R.input(review)
        XCTAssertEqual(try R.manifest(flagged).flagsShown, [.init(code: "required_row_missing", concerns: "saturates")])
        let resolved = try R.input(review, corrections: [entered, corrected, calculated])
        let manifest = try R.manifest(resolved)
        XCTAssertEqual(manifest.flagsShown, [])
        XCTAssertEqual(manifest.corrections, [entered, corrected, calculated])
        XCTAssertEqual(manifest.conversions, [F.kcal, F.sodium], "The conversion record stays as evidence of what Confirm showed")
        let values = Dictionary(uniqueKeysWithValues: resolved.candidates[0].candidate.nutrients.entries.map { ($0.key, $0.value) })
        for key in [NutrientKey.fatSaturated, .protein, .energyConsumed] {
            XCTAssertEqual(values[key]?.provenance.first?.sourceKind, .manualDeclaration, "\(key)")
        }
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let unknown = try service.save(F.state(flagged), operationID: LedgerFixtures.operationID(9_960))
            guard case .unknown = try XCTUnwrap(unknown.resolutionVersion.nutrients.entries.first { $0.key == .fatSaturated }).value else {
                return XCTFail("A flagged row left alone stays unknown, never zero")
            }
            XCTAssertNoThrow(try service.save(F.state(resolved), operationID: LedgerFixtures.operationID(9_961)), harness.name)
        }
    }

    func testCopyMappingHasAFallbackAndTheLaunchScopeIsTaiwanOnly() {
        XCTAssertEqual(PastedLabelLaunchScope.enabledFormats, ["taiwan_nutrition_labelling"])
        XCTAssertFalse(PastedLabelLaunchScope.admits("uk_nutrition_declaration"))
        XCTAssertEqual(PastedLabelCodes.classify("a_code_nobody_emits"), .init(kind: .hardDecline, copy: .unreadableTable))
        XCTAssertEqual(PastedLabelCodes.mapping.filter { $0.value.kind == .flag }.keys.sorted(),
                       ["column_count_mismatch", "required_basis_missing", "required_row_missing", "required_serving_declaration_missing"])
    }

    // MARK: G6 servings per pack, entered (contract section 3.2)

    func testAMissingServingsPerPackIsEnteredAsEvidenceOnBothStoresAndReencodesUnchanged() throws {
        let full = try F.candidate()
        let noPack = PastedLabelManifest.Candidate(route: full.route, inputSHA256: full.inputSHA256, declined: false, declineReasons: [],
            wouldMarkReady: false, language: full.language, servingSize: full.servingSize, servingsPerPack: nil,
            headers: full.headers, cells: full.cells, warnings: [])
        let g6 = LabelReading.Flag(code: "required_serving_declaration_missing", concerns: "servings_per_pack")
        let review = try R.review(R.reading(candidate: noPack, gate: .init(format: "taiwan_nutrition_labelling", skipped: nil,
                                                                         hardDeclines: [], flags: [g6])))
        XCTAssertEqual(review.flags, [g6], "G6 is a flag, never a decline")
        let clockTime = Date(timeIntervalSince1970: 1_700_000_700)
        let entry = try R.builder(at: clockTime).correction("servings_per_pack",
            value: .init(decimalText: "8", unit: "count", comparator: "="), in: review)
        XCTAssertEqual(entry, .init(kind: .entered, nutrient: "servings_per_pack", rowID: nil, headerID: "h2", recognised: nil,
                                    corrected: .init(decimalText: "8", unit: "count", comparator: "="), at: clockTime))
        for bad in [PastedLabelManifest.Correction.Value(decimalText: "8", unit: "g", comparator: "="),
                    .init(decimalText: "0", unit: "count", comparator: "="), .init(decimalText: "8", unit: "count", comparator: "<")] {
            XCTAssertThrowsError(try R.builder().correction("servings_per_pack", value: bad, in: review), "\(bad)")
        }
        // A printed servings-per-pack line is never overwritten.
        XCTAssertThrowsError(try R.builder().correction("servings_per_pack",
            value: .init(decimalText: "8", unit: "count", comparator: "="), in: R.review(R.reading())))

        let unfilled = try R.input(review)
        let filled = try R.input(review, corrections: [entry])
        let manifest = try R.manifest(filled)
        XCTAssertEqual(manifest.corrections, [entry])
        XCTAssertEqual(manifest.flagsShown, [], "The entered line resolves its flag")
        XCTAssertEqual(try R.manifest(unfilled).flagsShown, [.init(code: "required_serving_declaration_missing", concerns: "servings_per_pack")])
        // Evidence only: every nutrient value is the same (provenance differs only by the manifest hash).
        func values(_ input: PopulatedFoodConfirmation) -> [String] {
            input.candidates[0].candidate.nutrients.entries.map { entry in
                switch entry.value {
                case let .measured(exact): "\(entry.key.rawValue)=\(exact.amount)"
                case let .bounded(bounds): "\(entry.key.rawValue)<\(String(describing: bounds.upper))"
                default: "\(entry.key.rawValue):\(entry.value.provenance.isEmpty ? "unknown" : "other")"
                }
            }
        }
        XCTAssertEqual(values(filled), values(unfilled))
        XCTAssertEqual(filled.candidates[0].candidate.identity.servingBasis, unfilled.candidates[0].candidate.identity.servingBasis)
        // The stored bytes decode and re-encode unchanged.
        guard case let .text(payload) = filled.evidence[0].originalPayload else { return XCTFail() }
        let bytes = Data(payload.value.utf8)
        XCTAssertEqual(try LedgerFixtures.encoder.encode(try XCTUnwrap(PastedLabelManifest.decode(bytes))), bytes)

        // The verifier refuses an entered value beside a printed line, a second entry, or a corrected kind.
        let printed = try F.manifest(corrections: [entry])
        XCTAssertThrowsError(try F.input(printed), "The label prints servings per pack")
        let twice = PastedLabelManifest(pastedText: manifest.pastedText, pastedTextSHA256: manifest.pastedTextSHA256,
            parserVersion: manifest.parserVersion, gateVersion: manifest.gateVersion, arithmeticVersion: manifest.arithmeticVersion,
            conversionVersion: manifest.conversionVersion, labelFormat: manifest.labelFormat, launchScope: manifest.launchScope,
            identityMapping: manifest.identityMapping, candidate: manifest.candidate, storedHeaderID: manifest.storedHeaderID,
            conversions: manifest.conversions, flagsShown: [], corrections: [entry, entry], warningsShown: [],
            name: manifest.name, brand: manifest.brand)
        XCTAssertThrowsError(try F.input(twice))

        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let saved = try service.save(F.state(filled), operationID: LedgerFixtures.operationID(9_980))
            XCTAssertEqual(saved.evidence, filled.evidence, harness.name)
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(reopened.input.candidates[0], filled.candidates[0], harness.name)
            guard case let .text(stored) = try XCTUnwrap(harness.reader.evidence(id: filled.evidence[0].evidenceID), harness.name)
                .originalPayload else { return XCTFail() }
            XCTAssertEqual(Data(stored.value.utf8), bytes, "Stored verbatim (\(harness.name))")
        }
    }

    // MARK: Whole pack from an entered servings per pack (contract section 2.3)

    private func perServing(packLine: PastedLabelManifest.Candidate.ServingsPerPack?, readableServingSize: Bool = true,
                            corrections: [PastedLabelManifest.Correction] = []) throws -> PastedLabelManifest {
        let base = try F.perServingManifest(readableServingSize: readableServingSize)
        let c = base.candidate
        let candidate = PastedLabelManifest.Candidate(route: c.route, inputSHA256: c.inputSHA256, declined: false, declineReasons: [],
            wouldMarkReady: false, language: c.language, servingSize: c.servingSize, servingsPerPack: packLine, headers: c.headers,
            cells: c.cells, warnings: [])
        return PastedLabelManifest(pastedText: base.pastedText, pastedTextSHA256: base.pastedTextSHA256, parserVersion: base.parserVersion,
            gateVersion: base.gateVersion, arithmeticVersion: base.arithmeticVersion, conversionVersion: base.conversionVersion,
            labelFormat: base.labelFormat, launchScope: base.launchScope, identityMapping: base.identityMapping, candidate: candidate,
            storedHeaderID: base.storedHeaderID, conversions: [], flagsShown: [], corrections: corrections, warningsShown: [],
            name: base.name, brand: base.brand)
    }

    func testWholePackUsesAPrintedExactOrAnEnteredServingsPerPackAndLogsAsServingsOnBothStores() throws {
        let entered = PastedLabelManifest.Correction(kind: .entered, nutrient: "servings_per_pack", rowID: nil, headerID: "h1",
            recognised: nil, corrected: .init(decimalText: "8", unit: "count", comparator: "="), at: Date(timeIntervalSince1970: 1_700_000_800))
        let input = try F.input(perServing(packLine: nil, corrections: [entered]))
        XCTAssertEqual(PastedLabelServingPolicy.wholePack(input, candidate: input.candidates[0]),
                       PastedLabelWholePack(servings: 8, origin: .enteredByYou(correctionIndex: 0)))
        let printed = try F.input(perServing(packLine: .init(printedText: "本包裝含10份", decimalText: "10", approximate: false)))
        XCTAssertEqual(PastedLabelServingPolicy.wholePack(printed, candidate: printed.candidates[0]), PastedLabelWholePack(servings: 10, origin: .printed))
        let about = try F.input(perServing(packLine: .init(printedText: "本包裝含約10份", decimalText: "10", approximate: true)))
        XCTAssertNil(PastedLabelServingPolicy.wholePack(about, candidate: about.candidates[0]), "About is never a whole pack")
        let none = try F.input(perServing(packLine: nil))
        XCTAssertNil(PastedLabelServingPolicy.wholePack(none, candidate: none.candidates[0]), "Nothing printed or entered")
        let noSize = try F.input(perServing(packLine: nil, readableServingSize: false, corrections: [entered]))
        XCTAssertNil(PastedLabelServingPolicy.wholePack(noSize, candidate: noSize.candidates[0]), "A serving with no weight or volume")
        let per100 = try F.input(F.per100Manifest(servingSize: nil))
        XCTAssertNil(PastedLabelServingPolicy.wholePack(per100, candidate: per100.candidates[0]), "Per 100 g with no serving size")

        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(8, .count))
            state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(9_990))
            XCTAssertEqual(saved.logItemVersion.edibleQuantity, try PositiveQuantity(value: 240, unit: .grams), harness.name)
            let conversion = try XCTUnwrap(saved.quantityConversion, harness.name)
            XCTAssertEqual(conversion.sourceQuantity, try PositiveQuantity(value: 8, unit: .count))
            XCTAssertEqual(conversion.methodVersion.value, PastedLabelServingPolicy.version)
            XCTAssertEqual(conversion.evidenceID, input.evidence[0].evidenceID, "Cites the manifest that holds the entered count")
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(PastedLabelServingPolicy.wholePack(reopened.input, candidate: reopened.input.candidates[0]),
                           PastedLabelWholePack(servings: 8, origin: .enteredByYou(correctionIndex: 0)), harness.name)
        }
    }

    // MARK: 28. Basis-state markers (contract section 8.8)

    func test28EnglishBasisStateMarkersMatchWholeWordsAndChineseMarkersMatchSubstrings() throws {
        for text in ["Per 100ml as prepared", "PREPARED", "per serving (prepared)", "Drained weight", "100g drained,",
                     "每100毫升（沖泡後）", "每100公克(瀝乾)", "沖泡"] {
            XCTAssertTrue(PastedLabelBasisState.marks(text), text)
        }
        for text in ["Per 100g unprepared", "UNDRAINED", "preparedness", "Per 100g", "每100公克", "每份", "drainedx"] {
            XCTAssertFalse(PastedLabelBasisState.marks(text), text)
        }
        let candidate = try F.candidate()
        func with(header: String) -> PastedLabelManifest.Candidate {
            .init(route: candidate.route, inputSHA256: candidate.inputSHA256, declined: false, declineReasons: [], wouldMarkReady: false,
                  language: candidate.language, servingSize: candidate.servingSize, servingsPerPack: candidate.servingsPerPack,
                  headers: [candidate.headers[0], .init(headerID: "h2", printedText: header, basis: "per_100g", servingConversion: nil)],
                  cells: candidate.cells, warnings: [])
        }
        XCTAssertEqual(PastedLabelReader.classify(try R.reading(candidate: with(header: "Per 100g unprepared")), pastedText: F.pastedText).declineCodes, [])
        XCTAssertEqual(PastedLabelReader.classify(try R.reading(candidate: with(header: "Per 100g as prepared")), pastedText: F.pastedText).declineCodes,
                       ["basis_state_not_supported"])
    }

    // MARK: 19. Reuse reads no text

    /// Test 19 (contract section 6.4): reuse in v1 is through Recent foods and Favourites, with
    /// today's re-log semantics (new log item over the same evidence and release, new product and
    /// resolution versions with the same nutrients). Search by name is follow-up #269.
    func test19ALoggedLabelReusedFromRecentsCreatesANewLogItemAndReadsNoText() throws {
        let stub = StubLabelTextReader(try R.reading())
        guard case let .usable(review) = PastedLabelReader(reader: stub, digester: LedgerFixtures.digester).read(F.pastedText) else {
            return XCTFail("usable")
        }
        XCTAssertEqual(stub.calls, 1)
        let input = try R.input(review)
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let saved = try service.save(F.state(input), operationID: LedgerFixtures.operationID(9_970))
            let before = try harness.reader.counts()
            var state = try XCTUnwrap(service.relogState(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(80, .grams))
            state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let relogged = try service.save(state, operationID: LedgerFixtures.operationID(9_971))
            XCTAssertNotEqual(relogged.logItem.logItemID, saved.logItem.logItemID)
            XCTAssertEqual(relogged.evidence, saved.evidence, "The stored manifest bytes, re-verified, not re-read")
            XCTAssertEqual(relogged.sourceReleases, saved.sourceReleases)
            XCTAssertEqual(relogged.resolutionVersion.nutrients, saved.resolutionVersion.nutrients)
            XCTAssertEqual(try harness.reader.counts().evidence, before.evidence, "No new evidence (\(harness.name))")
            // A favourite's input is the same restore and re-verification of the stored manifest.
            let favourite = try service.favouriteInput(saved)
            XCTAssertEqual(favourite.evidence, saved.evidence, harness.name)
            XCTAssertEqual(favourite.candidates[0].candidate.nutrients, saved.resolutionVersion.nutrients, harness.name)
            XCTAssertThrowsError(try F.service(harness, conversions: nil).favouriteInput(saved),
                                 "Without the conversion port the calculated values fail closed (\(harness.name))")
        }
        XCTAssertEqual(stub.calls, 1, "Reuse never reads text")
    }
}

private struct SingleSavedReader: FoodConfirmationReading {
    let saved: StoredFoodConfirmation
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { saved.sourceReleases.first { $0.sourceReleaseID == id } }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { logItemID == saved.logItem.logItemID ? saved : nil }
    func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? {
        logItemVersionID == saved.logItemVersion.logItemVersionID ? saved : nil
    }
    func evidence(id: EvidenceID) throws -> CaptureEvidence? { saved.evidence.first { $0.evidenceID == id } }
}
