import FoodLedgerApplication
import SwiftUI

/// Every string of the label photo route (docs/label-photo-ai-prefill-v1.md section 7). British
/// spelling, plain language, no emoji. Shared Confirm strings stay where they are.
public enum LabelPhotoText {
    /// The display names of the one allow-listed route (E6).
    public static let modelName = "Gemini 4 Argon"
    public static let providerName = "Google Vertex"

    // MARK: 7.1 Label photo screen

    public static let addFoodRow = "Photo of nutrition label"
    public static let addFoodRowSubtitle = "Taiwan labels (營養標示). Read by AI; you check every value."
    public static let takePhoto = "Take photo"
    public static let chooseFromLibrary = "Choose from library"
    public static let screenTitle = "Label photo"
    public static let cropTitle = "Crop to the label"
    public static let cropInstruction = "Drag the corners so the nutrition table fills the frame. Only this part is sent."
    public static let useCrop = "Use crop"
    public static let rotate = "Rotate"
    public static let cancel = "Cancel"
    public static let retake = "Retake"
    public static let chooseAnother = "Choose another"
    public static let adjustCrop = "Adjust crop"
    public static let egressStatement = "Read label with AI sends this cropped photo to OpenRouter, which passes it to \(modelName) on \(providerName) to read the table. Location and camera details are removed first. Your name, brand and food log are not sent. Nothing is saved until you tap Log."
    public static let readButton = "Read label with AI"
    public static func underButton(reads: Int) -> String {
        "Uses your OpenRouter key and credit. Today: \(reads) of \(LabelPhotoSpendPolicy.dailyReadLimit) reads."
    }
    public static let firstUseTitle = "Send label photos to OpenRouter?"
    public static let firstUseBody = "To read a label photo, the app sends the cropped photo to OpenRouter and the model it names, using your key. OpenRouter is asked to use only an endpoint that keeps no copy and does not train on it, with no fallback to other providers. OpenRouter keeps its own account and usage records. You check and correct every value before anything is saved."
    public static let firstUseSend = "Send photo"
    public static let firstUseNotNow = "Not now"
    public static let privacyPolicy = "Privacy policy"
    public static let leave = "Leave without saving"
    public static let photoAccessibilityLabel = "Cropped label photo, as it will be sent"

    // MARK: 7.2 Blocking, reading, declined and failed states

    public static let cameraDenied = "Camera access is off for this app. You can choose a photo from your library instead, or turn on the camera in Settings."
    public static let openSettings = "Open Settings"
    public static let noKey = "Add your OpenRouter key to read label photos."
    public static let openRouterSettings = "OpenRouter settings"
    public static let keyNotValidated = "Validate your OpenRouter key before reading a photo."
    public static let validateKey = "Validate key"
    public static let offline = "You're offline. Reading a label photo needs a connection. You can paste the label text instead."
    public static let pasteLabel = "Paste nutrition label"
    public static let searchFoods = "Search foods"
    public static let dailyLimit = "You've reached today's limit of 30 label photo reads (or $0.50 of reported cost). It resets at midnight."
    public static let routeUnavailable = "Label photo reading is unavailable: the model's private endpoint could not be confirmed. Nothing was sent."
    public static let cropTooSmall = "This crop is too small to read. Move closer or crop less tightly."
    public static let photoTooLarge = "This photo could not be made small enough to send. Crop more tightly and try again."
    public static let reading = "Reading the label…"
    public static func retrying(attempt: Int) -> String { "OpenRouter is busy. Trying again (attempt \(attempt) of 3)…" }
    public static let cancelledAfterSending = "Stopped. The photo may already have reached OpenRouter; nothing was saved."
    public static let declinedNoTable = "No nutrition table was found in this photo. Crop to the table and try again."
    public static let declinedSupplement = "This looks like a supplement panel, which the app does not read."
    public static let failedTimedOut = "Reading the photo timed out. You can try again."
    public static let failedConnection = "Reading the photo could not connect. Check your connection and try again."
    public static let failedKeyRejected = "OpenRouter rejected the API key. Replace or revalidate it."
    public static let failedQuota = "OpenRouter reports a quota or rate limit. Check your quota and billing before trying again."
    public static let failedUnusable = "The model's answer could not be used, so nothing is shown. You can try again, or paste the label text."
    public static let failedCostPaused = "This read cost more than the $0.05 limit, so label photo reading is paused for today."
    public static let tryAgain = "Try again"
    /// Decision (17.19): a photo that cannot be decoded at all, which 7.2 does not name.
    public static let photoUnreadable = "This photo could not be opened. Choose another photo."

    /// The copy for a failure (7.2). Every failure code has its sentence.
    public static func failure(_ failure: LabelImageReadingFailure) -> String {
        switch failure {
        case .offline: offline
        case .keyMissing: noKey
        case .keyRejected: failedKeyRejected
        case .routeUnavailable: routeUnavailable
        case .dailyLimit: dailyLimit
        case .paused: failedCostPaused
        case .timedOut: failedTimedOut
        case .cancelled: cancelledAfterSending
        case .providerUnavailable: failedConnection
        case .quotaLimited: failedQuota
        case .wrongModel, .wrongProvider, .truncated, .refused, .oversize, .unreadableAnswer, .failed: failedUnusable
        }
    }

    /// The copy for a preparation refusal (7.2).
    public static func preparation(_ error: LabelImagePreparationError) -> String {
        switch error {
        case .cropTooSmall, .cropTooNarrow, .outOfBounds: cropTooSmall
        case .malformedOutput: photoTooLarge
        case .unreadable: photoUnreadable
        }
    }

    /// The sentences for a decline: one per distinct copy, in code order (7.2). The language,
    /// layout and basis-state sentences are the pasted route's; the table sentences name the photo.
    public static func declines(_ codes: [String]) -> [String] {
        var seen: Set<String> = []
        let messages = codes.map { code -> String in
            let classification = PastedLabelCodes.classify(code)
            guard classification.kind == .hardDecline else { return failedUnusable }
            switch classification.copy {
            case .noTable: return declinedNoTable
            case .supplementPanel: return declinedSupplement
            case .unsupportedLanguage, .layoutNotSupported, .basisStateNotSupported:
                return PastedLabelText.declineMessage(classification.copy)
            case .multiplePanels:
                return "This photo has more than one nutrition table (for example two flavours). Crop to the one you ate, then read again."
            default:
                return "The app could not read the table in this photo. Crop to one nutrition table, then try again."
            }
        }
        return (messages.isEmpty ? [failedUnusable] : messages).filter { seen.insert($0).inserted }
    }

    // MARK: 7.3 Confirm

    public static let photoSectionTitle = "Label photo"
    public static let valuesSectionTitle = "Nutrition from the photo"
    public static func sourceLine(basis: String) -> String {
        "From a label photo, read by AI · \(basis) · Traditional Chinese, Taiwan layout"
    }
    public static let honestyNote = "Read by AI from your photo. AI can misread numbers, so check each value against the photo before you log."
    public static func attentionSummary(_ count: Int) -> String {
        count == 1 ? "1 value needs your check before you can log." : "\(count) values need your check before you can log."
    }
    public static let attentionNone = "Every value was found on the photo. Check them before you log."
    public static let found = "Found on photo"
    public static let notFound = "Not found on photo. Check it."
    public static let checkFailed = "Doesn't add up with the other values. Check it."
    public static let checkedByYou = "Checked by you"
    public static let correctedByYou = "Corrected by you"
    public static let enteredByYou = "Entered by you"
    public static let leftUnknown = "Left unknown"
    public static let matchesPhoto = "Matches the photo"
    public static let correct = "Correct"
    public static let leaveUnknown = "Leave unknown"
    public static let checkedThem = "I've checked them"
    public static let energyCheck = "Energy does not match protein, fat and carbohydrate. Check these values against the photo."
    public static let servingCheck = "The per serving and per 100 g values do not agree with the serving size. Check them against the photo."
    /// Decision (17.19): the kJ to kcal and sub-row checks, which 7.3 does not word.
    public static let ratioCheck = "The kJ and kcal values do not agree. Check them against the photo."
    public static let subrowCheck = "A sub-row is larger than its main row. Check these values against the photo."
    /// Decision (17.19): a value in a row the gate flagged (G3 or G4), which 7.3 does not word.
    public static let flaggedWhenRead = "Flagged when read. Check it."
    public static let invalidValue = "Enter a number in the unit shown, for example 5.4."
    public static let notCorrectable = "This value can't be corrected here. Use Matches the photo or Leave unknown."
    public static let correctionRefused = "That change could not be applied. Nothing was saved."
    public static let correctTitle = "Correct value"
    public static let correctSave = "Use this value"
    public static func showOnPhoto(row: String, column: String) -> String { "Show \(row), \(column) on the photo" }
    public static func showingOnPhoto(row: String, column: String) -> String { "Showing \(row), \(column), on the photo" }
    public static func caption(row: String, column: String) -> String { "\(row), \(column)" }
    public static let notFoundOnPhoto = "This value was not found on the photo. Check the table yourself."
    public static func pinnedBar(_ count: Int) -> String {
        count == 1 ? "Check the 1 highlighted value against the photo." : "Check the \(count) highlighted values against the photo."
    }
    public static let sourceFooter = "To read a different photo, use Retake or adjust photo. To change a value, correct it in Nutrition from the photo."
    public static let retakeOrAdjust = "Retake or adjust photo"
    /// Display names for the stored model and provider of an admitted route; anything else is
    /// shown exactly as stored.
    public static let modelNames = ["google/gemini-4-argon": modelName]
    public static let providerNames = ["Google Vertex": providerName, "google-vertex": providerName]

    public static func savedSource(model: String, provider: String, date: String) -> String {
        "Read by \(modelNames[model] ?? model) on \(providerNames[provider] ?? provider) through OpenRouter, \(date); checked by you"
    }
    public static let fit = "Fit"
    public static let fullScreen = "Full screen"
    public static let showPhoto = "Show photo"
    public static let done = "Done"
    public static let paneAccessibilityLabel = "Label photo"
    public static let paneAccessibilityHint = "Swipe up or down to zoom."
    public static let photoNotOnDevice = "The photo is not on this device."
    /// The saved entry's Source row for a label photo.
    public static func savedSourceRow(basis: String) -> String {
        "From a label photo · \(basis) · Traditional Chinese, Taiwan layout"
    }
    public static let rereadConfirmation = "Reading again replaces your corrections"

    /// The check group's sentence.
    public static func check(_ name: String) -> String {
        switch name {
        case "energy": energyCheck
        case "serving_scaling", "serving_consistency": servingCheck
        case "kj_kcal_ratio": ratioCheck
        default: subrowCheck
        }
    }

    /// "per 100 g", "per serving" for a basis code.
    public static func column(_ basis: String) -> String {
        switch basis {
        case "per_serving": "per serving"
        case "per_100g": "per 100 g"
        case "per_100ml": "per 100 ml"
        default: "reference intake"
        }
    }
}

/// A logged label photo on its saved entry (7.3, "Saved entry and Developer tools").
public enum LabelPhotoSavedEntryText {
    public static let sectionTitle = "From a label photo"

    /// "Read by Gemini 4 Argon on Google Vertex through OpenRouter, 26 Oct 2026; checked by you".
    public static func sourceLine(_ detail: SavedFoodEntryDetail, locale: Locale = Locale(identifier: "en_GB")) -> String? {
        guard let manifest = detail.labelPhoto else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        let date = Date(timeIntervalSince1970: TimeInterval(manifest.response.completedAt) / 1_000)
        return LabelPhotoText.savedSource(model: manifest.response.model, provider: manifest.response.provider,
                                          date: formatter.string(from: date))
    }

    /// One line per value the user resolved: "Protein, per 100 g: Checked by you".
    public static func stateLines(_ detail: SavedFoodEntryDetail) -> [String] {
        guard let manifest = detail.labelPhoto else { return [] }
        let columns = Dictionary(manifest.candidate.headers.map { ($0.headerID, $0.basis) }, uniquingKeysWith: { first, _ in first })
        let titles = Dictionary(manifest.candidate.cells.map { cell in
            (LabelPhotoManifest.cellItem(rowID: cell.rowID, headerID: cell.headerID),
             LabelPhotoSourceModel.title(cell.nutrient, printed: cell.printedLabel) + ", " + LabelPhotoText.column(columns[cell.headerID] ?? cell.basis))
        }, uniquingKeysWith: { first, _ in first })
        return manifest.attention.map { record in
            let state: String = switch record.resolution {
            case .checked: LabelPhotoText.checkedByYou
            case .corrected: LabelPhotoText.correctedByYou
            case .entered: LabelPhotoText.enteredByYou
            case .leftUnknown: LabelPhotoText.leftUnknown
            }
            let title = titles[record.item] ?? (record.item == "serving_size" ? "Serving size" : "Servings per pack")
            return title + ": " + state
        }
    }
}
