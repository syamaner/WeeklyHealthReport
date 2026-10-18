import Foundation
import Testing
@testable import NutritionLabelParsing

// Contract tests 3 and 9 (`docs/pasted-nutrition-label-v1.md` sections 5 and 8.4).

/// A UK label printed per serving only (with a %RI column). Owner decision, 18 October 2026: it
/// is inferred as UK, not US, and gate v2 flags the missing per 100 column (G5); in v1 the launch
/// scope still declines UK.
private let ukPerServingOnly = "v1:off:5060457050039:nutrition_nl.5:tab"

@Test func test3InferenceAgreesWithTheDeclaredFormatOnEveryFrozenCase() throws {
    let lines = try ParityFixtures.lines("parity-cases-v1.jsonl")
    var disagreements = Set<String>()
    var agreed = 0
    var perServingOnly: LabelCaptureCandidate?
    for record in lines.dropFirst() {
        let id = record["id"] as? String ?? "?"
        guard let candidate = try ParityFixtures.candidate(record["candidate"]) else { continue }
        let inferred = LabelFormatInference.infer(candidate)
        // The Swift rule equals the export script's Python rule on every vector.
        #expect(inferred.rawValue == (record["expected"] as? [String: Any])?["inferred_format"] as? String, "\(id)")
        if id == ukPerServingOnly { perServingOnly = candidate }
        guard record["kind"] as? String == "text", !candidate.declined else { continue }
        if inferred.rawValue == record["declared_format"] as? String { agreed += 1 } else { disagreements.insert(id) }
    }
    #expect(disagreements.isEmpty, "\(disagreements)")
    #expect(agreed == 283) // 314 texts less 31 the parser declines
    let candidate = try #require(perServingOnly)
    #expect(LabelFormatInference.infer(candidate) == .uk)
    let report = LabelDeclineGate.evaluate(candidate, format: .uk)
    #expect(report.hardDeclines.isEmpty)
    #expect(report.flags == [.requiredBasisMissing])
}

@Test func test3UsNutritionFactsStaysUs() {
    let text = """
    Nutrition Facts
    Servings per container about 8
    Serving size 2/3 cup (55g)
    Amount per serving
    % Daily Value*
    Total Fat 8g 10%
    Sodium 160mg 7%
    Total Carbohydrate 37g 13%
    Protein 3g
    """
    let candidate = NutritionLabelTextParser().parse(text, inputSHA256: String(repeating: "0", count: 64))
    #expect(!candidate.declined)
    #expect(LabelFormatInference.infer(candidate) == .usNutritionFacts)
}

@Test func test3MixedAndUnknownLanguagesAreAmbiguous() {
    for language in [LabelLanguage.mixed, .unknown] {
        let candidate = LabelCaptureCandidate.declined(route: "A", inputSHA256: String(repeating: "0", count: 64), language: language, reasons: ["x"])
        #expect(LabelFormatInference.infer(candidate) == .ambiguous)
        #expect(LabelFormatInference.infer(candidate).declineCode == "format_ambiguous")
        #expect(LabelFormatInference.infer(candidate).gateFormat == nil)
    }
    let english = LabelCaptureCandidate(
        route: "A", inputSHA256: String(repeating: "0", count: 64), declined: false, declineReasons: [], wouldMarkReady: false,
        language: .english, servingSize: nil, servingsPerPack: nil,
        headers: [LabelHeader(headerID: "header_1", printedText: "Per serving", basis: .perServing, servingConversion: nil)], cells: [], warnings: []
    )
    #expect(LabelFormatInference.infer(english) == .usNutritionFacts)
    #expect(LabelFormatInference.infer(english).declineCode == "layout_not_supported")
}

@Test func test9SameTextGivesByteIdenticalCandidateAndFindings() throws {
    let lines = try ParityFixtures.lines("parity-cases-v1.jsonl")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var checked = 0
    // The second run uses a comma-decimal C locale. Nothing here reads `Locale.current` (decimal
    // text is parsed with `en_US_POSIX`), and Foundation's `Locale.current` cannot be switched
    // inside a running process, so this covers the C-level locale only.
    let previous = setlocale(LC_ALL, nil).map { String(cString: $0) } ?? "C"
    defer { setlocale(LC_ALL, previous) }
    for record in lines.dropFirst() where record["kind"] as? String == "text" {
        let id = record["id"] as? String ?? "?"
        let text = try #require(record["text"] as? String)
        let hash = try #require(record["text_sha256"] as? String)
        #expect(ParityFixtures.sha256(Data(text.utf8)) == hash, "\(id) text hash")
        let format = try #require(LabelGateFormat(rawValue: record["declared_format"] as? String ?? ""))
        setlocale(LC_ALL, previous)
        let first = NutritionLabelTextParser().parse(text, inputSHA256: hash)
        #expect(setlocale(LC_ALL, "de_DE.UTF-8") != nil)
        let second = NutritionLabelTextParser().parse(text, inputSHA256: hash)
        #expect(try encoder.encode(first) == encoder.encode(second), "\(id)")
        // The parse equals the candidate the CLI produced in another process when the vectors were exported.
        #expect(ParityFixtures.sameJSON(try ParityFixtures.jsonObject(first), record["candidate"] ?? NSNull()), "\(id) candidate")
        #expect(LabelDeclineGate.apply(first, format: format).report == LabelDeclineGate.apply(second, format: format).report)
        #expect(LabelArithmeticChecks.check(LabelArithmeticTable(first, format: format)) == LabelArithmeticChecks.check(LabelArithmeticTable(second, format: format)))
        if let header = PastedLabelStoredColumn.headerID(for: first) {
            #expect(PastedLabelConversions.conversions(for: first, storedHeaderID: header) == PastedLabelConversions.conversions(for: second, storedHeaderID: header))
        }
        checked += 1
    }
    #expect(checked == 314)
}
