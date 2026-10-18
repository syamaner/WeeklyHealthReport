import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport

/// Golden vectors of `pasted-label-conversions-v1` (contract section 3.5, worked values). The
/// arithmetic is owned and tested in `NutritionLabelParsingTests` (tests 5, 45 and 46); the
/// application reaches it only through the `PastedLabelConversionChecking` port.
struct GoldenPastedLabelConversions: PastedLabelConversionChecking {
    static let stored: [String: String] = [
        "kj_to_kcal_v1|1550|=": "370.5",
        "salt_to_sodium_v1|0.6|=": "240.0",
        "salt_to_sodium_v1|0.01|<": "4.0"
    ]
    func storedTextMatches(_ record: PastedLabelManifest.Conversion) -> Bool {
        Self.stored["\(record.rule)|\(record.operandText)|\(record.comparator ?? "=")"] == record.storedText
    }
}

/// A synthetic pasted label. The stored column (`h2`, per 100 g) prints kJ without kcal and salt
/// without sodium, so both v1 conversions apply; the per-serving column (`h1`) prints kcal, which
/// must never be used. Nothing here was parsed: the candidate is written by hand.
enum PastedLabelFixtures {
    static let pastedText = "營養標示\n每一份量30公克\n本包裝含10份\n每份 每100公克\n熱量 111大卡 1550 kJ\n蛋白質 1.6公克 5.2公克\n脂肪 <0.5公克 <0.5公克\n碳水化合物 18.0公克 60.1公克\n鹽 0.2公克 0.6公克\n"

    static func cell(_ row: String, _ nutrient: String, _ header: String, _ printed: String, _ decimal: String, _ unit: String,
                     canonical: String? = nil, comparator: String = "=") -> PastedLabelManifest.Candidate.Cell {
        PastedLabelManifest.Candidate.Cell(rowID: row, parentRowID: nil, nutrient: nutrient, printedLabel: row, headerID: header,
            basis: header == "h1" ? "per_serving" : "per_100g", printedText: printed, comparator: comparator, decimalText: decimal,
            unit: unit, canonicalUnit: canonical ?? unit, servingConversion: header == "h1" ? "30公克" : "not_applicable")
    }

    static func candidate(cells extra: [PastedLabelManifest.Candidate.Cell] = [], replacing: Set<String> = []) throws -> PastedLabelManifest.Candidate {
        let base = [
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
        ].filter { !replacing.contains("\($0.headerID):\($0.nutrient)") }
        return PastedLabelManifest.Candidate(route: "A", inputSHA256: try textHash(), declined: false, declineReasons: [],
            wouldMarkReady: true, language: "zh-Hant",
            servingSize: .init(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"),
            servingsPerPack: .init(printedText: "本包裝含10份", decimalText: "10", approximate: false),
            headers: [.init(headerID: "h1", printedText: "每份", basis: "per_serving", servingConversion: "30公克"),
                      .init(headerID: "h2", printedText: "每100公克", basis: "per_100g", servingConversion: nil)],
            cells: base + extra, warnings: [])
    }

    static func textHash(_ text: String = pastedText) throws -> String {
        try SHA256Digester().sha256(Data(text.utf8)).value
    }

    static let kcal = PastedLabelManifest.Conversion(nutrient: "energy_kcal", rule: "kj_to_kcal_v1", ruleVersion: "pasted-label-conversions-v1",
        sourceHeaderID: "h2", sourceRowID: "熱量", operandText: "1550", operandUnit: "kJ", factorText: "4.184",
        intermediateText: "370.458891", storedText: "370.5")
    static let sodium = PastedLabelManifest.Conversion(nutrient: "sodium", rule: "salt_to_sodium_v1", ruleVersion: "pasted-label-conversions-v1",
        sourceHeaderID: "h2", sourceRowID: "鹽", operandText: "0.6", operandUnit: "g_salt", factorText: "2.5",
        intermediateText: "240.000000", storedText: "240.0")

    /// Protein corrected from 5.2 to 5.4; fibre (not printed) entered as 2.0.
    static let corrections = [
        PastedLabelManifest.Correction(kind: .corrected, nutrient: "protein", rowID: "蛋白質", headerID: "h2",
            recognised: .init(printedText: "5.2公克", decimalText: "5.2", unit: "公克", comparator: "="),
            corrected: .init(decimalText: "5.4", unit: "g", comparator: "="), at: Date(timeIntervalSince1970: 1_700_000_100)),
        PastedLabelManifest.Correction(kind: .entered, nutrient: "fibre", rowID: nil, headerID: "h2", recognised: nil,
            corrected: .init(decimalText: "2.0", unit: "g", comparator: "="), at: Date(timeIntervalSince1970: 1_700_000_200))
    ]

    static func manifest(answer: PastedLabelIdentity.FortificationAnswer = .no, candidate: PastedLabelManifest.Candidate? = nil,
                         conversions: [PastedLabelManifest.Conversion] = [kcal, sodium],
                         corrections: [PastedLabelManifest.Correction] = corrections,
                         parserVersion: String = PastedLabelSource.parserVersion, brand: String? = "Synthetic Mill") throws -> PastedLabelManifest {
        PastedLabelManifest(pastedText: pastedText, pastedTextSHA256: try textHash(), parserVersion: parserVersion,
            gateVersion: PastedLabelSource.gateVersion, arithmeticVersion: PastedLabelSource.arithmeticVersion,
            conversionVersion: PastedLabelSource.conversionVersion, labelFormat: "taiwan_nutrition_labelling",
            launchScope: ["taiwan_nutrition_labelling"],
            identityMapping: try .init(fortificationAnswer: answer, servingBasis: .per100Grams),
            candidate: try candidate ?? self.candidate(), storedHeaderID: "h2", conversions: conversions,
            flagsShown: [.init(code: "required_row_missing", concerns: "fibre")], corrections: corrections,
            warningsShown: [], name: "Synthetic oat crackers", brand: brand)
    }

    static func data(_ manifest: PastedLabelManifest) throws -> Data { try LedgerFixtures.encoder.encode(manifest) }

    static func input(_ manifest: PastedLabelManifest, evidence: Int = 9_100) throws -> PopulatedFoodConfirmation {
        try PastedLabelSource.confirmation(manifestData: data(manifest), evidenceID: LedgerFixtures.id(evidence, EvidenceTag.self),
            capturedAt: LedgerFixtures.date, locale: LedgerText("zh_TW"), digester: LedgerFixtures.digester,
            conversions: GoldenPastedLabelConversions())
    }

    static func service(_ harness: TestHarness, conversions: (any PastedLabelConversionChecking)? = GoldenPastedLabelConversions()) throws -> FoodConfirmationService {
        try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: harness.reader,
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester,
            pastedLabelConversions: conversions)
    }

    static func state(_ input: PopulatedFoodConfirmation) -> FoodConfirmationState {
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(150, .grams))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return state
    }

    /// Replaces one nutrient of the single candidate, keeping everything else.
    static func replacing(_ input: PopulatedFoodConfirmation, _ key: NutrientKey, with value: NutrientValue) throws -> PopulatedFoodConfirmation {
        let populated = input.candidates[0]
        let source = populated.candidate
        let nutrients = try NutrientSet(entries: source.nutrients.entries.map { $0.key == key ? try NutrientEntry(key: key, value: value) : $0 })
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: source.sourceReleaseID,
            recordID: source.recordID, identity: source.identity, edibleQuantity: source.edibleQuantity, nutrients: nutrients,
            evidenceIDs: source.evidenceIDs, matchMetadata: source.matchMetadata), name: populated.name, brand: populated.brand,
            itemClass: populated.itemClass)
        return try PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: input.sourceReleases, candidates: [candidate],
            expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
    }
}
