import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// **Development only** (`docs/pasted-nutrition-label-uk-english-v1.md` P1). Runs the UK
/// development set through `UKDevelopmentReader` and scores it with the reader v3 fresh-set
/// scorer (`FreshSet.score`), unchanged. Unlike the release check there are no seals and a rerun
/// replaces the outputs: development figures are not an accuracy rate. Every real file lives in
/// the private folder, which `FreshSet.privateFolder` keeps outside every git checkout.
enum UKDevelopmentSet {
    struct Extra: Codable, Equatable {
        let labelID: String
        /// The inferred format (`uk_nutrition_declaration`, `us_nutrition_facts`, `format_ambiguous`, ...).
        let format: String?
        let parserDeclineReasons: [String]
        let parserWarnings: [String]

        enum CodingKeys: String, CodingKey {
            case format
            case labelID = "label_id", parserDeclineReasons = "parser_decline_reasons", parserWarnings = "parser_warnings"
        }
    }

    private struct SystemClock: LedgerClock { func now() -> Date { Date() } }

    /// `FreshSet.run` with the development reader: the basis is taken from the transcription when
    /// the sheet would be shown (reader v3 12.2.7 item 2).
    static func run(labelID: String, text: String, transcription: FreshSet.Transcription, reader: UKDevelopmentReader,
                    choose: (PastedLabelBasisOptions.Arrangement, PastedLabelBasisChoiceRequest) throws -> PastedLabelReview)
        -> (FreshSet.RunResult, Extra) {
        typealias Result = FreshSet.RunResult
        func declined(_ codes: [String], _ reading: LabelReading?, choice: Result.Choice? = nil) -> Result {
            Result(schema: FreshSet.runSchema, labelID: labelID, outcome: "declined", declineCodes: codes, choice: choice,
                   candidate: reading?.candidate, storedHeaderID: nil, conversions: [], flags: [], warningCodes: [], unreadRows: [])
        }
        func usable(_ review: PastedLabelReview, choice: Result.Choice?) -> Result {
            Result(schema: FreshSet.runSchema, labelID: labelID, outcome: "usable", declineCodes: [], choice: choice,
                   candidate: review.reading.candidate, storedHeaderID: review.storedHeaderID, conversions: review.reading.conversions,
                   flags: review.flags.map { "\($0.code):\($0.concerns)" }, warningCodes: review.warningCodes,
                   unreadRows: review.reading.unreadRows.map { "\($0)" })
        }
        let outcome = reader.read(text)
        let reading: LabelReading?
        let result: Result
        switch outcome {
        case let .declined(codes, declinedReading):
            reading = declinedReading
            result = declined(codes, declinedReading)
        case let .usable(review):
            reading = review.reading
            result = usable(review, choice: nil)
        case let .needsBasisChoice(request):
            reading = request.declinedReading
            let offered = request.offered
            let amountBases = transcription.columns.compactMap { $0.basis == "reference_intake" ? nil : $0 }
            if amountBases.isEmpty || !amountBases.allSatisfy({ $0.basis != nil }) {
                result = declined([FreshSet.basisNotSure], request.declinedReading, choice: .init(arrangement: "", offered: offered))
            } else {
                let identifier = amountBases.compactMap(\.basis).joined(separator: ",")
                if offered.contains(identifier), let arrangement = PastedLabelBasisOptions.Arrangement(identifier: identifier),
                   let review = try? choose(arrangement, request) {
                    result = usable(review, choice: .init(arrangement: identifier, offered: offered))
                } else {
                    result = declined([FreshSet.basisNotOffered], request.declinedReading, choice: .init(arrangement: identifier, offered: offered))
                }
            }
        }
        let extra = Extra(labelID: labelID, format: reading?.format, parserDeclineReasons: reading?.candidate.declineReasons ?? [],
                          parserWarnings: reading?.candidate.warnings.map { "\($0)" } ?? [])
        return (result, extra)
    }

    /// Reads every `texts/<id>.txt` with its `transcription/<id>.json`, writing `run/<id>.json` (the
    /// fresh-set run schema) and `run-extra/<id>.json`, and appending one line to `run-log.txt`.
    static func runAll(_ root: URL, commit: String, now: Date = Date()) throws -> Int {
        let builder = PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: SystemClock(), encoder: FoundationCanonicalJSONEncoder(),
                                              digester: SHA256Digester(), conversions: NutritionLabelConversionChecker())
        let reader = UKDevelopmentReader()
        let ids = try labelIDs(root)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        for folder in ["run", "run-extra"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for id in ids {
            let text = try String(contentsOf: root.appendingPathComponent("texts/\(id).txt"), encoding: .utf8)
            let t = try FreshSet.transcription(Data(contentsOf: root.appendingPathComponent("transcription/\(id).json")))
            let (result, extra) = run(labelID: id, text: text, transcription: t, reader: reader) { try builder.choose($0, in: $1) }
            try encoder.encode(result).write(to: root.appendingPathComponent("run/\(id).json"))
            try encoder.encode(extra).write(to: root.appendingPathComponent("run-extra/\(id).json"))
        }
        try FreshSet.append("run \(ISO8601DateFormatter().string(from: now)) commit=\(commit) labels=\(ids.count)\n",
                            to: root.appendingPathComponent("run-log.txt"))
        return ids.count
    }

    /// Scores every run output with `FreshSet.score`, writing `results/<id>.json`,
    /// `results/summary.json` and `results/formats.json` (labels by inferred format).
    static func scoreAll(_ root: URL) throws -> FreshSet.Summary {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let results = root.appendingPathComponent("results")
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        var scores: [FreshSet.Score] = []
        var formats: [String: Int] = [:]
        for id in try labelIDs(root) {
            let result = try decoder.decode(FreshSet.RunResult.self, from: Data(contentsOf: root.appendingPathComponent("run/\(id).json")))
            let extra = try decoder.decode(Extra.self, from: Data(contentsOf: root.appendingPathComponent("run-extra/\(id).json")))
            let s = FreshSet.score(result, try FreshSet.transcription(Data(contentsOf: root.appendingPathComponent("transcription/\(id).json"))))
            try encoder.encode(s).write(to: results.appendingPathComponent("\(id).json"))
            scores.append(s)
            formats[extra.format ?? "none", default: 0] += 1
        }
        let summary = FreshSet.summary(scores)
        try encoder.encode(summary).write(to: results.appendingPathComponent("summary.json"))
        try encoder.encode(formats).write(to: results.appendingPathComponent("formats.json"))
        return summary
    }

    private static func labelIDs(_ root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("texts").path)
            .filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }.sorted()
    }
}
