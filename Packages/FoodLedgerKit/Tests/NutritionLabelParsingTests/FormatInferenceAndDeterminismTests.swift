import Foundation
import Testing
@testable import NutritionLabelParsing

// Contract tests 3 and 9 (`docs/pasted-nutrition-label-v1.md` sections 5 and 8.4).

/// Frozen cases whose declared format the contract's inference rule does not reproduce. The rule
/// reads English without a per 100 g or per 100 ml column as a US layout, but this development
/// case is a UK label printed per serving only (gate v2 blocks it with G5). Both outcomes decline
/// in v1 (`layout_not_supported`), so the product result is the same; the disagreement is pinned
/// here so any new one fails, and is reported for an owner decision.
private let knownDisagreements: Set<String> = ["v1:off:5060457050039:nutrition_nl.5:tab"]

@Test func test3InferenceAgreesWithTheDeclaredFormatOnEveryFrozenCase() throws {
    let lines = try ParityFixtures.lines("parity-cases-v1.jsonl")
    var disagreements = Set<String>()
    var agreed = 0
    for record in lines.dropFirst() {
        let id = record["id"] as? String ?? "?"
        guard let candidate = try ParityFixtures.candidate(record["candidate"]) else { continue }
        let inferred = LabelFormatInference.infer(candidate)
        // The Swift rule equals the export script's Python rule on every vector.
        #expect(inferred.rawValue == (record["expected"] as? [String: Any])?["inferred_format"] as? String, "\(id)")
        guard record["kind"] as? String == "text", !candidate.declined else { continue }
        if inferred.rawValue == record["declared_format"] as? String { agreed += 1 } else { disagreements.insert(id) }
    }
    #expect(disagreements == knownDisagreements)
    #expect(agreed > 200)
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
    for record in lines.dropFirst() where record["kind"] as? String == "text" {
        let id = record["id"] as? String ?? "?"
        let text = try #require(record["text"] as? String)
        let hash = try #require(record["text_sha256"] as? String)
        #expect(ParityFixtures.sha256(Data(text.utf8)) == hash, "\(id) text hash")
        let format = try #require(LabelGateFormat(rawValue: record["declared_format"] as? String ?? ""))
        let first = NutritionLabelTextParser().parse(text, inputSHA256: hash)
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
    #expect(checked == 239)
}
