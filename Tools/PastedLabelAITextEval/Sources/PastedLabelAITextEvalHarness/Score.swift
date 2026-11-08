import FoodLabelPhotoCapture
import FoodLabelTextAIReading
import FoodLedgerApplication
import Foundation
import PastedLabelAITextEvalCore

/// `PastedLabelAITextEval score` (docs/pasted-label-ai-text-v1.md 5.2 item 2): the shipped steps in
/// product order, then the scorer against the label's transcription.
///
/// 1. The send output must have responded; otherwise the label failed (a refused call counts as
///    failed).
/// 2. The envelope check (T3): one choice, `stop`, and the response's model and provider must match
///    the pinned route, or the label failed.
/// 3. `PastedLabelAITextReader`: the text mapping; decline gate v2 (`.uk` for UK candidates), the
///    conversions and the arithmetic checks; the panel detector; the locator, unit and vocabulary
///    checks; attention. Only a hard decline declines (D19).
/// 4. `pasted-label-ai-text-scorer-v1` against the case.
public enum ScoreCommand {
    public struct Output: Codable, Equatable, Sendable {
        public let score: LabelScore
        public let pass: Bool
        public let f1: Double
        public let namedScores: [String: Double]
        public let costUSD: String?
        public let chargedUSD: String
        public let latencySeconds: Double?
        public let cached: Bool
        public let routeCandidate: String
        public let promptVersion: String
        public let readerVersions: [String: String]

        enum CodingKeys: String, CodingKey {
            case score, pass, f1, cached
            case namedScores = "named_scores", costUSD = "cost_usd", chargedUSD = "charged_usd", latencySeconds = "latency_seconds"
            case routeCandidate = "route_candidate", promptVersion = "prompt_version", readerVersions = "reader_versions"
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case textMismatch, sendTextMismatch, unreadableText, unknownRoute(String)
        public var description: String {
            switch self {
            case .textMismatch: "the text's SHA-256 is not the case's text_sha256"
            case .sendTextMismatch: "the send record's text_sha256 is not the case's"
            case .unreadableText: "the text file is not UTF-8"
            case let .unknownRoute(id): "route candidate \(id) is not in the closed set"
            }
        }
    }

    public static func run(evalCase: EvalCase, textData: Data, send: SendCommand.Output) throws -> Output {
        guard EvalCase.sha256(textData) == evalCase.textSHA256 else { throw Failure.textMismatch }
        // The send record must be for this case's text (A2 gate finding 7).
        guard send.textSHA256 == evalCase.textSHA256 else { throw Failure.sendTextMismatch }
        guard let text = String(data: textData, encoding: .utf8) else { throw Failure.unreadableText }
        guard let route = PastedLabelAITextRoute.candidate(send.routeCandidate) else { throw Failure.unknownRoute(send.routeCandidate) }
        let versions = PastedLabelAITextReader.versions
        let readerVersions = ["wire_schema": versions.wireSchema, "mapping": versions.mapping, "locator": versions.locator,
                              "vocabulary": versions.vocabulary, "detector": versions.detector, "attention": versions.attention,
                              "gate": versions.gate, "arithmetic": versions.arithmetic, "conversion": versions.conversion,
                              "scorer": PastedLabelAITextScorer.version]
        func output(_ score: LabelScore) -> Output {
            Output(score: score, pass: score.outcome == "reached_confirm" && !score.silentErrorTable, f1: score.fieldF1,
                   namedScores: score.namedScores, costUSD: send.cached ? send.cachedCostUSD : send.costUSD, chargedUSD: send.chargedUSD, latencySeconds: send.latencySeconds,
                   cached: send.cached, routeCandidate: send.routeCandidate, promptVersion: send.promptVersion, readerVersions: readerVersions)
        }
        func failed(_ reason: String) -> Output {
            output(PastedLabelAITextScorer.score(evalCase, outcome: "failed", declineReasons: [], failure: reason, table: nil))
        }
        // D19: a detector decline before sending is a hard decline, not a failure.
        if send.attempt.hasPrefix("declined_before_send:") {
            let markers = send.attempt.dropFirst("declined_before_send:".count).split(separator: ",").map { "detector:" + $0 }
            return output(PastedLabelAITextScorer.score(evalCase, outcome: "declined", declineReasons: markers, failure: nil, table: nil))
        }
        guard send.attempt == "responded", let status = send.status, let body = send.response else { return failed(send.attempt) }
        let raw = PastedLabelAITextRawResponse(status: status, headers: [:], body: Data(body.utf8), exceededLimit: false)
        guard case let .answered(content, _, _, _, _) = PastedLabelAITextEnvelope.check(raw, route: route) else {
            if case let .failed(_, failure, _) = PastedLabelAITextEnvelope.check(raw, route: route) { return failed("envelope:\(failure)") }
            return failed("envelope")
        }
        let reading = PastedLabelAITextReader().reading(text: text, textSHA256: evalCase.textSHA256, answer: content)
        let table = reading.outcome == .reachedConfirm ? confirmTable(reading) : nil
        return output(PastedLabelAITextScorer.score(evalCase, outcome: reading.outcome.rawValue, declineReasons: reading.declineReasons,
                                                     failure: reading.failure, table: table))
    }

    /// The table the product would show at Confirm, from the reading: every cell, with whether its
    /// value carries an attention item.
    public static func confirmTable(_ reading: PastedLabelAITextReadingResult) -> ConfirmTable? {
        guard let candidate = reading.candidate else { return nil }
        var attention: [String: Bool] = [:]
        for value in reading.cellValues {
            if let rowID = value.read.rowID { attention[rowID + "\u{0}" + value.headerID, default: false] = attention[rowID + "\u{0}" + value.headerID, default: false] || value.needsAttention }
        }
        let cells = candidate.cells.map { cell in
            ConfirmTable.Cell(rowID: cell.rowID, nutrient: cell.nutrient, printedLabel: cell.printedLabel, headerID: cell.headerID,
                              comparator: cell.comparator, decimalText: cell.decimalText, canonicalUnit: cell.canonicalUnit,
                              needsAttention: attention[cell.rowID + "\u{0}" + cell.headerID] ?? true)
        }
        return ConfirmTable(headers: candidate.headers.map { .init(id: $0.headerID, basis: $0.basis) }, cells: cells,
                            servingSize: candidate.servingSize?.decimalText.map { [$0, candidate.servingSize?.canonicalUnit ?? ""] },
                            servingsPerPack: candidate.servingsPerPack.map { [$0.decimalText, $0.approximate ? "true" : "false"] },
                            attentionItems: reading.attentionItemCount)
    }
}
