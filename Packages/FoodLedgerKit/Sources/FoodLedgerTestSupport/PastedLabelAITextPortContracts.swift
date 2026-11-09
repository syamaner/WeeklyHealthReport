import Foundation
import FoodLedgerApplication

/// Contract suites for the two pasted label AI text ports (docs/pasted-label-ai-text-v1.md 11.1,
/// contract test 28). The same suite runs over the application tests' fakes and over the real
/// adapters (`OpenRouterPastedLabelAITextAttempt` over a scripted transport, and
/// `PastedLabelAITextReader`). Each returns its violations; an empty list passes. No XCTest here,
/// so the suite stays inside this target's allowed imports.
public enum PastedLabelAITextPortContracts {
    // MARK: Fixtures (synthetic, no real label)

    /// A synthetic UK-format declaration, one row per line.
    public static let ukText = """
    Nutrition
    Typical values\tPer 100g
    Energy\t1046kJ / 250kcal
    Fat\t9.5g
    of which saturates\t3.2g
    Carbohydrate\t30g
    of which sugars\t12g
    Protein\t8.1g
    Salt\t0.75g
    """

    /// The text wire answer for `ukText`, plus one fabricated row (`Fibre 3g`) the text does not print.
    public static let ukAnswer = Data("""
    {"declined": false, "decline_reasons": [], "language": "en", "serving_size_text": "unknown", "servings_per_pack_text": "unknown",
     "headers": [{"header_id": "h1", "printed_text": "Per 100g", "basis": "per_100g"}],
     "rows": [
      {"printed_label": "Energy", "nutrient": "energy_kj", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "1046kJ", "unit": null}]},
      {"printed_label": "Energy", "nutrient": "energy_kcal", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "250kcal", "unit": null}]},
      {"printed_label": "Fat", "nutrient": "fat", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "9.5g", "unit": null}]},
      {"printed_label": "of which saturates", "nutrient": "saturates", "parent_nutrient": "fat", "values": [{"header_id": "h1", "printed_text": "3.2g", "unit": null}]},
      {"printed_label": "Carbohydrate", "nutrient": "carbohydrate", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "30g", "unit": null}]},
      {"printed_label": "of which sugars", "nutrient": "sugars", "parent_nutrient": "carbohydrate", "values": [{"header_id": "h1", "printed_text": "12g", "unit": null}]},
      {"printed_label": "Fibre", "nutrient": "fibre", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "3g", "unit": null}]},
      {"printed_label": "Protein", "nutrient": "protein", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "8.1g", "unit": null}]},
      {"printed_label": "Salt", "nutrient": "salt", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "0.75g", "unit": null}]}
     ]}
    """.utf8)

    /// A model decline.
    public static let declinedAnswer = Data("""
    {"declined": true, "decline_reasons": ["not_a_nutrition_table"], "language": "unknown", "serving_size_text": "unknown",
     "servings_per_pack_text": "unknown", "headers": [], "rows": []}
    """.utf8)

    /// Not a text wire answer (an extra member).
    public static let invalidAnswer = Data(#"{"declined": false, "extra": true}"#.utf8)

    /// The SHA-256 of `ukText` as UTF-8 (lowercase hex).
    public static let ukTextSHA256 = "df7dd79468b2a1fdae0f24f81d109e65a2e7029aa025addd8e91e09ded300ea4"

    // MARK: PastedLabelAITextAttempting

    /// The attempting contract. `sends` counts the bytes the subject has handed its transport;
    /// `body` is the canned reply body the transport returns with HTTP 200.
    public static func attempting(_ subject: any PastedLabelAITextAttempting, body: Data, sends: @Sendable () -> Int) async -> [String] {
        var violations: [String] = []
        if !PastedLabelAITextRoute.isAdmitted(subject.route) { violations.append("the route is not a text route") }
        var before = sends()
        if await subject.attempt(text: "", timeout: 5) != .notSent(.textEmpty) { violations.append("an empty text was not refused") }
        if await subject.attempt(text: " \n\t", timeout: 5) != .notSent(.textEmpty) { violations.append("a blank text was not refused") }
        let tooLong = String(repeating: "鈉", count: PastedLabelManifest.maximumTextScalars + 1)
        if await subject.attempt(text: tooLong, timeout: 5) != .notSent(.textTooLong) { violations.append("8,001 scalars were not refused") }
        if sends() != before { violations.append("a refused text reached the transport") }

        let cancelled = Task<PastedLabelAITextAttemptResult, Never> {
            while !Task.isCancelled { await Task.yield() }
            return await subject.attempt(text: ukText, timeout: 5)
        }
        cancelled.cancel()
        if await cancelled.value != .notSent(.cancelled) { violations.append("a cancelled task was not refused before sending") }
        if sends() != before { violations.append("a cancelled attempt reached the transport") }

        let first = await subject.attempt(text: ukText, timeout: 5)
        guard case let .responded(response) = first else {
            violations.append("a valid text did not respond: \(first)")
            return violations
        }
        if response.body != body { violations.append("the raw body was changed") }
        if response.status != 200 { violations.append("the status was changed") }
        if sends() != before + 1 { violations.append("one attempt did not send exactly once") }
        before = sends()
        let atCap = String(repeating: "a", count: PastedLabelManifest.maximumTextScalars)
        if case .responded = await subject.attempt(text: atCap, timeout: 5) {} else { violations.append("8,000 scalars were refused") }
        if sends() != before + 1 { violations.append("the 8,000-scalar text did not send exactly once") }
        return violations
    }

    // MARK: PastedLabelAITextReading

    public static func reading(_ subject: any PastedLabelAITextReading) -> [String] {
        var violations: [String] = []
        let invalid = subject.reading(text: ukText, textSHA256: ukTextSHA256, answer: invalidAnswer)
        if invalid.outcome != .failed || invalid.candidate != nil || !invalid.values.isEmpty {
            violations.append("an invalid answer did not fail with nothing to show")
        }
        if invalid.textSHA256 != ukTextSHA256 { violations.append("the text hash was not carried") }
        let declined = subject.reading(text: ukText, textSHA256: ukTextSHA256, answer: declinedAnswer)
        if declined.outcome != .declined || declined.declineReasons.isEmpty || !declined.cellValues.isEmpty {
            violations.append("a model decline did not decline with a reason and no cells")
        }
        let read = subject.reading(text: ukText, textSHA256: ukTextSHA256, answer: ukAnswer)
        if read != subject.reading(text: ukText, textSHA256: ukTextSHA256, answer: ukAnswer) { violations.append("the reading is not deterministic") }
        if read.outcome != .reachedConfirm { violations.append("the UK answer did not reach Confirm: \(read.outcome) \(read.declineReasons)") }
        if read.candidate?.inputSHA256 != ukTextSHA256 { violations.append("the candidate does not name the text hash") }
        if read.inferredFormat != PastedLabelAITextOffer.ukFormat { violations.append("the UK answer was not read as UK format") }
        let cells = read.candidate?.cells ?? []
        if cells.count != read.cellValues.count { violations.append("cells and cell values disagree") }
        for value in read.cellValues where value.locator.range == nil && value.reasons.isEmpty {
            violations.append("\(value.printedLabel) \(value.printedText): not located, yet no attention")
        }
        guard let fibre = read.values.first(where: { $0.nutrient == "fibre" }) else {
            violations.append("the fabricated value was dropped instead of flagged")
            return violations
        }
        if fibre.locator != .notFound || !fibre.reasons.contains(.notFound) {
            violations.append("the fabricated value is not a not-found attention item")
        }
        for value in read.values where value.nutrient != "fibre" {
            if value.locator.range == nil { violations.append("\(value.printedLabel) \(value.printedText) was not located") }
            if value.read.rowID == nil { violations.append("\(value.printedLabel) \(value.printedText) was not read") }
        }
        return violations
    }
}

/// A scripted `PastedLabelAITextAttempting` fake: it refuses what the contract requires and
/// otherwise returns the canned body with HTTP 200, counting each send.
public final class ScriptedPastedLabelAITextAttempter: PastedLabelAITextAttempting, @unchecked Sendable {
    public let route: PastedLabelAITextRoute.Route
    let body: Data
    private let lock = NSLock()
    private var count = 0

    public init(route: PastedLabelAITextRoute.Route = PastedLabelAITextRoute.gemini4ArgonVertexUS, body: Data) {
        self.route = route; self.body = body
    }

    public var sends: Int { lock.withLock { count } }

    public func attempt(text: String, timeout: TimeInterval) async -> PastedLabelAITextAttemptResult {
        if Task.isCancelled { return .notSent(.cancelled) }
        if text.unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) { return .notSent(.textEmpty) }
        if text.unicodeScalars.count > PastedLabelManifest.maximumTextScalars { return .notSent(.textTooLong) }
        lock.withLock { count += 1 }
        return .responded(PastedLabelAITextRawResponse(status: 200, headers: [:], body: body, exceededLimit: false))
    }
}

/// A scripted `PastedLabelAITextReading` fake: a table of answers to results; any other answer fails.
public struct ScriptedPastedLabelAITextReader: PastedLabelAITextReading {
    let results: [Data: PastedLabelAITextReadingResult]
    public init(results: [Data: PastedLabelAITextReadingResult]) { self.results = results }

    public func reading(text: String, textSHA256: String, answer: Data) -> PastedLabelAITextReadingResult {
        results[answer] ?? Self.failed(textSHA256: textSHA256)
    }

    public static let versions = PastedLabelAITextReadingResult.Versions(
        wireSchema: "fake", mapping: "fake", locator: PastedLabelTextLocator.version, vocabulary: PastedLabelAITextVocabulary.version,
        detector: PastedLabelAITextPanelDetector.version, attention: PastedLabelAITextAttention.version, format: PastedLabelAITextFormat.version,
        gate: "fake", arithmetic: "fake",
        conversion: "fake")

    public static func failed(textSHA256: String) -> PastedLabelAITextReadingResult {
        PastedLabelAITextReadingResult(outcome: .failed, failure: "unreadable_answer", declineReasons: [], textSHA256: textSHA256,
                                       inferredFormat: nil, candidate: nil, gate: nil, checks: [], conversions: [], storedHeaderID: nil,
                                       textDetector: PastedLabelAITextPanelDetector.Verdict(markers: []), candidateDetector: nil, values: [],
                                       servingLines: [], servingAttention: [:], versions: versions)
    }
}
