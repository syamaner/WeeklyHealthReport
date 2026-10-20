import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import GRDB
import XCTest

/// Pasted nutrition label v1, PR 2 (`docs/pasted-nutrition-label-v1.md` section 8.4): the
/// manifest, its verification at save and reopen, source admission, contract 7 and the
/// `v7_pasted_label` migration. Tests 17, 18, 30, 31, 32, 38 and 46 (application half), plus
/// golden round-trips. Every fixture is synthetic.
final class PastedLabelContractTests: XCTestCase {
    private typealias F = PastedLabelFixtures

    // MARK: Manifest encoding

    func testManifestGoldenBytesDecodeAndReencodeUnchanged() throws {
        let bytes = try F.data(F.manifest())
        XCTAssertEqual(try LedgerFixtures.digester.sha256(bytes).value, Self.manifestGoldenSHA256)
        let decoded = try XCTUnwrap(PastedLabelManifest.decode(bytes))
        XCTAssertEqual(try F.data(decoded), bytes)
        let text = String(decoding: bytes, as: UTF8.self)
        // Sorted keys, unescaped slashes, verbatim text, dates in milliseconds, explicit nulls.
        XCTAssertTrue(text.hasPrefix(#"{"arithmetic_version":"label-arithmetic-checks-v1","brand":"Synthetic Mill","candidate":{"automatic_save":false,"cells":["#))
        XCTAssertTrue(text.contains(#""kind":"entered","nutrient":"fibre","recognised":null,"row_id":null}"#))
        XCTAssertTrue(text.contains(#""at":1700000100000"#))
        XCTAssertTrue(text.contains(#""serving_size":{"canonical_unit":"g","decimal_text":"30","printed_text":"每一份量30公克","unit":"公克"}"#))
        XCTAssertTrue(text.contains(#""version":"pasted-nutrition-label-v1""#))
        // An empty brand is omitted, never encoded.
        let unbranded = try F.data(F.manifest(brand: ""))
        XCTAssertFalse(String(decoding: unbranded, as: UTF8.self).contains("\"brand\""))
        XCTAssertEqual(try F.data(XCTUnwrap(PastedLabelManifest.decode(unbranded))), unbranded)
    }

    func testConversionMirrorEncodesTheSameBytesAsTheParserRecord() throws {
        // The literals are the PR 1 golden bytes of the parser's own record (test 45).
        let exact = PastedLabelManifest.Conversion(nutrient: "energy_kcal", rule: "kj_to_kcal_v1", ruleVersion: "pasted-label-conversions-v1",
            sourceHeaderID: "header_1", sourceRowID: "energy_kj", operandText: "1550", operandUnit: "kJ", factorText: "4.184",
            intermediateText: "370.458891", storedText: "370.5")
        XCTAssertEqual(String(decoding: try LedgerFixtures.encoder.encode(exact), as: UTF8.self),
            #"{"factor_text":"4.184","intermediate_text":"370.458891","nutrient":"energy_kcal","operand_text":"1550","operand_unit":"kJ","rule":"kj_to_kcal_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"energy_kj","stored_text":"370.5"}"#)
        let bound = PastedLabelManifest.Conversion(nutrient: "sodium", rule: "salt_to_sodium_v1", ruleVersion: "pasted-label-conversions-v1",
            sourceHeaderID: "header_1", sourceRowID: "salt", operandText: "0.01", operandUnit: "g_salt", factorText: "2.5",
            intermediateText: "4.000000", storedText: "4.0", comparator: "<", rounding: "outward")
        XCTAssertEqual(String(decoding: try LedgerFixtures.encoder.encode(bound), as: UTF8.self),
            #"{"comparator":"<","factor_text":"2.5","intermediate_text":"4.000000","nutrient":"sodium","operand_text":"0.01","operand_unit":"g_salt","rounding":"outward","rule":"salt_to_sodium_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"salt","stored_text":"4.0"}"#)
    }

    func testManifestDecodingIsStrictAtEveryLevel() throws {
        let text = String(decoding: try F.data(F.manifest()), as: UTF8.self)
        for (from, to) in [(#"{"arithmetic_version""#, #"{"extra":1,"arithmetic_version""#),
                           (#""flags_shown":[{"code""#, #""flags_shown":[{"extra":1,"code""#),
                           (#""persistence_authorized":false"#, #""persistence_authorized":true"#),
                           (#""status":"user_selection_only""#, #""status":"ready""#),
                           (#""version":"pasted-nutrition-label-v1""#, #""version":"pasted-nutrition-label-v2""#),
                           (#""recognised":null,"#, ""),
                           (#""brand":"Synthetic Mill","#, #""brand":"","#)] {
            let changed = text.replacingOccurrences(of: from, with: to)
            XCTAssertNotEqual(changed, text, from)
            XCTAssertNil(PastedLabelManifest.decode(Data(changed.utf8)), from)
        }
    }

    // MARK: Records the manifest yields (one derivation for build and verify)

    func testRecordsAreBoundToTheManifestCellsConversionsAndCorrections() throws {
        let input = try F.input(F.manifest())
        let evidence = input.evidence[0]
        let release = input.sourceReleases[0]
        let hash = try XCTUnwrap(evidence.byteHash)
        XCTAssertEqual(evidence.kind, .labelText)
        XCTAssertEqual(evidence.captureMethod.value, "User pasted nutrition label")
        XCTAssertEqual(evidence.captureMethodVersion.value, "pasted-nutrition-label-v1")
        guard case let .text(payload) = evidence.originalPayload else { return XCTFail("text payload") }
        XCTAssertEqual(Data(payload.value.utf8), try F.data(F.manifest()), "The manifest bytes are stored verbatim")
        XCTAssertEqual(release.sourceID.value, "pasted-nutrition-label")
        XCTAssertEqual(release.sourceReleaseID.value, "pasted-label:" + hash.value)
        XCTAssertEqual(release.manifestHash, hash)
        XCTAssertEqual(release.artifactHash.value, try F.textHash())
        XCTAssertEqual(release.schemaVersion.value, "pasted-nutrition-label-v1:taiwan_nutrition_labelling")
        XCTAssertEqual(release.pipelineVersion.value,
            "nutrition-label-text-parser-v2:label-capture-decline-gate-v2:label-arithmetic-checks-v1:pasted-label-conversions-v1")
        XCTAssertEqual(release.licence.value, "User-supplied label text; no redistribution licence inferred.")
        XCTAssertEqual(release.attribution.value, "Pasted nutrition label")

        let candidate = input.candidates[0]
        XCTAssertEqual(candidate.itemClass, .food)
        // The edible quantity is the basis quantity on both sides, so no acknowledgement is raised.
        XCTAssertEqual(candidate.candidate.edibleQuantity, .known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil))
        XCTAssertEqual(input.expectedEdibleQuantity, candidate.candidate.edibleQuantity)
        XCTAssertEqual(candidate.candidate.identity, try PastedLabelIdentity.identity(fortification: .no, servingBasis: .per100Grams))
        func value(_ key: NutrientKey) -> NutrientValue { candidate.candidate.nutrients.entries.first { $0.key == key }!.value }

        // Calculated: measured, printed source, exactly one allow-listed transform.
        guard case let .measured(energy) = value(.energyConsumed) else { return XCTFail("energy") }
        XCTAssertEqual(energy.amount, Double("370.5"))
        XCTAssertEqual(energy.sourceValue, .exact(try SourceExactNutrientValue(amount: 1550, unit: LedgerText("kJ"), basis: .per100Grams)))
        XCTAssertEqual(energy.provenance.map(\.sourceKind), [.userVerifiedPanel])
        XCTAssertEqual(energy.provenance[0].transforms.map(\.transformID.value), ["kj_to_kcal_v1"])
        XCTAssertEqual(energy.provenance[0].manifestReference?.value, "manifest-sha256=\(hash.value);header=h2;row=熱量;literal=1550 kJ")
        XCTAssertTrue(NutrientDerivation.isCalculated(value(.energyConsumed)))
        guard case let .measured(sodium) = value(.sodium) else { return XCTFail("sodium") }
        XCTAssertEqual(sodium.amount, 240)
        XCTAssertEqual(sodium.sourceValue, .exact(try SourceExactNutrientValue(amount: 0.6, unit: LedgerText("g_salt"), basis: .per100Grams)))
        // Corrected and entered: manual_declaration bound to the correction record.
        guard case let .measured(protein) = value(.protein), case let .measured(fibre) = value(.fiber) else { return XCTFail("corrections") }
        XCTAssertEqual(protein.amount, 5.4)
        XCTAssertEqual(protein.provenance.map(\.sourceKind), [.manualDeclaration])
        XCTAssertEqual(protein.provenance[0].manifestReference?.value, "manifest-sha256=\(hash.value);correction=0")
        XCTAssertEqual(fibre.amount, 2)
        XCTAssertEqual(fibre.provenance[0].manifestReference?.value, "manifest-sha256=\(hash.value);correction=1")
        // Printed: no transform; a bound stays a bound with its comparator.
        guard case let .measured(carbohydrate) = value(.carbohydrates), case let .bounded(fat) = value(.fatTotal) else { return XCTFail("printed") }
        XCTAssertEqual(carbohydrate.amount, 60.1)
        XCTAssertEqual(carbohydrate.provenance[0].transforms, [])
        XCTAssertEqual(carbohydrate.provenance[0].manifestReference?.value, "manifest-sha256=\(hash.value);header=h2;row=碳水化合物;literal=60.1公克")
        XCTAssertNil(fat.lower)
        XCTAssertEqual(fat.upper, 0.5)
        XCTAssertFalse(fat.upperClosed)
        XCTAssertEqual(fat.origin, .measured)
        // The per-serving column's kcal is never used; everything not printed is unknown, never zero.
        XCTAssertEqual(value(.sugar), .unknown(.notDeclared))
        XCTAssertEqual(value(.fatSaturated), .unknown(.notDeclared))
        XCTAssertEqual(candidate.candidate.nutrients.entries.filter { $0.value != .unknown(.notDeclared) }.count, 6)
    }

    func testStoredBasisFollowsTheFixedColumnRuleAndTheServingCaseIsSettled() throws {
        let perServingOnly = try F.candidate()
        let headers = [PastedLabelManifest.Candidate.Header(headerID: "h1", printedText: "每份", basis: "per_serving", servingConversion: "30公克")]
        func manifest(servingSize: PastedLabelManifest.Candidate.ServingSize?, corrections: [PastedLabelManifest.Correction] = []) throws -> PastedLabelManifest {
            let candidate = PastedLabelManifest.Candidate(route: "A", inputSHA256: perServingOnly.inputSHA256, declined: false, declineReasons: [],
                wouldMarkReady: false, language: "zh-Hant", servingSize: servingSize, servingsPerPack: nil, headers: headers,
                cells: perServingOnly.cells.filter { $0.headerID == "h1" }, warnings: [])
            let basis: ResolutionBasis = .perServing(try PositiveQuantity(value: 1, unit: .count))
            return PastedLabelManifest(pastedText: F.pastedText, pastedTextSHA256: try F.textHash(), parserVersion: PastedLabelSource.parserVersion,
                gateVersion: PastedLabelSource.gateVersion, arithmeticVersion: PastedLabelSource.arithmeticVersion,
                conversionVersion: PastedLabelSource.conversionVersion, labelFormat: "taiwan_nutrition_labelling",
                launchScope: ["taiwan_nutrition_labelling"], identityMapping: try .init(fortificationAnswer: .no, servingBasis: basis),
                candidate: candidate, storedHeaderID: "h1", conversions: [], flagsShown: [], corrections: corrections,
                warningsShown: [], name: "Synthetic", brand: nil)
        }
        XCTAssertEqual(try PastedLabelSource.storedBasis(F.manifest()), .per100Grams)
        // Section 6.3 case 2: a per-serving column with a readable serving size.
        XCTAssertEqual(try PastedLabelSource.storedBasis(manifest(servingSize: perServingOnly.servingSize)),
                       .perServing(try PositiveQuantity(value: 30, unit: .grams)))
        // Case 3 (settled here): no readable serving size is one serving, counted, with no weight.
        XCTAssertEqual(try PastedLabelSource.storedBasis(manifest(servingSize: nil)), .perServing(try PositiveQuantity(value: 1, unit: .count)))
        XCTAssertEqual(try PastedLabelSource.storedBasis(manifest(servingSize: .init(printedText: "每一份量", decimalText: nil, unit: nil, canonicalUnit: nil))),
                       .perServing(try PositiveQuantity(value: 1, unit: .count)))
        // The user's entered serving size ("Entered by you") becomes the basis.
        let entered = PastedLabelManifest.Correction(kind: .entered, nutrient: "serving_size", rowID: nil, headerID: "h1", recognised: nil,
            corrected: .init(decimalText: "25", unit: "g", comparator: "="), at: LedgerFixtures.date)
        XCTAssertEqual(try PastedLabelSource.storedBasis(manifest(servingSize: nil, corrections: [entered])),
                       .perServing(try PositiveQuantity(value: 25, unit: .grams)))
        // Entering a serving size over a readable one is not an entry, it would be a correction.
        XCTAssertThrowsError(try PastedLabelSource.storedBasis(manifest(servingSize: perServingOnly.servingSize, corrections: [entered])))
        // The stored column is fixed by the rule, never chosen.
        let chosen = try F.manifest()
        let wrongColumn = PastedLabelManifest(pastedText: chosen.pastedText, pastedTextSHA256: chosen.pastedTextSHA256, parserVersion: chosen.parserVersion,
            gateVersion: chosen.gateVersion, arithmeticVersion: chosen.arithmeticVersion, conversionVersion: chosen.conversionVersion,
            labelFormat: chosen.labelFormat, launchScope: chosen.launchScope, identityMapping: chosen.identityMapping, candidate: chosen.candidate,
            storedHeaderID: "h1", conversions: [], flagsShown: [], corrections: [], warningsShown: [], name: chosen.name, brand: chosen.brand)
        XCTAssertThrowsError(try PastedLabelSource.storedBasis(wrongColumn))
    }

    // MARK: Save and reopen verification

    func testSaveAndReopenVerifyAgainstTheStoredManifestOnBothStores() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let input = try F.input(F.manifest())
            let service = try F.service(harness)
            let saved = try service.save(F.state(input), operationID: LedgerFixtures.operationID(9_200))
            XCTAssertEqual(saved.resolutionVersion.nutrients, input.candidates[0].candidate.nutrients, harness.name)
            XCTAssertEqual(saved.assertions, [], "A pasted-label save writes no assertion (\(harness.name))")
            XCTAssertEqual(saved.resolutionVersion.methodVersion.value, "food_confirmation_v5", harness.name)
            XCTAssertEqual(saved.evidence, input.evidence, harness.name)
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(reopened.input.candidates[0], input.candidates[0], harness.name)
            // Without the conversion port, an entry with calculated values fails closed.
            XCTAssertThrowsError(try F.service(harness, conversions: nil).reopen(logItemID: saved.logItem.logItemID), harness.name) {
                guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\($0)") }
            }
        }
    }

    func testAProductCorrectionKeepsTheSourceVerifiableOnReopenButCannotChangeItsNutrients() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let input = try F.input(F.manifest())
            let service = try F.service(harness)
            let saved = try service.save(F.state(input), operationID: LedgerFixtures.operationID(9_250))
            var reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            let source = input.candidates[0]
            let renamed = try FoodCorrection(name: LedgerText("Renamed crackers"), brand: nil, variant: LedgerText("Family pack"),
                identity: source.candidate.identity, itemClass: .food, nutrients: source.candidate.nutrients,
                reason: LedgerText("Synthetic rename; the label values are unchanged."))
            FoodConfirmationReducer.reduce(state: &reopened, action: .applyCorrection(renamed))
            let corrected = try service.save(reopened, operationID: LedgerFixtures.operationID(9_251))
            XCTAssertEqual(corrected.productVersion.name.value, "Renamed crackers", harness.name)
            let again = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(again.input.candidates[0], source, "The source candidate is restored from the manifest (\(harness.name))")
            // A correction that changes a label value is refused before policy.
            var changed = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            let tamperedNutrients = try F.replacing(input, .carbohydrates, with: .unknown(.notDeclared)).candidates[0].candidate.nutrients
            FoodConfirmationReducer.reduce(state: &changed, action: .applyCorrection(try FoodCorrection(name: source.name, brand: source.brand,
                variant: nil, identity: source.candidate.identity, itemClass: .food, nutrients: tamperedNutrients,
                reason: LedgerText("Synthetic value change."))))
            XCTAssertThrowsError(try service.save(changed, operationID: LedgerFixtures.operationID(9_252))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource, harness.name)
            }
        }
    }

    func testSaveFailsBeforePolicyWhenAStoredValueUnitBoundOrBasisDiffers() throws {
        let input = try F.input(F.manifest())
        let provenance = input.candidates[0].candidate.nutrients.entries.first { $0.key == .carbohydrates }!.value.provenance
        let tampered: [(String, PopulatedFoodConfirmation)] = [
            ("value", try F.replacing(input, .carbohydrates, with: .measured(ExactNutrientValue(amount: 61, unit: .grams,
                sourceValue: .exact(SourceExactNutrientValue(amount: 61, unit: LedgerText("g"), basis: .per100Grams)), provenance: provenance)))),
            ("source unit", try F.replacing(input, .carbohydrates, with: .measured(ExactNutrientValue(amount: 60.1, unit: .grams,
                sourceValue: .exact(SourceExactNutrientValue(amount: 60.1, unit: LedgerText("公克"), basis: .per100Grams)),
                provenance: [NutrientProvenance(sourceKind: .userVerifiedPanel, sourceID: provenance[0].sourceID,
                    sourceReleaseID: provenance[0].sourceReleaseID, evidenceID: provenance[0].evidenceID, capturedAt: provenance[0].capturedAt,
                    manifestReference: provenance[0].manifestReference, transforms: [NutrientTransform(transformID: LedgerText("unit"), transformVersion: LedgerText("v1"))])])))),
            ("bound to exact", try F.replacing(input, .fatTotal, with: .measured(ExactNutrientValue(amount: 0.5, unit: .grams,
                sourceValue: .exact(SourceExactNutrientValue(amount: 0.5, unit: LedgerText("g"), basis: .per100Grams)), provenance: provenance)))),
            ("basis", try F.replacing(input, .carbohydrates, with: .measured(ExactNutrientValue(amount: 60.1, unit: .grams,
                sourceValue: .exact(SourceExactNutrientValue(amount: 60.1, unit: LedgerText("g"), basis: .per100Millilitres)), provenance: provenance)))),
            ("unknown made zero", try F.replacing(input, .sugar, with: .measured(ExactNutrientValue(amount: 0, unit: .grams,
                sourceValue: .exact(SourceExactNutrientValue(amount: 0, unit: LedgerText("g"), basis: .per100Grams)), provenance: provenance))))
        ]
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            for (index, (name, changed)) in tampered.enumerated() {
                XCTAssertThrowsError(try F.service(harness).save(F.state(changed), operationID: LedgerFixtures.operationID(9_300 + index)), name) {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource, "\(harness.name) \(name)")
                }
            }
            XCTAssertEqual(try harness.reader.counts().operations, 0, harness.name)
        }
    }

    func testAlteredManifestBytesFailAtSave() throws {
        let input = try F.input(F.manifest())
        guard case let .text(payload) = input.evidence[0].originalPayload else { return XCTFail() }
        let altered = try CaptureEvidence(evidenceID: input.evidence[0].evidenceID, kind: .labelText, capturedAt: input.evidence[0].capturedAt,
            locale: input.evidence[0].locale, captureMethod: input.evidence[0].captureMethod, captureMethodVersion: input.evidence[0].captureMethodVersion,
            originalPayload: .text(LedgerText(payload.value.replacingOccurrences(of: "60.1", with: "61.0"))), byteHash: input.evidence[0].byteHash)
        let changed = try PopulatedFoodConfirmation(evidence: [altered], sourceReleases: input.sourceReleases, candidates: input.candidates,
            expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            XCTAssertThrowsError(try F.service(harness).save(F.state(changed), operationID: LedgerFixtures.operationID(9_350))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource, harness.name)
            }
        }
    }

    // MARK: 46. Conversion verification (application half)

    func test46ConversionVerificationComparesStoredTextAndLedgerAmountOnly() throws {
        func verifies(_ manifest: PastedLabelManifest, mutate: ((PopulatedFoodConfirmation) throws -> PopulatedFoodConfirmation)? = nil) throws -> Bool {
            // Build with a permissive checker, so the records exist, then verify with the golden one.
            struct Permissive: PastedLabelConversionChecking { func storedTextMatches(_: PastedLabelManifest.Conversion) -> Bool { true } }
            // A manifest the single derivation refuses cannot yield records at all: fail closed.
            guard var input = try? PastedLabelSource.confirmation(manifest: manifest, evidenceID: LedgerFixtures.id(9_100, EvidenceTag.self),
                capturedAt: LedgerFixtures.date, locale: LedgerText("zh_TW"), encoder: LedgerFixtures.encoder,
                digester: LedgerFixtures.digester, conversions: Permissive()) else { return false }
            if let mutate { input = try mutate(input) }
            return PanelSourceAdmission.verify(input, candidate: input.candidates[0], encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester,
                                               conversions: GoldenPastedLabelConversions())
        }
        func with(_ conversion: PastedLabelManifest.Conversion, stored: String? = nil, intermediate: String? = nil) -> PastedLabelManifest.Conversion {
            .init(nutrient: conversion.nutrient, rule: conversion.rule, ruleVersion: conversion.ruleVersion, sourceHeaderID: conversion.sourceHeaderID,
                  sourceRowID: conversion.sourceRowID, operandText: conversion.operandText, operandUnit: conversion.operandUnit,
                  factorText: conversion.factorText, intermediateText: intermediate ?? conversion.intermediateText,
                  storedText: stored ?? conversion.storedText, comparator: conversion.comparator, rounding: conversion.rounding)
        }
        XCTAssertTrue(try verifies(F.manifest()))
        XCTAssertTrue(try verifies(F.manifest(conversions: [with(F.kcal, intermediate: "370.458890"), F.sodium])), "Intermediate alone never invalidates")
        XCTAssertFalse(try verifies(F.manifest(conversions: [with(F.kcal, stored: "370.4"), F.sodium])), "stored_text differs from the recomputation")
        // The ledger amount must be Double(stored_text) exactly.
        XCTAssertFalse(try verifies(F.manifest()) { input in
            let energy = input.candidates[0].candidate.nutrients.entries[0].value
            guard case let .measured(value) = energy else { throw FoodLedgerValidationError.invalidUnit }
            return try F.replacing(input, .energyConsumed, with: .measured(ExactNutrientValue(amount: 370.45, unit: .kilocalories,
                sourceValue: value.sourceValue, provenance: value.provenance)))
        })
        // A conversion recorded where the printed counterpart exists (printed always wins).
        let printedKcal = try F.candidate(cells: [F.cell("熱量", "energy_kcal", "h2", "370大卡", "370", "大卡", canonical: "kcal")])
        XCTAssertFalse(try verifies(F.manifest(candidate: printedKcal)))
        XCTAssertTrue(try verifies(F.manifest(candidate: printedKcal, conversions: [F.sodium])))
        // A comparator that does not match the printed cell, or a source cell from the other column.
        XCTAssertFalse(try verifies(F.manifest(conversions: [F.kcal, .init(nutrient: "sodium", rule: "salt_to_sodium_v1",
            ruleVersion: "pasted-label-conversions-v1", sourceHeaderID: "h2", sourceRowID: "鹽", operandText: "0.6", operandUnit: "g_salt",
            factorText: "2.5", intermediateText: "240.000000", storedText: "240.0", comparator: "<", rounding: "outward")])))
        XCTAssertFalse(try verifies(F.manifest(conversions: [F.kcal, .init(nutrient: "sodium", rule: "salt_to_sodium_v1",
            ruleVersion: "pasted-label-conversions-v1", sourceHeaderID: "h1", sourceRowID: "鹽", operandText: "0.2", operandUnit: "g_salt",
            factorText: "2.5", intermediateText: "80.000000", storedText: "80.0")])))
        // A bound converts as a bound, outward, and stays a bound in the ledger.
        let boundSalt = try F.candidate(cells: [F.cell("鹽", "salt", "h2", "<0.01公克", "0.01", "公克", canonical: "g", comparator: "<")],
                                        replacing: ["h2:salt"])
        let boundRecord = PastedLabelManifest.Conversion(nutrient: "sodium", rule: "salt_to_sodium_v1", ruleVersion: "pasted-label-conversions-v1",
            sourceHeaderID: "h2", sourceRowID: "鹽", operandText: "0.01", operandUnit: "g_salt", factorText: "2.5",
            intermediateText: "4.000000", storedText: "4.0", comparator: "<", rounding: "outward")
        XCTAssertTrue(try verifies(F.manifest(candidate: boundSalt, conversions: [F.kcal, boundRecord])))
        let bound = try F.input(F.manifest(candidate: boundSalt, conversions: [F.kcal, boundRecord]))
        guard case let .bounded(sodium) = bound.candidates[0].candidate.nutrients.entries.first(where: { $0.key == .sodium })?.value else {
            return XCTFail("sodium bound")
        }
        XCTAssertEqual(sodium.upper, 4)
        XCTAssertNil(sodium.lower)
        XCTAssertFalse(sodium.upperClosed)
    }

    // MARK: 32. Source admission

    func test32AdmittedListIsAppendOnlyAndKeyedBySourceID() {
        XCTAssertEqual(PanelSourceAdmission.admittedSourceIDs, ["pasted-nutrition-label"])
    }

    func test32PanelValueFromAnyOtherSourceIsRejectedAtSave() throws {
        let other = try ExternalIdentifier("physical_package")
        let release = try LedgerFixtures.packageSourceRelease()
        let evidenceID = try LedgerFixtures.id(9_400, EvidenceTag.self)
        let evidence = try CaptureEvidence(evidenceID: evidenceID, kind: .synthetic, capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic_fixture"), captureMethodVersion: LedgerText("v1"), originalPayload: .text(LedgerText("panel")))
        let identity = try LedgerFixtures.identity()
        func input(_ provenance: NutrientProvenance) throws -> PopulatedFoodConfirmation {
            let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
                guard key == .protein else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
                return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(amount: 10, unit: .grams,
                    sourceValue: .exact(SourceExactNutrientValue(amount: 10, unit: LedgerText("g"), basis: .per100Grams)), provenance: [provenance])))
            })
            return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [PopulatedFoodCandidate(
                candidate: ProviderNeutralCandidate(sourceReleaseID: release.sourceReleaseID, recordID: ExternalIdentifier("row"), identity: identity,
                    edibleQuantity: .known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil), nutrients: nutrients,
                    evidenceIDs: [evidenceID]), name: LedgerText("Panel"), itemClass: .food)],
                expectedIdentity: identity, expectedEdibleQuantity: .known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil))
        }
        let cases: [(String, NutrientProvenance)] = [
            ("panel, other source", NutrientProvenance(sourceKind: .userVerifiedPanel, sourceID: other, sourceReleaseID: release.sourceReleaseID, evidenceID: evidenceID)),
            ("panel claiming the pasted source on another release", NutrientProvenance(sourceKind: .userVerifiedPanel,
                sourceID: try ExternalIdentifier("pasted-nutrition-label"), sourceReleaseID: release.sourceReleaseID, evidenceID: evidenceID))
        ]
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            for (index, (name, provenance)) in cases.enumerated() {
                var state = FoodConfirmationState(input: try input(provenance))
                FoodConfirmationReducer.reduce(state: &state, action: .accept)
                XCTAssertThrowsError(try F.service(harness).save(state, operationID: LedgerFixtures.operationID(9_410 + index)), name) {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource, "\(harness.name) \(name)")
                }
            }
            // A manual declaration that claims no admitted source is untouched by admission.
            var control = FoodConfirmationState(input: try input(NutrientProvenance(sourceKind: .manualDeclaration, sourceID: other,
                sourceReleaseID: release.sourceReleaseID, evidenceID: evidenceID)))
            FoodConfirmationReducer.reduce(state: &control, action: .setQuantity(100, .grams))
            FoodConfirmationReducer.reduce(state: &control, action: .accept)
            XCTAssertNoThrow(try F.service(harness).save(control, operationID: LedgerFixtures.operationID(9_419)), harness.name)
        }
    }

    func test32ManualDeclarationsClaimingThePastedReleaseMustCiteTheirCorrectionRecord() throws {
        let input = try F.input(F.manifest())
        let protein = input.candidates[0].candidate.nutrients.entries.first { $0.key == .protein }!.value
        guard case let .measured(value) = protein else { return XCTFail() }
        let original = value.provenance[0]
        func declared(sourceID: String = "pasted-nutrition-label", reference: String?) throws -> PopulatedFoodConfirmation {
            try F.replacing(input, .protein, with: .measured(ExactNutrientValue(amount: value.amount, unit: value.unit, sourceValue: value.sourceValue,
                provenance: [NutrientProvenance(sourceKind: .manualDeclaration, sourceID: ExternalIdentifier(sourceID),
                    sourceReleaseID: original.sourceReleaseID, evidenceID: original.evidenceID, capturedAt: original.capturedAt,
                    manifestReference: try reference.map { try LedgerText($0) })])))
        }
        let hash = try XCTUnwrap(input.evidence[0].byteHash).value
        let cases: [(String, PopulatedFoodConfirmation)] = [
            ("another sourceID on the pasted release", try declared(sourceID: "user", reference: "manifest-sha256=\(hash);correction=0")),
            ("no correction record cited", try declared(reference: nil)),
            ("a printed cell cited instead", try declared(reference: "manifest-sha256=\(hash);header=h2;row=蛋白質;literal=5.2公克")),
            ("another correction cited", try declared(reference: "manifest-sha256=\(hash);correction=1")),
            ("a correction that does not exist", try declared(reference: "manifest-sha256=\(hash);correction=7"))
        ]
        for (name, changed) in cases {
            XCTAssertFalse(PanelSourceAdmission.verify(changed, candidate: changed.candidates[0], encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester,
                                                       conversions: GoldenPastedLabelConversions()), name)
        }
        // A correction whose recognised value is not the printed cell is not a correction.
        let forged = PastedLabelManifest.Correction(kind: .corrected, nutrient: "protein", rowID: "蛋白質", headerID: "h2",
            recognised: .init(printedText: "5.0公克", decimalText: "5.0", unit: "公克", comparator: "="),
            corrected: .init(decimalText: "5.4", unit: "g", comparator: "="), at: LedgerFixtures.date)
        XCTAssertThrowsError(try F.input(F.manifest(corrections: [forged])))
        // An entered value over a printed row is not an entry.
        let entered = PastedLabelManifest.Correction(kind: .entered, nutrient: "carbohydrate", rowID: nil, headerID: "h2", recognised: nil,
            corrected: .init(decimalText: "1", unit: "g", comparator: "="), at: LedgerFixtures.date)
        XCTAssertThrowsError(try F.input(F.manifest(corrections: [entered])))
    }

    func testUnansweredFortificationLeavesTheExistingRequirementAndAPipelineMustBeAdmitted() throws {
        let unanswered = try F.input(F.manifest(answer: .unanswered))
        XCTAssertEqual(unanswered.candidates[0].candidate.identity.fortification, .unknown)
        XCTAssertEqual(unanswered.candidates[0].itemClass, .food)
        let fortified = try F.input(F.manifest(answer: .yes))
        XCTAssertEqual(fortified.candidates[0].itemClass, .fortifiedFood)
        XCTAssertThrowsError(try F.input(F.manifest(parserVersion: "nutrition-label-text-parser-v4")), "Not an admitted pipeline")
        XCTAssertNoThrow(try F.input(F.manifest(parserVersion: "nutrition-label-text-parser-v3")), "Parser v3 is admitted (reader v3 section 5.2)")
    }

    // MARK: 17 and 30. Contract version and precedence

    func test17And30ContractSevenIsCheckedFirst() throws {
        let input = try F.input(F.manifest())
        var records = try LedgerFixtures.baseMutation()
        XCTAssertLessThanOrEqual(CanonicalFoodProjection.minimumContractVersion(for: records), 6)
        let favourites = FavouriteMutation(favourites: [FavouriteEntry(favouriteID: try LedgerFixtures.id(1, FavouriteTag.self), createdAt: LedgerFixtures.date)])
        let reference = try CaptureEvidence(evidenceID: LedgerFixtures.id(9_500, EvidenceTag.self), kind: .referenceDefinition,
            capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB"), captureMethod: LedgerText("reference"),
            captureMethodVersion: LedgerText("v1"), originalPayload: .text(LedgerText("water")))
        records = LedgerMutation(evidence: records.evidence + [reference], assertions: records.assertions, products: records.products,
            productVersions: records.productVersions, libraryEntries: records.libraryEntries, libraryEntryVersions: records.libraryEntryVersions,
            resolutions: records.resolutions, resolutionVersions: records.resolutionVersions, logItems: records.logItems,
            logItemVersions: records.logItemVersions, quantityConversions: records.quantityConversions, plates: records.plates,
            plateWeightVersions: records.plateWeightVersions, candidateDecisions: records.candidateDecisions, conflicts: records.conflicts,
            sourceReleases: records.sourceReleases, sourceInstallations: records.sourceInstallations)
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: records, favourites: favourites), 6, "Without pasted evidence")
        let pasted = LedgerMutation(evidence: records.evidence + input.evidence, sourceReleases: records.sourceReleases + input.sourceReleases)
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: pasted, favourites: favourites), 7, "With favourites and reference data")
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: LedgerMutation(evidence: input.evidence)), 7)
        XCTAssertEqual(CanonicalFoodProjection.exportContractVersion(for: records, favourites: favourites), 6)
        XCTAssertEqual(CanonicalFoodProjection.exportContractVersion(for: LedgerMutation()), 6, "The export floor is unchanged")
        XCTAssertThrowsError(try CanonicalFoodProjection(records: pasted, favourites: favourites, foodContractVersion: 6)) {
            XCTAssertEqual($0 as? FoodArchiveError, .unsupportedFoodContract(6))
        }
    }

    // MARK: 18 and 38. Contract-7 archive round trip and reopen after restore

    func test18And38ContractSevenArchiveRoundTripsAndReopensAfterRestore() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let saved = try F.service(harness).save(F.state(F.input(F.manifest())), operationID: LedgerFixtures.operationID(9_600))
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let bundle = try FoodArchiveGenerator().generate(state: archive.archiveState(), ledgerID: LedgerText("pasted"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            let verified = try FoodArchiveVerifier().verify(bundle)
            XCTAssertEqual(verified.manifest.foodContractVersion, 7, harness.name)
            XCTAssertEqual(verified.manifest.migrationIdentifiers.map(\.value).last, "food-ledger-v7", harness.name)
            for destination in try LedgerFixtures.harnesses() {
                defer { destination.cleanup() }
                let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())
                _ = try importer.apply(importer.dryRun(bundle))
                // Byte for byte: the restored store exports exactly the archive it was restored from.
                let again = try FoodArchiveGenerator().generate(state: live.archiveState(), ledgerID: LedgerText("pasted"),
                    createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
                XCTAssertEqual(again, bundle, "\(harness.name)->\(destination.name)")
                // Reopen after restore verifies against the stored manifest (no parser is reachable here).
                let reopened = try XCTUnwrap(F.service(destination).reopen(logItemID: saved.logItem.logItemID))
                XCTAssertEqual(reopened.input.candidates[0].candidate.nutrients, saved.resolutionVersion.nutrients)
            }
        }
    }

    func test38ReopenFailsWithIntegrityFailureForAPipelineThatIsNotAdmitted() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let saved = try F.service(harness).save(F.state(F.input(F.manifest())), operationID: LedgerFixtures.operationID(9_700))
            for (from, to) in [("nutrition-label-text-parser-v2", "nutrition-label-text-parser-v9"), ("60.1公克", "61.0公克")] {
                let rewritten = try Self.rewriteStored(saved, replacing: from, with: to)
                let service = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: StoredPastedReader(saved: rewritten),
                    clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester,
                    pastedLabelConversions: GoldenPastedLabelConversions())
                XCTAssertThrowsError(try service.reopen(logItemID: saved.logItem.logItemID), "\(harness.name) \(to)") {
                    guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\($0)") }
                }
            }
            // Control: the untouched record reopens through the same reader.
            let control = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: StoredPastedReader(saved: saved),
                clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester,
                pastedLabelConversions: GoldenPastedLabelConversions())
            XCTAssertNotNil(try control.reopen(logItemID: saved.logItem.logItemID), harness.name)
        }
    }

    /// Rewrites the retained manifest and rebinds every digest-derived identifier, so only the
    /// semantic check can catch the change.
    static func rewriteStored(_ saved: StoredFoodConfirmation, replacing: String, with replacement: String) throws -> StoredFoodConfirmation {
        guard case let .text(payload) = saved.evidence[0].originalPayload else { throw FoodLedgerValidationError.invalidDigest }
        let oldHash = try XCTUnwrap(saved.evidence[0].byteHash).value
        let newText = payload.value.replacingOccurrences(of: replacing, with: replacement)
        XCTAssertNotEqual(newText, payload.value)
        let newHash = try SHA256Digester().sha256(Data(newText.utf8)).value
        var json = String(decoding: try LedgerFixtures.encoder.encode(saved), as: UTF8.self)
        json = json.replacingOccurrences(of: replacing, with: replacement).replacingOccurrences(of: oldHash, with: newHash)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(StoredFoodConfirmation.self, from: Data(json.utf8))
    }

    // MARK: 31. Migration v6 to v7, and contract-6-or-lower re-export

    func test31MigrationFromAPopulatedV6StoreChangesOnlyLedgerMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pasted-v7-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        do {
            let store = try FoodLedgerGRDBStore.temporary(directory: directory)
            try Self.populate(TestHarness(name: "grdb", committer: store, reader: store, cleanup: {}))
        }
        // Reconstruct schema 6 exactly as a v6 binary left it: metadata and migration log only.
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v7_pasted_label'")
            try db.execute(sql: "UPDATE ledger_metadata SET value = 'food-ledger-v6' WHERE key = 'schema_identity'")
            try db.execute(sql: "PRAGMA user_version = 6")
        }
        let before = try Self.tableHashes(queue)
        let schemaBefore = try Self.schema(queue)
        XCTAssertGreaterThan(before.count, 10)
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM favourite") }, 1)
        try queue.close()

        let migrated = try FoodLedgerGRDBStore.temporary(directory: directory)
        try migrated.verifyIntegrity()
        let after = try Self.tableHashes(DatabaseQueue(path: database.path))
        let changed = Set(before.keys.filter { before[$0] != after[$0] })
        XCTAssertEqual(changed, ["ledger_metadata"], "Only ledger_metadata may change")
        XCTAssertEqual(Set(after.keys), Set(before.keys), "No table is added or removed")
        let check = try DatabaseQueue(path: database.path)
        XCTAssertEqual(try Self.schema(check), schemaBefore, "No table, index or trigger definition changes")
        try check.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version"), 7)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT value FROM ledger_metadata WHERE key = 'schema_identity'"), "food-ledger-v7")
            // GRDB's own migration log records the one metadata migration.
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid").last, "v7_pasted_label")
        }
    }

    func test31ContractSixOrLowerArchivesReexportByteIdenticalFromAV7Binary() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            try Self.populate(harness)
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let bundle = try FoodArchiveGenerator().generate(state: archive.archiveState(), ledgerID: LedgerText("v6"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            // Golden: the bytes the contract-6 binary (origin/main before this change) generates
            // for this same state. Shared by both stores.
            XCTAssertEqual(try LedgerFixtures.digester.sha256(bundle.manifest).value, Self.contractSixManifestGoldenSHA256, harness.name)
            XCTAssertEqual(try LedgerFixtures.digester.sha256(bundle.snapshot).value, Self.contractSixSnapshotGoldenSHA256, harness.name)
            XCTAssertEqual(try LedgerFixtures.digester.sha256(bundle.operations).value, Self.contractSixOperationsGoldenSHA256, harness.name)
            XCTAssertEqual(try FoodArchiveVerifier().verify(bundle).manifest.foodContractVersion, 6, harness.name)
            for destination in try LedgerFixtures.harnesses() {
                defer { destination.cleanup() }
                let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())
                _ = try importer.apply(importer.dryRun(bundle))
                let again = try FoodArchiveGenerator().generate(state: live.archiveState(), ledgerID: LedgerText("v6"),
                    createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
                XCTAssertEqual(again, bundle, "\(harness.name)->\(destination.name)")
            }
        }
        // Committed archives at contracts 1 and 2 still verify, stage byte for byte at their own
        // contract, and decode and re-encode unchanged.
        for name in ["legacy-v1", "legacy-v2"] {
            let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
            let bundle = FoodArchiveBundle(manifest: try Data(contentsOf: directory.appendingPathComponent("manifest.json")),
                snapshot: try Data(contentsOf: directory.appendingPathComponent("snapshot.json")),
                operations: try Data(contentsOf: directory.appendingPathComponent("operations.ndjson")))
            let verified = try FoodArchiveVerifier().verify(bundle)
            XCTAssertLessThanOrEqual(verified.manifest.foodContractVersion, 2, name)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
            XCTAssertEqual(try LedgerFixtures.encoder.encode(decoder.decode(CanonicalFoodDocument.self, from: bundle.snapshot)), bundle.snapshot, name)
            for destination in try LedgerFixtures.harnesses() {
                defer { destination.cleanup() }
                let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                XCTAssertNoThrow(try FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging()).dryRun(bundle), name)
            }
        }
    }

    /// A populated contract-6 ledger: a base product, an exact log, plain water and a favourite,
    /// with deterministic identifiers and clock. Uses only APIs that existed at contract 6.
    static func populate(_ harness: TestHarness) throws {
        let context = try QuickAddContext(harness)
        _ = try context.ledger.commit(LedgerFixtures.baseMutation(), type: .createProduct, operationID: LedgerFixtures.operationID(9_800))
        let logged = try context.logExact(9_801, aliases: ["synthetic crackers"])
        try context.logWater(250)
        let favourite = try context.favourites.saveFavourite(logItemVersionID: logged.logItemVersion.logItemVersionID)
        try context.favourites.arrange([.favourite(favourite)])
    }

    private static func tableHashes(_ queue: DatabaseQueue) throws -> [String: String] {
        try queue.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations' ORDER BY name")
            var result: [String: String] = [:]
            for table in tables {
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\"").map { row in
                    row.columnNames.map { "\($0)=\(row[$0] as DatabaseValue)" }.joined(separator: "|")
                }.sorted()
                result[table] = try LedgerFixtures.digester.sha256(Data(rows.joined(separator: "\n").utf8)).value
            }
            return result
        }
    }

    private static func schema(_ queue: DatabaseQueue) throws -> [String] {
        try queue.read { db in
            try String.fetchAll(db, sql: "SELECT type || ':' || name || ':' || COALESCE(sql, '') FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name")
        }
    }

    static let manifestGoldenSHA256 = "2ade0208b2cf3937ac25b677ea00d0579e2c6bd41913f4658d883f2239f7e819"
    /// Generated by `origin/main` at e466d216 (contract 6, schema 6) for `populate(_:)` with the
    /// same fixture records, on both stores; see the PR's re-export evidence.
    static let contractSixManifestGoldenSHA256 = "ac0b555bc644adf3a9a1a770ef573a91e6bb749bf695bffd25e41ad1cabf4eba"
    static let contractSixSnapshotGoldenSHA256 = "27bd159349c0d8c2397ddbdc03308ce20aae2b4621c39d85daa6685ce93efe2b"
    static let contractSixOperationsGoldenSHA256 = "1909918a52906807b70f2e467ab9756e1967f3f920b32920557329677d90703e"
}

private struct StoredPastedReader: FoodConfirmationReading {
    let saved: StoredFoodConfirmation
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { saved.sourceReleases.first { $0.sourceReleaseID == id } }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { logItemID == saved.logItem.logItemID ? saved : nil }
    func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? {
        logItemVersionID == saved.logItemVersion.logItemVersionID ? saved : nil
    }
    func evidence(id: EvidenceID) throws -> CaptureEvidence? { saved.evidence.first { $0.evidenceID == id } }
}
