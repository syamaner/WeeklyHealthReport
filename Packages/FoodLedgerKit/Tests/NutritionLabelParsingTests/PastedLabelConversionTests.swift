import Foundation
import Testing
@testable import NutritionLabelParsing

// Contract tests 4 to 7 and 45 (`docs/pasted-nutrition-label-v1.md` sections 3.4, 3.5 and 8.4):
// `pasted-label-conversions-v1`, printed wins, no cross-column or chained conversion, and the
// golden vectors with the canonical JSON bytes of each conversion record. All fixtures are synthetic.

private func canonicalJSON(_ record: PastedLabelConversionRecord) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(record), as: UTF8.self)
}

private struct Golden {
    let rule: PastedLabelConversionRule
    let operand: String
    let comparator: PastedLabelConversionComparator
    let quotient: String
    let intermediate: String
    let stored: String
    let amount: Double
    let json: String
}

// The quotient is pinned as Foundation's own `NSDecimalDivide` result ("at Foundation Decimal
// precision", section 3.5). For non-terminating quotients that is not a correctly rounded
// 38-digit value (Python `decimal` at 38 digits gives 370.45889101338432122370936902485659656
// for 1550 / 4.184; Foundation keeps 37 digits here and 34 for 10 / 4.184). Only `stored_text`
// is ever verified, so this cannot change a stored amount; the pin catches a platform change.
private let goldens: [Golden] = [
    Golden(
        rule: .kjToKcal, operand: "1550", comparator: .equal,
        quotient: "370.4588910133843212237093690248565965", intermediate: "370.458891", stored: "370.5", amount: 370.5,
        json: #"{"factor_text":"4.184","intermediate_text":"370.458891","nutrient":"energy_kcal","operand_text":"1550","operand_unit":"kJ","rule":"kj_to_kcal_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"energy_kj","stored_text":"370.5"}"#
    ),
    Golden(
        rule: .saltToSodium, operand: "0.6", comparator: .equal,
        quotient: "240", intermediate: "240.000000", stored: "240.0", amount: 240.0,
        json: #"{"factor_text":"2.5","intermediate_text":"240.000000","nutrient":"sodium","operand_text":"0.6","operand_unit":"g_salt","rule":"salt_to_sodium_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"salt","stored_text":"240.0"}"#
    ),
    Golden(
        rule: .saltToSodium, operand: "0.03", comparator: .equal,
        quotient: "12", intermediate: "12.000000", stored: "12.0", amount: 12.0,
        json: #"{"factor_text":"2.5","intermediate_text":"12.000000","nutrient":"sodium","operand_text":"0.03","operand_unit":"g_salt","rule":"salt_to_sodium_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"salt","stored_text":"12.0"}"#
    ),
    Golden(
        rule: .saltToSodium, operand: "0", comparator: .equal,
        quotient: "0", intermediate: "0.000000", stored: "0.0", amount: 0.0,
        json: #"{"factor_text":"2.5","intermediate_text":"0.000000","nutrient":"sodium","operand_text":"0","operand_unit":"g_salt","rule":"salt_to_sodium_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"salt","stored_text":"0.0"}"#
    ),
    // Half-even ties at the sixth place: 1.2345625 stays at ...562, 1.2345635 goes to ...564.
    Golden(
        rule: .kjToKcal, operand: "5.1654095", comparator: .equal,
        quotient: "1.2345625", intermediate: "1.234562", stored: "1.2", amount: 1.2,
        json: #"{"factor_text":"4.184","intermediate_text":"1.234562","nutrient":"energy_kcal","operand_text":"5.1654095","operand_unit":"kJ","rule":"kj_to_kcal_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"energy_kj","stored_text":"1.2"}"#
    ),
    Golden(
        rule: .kjToKcal, operand: "5.165413684", comparator: .equal,
        quotient: "1.2345635", intermediate: "1.234564", stored: "1.2", amount: 1.2,
        json: #"{"factor_text":"4.184","intermediate_text":"1.234564","nutrient":"energy_kcal","operand_text":"5.165413684","operand_unit":"kJ","rule":"kj_to_kcal_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"energy_kj","stored_text":"1.2"}"#
    ),
    // Half away from zero at the first place: 0.25 is stored as 0.3, not the half-even 0.2.
    Golden(
        rule: .kjToKcal, operand: "1.046", comparator: .equal,
        quotient: "0.25", intermediate: "0.250000", stored: "0.3", amount: 0.3,
        json: #"{"factor_text":"4.184","intermediate_text":"0.250000","nutrient":"energy_kcal","operand_text":"1.046","operand_unit":"kJ","rule":"kj_to_kcal_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"energy_kj","stored_text":"0.3"}"#
    ),
    Golden(
        rule: .saltToSodium, operand: "0.000625", comparator: .equal,
        quotient: "0.25", intermediate: "0.250000", stored: "0.3", amount: 0.3,
        json: #"{"factor_text":"2.5","intermediate_text":"0.250000","nutrient":"sodium","operand_text":"0.000625","operand_unit":"g_salt","rule":"salt_to_sodium_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"salt","stored_text":"0.3"}"#
    ),
    // Bounds round outward directly from the quotient.
    Golden(
        rule: .saltToSodium, operand: "0.01", comparator: .less,
        quotient: "4", intermediate: "4.000000", stored: "4.0", amount: 4.0,
        json: #"{"comparator":"<","factor_text":"2.5","intermediate_text":"4.000000","nutrient":"sodium","operand_text":"0.01","operand_unit":"g_salt","rounding":"outward","rule":"salt_to_sodium_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"salt","stored_text":"4.0"}"#
    ),
    Golden(
        rule: .saltToSodium, operand: "0.1", comparator: .less,
        quotient: "40", intermediate: "40.000000", stored: "40.0", amount: 40.0,
        json: #"{"comparator":"<","factor_text":"2.5","intermediate_text":"40.000000","nutrient":"sodium","operand_text":"0.1","operand_unit":"g_salt","rounding":"outward","rule":"salt_to_sodium_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"salt","stored_text":"40.0"}"#
    ),
    Golden(
        rule: .saltToSodium, operand: "0.0333", comparator: .lessOrEqual,
        quotient: "13.32", intermediate: "13.320000", stored: "13.4", amount: 13.4,
        json: #"{"comparator":"<=","factor_text":"2.5","intermediate_text":"13.320000","nutrient":"sodium","operand_text":"0.0333","operand_unit":"g_salt","rounding":"outward","rule":"salt_to_sodium_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"salt","stored_text":"13.4"}"#
    ),
    Golden(
        rule: .saltToSodium, operand: "0.0333", comparator: .greaterOrEqual,
        quotient: "13.32", intermediate: "13.320000", stored: "13.3", amount: 13.3,
        json: #"{"comparator":">=","factor_text":"2.5","intermediate_text":"13.320000","nutrient":"sodium","operand_text":"0.0333","operand_unit":"g_salt","rounding":"outward","rule":"salt_to_sodium_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"salt","stored_text":"13.3"}"#
    ),
    Golden(
        rule: .kjToKcal, operand: "10", comparator: .greater,
        quotient: "2.390057361376673040152963671128107", intermediate: "2.390057", stored: "2.3", amount: 2.3,
        json: #"{"comparator":">","factor_text":"4.184","intermediate_text":"2.390057","nutrient":"energy_kcal","operand_text":"10","operand_unit":"kJ","rounding":"outward","rule":"kj_to_kcal_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"energy_kj","stored_text":"2.3"}"#
    ),
    Golden(
        rule: .kjToKcal, operand: "10", comparator: .less,
        quotient: "2.390057361376673040152963671128107", intermediate: "2.390057", stored: "2.4", amount: 2.4,
        json: #"{"comparator":"<","factor_text":"4.184","intermediate_text":"2.390057","nutrient":"energy_kcal","operand_text":"10","operand_unit":"kJ","rounding":"outward","rule":"kj_to_kcal_v1","rule_version":"pasted-label-conversions-v1","source_header_id":"header_1","source_row_id":"energy_kj","stored_text":"2.4"}"#
    ),
]

@Test func test45ConversionGoldenVectors() throws {
    for golden in goldens {
        let conversion = try #require(PastedLabelConversions.convert(
            golden.rule, operandText: golden.operand, comparator: golden.comparator,
            sourceHeaderID: "header_1", sourceRowID: golden.rule.sourceNutrient
        ))
        #expect(conversion.operand == Decimal(string: golden.operand, locale: Locale(identifier: "en_US_POSIX")))
        #expect(conversion.quotient == Decimal(string: golden.quotient, locale: Locale(identifier: "en_US_POSIX")), "\(golden.operand): \(conversion.quotient)")
        #expect(conversion.record.intermediateText == golden.intermediate)
        #expect(conversion.record.storedText == golden.stored)
        #expect(Double(conversion.record.storedText) == golden.amount)
        #expect(conversion.record.storedAmount == golden.amount)
        #expect(try canonicalJSON(conversion.record) == golden.json)
        #expect(PastedLabelConversions.storedTextMatches(conversion.record))
    }
}

@Test func test5ConversionRulesAndWorkedValues() throws {
    let kcal = try #require(PastedLabelConversions.convert(.kjToKcal, operandText: "1550", sourceHeaderID: "h", sourceRowID: "r"))
    #expect(kcal.record.storedText == "370.5")
    #expect(kcal.record.comparator == nil && kcal.record.rounding == nil)
    // A comma decimal is read as a point; the operand text is kept as printed.
    let comma = try #require(PastedLabelConversions.convert(.saltToSodium, operandText: "0,6", sourceHeaderID: "h", sourceRowID: "r"))
    #expect(comma.record.storedText == "240.0")
    #expect(comma.record.operandText == "0,6")
    // Only plain printed decimal text converts.
    for bad in ["", "1e3", "-1", "1.", ".5", "1.2.3", "１２", "12\n", " 12"] {
        #expect(PastedLabelConversions.convert(.kjToKcal, operandText: bad, sourceHeaderID: "h", sourceRowID: "r") == nil, "\(bad)")
    }
    // An absent row is never converted.
    let noEnergy = candidate([cell("fat", "header_1", .per100g, "3.2", "g")])
    #expect(PastedLabelConversions.conversions(for: noEnergy, storedHeaderID: "header_1").isEmpty)
    // A printed zero converts to 0.0 and is still calculated.
    let zero = candidate([cell("salt", "header_1", .per100g, "0", "g")])
    #expect(PastedLabelConversions.conversions(for: zero, storedHeaderID: "header_1").map(\.record.storedText) == ["0.0"])
    // A printed bound converts as a bound, outward.
    let bound = candidate([cell("salt", "header_1", .per100g, "0.01", "g", comparator: .less)])
    let converted = PastedLabelConversions.conversions(for: bound, storedHeaderID: "header_1")
    #expect(converted.map(\.record.storedText) == ["4.0"])
    #expect(converted.first?.record.comparator == .less)
    #expect(converted.first?.record.rounding == "outward")
}

@Test func storedTextVerificationIgnoresTheIntermediate() throws {
    var record = try #require(PastedLabelConversions.convert(.kjToKcal, operandText: "1550", sourceHeaderID: "h", sourceRowID: "r")).record
    record.intermediateText = "370.458890"
    #expect(PastedLabelConversions.storedTextMatches(record))
    record.storedText = "370.4"
    #expect(!PastedLabelConversions.storedTextMatches(record))
}

@Test func test6PrintedAlwaysWins() {
    // kcal and kJ both printed, and disagreeing: kcal is stored as printed, nothing is converted.
    let energy = candidate([
        cell("energy_kj", "header_1", .per100g, "1550", "kJ"),
        cell("energy_kcal", "header_1", .per100g, "500", "kcal"),
        cell("salt", "header_1", .per100g, "0.6", "g"),
        cell("sodium", "header_1", .per100g, "100", "mg"),
    ])
    #expect(PastedLabelConversions.conversions(for: energy, storedHeaderID: "header_1").isEmpty)
    let values = PastedLabelStoredColumn.values(for: energy, storedHeaderID: "header_1")
    #expect(values.map(\.nutrient) == ["energy_kcal", "sodium"])
    #expect(values.allSatisfy { if case .printed = $0 { true } else { false } })
    if case .printed(let kcal) = values.first { #expect(kcal.decimalText == "500") }
}

@Test func test7NoCrossColumnOrChainedConversion() {
    // kJ and salt printed only in the per-serving column; the per 100 g column is stored.
    let table = candidate(
        [
            cell("fat", "header_1", .per100g, "3.2", "g"),
            cell("energy_kj", "header_2", .perServing, "465", "kJ"),
            cell("salt", "header_2", .perServing, "0.2", "g"),
        ],
        headers: [header("header_1", .per100g), header("header_2", .perServing)]
    )
    #expect(PastedLabelStoredColumn.headerID(for: table) == "header_1")
    #expect(PastedLabelConversions.conversions(for: table, storedHeaderID: "header_1").isEmpty)
    #expect(PastedLabelStoredColumn.values(for: table, storedHeaderID: "header_1").map(\.nutrient) == ["fat"])
    // Two kJ cells in the stored column are not one printed cell: nothing is converted.
    let twice = candidate([cell("energy_kj", "header_1", .per100g, "1550", "kJ"), cell("energy_kj", "header_1", .per100g, "1500", "kJ")])
    #expect(PastedLabelConversions.conversions(for: twice, storedHeaderID: "header_1").isEmpty)
    // A conversion's output is never a source: each rule reads only its printed source nutrient.
    let kjOnly = candidate([cell("energy_kj", "header_1", .per100g, "1550", "kJ")])
    let converted = PastedLabelConversions.conversions(for: kjOnly, storedHeaderID: "header_1")
    #expect(converted.map(\.record.rule) == [.kjToKcal])
    #expect(converted.map(\.record.operandText) == ["1550"])
}

@Test func test4NoInferenceFromReferenceIntakeOrTheOtherColumn() {
    let table = candidate(
        [
            cell("fat", "header_1", .per100g, "3.2", "g"),
            cell("fat", "header_2", .perServing, "1.6", "g"),
            cell("protein", "header_2", .perServing, "4", "g"),
            cell("sugars", "header_3", .referenceIntake, "12", "%"),
            cell("unrecognised", "header_1", .per100g, "5", "g"),
            cell("energy_kcal", "header_1", .per100g, "40", "%"),
        ],
        headers: [header("header_1", .per100g), header("header_2", .perServing), header("header_3", .referenceIntake)]
    )
    let values = PastedLabelStoredColumn.values(for: table, storedHeaderID: "header_1")
    // Protein (per serving only), sugars (% RI only), an unrecognised row and a percentage never become stored values.
    #expect(values.map(\.nutrient) == ["fat"])
    if case .printed(let fat) = values.first { #expect(fat.decimalText == "3.2") }
    // The per-serving column is the stored column only when no per 100 column is printed.
    let servingOnly = candidate([cell("fat", "header_1", .perServing, "1.6", "g")], headers: [header("header_1", .perServing)])
    #expect(PastedLabelStoredColumn.headerID(for: servingOnly) == "header_1")
    #expect(PastedLabelStoredColumn.headerID(for: candidate([], headers: [header("header_1", .referenceIntake)])) == nil)
}

// MARK: Synthetic candidates

private func header(_ id: String, _ basis: LabelBasis) -> LabelHeader {
    LabelHeader(headerID: id, printedText: basis.rawValue, basis: basis, servingConversion: nil)
}

private func cell(_ nutrient: String, _ headerID: String, _ basis: LabelBasis, _ number: String, _ unit: String, comparator: LabelComparator = .equal) -> LabelCell {
    LabelCell(
        rowID: nutrient, parentRowID: nil, nutrient: nutrient, printedLabel: nutrient, headerID: headerID, basis: basis,
        printedText: (comparator == .equal ? "" : comparator.rawValue) + number + unit, comparator: comparator,
        decimalText: number, unit: unit, canonicalUnit: unit, servingConversion: basis == .perServing ? "unknown" : "not_applicable"
    )
}

private func candidate(_ cells: [LabelCell], headers: [LabelHeader] = [LabelHeader(headerID: "header_1", printedText: "Per 100g", basis: .per100g, servingConversion: nil)]) -> LabelCaptureCandidate {
    LabelCaptureCandidate(
        route: "A", inputSHA256: String(repeating: "0", count: 64), declined: false, declineReasons: [], wouldMarkReady: true,
        language: .english, servingSize: nil, servingsPerPack: nil, headers: headers, cells: cells, warnings: []
    )
}
