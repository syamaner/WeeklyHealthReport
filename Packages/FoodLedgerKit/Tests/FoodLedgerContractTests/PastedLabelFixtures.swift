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
                         parserVersion: String = PastedLabelSource.parserVersionV2, brand: String? = "Synthetic Mill") throws -> PastedLabelManifest {
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
        try PastedLabelSource.confirmation(manifest: manifest, evidenceID: LedgerFixtures.id(evidence, EvidenceTag.self),
            capturedAt: LedgerFixtures.date, locale: LedgerText("zh_TW"), encoder: LedgerFixtures.encoder,
            digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions())
    }

    /// The per 100 g label (`h2` stored) with its serving lines replaced, for
    /// `pasted-label-serving-v2`: a serving size (or none), servings per pack (or none), the
    /// stored column's basis (`per_100g` or `per_100ml`) and the user's corrections.
    static func per100Manifest(servingSize: PastedLabelManifest.Candidate.ServingSize?,
                               servingsPerPack: PastedLabelManifest.Candidate.ServingsPerPack? = nil,
                               basis: String = "per_100g", corrections: [PastedLabelManifest.Correction] = [],
                               parserVersion: String = PastedLabelSource.parserVersionV2) throws -> PastedLabelManifest {
        let full = try candidate()
        let headers = full.headers.map { $0.headerID == "h2" ? .init(headerID: "h2", printedText: basis == "per_100ml" ? "每100毫升" : "每100公克",
                                                                      basis: basis, servingConversion: nil) : $0 }
        let candidate = PastedLabelManifest.Candidate(route: "A", inputSHA256: full.inputSHA256, declined: false, declineReasons: [],
            wouldMarkReady: full.wouldMarkReady, language: full.language, servingSize: servingSize, servingsPerPack: servingsPerPack,
            headers: headers, cells: full.cells, warnings: [])
        let servingBasis: ResolutionBasis = basis == "per_100ml" ? .per100Millilitres : .per100Grams
        return PastedLabelManifest(pastedText: pastedText, pastedTextSHA256: try textHash(), parserVersion: parserVersion,
            gateVersion: PastedLabelSource.gateVersion, arithmeticVersion: PastedLabelSource.arithmeticVersion,
            conversionVersion: PastedLabelSource.conversionVersion, labelFormat: "taiwan_nutrition_labelling",
            launchScope: ["taiwan_nutrition_labelling"], identityMapping: try .init(fortificationAnswer: .no, servingBasis: servingBasis),
            candidate: candidate, storedHeaderID: "h2", conversions: [kcal, sodium], flagsShown: [], corrections: corrections,
            warningsShown: [], name: "Synthetic oat crackers", brand: "Synthetic Mill")
    }

    /// A label printed per serving only (`h1`), with or without a readable serving size:
    /// section 6.3 case 2 (`perServing(30 g)`) or case 3 (`perServing(1 count)`).
    static func perServingManifest(readableServingSize: Bool,
                                   parserVersion: String = PastedLabelSource.parserVersionV2) throws -> PastedLabelManifest {
        let full = try candidate()
        let size = readableServingSize ? full.servingSize : nil
        let candidate = PastedLabelManifest.Candidate(route: "A", inputSHA256: full.inputSHA256, declined: false, declineReasons: [],
            wouldMarkReady: false, language: "zh-Hant", servingSize: size, servingsPerPack: nil,
            headers: [.init(headerID: "h1", printedText: "每份", basis: "per_serving", servingConversion: "30公克")],
            cells: full.cells.filter { $0.headerID == "h1" }, warnings: [])
        let basis: ResolutionBasis = readableServingSize ? .perServing(try PositiveQuantity(value: 30, unit: .grams))
            : .perServing(try PositiveQuantity(value: 1, unit: .count))
        return PastedLabelManifest(pastedText: pastedText, pastedTextSHA256: try textHash(), parserVersion: parserVersion,
            gateVersion: PastedLabelSource.gateVersion, arithmeticVersion: PastedLabelSource.arithmeticVersion,
            conversionVersion: PastedLabelSource.conversionVersion, labelFormat: "taiwan_nutrition_labelling",
            launchScope: ["taiwan_nutrition_labelling"], identityMapping: try .init(fortificationAnswer: .no, servingBasis: basis),
            candidate: candidate, storedHeaderID: "h1", conversions: [], flagsShown: [], corrections: [],
            warningsShown: [], name: "Synthetic per-serving crackers", brand: nil)
    }

    /// Re-encodes `value` with the retained manifest text replaced and every hash rebound, so
    /// only a content or canonical-bytes check can catch the change.
    static func rebinding<T: Codable & Sendable>(_ value: T, manifestText old: String, with new: String) throws -> T {
        let oldHash = try SHA256Digester().sha256(Data(old.utf8)).value
        let newHash = try SHA256Digester().sha256(Data(new.utf8)).value
        func escaped(_ text: String) throws -> String {
            let quoted = String(decoding: try LedgerFixtures.encoder.encode([text]), as: UTF8.self)
            return String(quoted.dropFirst(2).dropLast(2))
        }
        var json = String(decoding: try LedgerFixtures.encoder.encode(value), as: UTF8.self)
        let from = try escaped(old), to = try escaped(new)
        precondition(json.contains(from))
        json = json.replacingOccurrences(of: from, with: to).replacingOccurrences(of: oldHash, with: newHash)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    /// Byte-level variants of a canonical manifest that decode to the same manifest.
    static func nonCanonicalVariants(_ text: String) -> [(String, String)] {
        [("whitespace", text.replacingOccurrences(of: #"{"arithmetic_version""#, with: #"{ "arithmetic_version""#)),
         ("key order", text.replacingOccurrences(of: #""arithmetic_version":"label-arithmetic-checks-v1","brand":"Synthetic Mill","#,
                                                 with: #""brand":"Synthetic Mill","arithmetic_version":"label-arithmetic-checks-v1","#)),
         ("escaped UTF-8", text.replacingOccurrences(of: "營", with: #"\u71df"#))]
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
