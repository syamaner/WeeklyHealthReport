import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// **Development only** (`docs/pasted-nutrition-label-uk-english-v1.md` P1). Runs the UK
/// development set through the UK fresh-set run (`UKFreshSet.run`: the UK adapter, the
/// `.ukDevelopment` policy and a confirmation built with the same policy, #371 P2b seam) and
/// scores it with the UK scorer (`UKFreshSet.score`, P3), reading the P1 transcriptions (Taiwan
/// schema, `panel` counted `unknown`) through `UKFreshSet.developmentTranscription`. Unlike the
/// release check there are no seals and a rerun replaces the outputs: development figures are not
/// an accuracy rate. Every real file lives in the private folder, which `FreshSet.privateFolder`
/// keeps outside every git checkout.
enum UKDevelopmentSet {
    /// One label's set-aside file (`UKSetAsideRecord.fileSchema`).
    struct SetAsideFile: Codable, Equatable {
        let schema: String
        let labelID: String
        let entries: [UKSetAsideRecord]

        enum CodingKeys: String, CodingKey { case schema, labelID = "label_id", entries }
    }

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

    /// `UKFreshSet.run` (the basis is taken from the transcription when the sheet would be shown,
    /// reader v3 12.2.7 item 2), with the parser's decline reasons and warnings beside it.
    static func run(labelID: String, text: String, transcription: UKFreshSet.Transcription,
                    choose: (PastedLabelBasisOptions.Arrangement, PastedLabelBasisChoiceRequest) throws -> PastedLabelReview)
        -> (UKFreshSet.RunResult, Extra) {
        let result = UKFreshSet.run(labelID: labelID, text: text, transcription: transcription, choose: choose)
        let extra = Extra(labelID: labelID, format: result.format, parserDeclineReasons: result.candidate?.declineReasons ?? [],
                          parserWarnings: result.candidate?.warnings.map { "\($0)" } ?? [])
        return (result, extra)
    }

    /// Reads every `texts/<id>.txt` with its `transcription/<id>.json`, writing `run/<id>.json` (the
    /// UK fresh-set run schema) and `run-extra/<id>.json`, and appending one line to `run-log.txt`.
    static func runAll(_ root: URL, commit: String, now: Date = Date()) throws -> Int {
        let builder = UKFreshSet.builder()
        let ids = try labelIDs(root)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        for folder in ["run", "run-extra", "set-aside"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for id in ids {
            let text = try String(contentsOf: root.appendingPathComponent("texts/\(id).txt"), encoding: .utf8)
            let t = try UKFreshSet.developmentTranscription(Data(contentsOf: root.appendingPathComponent("transcription/\(id).json")))
            let (result, extra) = run(labelID: id, text: text, transcription: t) { try builder.choose($0, in: $1) }
            try encoder.encode(result).write(to: root.appendingPathComponent("run/\(id).json"))
            try encoder.encode(extra).write(to: root.appendingPathComponent("run-extra/\(id).json"))
            // The set-aside list beside the run output, so the run schema is unchanged (v2 P1 section 2).
            try encoder.encode(SetAsideFile(schema: UKSetAsideRecord.fileSchema, labelID: id, entries: UKEnglishLabelTextReader().setAside(text)))
                .write(to: root.appendingPathComponent("set-aside/\(id).json"))
        }
        try FreshSet.append("run \(ISO8601DateFormatter().string(from: now)) commit=\(commit) labels=\(ids.count)\n",
                            to: root.appendingPathComponent("run-log.txt"))
        return ids.count
    }

    /// Scores every run output with `UKFreshSet.score`, writing `results/<id>.json`,
    /// `results/summary.json` (with counts by `panel`) and `results/formats.json` (labels by
    /// inferred format).
    static func scoreAll(_ root: URL) throws -> UKFreshSet.Summary {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let results = root.appendingPathComponent("results")
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        var scores: [UKFreshSet.Score] = []
        var formats: [String: Int] = [:]
        for id in try labelIDs(root) {
            let result = try decoder.decode(UKFreshSet.RunResult.self, from: Data(contentsOf: root.appendingPathComponent("run/\(id).json")))
            let extra = try decoder.decode(Extra.self, from: Data(contentsOf: root.appendingPathComponent("run-extra/\(id).json")))
            let t = try UKFreshSet.developmentTranscription(Data(contentsOf: root.appendingPathComponent("transcription/\(id).json")))
            let s = UKFreshSet.score(result, t)
            try encoder.encode(s).write(to: results.appendingPathComponent("\(id).json"))
            scores.append(s)
            formats[extra.format ?? "none", default: 0] += 1
        }
        let summary = UKFreshSet.summary(scores)
        try encoder.encode(summary).write(to: results.appendingPathComponent("summary.json"))
        try encoder.encode(formats).write(to: results.appendingPathComponent("formats.json"))
        return summary
    }

    private static func labelIDs(_ root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("texts").path)
            .filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }.sorted()
    }
}
