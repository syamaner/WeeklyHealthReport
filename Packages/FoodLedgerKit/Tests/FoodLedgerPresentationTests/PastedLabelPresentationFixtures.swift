import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport

/// Synthetic pasted-label fixtures for the presentation tests (#93, PR 4). Nothing is parsed:
/// each `LabelReading` is written by hand and reaches the view models only through the
/// application reader, the way the adapter's output does. No real product label is used.
enum LabelFixtures {
    static let now = Date(timeIntervalSince1970: 1_791_800_000)

    struct Clock: LedgerClock { let value: Date; func now() -> Date { value } }

    /// pasted-label-conversions-v1 golden results for the values used here (the arithmetic is
    /// owned and tested in NutritionLabelParsingTests).
    struct Conversions: PastedLabelConversionChecking {
        func storedTextMatches(_ record: PastedLabelManifest.Conversion) -> Bool {
            ["kj_to_kcal_v1|1550": "370.5", "salt_to_sodium_v1|0.6": "240.0"]["\(record.rule)|\(record.operandText)"] == record.storedText
        }
    }

    /// kJ-only energy and salt-only sodium in the stored per 100 g column (h2), so both
    /// conversions apply; per serving (h1) prints kcal, which is evidence only. Saturated fat is
    /// not printed (a G3 flag) and fibre is not printed at all ("Not stated").
    static let pastedText = "營養標示\n每一份量30公克\n本包裝含10份\n每份 每100公克\n熱量 111大卡 1550 kJ\n蛋白質 1.6公克 5.2公克\n脂肪 <0.5公克 <0.5公克\n碳水化合物 18.0公克 60.1公克\n鹽 0.2公克 0.6公克\n"

    static func cell(_ row: String, _ nutrient: String, _ header: String, _ printed: String, _ decimal: String, _ unit: String,
                     canonical: String? = nil, comparator: String = "=") -> PastedLabelManifest.Candidate.Cell {
        PastedLabelManifest.Candidate.Cell(rowID: row, parentRowID: nil, nutrient: nutrient, printedLabel: row, headerID: header,
            basis: header == "h1" ? "per_serving" : "per_100g", printedText: printed, comparator: comparator, decimalText: decimal,
            unit: unit, canonicalUnit: canonical ?? unit, servingConversion: header == "h1" ? "30公克" : "not_applicable")
    }

    static let cells = [
        cell("熱量", "energy_kcal", "h1", "111大卡", "111", "大卡", canonical: "kcal"),
        cell("熱量", "energy_kj", "h2", "1550 kJ", "1550", "kJ"),
        cell("蛋白質", "protein", "h1", "1.6公克", "1.6", "公克", canonical: "g"),
        cell("蛋白質", "protein", "h2", "5.2公克", "5.2", "公克", canonical: "g"),
        cell("脂肪", "fat", "h1", "<0.5公克", "0.5", "公克", canonical: "g", comparator: "<"),
        cell("脂肪", "fat", "h2", "<0.5公克", "0.5", "公克", canonical: "g", comparator: "<"),
        cell("碳水化合物", "carbohydrate", "h1", "18.0公克", "18.0", "公克", canonical: "g"),
        cell("碳水化合物", "carbohydrate", "h2", "60.1公克", "60.1", "公克", canonical: "g"),
        cell("鹽", "salt", "h1", "0.2公克", "0.2", "公克", canonical: "g"),
        cell("鹽", "salt", "h2", "0.6公克", "0.6", "公克", canonical: "g")
    ]

    static func hash(_ text: String) -> String { (try? SHA256Digester().sha256(Data(text.utf8)).value) ?? "" }

    static let versions = LabelReading.Versions(parser: PastedLabelSource.parserVersion, gate: PastedLabelSource.gateVersion,
        arithmetic: PastedLabelSource.arithmeticVersion, conversion: PastedLabelSource.conversionVersion,
        formatInference: "pasted-label-format-inference-v1")

    static let kcal = PastedLabelManifest.Conversion(nutrient: "energy_kcal", rule: "kj_to_kcal_v1", ruleVersion: "pasted-label-conversions-v1",
        sourceHeaderID: "h2", sourceRowID: "熱量", operandText: "1550", operandUnit: "kJ", factorText: "4.184",
        intermediateText: "370.458891", storedText: "370.5")
    static let sodium = PastedLabelManifest.Conversion(nutrient: "sodium", rule: "salt_to_sodium_v1", ruleVersion: "pasted-label-conversions-v1",
        sourceHeaderID: "h2", sourceRowID: "鹽", operandText: "0.6", operandUnit: "g_salt", factorText: "2.5",
        intermediateText: "240.000000", storedText: "240.0")

    static let gateFlags = [
        LabelReading.Flag(code: "required_row_missing", concerns: "energy_kcal"),
        LabelReading.Flag(code: "required_row_missing", concerns: "saturates"),
        LabelReading.Flag(code: "required_row_missing", concerns: "sodium")
    ]

    static let printedServingSize = PastedLabelManifest.Candidate.ServingSize(printedText: "每一份量30公克", decimalText: "30",
                                                                              unit: "公克", canonicalUnit: "g")

    /// The per 100 g reading: Confirm stores h2. Its printed 30 g serving size qualifies for
    /// `pasted-label-serving-v3` (a parser-v3 reading); pass another (or nil) to test the cases that do not.
    static func reading(text: String = pastedText, checks: [LabelReading.Check] = [],
                        servingSize: PastedLabelManifest.Candidate.ServingSize? = printedServingSize,
                        warnings: [String] = []) -> LabelReading {
        let candidate = PastedLabelManifest.Candidate(route: "A", inputSHA256: hash(text), declined: false, declineReasons: [],
            wouldMarkReady: true, language: "zh-Hant",
            servingSize: servingSize,
            servingsPerPack: .init(printedText: "本包裝含10份", decimalText: "10", approximate: false),
            headers: [.init(headerID: "h1", printedText: "每份", basis: "per_serving", servingConversion: "30公克"),
                      .init(headerID: "h2", printedText: "每100公克", basis: "per_100g", servingConversion: nil)],
            cells: cells, warnings: warnings)
        return LabelReading(origin: .pastedText, textSHA256: hash(text), candidate: candidate, format: "taiwan_nutrition_labelling",
            gate: .init(format: "taiwan_nutrition_labelling", skipped: nil, hardDeclines: [], flags: gateFlags),
            checks: checks, conversions: [kcal, sodium], storedHeaderID: "h2", versions: versions)
    }

    /// Per serving only (h1), with or without a printed servings-per-pack line and serving size.
    static func perServingReading(pack: PastedLabelManifest.Candidate.ServingsPerPack? = .init(printedText: "本包裝含10份", decimalText: "10", approximate: false),
                                  servingSize: Bool = true) -> LabelReading {
        let perServing = [
            cell("熱量", "energy_kcal", "h1", "111大卡", "111", "大卡", canonical: "kcal"),
            cell("蛋白質", "protein", "h1", "1.6公克", "1.6", "公克", canonical: "g"),
            cell("脂肪", "fat", "h1", "3.0公克", "3.0", "公克", canonical: "g"),
            cell("飽和脂肪", "saturates", "h1", "1.0公克", "1.0", "公克", canonical: "g"),
            cell("碳水化合物", "carbohydrate", "h1", "18.0公克", "18.0", "公克", canonical: "g"),
            cell("糖", "sugars", "h1", "2.0公克", "2.0", "公克", canonical: "g"),
            cell("鈉", "sodium", "h1", "80毫克", "80", "毫克", canonical: "mg")
        ]
        var flags: [LabelReading.Flag] = []
        if pack == nil { flags.append(.init(code: "required_serving_declaration_missing", concerns: "servings_per_pack")) }
        if !servingSize { flags.append(.init(code: "required_serving_declaration_missing", concerns: "serving_size")) }
        let candidate = PastedLabelManifest.Candidate(route: "A", inputSHA256: hash(pastedText), declined: false, declineReasons: [],
            wouldMarkReady: false, language: "zh-Hant",
            servingSize: servingSize ? .init(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g") : nil,
            servingsPerPack: pack,
            headers: [.init(headerID: "h1", printedText: "每份", basis: "per_serving", servingConversion: servingSize ? "30公克" : nil)],
            cells: perServing, warnings: [])
        return LabelReading(origin: .pastedText, textSHA256: hash(pastedText), candidate: candidate, format: "taiwan_nutrition_labelling",
            gate: .init(format: "taiwan_nutrition_labelling", skipped: nil, hardDeclines: [], flags: flags),
            checks: [], conversions: [], storedHeaderID: "h1", versions: versions)
    }

    static func declined(_ codes: [String]) -> LabelReading {
        let candidate = PastedLabelManifest.Candidate(route: "A", inputSHA256: hash(pastedText), declined: true, declineReasons: codes,
            wouldMarkReady: false, language: "zh-Hant", servingSize: nil, servingsPerPack: nil, headers: [], cells: [], warnings: [])
        return LabelReading(origin: .pastedText, textSHA256: hash(pastedText), candidate: candidate, format: "taiwan_nutrition_labelling",
            gate: nil, checks: [], conversions: [], storedHeaderID: nil, versions: versions)
    }

    static func review(_ reading: LabelReading = reading(), text: String = pastedText) throws -> PastedLabelReview {
        guard case let .usable(review) = PastedLabelReader.classify(reading, pastedText: text) else {
            throw PastedLabelSourceError.invalidManifest("fixture reading is not usable")
        }
        return review
    }

    static func builder(conversions: any PastedLabelConversionChecking = Conversions()) -> PastedLabelConfirmation {
        PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: Clock(value: now), encoder: FoundationCanonicalJSONEncoder(),
                                digester: SHA256Digester(), conversions: conversions)
    }

    static let details = PastedLabelDetails(name: "Synthetic oat crackers", brand: "Synthetic Mill", fortification: .no)
    static let locale = try! LedgerText("zh_TW")

    @MainActor
    static func source(_ reading: LabelReading = reading(), details: PastedLabelDetails = details,
                       conversions: any PastedLabelConversionChecking = Conversions()) throws -> PastedLabelSourceModel {
        try PastedLabelSourceModel(review: review(reading), details: details, builder: builder(conversions: conversions), locale: locale)
    }

    /// A Confirm wired like the app: an in-memory ledger, the pasted-label conversion checker on
    /// save, and each correction replacing Confirm's source input.
    @MainActor
    static func confirm(_ source: PastedLabelSourceModel,
                        conversions: any PastedLabelConversionChecking = Conversions()) throws -> (FoodConfirmationViewModel, InMemoryFoodLedgerStore) {
        let store = InMemoryFoodLedgerStore()
        let ids = RandomLedgerIDGenerator()
        let ledger = FoodLedgerService(actorID: try LedgerID("00000000-0000-0000-0000-00000000a000"), committer: store,
            clock: Clock(value: now), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let service = FoodConfirmationService(ledger: ledger, reader: store, clock: Clock(value: now), ids: ids,
            digester: SHA256Digester(), pastedLabelConversions: conversions)
        let input = try XCTUnwrapOrThrow(source.input)
        let model = FoodConfirmationViewModel(state: FoodConfirmationState(input: input, prefillSourceQuantity: false),
                                              now: { now }) { state in
            try service.save(state, operationID: ids.makeID(OperationTag.self), idempotencyKey: nil)
        }
        source.onInputChange = { [weak model] in model?.replaceSourceInput($0) }
        return (model, store)
    }

    static func XCTUnwrapOrThrow<T>(_ value: T?) throws -> T {
        guard let value else { throw PastedLabelSourceError.invalidManifest("nil") }
        return value
    }

    /// A reader stub behind the application's `LabelTextReading` port.
    final class StubReader: LabelTextReading, @unchecked Sendable {
        private let lock = NSLock()
        private var reading: LabelReading
        private(set) var texts: [String] = []
        private(set) var hashes: [String] = []
        init(_ reading: LabelReading) { self.reading = reading }
        func set(_ reading: LabelReading) { lock.withLock { self.reading = reading } }
        func read(_ text: String, textSHA256: String) -> LabelReading {
            lock.withLock { texts.append(text); hashes.append(textSHA256); return reading }
        }
    }

    @MainActor
    static func textModel(_ stub: StubReader, diagnostics: @escaping ([String]) -> Void = { _ in }) -> PastedLabelTextViewModel {
        let reader = PastedLabelReader(reader: stub, digester: SHA256Digester())
        return PastedLabelTextViewModel(read: { reader.read($0) }, makeConfirm: { review, details in
            try PastedLabelSourceModel(review: review, details: details, builder: builder(), locale: locale)
        }, recordDiagnostics: diagnostics)
    }
}
