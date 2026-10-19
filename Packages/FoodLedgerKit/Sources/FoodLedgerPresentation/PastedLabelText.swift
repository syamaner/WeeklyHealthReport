import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// Copy for the pasted nutrition label route (`docs/pasted-nutrition-label-v1.md` sections 2,
/// 3, 4 and 9.1). British spelling, plain language, no emoji, no confidence score and no
/// "checked" badge. Codes are for Developer tools only and never appear in this copy.
public enum PastedLabelText {
    // MARK: Label text screen (section 2.2)

    public static let title = "Paste nutrition label"
    public static let addFoodRow = "Paste nutrition label"
    public static let nameField = "Name"
    public static let namePrompt = "For example Oat granola"
    public static let brandField = "Brand (optional)"
    public static let fortifiedQuestion = "Fortified?"
    public static let fortifiedHelp = "Does the pack say vitamins or minerals are added?"
    public static let labelTextField = "Label text"
    public static let labelTextHelp = "Paste the nutrition table only. The text you read is saved with the entry as its source, on this device."
    public static let readLabel = "Read label"
    public static let readAgainTitle = "Reading the text again replaces your corrections."
    public static let readAgain = "Read again"
    public static let backToConfirm = "Back to Confirm"
    public static let clearText = "Paste again"
    public static let searchInstead = "Search foods instead"
    public static let scanInstead = "Scan barcode instead"
    public static let leaveWithoutSaving = "Leave without saving"
    public static let nothingSaved = "Nothing is saved until you choose Log on the next screen."

    /// Why Read label is disabled, or nil when it is enabled.
    public static func readBlockedReason(nameMissing: Bool, textMissing: Bool, tooLong: Bool) -> String? {
        if tooLong { return declineMessage(.textTooLong) }
        if nameMissing && textMissing { return "Enter a name and paste the label text." }
        if nameMissing { return "Enter a name for this food." }
        if textMissing { return "Paste the label text." }
        return nil
    }

    // MARK: Hard declines (section 3.1)

    /// The layouts the launch scope reads, from `PastedLabelLaunchScope`.
    public static var supportedLayouts: String {
        let names = PastedLabelLaunchScope.enabledFormats.map(layoutName)
        return names.count <= 1 ? (names.first ?? "") : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    public static func layoutName(_ format: String) -> String {
        switch format {
        case "taiwan_nutrition_labelling": "Traditional Chinese (Taiwan layout)"
        case "uk_nutrition_declaration": "English (UK layout)"
        default: "unknown"
        }
    }

    /// The copy for a copy key. Every key has its own sentence.
    public static func declineMessage(_ key: PastedLabelCodes.CopyKey) -> String {
        switch key {
        case .supplementPanel: "This looks like a supplement panel, which the app does not read."
        case .unsupportedLanguage: "This label is in a language the app cannot read yet. It reads \(supportedLayouts) labels."
        case .noTable: "No nutrition table was found in this text."
        case .layoutNotSupported: "The app cannot read this label layout yet. It reads \(supportedLayouts) labels."
        case .basisStateNotSupported: "This table is for the food as prepared or drained (for example 沖泡 or 瀝乾). The app reads values for the food as sold only."
        case .valuesNotBound: "The app could not match the values in this text to their rows and columns. Check that it is one table with each value on its row, then try again."
        case .textTooLong: "This text is too long to be one nutrition table. Paste the table only."
        case .unreadableTable: "The app could not read this table. Check that it is one nutrition table, then try again."
        case .rowNotRead, .cellNotRead, .noPer100Column, .servingLineNotRead:
            // A flag is never a decline; reaching here means the classification drifted.
            declineMessage(.unreadableTable)
        }
    }

    /// The reasons shown above the field for a decline: one sentence per distinct copy, in
    /// code order. A code without its own mapping renders `unreadable_table` (test 27).
    public static func declineMessages(_ codes: [String]) -> [String] {
        var seen: Set<String> = []
        let messages = codes.map { code -> String in
            let classification = PastedLabelCodes.classify(code)
            return classification.kind == .hardDecline ? declineMessage(classification.copy) : declineMessage(.unreadableTable)
        }
        return (messages.isEmpty ? [declineMessage(.unreadableTable)] : messages).filter { seen.insert($0).inserted }
    }

    // MARK: Confirm (section 2.3)

    public static let disclaimer = "Read automatically from your text. Check each value against the label."
    public static let sectionTitle = "From pasted label"
    public static let readButNotUsedTitle = "Read but not used"
    public static let notUsed = "Not used"
    public static let pastedTextTitle = "Pasted text"
    public static let editLabelText = "Edit label text"
    public static let reportMisread = "Report a misread"
    public static let otherNutrientsTitle = "Other nutrients"
    public static let otherNutrientsNote = "The label does not state these. They stay unknown, never zero."
    public static let notStated = "Not stated"
    public static let notRead = "Not read"
    /// A unit code as shown in the interface: "mL" for the stored code "ml"; others unchanged.
    public static func unitLabel(_ code: String) -> String { code == "ml" ? "mL" : code }

    /// "Whole pack (1 serving)", "Whole pack (2.5 servings)".
    public static func wholePackTitle(_ servings: Double) -> String {
        "Whole pack (\(FoodDisplayNumber.amount(servings, fraction: 0...2)) \(servings == 1 ? "serving" : "servings"))"
    }

    /// Whole pack's caption, from the serving size's own origin (printed, corrected or entered).
    public static func wholePackNote(servingSize origin: NutrientValueOrigin) -> String {
        switch origin {
        case .correctedByYou: "Logged as that many servings, through the serving size you corrected."
        case .enteredByYou: "Logged as that many servings, through the serving size you entered."
        default: "Logged as that many servings, through the printed serving size."
        }
    }

    public static func sourceLine(basis: String, format: String) -> String {
        "From pasted label · \(basisLabel(basis)) · \(languageLabel(format))"
    }

    public static func basisLabel(_ basis: String) -> String {
        switch basis {
        case "per_100g": "per 100 g"
        case "per_100ml": "per 100 ml"
        case "per_serving": "per serving"
        case "reference_intake": "reference intake"
        default: basis.replacingOccurrences(of: "_", with: " ")
        }
    }

    public static func languageLabel(_ format: String) -> String {
        switch format {
        case "taiwan_nutrition_labelling": "Traditional Chinese, Taiwan layout"
        case "uk_nutrition_declaration": "English, UK layout"
        default: "Layout not recognised"
        }
    }

    /// A reader nutrient key in plain words, lower case for use inside a sentence.
    public static func nutrientName(_ nutrient: String) -> String {
        switch nutrient {
        case "energy_kcal": "energy (kcal)"
        case "energy_kj": "energy (kJ)"
        case "fat": "fat"
        case "saturates": "saturated fat"
        case "trans_fat": "trans fat"
        case "carbohydrate": "carbohydrate"
        case "sugars": "sugars"
        case "added_sugars": "added sugars"
        case "fibre": "fibre"
        case "protein": "protein"
        case "sodium": "sodium"
        case "salt": "salt"
        case PastedLabelManifest.Correction.servingSize: "serving size"
        case PastedLabelManifest.Correction.servingsPerPack: "servings per pack"
        default: nutrient.replacingOccurrences(of: "_", with: " ")
        }
    }

    // MARK: Flags G3 to G6 (section 3.2), never blocking

    /// The exception copy for one flag, on the row, cell or line it concerns.
    public static func flagMessage(_ flag: LabelReading.Flag, headers: [PastedLabelManifest.Candidate.Header]) -> String {
        switch PastedLabelCodes.classify(flag.code).copy {
        case .rowNotRead:
            let name = nutrientName(flag.nutrient ?? flag.concerns)
            guard fillable(flag.nutrient ?? flag.concerns) else {
                return "Not read: \(name). The app does not store \(name) yet, so it stays unknown."
            }
            return "Not read: \(name). Add it, or leave it unknown."
        case .cellNotRead:
            let column = flag.headerID.flatMap { id in headers.first { $0.headerID == id } }.map { basisLabel($0.basis) } ?? "another column"
            return "Not read: \(nutrientName(flag.nutrient ?? flag.concerns)), \(column). Add it, or leave it unknown."
        case .noPer100Column:
            return "No per 100 g or per 100 ml values were read."
        case .servingLineNotRead:
            return "Not read: \(nutrientName(flag.concerns)). Add it, or leave it unknown."
        default:
            return declineMessage(.unreadableTable)
        }
    }

    /// Whether the user can enter a value for a reader key in v1: a stored ledger nutrient or
    /// a serving line. Trans fat has no ledger key yet (#270).
    public static func fillable(_ nutrient: String) -> Bool {
        PastedLabelSource.ledgerKeys[nutrient] != nil
            || [PastedLabelManifest.Correction.servingSize, PastedLabelManifest.Correction.servingsPerPack].contains(nutrient)
    }

    // MARK: Warnings (section 4), never blocking, no pass badge

    /// One warning code (`<check>:<basis>[:<nutrient>][:<child>]`) in plain words.
    public static func warningMessage(_ code: String) -> String {
        let parts = code.split(separator: ":").map(String.init)
        switch parts.first {
        case "energy":
            return "Energy does not match the fat, carbohydrate and protein shown. Check the label text."
        case "kj_kcal_ratio":
            return "The kJ and kcal values do not match each other. Check the label text."
        case "serving_scaling":
            return "The per serving and per 100 values do not match the serving size. Check the label text."
        case "subrow_not_above_parent":
            let child = parts.count > 2 ? parts[parts.count - 1] : ""
            let parent = ["saturates": "fat", "trans_fat": "fat", "sugars": "carbohydrate", "fibre": "carbohydrate"][child]
            if let parent {
                return FoodDisplayNumber.capitalisedFirst("\(nutrientName(child)) is more than \(nutrientName(parent)). Check the label text.")
            }
            return "A sub-row is more than the row it belongs to. Check the label text."
        case "bound_consistency":
            return "A value is printed as a range in one column and exact in another. Check the label text."
        case "net_weight":
            return "The servings per pack do not match the pack weight. Check the label text."
        default:
            return "Some values do not add up. Check the label text."
        }
    }

    // MARK: Misread report preview (section 9.1)

    public static let reportPreviewTitle = "Report a misread"
    public static let reportPreviewNote = "Check or trim this report. It goes only where you choose in the share sheet, or nowhere if you cancel. Nothing is sent automatically."
    public static let share = "Share"
    public static let cancel = "Cancel"
}

/// The one formatter for `NutrientValueOrigin` (contract section 3.5, test 33): Confirm, the
/// saved entry, the misread report and Developer tools all render origins here, so "about",
/// "Calculated" and the source wording cannot drift. Never colour or a symbol alone.
public enum NutrientOriginText {
    /// The origin in words. VoiceOver reads the same words.
    public static func tag(_ origin: NutrientValueOrigin) -> String {
        switch origin {
        case .printed: "Printed"
        case .calculated: "Calculated"
        case .correctedByYou: "Corrected by you"
        case .enteredByYou: "Entered by you"
        case .unknown(.notRead): PastedLabelText.notRead
        case .unknown(.notStated): PastedLabelText.notStated
        }
    }

    /// The rule of a calculated value: "kcal = kJ ÷ 4.184".
    public static func rule(_ rule: String) -> String {
        switch rule {
        case "kj_to_kcal_v1": "kcal = kJ ÷ 4.184"
        case "salt_to_sodium_v1": "sodium = salt ÷ 2.5"
        default: rule
        }
    }

    /// "Calculated from 1550 kJ (printed), kcal = kJ ÷ 4.184".
    public static func calculatedSource(_ conversion: PastedLabelManifest.Conversion) -> String {
        let unit = conversion.operandUnit == "g_salt" ? "g salt" : conversion.operandUnit
        let comparator = conversion.comparator.map { $0 == "<" ? "less than " : "up to " } ?? ""
        return "Calculated from \(comparator)\(conversion.operandText) \(unit) (printed), \(rule(conversion.rule))"
    }

    /// A stored value as shown beside its origin: "5.2 g", "Less than 0.5 g", "about 371 kcal",
    /// "Less than 40 mg · Calculated". Calculated kcal and mg are shown to a whole number: an exact
    /// value half away from zero with "about"; a bound rounded outward (an upper end up) so the
    /// shown bound still contains the printed one, tagged "Calculated". Unknown is never zero.
    public static func amount(_ value: NutrientValue, origin: NutrientValueOrigin) -> String {
        let calculated: Bool = if case .calculated = origin { true } else { false }
        switch value {
        case let .measured(exact), let .augmented(exact):
            if calculated { return calculatedAmount(exact.amount, unit: exact.unit.rawValue, comparator: "=") }
            return "\(FoodDisplayNumber.amount(exact.amount, fraction: 0...3)) \(exact.unit.rawValue)"
        case let .bounded(bounds):
            let unit = bounds.unit.rawValue
            if let upper = bounds.upper, bounds.lower == nil {
                if calculated { return calculatedAmount(upper, unit: unit, comparator: bounds.upperClosed ? "<=" : "<") }
                let number = FoodDisplayNumber.amount(upper, fraction: 0...3)
                return bounds.upperClosed ? "\(number) \(unit) or less" : "Less than \(number) \(unit)"
            }
            let lower = bounds.lower.map { FoodDisplayNumber.amount($0, fraction: 0...3) } ?? "?"
            let upper = bounds.upper.map { FoodDisplayNumber.amount($0, fraction: 0...3) } ?? "?"
            return "\(lower) to \(upper) \(unit)" + (calculated ? " · \(tag(origin))" : "")
        case .unknown:
            if case let .unknown(reason) = origin { return tag(.unknown(reason)) }
            return PastedLabelText.notStated
        }
    }

    /// The one display of a calculated amount (section 3.5), shared by Confirm and the report.
    public static func calculatedAmount(_ amount: Double, unit: String, comparator: String) -> String {
        let whole = unit == "kcal" || unit == "mg"
        switch comparator {
        case "<", "<=":
            let shown = whole ? FoodDisplayNumber.amount(amount.rounded(.up), fraction: 0...0) : FoodDisplayNumber.amount(amount, fraction: 0...3)
            let text = comparator == "<" ? "Less than \(shown) \(unit)" : "\(shown) \(unit) or less"
            return "\(text) · \(tag(.calculated(rule: "")))"
        default:
            let shown = whole ? FoodDisplayNumber.amount(amount.rounded(.toNearestOrAwayFromZero), fraction: 0...0)
                : FoodDisplayNumber.amount(amount, fraction: 0...3)
            return "about \(shown) \(unit)"
        }
    }

    /// A consumed total on the saved entry with its value's origin: "about 555 kcal · Calculated".
    public static func consumed(_ amount: String, origin: NutrientValueOrigin?) -> String {
        guard let origin else { return amount }
        switch origin {
        case .calculated: return "about \(amount) · \(tag(origin))"
        case .correctedByYou, .enteredByYou, .printed: return "\(amount) · \(tag(origin))"
        case .unknown: return amount
        }
    }

    /// One report line for a value read: "Energy (熱量) per 100 g: about 370.5 kcal · Calculated from …".
    public static func reportValue(_ value: PastedLabelMisreadReport.Value) -> String {
        let basis = PastedLabelText.basisLabel(value.basis)
        let label = "\(FoodDisplayNumber.capitalisedFirst(PastedLabelText.nutrientName(value.nutrient))) (\(value.printedLabel)) \(basis)"
        if case .calculated = value.origin, let conversion = value.conversion, let amount = Double(value.decimalText) {
            // Rounded exactly as on Confirm (section 3.5, Display).
            var shown = calculatedAmount(amount, unit: value.unit, comparator: value.comparator)
            let tagged = " · \(tag(value.origin))"
            if shown.hasSuffix(tagged) { shown.removeLast(tagged.count) }  // the source line says "Calculated from"
            return "\(label): \(shown) · \(calculatedSource(conversion))"
        }
        return "\(label): \(value.printedText) · \(tag(value.origin))"
    }
}

/// A logged pasted label on the saved entry (#93): each consumed value with its origin, and
/// the calculated values' printed sources, through the one origin formatter.
public enum PastedLabelSavedEntryText {
    public static let sectionTitle = "From pasted label"

    /// "about 555 kcal · Calculated", "12 g · Corrected by you", or the plain value.
    public static func value(_ total: FoodIntakeTotal, detail: SavedFoodEntryDetail) -> String {
        let plain = FoodLogText.nutrient(total, augmented: detail.augmentedKeys.contains(total.key))
        guard total.knownAmount != nil else {
            // Bounds stay bounds: a bound has no consumed amount, so it is shown as stored for
            // the label's basis ("Less than 0.5 g per 100 g · Printed"), never as unknown or zero.
            guard let value = detail.pastedLabelValues[total.key], case .bounded = value,
                  let origin = detail.valueOrigins[total.key] else { return plain }
            let basis = detail.pastedLabel.flatMap { manifest in
                manifest.candidate.headers.first { $0.headerID == manifest.storedHeaderID }.map { PastedLabelText.basisLabel($0.basis) }
            } ?? ""
            let tag = " · \(NutrientOriginText.tag(origin))"
            var amount = NutrientOriginText.amount(value, origin: origin)
            if amount.hasSuffix(tag) { amount.removeLast(tag.count) }
            return "\(amount) \(basis)\(tag)"
        }
        return NutrientOriginText.consumed(plain, origin: detail.valueOrigins[total.key])
    }

    /// One line per stored label value that is not simply printed: calculated values with
    /// their printed source and rule, corrected and entered values in words.
    public static func originLines(_ detail: SavedFoodEntryDetail) -> [String] {
        guard let manifest = detail.pastedLabel else { return [] }
        return PastedLabelSourceModel.rowOrder.compactMap { nutrient -> String? in
            guard let key = PastedLabelSource.ledgerKeys[nutrient], let origin = detail.valueOrigins[key] else { return nil }
            let title = FoodNutritionReviewPresentation.label(key)
            switch origin {
            case .calculated:
                return manifest.conversions.first { $0.nutrient == nutrient }.map { "\(title): \(NutrientOriginText.calculatedSource($0))" }
            case .correctedByYou, .enteredByYou, .unknown:
                return "\(title): \(NutrientOriginText.tag(origin))"
            case .printed:
                return nil
            }
        }
    }

    /// Where a servings amount's serving size came from: "Serving size 30 g · Printed",
    /// "… · Corrected by you" or "… · Entered by you". Nil when the amount is not in servings
    /// through a serving size.
    public static func servingSizeLine(_ detail: SavedFoodEntryDetail) -> String? {
        guard let size = detail.servingSize else { return nil }
        let unit = size.quantity.unit == .millilitres ? "mL" : size.quantity.unit.rawValue
        return "Serving size \(FoodDisplayNumber.amount(size.quantity.value, fraction: 0...2)) \(unit) · \(NutrientOriginText.tag(size.origin))"
    }

    public static func sourceLine(_ detail: SavedFoodEntryDetail) -> String? {
        guard let manifest = detail.pastedLabel else { return nil }
        let basis = manifest.candidate.headers.first { $0.headerID == manifest.storedHeaderID }?.basis ?? ""
        return PastedLabelText.sourceLine(basis: basis, format: manifest.labelFormat)
    }

    public static func reportText(_ detail: SavedFoodEntryDetail) -> String? {
        detail.pastedLabel.map { PastedLabelMisreadReport(manifest: $0).text(wording: PastedLabelReportText()) }
    }
}

/// The report's words, through the one origin formatter.
public struct PastedLabelReportText: PastedLabelReportWording {
    public init() {}

    public func heading(_ heading: PastedLabelMisreadReport.Heading) -> String {
        switch heading {
        case .title: "Pasted nutrition label: possible misread"
        case .pastedText: "Pasted text:"
        case .valuesRead: "Values read:"
        case .serving: "Serving lines read:"
        case .declined: "Why it was not read:"
        case .warnings: "Warnings shown:"
        case .versions: "Reader versions:"
        }
    }

    public func value(_ value: PastedLabelMisreadReport.Value) -> String { NutrientOriginText.reportValue(value) }

    public func servingSize(_ printedText: String?) -> String { "Serving size: \(printedText ?? PastedLabelText.notStated)" }

    public func servingsPerPack(_ printedText: String?) -> String { "Servings per pack: \(printedText ?? PastedLabelText.notStated)" }

    /// The reason in words, with its code so the owner can reproduce it in Developer tools.
    public func decline(_ code: String) -> String { "\(PastedLabelText.declineMessages([code]).first ?? code) (\(code))" }

    public func warning(_ code: String) -> String { "\(PastedLabelText.warningMessage(code)) (\(code))" }

    public func versions(_ versions: PastedLabelMisreadReport.Versions) -> String {
        [versions.parser, versions.gate, versions.arithmetic, versions.conversion].joined(separator: ", ")
    }
}
