import FoodLedgerApplication
import FoodLedgerDomain

/// Developer tools lines for a bundled reference row (docs/ciqual-2025-admission-v1.md section
/// 7): release hashes, attribution, licence, the name in the source's language and, per value,
/// the published literal, confidence code, source code, `min`/`max` literals and the stored
/// `manifestReference`. Identifiers and codes stay here; they never reach search rows, Confirm,
/// the saved entry or an export. `min`/`max` are shown as published and are never bounds.
public enum GenericSourceDetailsText {
    public static func lines(_ details: GenericSourceRecordDetails, nutrients: NutrientSet, release: SourceRelease?) -> [String] {
        var lines = ["\(details.originalNameLanguage) name (Developer tools only, not searched or saved): \(details.originalName)"]
        if let release {
            lines.append("Source manifest SHA-256: \(release.artifactHash.value)")
            lines.append("Corpus SHA-256: \(release.manifestHash.value)")
            lines.append("Attribution: \(release.attribution.value)")
            lines.append("Licence: \(release.licence.value)")
        } else {
            lines.append("Release details: not found for this record's source release")
        }
        let entries = Dictionary(uniqueKeysWithValues: nutrients.entries.map { ($0.key, $0.value) })
        lines += details.values.map { value in
            line(value, sourceName: details.sourceName, stored: entries[value.key])
        }
        return lines
    }

    static func line(_ value: GenericSourceRecordDetails.Value, sourceName: String, stored: NutrientValue?) -> String {
        var parts = ["literal \(value.literal)"]
        if let code = value.confidence {
            let calculated = value.key == .energyConsumed && code == "D" ? ", calculated, not analysed" : ""
            parts.append("\(sourceName) confidence \(code)\(calculated)")
        }
        if let source = value.sourceCode { parts.append("source code \(source)") }
        parts.append("constituent \(value.constituentCode)")
        switch (value.minimum, value.maximum) {
        case (nil, nil): break
        case let (minimum, maximum):
            let range = [minimum.map { "min \($0)" }, maximum.map { "max \($0)" }].compactMap { $0 }.joined(separator: " · ")
            parts.append("\(range) (spread of source data, not a bound)")
        }
        switch stored {
        case let .unknown(reason)?: parts.append("stays unknown (\(reason.rawValue))")
        case let stored?:
            if let reference = stored.provenance.compactMap(\.manifestReference).first { parts.append("reference \(reference.value)") }
        case nil: break
        }
        return "\(FoodNutritionReviewPresentation.label(value.key)): " + parts.joined(separator: " · ")
    }
}
