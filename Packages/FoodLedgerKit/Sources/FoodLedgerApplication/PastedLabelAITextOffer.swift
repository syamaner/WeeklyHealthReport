import Foundation

/// When Read with AI is offered (docs/pasted-label-ai-text-v1.md 4.6, D1 and D15): only after
/// the frozen reader declines, and only for a closed set of its decline codes, fixed here from
/// `PastedLabelCodes`:
/// - a Taiwan table (`taiwan_nutrition_labelling`) whose every decline code is a layout decline
///   (`taiwanLayoutCodes`);
/// - a UK-format paste (`uk_nutrition_declaration`) declined with exactly `layout_not_supported`,
///   the code the product scope gives every UK table once its gate has inferred the format.
///
/// Never for identity declines (`basis_state_not_supported`), `text_too_long`, an empty paste, a
/// hash failure (no reading, so no format), gate G1 or G2 declines (simplified Chinese included),
/// an ambiguous or US format, two panels, or any code outside these sets. Pure.
public enum PastedLabelAITextOffer {
    public static let taiwanFormat = "taiwan_nutrition_labelling"
    public static let ukFormat = "uk_nutrition_declaration"

    /// The frozen reader's layout declines of a table it could not bind.
    public static let taiwanLayoutCodes: Set<String> = [
        // Parser v2 binding failures, which `PastedLabelCodes` names only in its mapping.
        "count_mismatch", "values_without_row", "energy_without_unit", "value_without_unit", "unrecognised_unit", "duplicate_basis",
        PastedLabelCodes.noBasisHeader, PastedLabelCodes.layoutAmbiguous, PastedLabelCodes.tooLittleRead, PastedLabelCodes.flattenedTableAmbiguous,
        PastedLabelCodes.unheadedColumnsWithoutServingSize, PastedLabelCodes.unheadedColumnsServingSizeNotInGramsOrMillilitres
    ]

    /// Whether Read with AI is offered for a decline. `format` is the reading's inferred format,
    /// nil when the reader returned no reading (too long, or a hash failure).
    public static func isOffered(declineCodes: [String], format: String?, pastedText: String) -> Bool {
        guard !declineCodes.isEmpty, !pastedText.unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) else { return false }
        guard pastedText.unicodeScalars.count <= PastedLabelManifest.maximumTextScalars else { return false }
        switch format {
        case taiwanFormat?: return declineCodes.allSatisfy(taiwanLayoutCodes.contains)
        case ukFormat?: return Set(declineCodes) == [PastedLabelCodes.layoutNotSupported]
        default: return false
        }
    }
}
