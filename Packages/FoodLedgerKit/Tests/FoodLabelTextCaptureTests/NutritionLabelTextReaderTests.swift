import Foundation
@testable import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
@testable import NutritionLabelParsing
import XCTest

/// Pasted nutrition label v1, PR 3: the `FoodLabelTextCapture` adapter behind the
/// `LabelTextReading` and `PastedLabelConversionChecking` ports, on the frozen parity cases and
/// on synthetic texts (`docs/pasted-nutrition-label-v1.md` tests 10, 26, 27 and 28).
final class NutritionLabelTextReaderTests: XCTestCase {
    private struct Clock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } }
    private let reader = PastedLabelReader(reader: NutritionLabelTextReader(), digester: SHA256Digester())

    private func builder() -> PastedLabelConfirmation {
        PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: Clock(),
                                encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester(),
                                conversions: NutritionLabelConversionChecker())
    }

    private struct NotUsable: Error, CustomStringConvertible { let description: String }

    /// The usable review of `text`. A decline is a test failure, never a skip, so a flag that
    /// regresses into a decline fails here.
    private func review(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> PastedLabelReview {
        let outcome = reader.read(text)
        guard case let .usable(review) = outcome else {
            XCTFail("Expected a usable reading, got a decline: \(outcome.declineCodes)", file: file, line: line)
            throw NotUsable(description: "declined: \(outcome.declineCodes)")
        }
        return review
    }

    // MARK: 26. Launch scope after a faithful gate

    func test26LaunchScopeDeclinesUKAfterTheGateWhileUKGateParityStillPasses() throws {
        var ukGated = 0
        for item in try FrozenParityCases.textCases() where item.declaredFormat == "uk_nutrition_declaration" {
            let outcome = reader.read(item.text)
            guard case let .declined(codes, reading) = outcome else { return XCTFail("\(item.id) must not reach Confirm") }
            let reading_ = try XCTUnwrap(reading, item.id)
            if reading_.candidate.declined { continue }
            ukGated += 1
            XCTAssertTrue(codes.contains("layout_not_supported"), "\(item.id): \(codes)")
            XCTAssertEqual(reading_.format, "uk_nutrition_declaration", item.id)
            XCTAssertEqual(reading_.gate?.format, "uk_nutrition_declaration", "\(item.id): the gate still runs under UK")
            // Gate parity: the gate's own output on the UK vector is gate v2's frozen report.
            let parsed = NutritionLabelTextParser().parse(item.text, inputSHA256: reading_.textSHA256)
            let report = LabelDeclineGate.apply(parsed, format: .uk).report
            let expected = try XCTUnwrap((item.expected["gate"] as? [String: Any])?["report"] as? [String: Any], item.id)
            XCTAssertEqual(report.declines.map(\.rawValue), expected["declines"] as? [String], item.id)
            XCTAssertEqual(report.blocks.map(\.rawValue), expected["blocks"] as? [String], item.id)
            XCTAssertEqual(report.details, expected["details"] as? [String], item.id)
            XCTAssertEqual(report.skipped?.rawValue, expected["skipped"] as? String, item.id)
        }
        XCTAssertGreaterThan(ukGated, 0)
        // Synthetic UK (per 100 g, and per serving only) and US layouts.
        XCTAssertEqual(reader.read(SyntheticLabelTexts.ukDeclaration).declineCodes, ["layout_not_supported"])
        let us = "Nutrition Facts\nServing size 55g\nPer serving\nEnergy 230kcal\nFat 8g\nSaturated fat 1g\nCarbohydrate 37g\nSugars 12g\nProtein 3g\nSodium 160mg\n"
        guard case let .declined(codes, reading) = reader.read(us) else { return XCTFail("US must decline") }
        XCTAssertEqual(codes, ["layout_not_supported"]); XCTAssertEqual(reading?.format, "us_nutrition_facts"); XCTAssertNil(reading?.gate)
    }

    // MARK: Frozen parity cases end to end

    /// Every frozen text case through the reader, the launch scope and the flag mapping. Taiwan
    /// cases that are usable all build a verified Confirm input (test 10 on real parser output).
    func testFrozenParityCasesThroughTheProductReader() throws {
        var tally: [String: Int] = [:]
        var declinesByCode: [String: Int] = [:]
        var flagsByCode: [String: Int] = [:]
        for item in try FrozenParityCases.textCases() {
            let format = item.declaredFormat == "taiwan_nutrition_labelling" ? "taiwan" : "uk"
            let outcome = reader.read(item.text)
            if format == "taiwan" {
                // No false declines and no false readings on Taiwan: the product declines exactly
                // the texts the frozen parser declines.
                XCTAssertEqual(outcome.declineCodes.isEmpty, !item.parserDeclined, item.id)
            }
            switch outcome {
            case let .declined(codes, reading):
                tally["\(format) \(item.split) declined", default: 0] += 1
                for code in codes { declinesByCode[code, default: 0] += 1 }
                if let reading, !reading.candidate.declined, item.declaredFormat == "taiwan_nutrition_labelling" {
                    XCTAssertFalse(codes.contains("layout_not_supported"), item.id)
                }
            case let .usable(review):
                XCTAssertEqual(item.declaredFormat, "taiwan_nutrition_labelling", "\(item.id): only Taiwan reaches Confirm")
                XCTAssertEqual(review.reading.format, item.declaredFormat, "\(item.id): inference agrees with the declared format")
                tally["\(format) \(item.split) \(review.flags.isEmpty ? "usable" : "usable with flags")", default: 0] += 1
                for flag in review.flags { flagsByCode[flag.code, default: 0] += 1 }
                let input = try builder().confirmation(review, details: .init(name: "Synthetic \(item.id)", fortification: .no),
                                                       corrections: [], locale: LedgerText("zh_TW"))
                let candidate = input.candidates[0]
                XCTAssertTrue(PastedLabelSource.verify(input, candidate: candidate, encoder: FoundationCanonicalJSONEncoder(),
                                                       digester: SHA256Digester(), conversions: NutritionLabelConversionChecker()), item.id)
                for entry in candidate.candidate.nutrients.entries {
                    for provenance in entry.value.provenance {
                        XCTAssertTrue(provenance.manifestReference?.value.contains(";header=\(review.storedHeaderID);row=") == true, item.id)
                    }
                }
            }
        }
        print("PASTED-LABEL-FROZEN-TALLY \(tally.sorted { $0.key < $1.key })")
        print("PASTED-LABEL-FROZEN-DECLINES \(declinesByCode.sorted { $0.key < $1.key })")
        print("PASTED-LABEL-FROZEN-FLAGS \(flagsByCode.sorted { $0.key < $1.key })")
        XCTAssertEqual(tally, Self.frozenTally)
        XCTAssertEqual(declinesByCode, Self.frozenDeclines)
        XCTAssertEqual(flagsByCode, Self.frozenFlags)
    }

    /// Pinned on the frozen vectors (314 text cases: 212 Taiwan, 102 UK). The untouched Taiwan
    /// split matches the evaluation (92 tables, 15 required declines). Every UK case is declined
    /// by the launch scope; one also carries `basis_state_not_supported` ("as prepared").
    static let frozenTally: [String: Int] = [
        "taiwan development usable": 89, "taiwan development declined": 16,
        "taiwan untouched usable": 92, "taiwan untouched declined": 15,
        "uk development declined": 102
    ]
    static let frozenDeclines: [String: Int] = [
        "energy_without_unit": 18, "unsupported_language": 13, "layout_not_supported": 102, "basis_state_not_supported": 1
    ]
    static let frozenFlags: [String: Int] = [:]

    // MARK: 27. Every code maps to copy

    /// Parser decline codes, read from the parser sources (v2, which the reader no longer runs but
    /// whose codes v3 keeps, v3 and its layout precedence) so a new code cannot go unmapped.
    static func parserDeclineCodes() throws -> Set<String> {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NutritionLabelParsing")
        var text = ""
        for file in ["NutritionLabelTextParser.swift", "NutritionLabelTextParserV3.swift", "LabelLayout.swift"] {
            text += try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8) + "\n"
        }
        let literal = try NSRegularExpression(pattern: #""([a-z]+(?:_[a-z]+)+)""#)
        var codes: Set<String> = []
        for line in text.split(separator: "\n") where line.contains("decline(") || line.contains("declineReasons.append")
            || line.contains("reasons: [") || line.contains("Decline = [") || line.contains("ambiguousCode = ") {
            let line = String(line)
            for match in literal.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                codes.insert(String(line[Range(match.range(at: 1), in: line)!]))
            }
        }
        return codes
    }

    func test27EveryParserGateAndRouteCodeMapsToCopyAndIsClassifiedOnce() throws {
        let parser = try Self.parserDeclineCodes()
        XCTAssertEqual(parser, ["unsupported_language", "multiple_panels", "values_without_row", "no_table", "no_basis_header",
                                "duplicate_basis", "energy_without_unit", "value_without_unit", "unrecognised_unit", "count_mismatch",
                                "layout_ambiguous"],
                       "A new parser code needs its own mapping and copy")
        let gate = Set(LabelGateReason.allCases.map(\.rawValue))
        var skipped: Set<String> = []
        for skip in [LabelGateSkip.failedCandidate, .tablesUnavailable, .alreadyDeclined] {
            let report = LabelGateReport(gateVersion: LabelDeclineGate.version, labelFormat: .taiwan, declines: [], blocks: [], details: [], skipped: skip)
            skipped.formUnion(report.hardDeclineCodes)
            XCTAssertFalse(report.isUsable)
        }
        XCTAssertEqual(skipped, ["unreadable_table"], "failed_candidate counts as unreadable")
        let inference = Set([LabelFormatInference.Outcome.taiwan, .uk, .usNutritionFacts, .ambiguous].compactMap(\.declineCode))
        let route: Set<String> = ["text_too_long", "layout_not_supported", PastedLabelIdentity.basisStateNotSupported, "no_table", "unreadable_table"]
        let emitted = parser.union(gate).union(skipped).union(inference).union(route)
        XCTAssertEqual(Set(PastedLabelCodes.mapping.keys), emitted, "Every emitted code has its own mapping, and nothing else is mapped")
        let flags = Set(LabelGateReason.allCases.filter { !$0.isHardDecline }.map(\.rawValue))
        XCTAssertEqual(flags, ["required_row_missing", "column_count_mismatch", "required_basis_missing", "required_serving_declaration_missing"])
        let sectionThreeOne: Set<String> = ["not_a_food_nutrition_panel", "unsupported_language", "unsupported_script", "no_table",
            "layout_not_supported", "format_ambiguous", "basis_state_not_supported", "multiple_panels", "no_basis_header", "duplicate_basis",
            "count_mismatch", "values_without_row", "energy_without_unit", "value_without_unit", "unrecognised_unit", "text_too_long", "unreadable_table",
            "layout_ambiguous"]
        for code in emitted {
            let classification = PastedLabelCodes.classify(code)
            XCTAssertEqual(classification.kind == .flag, flags.contains(code), code)
            XCTAssertEqual(classification.kind == .hardDecline, sectionThreeOne.contains(code), code)
            // Reader v3 section 3.0: `layout_ambiguous` is copied as `unreadable_table` (decision 19).
            XCTAssertEqual(classification.copy == .unreadableTable, ["unreadable_table", "layout_ambiguous"].contains(code), "\(code) has its own copy")
        }
        XCTAssertEqual(PastedLabelCodes.classify("gate:required_row_missing").copy, .unreadableTable, "Unmapped codes fall back")
    }

    // MARK: 28. Identity mapping

    func test28AsPreparedOrDrainedDeclinesAndFortificationDecidesTheIdentityRequirement() throws {
        XCTAssertEqual(reader.read(SyntheticLabelTexts.asPrepared).declineCodes, ["basis_state_not_supported"])
        XCTAssertEqual(reader.read(SyntheticLabelTexts.drained).declineCodes, ["basis_state_not_supported"])
        let review = try review(SyntheticLabelTexts.base)
        func requirements(_ answer: PastedLabelIdentity.FortificationAnswer) throws -> [FoodLogRequirement] {
            let input = try builder().confirmation(review, details: .init(name: "Synthetic granola", fortification: answer),
                                                   corrections: [], locale: LedgerText("zh_TW"))
            var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(40, .grams))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            return FoodLogPolicy.requirements(state, now: Date(timeIntervalSince1970: 1_700_000_000), calendar: .current)
        }
        XCTAssertEqual(try requirements(.yes), [])
        XCTAssertEqual(try requirements(.no), [])
        XCTAssertEqual(try requirements(.unanswered), [.sourceIdentityMissing([.fortification])])
    }

    // MARK: Flags, conversions and declines on synthetic text

    func testFlagsAreShownNotDeclinedAndACalculatedValueSatisfiesItsRow() throws {
        let kilojoules = try review(SyntheticLabelTexts.kilojoulesOnly)
        XCTAssertEqual(kilojoules.flags, [], "The kcal row's G3 is satisfied by the calculated value")
        XCTAssertEqual(kilojoules.reading.gate?.flags.map(\.concerns), ["energy_kcal"], "The faithful gate still reports G3")
        XCTAssertEqual(kilojoules.reading.conversions.map(\.storedText), ["419.2"])
        let input = try builder().confirmation(kilojoules, details: .init(name: "Synthetic granola", fortification: .no),
                                               corrections: [], locale: LedgerText("zh_TW"))
        let energy = try XCTUnwrap(input.candidates[0].candidate.nutrients.entries.first { $0.key == .energyConsumed }).value
        XCTAssertTrue(NutrientDerivation.isCalculated(energy))
        XCTAssertTrue(energy.provenance.allSatisfy { $0.transforms.count == 1 })

        XCTAssertEqual(try review(SyntheticLabelTexts.sodiumMissing).flags, [.init(code: "required_row_missing", concerns: "sodium")])
        XCTAssertEqual(try review(SyntheticLabelTexts.packMissing).flags,
                       [.init(code: "required_serving_declaration_missing", concerns: "servings_per_pack")])
        let noSize = try review(SyntheticLabelTexts.perServingNoSize)
        XCTAssertEqual(noSize.flags, [.init(code: "required_serving_declaration_missing", concerns: "serving_size")])
        // Entering the serving size resolves its flag and settles the basis (section 6.3).
        let entry = try builder().correction("serving_size", value: .init(decimalText: "40", unit: "g", comparator: "="), in: noSize)
        let manifest = try builder().manifest(noSize, details: .init(name: "Synthetic granola", fortification: .no), corrections: [entry])
        XCTAssertEqual(manifest.flagsShown, [])
        XCTAssertEqual(try PastedLabelSource.storedBasis(manifest), .perServing(try PositiveQuantity(value: 40, unit: .grams)))

        XCTAssertEqual(try review(SyntheticLabelTexts.energyMismatch).warningCodes, ["energy:per_100g", "energy:per_serving"])
        XCTAssertEqual(try review(SyntheticLabelTexts.base).warningCodes, [], "A pass shows nothing")
        XCTAssertEqual(reader.read(SyntheticLabelTexts.fullwidthDigits).declineCodes, ["unreadable_table"])
        XCTAssertEqual(reader.read(SyntheticLabelTexts.japanese).declineCodes, ["unsupported_language"])
        let supplement = SyntheticLabelTexts.taiwan(header: "　　　　營養補充 每份  每100公克")
        XCTAssertEqual(reader.read(supplement).declineCodes, ["not_a_food_nutrition_panel"])
    }

    /// Reader v3 section 3.9, consistent with v1 decision 6: energy is read in kcal or kJ. With
    /// both printed, on one row or on two (the kJ line continuing the energy row), the kcal cell is
    /// stored and the kJ cell is read but not used: nothing is calculated, never both.
    func testKcalAndKjOnOneRowOrTwoStoreTheKcalAndKeepTheKjReadButNotUsed() throws {
        for (name, energy) in [("one row", ["熱量  167.7 大卡  701.7 kJ  419.2 大卡  1754 kJ"]),
                               ("two rows", ["熱量  167.7 大卡  419.2 大卡", "701.7 kJ  1754 kJ"])] {
            let read = try review(SyntheticLabelTexts.taiwan(energy + SyntheticLabelTexts.rows.dropFirst()))
            let candidate = read.reading.candidate
            XCTAssertFalse(candidate.warnings.contains { $0.hasPrefix("row_not_read") }, name)
            let stored = candidate.cells.filter { $0.headerID == read.storedHeaderID }
            XCTAssertEqual(stored.filter { $0.nutrient == "energy_kcal" }.map(\.decimalText), ["419.2"], name)
            XCTAssertEqual(stored.filter { $0.nutrient == "energy_kj" }.map(\.decimalText), ["1754"], name)
            XCTAssertEqual(read.reading.conversions, [], "\(name): kcal is printed, so nothing is calculated")
            XCTAssertEqual(read.flags, [], name)
            let input = try builder().confirmation(read, details: .init(name: "Synthetic granola", fortification: .no),
                                                   corrections: [], locale: LedgerText("zh_TW"))
            let value = try XCTUnwrap(input.candidates[0].candidate.nutrients.entries.first { $0.key == .energyConsumed }).value
            XCTAssertFalse(NutrientDerivation.isCalculated(value), name)
        }
    }

    // MARK: Mapping across the port

    func testTheCandidateMirrorEncodesTheParserCandidateBytes() throws {
        let encoder = FoundationCanonicalJSONEncoder()
        for text in [SyntheticLabelTexts.base, SyntheticLabelTexts.kilojoulesOnly, SyntheticLabelTexts.perServingNoSize, SyntheticLabelTexts.japanese] {
            let hash = try SHA256Digester().sha256(Data(text.utf8)).value
            let parsed = NutritionLabelTextParserV3().parse(text, inputSHA256: hash) // the parser the reader runs
            let reading = NutritionLabelTextReader().read(text, textSHA256: hash)
            XCTAssertEqual(try encoder.encode(reading.candidate), try encoder.encode(parsed))
            XCTAssertEqual(reading.versions, NutritionLabelTextReader.versions)
            XCTAssertEqual(reading.origin, .pastedText)
        }
        XCTAssertEqual(NutritionLabelTextReader.versions.parser, PastedLabelSource.parserVersion)
        XCTAssertEqual(NutritionLabelTextReader.versions.parser, "nutrition-label-text-parser-v3")
        XCTAssertEqual(NutritionLabelTextReader.versions.gate, PastedLabelSource.gateVersion)
        XCTAssertEqual(NutritionLabelTextReader.versions.arithmetic, PastedLabelSource.arithmeticVersion)
        XCTAssertEqual(NutritionLabelTextReader.versions.conversion, PastedLabelSource.conversionVersion)
    }

    func testTheConversionCheckerIsTheTightenedStoredTextMatches() {
        let checker = NutritionLabelConversionChecker()
        let golden = PastedLabelManifest.Conversion(nutrient: "energy_kcal", rule: "kj_to_kcal_v1", ruleVersion: "pasted-label-conversions-v1",
            sourceHeaderID: "h2", sourceRowID: "熱量", operandText: "1550", operandUnit: "kJ", factorText: "4.184",
            intermediateText: "370.458891", storedText: "370.5")
        func with(_ change: (inout [String: String?]) -> Void) -> PastedLabelManifest.Conversion {
            var fields: [String: String?] = ["nutrient": golden.nutrient, "rule": golden.rule, "stored": golden.storedText,
                                             "intermediate": golden.intermediateText, "comparator": nil, "rounding": nil, "factor": golden.factorText]
            change(&fields)
            return .init(nutrient: fields["nutrient"]!!, rule: fields["rule"]!!, ruleVersion: golden.ruleVersion, sourceHeaderID: "h2",
                         sourceRowID: "熱量", operandText: "1550", operandUnit: "kJ", factorText: fields["factor"]!!,
                         intermediateText: fields["intermediate"]!!, storedText: fields["stored"]!!,
                         comparator: fields["comparator"] ?? nil, rounding: fields["rounding"] ?? nil)
        }
        XCTAssertTrue(checker.storedTextMatches(golden))
        XCTAssertTrue(checker.storedTextMatches(with { $0["intermediate"] = "370.458890" }), "The intermediate is never compared")
        XCTAssertFalse(checker.storedTextMatches(with { $0["stored"] = "370.6" }))
        XCTAssertFalse(checker.storedTextMatches(with { $0["rule"] = "kj_to_kcal_v2" }), "An unknown rule fails closed")
        XCTAssertFalse(checker.storedTextMatches(with { $0["nutrient"] = "sodium" }))
        XCTAssertFalse(checker.storedTextMatches(with { $0["factor"] = "4.2" }))
        XCTAssertFalse(checker.storedTextMatches(with { $0["comparator"] = "=" }), "An exact value carries no comparator")
        XCTAssertFalse(checker.storedTextMatches(with { $0["comparator"] = "~"; $0["rounding"] = "outward" }))
        XCTAssertFalse(checker.storedTextMatches(with { $0["comparator"] = "<" }), "A bound needs outward rounding")
    }
}
